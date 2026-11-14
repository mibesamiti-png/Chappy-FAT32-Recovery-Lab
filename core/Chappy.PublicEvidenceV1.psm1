#Requires -Version 5.1
# Team A R7 / A7-06: public SAFE synthetic-only projection over one actual A
# B/C/D + candidate-scoped Stream.Read source witness. No real card, IMG, or export.
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Chappy.LiveBcdEvidence.psm1') -Force

function Get-ChappyA7PublicEvidenceV1 {
 [CmdletBinding(PositionalBinding=$false)]
 param(
  [Parameter(Mandatory)][IO.Stream]$Source,
  [switch]$EnableSyntheticPublicEvidence,
  [ValidateRange(1024,120000)][long]$MaxPhysicalReadBytes=120000,
  [ValidateRange(1,512)][int]$MaxReadCalls=512
 )
 $metrics=[pscustomobject][ordered]@{
  actualReturnedBytes=0L;uniqueReturnedBytes=0L;repeatedReturnedBytes=0L
  physicalReadCalls=0L;fragmentScoutReturnedBytes=0L;candidateRereadReturnedBytes=0L
  fatObservedPairedEntries=$null;fatUnobservedPairedEntries=$null
  candidateCount=0;candidateSourceObservedCount=0
 }
 $report=[ordered]@{
  schemaVersion='a7_public_evidence_v1';team='A'
  status='disabled';decision='unknown'
  evidenceScope='generated_synthetic_only_default_off'
  sourceAuthority='none'
  sourceAuthenticity='not_proven'
  sourceCoverage='unscanned_UNKNOWN'
  originalIdentity='unknown';originalShaVerified=$false
  canSelectOriginal=$false;canSelectFatCopy=$false
  canExport=$false;canRepair=$false
  candidateDefinitions=@();bStatus='unknown';cStatus='unknown';dStatus='unknown'
  warningCodes=@('a7.public_optin_required')
  evidenceReferences=@()
  limits=[pscustomobject]@{maxPhysicalReadBytes=$MaxPhysicalReadBytes;maxReadCalls=$MaxReadCalls}
  metrics=$metrics
 }
 if(-not $EnableSyntheticPublicEvidence){return [pscustomobject]$report}
 $report.status='partial'
 $report.warningCodes=@('a7.public_source_or_candidate_UNKNOWN')
 # Only artificial source MemoryStreams are accepted by actual A integration.
 # This function itself never accepts a path or a source-return event log.
 $inner=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $Source -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedDirectoryReceipts -BindAObservedFatPairReceipts -BindAObservedCFragmentReceipts -MaxPhysicalReadBytes $MaxPhysicalReadBytes -MaxReadCalls $MaxReadCalls
 $report.bStatus=[string]$inner.b.status
 $report.cStatus=[string]$inner.c.status
 $report.dStatus=[string]$inner.d.status
 $metrics.actualReturnedBytes=[long]$inner.metrics.actualReturnedBytes
 $metrics.uniqueReturnedBytes=[long]$inner.metrics.uniqueReturnedBytes
 $metrics.repeatedReturnedBytes=[long]$inner.metrics.repeatedReturnedBytes
 $metrics.physicalReadCalls=[long]$inner.metrics.physicalReadCalls
 $receipt=$inner.cFragmentPhysicalReceipt
 if($receipt.decision -cne 'source_observed_candidate_definitions_original_UNKNOWN' -or
    $inner.bPhysicalReceipt.decision -cne 'A_in_process_returned_intervals_consistent' -or
    $inner.dPhysicalReceipt.decision -cne 'A_in_process_numeric_FAT_pair_coverage_consistent' -or
    $inner.sourceReadEvidence -cne 'in_process_source_and_candidate_receipts_not_original_integrity'){
  return [pscustomobject]$report
 }
 $definitions=@($receipt.candidateDefinitions)
 if($definitions.Count -lt 1 -or $definitions.Count -gt 16 -or
    $definitions.Count -ne [int]$receipt.sourceObservedCandidateCount){
  return [pscustomobject]$report
 }
 $safe=New-Object 'System.Collections.Generic.List[object]'
 foreach($c in $definitions){
  $spans=@($c.orderedExtents)
  if($spans.Count -ne 2 -or $c.format -cne '3mf' -or
     [string]$c.candidateId -cnotmatch '^3mf:[0-9]+\+[0-9]+,[0-9]+\+[0-9]+$' -or
     $c.readEvidenceStatus -cne 'A_in_process_source_observed' -or
     $c.originalIdentity -cne 'unknown' -or
     $c.canSelectOriginal -or $c.canExport -or $c.canRepair){
   return [pscustomobject]$report
  }
  [long]$first=[long]$spans[0].offsetBytes
  [long]$firstB=[long]$spans[0].lengthBytes
  [long]$second=[long]$spans[1].offsetBytes
  [long]$secondB=[long]$spans[1].lengthBytes
  if($first -lt 0 -or $second -lt 0 -or $firstB -le 0 -or $secondB -le 0 -or
     ($firstB+$secondB) -gt 1056L -or
     $first -gt $Source.Length-$firstB -or $second -gt $Source.Length-$secondB -or
     ($first -lt $second+$secondB -and $second -lt $first+$firstB) -or
     [string]$c.candidateId -cne ('3mf:{0}+{1},{2}+{3}' -f $first,$firstB,$second,$secondB) -or
     [long]$c.expectedExtentBytes -ne ($firstB+$secondB) -or
     [long]$c.validationReturnedBytes -ne ($firstB+$secondB) -or
     [int]$c.validationReadEvents -lt 1){
   return [pscustomobject]$report
  }
  $safe.Add([pscustomobject]@{
   candidateId=[string]$c.candidateId;format='3mf'
   orderedPhysicalExtents=@(
    [pscustomobject]@{sequence=0;offsetBytes=$first;lengthBytes=$firstB},
    [pscustomobject]@{sequence=1;offsetBytes=$second;lengthBytes=$secondB}
   )
   readEvidenceStatus='A_in_process_source_observed'
   sourceEvidenceReference='A7.candidate_specific_successful_return'
   sourceObservedReturnedBytes=[long]$c.validationReturnedBytes
   sourceObservedReadCalls=[int]$c.validationReadEvents
   integrityScope='structural_only_not_original_file_integrity'
   originalIdentity='unknown';originalShaVerified=$false
   canSelectOriginal=$false;canExport=$false;canRepair=$false
  })
 }
 if($safe.Count -ne $definitions.Count){return [pscustomobject]$report}
 $metrics.fragmentScoutReturnedBytes=[long]$inner.metrics.fragmentScanReturnedBytes
 $metrics.candidateRereadReturnedBytes=[long]$inner.metrics.candidateValidationReturnedBytes
 $metrics.fatObservedPairedEntries=[long]$inner.dPhysicalReceipt.pairedFullyObservedEntries
 $metrics.fatUnobservedPairedEntries=[long]$inner.dPhysicalReceipt.unobservedPairedEntryIndices
 $metrics.candidateCount=$safe.Count
 $metrics.candidateSourceObservedCount=$safe.Count
 if($metrics.actualReturnedBytes -gt $MaxPhysicalReadBytes -or
    $metrics.physicalReadCalls -gt $MaxReadCalls -or
    $metrics.actualReturnedBytes -ne ($metrics.uniqueReturnedBytes+$metrics.repeatedReturnedBytes) -or
    $metrics.fatObservedPairedEntries -ne 128L -or
    $metrics.fatUnobservedPairedEntries -ne 65536L){
  # These are narrow R3 synthetic expected controls, not a claimed general FAT32 geometry.
  return [pscustomobject]$report
 }
 $report.decision='source_observed_structural_candidates_only'
 $report.sourceAuthority='A_same_invocation_protected_Stream_Read'
 $report.sourceAuthenticity='not_real_media_authenticated'
 $report.sourceCoverage='partial_32768B_data_window_remote_UNKNOWN'
 $report.candidateDefinitions=@($safe.ToArray())
 $report.evidenceReferences=@('A7.B_directory_actual_read','A7.C_two_piece_actual_scan','A7.D_fat_pair_actual_read','A7.candidate_specific_successful_return')
 $report.warningCodes=@('a7.original_file_identity_UNKNOWN','a7.numeric_volume_geometry_not_authenticated','a7.remote_source_unobserved','a7.no_original_SHA')
 return [pscustomobject]$report
}
Export-ModuleMember -Function Get-ChappyA7PublicEvidenceV1
