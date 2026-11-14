#Requires -Version 5.1
# A7 original-stage output classification: independent outcome axes, one-source
# evidence deduplication and test-only external artificial original oracle.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $root 'core\Chappy.PublicEvidenceV1.psm1') -Force
function Assert-A7Axes([bool]$Valid,[string]$Message){
 if(-not $Valid){throw ('A7_OUTCOME_AXES_FAIL: '+$Message)}
}
if(-not ('A7AxesShortSource' -as [type])){
 Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class A7AxesShortSource:MemoryStream {
 bool first=false;long returned=0;
 public A7AxesShortSource(byte[] b):base(b,false){}
 public long Returned {get{return returned;}}
 public override int Read(byte[] b,int offset,int count){
  if(first)return 0;
  first=true;int got=base.Read(b,offset,Math.Min(17,count));returned+=got;return got;
 }
}
'@
}
$pass=0
foreach($spc in @(1,2)){
 $f=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
 [byte[]]$image=$f.image
 $initial=Get-A3DSha256 $image
 $stream=[IO.MemoryStream]::new($image,$false)
 try{
  $off=Get-ChappyA7PublicEvidenceV1 -Source $stream
  Assert-A7Axes ($off.status -ceq 'disabled' -and
   $off.outcome.discovery -ceq 'unknown' -and
   $off.outcome.structure -ceq 'unverified' -and
   $off.outcome.oracleByteIdentity -ceq 'test_only_not_evaluated' -and
   $off.evidenceAccounting.sourceSessionCount -eq 0 -and
   $off.evidenceAccounting.uniquePhaseLabelCount -eq 0 -and
   $off.metrics.actualReturnedBytes -eq 0L -and
   $stream.Position -eq 0L) ('SPC'+$spc+':default_off_no_source_read_or_identity_claim')
  $pub=Get-ChappyA7PublicEvidenceV1 -Source $stream -EnableSyntheticPublicEvidence
  Assert-A7Axes ($pub.schemaVersion -ceq 'a7_public_evidence_v1' -and
   $pub.status -ceq 'partial' -and
   $pub.decision -ceq 'source_observed_structural_candidates_only' -and
   $pub.outcome.discovery -ceq 'bounded_window_found' -and
   $pub.outcome.structure -ceq 'structurally_consistent_3mf_not_original' -and
   $pub.outcome.sourceObservation -ceq 'one_A_invocation_observed' -and
   $pub.outcome.ambiguity -ceq 'unscanned_regions_or_alternatives_unknown' -and
   $pub.outcome.oracleByteIdentity -ceq 'test_only_not_evaluated' -and
   $pub.outcome.recoverability -ceq 'unknown' -and
   -not $pub.outcome.unrecoverable) ('SPC'+$spc+':independent_candidate_result_axes')
  $refs=@($pub.evidenceReferences)
  Assert-A7Axes ($refs.Count -eq 4 -and
   @($refs | Select-Object -Unique).Count -eq 4 -and
   $pub.evidenceAccounting.sourceSessionCount -eq 1 -and
   $pub.evidenceAccounting.phaseLabelCount -eq 4 -and
   $pub.evidenceAccounting.uniquePhaseLabelCount -eq 4 -and
   $pub.evidenceAccounting.actualReturnedBytes -eq $pub.metrics.actualReturnedBytes -and
   $pub.evidenceAccounting.distinctSourceBytes -eq $pub.metrics.uniqueReturnedBytes -and
   $pub.evidenceAccounting.repeatedSourceBytes -eq $pub.metrics.repeatedReturnedBytes -and
   $pub.evidenceAccounting.repeatedSourceBytes -gt 0 -and
   $pub.evidenceAccounting.actualReturnedBytes -eq
    ($pub.evidenceAccounting.distinctSourceBytes+$pub.evidenceAccounting.repeatedSourceBytes) -and
   -not $pub.evidenceAccounting.repeatedReadsIndependentEvidence -and
   $pub.evidenceAccounting.originalOracleWitnessCount -eq 0) ('SPC'+$spc+':4_phases_one_source_no_double_credit')
  $c=@($pub.candidateDefinitions)
  Assert-A7Axes ($c.Count -eq 1 -and
   $c[0].candidateState.discovery -ceq 'bounded_window_found' -and
   $c[0].candidateState.structure -ceq '3mf_structural_candidate' -and
   $c[0].candidateState.sourceObservation -ceq 'A_successfully_returned_candidate_extents' -and
   $c[0].candidateState.oracleByteIdentity -ceq 'test_only_not_evaluated' -and
   $c[0].candidateState.recoverability -ceq 'unknown' -and
   $c[0].originalIdentity -ceq 'unknown' -and
   -not $c[0].canSelectOriginal -and -not $c[0].canExport) ('SPC'+$spc+':per_candidate_axes')
  # Test-only oracle is read ONLY AFTER the public source report is finalized.
  # It is never passed to the module or surfaced in the result.
  $spans=@($c[0].orderedPhysicalExtents)
  $total=[int]($spans[0].lengthBytes+$spans[1].lengthBytes)
  [byte[]]$reassembled=[byte[]]::new($total)
  [Array]::Copy($image,[int]$spans[0].offsetBytes,$reassembled,0,[int]$spans[0].lengthBytes)
  [Array]::Copy($image,[int]$spans[1].offsetBytes,$reassembled,[int]$spans[0].lengthBytes,[int]$spans[1].lengthBytes)
  $sha=Get-A3DSha256 $reassembled
  $original=@($f.oracle | Where-Object {$_.shortName -ceq 'MODEL   3MF'})
  $unrelated=@($f.oracle | Where-Object {$_.shortName -ceq 'PRINT   GCO'})
  Assert-A7Axes ($original.Count -eq 1 -and $unrelated.Count -eq 1 -and
   $sha -ceq [string]$original[0].sha256 -and
   $sha -cne [string]$unrelated[0].sha256) ('SPC'+$spc+':external_oracle_has_both_true_and_false_original_labels')
  $json=$pub | ConvertTo-Json -Compress -Depth 12
  Assert-A7Axes ($json.Length -lt 12000 -and
   $json -notmatch '(?i)\bsha256\b|artificial_3mf|artificial_gcode|master_img_path|privatefilename' -and
   ($json | ConvertFrom-Json).outcome.oracleByteIdentity -ceq 'test_only_not_evaluated' -and
   $pub.originalIdentity -ceq 'unknown' -and
   -not $pub.originalShaVerified -and -not $pub.canRepair -and
   -not $pub.canExport -and
   (Get-A3DSha256 $image) -ceq $initial) ('SPC'+$spc+':public_result_does_not_leak_or_promote_oracle')
  $pass++
  Write-Host ('A7 DISTINCT OUTCOMES: SPC{0} phaseLabels=4 independentSource=1 repeatedB={1} externalTruth=EXACT only test-only publicOriginal=UNKNOWN' -f $spc,$pub.evidenceAccounting.repeatedSourceBytes)
 }finally{$stream.Dispose()}
}
Assert-A7Axes ($pass -eq 2) 'two_standard_source_cases'
# A fake full-length artificial stream that truly returns 17 bytes and then
# zero must never produce a source-confirmed candidate or mark unrecoverable.
$shortImage=[byte[]](New-ChappyA3DStandardFixture -Seed 202612 -SectorsPerCluster 1).image
$before=Get-A3DSha256 $shortImage
$broken=[A7AxesShortSource]::new($shortImage)
try{
 $bad=Get-ChappyA7PublicEvidenceV1 -Source $broken -EnableSyntheticPublicEvidence
 Assert-A7Axes ($bad.decision -ceq 'unknown' -and
  $bad.outcome.discovery -ceq 'unknown' -and
  $bad.outcome.oracleByteIdentity -ceq 'test_only_not_evaluated' -and
  -not $bad.outcome.unrecoverable -and
  $bad.evidenceAccounting.sourceSessionCount -eq 0 -and
  $bad.metrics.actualReturnedBytes -eq 17L -and
  $bad.metrics.actualReturnedBytes -eq $broken.Returned -and
  @($bad.candidateDefinitions).Count -eq 0 -and
  -not $bad.canSelectOriginal -and -not $bad.canExport -and
  (Get-A3DSha256 $shortImage) -ceq $before) 'physical_17B_then_0_means_UNKNOWN_not_unrecoverable'
}finally{$broken.Dispose()}
Write-Host 'PASS: A7 candidate state axes, one-source evidence de-dup, outside-only original oracle scorer and fail-closed unknown semantics.'
