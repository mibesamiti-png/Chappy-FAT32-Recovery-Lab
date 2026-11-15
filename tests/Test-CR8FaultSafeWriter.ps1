#Requires -Version 5.1
# Team C ACTIVE #199 independent synthetic fault matrix.
# NOT wired into A's shared runner: A alone adds this standalone test there.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Assert-CR8Fault([bool]$Okay,[string]$Label){
 if(-not $Okay){throw ('C_R8_P5_FAIL: '+$Label)}
}
function Get-CR8IndependentSha([byte[]]$Bytes){
 $h=[Security.Cryptography.SHA256]::Create()
 try{[BitConverter]::ToString($h.ComputeHash($Bytes)).Replace('-','')}
 finally{$h.Dispose()}
}
$repo=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'core\Chappy.R8FaultSafeWriter.psm1') -Force
. (Join-Path $repo 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
$fixture=New-ChappyA3DCleanFixture -Seed 202611
$originalSha=Get-CR8IndependentSha $fixture.image
# Fixture oracle is used exclusively by test to assemble artificial candidate;
# production writer receives no oracle offsets, original SHA or FAT metadata.
$truth=@($fixture.oracle | Where-Object {$_.shortName -ceq 'MODEL   3MF'})[0]
Assert-CR8Fault ($null -ne $truth -and @($truth.extents).Count -eq 2) 'synthetic_3mf_truth_available_to_test_only'
$n=0
foreach($p in @($truth.extents)){$n+=[int]$p.lengthBytes}
[byte[]]$candidate=[byte[]]::new($n)
$cursor=0
foreach($p in @($truth.extents)){
 [Array]::Copy($fixture.image,[int]$p.offsetBytes,$candidate,$cursor,[int]$p.lengthBytes)
 $cursor+=[int]$p.lengthBytes
}
$sourceCandidateSha=Get-CR8IndependentSha $candidate
Assert-CR8Fault ($n -ge 256 -and $n -le 4096 -and
 $candidate[0] -eq 0x50 -and $candidate[1] -eq 0x4b -and
 $sourceCandidateSha -ceq $truth.sha256 -and $cursor -eq $n) 'bounded_generated_ZIP_3MF'
$root=Join-Path ([IO.Path]::GetTempPath()) ('ChappyR8Synthetic-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$rootCreated=$true;$total=0;$faultCases=0;$ownedClean=0;$collision=0
$sentinel=Join-Path $root 'sentinel.keep'
[byte[]]$sentinelBytes=[Text.Encoding]::ASCII.GetBytes('test-owned-sentinel-must-remain-unchanged')
[IO.File]::WriteAllBytes($sentinel,$sentinelBytes)
$sentinelSha=Get-CR8IndependentSha $sentinelBytes
$successFile=$null
try{
 $args=@{SyntheticCandidateBytes=$candidate;OutputRoot=$root;SyntheticFixtureTag='A3D-clean-202611'}
 $disabled=Invoke-ChappyR8SyntheticFaultWriterV1 @args
 Assert-CR8Fault ($disabled.status -eq 'disabled' -and
   $disabled.schemaVersion -eq 'c_r8_synthetic_fault_writer_v1' -and
   $disabled.metrics.successfulWriteBytes -eq 0 -and
   $disabled.metrics.writeCalls -eq 0 -and
   @([IO.Directory]::GetFiles($root)).Count -eq 1) 'default_OFF_zero_new_file'
 $total++
 # Successful CreateNew -> same FileStream readback -> independent test SHA.
 $success=Invoke-ChappyR8SyntheticFaultWriterV1 @args -EnableSyntheticFaultWriter
 Assert-CR8Fault ($success.status -eq 'complete' -and
   $success.decision -eq 'synthetic_candidate_readback_verified_original_UNKNOWN' -and
   $success.outputVerified -and $success.outputBytes -eq $n -and
   $success.outputSha256 -ceq $sourceCandidateSha -and
   $success.sourceUnchanged -and $success.originalIdentity -eq 'unknown' -and
   $success.sourceAuthenticity -eq 'not_proven' -and
   -not $success.originalShaVerified -and -not $success.canExportOriginal -and
   -not $success.canRepairOriginal -and
   $success.metrics.successfulWriteBytes -eq $n -and
   $success.metrics.readbackReturnedBytes -eq $n -and
   $success.metrics.cleanupStatus -eq 'not_needed' -and
   $success.outputName -match '^candidate-[0-9A-F]{32}\.3mf$') 'success_readback_digest_and_original_UNKNOWN'
 $successFile=Join-Path $root $success.outputName
 Assert-CR8Fault ([IO.File]::Exists($successFile) -and
   (Get-CR8IndependentSha ([IO.File]::ReadAllBytes($successFile))) -ceq $sourceCandidateSha) 'independent_real_test_output_sha'
 $total++
 # Same generated candidate name: reject atomically without overwriting or
 # deleting somebody else's pre-existing completed output.
 $before=[IO.File]::ReadAllBytes($successFile)
 $same=Invoke-ChappyR8SyntheticFaultWriterV1 @args -EnableSyntheticFaultWriter
 Assert-CR8Fault ($same.status -eq 'partial' -and $same.outputVerified -eq $false -and
   $same.metrics.createdThisCall -eq $false -and
   $same.metrics.cleanupStatus -eq 'not_needed' -and
   $same.metrics.successfulWriteBytes -eq 0 -and
   (Get-CR8IndependentSha ([IO.File]::ReadAllBytes($successFile))) -ceq (Get-CR8IndependentSha $before)) 'collision_existing_not_overwritten_or_deleted'
 $collision++;$total++
 # This success artifact was created exclusively by THIS test and independently
 # SHA-verified above. Dispose it in test harness before injecting new faults.
 [IO.File]::Delete($successFile)
 Assert-CR8Fault (-not [IO.File]::Exists($successFile)) 'test_owned_success_cleaned'
 $successFile=$null
 # The simulated faults NEVER fill a disk, change permissions or access source.
 $cases=@(
  @{mode='BeforeWrite';written=0;read=0;created=$true},
  @{mode='AfterPartialWrite';written=127;read=0;created=$true},
  @{mode='AfterFullWrite';written=$n;read=0;created=$true},
  @{mode='BeforeReadback';written=$n;read=0;created=$true},
  @{mode='DuringReadback';written=$n;read=127;created=$true},
  @{mode='DigestMismatch';written=$n;read=$n;created=$true},
  @{mode='DiskFullBefore';written=0;read=0;created=$true},
  @{mode='DiskFullPartial';written=127;read=0;created=$true},
  @{mode='PermissionDeniedBefore';written=0;read=0;created=$false},
  @{mode='PermissionDeniedAfterCreate';written=0;read=0;created=$true}
 )
 foreach($test in $cases){
  $r=Invoke-ChappyR8SyntheticFaultWriterV1 @args -EnableSyntheticFaultWriter -FaultMode $test.mode
  Assert-CR8Fault ($r.status -eq 'partial' -and $r.decision -eq 'synthetic_write_or_readback_failed_UNKNOWN' -and
   -not $r.outputVerified -and $null -eq $r.outputName -and
   $null -eq $r.outputSha256 -and $r.outputBytes -eq 0 -and
   $r.originalIdentity -eq 'unknown' -and
   $r.sourceUnchanged -and
   -not $r.originalShaVerified -and -not $r.canExportOriginal -and
   $r.metrics.successfulWriteBytes -eq $test.written -and
   $r.metrics.readbackReturnedBytes -eq $test.read -and
   $r.metrics.createdThisCall -eq $test.created) ($test.mode+':failure_report_sanitized')
  if($test.created){
   Assert-CR8Fault ($r.metrics.cleanupStatus -eq 'owned_handle_delete_marked' -and
    $r.metrics.ownedHandleMatchedForCleanup) ($test.mode+':owned_only_handle_disposition')
   $ownedClean++
  }else{
   Assert-CR8Fault ($r.metrics.cleanupStatus -eq 'not_needed' -and
    -not $r.metrics.ownedHandleMatchedForCleanup) ($test.mode+':no_created_object_no_cleanup')
  }
  Assert-CR8Fault (@([IO.Directory]::GetFiles($root)).Count -eq 1 -and
   (Get-CR8IndependentSha ([IO.File]::ReadAllBytes($sentinel))) -ceq $sentinelSha -and
   (Get-CR8IndependentSha $candidate) -ceq $sourceCandidateSha -and
   (Get-CR8IndependentSha $fixture.image) -ceq $originalSha) ($test.mode+':no_leftover_and_source_and_sentinel_unchanged')
  $faultCases++;$total++
  Write-Host ('C R8-P5 FAULT mode={0} created={1} completed_write_calls={2} confirmed_written_B={3} readback_B={4} owned_handle_cleanup={5} sentinel_unchanged=1' -f
    $test.mode,$r.metrics.createdThisCall,$r.metrics.writeCalls,
    $r.metrics.successfulWriteBytes,$r.metrics.readbackReturnedBytes,$r.metrics.cleanupStatus)
 }
 # No destination / rejected quota / wrong synthetic tag => no source copy
 $rejected=Invoke-ChappyR8SyntheticFaultWriterV1 @args -EnableSyntheticFaultWriter -MaxOutputBytes 100
 Assert-CR8Fault ($rejected.status -eq 'rejected' -and
   $rejected.metrics.createdThisCall -eq $false -and
   @([IO.Directory]::GetFiles($root)).Count -eq 1) 'quota_preflight_no_create'
 $total++
 $notOurRoot=Invoke-ChappyR8SyntheticFaultWriterV1 -SyntheticCandidateBytes $candidate -OutputRoot ([IO.Path]::GetTempPath()) -SyntheticFixtureTag 'A3D-clean-202611' -EnableSyntheticFaultWriter
 Assert-CR8Fault ($notOurRoot.status -eq 'rejected' -and
   $notOurRoot.metrics.createdThisCall -eq $false) 'direct_OS_temp_not_disposable_root'
 $total++
 $invalid=Invoke-ChappyR8SyntheticFaultWriterV1 @args -SyntheticFixtureTag 'real-source-not-authorized' -EnableSyntheticFaultWriter
 Assert-CR8Fault ($invalid.status -eq 'rejected' -and
   $invalid.metrics.createdThisCall -eq $false) 'not_an_authorized_generated_fixture_label'
 $total++
 Assert-CR8Fault ((Get-CR8IndependentSha $candidate) -ceq $sourceCandidateSha -and
  (Get-CR8IndependentSha $fixture.image) -ceq $originalSha -and
  (Get-CR8IndependentSha ([IO.File]::ReadAllBytes($sentinel))) -ceq $sentinelSha -and
  @([IO.Directory]::GetFiles($root)).Count -eq 1) 'final_sha_and_sentinel_invariant'
 Write-Host ('C R8-P5 SUMMARY assertions_groups={0} fault_cases={1} owned_file_cleanup={2} preowned_collision_preserved={3} synthetic_candidate_B={4} original_identity_claims=0 real_media_access=0' -f
    $total,$faultCases,$ownedClean,$collision,$n)
 Write-Host 'PASS: C R8-P5 synthetic-only default-off CreateNew fault matrix, same-handle readback and owned-identity cleanup'
}finally{
 # Remove only the EXACT test-created sentinel; never recursively delete a
 # directory or stray file left because ownership could not be established.
 if($null -ne $successFile -and [IO.File]::Exists($successFile) -and
  (Get-CR8IndependentSha ([IO.File]::ReadAllBytes($successFile))) -ceq $sourceCandidateSha){
  [IO.File]::Delete($successFile)
 }
 if([IO.File]::Exists($sentinel) -and
  (Get-CR8IndependentSha ([IO.File]::ReadAllBytes($sentinel))) -ceq $sentinelSha){
  [IO.File]::Delete($sentinel)
 }
 if($rootCreated -and [IO.Directory]::Exists($root) -and
  @([IO.Directory]::GetFileSystemEntries($root)).Count -eq 0){
  [IO.Directory]::Delete($root,$false)
 }
}
