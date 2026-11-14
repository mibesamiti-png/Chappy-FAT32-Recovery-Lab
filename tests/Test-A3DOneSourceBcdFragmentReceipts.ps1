#Requires -Version 5.1
# Team A R7: one actual Stream.Read meter sees B + C + D + two-piece C scout
# and A candidate-specific re-reads. No real media; artificial nonwritable only.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $root 'core\Chappy.LiveBcdEvidence.psm1') -Force
function Assert-A7R12([bool]$Good,[string]$Why) {
 if(-not $Good){throw ('A7_R12_ONE_SOURCE_FAIL: '+$Why)}
}
if(-not ('A7R12LateFatZeroMemory' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class A7R12LateFatZeroMemory:MemoryStream {
 readonly long fatOffset; bool shortSent=false; long calls=0,returned=0;
 public A7R12LateFatZeroMemory(byte[] bytes,long at):base(bytes,false){fatOffset=at;}
 public bool Triggered {get{return shortSent;}}
 public long Calls {get{return calls;}}
 public long Returned {get{return returned;}}
 public override int Read(byte[] b,int off,int count){
  calls++;
  if(shortSent)return 0;
  int got=Position==fatOffset && calls>8 ?
    base.Read(b,off,Math.Min(3,count)) : base.Read(b,off,count);
  if(Position==fatOffset+3 && got==3)shortSent=true;
  returned+=got;return got;
 }
}
'@
}
$complete=0
$wholeActual=0L
foreach($spc in @(1,2)){
 $fixture=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
 [byte[]]$image=$fixture.image
 $sha=Get-A3DSha256 $image
 $memory=[IO.MemoryStream]::new($image,$false)
 try{
  $disabled=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $memory -BindAObservedCFragmentReceipts
  Assert-A7R12 ($disabled.status -ceq 'disabled' -and
   $disabled.cFragmentPhysicalReceipt.decision -ceq 'not_requested' -and
   $disabled.metrics.actualReturnedBytes -eq 0L -and
   $memory.Position -eq 0L) ('SPC'+$spc+': disabled no source reads')
  $missing=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $memory -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedCFragmentReceipts
  Assert-A7R12 ($missing.status -ceq 'partial' -and
   $missing.warnings -contains 'a7.fragment_requires_versioned_B_D_and_A_source_receipts' -and
   $missing.metrics.actualReturnedBytes -eq 0L -and
   $memory.Position -eq 0L) ('SPC'+$spc+': unsupported source binding refuses before Read')
  $live=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $memory -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedDirectoryReceipts -BindAObservedFatPairReceipts -BindAObservedCFragmentReceipts
  $c=$live.cFragmentPhysicalReceipt
  Assert-A7R12 ($live.status -ceq 'partial' -and
   $live.bPhysicalReceipt.decision -ceq 'A_in_process_returned_intervals_consistent' -and
   $live.dPhysicalReceipt.decision -ceq 'A_in_process_numeric_FAT_pair_coverage_consistent' -and
   $live.dPhysicalReceipt.pairedFullyObservedEntries -eq 128L -and
   $live.dPhysicalReceipt.unobservedPairedEntryIndices -eq 65536L -and
   $c.schemaVersion -ceq 'a7_live_fragment_receipt_v1' -and
   $c.decision -ceq 'source_observed_candidate_definitions_original_UNKNOWN' -and
   $c.sourceOrigin -ceq 'A_in_process_live_Stream_Read_only' -and
   $c.numericDataWindowTrust -ceq 'B_numeric_BPB_unverified' -and
   $c.numericDataWindowStartBytes -gt 65536 -and
   $c.candidateCount -eq 1 -and
   $c.sourceObservedCandidateCount -eq 1) ('SPC'+$spc+': B_C_D_AND_CANDIDATE_one_meter')
  Assert-A7R12 ($live.metrics.fragmentScanReturnedBytes -gt 32768 -and
   $live.metrics.candidateValidationReturnedBytes -gt 0 -and
   $live.metrics.candidateValidationReturnedBytes -eq $c.candidateValidationReturnedBytes -and
   $live.metrics.repeatedReturnedBytes -eq $live.metrics.actualReturnedBytes-$live.metrics.uniqueReturnedBytes -and
   $live.metrics.actualReturnedBytes -le 120000L -and
   $live.metrics.physicalReadCalls -le 512L -and
   $live.metrics.sourceReadEvents -gt 10) ('SPC'+$spc+': A_quota_real_read_union_costs')
  foreach($candidate in @($c.candidateDefinitions)){
   Assert-A7R12 ($candidate.readEvidenceStatus -ceq 'A_in_process_source_observed' -and
    @($candidate.orderedExtents).Count -eq 2 -and
    $candidate.validationReturnedBytes -eq $candidate.expectedExtentBytes -and
    $candidate.validationReadEvents -gt 0 -and
    $candidate.orderedExtents[0].offsetBytes -ge $c.numericDataWindowStartBytes -and
    $candidate.orderedExtents[1].offsetBytes -ge $c.numericDataWindowStartBytes -and
    -not $candidate.originalShaVerified -and
    $candidate.originalIdentity -ceq 'unknown' -and
    -not $candidate.canExport -and
    -not $candidate.canRepair) ('SPC'+$spc+': ordered_C_candidate_A_source_return')
  }
  Assert-A7R12 ($c.incompleteOriginalSource -and
   $live.originalIdentity -ceq 'unknown' -and
   $live.recoveredOriginalFiles -eq 0 -and
   -not $live.canExport -and -not $live.canSelectFatCopy -and
   -not $c.canExport -and -not $c.canSelectOriginal -and -not $c.canRepair -and
   $live.sourceReadEvidence -ceq 'in_process_source_and_candidate_receipts_not_original_integrity' -and
   $memory.CanWrite -eq $false -and
   (Get-A3DSha256 $image) -ceq $sha) ('SPC'+$spc+': no_original_file_or_source_authenticity_claim')
  $wholeActual+=[long]$live.metrics.actualReturnedBytes
  $complete++
  Write-Host ('A7 R12 SHARED SOURCE: SPC{0} A_total_returnedB={1} A_calls={2} fragmentScoutB={3} candidateValidationB={4} C_candidates={5} FAT_observed=128/65664 original=UNKNOWN' -f $spc,$live.metrics.actualReturnedBytes,$live.metrics.physicalReadCalls,$live.metrics.fragmentScanReturnedBytes,$live.metrics.candidateValidationReturnedBytes,$c.candidateCount)
 }finally{$memory.Dispose()}
}
Assert-A7R12 ($complete -eq 2 -and $wholeActual -gt 0) 'two_standard_generated_sources'
# A protected stream must not carry candidate source-observed receipt from a
# late 3-byte FAT read followed by true physical zero in a separate instance.
$bad=[byte[]](New-ChappyA3DStandardFixture -Seed 202627 -SectorsPerCluster 1).image
$shaBad=Get-A3DSha256 $bad
$source=[A7R12LateFatZeroMemory]::new($bad,16896L)
try{
 $r=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $source -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedDirectoryReceipts -BindAObservedFatPairReceipts -BindAObservedCFragmentReceipts
 Assert-A7R12 ($source.Triggered -and $source.Position -lt $source.Length -and
  $r.status -ceq 'partial' -and
  $r.cFragmentPhysicalReceipt.decision -ceq 'partial_unknown' -and
  $r.cFragmentPhysicalReceipt.candidateCount -eq 0 -and
  $r.dPhysicalReceipt.decision -ceq 'unattributed' -and
  $r.metrics.actualReturnedBytes -eq $source.Returned -and
  $r.metrics.physicalReadCalls -eq $source.Calls -and
  -not $r.canExport -and (Get-A3DSha256 $bad) -ceq $shaBad) 'late_3B_FAT_physical_zero_never_mints_candidate_receipt'
}finally{$source.Dispose()}
$quota=[IO.MemoryStream]::new($bad,$false)
try{
 $q=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $quota -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedDirectoryReceipts -BindAObservedFatPairReceipts -BindAObservedCFragmentReceipts -MaxPhysicalReadBytes 1024
 Assert-A7R12 ($q.cFragmentPhysicalReceipt.candidateCount -eq 0 -and
  $q.metrics.actualReturnedBytes -le 1024L -and -not $q.canExport) 'global_quota_UNKNOWN_not_winner'
}finally{$quota.Dispose()}
$writable=[IO.MemoryStream]::new($bad)
try{
 $deny=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $writable -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedDirectoryReceipts -BindAObservedFatPairReceipts -BindAObservedCFragmentReceipts
 Assert-A7R12 ($deny.metrics.actualReturnedBytes -eq 0L -and
  $deny.cFragmentPhysicalReceipt.decision -ceq 'not_requested' -and -not $deny.canExport) 'writable_source_denied_without_reads'
}finally{$writable.Dispose()}
Write-Host 'PASS: A7 B/C/D + actual C two-piece candidate physical validation under ONE protected A Stream.Read, default OFF and source/error unknown.'
