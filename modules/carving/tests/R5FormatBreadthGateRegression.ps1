#requires -Version 5.1
# C5-02 generated-only regression; SHA oracle stays outside C production module.
function Assert-CBreadth([bool]$Ok,[string]$Why) {
 if(-not $Ok){throw ('C5_02_BREADTH_FAIL: '+$Why)}
}
function New-CBreadthAscii([int]$N) {
 $v=New-Object 'System.Collections.Generic.List[string]'
 $v.Add('solid mesh')
 for($i=0;$i -lt $N;$i++){
  foreach($s in @('facet normal 0 0 1','outer loop','vertex 0 0 0','vertex 1 0 0','vertex 0 1 0','endloop','endfacet')){$v.Add($s)}
 }
 $v.Add('endsolid mesh')
 return ,[Text.Encoding]::ASCII.GetBytes(([string]::Join([char]10,$v)+[char]10))
}
function New-CBreadthBinary([int]$N,[bool]$Shadow) {
 [byte[]]$b=[byte[]]::new(512)
 [byte[]]$h=[Text.Encoding]::ASCII.GetBytes($(if($Shadow){'solid shadow'}else{'synthetic mesh'}))
 [Array]::Copy($h,0,$b,0,$h.Length)
 [Array]::Copy([BitConverter]::GetBytes([uint32]$N),0,$b,80,4)
 for($f=0;$f -lt $N;$f++){
  $at=84+50*$f
  foreach($j in @(2,6,10)){[Array]::Copy([BitConverter]::GetBytes([single]1),0,$b,($at+4*$j),4)}
 }
 return ,$b
}
function New-CBreadthStlCase([string]$Name){
 $ascii=$Name.StartsWith('a_')
 $n=if($Name -in @('a_1','a_3','a_4','a_5')){[int]$Name.Substring(2)}elseif($Name -eq 'b_8' -or $Name -eq 'b_9'){8}else{2}
 if(-not $ascii){$n=if($Name -in @('b_8','b_9')){8}else{4}}
 [byte[]]$original=if($ascii){New-CBreadthAscii $n}else{New-CBreadthBinary $n ($Name -eq 'b_solid')}
 [byte[]]$b=[byte[]]$original.Clone()
 switch($Name){
  'a_modified' {$b=[Text.Encoding]::ASCII.GetBytes(([Text.Encoding]::ASCII.GetString($b)).Replace('vertex 1 0 0','vertex 2 0 0'))}
  'a_badfacet' {$b=[Text.Encoding]::ASCII.GetBytes(([Text.Encoding]::ASCII.GetString($b)).Replace('endfacet','endfacex'))}
  'a_wrongend' {$b=[Text.Encoding]::ASCII.GetBytes(([Text.Encoding]::ASCII.GetString($b)).Replace('endsolid mesh','endsolid other'))}
  'a_nan' {$b=[Text.Encoding]::ASCII.GetBytes(([Text.Encoding]::ASCII.GetString($b)).Replace('facet normal 0 0 1','facet normal NaN 0 1'))}
  'a_control' {$pos=([Text.Encoding]::ASCII.GetString($b)).IndexOf('vertex',[StringComparison]::Ordinal);$b[$pos]=1}
  'a_trunc' {$size=$b.Length-('endsolid mesh'+[char]10).Length;[byte[]]$tr=[byte[]]::new($size);[Array]::Copy($b,$tr,$size);$b=$tr}
  'b_modified' {[Array]::Copy([BitConverter]::GetBytes([single]2),0,$b,(84+4*6),4)}
  'b_9' {[Array]::Copy([BitConverter]::GetBytes([uint32]9),0,$b,80,4)}
  'b_nan' {[Array]::Copy([BitConverter]::GetBytes([uint32]0x7fc00000),0,$b,(84+4*6),4)}
  'b_attr' {$b[84+48]=1}
  'b_zero' {for($f=0;$f -lt 4;$f++){for($j=3;$j -lt 12;$j++){[Array]::Clear($b,(84+50*$f+4*$j),4)}}}
  'b_header' {$b[0]=255}
 }
 return [pscustomobject]@{bytes=$b;original=$original;ascii=$ascii}
}
function Invoke-CBreadthStl {
 $all=@('a_1','a_2','a_3','a_4','a_modified','a_5','a_badfacet','a_wrongend','a_nan','a_control','a_trunc',
  'b_4','b_8','b_solid','b_modified','b_9','b_nan','b_attr','b_zero','b_header')
 $positives=@('a_1','a_2','a_3','a_4','a_modified','b_4','b_8','b_solid','b_modified')
 $tp=0;$fp=0;$tn=0;$fn=0;$shaExact=0;$shaDifferent=0;$physical=0L;$calls=0;$unknown=0
 foreach($name in $all){
  $data=New-CBreadthStlCase $name
  Assert-CBreadth ($data.bytes.Length -le 512 -and $data.bytes.Length -gt 50) ($name+':sector_sized')
  [byte[]]$img=[byte[]]::new(131072)
  [Array]::Copy($data.bytes,0,$img,10240,$data.bytes.Length)
  $sha=Get-A3DSha256 $img
  $off=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($img,$false))
  try{
   $disabled=Get-ChappyStlCandidates -Stream $off
   Assert-CBreadth ($disabled.status -eq 'disabled' -and $off.BytesRead -eq 0) ($name+':off_zero')
  }finally{$off.Dispose()}
  $stream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($img,$false))
  try{
   $res=Get-ChappyStlCandidates -Stream $stream -EnableStlEvidence -MaxScanBytes 65536 -MaxSourceBytes 65536 -MaxSectorProbes 128 -MaxCandidates 16 -MaxValidatorBytes 65536
   Assert-CBreadth ($res.status -eq 'partial' -and $res.scanIncomplete -and $res.metrics.bytesRead -eq 65536 -and
    $stream.BytesRead -eq 65536 -and $res.metrics.readRequests -eq 128 -and $res.metrics.entriesChecked -eq 128 -and
    $res.metrics.validatorBytesRead -eq 65536 -and $res.metrics.maxScratchSectorBytes -eq 512 -and
    @($res.items).Count -le 1) ($name+':physical_budget')
   $physical+=$stream.BytesRead;$calls+=$res.metrics.readRequests
  }finally{$stream.Dispose()}
  Assert-CBreadth ((Get-A3DSha256 $img) -ceq $sha) ($name+':source_immutable')
  $expectedLength=if($data.ascii){$data.bytes.Length}else{84+50*[BitConverter]::ToUInt32($data.bytes,80)}
  $hits=@($res.items | Where-Object {$_.offsetBytes -eq 10240 -and $_.lengthBytes -eq $expectedLength -and
    $_.format -eq $(if($data.ascii){'stl_ascii'}else{'stl_binary'})})
  $valid=$name -in $positives
  if($valid){if($hits.Count -eq 1){$tp++}else{$fn++}}else{if($hits.Count -gt 0){$fp++}else{$tn++}}
  if($hits.Count -eq 1){
   Assert-CBreadth ($valid -and $hits[0].confidence -eq 'probable' -and $hits[0].originalIdentity -eq 'unknown' -and
    $hits[0].integrityScope -eq 'structural_only_not_original_file_integrity' -and
    $null -eq $hits[0].PSObject.Properties['sourceToken']) ($name+':no_original_claim')
   [byte[]]$slice=[byte[]]::new([int]$hits[0].lengthBytes)
   [Array]::Copy($img,10240,$slice,0,$slice.Length)
   if((Get-A3DSha256 $slice) -ceq (Get-A3DSha256 $data.original)){$shaExact++}else{$shaDifferent++}
  }else{$unknown++}
  Write-Host ('C5-02 STL CASE={0} truth={1} found={2} physicalB={3} calls={4}' -f $name,$valid,($hits.Count -eq 1),$res.metrics.bytesRead,$res.metrics.readRequests)
 }
 Assert-CBreadth ($all.Count -eq 20 -and $tp -eq 9 -and $fp -eq 0 -and $fn -eq 0 -and $tn -eq 11 -and
  $shaExact -eq 7 -and $shaDifferent -eq 2) 'stl_frozen_confusion_20'
 Write-Host ('C5-02 STL SUMMARY cases=20 TP={0} FP={1} FN={2} TN={3} exact_SHA={4} structural_SHA_different={5} unknown={6} actual_returned_B={7} unique_observed_B={8} Read_calls={9} validator_sector_B={10} original_claims=0' -f $tp,$fp,$fn,$tn,$shaExact,$shaDifferent,$unknown,$physical,$physical,$calls,$physical)
}
function New-CBreadthGcodeCase([string]$Name){
 $e=[char]10
 $base=[string]::Join($e,@('G28','G1 X0 Y0','G1 X10 Y5 E0.2','G1 X20 Y10','M104 S200','M84'))+$e
 $s=$base
 switch($Name){
  'valid_comments' {$s='; G28 in comment is NOT executable'+$e+$base}
  'valid_inline' {$s=$base.Replace('G28'+$e,'G28 ;home'+$e).Replace('G1 X0 Y0','G1 X0 Y0 ;motion')}
  'valid_changed' {$s=$base.Replace('G1 X10 Y5','G1 X11 Y5')}
  'valid_signed' {$s=$base.Replace('G1 X10 Y5','G1 X-1.5 Y+.4')}
  'valid_shadow' {$s=';generated artificial header'+$e+';M112 comment only'+$e+$base}
  'neg_M112' {$s=$base.Replace('M84','M112')}
  'neg_M500' {$s=$base.Replace('M84','M500')}
  'neg_comments' {$s=(';G28 some text'+$e)*8}
  'neg_no_motion' {$s=[string]::Join($e,@('G28','G90','G91','G92 X0','M104 S200','M84',';no XYZ motion in file'))+$e}
  'neg_no_home' {$s=$base.Replace('G28'+$e,'G90'+$e)}
  'neg_unterminated' {$s=$base.Substring(0,$base.Length-1)}
  'neg_bad_args' {$s=$base.Replace('G1 X10 Y5','G1 Xoops Y5')}
  'neg_long_line' {$s=';'+('A'*161)+$e+$base}
  'neg_many_lines' {$s=(';ok'+$e)*129+$base}
  'neg_numbered' {$s=$base.Replace('G1 X10 Y5','N23 G1 X10 Y5')}
  'neg_only_comment_motion' {$s=$base.Replace('G1 X0 Y0',';G1 X0 Y0').Replace('G1 X10 Y5',';G1 X10 Y5').Replace('G1 X20 Y10',';G1 X20 Y10')}
  'neg_random' {$s='ordinary invented text not G-code'+$e+'other unrelated words'+$e+'nothing here'+$e}
 }
 [byte[]]$b=[Text.Encoding]::ASCII.GetBytes($s)
 if($Name -eq 'neg_utf8'){$b=[Text.Encoding]::ASCII.GetBytes($base);$b[11]=227}
 if($Name -eq 'neg_null'){$b=[Text.Encoding]::ASCII.GetBytes($base);$b[11]=0}
 return [pscustomobject]@{bytes=$b;original=[Text.Encoding]::ASCII.GetBytes($base)}
}
function Invoke-CBreadthGcode{
 $all=@('valid_basic','valid_comments','valid_inline','valid_changed','valid_signed','valid_shadow',
  'neg_M112','neg_M500','neg_comments','neg_no_motion','neg_no_home','neg_unterminated','neg_bad_args',
  'neg_long_line','neg_many_lines','neg_numbered','neg_only_comment_motion','neg_random','neg_utf8','neg_null')
 $tp=0;$fp=0;$fn=0;$tn=0;$shaExact=0;$shaDifferent=0;$physical=0L;$calls=0;$unknown=0
 foreach($name in $all){
  $datum=New-CBreadthGcodeCase $name
  Assert-CBreadth ($datum.bytes.Length -ge 48 -and $datum.bytes.Length -le 8192) ($name+':supplied_48_to_8192_B_span')
  [byte[]]$img=[byte[]]::new(131072)
  [Array]::Copy($datum.bytes,0,$img,10240,$datum.bytes.Length)
  $sha=Get-A3DSha256 $img
  $off=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($img,$false))
  try{
   $disabled=Get-ChappyGcodeEvidence -Stream $off -OffsetBytes 10240 -LengthBytes $datum.bytes.Length
   Assert-CBreadth ($disabled.status -eq 'disabled' -and $off.BytesRead -eq 0 -and @($disabled.items).Count -eq 0) ($name+':default_off_zero')
  }finally{$off.Dispose()}
  $stream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($img,$false))
  try{
   $res=Get-ChappyGcodeEvidence -Stream $stream -OffsetBytes 10240 -LengthBytes $datum.bytes.Length -EnableGcodeEvidence
   Assert-CBreadth ($res.metrics.bytesRead -eq $stream.BytesRead -and
    $res.metrics.uniquePhysicalBytesRead -eq $stream.BytesRead -and
    $res.metrics.readRequests -eq 1 -and $res.metrics.maxCandidateScratchBytes -eq 8192 -and
    $res.metrics.peakProcessMemoryStatus -eq 'not_measured') ($name+':exact_returned_B')
   $physical+=$stream.BytesRead;$calls+=$res.metrics.readRequests
  }finally{$stream.Dispose()}
  Assert-CBreadth ((Get-A3DSha256 $img) -ceq $sha) ($name+':unmodified_source')
  $valid=$name.StartsWith('valid_')
  $accepted=($res.status -eq 'ok' -and $res.decision -eq 'format_consistent' -and @($res.items).Count -eq 1)
  if($valid){if($accepted){$tp++}else{$fn++}}else{if($accepted){$fp++}else{$tn++}}
  if($accepted){
   $i=$res.items[0]
   Assert-CBreadth ($valid -and $i.offsetBytes -eq 10240 -and $i.lengthBytes -eq $datum.bytes.Length -and
    $i.format -eq 'gcode' -and $i.confidence -eq 'probable' -and $i.originalIdentity -eq 'unknown' -and
    $i.integrityScope -eq 'heuristic_text_only_not_original_file_integrity' -and
    $i.sourceOrigin -eq 'unattributed_without_A_meter' -and
    $null -eq $i.PSObject.Properties['sourceToken']) ($name+':no_original_or_printer_safety_claim')
   if((Get-A3DSha256 $datum.bytes) -ceq (Get-A3DSha256 $datum.original)){$shaExact++}else{$shaDifferent++}
  }else{
   $unknown++
   Assert-CBreadth ($res.status -eq 'partial' -and $res.decision -eq 'unknown' -and
    @($res.items).Count -eq 0) ($name+':outside_strict_syntax_is_unknown')
  }
  Write-Host ('C5-02 GCODE CASE={0} truth={1} proposed={2} sourceB={3} calls={4}' -f $name,$valid,$accepted,$res.metrics.bytesRead,$res.metrics.readRequests)
 }
 Assert-CBreadth ($all.Count -eq 20 -and $tp -eq 6 -and $fp -eq 0 -and $fn -eq 0 -and $tn -eq 14 -and
  $shaExact -eq 1 -and $shaDifferent -eq 5 -and $unknown -eq 14) 'gcode_frozen_confusion_20'
 [byte[]]$img=[byte[]]::new(131072)
 [byte[]]$clean=(New-CBreadthGcodeCase 'valid_basic').bytes
 [Array]::Copy($clean,0,$img,10240,$clean.Length)
 $legacyStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($img,$false))
 try{
  $legacy=Get-ChappyCarvingCandidates -Stream $legacyStream -MaxScanBytes 65536 -ExtraValidationReadBytes 32768 -MaxFileBytes 4096 -MaxCandidates 16 -MaxProbes 16 -MaxProbeBytes 8192
  Assert-CBreadth (@($legacy.items|Where-Object {$_.format -eq 'gcode' -and $_.offsetBytes -eq 10240}).Count -eq 1 -and
   $legacy.metrics.bytesRead -eq $legacyStream.BytesRead -and $legacyStream.BytesRead -le 98304) 'legacy_discovery_unchanged'
 }finally{$legacyStream.Dispose()}
 $short=[ChappyCStl17Eof]::new([IO.MemoryStream]::new($img,$false))
 try{
  $res=Get-ChappyGcodeEvidence -Stream $short -EnableGcodeEvidence -OffsetBytes 10240 -LengthBytes $clean.Length
  Assert-CBreadth ($res.status -eq 'partial' -and $res.decision -eq 'unknown' -and @($res.items).Count -eq 0 -and
   $short.BytesReturned -eq 17 -and $res.metrics.bytesRead -eq 17 -and
   $res.metrics.uniquePhysicalBytesRead -eq 17 -and $short.ReadCalls -eq 2 -and $res.metrics.readRequests -eq 2) 'true_17_B_then_zero_EOF'
 }finally{$short.Dispose()}
 $under=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($img,$false))
 try{
  $res=Get-ChappyGcodeEvidence -Stream $under -EnableGcodeEvidence -OffsetBytes 10240 -LengthBytes $clean.Length -MaxSourceBytes 1
  Assert-CBreadth ($res.status -eq 'partial' -and @($res.items).Count -eq 0 -and $under.BytesRead -eq 0) 'quota_zero_reads'
  $res=Get-ChappyGcodeEvidence -Stream $under -EnableGcodeEvidence -OffsetBytes 131060 -LengthBytes $clean.Length
  Assert-CBreadth ($res.status -eq 'partial' -and $under.BytesRead -eq 0) 'out_of_bounds_zero_reads'
 }finally{$under.Dispose()}
 $writable=[IO.MemoryStream]::new($img,$true)
 try{
  $res=Get-ChappyGcodeEvidence -Stream $writable -EnableGcodeEvidence -OffsetBytes 10240 -LengthBytes $clean.Length
  Assert-CBreadth ($res.status -eq 'error' -and $res.decision -eq 'unknown' -and $res.metrics.bytesRead -eq 0) 'writable_refused'
 }finally{$writable.Dispose()}
 Write-Host ('C5-02 GCODE SUMMARY cases=20 TP={0} FP={1} FN={2} TN={3} source_original_SHA_exact={4} changed_but_structure={5} unknown={6} actual_returned_B={7} unique_observed_B={8} Read_calls={9} original_claims=0' -f $tp,$fp,$fn,$tn,$shaExact,$shaDifferent,$unknown,$physical,$physical,$calls)
}
function Invoke-CFormatBreadthGate {
 Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Chappy.StlEvidence.psm1') -Force
 . (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'tests\helpers\New-Chappy3DCleanFixture.ps1')
 Invoke-CBreadthStl
 Invoke-CBreadthGcode
 Write-Host 'PASS: C5-02 STL 1-4 facet and strict G-code structural-only bounded acceptance'
}
