#Requires -Version 5.1
# D6-02 original FAT acceptance — synthetic memory only, no device paths.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32GuardedResult.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32SharedChainEvidence.psm1') -Force
$script:Pass=0;$script:Fail=0
function Assert-D602([bool]$Condition,[string]$Label){
 if($Condition){$script:Pass++;Write-Host ('PASS '+$Label)}
 else{$script:Fail++;Write-Host ('FAIL '+$Label)}
}
function Set-D602Entry([byte[]]$Data,[long]$At,[uint32]$Value){
 [Array]::Copy([BitConverter]::GetBytes($Value),0,$Data,[int]$At,4)
}
function Hash-D602([byte[]]$Data){
 $h=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($h.ComputeHash($Data)).Replace('-','')}
 finally{$h.Dispose()}
}
function Throws-D602([scriptblock]$Action){
 try{$null=& $Action;return $false}catch{return $true}
}
# A separate source-side observer, not a D report or D-issued attestation.
if(-not ('D602IndependentMemorySource' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D602IndependentMemorySource:Stream{
 readonly MemoryStream source;
 readonly HashSet<long> seen=new HashSet<long>();
 readonly HashSet<long> guardSeen=new HashSet<long>();
 readonly HashSet<long> chainSeen=new HashSet<long>();
 readonly long cutoff;
 readonly int chunk;
 string phase="";
 long bytes=0,calls=0,early=0,guardBytes=0,chainBytes=0,guardCalls=0,chainCalls=0;
 public D602IndependentMemorySource(byte[] img,long stop,int maxChunk){
  if(img==null||stop<0||maxChunk<1||maxChunk>4096)throw new ArgumentException("Bad synthetic source");
  source=new MemoryStream(img,false);cutoff=stop;chunk=maxChunk;
 }
 public void Begin(string p){
  if(p!="guard"&&p!="chain")throw new ArgumentException("Invalid phase");
  phase=p;
 }
 public long Actual{get{return bytes;}}
 public long Unique{get{return seen.Count;}}
 public long Repeated{get{return bytes-seen.Count;}}
 public long Calls{get{return calls;}}
 public long Early{get{return early;}}
 public long GuardActual{get{return guardBytes;}}
 public long GuardUnique{get{return guardSeen.Count;}}
 public long GuardCalls{get{return guardCalls;}}
 public long ChainActual{get{return chainBytes;}}
 public long ChainUnique{get{return chainSeen.Count;}}
 public long ChainCalls{get{return chainCalls;}}
 public bool Observed4(long at){
  if(at<0||at>long.MaxValue-4)return false;
  for(int i=0;i<4;i++)if(!seen.Contains(at+i))return false;
  return true;
 }
 public override bool CanRead{get{return true;}}
 public override bool CanSeek{get{return true;}}
 public override bool CanWrite{get{return false;}}
 public override long Length{get{return source.Length;}}
 public override long Position{get{return source.Position;}set{throw new NotSupportedException();}}
 public override long Seek(long at,SeekOrigin origin){return source.Seek(at,origin);}
 public override int Read(byte[] buffer,int offset,int count){
  if(phase!="guard"&&phase!="chain")throw new InvalidOperationException("Missing phase");
  if(buffer==null||offset<0||count<0||offset>buffer.Length-count)throw new ArgumentException("Invalid read");
  if(calls>=640||count>8192-bytes)throw new IOException("D602.source_hard_quota");
  calls++;
  if(phase=="guard")guardCalls++;else chainCalls++;
  long start=source.Position;
  if(bytes>=cutoff){if(start<source.Length)early++;return 0;}
  int n=source.Read(buffer,offset,(int)Math.Min((long)count,Math.Min((long)chunk,cutoff-bytes)));
  if(n==0&&start<source.Length)early++;
  if(n>0){
   bytes+=n;
   if(phase=="guard")guardBytes+=n;else chainBytes+=n;
   for(int i=0;i<n;i++){
    long at=start+i;seen.Add(at);
    if(phase=="guard")guardSeen.Add(at);else chainSeen.Add(at);
   }
  }
  return n;
 }
 public override void Flush(){}
 public override void SetLength(long n){throw new NotSupportedException();}
 public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
 protected override void Dispose(bool disposing){if(disposing)source.Dispose();base.Dispose(disposing);}
}
'@
}
function Run-D602 {
 param([byte[]]$Image,[long]$Fat1,[long]$Fat2,[long]$FatLength,
 [long]$Stop=[long]::MaxValue,[int]$Chunk=4096)
 $src=[D602IndependentMemorySource]::new($Image,$Stop,$Chunk)
 try{
  $src.Begin('guard')
  $gargs=@{Stream=$src;EnableGuardedDiagnostics=$true;MaxPhysicalReadBytes=4096;MaxPhysicalReadCalls=512}
  $g=Get-ChappyFatGuardedResult @gargs
  $s=$null
  if($g.guardDecision -ceq 'candidate_geometry_unverified' -and
     $g.fatProbeState -ceq 'fixed_baseline_sampled' -and
     $g.metrics.prematureSourceZeroReads -eq 0){
   $src.Begin('chain')
   $a=@{Stream=$src;Fat1OffsetBytes=$Fat1;Fat2OffsetBytes=$Fat2;
      FatLengthBytes=$FatLength;MaxDataCluster=65542L;
      StartClusters=([long[]]@(4,8));MaxReadBytes=256;
      MaxReadCalls=128;MaxStepsPerChain=8}
   $s=Get-ChappyFatSharedChainEvidence @a
  }
  return [pscustomobject]@{
   g=$g;s=$s;actual=$src.Actual;unique=$src.Unique;repeated=$src.Repeated;
   calls=$src.Calls;early=$src.Early;
   guardActual=$src.GuardActual;guardUnique=$src.GuardUnique;guardCalls=$src.GuardCalls;
   chainActual=$src.ChainActual;chainUnique=$src.ChainUnique;chainCalls=$src.ChainCalls;
   # This planted remote position belongs only to the scorer, not D analyzers.
   remote4Observed=$src.Observed4(($Fat2+4L*60000L))
  }
 }finally{$src.Dispose()}
}
$cases=@(
 [pscustomobject]@{id='clean';seed=202617;spc=1;fault='none';bad=$false;shared=$false;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='healthy_fragment';seed=202618;spc=2;fault='fragment';bad=$false;shared=$false;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='fat2_only_missing';seed=202619;spc=1;fault='fat2free';bad=$true;shared=$false;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='both_missing';seed=202617;spc=2;fault='bothfree';bad=$true;shared=$false;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='both_cycle';seed=202618;spc=1;fault='cycle';bad=$true;shared=$false;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='both_bad_marker';seed=202619;spc=2;fault='bad';bad=$true;shared=$false;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='both_shared_numeric_node';seed=202617;spc=1;fault='shared';bad=$false;shared=$true;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='fat2_out_of_data_range';seed=202618;spc=2;fault='outofrange';bad=$true;shared=$false;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='remote_fat2_60000';seed=202619;spc=1;fault='remote';bad=$null;shared=$null;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='premature_source_zero';seed=202619;spc=2;fault='none';bad=$null;shared=$null;cut=1100L;chunk=7}
)
$badScore=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0}
$sharedScore=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0}
$actualTotal=0L;$uniqueTotal=0L;$callsTotal=0L;$guardTotal=0L;$chainTotal=0L
foreach($c in $cases){
 $fixture=New-ChappyA3DStandardFixture -Seed $c.seed -SectorsPerCluster $c.spc -Fragment3Mf:($c.fault -eq 'fragment')
 [byte[]]$image=$fixture.image
 $fatBytes=[long][Math]::Ceiling((4.0*(65541+2))/512.0)*512L
 $fat1=33L*512L;$fat2=$fat1+$fatBytes
 # Make caller-hinted chains 4->6->EOC and 8->9->EOC, in both FAT copies.
 foreach($f in @($fat1,$fat2)){
  Set-D602Entry $image ($f+16L) ([uint32]6)
  Set-D602Entry $image ($f+24L) ([uint32]0x0FFFFFFF)
  Set-D602Entry $image ($f+32L) ([uint32]9)
  Set-D602Entry $image ($f+36L) ([uint32]0x0FFFFFFF)
 }
 switch($c.fault){
  'fat2free' {Set-D602Entry $image ($fat2+16L) ([uint32]0)}
  'bothfree' {foreach($f in @($fat1,$fat2)){Set-D602Entry $image ($f+16L) ([uint32]0)}}
  'cycle' {foreach($f in @($fat1,$fat2)){Set-D602Entry $image ($f+24L) ([uint32]4)}}
  'bad' {foreach($f in @($fat1,$fat2)){Set-D602Entry $image ($f+16L) ([uint32]0x0FFFFFF7)}}
  'shared' {foreach($f in @($fat1,$fat2)){Set-D602Entry $image ($f+32L) ([uint32]6)}}
  'outofrange' {Set-D602Entry $image ($fat2+16L) ([uint32]70000)}
  'remote' {Set-D602Entry $image ($fat2+4L*60000L) ([uint32]1)}
 }
 $before=Hash-D602 $image
 $o=Run-D602 -Image $image -Fat1 $fat1 -Fat2 $fat2 -FatLength $fatBytes -Stop $c.cut -Chunk $c.chunk
 $g=$o.g;$s=$o.s
 Assert-D602 ((Hash-D602 $image) -ceq $before) ($c.id+' source SHA256 unchanged after diagnostics')
 Assert-D602 ($o.actual -le 8192 -and $o.calls -le 640 -and
  $o.actual -eq ($o.guardActual+$o.chainActual) -and
  $o.repeated -eq ($o.actual-$o.unique) -and
  $o.calls -eq ($o.guardCalls+$o.chainCalls)) ($c.id+' independent outer actual/unique/repeated/calls bounded')
 Assert-D602 ($g.contractVersion -ceq 'd6_guarded_fat_result_v1' -and
  $g.metrics.actualReturnedBytes -eq $o.guardActual -and
  $g.metrics.uniqueReturnedBytes -eq $o.guardUnique -and
  $g.metrics.physicalReadCalls -eq $o.guardCalls -and
  $g.sourceReadProvenance -ceq 'internal_D_source_events_NOT_A_attested') ($c.id+' D guard metrics independently reconciled')
 Assert-D602 ($g.fatCopyWinner -ceq 'not_selected' -and
  $g.fileOwner -ceq 'unknown' -and $g.originalIdentity -ceq 'unknown' -and
  $g.geometryAuthenticity -ceq 'unknown' -and
  -not $g.canRepair -and -not $g.canExport -and
  -not $g.writePermitted) ($c.id+' no FAT winner, original-file owner, write, repair or export')
 if($null -eq $c.bad){
  $badScore.UNKNOWN++;$sharedScore.UNKNOWN++
  if($c.fault -ceq 'remote'){
   Assert-D602 (-not $o.remote4Observed -and
    $g.fatProbeState -ceq 'fixed_baseline_sampled' -and
    $g.evidence.pairedFullyObservedEntries -eq 128 -and
    $g.evidence.unobservedPairedEntryIndices -eq 65536 -and
    $g.evidence.mirrorDifferentEntries -eq 0 -and
    $null -ne $s -and $s.sharedObservedInCopies -eq 0) 'Remote FAT2 entry60000 physically unread, never scored clean, remain UNKNOWN'
  }else{
   Assert-D602 ($o.early -gt 0 -and $o.actual -eq 1100 -and
    $g.guardDecision -ceq 'blocked_insufficient_evidence' -and
    $g.metrics.fatFixedReturnedBytes -eq 0 -and $null -eq $s -and
    $null -eq $g.evidence.pairedCoveragePercent) 'Premature source zero physically halts all FAT evidence, UNKNOWN'
  }
 }else{
  Assert-D602 ($g.guardDecision -ceq 'candidate_geometry_unverified' -and
   $g.fatProbeState -ceq 'fixed_baseline_sampled' -and
   $g.evidence.totalDeclaredEntriesPerCopy -eq 65664 -and
   $g.evidence.pairedFullyObservedEntries -eq 128 -and
   $g.evidence.unobservedPairedEntryIndices -eq 65536 -and
   $g.evidence.unobservedPairPercent -gt 99.8 -and
   $null -ne $s) ($c.id+' fixed 128 physical FAT pairs, remaining 65536 indices UNKNOWN')
  Assert-D602 ($s.metrics.actualReturnedBytes -eq $o.chainActual -and
   $s.metrics.uniqueReturnedBytes -eq $o.chainUnique -and
   $s.metrics.physicalReadCalls -eq $o.chainCalls -and
   $s.metrics.actualReturnedBytes -le 256 -and
   $s.metrics.physicalReadCalls -le 128 -and
   $s.fileOwner -ceq 'unknown' -and
   $s.fatCopyWinner -ceq 'not_selected' -and -not $s.writePermitted) ($c.id+' chain source independently metered, numeric hints never become owners')
  $badTerminals=@('free','bad_cluster','reserved','out_of_range','cycle')
  $observedBad=@($s.items|Where-Object {$badTerminals -contains $_.terminal}).Count
  $hit=($g.evidence.mirrorDifferentEntries -gt 0 -or $observedBad -gt 0)
  $sharedHit=($s.sharedObservedInCopies -eq 2)
  if($c.bad){if($hit){$badScore.TP++}else{$badScore.FN++}}
  else{if($hit){$badScore.FP++}else{$badScore.TN++}}
  if($c.shared){if($sharedHit){$sharedScore.TP++}else{$sharedScore.FN++}}
  else{if($sharedHit){$sharedScore.FP++}else{$sharedScore.TN++}}
  Assert-D602 ($hit -eq $c.bad -and $sharedHit -eq $c.shared) ($c.id+' observed invalid-link and shared-numeric-node scored separately')
  switch($c.fault){
   'fat2free' {Assert-D602 ($g.evidence.mirrorDifferentEntries -gt 0 -and
     @($s.items|Where-Object {$_.fatCopyIndex -eq 1 -and $_.startCluster -eq 4 -and $_.terminal -eq 'free'}).Count -eq 1) 'FAT2 missing link observed; no selection of FAT1 winner'}
   'bothfree' {Assert-D602 ($g.evidence.mirrorDifferentEntries -eq 0 -and
     @($s.items|Where-Object {$_.startCluster -eq 4 -and $_.terminal -eq 'free'}).Count -eq 2) 'Both identical missing links do not count as healthy mirror'}
   'cycle' {Assert-D602 ($g.evidence.mirrorDifferentEntries -eq 0 -and
     @($s.items|Where-Object {$_.startCluster -eq 4 -and $_.terminal -eq 'cycle'}).Count -eq 2) 'Both copies identically cyclic remain suspect'}
   'bad' {Assert-D602 ($g.evidence.mirrorDifferentEntries -eq 0 -and
     @($s.items|Where-Object {$_.startCluster -eq 4 -and $_.terminal -eq 'bad_cluster'}).Count -eq 2) 'Identical FAT bad-cluster marks observed'}
   'shared' {Assert-D602 ($s.sharedObservedInCopies -eq 2 -and
     $s.copies[0].sharedObservedClusterCount -eq 1 -and
     $s.copies[1].sharedObservedClusterCount -eq 1 -and
     $s.fileOwner -ceq 'unknown') 'Numeric convergence in both FATs is NOT two real file owners'}
   'outofrange' {Assert-D602 ($g.evidence.mirrorDifferentEntries -gt 0 -and
     @($s.items|Where-Object {$_.fatCopyIndex -eq 1 -and $_.terminal -eq 'out_of_range'}).Count -eq 1) 'FAT2 link to cluster70000 out of data range rejected'}
   'none' {Assert-D602 ($s.sharedObservedInCopies -eq 0 -and
     @($s.items|Where-Object {$_.terminal -ne 'eoc'}).Count -eq 0) 'Clean observed chains terminate normally'}
   'fragment' {Assert-D602 ($s.sharedObservedInCopies -eq 0 -and
     @($s.items|Where-Object {$_.terminal -ne 'eoc'}).Count -eq 0) 'Healthy fragmentation does not create false corruption'}
  }
 }
 $actualTotal+=$o.actual;$uniqueTotal+=$o.unique;$callsTotal+=$o.calls
 $guardTotal+=$o.guardActual;$chainTotal+=$o.chainActual
 Write-Host ('D6-02 case={0} mirrorDiff={1} sharedCopies={2} observedPairs={3}/65664 physical actual/unique={4}/{5} calls={6} scorerUnknown={7}' -f
  $c.id,$g.evidence.mirrorDifferentEntries,
  $(if($null -eq $s){'UNKNOWN'}else{$s.sharedObservedInCopies}),
  $g.evidence.pairedFullyObservedEntries,$o.actual,$o.unique,$o.calls,
  ($null -eq $c.bad))
 $fixture=$null;$image=$null;[GC]::Collect()
}
Assert-D602 ($badScore.TP -eq 5 -and $badScore.FP -eq 0 -and
 $badScore.FN -eq 0 -and $badScore.TN -eq 3 -and $badScore.UNKNOWN -eq 2) 'Invalid-link/copy disagreement TP5 FP0 FN0 TN3 UNKNOWN2; remote unseen not negative'
Assert-D602 ($sharedScore.TP -eq 1 -and $sharedScore.FP -eq 0 -and
 $sharedScore.FN -eq 0 -and $sharedScore.TN -eq 7 -and $sharedScore.UNKNOWN -eq 2) 'Numeric shared-node TP1 FP0 FN0 TN7 UNKNOWN2; no file-owner inference'
$fake=[byte[]]::new(8192)
$write=[IO.MemoryStream]::new($fake,$true)
try{
 $args=@{Stream=$write;Fat1OffsetBytes=512;Fat2OffsetBytes=4096;
  FatLengthBytes=1024;MaxDataCluster=100;StartClusters=([long[]]@(4,8))}
 Assert-D602 (Throws-D602 {Get-ChappyFatSharedChainEvidence @args}) 'Writable source is rejected by existing shared-chain API'
}finally{$write.Dispose()}
$read=[IO.MemoryStream]::new($fake,$false)
try{
 $args=@{Stream=$read;Fat1OffsetBytes=512;Fat2OffsetBytes=600;
  FatLengthBytes=1024;MaxDataCluster=100;StartClusters=([long[]]@(4,8))}
 Assert-D602 (Throws-D602 {Get-ChappyFatSharedChainEvidence @args}) 'Overlapping caller-provided FAT copies refused without source-owner inference'
}finally{$read.Dispose()}
Write-Host ('D6-02 R6 accepted scorer invalid-link TP/FP/FN/TN/UNKNOWN={0}/{1}/{2}/{3}/{4}; observed numeric shared={5}/{6}/{7}/{8}/{9}' -f
 $badScore.TP,$badScore.FP,$badScore.FN,$badScore.TN,$badScore.UNKNOWN,
 $sharedScore.TP,$sharedScore.FP,$sharedScore.FN,$sharedScore.TN,$sharedScore.UNKNOWN)
Write-Host ('D6-02 sources=10 source physical actual={0}, summed source-local unique={1}, duplicates={2}, calls={3}, guardBytes={4}, hintedChainBytes={5}' -f
 $actualTotal,$uniqueTotal,($actualTotal-$uniqueTotal),$callsTotal,$guardTotal,$chainTotal)
Write-Host ('Team D D6-02 original FAT acceptance: {0} PASS / {1} FAIL' -f $script:Pass,$script:Fail)
if($script:Fail -gt 0){exit 1}
