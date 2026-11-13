#requires -Version 5.1
# C5-06 independent generated-only interface scorer.
# Artificial original extents and SHA stay HERE, never in C production API.
function Assert-C5V1([bool]$Okay,[string]$Why){
    if(-not $Okay){throw ('C5_06_V1_FAIL: '+$Why)}
}
if(-not ('ChappyC5V1MeasuredMemory' -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class ChappyC5V1MeasuredMemory : MemoryStream {
 private readonly HashSet<long> unique=new HashSet<long>();
 public long Returned{get;private set;}
 public long ReadCalls{get;private set;}
 public long UniqueReturned{get{return unique.Count;}}
 public ChappyC5V1MeasuredMemory(byte[] b):base(b,false){}
 public override int Read(byte[] b,int offset,int count){
  long at=Position;
  int got=base.Read(b,offset,count);
  ReadCalls++;Returned+=got;
  for(int i=0;i<got;i++)unique.Add(at+i);
  return got;
 }
}
public sealed class ChappyC5V1True17Eof : MemoryStream {
 private bool first;
 public long Returned{get;private set;}
 public int ReadCalls{get;private set;}
 public ChappyC5V1True17Eof(byte[] b):base(b,false){}
 public override int Read(byte[] b,int offset,int count){
  ReadCalls++;
  if(first)return 0;
  first=true;
  int got=base.Read(b,offset,Math.Min(17,count));
  Returned+=got;return got;
 }
}
'@
}
function Get-C5V1Score {
 param([byte[]]$Image,[object[]]$Candidates,[string]$OriginalSha,[long]$WindowStart,[int]$WindowBytes)
 $exact=0;$different=0;$ambig=@{}
 foreach($candidate in $Candidates){
  Assert-C5V1 ($candidate.originalIdentity -ceq 'unknown' -and
   $candidate.integrityScope -ceq 'structural_only_not_original_file_integrity' -and
   $candidate.sourceAuthenticity -ceq 'not_proven' -and
   $candidate.keyScope -ceq 'C_unattested_source_relative_only' -and
   $candidate.confidence -eq 'probable' -and $candidate.format -eq '3mf' -and
   $candidate.extentCount -eq 2 -and -not $candidate.canExport -and
   -not $candidate.canSelectOriginal -and
   $null -eq $candidate.PSObject.Properties['sourceToken'] -and
   $null -eq $candidate.PSObject.Properties['evidenceId'] -and
   $null -eq $candidate.PSObject.Properties['candidateSha256'] -and
   @($candidate.sourceSpans).Count -eq 2) 'candidate_schema_no_fake_original_or_A_receipts'
  $a=$candidate.sourceSpans[0];$b=$candidate.sourceSpans[1]
  $end=$WindowStart+[long]$WindowBytes
  Assert-C5V1 ($a.sequence -eq 0 -and $b.sequence -eq 1 -and
   $a.offsetBytes -ge $WindowStart -and $b.offsetBytes -ge $WindowStart -and
   $a.lengthBytes -gt 0 -and $b.lengthBytes -gt 0 -and
   $a.offsetBytes+$a.lengthBytes -le $end -and
   $b.offsetBytes+$b.lengthBytes -le $end -and
   ($a.offsetBytes -ge ($b.offsetBytes+$b.lengthBytes) -or
    $b.offsetBytes -ge ($a.offsetBytes+$a.lengthBytes)) -and
   $candidate.lengthBytes -eq ($a.lengthBytes+$b.lengthBytes) -and
   $candidate.lengthBytes -le 1056 -and
   $candidate.candidateKey -ceq ('3mf:{0}+{1},{2}+{3}' -f $a.offsetBytes,$a.lengthBytes,$b.offsetBytes,$b.lengthBytes)
  ) 'ordered_nonoverlap_unique_source_spans'
  Assert-C5V1 (-not $ambig.ContainsKey($candidate.candidateKey)) 'distinct_extent_keys'
  $ambig[$candidate.candidateKey]=$true
  [byte[]]$joined=[byte[]]::new([int]$candidate.lengthBytes)
  [Array]::Copy($Image,[int]$a.offsetBytes,$joined,0,[int]$a.lengthBytes)
  [Array]::Copy($Image,[int]$b.offsetBytes,$joined,[int]$a.lengthBytes,[int]$b.lengthBytes)
  if((Get-A3DSha256 $joined) -ceq $OriginalSha){$exact++}else{$different++}
 }
 return [pscustomobject]@{exact=$exact;different=$different}
}
function Invoke-C5V1OneCase {
 param([byte[]]$Image,[string]$Name,[string]$OriginalSha,[long]$Start,[int]$Window,
 [bool]$Large,[string]$ExpectedDecision,[int]$ExpectedExact,[int]$ExpectedWrong)
 $imageBefore=Get-A3DSha256 $Image
 $off=[ChappyC5V1MeasuredMemory]::new($Image)
 try{
  $none=Get-ChappyCarvingCandidateEvidenceV1 -Source $off -WindowStartBytes $Start -WindowBytes $Window
  Assert-C5V1 ($none.schemaVersion -eq 'c_candidate_evidence_v1' -and
   $none.status -eq 'disabled' -and $none.decision -eq 'unknown' -and
   $off.Returned -eq 0 -and $off.ReadCalls -eq 0 -and
   @($none.candidateDefinitions).Count -eq 0) ($Name+':disabled_no_source_access')
 }finally{$off.Dispose()}
 $reader=[ChappyC5V1MeasuredMemory]::new($Image)
 try{
  $args=@{Source=$reader;EnableCandidateEvidence=$true
   EnableStandardsShapedSource=$Large;EnableExpandedFiniteHypotheses=$true
   WindowStartBytes=$Start;WindowBytes=$Window;MaxSourceReturnedBytes=81920
   MaxPhysicalReadCalls=512;MaxWorkMilliseconds=30000}
  $result=Get-ChappyCarvingCandidateEvidenceV1 @args
  Assert-C5V1 ($result.status -eq 'partial' -and $result.decision -eq $ExpectedDecision -and
   $result.scanIncomplete -and $result.searchWindowStartBytes -eq $Start -and
   $result.searchWindowBytes -eq $Window -and
   $result.sourceAuthenticity -eq 'not_proven' -and
   $result.sourceReadAttestation -eq 'C_unattested_A_outer_receipt_required' -and
   $result.originalIdentity -eq 'unknown' -and -not $result.originalShaVerified -and
   -not $result.canExport -and -not $result.canRepair -and
   -not $result.canSelectOriginal -and $null -eq $result.selectedOriginal -and
   $result.warnings -contains 'candidate.unscanned_source_unknown' -and
   $result.candidateCount -eq @($result.candidateDefinitions).Count) ($Name+':versioned_guarded_envelope')
  $m=$result.metrics
  Assert-C5V1 ($m.sourceReturnedBytes -eq $reader.Returned -and
   $m.sourceUniqueReturnedBytes -eq $reader.UniqueReturned -and
   $m.sourceReadCalls -eq $reader.ReadCalls -and
   $m.sourceRepeatedReturnedBytes -eq ($reader.Returned-$reader.UniqueReturned) -and
   $m.sourceReturnedBytes -le 81920 -and $m.sourceReadCalls -le 512 -and
   $m.sectorProbes -eq [int]($Window/512) -and
   $m.startSignatures -le 4 -and $m.tailSignatures -le 8 -and
   $m.pairAttempts -le 16 -and $m.candidateCount -le 16 -and
   $m.inMemoryZipValidatorBytes -le 98304 -and
   $m.maxSectorScratchBytes -eq 512 -and $m.maxPairScratchBytes -eq 1056 -and
   $m.processPeakMemoryStatus -eq 'not_measured' -and
   $null -eq $m.processPeakMemoryBytes) ($Name+':C_meter_equals_independent_actual_Stream_Read')
  $score=Get-C5V1Score -Image $Image -Candidates @($result.candidateDefinitions) -OriginalSha $OriginalSha -WindowStart $Start -WindowBytes $Window
  Assert-C5V1 ($score.exact -eq $ExpectedExact -and $score.different -eq $ExpectedWrong) ($Name+':independent_original_SHA_and_CRC_false_join')
  Assert-C5V1 ((Get-A3DSha256 $Image) -ceq $imageBefore) ($Name+':synthetic_source_unchanged')
  Write-Host ('C5-06 V1 CASE name={0} decision={1} items={2} SHA_exact={3} structure_SHA_wrong={4} actualB={5} uniqueB={6} calls={7} probes={8} pairs={9} parserB={10}' -f
   $Name,$result.decision,$result.candidateCount,$score.exact,$score.different,
   $m.sourceReturnedBytes,$m.sourceUniqueReturnedBytes,$m.sourceReadCalls,
   $m.sectorProbes,$m.pairAttempts,$m.inMemoryZipValidatorBytes)
  return [pscustomobject]@{result=$result;score=$score}
 }finally{$reader.Dispose()}
}
function Invoke-C5CandidateEvidenceV1Gate {
 $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
 Import-Module (Join-Path $root 'modules\carving\Chappy.CandidateEvidenceV1.psm1') -Force
 . (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
 . (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
 . (Join-Path $root 'modules\directory\DirectoryScanner.ps1')
 . (Join-Path $PSScriptRoot 'R5VariableZipPairRegression.ps1')
 $clean=New-ChappyA3DCleanFixture -Seed 202611
 $truth=$clean.oracle[1]
 [byte[]]$original=[byte[]]::new([int]$truth.lengthBytes)
 $pos=0
 foreach($span in $truth.extents){
  [Array]::Copy($clean.image,[int]$span.offsetBytes,$original,$pos,[int]$span.lengthBytes)
  $pos+=[int]$span.lengthBytes
 }
 Assert-C5V1 ($pos -eq $original.Length -and (Get-A3DSha256 $original) -ceq $truth.sha256) 'generator_truth_external_only'
 $compact=@(
  [pscustomobject]@{name='M01_control';decision='one_possible';exact=1;different=0},
  [pscustomobject]@{name='alternate_zip_metadata';decision='ambiguous';exact=1;different=1},
  [pscustomobject]@{name='missing_tail';decision='unknown';exact=0;different=0},
  [pscustomobject]@{name='offgrid_plus_two';decision='one_possible';exact=1;different=0},
  [pscustomobject]@{name='nonlisted_first_560';decision='one_possible';exact=1;different=0},
  [pscustomobject]@{name='physical_reverse';decision='one_possible';exact=1;different=0}
 )
 $compactTP=0;$compactTN=0;$compactExtraWrong=0
 $cBytes=0L;$cUnique=0L;$cCalls=0;$cPairs=0
 $referenceImg=$null
 foreach($c in $compact){
  $kind=if($c.name -eq 'physical_reverse'){'M01_control'}else{$c.name}
  $s=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind $kind
  [byte[]]$image=$s.image
  if($c.name -eq 'physical_reverse'){
   [Array]::Clear($image,58880,1024);[Array]::Clear($image,60416,1024)
   [Array]::Copy($original,0,$image,60416,512)
   [Array]::Copy($original,512,$image,58880,($original.Length-512))
  }
  if($c.name -eq 'M01_control'){$referenceImg=$image}
  $one=Invoke-C5V1OneCase -Image $image -Name $c.name -OriginalSha $truth.sha256 -Start 0 -Window 65536 -Large $false -ExpectedDecision $c.decision -ExpectedExact $c.exact -ExpectedWrong $c.different
  $compactTP+=$one.score.exact;$compactExtraWrong+=$one.score.different
  if($c.name -eq 'missing_tail' -and $one.result.decision -eq 'unknown'){$compactTN++}
  $cBytes+=$one.result.metrics.sourceReturnedBytes
  $cUnique+=$one.result.metrics.sourceUniqueReturnedBytes
  $cCalls+=$one.result.metrics.sourceReadCalls
  $cPairs+=$one.result.metrics.pairAttempts
 }
 Assert-C5V1 ($compactTP -eq 5 -and $compactExtraWrong -eq 1 -and $compactTN -eq 1) 'compact_6_case_oracle_scorer'
 # Guard controls use only generated in-memory source; not part of TP/FP counts.
 $blocked=[ChappyC5V1MeasuredMemory]::new($referenceImg)
 try{
  $r=Get-ChappyCarvingCandidateEvidenceV1 -Source $blocked -EnableCandidateEvidence -MaxSourceReturnedBytes 1024
  Assert-C5V1 ($r.status -eq 'partial' -and $r.decision -eq 'incomplete' -and
   $r.candidateCount -eq 0 -and $blocked.Returned -eq 0) 'underquota_preflight_zero_read'
  $r=Get-ChappyCarvingCandidateEvidenceV1 -Source $blocked -EnableCandidateEvidence -WindowStartBytes 513
  Assert-C5V1 ($r.candidateCount -eq 0 -and $blocked.Returned -eq 0) 'misaligned_hint_zero_read'
  $r=Get-ChappyCarvingCandidateEvidenceV1 -Source $blocked -EnableCandidateEvidence -WindowStartBytes 2097152
  Assert-C5V1 ($r.candidateCount -eq 0 -and $blocked.Returned -eq 0) 'out_of_window_zero_read'
 }finally{$blocked.Dispose()}
 $short=[ChappyC5V1True17Eof]::new($referenceImg)
 try{
  $r=Get-ChappyCarvingCandidateEvidenceV1 -Source $short -EnableCandidateEvidence
  Assert-C5V1 ($r.decision -eq 'incomplete' -and $r.candidateCount -eq 0 -and
   $r.metrics.sourceReturnedBytes -eq 17 -and $r.metrics.sourceUniqueReturnedBytes -eq 17 -and
   $r.metrics.sourceReadCalls -eq 2 -and $r.metrics.zeroByteReadCalls -eq 1 -and
   $short.Returned -eq 17 -and $short.ReadCalls -eq 2) 'physical_17B_then_true_0_EOF'
 }finally{$short.Dispose()}
 $capped=[ChappyC5V1MeasuredMemory]::new($referenceImg)
 try{
  $r=Get-ChappyCarvingCandidateEvidenceV1 -Source $capped -EnableCandidateEvidence -MaxPhysicalReadCalls 2
  Assert-C5V1 ($r.decision -eq 'incomplete' -and $r.candidateCount -eq 0 -and
   $r.metrics.sourceReadCalls -le 3 -and $r.metrics.sourceReturnedBytes -le 1024) 'read_call_overflow_no_early_winner'
 }finally{$capped.Dispose()}
 $writable=[IO.MemoryStream]::new($referenceImg,$true)
 try{
  $r=Get-ChappyCarvingCandidateEvidenceV1 -Source $writable -EnableCandidateEvidence
  Assert-C5V1 ($r.decision -eq 'incomplete' -and $r.candidateCount -eq 0 -and
   $r.metrics.sourceReturnedBytes -eq 0) 'writable_denied'
 }finally{$writable.Dispose()}
 $nonmemory=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($referenceImg,$false))
 try{
  $r=Get-ChappyCarvingCandidateEvidenceV1 -Source $nonmemory -EnableCandidateEvidence
  Assert-C5V1 ($r.decision -eq 'incomplete' -and $r.candidateCount -eq 0 -and
   $nonmemory.BytesRead -eq 0) 'nonmemory_wrappers_not_authentic_memory_source'
 }finally{$nonmemory.Dispose()}
 $r3Count=0;$r3Exact=0;$r3RootUnknown=0;$r3Bytes=0L;$r3Unique=0L;$r3Calls=0;$r3Pairs=0
 foreach($spc in @(1,2)){
  $fx=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
  [byte[]]$img=$fx.image
  $before=Get-A3DSha256 $img
  $bsource=[IO.MemoryStream]::new($img,$false)
  try{$geo=Get-ChappyFat32Geometry -Stream $bsource}finally{$bsource.Dispose()}
  Assert-C5V1 ($geo.clusterCount -eq 65541 -and
    $geo.dataOffsetBytes -gt 65536 -and ($geo.dataOffsetBytes%512) -eq 0) ('r3_spc'+$spc+':B_geometry_only_untrusted')
  $denied=[ChappyC5V1MeasuredMemory]::new($img)
  try{
   $r=Get-ChappyCarvingCandidateEvidenceV1 -Source $denied -EnableCandidateEvidence -WindowStartBytes ([long]$geo.dataOffsetBytes) -WindowBytes 32768
   Assert-C5V1 ($r.decision -eq 'incomplete' -and $denied.Returned -eq 0) ('r3_spc'+$spc+':large_source_default_off')
  }finally{$denied.Dispose()}
  $file=@($fx.oracle | Where-Object {$_.shortName -ceq 'MODEL   3MF'})[0]
  foreach($mode in @('root','data')){
   $start=if($mode -eq 'root'){0L}else{[long]$geo.dataOffsetBytes}
   $kind=('r3_spc{0}_{1}' -f $spc,$mode)
   $want=if($mode -eq 'data'){'one_possible'}else{'unknown'}
   $exact=if($mode -eq 'data'){1}else{0}
   $result=Invoke-C5V1OneCase -Image $img -Name $kind -OriginalSha $file.sha256 -Start $start -Window 32768 -Large $true -ExpectedDecision $want -ExpectedExact $exact -ExpectedWrong 0
   $r3Count++;$r3Exact+=$result.score.exact
   if($mode -eq 'root' -and $result.result.candidateCount -eq 0){$r3RootUnknown++}
   $r3Bytes+=$result.result.metrics.sourceReturnedBytes
   $r3Unique+=$result.result.metrics.sourceUniqueReturnedBytes
   $r3Calls+=$result.result.metrics.sourceReadCalls
   $r3Pairs+=$result.result.metrics.pairAttempts
  }
  Assert-C5V1 ((Get-A3DSha256 $img) -ceq $before) ('r3_spc'+$spc+':sha_unchanged')
  $fx=$null;$img=$null;[GC]::Collect()
 }
 Assert-C5V1 ($r3Count -eq 4 -and $r3Exact -eq 2 -and $r3RootUnknown -eq 2) 'R3_both_FAT32_cluster_sizes_root_vs_data'
 Write-Host ('C5-06 V1 SUMMARY compact=6 case_TP=5 FP=0 FN=0 TN=1 CRC_consistent_original_SHA_wrong=1 compact_returned_B={0} compact_unique_B={1} compact_calls={2} compact_pairs={3} R3_trials={4} R3_exact={5} R3_root_UNKNOWN={6} R3_returned_B={7} R3_unique_B={8} R3_calls={9} R3_pairs={10} false_original_claims=0 A_tokens=0 process_peak_RAM=not_measured' -f
  $cBytes,$cUnique,$cCalls,$cPairs,$r3Count,$r3Exact,$r3RootUnknown,$r3Bytes,$r3Unique,$r3Calls,$r3Pairs)
 Write-Host 'PASS: C5-06 production versioned bounded memory-only C candidate API, R2 and R3 independent artificial SHA, false join and EOF guards'
}
