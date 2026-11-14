#Requires -Version 5.1
# Team A public-safe result is a projection of REAL A source-return evidence,
# generated nonwritable synthetic image only. No source paths or raw bytes.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $root 'core\Chappy.PublicEvidenceV1.psm1') -Force
function Check-A7Public([bool]$OK,[string]$Why) {
 if(-not $OK){throw ('A7_PUBLIC_V1_FAIL: '+$Why)}
}
if(-not ('A7PublicShortSource17' -as [type])){
 Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class A7PublicShortSource17 : MemoryStream {
 bool first=false;
 public A7PublicShortSource17(byte[] bytes) : base(bytes,false){}
 public override int Read(byte[] b,int off,int count) {
  if(first)return 0;
  first=true;return base.Read(b,off,Math.Min(17,count));
 }
}
'@
}
$full=0;$actual=0L
foreach($spc in @(1,2)){
 $fixture=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
 [byte[]]$image=$fixture.image
 $initial=Get-A3DSha256 $image
 $memory=[IO.MemoryStream]::new($image,$false)
 try{
  $off=Get-ChappyA7PublicEvidenceV1 -Source $memory
  Check-A7Public ($off.status -ceq 'disabled' -and $off.schemaVersion -ceq 'a7_public_evidence_v1' -and
   $off.metrics.actualReturnedBytes -eq 0L -and @($off.candidateDefinitions).Count -eq 0 -and
   $off.evidenceReferences.Count -eq 0 -and
   $memory.Position -eq 0L) ('SPC'+$spc+':default_no_Read_or_source_property_use')
  $report=Get-ChappyA7PublicEvidenceV1 -Source $memory -EnableSyntheticPublicEvidence
  Check-A7Public ($report.schemaVersion -ceq 'a7_public_evidence_v1' -and
   $report.team -ceq 'A' -and $report.status -ceq 'partial' -and
   $report.decision -ceq 'source_observed_structural_candidates_only' -and
   $report.sourceAuthority -ceq 'A_same_invocation_protected_Stream_Read' -and
   $report.sourceAuthenticity -ceq 'not_real_media_authenticated' -and
   $report.sourceCoverage -ceq 'partial_32768B_data_window_remote_UNKNOWN' -and
   @($report.candidateDefinitions).Count -eq 1 -and
   @($report.evidenceReferences).Count -eq 4) ('SPC'+$spc+':versioned_explicit_source_scoped_safe_contract')
  Check-A7Public ($report.originalIdentity -ceq 'unknown' -and
   -not $report.originalShaVerified -and
   -not $report.canSelectOriginal -and -not $report.canSelectFatCopy -and
   -not $report.canExport -and -not $report.canRepair -and
   $report.warningCodes -contains 'a7.no_original_SHA' -and
   $report.warningCodes -contains 'a7.numeric_volume_geometry_not_authenticated' -and
   $report.metrics.fatObservedPairedEntries -eq 128L -and
   $report.metrics.fatUnobservedPairedEntries -eq 65536L) ('SPC'+$spc+':remote_and_original_UNKNOWN')
  Check-A7Public ($report.metrics.actualReturnedBytes -gt 100000 -and
   $report.metrics.actualReturnedBytes -le 120000 -and
   $report.metrics.physicalReadCalls -gt 0 -and
   $report.metrics.physicalReadCalls -le 512 -and
   $report.metrics.actualReturnedBytes -eq ($report.metrics.uniqueReturnedBytes+$report.metrics.repeatedReturnedBytes) -and
   $report.metrics.fragmentScoutReturnedBytes -gt 32768 -and
   $report.metrics.candidateRereadReturnedBytes -eq 887L -and
   $report.metrics.candidateSourceObservedCount -eq 1) ('SPC'+$spc+':true_A_returned_source_totals_and_C_specific_candidate')
  $c=@($report.candidateDefinitions)[0]
  Check-A7Public ($c.candidateId -match '^3mf:[0-9]+\+[0-9]+,[0-9]+\+[0-9]+$' -and
   @($c.orderedPhysicalExtents).Count -eq 2 -and
   $c.readEvidenceStatus -ceq 'A_in_process_source_observed' -and
   $c.sourceObservedReturnedBytes -eq 887L -and
   $c.sourceObservedReadCalls -ge 2 -and
   -not $c.canExport -and $c.originalIdentity -ceq 'unknown') ('SPC'+$spc+':C_id_order_extent_A_source_return_no_original_claim')
  $json=$report|ConvertTo-Json -Depth 12 -Compress
  $rebuilt=$json|ConvertFrom-Json
  Check-A7Public ($rebuilt.schemaVersion -ceq 'a7_public_evidence_v1' -and
   $rebuilt.candidateDefinitions.Count -eq 1 -and
   $json -notmatch '(?i)sourceToken|originalSha256|realfilename|filecontents|privatepath|\.img' -and
   $json.Length -lt 10000) ('SPC'+$spc+':sanitized_bounded_serializable_public_schema')
  Check-A7Public ((Get-A3DSha256 $image) -ceq $initial -and -not $memory.CanWrite) ('SPC'+$spc+':unchanged_artificial_source')
  $actual+=[long]$report.metrics.actualReturnedBytes
  $full++
  Write-Host ('A7 PUBLIC: SPC{0} sourceReturnedB={1} readCalls={2} candidates={3} originalUNKNOWN=yes' -f $spc,$report.metrics.actualReturnedBytes,$report.metrics.physicalReadCalls,@($report.candidateDefinitions).Count)
 }finally{$memory.Dispose()}
}
Check-A7Public ($full -eq 2 -and $actual -gt 0) 'two_generated_standard_source_cases'
$bad=[byte[]](New-ChappyA3DStandardFixture -Seed 202612 -SectorsPerCluster 1).image
$initialBad=Get-A3DSha256 $bad
$short=[A7PublicShortSource17]::new($bad)
try{
 $r=Get-ChappyA7PublicEvidenceV1 -Source $short -EnableSyntheticPublicEvidence
 Check-A7Public ($r.status -ceq 'partial' -and $r.decision -ceq 'unknown' -and
  @($r.candidateDefinitions).Count -eq 0 -and $r.metrics.actualReturnedBytes -eq 17L -and
  -not $r.canExport -and
  (Get-A3DSha256 $bad) -ceq $initialBad) 'short_17B_true_zero_unknown_without_public_candidate'
}finally{$short.Dispose()}
$quota=[IO.MemoryStream]::new($bad,$false)
try{
 $r=Get-ChappyA7PublicEvidenceV1 -Source $quota -EnableSyntheticPublicEvidence -MaxPhysicalReadBytes 1024
 Check-A7Public ($r.decision -ceq 'unknown' -and
  $r.metrics.actualReturnedBytes -le 1024L -and
  @($r.candidateDefinitions).Count -eq 0 -and -not $r.canExport) 'total_A_source_quota_UNKNOWN'
}finally{$quota.Dispose()}
$writable=[IO.MemoryStream]::new($bad)
try{
 $r=Get-ChappyA7PublicEvidenceV1 -Source $writable -EnableSyntheticPublicEvidence
 Check-A7Public ($r.decision -ceq 'unknown' -and
  $r.metrics.actualReturnedBytes -eq 0L -and
  @($r.candidateDefinitions).Count -eq 0 -and -not $r.canExport) 'writable_source_no_Read'
}finally{$writable.Dispose()}
Write-Host 'PASS: A7 public v1 actual A one-session B/C/D/C-candidate structural evidence, source/candidate UNKNOWN and privacy-safe JSON.'
