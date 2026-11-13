#Requires -Version 5.1
# A7-02/A7-04: actual non-oracle production C candidates are physically re-read
# by A in a new candidate_validation phase. Only generated, nonwritable bytes.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-Chappy3DDamagedFixture.ps1')
. (Join-Path $root 'modules\carving\tests\R5VariableZipPairRegression.ps1')
Import-Module (Join-Path $root 'core\Chappy.FragmentPhysicalReceipts.psm1') -Force
function Assert-A7Receipt([bool]$Okay,[string]$Reason){
 if(-not $Okay){throw ('A7_FRAGMENT_SOURCE_RECEIPTS_FAIL: '+$Reason)}
}
if(-not ('A7ReceiptEarlyZeroMemoryV1' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class A7ReceiptEarlyZeroMemoryV1:MemoryStream {
 bool done=false;
 public A7ReceiptEarlyZeroMemoryV1(byte[] b):base(b,false){}
 public override int Read(byte[] b,int o,int n){
  if(done)return 0;
  done=true;
  return base.Read(b,o,Math.Min(n,17));
 }
}
public sealed class A7ReceiptOneByteMemoryV1:MemoryStream {
 public A7ReceiptOneByteMemoryV1(byte[] b):base(b,false){}
 public override int Read(byte[] b,int o,int n){
  return base.Read(b,o,Math.Min(n,1));
 }
}
'@
}
$clean=New-ChappyA3DCleanFixture -Seed 202611
$truth=@($clean.oracle|Where-Object {$_.shortName -ceq 'MODEL   3MF'})[0]
[byte[]]$original=[byte[]]::new([int]$truth.lengthBytes)
$offset=0
foreach($span in $truth.extents){
 [Array]::Copy($clean.image,[int]$span.offsetBytes,$original,$offset,[int]$span.lengthBytes)
 $offset+=[int]$span.lengthBytes
}
Assert-A7Receipt ($offset -eq $original.Length -and (Get-A3DSha256 $original) -ceq $truth.sha256) 'independent_generated_original_SHA'
$validated=0
foreach($kind in @('M01_control','alternate_zip_metadata','missing_tail')){
 $fx=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind $kind
 [byte[]]$image=$fx.image
 $before=Get-A3DSha256 $image
 $raw=[IO.MemoryStream]::new($image,$false)
 try{
  $disabled=Invoke-ChappyA7FragmentPhysicalReceipts -Source $raw
  Assert-A7Receipt ($disabled.status -ceq 'disabled' -and
   $disabled.metrics.actualReturnedBytes -eq 0 -and
   $raw.Position -eq 0 -and @($disabled.candidateDefinitions).Count -eq 0) 'disabled_reads_nothing'
  $report=Invoke-ChappyA7FragmentPhysicalReceipts -Source $raw -EnableA7FragmentReceipts
  $m=$report.metrics
  Assert-A7Receipt ($report.schemaVersion -ceq 'a7_fragment_physical_receipts_v1' -and
   $report.status -ceq 'partial' -and
   $report.originalIdentity -ceq 'unknown' -and
   -not $report.originalShaVerified -and -not $report.canSelectOriginal -and
   -not $report.canExport -and -not $report.canRepair -and
   $report.sourceAuthority -ceq 'A_in_process_successful_return_not_real_media_authentication') 'limited_source_read_not_original_integrity'
  Assert-A7Receipt ($m.actualReturnedBytes -gt 0 -and $m.actualReturnedBytes -le 120000 -and
   $m.scanReturnedBytes -ge 65536 -and
   $m.actualReturnedBytes -eq ($m.scanReturnedBytes+$m.validationReturnedBytes) -and
   $m.uniqueReturnedBytes -gt 0 -and
   $m.repeatedReturnedBytes -eq $m.actualReturnedBytes-$m.uniqueReturnedBytes -and
   $m.physicalReadCalls -ge $m.sourceReadEvents -and $m.physicalReadCalls -le 512) 'bounded_A_outer_source_actual_successful_Read_accounting'
  if($kind -eq 'missing_tail'){
   Assert-A7Receipt ($report.sourceObservedCandidateCount -eq 0 -and
    @($report.candidateDefinitions).Count -eq 0 -and
    $report.cDecision -ceq 'unknown') 'missing_tail_does_not_mint_candidate'
  }else{
   $want=$(if($kind -eq 'alternate_zip_metadata'){2}else{1})
   Assert-A7Receipt ($report.cStatus -ceq 'ok' -and
    $report.candidateCount -eq $want -and
    $report.sourceObservedCandidateCount -eq $want -and
    $report.incompleteCandidateCount -eq 0 -and
    $m.validationReturnedBytes -gt 0 -and
    $report.sourceReadScope -ceq 'A_candidate_specific_returned_bytes_only') ('candidate_specific_A_rereads_'+$kind)
   $exact=0;$wrong=0
   foreach($candidate in @($report.candidateDefinitions)){
    Assert-A7Receipt ($candidate.readEvidenceStatus -ceq 'source_observed' -and
     $candidate.validationScope -ceq 'A_in_process_candidate_specific_successful_Read' -and
     $candidate.readReturnedBytes -eq $candidate.expectedExtentBytes -and
     $candidate.candidateValidationReadEvents -gt 0 -and
     $candidate.originalIdentity -ceq 'unknown' -and
     -not $candidate.originalShaVerified -and
     @($candidate.orderedExtents).Count -eq 2) 'A_actual_physical_two_extent_read_events'
    [byte[]]$joined=[byte[]]::new([int]$candidate.expectedExtentBytes)
    $at=0
    foreach($e in $candidate.orderedExtents){
     [Array]::Copy($image,[int]$e.offsetBytes,$joined,$at,[int]$e.lengthBytes)
     $at+=[int]$e.lengthBytes
    }
    if((Get-A3DSha256 $joined) -ceq $truth.sha256){$exact++}else{$wrong++}
   }
   if($kind -eq 'alternate_zip_metadata'){
    Assert-A7Receipt ($exact -eq 1 -and $wrong -eq 1 -and
     $report.cDecision -ceq 'ambiguous') 'CRC_consistent_wrong_original_SHA_stays_ambiguous'
   }else{
    Assert-A7Receipt ($exact -eq 1 -and $wrong -eq 0) 'synthetic_original_sha_only_external_test_oracle'
   }
   $validated+=$want
  }
  Assert-A7Receipt ((Get-A3DSha256 $image) -ceq $before -and -not $raw.CanWrite) 'source_SHA_unchanged'
  Write-Host ('A7 candidate receipt synthetic={0} observed={1} readB={2} rereadB={3} uniqueB={4} calls={5} original=UNKNOWN' -f
   $kind,$report.sourceObservedCandidateCount,$m.actualReturnedBytes,$m.validationReturnedBytes,$m.uniqueReturnedBytes,$m.physicalReadCalls)
 }finally{$raw.Dispose()}
}
$fx=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind 'M01_control'
[byte[]]$bytes=$fx.image
$sourceSha=Get-A3DSha256 $bytes
$writable=[IO.MemoryStream]::new($bytes,$true)
try{
 $refused=Invoke-ChappyA7FragmentPhysicalReceipts -Source $writable -EnableA7FragmentReceipts
 Assert-A7Receipt ($refused.sourceReadScope -ceq 'none' -and
  $refused.metrics.actualReturnedBytes -eq 0 -and
  $refused.sourceObservedCandidateCount -eq 0) 'writable_refused_no_read'
}finally{$writable.Dispose()}
$early=[A7ReceiptEarlyZeroMemoryV1]::new($bytes)
try{
 $unknown=Invoke-ChappyA7FragmentPhysicalReceipts -Source $early -EnableA7FragmentReceipts
 Assert-A7Receipt ($unknown.sourceObservedCandidateCount -eq 0 -and
  $unknown.metrics.actualReturnedBytes -le 17 -and
  $unknown.originalIdentity -ceq 'unknown') 'true_17B_then_zero_EOF_never_claims_candidate'
}finally{$early.Dispose()}
$quota=[IO.MemoryStream]::new($bytes,$false)
try{
 $unknown=Invoke-ChappyA7FragmentPhysicalReceipts -Source $quota -EnableA7FragmentReceipts -MaxPhysicalReadBytes 1024
 Assert-A7Receipt ($unknown.sourceObservedCandidateCount -eq 0 -and
  $unknown.metrics.actualReturnedBytes -le 1024 -and
  $unknown.sourceReadScope -ceq 'unattributed') 'A_global_returned_byte_quota_refuses_C_scan'
}finally{$quota.Dispose()}
$oneByte=[A7ReceiptOneByteMemoryV1]::new($bytes)
try{
 $unknown=Invoke-ChappyA7FragmentPhysicalReceipts -Source $oneByte -EnableA7FragmentReceipts -MaxReadCalls 8
 Assert-A7Receipt ($unknown.sourceObservedCandidateCount -eq 0 -and
  $unknown.metrics.physicalReadCalls -le 8 -and
  $unknown.originalIdentity -ceq 'unknown') 'A_global_call_cap_refuses_partial_scan'
}finally{$oneByte.Dispose()}
Assert-A7Receipt ($validated -eq 3 -and (Get-A3DSha256 $bytes) -ceq $sourceSha) 'all_positive_structural_candidates_source_observed_no_original_integrity'
Write-Host 'PASS: A7 real C 2-piece candidates A physically revalidated per ordered extent, 3 structural candidates source-observed, wrong-original remains ambiguous, missing tail/true EOF/budgets unknown, no actual user file.'