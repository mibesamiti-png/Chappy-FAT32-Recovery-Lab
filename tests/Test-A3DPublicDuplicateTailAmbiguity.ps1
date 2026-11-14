#Requires -Version 5.1
# A7-04/A7-05: ACTUAL same-session B/C/D + C two-piece source
# must not auto-select when a valid tail exists at TWO physical locations.
# All bytes are freshly generated synthetic read-only MemoryStreams.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $root 'core\Chappy.PublicEvidenceV1.psm1') -Force
function Require-A7Ambig([bool]$OK,[string]$Reason){
 if(-not $OK){throw ('A7_R7_MULTI_AMBIG_FAIL: '+$Reason)}
}
$verified=0
foreach($spc in @(1,2)){
 $f=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
 [byte[]]$original=$f.image
 $originalSha=Get-A3DSha256 $original
 $control=[IO.MemoryStream]::new($original,$false)
 try{
  $first=Get-ChappyA7PublicEvidenceV1 -Source $control -EnableSyntheticPublicEvidence
  Require-A7Ambig ($first.decision -ceq 'source_observed_structural_candidates_only' -and
   @($first.candidateDefinitions).Count -eq 1 -and
   $first.outcome.ambiguity -ceq 'unscanned_regions_or_alternatives_unknown') ('SPC'+$spc+':baseline_single_candidate')
  # The *test* duplicates the actual discovered full trailing 512-byte
  # synthetic sector at a vacant nearby sector. It never supplies this
  # location (or any oracle truth) to the production scanner.
  $tail=@($first.candidateDefinitions[0].orderedPhysicalExtents)[1]
  [long]$sourceSector=[long]([math]::Floor([double]$tail.offsetBytes/512.0)*512)
  [long]$secondSector=$sourceSector+6144L
  [long]$firstPiece=[long]$first.candidateDefinitions[0].orderedPhysicalExtents[0].offsetBytes
  Require-A7Ambig (($sourceSector % 512L) -eq 0L -and
   ($secondSector % 512L) -eq 0L -and
   $secondSector -gt ($sourceSector+512L) -and
   $secondSector -gt ($firstPiece+1056L) -and
   $secondSector -le ([long]$original.Length-512L)) ('SPC'+$spc+':synthetic_only_duplicate_tail_sector_bounds')
  [byte[]]$duplicated=[byte[]]$original.Clone()
  [Array]::Copy($original,[int]$sourceSector,$duplicated,[int]$secondSector,512)
  $afterConstruction=Get-A3DSha256 $duplicated
  Require-A7Ambig ($afterConstruction -cne $originalSha) ('SPC'+$spc+':test_artificial_source_modified_before_call_only')
  $mem=[IO.MemoryStream]::new($duplicated,$false)
  try{
   $res=Get-ChappyA7PublicEvidenceV1 -Source $mem -EnableSyntheticPublicEvidence
   $candidates=@($res.candidateDefinitions)
   Require-A7Ambig ($res.schemaVersion -ceq 'a7_public_evidence_v1' -and
    $res.status -ceq 'partial' -and
    $res.decision -ceq 'source_observed_structural_candidates_only' -and
    $res.outcome.discovery -ceq 'bounded_window_found' -and
    $res.outcome.structure -ceq 'structurally_consistent_3mf_not_original' -and
    $res.outcome.sourceObservation -ceq 'one_A_invocation_observed' -and
    $res.outcome.ambiguity -ceq 'multiple_structural_hypotheses' -and
    $res.outcome.oracleByteIdentity -ceq 'test_only_not_evaluated' -and
    $res.outcome.recoverability -ceq 'unknown' -and
    -not $res.outcome.unrecoverable -and
    $candidates.Count -ge 2 -and $candidates.Count -le 16) ('SPC'+$spc+':actually_scanned_duplicate_tail_is_ambiguous')
   $keys=@($candidates | ForEach-Object {$_.candidateId})
   Require-A7Ambig (@($keys|Select-Object -Unique).Count -eq $keys.Count -and
    $res.metrics.candidateCount -eq $candidates.Count -and
    $res.metrics.candidateSourceObservedCount -eq $candidates.Count -and
    $res.evidenceAccounting.sourceSessionCount -eq 1 -and
    $res.evidenceAccounting.phaseLabelCount -eq 4 -and
    $res.evidenceAccounting.uniquePhaseLabelCount -eq 4 -and
    -not $res.evidenceAccounting.repeatedReadsIndependentEvidence -and
    $res.evidenceAccounting.originalOracleWitnessCount -eq 0) ('SPC'+$spc+':multiple_candidates_are_one_physical_source_not_multiple_originals')
   $oracle=@($f.oracle | Where-Object {$_.shortName -ceq 'MODEL   3MF'})
   Require-A7Ambig ($oracle.Count -eq 1) ('SPC'+$spc+':private_original_scorer_setup')
   $externalMatches=0
   foreach($candidate in $candidates){
    $ext=@($candidate.orderedPhysicalExtents)
    Require-A7Ambig ($ext.Count -eq 2 -and
     $candidate.readEvidenceStatus -ceq 'A_in_process_source_observed' -and
     $candidate.candidateState.structure -ceq '3mf_structural_candidate' -and
     $candidate.candidateState.ambiguity -ceq 'other_hypotheses_or_unscanned_source_unknown' -and
     $candidate.candidateState.oracleByteIdentity -ceq 'test_only_not_evaluated' -and
     $candidate.originalIdentity -ceq 'unknown' -and -not $candidate.canSelectOriginal -and
     -not $candidate.canExport -and -not $candidate.canRepair) ('SPC'+$spc+':per_candidate_no_original_claim')
    # Independent TEST-only oracle; never given to A/C code.
    $length=[int]($ext[0].lengthBytes+$ext[1].lengthBytes)
    [byte[]]$joined=[byte[]]::new($length)
    [Array]::Copy($duplicated,[int]$ext[0].offsetBytes,$joined,0,[int]$ext[0].lengthBytes)
    [Array]::Copy($duplicated,[int]$ext[1].offsetBytes,$joined,[int]$ext[0].lengthBytes,[int]$ext[1].lengthBytes)
    if((Get-A3DSha256 $joined) -ceq [string]$oracle[0].sha256){$externalMatches++}
   }
   Require-A7Ambig ($externalMatches -ge 2 -and
    $res.originalIdentity -ceq 'unknown' -and
    -not $res.originalShaVerified -and -not $res.canSelectOriginal -and
    -not $res.canSelectFatCopy -and -not $res.canExport -and -not $res.canRepair -and
    $res.metrics.actualReturnedBytes -eq ($res.metrics.uniqueReturnedBytes+$res.metrics.repeatedReturnedBytes) -and
    $res.metrics.actualReturnedBytes -le 120000L -and
    $res.metrics.physicalReadCalls -le 512L -and
    (Get-A3DSha256 $duplicated) -ceq $afterConstruction -and
    (Get-A3DSha256 $original) -ceq $originalSha) ('SPC'+$spc+':even_two_external_exact_copies_cannot_pick_source_origins')
   $json=$res|ConvertTo-Json -Depth 14 -Compress
   Require-A7Ambig ($json.Length -lt 18000 -and
    $json -notmatch '(?i)\bsha256\b|artificial_3mf|privatefilename|master_img_path' -and
    ($json|ConvertFrom-Json).outcome.ambiguity -ceq 'multiple_structural_hypotheses') ('SPC'+$spc+':public_json_ambiguous_and_oracle_private')
   Write-Host ('A7 DOUBLE TAIL: SPC{0} A-candidate-count={1} externalScorerMatches={2} sourceSessions=1 sourceReturnedB={3} original=UNKNOWN' -f $spc,$candidates.Count,$externalMatches,$res.metrics.actualReturnedBytes)
   $verified++
  }finally{$mem.Dispose()}
 }finally{$control.Dispose()}
}
Require-A7Ambig ($verified -eq 2) 'both_R3_synthetic_cases'
Write-Host 'PASS: A7 real public source duplicate CRC-valid 3MF tail is AMBIGUOUS; candidates source-observed not original-identified or auto-selected.'
