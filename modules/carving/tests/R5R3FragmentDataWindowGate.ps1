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
      Assert-CR3Pair ($score.exactCandidate.secondOffset -lt $score.exactCandidate.firstOffset) 'spc1_reversed_physical_cluster_placement'
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
