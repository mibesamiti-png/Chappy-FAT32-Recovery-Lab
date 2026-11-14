#Requires -Version 5.1
# R8 P3 artificial standard FAT32 source -> real A R7 evidence -> separate
# measured A candidate reread -> disposable, CreateNew/no-overwrite 3MF output.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $root 'core\Chappy.R8SourceBoundSyntheticBridge.psm1') -Force
function Assert-P3([bool]$Good,[string]$Reason) {
 if(-not $Good){throw ('A_R8_P3_FAIL: '+$Reason)}
}
if(-not ('ChappyR8P3ShortZeroMemory' -as [type])){
 Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class ChappyR8P3ShortZeroMemory:MemoryStream {
 bool first=false;
 public ChappyR8P3ShortZeroMemory(byte[] data):base(data,false){}
 public override int Read(byte[] b,int o,int count) {
  if(first)return 0;
  first=true;return base.Read(b,o,Math.Min(17,count));
 }
}
public sealed class ChappyR8P3SecondSessionShortMemory:MemoryStream {
 readonly long stopAfterCalls;
 long calls=0;bool fault=false;
 public ChappyR8P3SecondSessionShortMemory(byte[] data,long after):base(data,false){stopAfterCalls=after;}
 public bool Triggered {get{return fault;}}
 public override int Read(byte[] b,int o,int count){
  calls++;
  if(fault)return 0;
  if(calls>stopAfterCalls){fault=true;return base.Read(b,o,Math.Min(3,count));}
  return base.Read(b,o,count);
 }
}
'@
}
$processed=0
foreach($spc in @(1,2)){
 $fixture=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
 [byte[]]$image=$fixture.image
 $imageSha=Get-A3DSha256 $image
 $truth=@($fixture.oracle|Where-Object {$_.shortName -ceq 'MODEL   3MF'})
 Assert-P3 ($truth.Count -eq 1 -and $truth[0].lengthBytes -eq 887) ('SPC'+$spc+':artificial_scorer_only_original')
 $source=[IO.MemoryStream]::new($image,$false)
 $dir=Join-Path ([IO.Path]::GetTempPath()) ('ChappyR8Synthetic-'+[guid]::NewGuid().ToString('N'))
 [void][IO.Directory]::CreateDirectory($dir)
 try{
  $common=@{
   Source=$source;OutputRoot=$dir;SyntheticFixtureTag='A3D-standard-202611'
  }
  $off=Export-ChappyR8SourceBoundSyntheticCandidateV1 @common
  Assert-P3 ($off.status -ceq 'disabled' -and
   $off.r7SourceSessionCount -eq 0 -and $off.metrics.r7ActualReturnedBytes -eq 0L -and
   $off.metrics.r8CandidateActualReturnedBytes -eq 0L -and
   @([IO.Directory]::GetFiles($dir)).Count -eq 0 -and $source.Position -eq 0L) ('SPC'+$spc+':default_off_no_IO')
  $yes=Export-ChappyR8SourceBoundSyntheticCandidateV1 @common -EnableSyntheticR7SourceBindingAndExport
  Assert-P3 ($yes.schemaVersion -ceq 'r8_synthetic_r7_source_binding_v1' -and
   $yes.status -ceq 'complete' -and
   $yes.decision -ceq 'synthetic_source_bound_output_verified_original_UNKNOWN' -and
   $yes.r7SourceSessionCount -eq 1 -and
   $yes.r8CandidateRereadSessionCount -eq 1 -and
   $yes.sourcePhaseAccounting -ceq 'two_separate_A_source_sessions_do_not_pool_unique_bytes' -and
   $yes.candidateCount -eq 1 -and
   $yes.r7CandidateId -match '^3mf:[0-9]+\+[0-9]+,[0-9]+\+[0-9]+$' -and
   $yes.outputVerified -and
   $yes.outputBytes -eq 887L -and
   $yes.sourceAuthenticity -ceq 'not_real_media_authenticated' -and
   -not $yes.canExportOriginal -and -not $yes.originalShaVerified -and
   -not $yes.canSelectOriginal -and -not $yes.canRepairOriginal) ('SPC'+$spc+':actual_R7_then_separate_A_reread_then_output_original_unknown')
  Assert-P3 ($yes.metrics.r7ActualReturnedBytes -gt 100000L -and
   $yes.metrics.r7ActualReturnedBytes -le 120000L -and
   $yes.metrics.r7PhysicalReadCalls -le 512 -and
   $yes.metrics.r8CandidateActualReturnedBytes -eq 887L -and
   $yes.metrics.r8CandidateUniqueReturnedBytes -eq 887L -and
   $yes.metrics.r8CandidateRepeatedReturnedBytes -eq 0L -and
   $yes.metrics.r8CandidatePhysicalReadCalls -ge 2 -and
   $yes.metrics.projectedCandidateBytes -eq 887L) ('SPC'+$spc+':two_independent_actual_source_counters_not_double_counted')
  Assert-P3 ([IO.File]::Exists($yes.outputPath) -and
   [IO.Path]::GetDirectoryName($yes.outputPath) -ceq $dir -and
   $yes.outputName -match '^candidate-[0-9A-F]{32}\.3mf$' -and
   $yes.outputSha256 -ceq [string]$truth[0].sha256 -and
   ((Get-A3DSha256 ([IO.File]::ReadAllBytes($yes.outputPath))) -ceq [string]$truth[0].sha256)) ('SPC'+$spc+':external_test_only_original_SHA_match_and_new_disposable_file')
  Assert-P3 ((Get-A3DSha256 $image) -ceq $imageSha -and
   -not $source.CanWrite) ('SPC'+$spc+':unchanged_generated_source')
  $again=Export-ChappyR8SourceBoundSyntheticCandidateV1 @common -EnableSyntheticR7SourceBindingAndExport
  Assert-P3 ($again.status -ceq 'partial' -and
   $again.decision -ceq 'source_binding_incomplete_UNKNOWN' -and
   -not $again.outputVerified -and
   @([IO.Directory]::GetFiles($dir)).Count -eq 1 -and
   ((Get-A3DSha256 ([IO.File]::ReadAllBytes($yes.outputPath))) -ceq $yes.outputSha256)) ('SPC'+$spc+':CREATE_NEW_collision_does_not_modify_existing_output')
  $processed++
  Write-Host ('R8 P3 SYNTHETIC: SPC{0} R7Returned={1}B/{2}calls R8Candidate={3}B/{4}calls output={5}B independentOracleSHA=test_only original=UNKNOWN' -f $spc,$yes.metrics.r7ActualReturnedBytes,$yes.metrics.r7PhysicalReadCalls,$yes.metrics.r8CandidateActualReturnedBytes,$yes.metrics.r8CandidatePhysicalReadCalls,$yes.outputBytes)
 }finally{
  $source.Dispose()
  if([IO.Directory]::Exists($dir)){[IO.Directory]::Delete($dir,$true)}
 }
}
Assert-P3 ($processed -eq 2) 'both_standard_SPC_sources'
$bad=[byte[]](New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster 1 -Fragment3Mf).image
$badSha=Get-A3DSha256 $bad
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('ChappyR8Synthetic-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tmp)
try{
 $short=[ChappyR8P3ShortZeroMemory]::new($bad)
 try{
  $r=Export-ChappyR8SourceBoundSyntheticCandidateV1 -Source $short -OutputRoot $tmp -SyntheticFixtureTag 'A3D-standard-202611' -EnableSyntheticR7SourceBindingAndExport
  Assert-P3 ($r.status -ceq 'partial' -and $r.candidateCount -eq 0 -and
   $r.metrics.r7ActualReturnedBytes -eq 17L -and
   $r.r8CandidateRereadSessionCount -eq 0 -and
   @([IO.Directory]::GetFiles($tmp)).Count -eq 0) 'true_17B_then_zero_never_exports'
 }finally{$short.Dispose()}
 $quota=[IO.MemoryStream]::new($bad,$false)
 try{
  $r=Export-ChappyR8SourceBoundSyntheticCandidateV1 -Source $quota -OutputRoot $tmp -SyntheticFixtureTag 'A3D-standard-202611' -EnableSyntheticR7SourceBindingAndExport -MaxR7ReturnedBytes 1024
  Assert-P3 ($r.status -eq 'partial' -and $r.metrics.r7ActualReturnedBytes -le 1024L -and
   $r.r8CandidateRereadSessionCount -eq 0 -and
   @([IO.Directory]::GetFiles($tmp)).Count -eq 0) 'A_R7_global_quota_unknown'
 }finally{$quota.Dispose()}
 $w=[IO.MemoryStream]::new($bad)
 try{
  $r=Export-ChappyR8SourceBoundSyntheticCandidateV1 -Source $w -OutputRoot $tmp -SyntheticFixtureTag 'A3D-standard-202611' -EnableSyntheticR7SourceBindingAndExport
  Assert-P3 ($r.status -eq 'rejected' -and $r.metrics.r7ActualReturnedBytes -eq 0L -and
   @([IO.Directory]::GetFiles($tmp)).Count -eq 0) 'writable_memory_disallowed_before_read'
 }finally{$w.Dispose()}
 $fault=[ChappyR8P3SecondSessionShortMemory]::new($bad,93)
 try{
  $r=Export-ChappyR8SourceBoundSyntheticCandidateV1 -Source $fault -OutputRoot $tmp -SyntheticFixtureTag 'A3D-standard-202611' -EnableSyntheticR7SourceBindingAndExport
  Assert-P3 ($fault.Triggered -and
   $r.status -ceq 'partial' -and
   $r.r8CandidateRereadSessionCount -eq 1 -and
   -not $r.outputVerified -and
   @([IO.Directory]::GetFiles($tmp)).Count -eq 0) 'late_source_reread_3B_then_zero_rejects_candidate'
 }finally{$fault.Dispose()}
 Assert-P3 ((Get-A3DSha256 $bad) -ceq $badSha) 'all_artificial_negative_source_bytes_unchanged'
}finally{
 if([IO.Directory]::Exists($tmp)){[IO.Directory]::Delete($tmp,$true)}
}
Write-Host 'PASS: R8-P3 actual R7 source evidence + independently metered R8 candidate reread + safe disposable CreateNew output; no genuine file identity.'
