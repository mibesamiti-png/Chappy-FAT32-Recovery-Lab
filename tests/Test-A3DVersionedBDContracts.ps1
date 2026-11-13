#Requires -Version 5.1
# Team A A7-06: real B4-05 + D6-05 versioned results under A outer Stream.
# Only generated artificial nonwritable memory. No device path, export or writes.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-Chappy3DDamagedFixture.ps1')
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $root 'core\Chappy.LiveBcdEvidence.psm1') -Force
function Assert-A7BD([bool]$Okay,[string]$Code){if(-not $Okay){throw ('A7_VERSIONED_BD_FAIL: '+$Code)}}
$runs=0;$returned=0L
foreach($case in @('M00','M02')){
 $fixture=New-ChappyA3DDamagedFixture -Seed 202611 -Case $case
 [byte[]]$img=$fixture.image
 $sha=Get-A3DSha256 $img
 $source=[IO.MemoryStream]::new($img,$false)
 try{
  $disabled=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $source -UseVersionedBDContracts
  Assert-A7BD ($disabled.status -ceq 'disabled' -and $disabled.metrics.actualReturnedBytes -eq 0 -and $source.Position -eq 0) 'default_OFF_zero_returns_even_with_versioned_switch'
  $r=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $source -EnableSyntheticLiveBcd -UseVersionedBDContracts
  Assert-A7BD ($r.status -ceq 'partial' -and $r.schemaVersion -ceq 'a7_live_bcd_envelope_v1' -and
   $r.sourceReadEvidence -ceq 'in_process_source_reads_reconciled_not_candidate_receipts' -and
   $r.originalIdentity -ceq 'unknown' -and $r.recoveredOriginalFiles -eq 0 -and
   -not $r.canExport -and -not $r.canSelectFatCopy) 'cross_team_actual_consumer_envelope'
  Assert-A7BD ($r.b.schemaVersion -ceq 'b_directory_evidence_v1' -and
   $r.b.probableParentEdges -eq 0 -and
   $r.b.sourceReadAttestation -ceq 'B_unattested_A_checks_outer_source' -and
   $r.b.candidateCount -gt 0) 'B_real_versioned_redacted_strict_parent'
  Assert-A7BD ($r.d.contractVersion -ceq 'd6_guarded_fat_result_v1' -and
   $r.d.fatWinner -ceq 'not_selected' -and -not $r.d.writePermitted -and
   $r.d.sourceReadAttestation -ceq 'D_unattested_A_checks_outer_source' -and
   $r.d.guardDecision.Length -gt 0) 'D_real_guarded_first_VBR_policy'
  $m=$r.metrics
  Assert-A7BD ($m.actualReturnedBytes -gt 0 -and $m.actualReturnedBytes -le 120000 -and
   $m.uniqueReturnedBytes -gt 0 -and $m.repeatedReturnedBytes -eq ($m.actualReturnedBytes-$m.uniqueReturnedBytes) -and
   $m.actualReturnedBytes -eq ($m.geometryReturnedBytes+$m.directoryReturnedBytes+$m.carvingReturnedBytes+$m.fatReturnedBytes) -and
   $m.physicalReadCalls -ge $m.sourceReadEvents -and $m.physicalReadCalls -le 512) 'A_independent_all_consumer_actual_returns'
  Assert-A7BD ((Get-A3DSha256 $img) -ceq $sha -and -not $source.CanWrite) 'compact_image_SHA_unchanged'
  $runs++;$returned += $m.actualReturnedBytes
  Write-Host ('A7 NEW BD compact={0} Bv={1} Dv={2} Dguard={3} returned={4} unique={5} reads={6} original=UNKNOWN' -f
   $case,$r.b.schemaVersion,$r.d.contractVersion,$r.d.guardDecision,$m.actualReturnedBytes,$m.uniqueReturnedBytes,$m.physicalReadCalls)
 }finally{$source.Dispose()}
}
# Real standards-shaped artificial FAT32 checks the deny-first interface on
# geometry that extends beyond compact 2MiB research geometry assumptions.
$standard=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster 1
[byte[]]$big=$standard.image
Assert-A7BD ($big.Length -gt 30MB -and $big.Length -lt 80MB) 'standard_synthetic_geometry'
$bigSha=Get-A3DSha256 $big
$bigRaw=[IO.MemoryStream]::new($big,$false)
try{
 $r=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $bigRaw -EnableSyntheticLiveBcd -UseVersionedBDContracts
 Assert-A7BD ($r.status -ceq 'partial' -and
  $r.sourceReadEvidence -ceq 'in_process_source_reads_reconciled_not_candidate_receipts' -and
  $r.b.schemaVersion -ceq 'b_directory_evidence_v1' -and
  $r.d.contractVersion -ceq 'd6_guarded_fat_result_v1' -and
  $r.originalIdentity -ceq 'unknown' -and -not $r.canExport -and
  -not $r.d.writePermitted -and $r.d.fatWinner -ceq 'not_selected') 'standard_size_real_B_D_contracts_under_A_meter'
 Assert-A7BD ($r.metrics.actualReturnedBytes -gt 0 -and
  $r.metrics.actualReturnedBytes -le 120000 -and
  $r.metrics.fatReturnedBytes -le 4096 -and
  $r.metrics.actualReturnedBytes -eq ($r.metrics.geometryReturnedBytes+$r.metrics.directoryReturnedBytes+$r.metrics.carvingReturnedBytes+$r.metrics.fatReturnedBytes) -and
  (Get-A3DSha256 $big) -ceq $bigSha) 'standard_true_physical_bytes_and_source_unchanged'
 Write-Host ('A7 NEW BD standard actualB={0} FATphaseB={1} guard={2} state={3} observedOriginal=UNKNOWN' -f
  $r.metrics.actualReturnedBytes,$r.metrics.fatReturnedBytes,$r.d.guardDecision,$r.d.fatProbeState)
 $runs++
}finally{$bigRaw.Dispose()}
# A forcibly caps total physical consumption across B,C,D. A budget refusal
# cannot be turned into a healthy empty FAT or verified original file.
$smallRaw=[IO.MemoryStream]::new($big,$false)
try{
 $r=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $smallRaw -EnableSyntheticLiveBcd -UseVersionedBDContracts -MaxPhysicalReadBytes 1024
 Assert-A7BD ($r.status -ceq 'partial' -and $r.sourceReadEvidence -ceq 'unattributed' -and
  $r.metrics.actualReturnedBytes -le 1024 -and $r.originalIdentity -ceq 'unknown' -and
  -not $r.canExport -and -not $r.canSelectFatCopy) 'global_shared_A_quota_denies_versioned_fat'
}finally{$smallRaw.Dispose()}
Assert-A7BD ($runs -eq 3 -and $returned -gt 0) 'three_actual_multiteam_synthetic_cases'
Write-Host 'PASS: A7 actual B4-05 and D6-05 versioned adapters under one physical A returned-byte meter on compact + standards-shaped artificial source, 0 original files and 0 exports.'