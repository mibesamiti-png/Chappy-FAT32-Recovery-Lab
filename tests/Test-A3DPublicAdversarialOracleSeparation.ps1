#Requires -Version 5.1
# Team A indexed A7-04/A7-05: externally scored generated synthetic truth
# is never a production/public original-identity statement.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $root 'core\Chappy.PublicEvidenceV1.psm1') -Force
Import-Module (Join-Path $root 'core\Chappy.CandidateDefinitionBoundary.psm1') -Force
function Assert-A7Conflict([bool]$Condition,[string]$Description) {
 if(-not $Condition){throw ('A7_R13_ADVERSARIAL_FAIL: '+$Description)}
}
function New-A7Proposal([string]$Id,[object[]]$Spans,[string]$Token) {
 return [pscustomobject]@{
  candidateId=$Id;format='3mf';sourceToken=$Token;extents=@($Spans)
 }
}
if(-not ('A7R13LateFat3BThenZero' -as [type])){
 Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class A7R13LateFat3BThenZero:MemoryStream {
 readonly long fatOffset; bool shortSent=false; long physicalReturned=0;
 public A7R13LateFat3BThenZero(byte[] bytes,long at):base(bytes,false){fatOffset=at;}
 public bool Triggered {get{return shortSent;}}
 public long PhysicalReturned {get{return physicalReturned;}}
 public override int Read(byte[] b,int off,int n) {
  if(shortSent)return 0;
  int got=Position==fatOffset ? base.Read(b,off,Math.Min(3,n)) : base.Read(b,off,n);
  if(Position==fatOffset+3 && got==3)shortSent=true;
  physicalReturned+=got;
  return got;
 }
}
'@
}
$scored=0
foreach($spc in @(1,2)){
 $fixture=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
 [byte[]]$image=$fixture.image
 $wholeSha=Get-A3DSha256 $image
 $m=[IO.MemoryStream]::new($image,$false)
 try{
  # A actual protected source reads first. Oracle never goes to the public API.
  $report=Get-ChappyA7PublicEvidenceV1 -Source $m -EnableSyntheticPublicEvidence
  Assert-A7Conflict ($report.decision -ceq 'source_observed_structural_candidates_only' -and
   $report.status -ceq 'partial' -and
   $report.sourceAuthenticity -ceq 'not_real_media_authenticated' -and
   @($report.candidateDefinitions).Count -eq 1 -and
   $report.metrics.fatUnobservedPairedEntries -eq 65536L -and
   -not $report.canSelectOriginal -and -not $report.originalShaVerified -and
   -not $report.canExport) ('SPC'+$spc+': structural_and_returned_source_never_original_identity')
  $c=@($report.candidateDefinitions)[0]
  $spans=@($c.orderedPhysicalExtents)
  Assert-A7Conflict ($spans.Count -eq 2 -and $c.sourceObservedReturnedBytes -eq 887L) 'actual_A_two_piece_read'
  # INDEPENDENT OFFLINE TEST ORACLE ONLY: physically reconstruct the bytes in
  # the fixture *after* the A production reporter has returned.
  [int]$total=0
  foreach($span in $spans){$total+=[int]$span.lengthBytes}
  [byte[]]$bytes=[byte[]]::new($total)
  [int]$cursor=0
  foreach($span in $spans){
   [Array]::Copy($image,[int]$span.offsetBytes,$bytes,$cursor,[int]$span.lengthBytes)
   $cursor += [int]$span.lengthBytes
  }
  $candidateSha=Get-A3DSha256 $bytes
  $truth=@($fixture.oracle | Where-Object {$_.shortName -ceq 'MODEL   3MF'})
  $other=@($fixture.oracle | Where-Object {$_.shortName -ceq 'PRINT   GCO'})
  Assert-A7Conflict ($truth.Count -eq 1 -and $other.Count -eq 1 -and
   [long]$truth[0].lengthBytes -eq [long]$total -and
   $candidateSha -ceq [string]$truth[0].sha256 -and
   $candidateSha -cne [string]$other[0].sha256) ('SPC'+$spc+': external_oracle_distinguishes_exact_from_other_original')
  $json=$report | ConvertTo-Json -Depth 14 -Compress
  Assert-A7Conflict ($json -notmatch '(?i)\bsha256\b|artificial_3mf|artificial_gcode|originalFileName|originalBytes' -and
   $report.candidateDefinitions[0].integrityScope -ceq 'structural_only_not_original_file_integrity' -and
   $report.candidateDefinitions[0].originalIdentity -ceq 'unknown') ('SPC'+$spc+': independent_oracle_never_enters_public_result')
  # A definition is still *metadata only*, even after A source-observed bytes.
  # Repeated identical observations count once, not two independent facts.
  $token='A7_generated_scope_'+$spc
  $ordered=@($spans | ForEach-Object {
   [pscustomobject]@{offsetBytes=[long]$_.offsetBytes;lengthBytes=[long]$_.lengthBytes}
  })
  $good=New-A7Proposal ([string]$c.candidateId) $ordered $token
  $dup=Resolve-ChappyCandidateDefinitionBoundary -ImageLengthBytes ([long]$image.Length) -SourceToken $token -Proposals @($good,$good)
  Assert-A7Conflict ($dup.uniqueCandidateIds -eq 1 -and
   $dup.candidates[0].definitionCount -eq 2 -and
   $dup.conflictingCandidateIds -eq 0 -and
   $dup.candidates[0].sourceAuthority -ceq 'caller_supplied_unverified_not_A_meter' -and
   $dup.candidates[0].originalIdentity -ceq 'unknown') 'duplicate_metadata_not_new_A_source_proof'
  $reversed=New-A7Proposal ([string]$c.candidateId) @($ordered[1],$ordered[0]) $token
  $conflict=Resolve-ChappyCandidateDefinitionBoundary -ImageLengthBytes ([long]$image.Length) -SourceToken $token -Proposals @($good,$reversed)
  Assert-A7Conflict ($conflict.conflictingCandidateIds -eq 1 -and
   $conflict.candidates[0].status -ceq 'conflicting' -and
   -not $conflict.candidates[0].independentPhysicalReceiptEligible -and
   $conflict.candidates[0].reasons.Count -gt 0) 'reordered_same_ID_must_not_merge_or_promote'
  $foreign=New-A7Proposal ([string]$c.candidateId) $ordered ($token+'_foreign')
  $wrong=Resolve-ChappyCandidateDefinitionBoundary -ImageLengthBytes ([long]$image.Length) -SourceToken $token -Proposals @($foreign)
  Assert-A7Conflict ($wrong.conflictingCandidateIds -eq 1 -and
   -not $wrong.candidates[0].independentPhysicalReceiptEligible) 'foreign_source_token_no_A_receipt'
  Assert-A7Conflict ((Get-A3DSha256 $image) -ceq $wholeSha -and -not $m.CanWrite) 'generated_source_unchanged'
  $scored++
  Write-Host ('A7 EXTERNAL ORACLE: SPC{0} tested exact-original=yes unrelated-original=no publicOriginalIdentity=UNKNOWN duplicateAttribution=1 reordered=CONFLICT' -f $spc)
 }finally{$m.Dispose()}
}
Assert-A7Conflict ($scored -eq 2) 'both_R3_standards_sources_independent_scored'
# Contradictory backup BPB must not manufacture public source-authenticated
# candidate evidence when primary/backup numeric geometry conflicts.
$fixture2=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster 1 -Fragment3Mf
[byte[]]$corrupt=[byte[]]$fixture2.image.Clone()
$corrupt[(7*512)+13]=4 # backup BPB sectors/cluster differs from primary 1
$corruptSha=Get-A3DSha256 $corrupt
$broken=[IO.MemoryStream]::new($corrupt,$false)
try{
 $p=Get-ChappyA7PublicEvidenceV1 -Source $broken -EnableSyntheticPublicEvidence
 Assert-A7Conflict ($p.decision -ceq 'unknown' -and
  @($p.candidateDefinitions).Count -eq 0 -and
  $p.originalIdentity -ceq 'unknown' -and
  -not $p.canExport -and -not $p.canSelectFatCopy -and
  (Get-A3DSha256 $corrupt) -ceq $corruptSha) 'conflicting_BPB_must_not_mint_positive_public_candidate'
}finally{$broken.Dispose()}
# Delayed physical FAT1 3-byte read followed by true zero is NOT a complete
# numeric 4-byte FAT pair; no public candidate, regardless of logical length.
[byte[]]$damaged=[byte[]]$fixture2.image.Clone()
$damagedSha=Get-A3DSha256 $damaged
$late=[A7R13LateFat3BThenZero]::new($damaged,16896L)
try{
 $p=Get-ChappyA7PublicEvidenceV1 -Source $late -EnableSyntheticPublicEvidence
 Assert-A7Conflict ($late.Triggered -and $p.decision -ceq 'unknown' -and
  @($p.candidateDefinitions).Count -eq 0 -and
  $p.metrics.actualReturnedBytes -eq $late.PhysicalReturned -and
  -not $p.canExport -and -not $p.canSelectOriginal -and
  (Get-A3DSha256 $damaged) -ceq $damagedSha) 'late_3B_then_zero_stays_unknown_no_candidate'
}finally{$late.Dispose()}
Write-Host 'PASS: A7 public actual synthetic source, conflicting/reordered duplicate candidate IDs and independent external oracle, no original promotion.'
