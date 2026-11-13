#Requires -Version 5.1
# A7 B4-04 live A-issued directory returned-event join, artificial memory only.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-Chappy3DDamagedFixture.ps1')
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $root 'core\Chappy.LiveBcdEvidence.psm1') -Force
function Assert-A7DirJoin([bool]$Yes,[string]$Why){
 if(-not $Yes){throw ('A7_DIRECTORY_OUTER_JOIN_FAIL: '+$Why)}
}
if(-not ('A7DirJoinEarlyZeroMemoryV1' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class A7DirJoinEarlyZeroMemoryV1:MemoryStream{
 bool first=false;
 public A7DirJoinEarlyZeroMemoryV1(byte[] bytes):base(bytes,false){}
 public override int Read(byte[] b,int o,int n){
  if(first)return 0;
  first=true;
  return base.Read(b,o,Math.Min(17,n));
 }
}
'@
}
$cases=@(
 [pscustomobject]@{id='M00';image=(New-ChappyA3DDamagedFixture -Seed 202611 -Case M00).image},
 [pscustomobject]@{id='M02';image=(New-ChappyA3DDamagedFixture -Seed 202611 -Case M02).image},
 [pscustomobject]@{id='SPC1';image=(New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster 1).image}
)
$actualSourceBytes=0L
$matched=0
foreach($case in $cases){
 [byte[]]$img=$case.image
 $before=Get-A3DSha256 $img
 $raw=[IO.MemoryStream]::new($img,$false)
 try{
  $disabled=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $raw -BindAObservedDirectoryReceipts
  Assert-A7DirJoin ($disabled.status -ceq 'disabled' -and
   $disabled.metrics.actualReturnedBytes -eq 0 -and
   $disabled.bPhysicalReceipt.decision -ceq 'not_requested' -and
   $raw.Position -eq 0) 'default_off_zero_reads_even_receipt_switch'
  $badSwitch=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $raw -EnableSyntheticLiveBcd -BindAObservedDirectoryReceipts
  Assert-A7DirJoin ($badSwitch.status -ceq 'partial' -and
   $badSwitch.metrics.actualReturnedBytes -eq 0 -and
   $badSwitch.warnings -contains 'a7.directory_receipt_requires_versioned_B') 'versioned_B_mandatory_before_any_source_reads'
  $good=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $raw -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedDirectoryReceipts
  $br=$good.bPhysicalReceipt
  $m=$good.metrics
  Assert-A7DirJoin ($good.status -ceq 'partial' -and
   $good.sourceReadEvidence -ceq 'in_process_source_reads_reconciled_not_candidate_receipts' -and
   $good.b.schemaVersion -ceq 'b_directory_evidence_v1' -and
   $good.d.contractVersion -ceq 'd6_guarded_fat_result_v1' -and
   $good.b.probableParentEdges -eq 0 -and
   $good.d.fatWinner -ceq 'not_selected') 'real_B_C_D_under_one_A_meter'
  Assert-A7DirJoin ($br.schemaVersion -ceq 'a7_directory_source_receipt_v1' -and
   $br.decision -ceq 'A_in_process_returned_intervals_consistent' -and
   $br.outerEventOrigin -ceq 'A_in_process_live_Stream_Read_only' -and
   $br.sourceAuthenticity -ceq 'not_real_media_authenticated' -and
   $br.originalParent -ceq 'unknown' -and
   -not $br.canExport -and
   $br.observedCompletedSpans -ge 1) 'B_completed_directory_ranges_are_actual_A_source_returns'
  Assert-A7DirJoin ($m.actualReturnedBytes -eq ($m.geometryReturnedBytes+$m.directoryReturnedBytes+$m.carvingReturnedBytes+$m.fatReturnedBytes) -and
   $m.directoryReturnedBytes -ge 512 -and
   $m.actualReturnedBytes -le 120000 -and
   $m.uniqueReturnedBytes -le $m.actualReturnedBytes -and
   $m.repeatedReturnedBytes -eq $m.actualReturnedBytes-$m.uniqueReturnedBytes -and
   $m.physicalReadCalls -le 512) 'A_real_returned_directory_and_D_source_budget_consistent'
  Assert-A7DirJoin ($good.originalIdentity -ceq 'unknown' -and
   $good.recoveredOriginalFiles -eq 0 -and -not $good.canExport -and
   (Get-A3DSha256 $img) -ceq $before -and -not $raw.CanWrite) 'generated_source_unmodified_and_no_original_claim'
  $matched++;$actualSourceBytes+=[long]$m.actualReturnedBytes
  Write-Host ('A7 B4-04 join={0} decision={1} spans={2} pairs={3} directoryB={4} totalB={5} originalParent=UNKNOWN' -f
   $case.id,$br.decision,$br.observedCompletedSpans,$br.observedStructuralPairs,$m.directoryReturnedBytes,$m.actualReturnedBytes)
 }finally{$raw.Dispose()}
}
$control=[byte[]](New-ChappyA3DDamagedFixture -Seed 202612 -Case M00).image
$sha=Get-A3DSha256 $control
$early=[A7DirJoinEarlyZeroMemoryV1]::new($control)
try{
 $unknown=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $early -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedDirectoryReceipts
 Assert-A7DirJoin ($unknown.status -ceq 'partial' -and
  $unknown.metrics.actualReturnedBytes -le 17 -and
  $unknown.bPhysicalReceipt.decision -cne 'A_in_process_returned_intervals_consistent' -and
  $unknown.originalIdentity -ceq 'unknown' -and -not $unknown.canExport) 'early_17B_then_real_zero_no_fabricated_B_spans'
}finally{$early.Dispose()}
$quota=[IO.MemoryStream]::new($control,$false)
try{
 $denied=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $quota -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedDirectoryReceipts -MaxPhysicalReadBytes 1024
 Assert-A7DirJoin ($denied.metrics.actualReturnedBytes -le 1024 -and
  $denied.bPhysicalReceipt.decision -cne 'A_in_process_returned_intervals_consistent' -and
  -not $denied.canSelectFatCopy) 'global_outer_quota_cannot_promote_source'
}finally{$quota.Dispose()}
$writable=[IO.MemoryStream]::new($control,$true)
try{
 $denied=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $writable -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedDirectoryReceipts
 Assert-A7DirJoin ($denied.metrics.actualReturnedBytes -eq 0 -and
  $denied.sourceReadEvidence -ceq 'none') 'writable_denied_no_source_reads'
}finally{$writable.Dispose()}
Assert-A7DirJoin ((Get-A3DSha256 $control) -ceq $sha -and $matched -eq 3 -and $actualSourceBytes -gt 0) 'three_independent_artificial_sources_all_checked'
Write-Host 'PASS: A7 actual source Stream.Read directory returned spans join B4-04 and parent observations, three real BCD runs, early EOF/quota/writable deny, no original path, SHA or export.'