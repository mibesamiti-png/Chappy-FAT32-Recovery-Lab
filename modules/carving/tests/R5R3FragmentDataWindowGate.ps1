#requires -Version 5.1
# C5-03 standard FAT32 artificial test: B derives source data window from BPB,
# external scorer alone reads oracle physical fragments/original SHA.
function Assert-CR3Pair([bool]$Ok,[string]$Why){
 if(-not $Ok){throw ('C5_03_R3_FAIL: '+$Why)}
}
function Invoke-C5R3PairDataWindowGate {
 $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
 Import-Module (Join-Path $root 'modules\carving\Chappy.FragmentEvidence.psm1') -Force
 . (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
 . (Join-Path $root 'modules\directory\DirectoryScanner.ps1')
 . (Join-Path $PSScriptRoot 'R5FragmentModuleGateRegression.ps1')
 $cases=0;$dataExact=0;$rootExact=0;$wrong=0;$actual=0L;$unique=0L
 $calls=0;$parser=0L;$pairs=0;$sectors=0
 foreach($spc in @(1,2)){
  $fx=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
  [byte[]]$img=$fx.image
  $originalInputSha=Get-A3DSha256 $img
  $geoStream=[IO.MemoryStream]::new($img,$false)
  try{$geo=Get-ChappyFat32Geometry -Stream $geoStream}finally{$geoStream.Dispose()}
  Assert-CR3Pair ($geo.clusterCount -eq 65541 -and $geo.dataOffsetBytes -gt 65536 -and
   ($geo.dataOffsetBytes%512) -eq 0 -and $geo.dataOffsetBytes -le $img.Length-32768 -and
   $geo.clusterSizeBytes -eq $spc*512) ('spc'+$spc+':independent_B_BPBand_geometry')
  $denied=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($img,$false))
  try{
   $threw=$false
   try{Get-ChappyFragmentCandidates -Source $denied -EnableFragmentEvidence -WindowBytes 32768|Out-Null}catch{$threw=$true}
   Assert-CR3Pair ($threw -and $denied.ReadCalls -eq 0 -and $denied.BytesRead -eq 0) ('spc'+$spc+':large_source_default_denied')
  }finally{$denied.Dispose()}
  $disabled=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($img,$false))
  try{
   $disabledResult=Get-ChappyFragmentCandidates -Source $disabled -StartOffsetBytes ([long]$geo.dataOffsetBytes)
   Assert-CR3Pair ($disabledResult.status -eq 'disabled' -and $disabled.ReadCalls -eq 0 -and
    $disabled.BytesRead -eq 0) ('spc'+$spc+':disabled_zero_stream_access')
  }finally{$disabled.Dispose()}
  foreach($mode in @('root','data')){
   $windowStart=if($mode -eq 'root'){0L}else{[long]$geo.dataOffsetBytes}
   $meter=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($img,$false))
   try{
    $args=@{Source=$meter;EnableFragmentEvidence=$true;EnableStandardsShapedSource=$true
     StartOffsetBytes=$windowStart;WindowBytes=32768;IncludeStartPhasePlusTwo=$true
     IncludeFirstPiece560=$true;MaxStarts=4;MaxTails=8;MaxPairs=16
     MaxSourceBytes=81920;MaxValidationBytes=98304;MaxMilliseconds=30000}
    $r=Get-ChappyFragmentCandidates @args
    Assert-CR3Pair ($r.status -eq 'ok' -and $r.scanIncomplete -and
     $r.windowHintOrigin -eq 'caller_unattested' -and $r.searchWindowStartBytes -eq $windowStart -and
     $r.originalIdentity -eq 'unknown' -and $null -eq $r.selectedOriginal -and
     -not $r.canAutoSelectOriginal -and $r.metrics.searchWindowBytes -eq 32768 -and
     $r.metrics.sectorProbes -eq 64 -and $r.metrics.pairAttempts -le 16 -and
     $r.metrics.sourceBytesRead -eq $meter.BytesRead -and $r.metrics.readRequests -eq $meter.ReadCalls -and
     $r.metrics.sourceBytesRead -le 81920 -and $r.metrics.validatorBytesRead -le 98304 -and
     $meter.UniqueBytes -le $meter.BytesRead) ('spc'+$spc+'/'+$mode+':bounded_and_unknown')
    foreach($item in @($r.items)){
     Assert-CR3Pair ($item.originalIdentity -eq 'unknown' -and
      $item.sourceOrigin -eq 'unattributed_without_A_meter' -and
      $null -eq $item.PSObject.Properties['sourceToken'] -and
      @($item.sourceSpans).Count -eq 2 -and
      $item.firstOffset -ge $windowStart -and $item.secondOffset -ge $windowStart -and
      $item.firstOffset+$item.firstBytes -le $windowStart+32768 -and
      $item.secondOffset+$item.secondBytes -le $windowStart+32768) ('spc'+$spc+'/'+$mode+':absolute_physical_spans')
    }
    # Oracle data is used only here AFTER candidate discovery.
    $truth=@($fx.oracle|Where-Object {$_.shortName -ceq 'MODEL   3MF'})[0]
    $score=Get-CFragmentScorer -Image $img -Hypotheses @($r.items) -OriginalSha $truth.sha256
    if($mode -eq 'root'){
     Assert-CR3Pair ($score.exact -eq 0 -and $r.decision -eq 'unknown' -and @($r.items).Count -eq 0) ('spc'+$spc+':root_only_zero')
     $rootExact+=$score.exact
    }else{
     Assert-CR3Pair ($score.exact -eq 1 -and $score.structuralWrong -eq 0 -and
      $r.decision -eq 'one_possible' -and @($r.items).Count -eq 1) ('spc'+$spc+':data_window_true_original_join')
     $dataExact+=$score.exact
     if($spc -eq 1){
      Assert-CR3Pair ($score.exactCandidate.secondOffset -ne ($score.exactCandidate.firstOffset+$score.exactCandidate.firstBytes)) 'spc1_noncontiguous_two_cluster_fragment_placement'
     }
    }
    $cases++;$actual+=$meter.BytesRead;$unique+=$meter.UniqueBytes;$calls+=$meter.ReadCalls
    $parser+=[long]$r.metrics.validatorBytesRead;$pairs+=[int]$r.metrics.pairAttempts
    $sectors+=[int]$r.metrics.sectorProbes;$wrong+=$score.structuralWrong
    Write-Host ('C5-03 R3 CASE spc={0} mode={1} window={2} status={3} decision={4} exact={5} extra_wrong={6} physicalB={7} uniqueB={8} calls={9} parserB={10} pairs={11}' -f
     $spc,$mode,$windowStart,$r.status,$r.decision,$score.exact,$score.structuralWrong,
     $meter.BytesRead,$meter.UniqueBytes,$meter.ReadCalls,$r.metrics.validatorBytesRead,$r.metrics.pairAttempts)
   }finally{$meter.Dispose()}
  }
  Assert-CR3Pair ((Get-A3DSha256 $img) -ceq $originalInputSha) ('spc'+$spc+':unchanged_source_SHA')
  $img=$null;$fx=$null;[GC]::Collect()
 }
 Assert-CR3Pair ($cases -eq 4 -and $dataExact -eq 2 -and $rootExact -eq 0 -and
  $wrong -eq 0 -and $sectors -eq 256) 'both_standard_R3_tracks'
 Write-Host ('C5-03 R3 SUMMARY trials={0} true_SHA_exact_data={1} root={2} structural_SHA_wrong={3} actual_returned_source_B={4} unique_returned_source_B={5} Stream_Read_calls={6} parser_B={7} sectors={8} pairs={9} original_claims=0' -f
  $cases,$dataExact,$rootExact,$wrong,$actual,$unique,$calls,$parser,$sectors,$pairs)
 Write-Host 'PASS: C5-03 R3 independently B-derived data window and bounded 2-piece source probes'
}

# Same fixed +2 phase and 560B length expansion on every invented compact
# case, with no true offsets/lengths passed to the callable C candidate finder.
function Invoke-C5ExpandedCompactGate {
 $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
 Import-Module (Join-Path $root 'modules\carving\Chappy.FragmentEvidence.psm1') -Force
 . (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
 . (Join-Path $PSScriptRoot 'R5VariableZipPairRegression.ps1')
 . (Join-Path $PSScriptRoot 'R5FragmentModuleGateRegression.ps1')
 $clean=New-ChappyA3DCleanFixture -Seed 202611
 $truth=$clean.oracle[1]
 [byte[]]$original=[byte[]]::new([int]$truth.lengthBytes)
 $cursor=0
 foreach($span in $truth.extents){
  [Array]::Copy($clean.image,[int]$span.offsetBytes,$original,$cursor,[int]$span.lengthBytes)
  $cursor+=[int]$span.lengthBytes
 }
 Assert-CR3Pair ($cursor -eq $truth.lengthBytes -and (Get-A3DSha256 $original) -ceq $truth.sha256) 'compact_original_known_only_to_scorer'
 $names=@('M01_control','non512_offgrid_tail','offgrid_first','offgrid_plus_two',
  'nonlisted_first_560','fake_eocd','alternate_zip_metadata','missing_tail','physical_reverse')
 $baseExact=0;$expandedExact=0;$baseFN=0;$expandedFN=0;$wrong=0;$ambiguous=0
 $unknown=0;$physical=0L;$unique=0L;$calls=0;$parser=0L;$pairs=0
 foreach($name in $names){
  $kind=if($name -eq 'physical_reverse'){'M01_control'}else{$name}
  $fx=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind $kind
  [byte[]]$img=$fx.image
  if($name -eq 'physical_reverse'){
   [Array]::Clear($img,58880,1024)
   [Array]::Clear($img,60416,1024)
   [Array]::Copy($original,0,$img,60416,512)
   [Array]::Copy($original,512,$img,58880,($original.Length-512))
  }
  $inputSha=Get-A3DSha256 $img
  $b=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($img,$false))
  try{
   $baseline=Get-ChappyFragmentCandidates -Source $b -EnableFragmentEvidence
   Assert-CR3Pair ($baseline.status -eq 'ok' -and $baseline.metrics.sectorProbes -eq 128 -and
     $baseline.metrics.sourceBytesRead -eq $b.BytesRead) ($name+':old_module_unchanged')
   $scoreBase=Get-CFragmentScorer -Image $img -Hypotheses @($baseline.items) -OriginalSha $truth.sha256
   $baseExact+=$scoreBase.exact
   if($name -ne 'missing_tail' -and $scoreBase.exact -eq 0){$baseFN++}
  }finally{$b.Dispose()}
  $m=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($img,$false))
  try{
   $expanded=Get-ChappyFragmentCandidates -Source $m -EnableFragmentEvidence -IncludeStartPhasePlusTwo -IncludeFirstPiece560
   Assert-CR3Pair ($expanded.status -eq 'ok' -and
     $expanded.originalIdentity -eq 'unknown' -and $null -eq $expanded.selectedOriginal -and
     -not $expanded.canAutoSelectOriginal -and $expanded.metrics.sectorProbes -eq 128 -and
     $expanded.metrics.pairAttempts -le 16 -and $expanded.metrics.sourceBytesRead -eq $m.BytesRead -and
     $expanded.metrics.readRequests -eq $m.ReadCalls -and $expanded.metrics.sourceBytesRead -le 81920 -and
     $expanded.metrics.validatorBytesRead -le 98304) ($name+':expanded_still_bounded_and_unknown')
   $score=Get-CFragmentScorer -Image $img -Hypotheses @($expanded.items) -OriginalSha $truth.sha256
   if($name -eq 'missing_tail'){
    Assert-CR3Pair ($expanded.decision -eq 'unknown' -and $score.exact -eq 0 -and
      @($expanded.items).Count -eq 0) 'missing_tail_fails_unknown'
    $unknown++
   }else{
    Assert-CR3Pair ($score.exact -eq 1) ($name+':one_SHA_exact_external_only')
    $expandedExact+=$score.exact
   }
   if($name -eq 'alternate_zip_metadata'){
    Assert-CR3Pair ($expanded.decision -eq 'ambiguous' -and $score.structuralWrong -eq 1 -and
      @($expanded.items).Count -eq 2) 'CRC_valid_wrong_SHA_stays_ambiguous'
    $ambiguous++
   }
   if($name -eq 'physical_reverse'){
    Assert-CR3Pair ($score.exactCandidate.firstOffset -gt $score.exactCandidate.secondOffset) 'reverse_physical_correct_logical_order'
   }
   $wrong+=$score.structuralWrong;$physical+=$m.BytesRead;$unique+=$m.UniqueBytes
   $calls+=$m.ReadCalls;$pairs+=[int]$expanded.metrics.pairAttempts
   $parser+=[long]$expanded.metrics.validatorBytesRead
   Write-Host ('C5-03 COMPACT CASE={0} baseline={1} broadened={2} exact={3} extra_CRC_wrong_SHA={4} physicalB={5} uniqueB={6} calls={7} pairs={8}' -f
    $name,$baseline.decision,$expanded.decision,$score.exact,$score.structuralWrong,
    $m.BytesRead,$m.UniqueBytes,$m.ReadCalls,$expanded.metrics.pairAttempts)
  }finally{$m.Dispose()}
  Assert-CR3Pair ((Get-A3DSha256 $img) -ceq $inputSha) ($name+':source_immutable')
 }
 Assert-CR3Pair ($names.Count -eq 9 -and $baseExact -eq 6 -and $baseFN -eq 2 -and
   $expandedExact -eq 8 -and $expandedFN -eq 0 -and $wrong -eq 1 -and
   $ambiguous -eq 1 -and $unknown -eq 1) 'compact_two_extra_nonoracle_cases'
 # Deny bad search window with zero physical reads on invented large source.
 [byte[]]$little=[byte[]]::new(65536)
 foreach($off in @(3L,65500L)){
  $meter=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($little,$false))
  try{
   $r=Get-ChappyFragmentCandidates -Source $meter -EnableFragmentEvidence -StartOffsetBytes $off
   Assert-CR3Pair ($r.status -eq 'partial' -and $r.decision -eq 'incomplete' -and
    @($r.items).Count -eq 0 -and $r.metrics.sourceBytesRead -eq 0 -and
    $meter.ReadCalls -eq 0 -and $meter.BytesRead -eq 0) 'invalid_window_preflight_without_io'
  }finally{$meter.Dispose()}
 }
 Write-Host ('C5-03 COMPACT SUMMARY cases=9 original_present=8 missing=1 baseline_TP={0} baseline_FN={1} expanded_TP={2} expanded_FN={3} expanded_TN=1 expanded_FP=0 CRC_consistent_SHA_wrong_extra={4} ambiguous={5} unknown={6} actual_sourceB={7} unique_sourceB={8} Read_calls={9} parserB={10} pair_attempts={11}' -f
  $baseExact,$baseFN,$expandedExact,$expandedFN,$wrong,$ambiguous,$unknown,$physical,$unique,$calls,$parser,$pairs)
}
function Invoke-C5R3PairGate{
 Invoke-C5ExpandedCompactGate
 Invoke-C5R3PairDataWindowGate
 Write-Host 'PASS: C5-03 synthetic R2 broadened hypotheses and R3 B-data-window nonoracle 2-piece gate'
}
