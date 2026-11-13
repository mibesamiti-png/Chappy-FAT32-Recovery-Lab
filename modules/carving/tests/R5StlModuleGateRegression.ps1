#requires -Version 5.1
# Team C gate C5-02 independent scorer, strictly artificial inputs.
function Assert-CStlGate([bool]$Okay,[string]$Code) {if(-not $Okay){throw ('C5_02_STL_FAIL: '+$Code)}}
if(-not ('ChappyCStl17Eof' -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class ChappyCStl17Eof:Stream {
 private readonly Stream s;private bool served;
 public long BytesReturned{get;private set;}
 public int ReadCalls{get;private set;}
 public ChappyCStl17Eof(Stream x){if(x.CanWrite)throw new ArgumentException();s=x;}
 public override bool CanRead{get{return true;}}
 public override bool CanSeek{get{return true;}}
 public override bool CanWrite{get{return false;}}
 public override long Length{get{return s.Length;}}
 public override long Position{get{return s.Position;}set{s.Position=value;}}
 public override int Read(byte[] b,int o,int n){ReadCalls++;if(served)return 0;served=true;int v=s.Read(b,o,Math.Min(n,17));BytesReturned+=v;return v;}
 public override long Seek(long p,SeekOrigin o){return s.Seek(p,o);}
 public override void Flush(){}
 public override void SetLength(long n){throw new NotSupportedException();}
 public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
 protected override void Dispose(bool d){if(d)s.Dispose();base.Dispose(d);}
}
'@
}
function Invoke-CStlModuleGateRegression {
 $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
 Import-Module (Join-Path $root 'modules\carving\Chappy.StlEvidence.psm1') -Force
 . (Join-Path $root 'tests\helpers\New-Chappy3DCleanFixture.ps1')
 $fixture=New-ChappyA3DCleanFixture -Seed 202611 -IncludeFormatControls
 $truth=@{};foreach($record in $fixture.oracle){$truth[$record.format]=$record}
 $names=@('clean','binary_vertex_modified','binary_count_invalid','ascii_keyword_invalid','ascii_number_invalid','binary_nan_invalid','binary_all_zero_vertices')
 $tp=0;$tn=0;$fp=0;$fn=0;$exact=0;$changed=0;$sumPhysical=0L;$sumCalls=0;$sumValidation=0L
 foreach($case in $names){
  [byte[]]$img=[byte[]]$fixture.image.Clone()
  $bin=$truth['stl_binary'];$ascii=$truth['stl_ascii']
  $bat=[int]$bin.extents[0].offsetBytes;$aat=[int]$ascii.extents[0].offsetBytes
  switch($case){
   'binary_vertex_modified' {$img[$bat+84+12]=[byte]($img[$bat+84+12] -bxor 1)}
   'binary_count_invalid' {[Array]::Copy([BitConverter]::GetBytes([uint32]65535),0,$img,($bat+80),4)}
   'ascii_keyword_invalid' {
    $text=[Text.Encoding]::ASCII.GetString($img,$aat,[int]$ascii.lengthBytes)
    $pos=$text.IndexOf('endfacet',[StringComparison]::Ordinal)
    Assert-CStlGate ($pos -ge 0) 'ascii_keyword_position'
    $img[$aat+$pos+7]=[byte][char]'x'
   }
   'ascii_number_invalid' {
    $text=[Text.Encoding]::ASCII.GetString($img,$aat,[int]$ascii.lengthBytes)
    $pos=$text.IndexOf('vertex 0',[StringComparison]::Ordinal)
    Assert-CStlGate ($pos -ge 0) 'ascii_number_position'
    $img[$aat+$pos+7]=[byte][char]'x'
   }
   'binary_nan_invalid' {[Array]::Copy([BitConverter]::GetBytes([uint32]0x7FC00000),0,$img,($bat+84+12),4)}
   'binary_all_zero_vertices' {
    for($f=0;$f -lt 4;$f++){for($j=3;$j -lt 12;$j++){[Array]::Clear($img,($bat+84+50*$f+4*$j),4)}}
   }
  }
  $before=Get-A3DSha256 $img
  $off=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($img,$false))
  try{$none=Get-ChappyStlCandidates -Stream $off
   Assert-CStlGate ($none.status -eq 'disabled' -and @($none.items).Count -eq 0 -and $off.BytesRead -eq 0) ($case+':default_off_zero_io')
  }finally{$off.Dispose()}
  $read=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($img,$false))
  try{
   $r=Get-ChappyStlCandidates -Stream $read -EnableStlEvidence -MaxScanBytes 65536 -MaxSourceBytes 65536 -MaxSectorProbes 128 -MaxCandidates 16 -MaxValidatorBytes 65536 -MaxWorkMilliseconds 30000
   Assert-CStlGate ($r.status -eq 'partial' -and $r.scanIncomplete -and $r.originalIdentity -eq 'unknown' -and $r.metrics.bytesRead -eq $read.BytesRead -and $r.metrics.bytesRead -eq 65536 -and $r.metrics.readRequests -eq 128 -and $r.metrics.entriesChecked -eq 128 -and $r.metrics.scannedBytes -eq 65536 -and $r.metrics.validatorBytesRead -eq 65536 -and $r.metrics.maxScratchSectorBytes -eq 512 -and @($r.items).Count -le 16) ($case+':bounded_source_and_parser')
   $sumPhysical+=$read.BytesRead;$sumCalls+=$r.metrics.readRequests;$sumValidation+=$r.metrics.validatorBytesRead
  }finally{$read.Dispose()}
  Assert-CStlGate ((Get-A3DSha256 $img) -ceq $before) ($case+':SHA_unchanged')
  foreach($format in @('stl_binary','stl_ascii')){
   $truthRecord=$truth[$format];$valid=$true
   if($format -eq 'stl_binary' -and $case -in @('binary_count_invalid','binary_nan_invalid','binary_all_zero_vertices')){$valid=$false}
   if($format -eq 'stl_ascii' -and $case -in @('ascii_keyword_invalid','ascii_number_invalid')){$valid=$false}
   $found=@($r.items|Where-Object {$_.format -eq $format -and $_.offsetBytes -eq $truthRecord.extents[0].offsetBytes -and $_.lengthBytes -eq $truthRecord.lengthBytes})
   Assert-CStlGate ($found.Count -le 1) ($case+':no_duplicate')
   if($found.Count -eq 1){
    if($valid){$tp++}else{$fp++}
    Assert-CStlGate ($found[0].confidence -eq 'probable' -and $found[0].integrityScope -eq 'structural_only_not_original_file_integrity' -and $found[0].originalIdentity -eq 'unknown' -and $null -eq $found[0].PSObject.Properties['sourceToken']) ($case+':no_original_claim')
    [byte[]]$slice=[byte[]]::new([int]$found[0].lengthBytes)
    [Array]::Copy($img,[int]$found[0].offsetBytes,$slice,0,$slice.Length)
    if((Get-A3DSha256 $slice) -ceq $truthRecord.sha256){$exact++}else{$changed++}
   }else{if($valid){$fn++}else{$tn++}}
  }
  Assert-CStlGate (@($r.items|Where-Object {$_.offsetBytes -ne $bin.extents[0].offsetBytes -and $_.offsetBytes -ne $ascii.extents[0].offsetBytes}).Count -eq 0) ($case+':no_nontruth_candidates')
  Write-Host ('C5-02 STL case={0} candidates={1} sourceB={2} source_calls={3} parserB={4}' -f $case,@($r.items).Count,$r.metrics.bytesRead,$r.metrics.readRequests,$r.metrics.validatorBytesRead)
 }
 Assert-CStlGate ($tp -eq 9 -and $fp -eq 0 -and $fn -eq 0 -and $tn -eq 5 -and $exact -eq 8 -and $changed -eq 1) 'seven_case_two_format_confusion_table'
 [byte[]]$clean=$fixture.image
 $short=[ChappyCStl17Eof]::new([IO.MemoryStream]::new($clean,$false))
 try{$r=Get-ChappyStlCandidates -Stream $short -EnableStlEvidence
  Assert-CStlGate ($r.status -eq 'partial' -and @($r.items).Count -eq 0 -and $short.BytesReturned -eq 17 -and $r.metrics.bytesRead -eq 17 -and $r.metrics.readRequests -eq $short.ReadCalls) 'true_17B_EOF_no_candidates'
 }finally{$short.Dispose()}
 $under=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($clean,$false))
 try{
  foreach($kwargs in @(@{MaxSourceBytes=1024},@{MaxSectorProbes=1},@{MaxValidatorBytes=1024},@{StartOffset=($clean.Length-17)})){
   $r=Get-ChappyStlCandidates -Stream $under -EnableStlEvidence @kwargs
   Assert-CStlGate ($r.status -eq 'partial' -and @($r.items).Count -eq 0 -and $under.BytesRead -eq 0) 'preflight_underquota_or_out_of_range'
  }
 }finally{$under.Dispose()}
 $writable=[IO.MemoryStream]::new($clean,$true)
 try{$r=Get-ChappyStlCandidates -Stream $writable -EnableStlEvidence
  Assert-CStlGate ($r.status -eq 'error' -and @($r.items).Count -eq 0) 'reject_writable_source'
 }finally{$writable.Dispose()}
 [byte[]]$flood=[byte[]]::new(65536)
 for($i=0;$i -lt 24;$i++){[Array]::Copy($clean,[int]$truth['stl_binary'].extents[0].offsetBytes,$flood,($i*512),512)}
 $floodSha=Get-A3DSha256 $flood
 $fs=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($flood,$false))
 try{$r=Get-ChappyStlCandidates -Stream $fs -EnableStlEvidence -MaxCandidates 1
  Assert-CStlGate ($r.status -eq 'partial' -and @($r.items).Count -eq 0 -and $fs.BytesRead -eq $r.metrics.bytesRead -and $r.metrics.bytesRead -le 65536) 'candidate_flood_fail_closed'
 }finally{$fs.Dispose()}
 Assert-CStlGate ((Get-A3DSha256 $flood) -ceq $floodSha) 'flood_immutable'
 # G-code regression reuses existing production C scanner; new STL module does not change it.
 [byte[]]$gImage=[byte[]]::new(65536)
 $gText=([string]::Join([char]10,@(';SYNTHETIC','G28','G1 X10','G1 X11','G1 X12','M104 S200','M84'))+[char]10)
 [byte[]]$gCode=[Text.Encoding]::ASCII.GetBytes($gText)
 [Array]::Copy($gCode,0,$gImage,10240,$gCode.Length)
 $gStart=10240+(';SYNTHETIC'+[char]10).Length
 $gs=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($gImage,$false))
 try{$g=Get-ChappyCarvingCandidates -Stream $gs -MaxScanBytes 65536 -ExtraValidationReadBytes 32768 -MaxCandidates 16 -MaxProbes 16 -MaxFileBytes 4096 -MaxProbeBytes 8192
  Assert-CStlGate (@($g.items|Where-Object {$_.format -eq 'gcode' -and $_.offsetBytes -eq $gStart}).Count -eq 1 -and $gs.BytesRead -eq $g.metrics.bytesRead -and $g.metrics.bytesRead -le 98304) 'production_gcode_positive'
 }finally{$gs.Dispose()}
 [byte[]]$badG=[byte[]]::new(65536)
 [byte[]]$shortG=[Text.Encoding]::ASCII.GetBytes(('G28'+[char]10+'M104 S200'+[char]10))
 [Array]::Copy($shortG,0,$badG,10240,$shortG.Length)
 $gs=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($badG,$false))
 try{$g=Get-ChappyCarvingCandidates -Stream $gs -MaxScanBytes 65536 -ExtraValidationReadBytes 32768 -MaxCandidates 16 -MaxProbes 16 -MaxFileBytes 4096 -MaxProbeBytes 8192
  Assert-CStlGate (@($g.items|Where-Object {$_.format -eq 'gcode'}).Count -eq 0) 'production_gcode_short_decoy_rejected'
 }finally{$gs.Dispose()}
 Write-Host ('C5-02 STL SUMMARY cases=7 labels=14 defaultoff_TP=0 defaultoff_FN=9 defaultoff_TN=5 optin_TP={0} FP={1} FN={2} TN={3} external_SHA_exact={4} changed_SHA_but_structure={5} actual_bytes={6} read_calls={7} validator_bytes={8} original_claims=0 SHA_unchanged=True' -f $tp,$fp,$fn,$tn,$exact,$changed,$sumPhysical,$sumCalls,$sumValidation)
 Write-Host 'PASS: C5-02 STL guarded production module; binary/ASCII/G-code synthetic positive, negative and EOF quota safety'
}
