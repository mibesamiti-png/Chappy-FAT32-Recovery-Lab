#Requires -Version 5.1
# A7 D6-04 actual A same-session FAT source-returned 4-byte pair binding.
# Synthetic nonwritable MemoryStreams only; no original file/IMG.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $root 'core\Chappy.LiveBcdEvidence.psm1') -Force
function Assert-A7Fat([bool]$Ok,[string]$Label){
 if(-not $Ok){throw ('A7_FAT_LIVE_RETURNED_FAIL: '+$Label)}
}
if(-not ('A7FatEarlyZeroStreamV1' -as [type])){
 Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class A7FatEarlyZeroStreamV1:MemoryStream{
 bool first=false;
 public A7FatEarlyZeroStreamV1(byte[] data):base(data,false){}
 public override int Read(byte[] b,int o,int n){
  if(first)return 0;
  first=true;
  return base.Read(b,o,Math.Min(17,n));
 }
}
'@
}
$success=0
$sourceBytes=0L
foreach($spc in @(1,2)){
 $fixture=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc
 [byte[]]$img=$fixture.image
 $sha=Get-A3DSha256 $img
 $stream=[IO.MemoryStream]::new($img,$false)
 try{
  $disabled=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $stream -BindAObservedFatPairReceipts
  Assert-A7Fat ($disabled.status -ceq 'disabled' -and $disabled.dPhysicalReceipt.decision -ceq 'not_requested' -and $disabled.metrics.actualReturnedBytes -eq 0 -and $stream.Position -eq 0) 'disabled_zero_source_reads'
  $missing=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $stream -EnableSyntheticLiveBcd -BindAObservedFatPairReceipts
  Assert-A7Fat ($missing.status -ceq 'partial' -and $missing.warnings -contains 'a7.fat_pair_receipt_requires_versioned_D' -and $missing.metrics.actualReturnedBytes -eq 0 -and $stream.Position -eq 0) 'versioned_D_optin_required_before_any_Read'
  $live=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $stream -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedDirectoryReceipts -BindAObservedFatPairReceipts
  $fat=$live.dPhysicalReceipt
  Assert-A7Fat ($live.status -ceq 'partial' -and $live.d.contractVersion -ceq 'd6_guarded_fat_result_v1' -and $live.bPhysicalReceipt.decision -ceq 'A_in_process_returned_intervals_consistent') ('B_and_D_joined_under_same_A_meter_SPC'+$spc)
  Assert-A7Fat ($fat.schemaVersion -ceq 'a7_fat_pair_source_receipt_v1' -and $fat.decision -ceq 'A_in_process_numeric_FAT_pair_coverage_consistent' -and $fat.outerEventOrigin -ceq 'A_in_process_live_Stream_Read_only' -and $fat.sourceAuthenticity -ceq 'not_real_media_authenticated' -and $fat.pairedFullyObservedEntries -eq 128L -and $fat.unobservedPairedEntryIndices -eq 65536L -and $fat.observedSourceReadEvents -gt 0 -and $fat.sourceActualReturnedBytes -gt 0 -and $fat.physicalReadCalls -gt 0) ('actual_A_source_returned_FAT1_FAT2_pair_coverage_SPC'+$spc)
  Assert-A7Fat ($fat.originalIdentity -ceq 'unknown' -and $fat.fatCopyWinner -ceq 'not_selected' -and -not $fat.canRepair -and -not $fat.canExport -and $live.recoveredOriginalFiles -eq 0 -and $live.originalIdentity -ceq 'unknown' -and -not $live.canExport -and -not $live.canSelectFatCopy -and -not $stream.CanWrite) 'no_original_or_repair_or_winner_claim'
  Assert-A7Fat ($live.metrics.actualReturnedBytes -le 120000 -and $live.metrics.physicalReadCalls -le 512 -and $live.metrics.repeatedReturnedBytes -eq $live.metrics.actualReturnedBytes-$live.metrics.uniqueReturnedBytes -and (Get-A3DSha256 $img) -ceq $sha) 'total_bounded_real_A_meter_and_generated_SHA_unchanged'
  $success++;$sourceBytes+=[long]$live.metrics.actualReturnedBytes
  Write-Host ('A7 D6-04 LIVE FAT: SPC{0} paired={1}/65664 remoteUnknown={2} DphysicalB={3} outerCalls={4} AwholeSourceB={5} sourceAuthenticity=NOT_REAL_MEDIA_AUTHENTICATED' -f $spc,$fat.pairedFullyObservedEntries,$fat.unobservedPairedEntryIndices,$fat.sourceActualReturnedBytes,$fat.physicalReadCalls,$live.metrics.actualReturnedBytes)
 }finally{$stream.Dispose()}
}
Assert-A7Fat ($success -eq 2 -and $sourceBytes -gt 0) 'two_independent_standard_FAT32_source_fixtures'
# Fatal early physical zero before even a complete boot sector: never report positive FAT pairs.
$img2=[byte[]](New-ChappyA3DStandardFixture -Seed 202612 -SectorsPerCluster 1).image
$before2=Get-A3DSha256 $img2
$short=[A7FatEarlyZeroStreamV1]::new($img2)
try{
 $unknown=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $short -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedFatPairReceipts
 Assert-A7Fat ($unknown.status -ceq 'partial' -and $unknown.recoveredOriginalFiles -eq 0 -and $unknown.dPhysicalReceipt.decision -cne 'A_in_process_numeric_FAT_pair_coverage_consistent' -and -not $unknown.canExport -and $unknown.metrics.actualReturnedBytes -eq 17L -and (Get-A3DSha256 $img2) -ceq $before2) 'early_17B_then_zero_source_returns_unknown'
}finally{$short.Dispose()}
# Cross-operator/out-of-budget tests must never mint positive joined source receipts.
$small=[IO.MemoryStream]::new($img2,$false)
try{
 $quota=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $small -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedFatPairReceipts -MaxPhysicalReadBytes 1024
 Assert-A7Fat ($quota.dPhysicalReceipt.decision -cne 'A_in_process_numeric_FAT_pair_coverage_consistent' -and -not $quota.canExport -and $quota.metrics.actualReturnedBytes -le 1024L) 'global_source_quota_fail_closed'
}finally{$small.Dispose()}
$writable=[IO.MemoryStream]::new($img2)
try{
 $blocked=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $writable -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedFatPairReceipts
 Assert-A7Fat ($blocked.status -ceq 'partial' -and $blocked.metrics.actualReturnedBytes -eq 0 -and $blocked.dPhysicalReceipt.decision -ceq 'not_requested' -and -not $blocked.canExport) 'writable_source_denied_without_Read'
}finally{$writable.Dispose()}
Write-Host 'PASS: A7 real A in-process B/D source-bound FAT 4-byte pair receipts on generated SPC1/SPC2; unavailable/EOF/quota/writable deny, no real IMG.'
