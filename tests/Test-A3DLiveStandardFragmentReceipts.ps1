#Requires -Version 5.1
# A7 new standard FAT32 non-oracle C two-fragment actual A source receipt tests.
# ALL sources invented in-memory, strictly nonwritable; no original device/IMG.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $root 'core\Chappy.FragmentPhysicalReceipts.psm1') -Force
function Assert-A7StandardFrag([bool]$Ok,[string]$Message){
 if(-not $Ok){throw ('A7_STANDARD_FRAGMENT_FAIL: '+$Message)}
}
if(-not ('A7StdFragShortZeroSource' -as [type])){
 Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class A7StdFragShortZeroSource:MemoryStream{
 bool first=false;
 public A7StdFragShortZeroSource(byte[] bytes):base(bytes,false){}
 public override int Read(byte[] buffer,int offset,int count) {
  if(first)return 0;
  first=true;
  return base.Read(buffer,offset,Math.Min(17,count));
 }
}
'@
}
$sourceTotal=0L;$verified=0
foreach($spc in @(1,2)){
 $fixture=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
 [byte[]]$img=$fixture.image
 $before=Get-A3DSha256 $img
 $raw=[IO.MemoryStream]::new($img,$false)
 try{
  $off=Invoke-ChappyA7FragmentPhysicalReceipts -Source $raw -EnableStandardFAT32DataWindow
  Assert-A7StandardFrag ($off.status -ceq 'disabled' -and $off.metrics.actualReturnedBytes -eq 0 -and $off.sourceToken -eq $null -and $off.dataWindowOrigin -ceq 'not_requested' -and $raw.Position -eq 0) ('SPC'+$spc+':optin_disabled_without_reads')
  $compact=Invoke-ChappyA7FragmentPhysicalReceipts -Source $raw -EnableA7FragmentReceipts
  Assert-A7StandardFrag ($compact.status -ceq 'partial' -and $compact.metrics.actualReturnedBytes -eq 0 -and $compact.candidateCount -eq 0 -and $compact.dataWindowOrigin -ceq 'not_requested') ('SPC'+$spc+':large_standard_source_denied_without_optin')
  $live=Invoke-ChappyA7FragmentPhysicalReceipts -Source $raw -EnableA7FragmentReceipts -EnableStandardFAT32DataWindow
  Assert-A7StandardFrag ($live.schemaVersion -ceq 'a7_fragment_physical_receipts_v1' -and
   $live.status -ceq 'partial' -and $live.cStatus -ceq 'ok' -and
   $live.dataWindowOrigin -ceq 'A_in_process_B_numeric_geometry_unverified' -and
   $live.dataWindowStartBytes -gt 65536L -and
   ($live.dataWindowStartBytes % 512) -eq 0 -and
   $live.cScanIncomplete -and
   $live.candidateCount -ge 1 -and $live.candidateCount -le 16 -and
   $live.sourceObservedCandidateCount -ge 1 -and $live.incompleteCandidateCount -eq 0) ('SPC'+$spc+':nonoracle_live_C_with_A_candidate_reread')
  Assert-A7StandardFrag ($live.metrics.geometryReturnedBytes -gt 0 -and
   $live.metrics.scanReturnedBytes -ge 32768 -and
   $live.metrics.validationReturnedBytes -gt 0 -and
   $live.metrics.geometryReturnedBytes+$live.metrics.scanReturnedBytes+$live.metrics.validationReturnedBytes -eq $live.metrics.actualReturnedBytes -and
   $live.metrics.actualReturnedBytes -le 120000L -and
   $live.metrics.physicalReadCalls -le 512L -and
   $live.metrics.uniqueReturnedBytes -le $live.metrics.actualReturnedBytes -and
   $live.metrics.repeatedReturnedBytes -eq $live.metrics.actualReturnedBytes-$live.metrics.uniqueReturnedBytes) ('SPC'+$spc+':A_same_stream_geometry_scout_validation_actual_returned_byte_union')
  Assert-A7StandardFrag ($live.originalIdentity -ceq 'unknown' -and
   -not $live.originalShaVerified -and -not $live.canSelectOriginal -and
   -not $live.canRepair -and -not $live.canExport -and
   $live.sourceReadScope -ceq 'A_candidate_specific_returned_bytes_only' -and
   -not $raw.CanWrite -and
   (Get-A3DSha256 $img) -ceq $before) ('SPC'+$spc+':generated_source_not_mutated_and_no_original_claim')
  foreach($c in @($live.candidateDefinitions)){
   Assert-A7StandardFrag ($c.readEvidenceStatus -ceq 'source_observed' -and
    $c.candidateValidationReadEvents -gt 0 -and
    $c.readReturnedBytes -eq $c.expectedExtentBytes -and
    @($c.orderedExtents).Count -eq 2 -and
    $c.orderedExtents[0].offsetBytes -ge $live.dataWindowStartBytes -and
    $c.orderedExtents[1].offsetBytes -ge $live.dataWindowStartBytes -and
    $c.originalIdentity -ceq 'unknown' -and -not $c.originalShaVerified -and
    -not $c.canSelectOriginal -and -not $c.canExport) ('SPC'+$spc+':real_A_candidate_specific_physical_return_receipts')
  }
  $sourceTotal += [long]$live.metrics.actualReturnedBytes
  $verified++
  Write-Host ('A7 STANDARD FRAGMENT: SPC{0} observed={1} geometryB={2} cScoutB={3} validationB={4} AphysicalTotalB={5} SourceAuth=NOT_REAL_MEDIA_AUTHENTICATED originalIdentity=UNKNOWN' -f
   $spc,$live.sourceObservedCandidateCount,$live.metrics.geometryReturnedBytes,$live.metrics.scanReturnedBytes,$live.metrics.validationReturnedBytes,$live.metrics.actualReturnedBytes)
 }finally{$raw.Dispose()}
}
Assert-A7StandardFrag ($verified -eq 2 -and $sourceTotal -gt 0) 'both_standard_source_geometries'
# Real physical premature zero cannot mint a candidate-specific source-observed receipt.
$bad=[byte[]](New-ChappyA3DStandardFixture -Seed 202612 -SectorsPerCluster 1).image
$h=Get-A3DSha256 $bad
$cut=[A7StdFragShortZeroSource]::new($bad)
try{
 $u=Invoke-ChappyA7FragmentPhysicalReceipts -Source $cut -EnableA7FragmentReceipts -EnableStandardFAT32DataWindow
 Assert-A7StandardFrag ($u.status -ceq 'partial' -and
  $u.sourceObservedCandidateCount -eq 0 -and $u.candidateCount -eq 0 -and
  $u.metrics.actualReturnedBytes -eq 17L -and
  $u.originalIdentity -ceq 'unknown' -and -not $u.canExport -and
  (Get-A3DSha256 $bad) -ceq $h) 'early_17B_then_zero_cannot_authenticate_geometry_or_candidate'
}finally{$cut.Dispose()}
$quota=[IO.MemoryStream]::new($bad,$false)
try{
 $q=Invoke-ChappyA7FragmentPhysicalReceipts -Source $quota -EnableA7FragmentReceipts -EnableStandardFAT32DataWindow -MaxPhysicalReadBytes 1024
 Assert-A7StandardFrag ($q.candidateCount -eq 0 -and $q.sourceObservedCandidateCount -eq 0 -and $q.metrics.actualReturnedBytes -le 1024L -and -not $q.canExport) 'A_strict_global_quota_failure_UNKNOWN'
}finally{$quota.Dispose()}
$w=[IO.MemoryStream]::new($bad)
try{
 $refused=Invoke-ChappyA7FragmentPhysicalReceipts -Source $w -EnableA7FragmentReceipts -EnableStandardFAT32DataWindow
 Assert-A7StandardFrag ($refused.metrics.actualReturnedBytes -eq 0 -and
  $refused.sourceObservedCandidateCount -eq 0 -and -not $refused.canExport) 'writable_source_denied'
}finally{$w.Dispose()}
Write-Host 'PASS: A7 actual A source-metered standard FAT32 B-geometry/C two-fragment candidate reads, negative EOF/quota/writable and no original claim.'
