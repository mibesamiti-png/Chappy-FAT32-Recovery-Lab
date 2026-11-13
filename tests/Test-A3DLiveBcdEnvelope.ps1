#Requires -Version 5.1
# Team A A7-01 live B/C/D module execution and separately metered source returns.
# Test-generated 2MiB nonwritable bytes ONLY; no real card/master IMG.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-Chappy3DDamagedFixture.ps1')
Import-Module (Join-Path $root 'core\Chappy.LiveBcdEvidence.psm1') -Force
function Assert-A7LiveBcd([bool]$Condition,[string]$Reason){
 if(-not $Condition){throw ('A7_LIVE_BCD_FAIL: '+$Reason)}
}
if(-not ('ChappyA7EarlyBcdMemoryV1' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class ChappyA7EarlyBcdMemoryV1 : MemoryStream {
 bool started=false;
 public ChappyA7EarlyBcdMemoryV1(byte[] bytes):base(bytes,false){}
 public override int Read(byte[] b,int off,int n){
  if(started)return 0;
  started=true;
  return base.Read(b,off,Math.Min(n,17));
 }
}
'@
}
$caseCount=0
foreach($case in @('M00','M02')){
 $fixture=New-ChappyA3DDamagedFixture -Seed 202611 -Case $case
 [byte[]]$bytes=$fixture.image
 $before=Get-A3DSha256 $bytes
 $raw=[IO.MemoryStream]::new($bytes,$false)
 try{
  $oldPosition=$raw.Position
  $disabled=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $raw
  Assert-A7LiveBcd ($disabled.status -ceq 'disabled' -and
   $disabled.metrics.actualReturnedBytes -eq 0 -and
   $raw.Position -eq $oldPosition -and
   @($disabled.candidateDefinitions).Count -eq 0) 'default_OFF_no_physical_source_reads'
  $active=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $raw -EnableSyntheticLiveBcd
  Assert-A7LiveBcd ($active.schemaVersion -ceq 'a7_live_bcd_envelope_v1' -and
   $active.status -ceq 'partial' -and
   $active.sourceReadEvidence -ceq 'in_process_source_reads_reconciled_not_candidate_receipts' -and
   $active.sourceAuthority -ceq 'A_in_process_returned_bytes_not_real_media_authenticity') 'real_B_C_D_source_event_union_reconciled'
  Assert-A7LiveBcd ($active.b.status -ne 'unknown' -and
   $active.b.probableParentEdges -eq 0 -and
   $active.c.status -ne 'unknown' -and
   $active.d.status -ne 'unknown' -and
   $active.d.fatWinner -ceq 'not_selected' -and
   -not $active.d.writePermitted) 'actual_three_module_results_with_conservative_B_parent'
  $m=$active.metrics
  Assert-A7LiveBcd ($m.actualReturnedBytes -gt 0 -and
   $m.actualReturnedBytes -le 120000 -and
   $m.uniqueReturnedBytes -gt 0 -and
   $m.uniqueReturnedBytes -le $m.actualReturnedBytes -and
   $m.repeatedReturnedBytes -eq $m.actualReturnedBytes-$m.uniqueReturnedBytes -and
   $m.physicalReadCalls -ge $m.sourceReadEvents -and
   $m.directoryReturnedBytes -gt 0 -and
   $m.carvingReturnedBytes -gt 0 -and
   $m.fatReturnedBytes -gt 0 -and
   $m.actualReturnedBytes -eq $m.geometryReturnedBytes+$m.directoryReturnedBytes+
    $m.carvingReturnedBytes+$m.fatReturnedBytes) 'true_source_read_costs_per_consumer'
  foreach($candidate in @($active.candidateDefinitions)){
   Assert-A7LiveBcd ($candidate.status -ceq 'consistent_definition_only' -and
     $candidate.physicalCandidateValidation -ceq 'not_performed' -and
     $candidate.originalIdentity -ceq 'unknown' -and
     $candidate.candidateId -clike '*:*+*' -and
     @($candidate.orderedExtents).Count -eq 1) 'C_ids_and_spans_are_not_trusted_original_bytes'
  }
  Assert-A7LiveBcd ($active.originalIdentity -ceq 'unknown' -and
   $active.recoveredOriginalFiles -eq 0 -and
   -not $active.canExport -and -not $active.canSelectFatCopy -and
   $null -eq $active.PSObject.Properties['privateFilePath']) 'never_infer_original_or_export'
  Assert-A7LiveBcd ((Get-A3DSha256 $bytes) -ceq $before -and
   -not $raw.CanWrite) 'artificial_source_SHA_unchanged'
  $caseCount++
  Write-Host ('A7 LIVE BCD case={0} actualB={1} uniqueB={2} calls={3} Bitems={4} Citems={5} fat={6} original=UNKNOWN' -f
   $case,$m.actualReturnedBytes,$m.uniqueReturnedBytes,$m.physicalReadCalls,
   $active.b.candidateCount,$active.c.candidateCount,$active.d.status)
 }finally{$raw.Dispose()}
}
$fixture=New-ChappyA3DDamagedFixture -Seed 202612 -Case M00
[byte[]]$image=$fixture.image
$sha=Get-A3DSha256 $image
$writable=[IO.MemoryStream]::new($image,$true)
try{
 $bad=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $writable -EnableSyntheticLiveBcd
 Assert-A7LiveBcd ($bad.status -ceq 'partial' -and
  $bad.sourceReadEvidence -ceq 'none' -and
  $bad.metrics.actualReturnedBytes -eq 0 -and
  $bad.warnings -contains 'a7.strict_nonwritable_synthetic_memory_required') 'writable_source_refused_before_read'
}finally{$writable.Dispose()}
$short=[ChappyA7EarlyBcdMemoryV1]::new($image)
try{
 $unknown=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $short -EnableSyntheticLiveBcd
 Assert-A7LiveBcd ($unknown.status -ceq 'partial' -and
  $unknown.sourceReadEvidence -ceq 'unattributed' -and
  $unknown.metrics.actualReturnedBytes -le 17 -and
  @($unknown.candidateDefinitions).Count -eq 0 -and
  $unknown.originalIdentity -ceq 'unknown') 'early_true_EOF_fails_closed'
}finally{$short.Dispose()}
$quotaSource=[IO.MemoryStream]::new($image,$false)
try{
 $quota=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $quotaSource -EnableSyntheticLiveBcd -MaxPhysicalReadBytes 1024
 Assert-A7LiveBcd ($quota.status -ceq 'partial' -and
  $quota.metrics.actualReturnedBytes -le 1024 -and
  $quota.originalIdentity -ceq 'unknown' -and
  -not $quota.canExport) 'hard_1024_byte_shared_source_quota'
}finally{$quotaSource.Dispose()}
$oneCall=[IO.MemoryStream]::new($image,$false)
try{
 $cap=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $oneCall -EnableSyntheticLiveBcd -MaxReadCalls 1
 Assert-A7LiveBcd ($cap.status -ceq 'partial' -and
  $cap.metrics.physicalReadCalls -le 1 -and
  $cap.sourceReadEvidence -ceq 'unattributed') 'hard_physical_call_cap'
}finally{$oneCall.Dispose()}
Assert-A7LiveBcd ((Get-A3DSha256 $image) -ceq $sha -and $caseCount -eq 2) 'all_artificial_bytes_preserved'
Write-Host 'PASS: A7 live three-module read-only B/C/D envelope, independent in-process returned bytes, strict parent suppression, true source EOF/quota denial, no original winner/export.'