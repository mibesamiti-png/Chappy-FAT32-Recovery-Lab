#Requires -Version 5.1
# Original formal R6 acceptance audit: BOTH compact R2 and standards-shaped R3.
# All data generated inside test; original oracle/mutations never passed as
# discovery hints, and no real source/IMG/device/path is accessed.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
. (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
# GuardedResult force-imports a nested geometry dependency. On Windows PS5.1
# import direct compact readers LAST to keep their public commands visible.
Import-Module (Join-Path $PSScriptRoot '..\Fat32GuardedResult.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32GuardedReturnedSourceJoin.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32SharedChainEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32GeometryTrust.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32MirrorWindows.psm1') -Force
$script:Pass=0;$script:Fail=0
function Assert-R6([bool]$ok,[string]$desc){
 if($ok){$script:Pass++;Write-Host ('PASS '+$desc)}
 else{$script:Fail++;Write-Host ('FAIL '+$desc)}
}
function Hash-R6([byte[]]$b){
 $h=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($h.ComputeHash($b)).Replace('-','')}
 finally{$h.Dispose()}
}
function Put-R6([byte[]]$b,[long]$at,[uint32]$value){
 [Array]::Copy([BitConverter]::GetBytes($value),0,$b,[int]$at,4)
}
if(-not ('D6FormalSuccessfulRead' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D6FormalSuccessfulRead {
 public string Consumer{get;set;}
 public long OffsetBytes{get;set;}
 public int ReturnedBytes{get;set;}
}
public sealed class D6FormalSyntheticSource:Stream {
 readonly MemoryStream source;
 readonly HashSet<long> unique=new HashSet<long>();
 readonly List<D6FormalSuccessfulRead> returns=new List<D6FormalSuccessfulRead>();
 readonly long stop;
 readonly int maxChunk;
 string phase="fat";
 long actual=0,calls=0,early=0;
 public D6FormalSyntheticSource(byte[] data,long cutoff,int chunk) {
  if(data==null||cutoff<0||chunk<1||chunk>4096)
    throw new ArgumentException("Artificial data only");
  source=new MemoryStream(data,false);stop=cutoff;maxChunk=chunk;
 }
 public void Phase(string label) {
  if(label!="fat"&&label!="chain"&&label!="compact")throw new ArgumentException("Invalid phase");
  phase=label;
 }
 public D6FormalSuccessfulRead[] Events{get{return returns.ToArray();}}
 public long Actual{get{return actual;}}
 public long Unique{get{return unique.Count;}}
 public long Calls{get{return calls;}}
 public long Early{get{return early;}}
 public bool Has4(long at){
  for(int j=0;j<4;j++)if(!unique.Contains(at+j))return false;
  return true;
 }
 public override bool CanRead{get{return true;}}
 public override bool CanSeek{get{return true;}}
 public override bool CanWrite{get{return false;}}
 public override long Length{get{return source.Length;}}
 public override long Position{get{return source.Position;}set{throw new NotSupportedException();}}
 public override long Seek(long offset,SeekOrigin origin){return source.Seek(offset,origin);}
 public override int Read(byte[] buffer,int offset,int count) {
  if(buffer==null||offset<0||count<0||offset>buffer.Length-count)
    throw new ArgumentException("Bad Stream.Read");
  if(calls>=640||count>8192-actual)throw new IOException("R6.outer_read_budget_exhausted");
  calls++;
  long at=source.Position;
  if(actual>=stop){if(at<source.Length)early++;return 0;}
  int n=source.Read(buffer,offset,(int)Math.Min((long)count,Math.Min((long)maxChunk,stop-actual)));
  if(n==0&&at<source.Length)early++;
  if(n>0){
   actual+=n;
   returns.Add(new D6FormalSuccessfulRead{Consumer=phase,OffsetBytes=at,ReturnedBytes=n});
   for(int i=0;i<n;i++)unique.Add(at+i);
  }
  return n;
 }
 public override void Flush(){}
 public override void SetLength(long n){throw new NotSupportedException();}
 public override void Write(byte[] b,int at,int n){throw new NotSupportedException();}
 protected override void Dispose(bool disposing){if(disposing)source.Dispose();base.Dispose(disposing);}
}
'@
}

# Track R2 candidate mirror index (not original-file correctness). X02
# geometry rejection is UNKNOWN, not a TN due to truncated file payload.
$compact=@(
 [pscustomobject]@{id='M00';truth=$false;difference=0},
 [pscustomobject]@{id='M01';truth=$false;difference=0},
 [pscustomobject]@{id='M02';truth=$true;difference=1},
 [pscustomobject]@{id='X02';truth=$null;difference=0}
)
$r2score=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0}
$r2actual=0L;$r2unique=0L;$r2calls=0L
foreach($c in $compact){
 $fixture=New-ChappyA3DDamagedFixture -Case $c.id -Seed 202611
 [byte[]]$bytes=$fixture.image
 $hash=Hash-R6 $bytes
 Assert-R6 ($hash -ceq $fixture.manifest.imageSha256) ($c.id+' independent fixture image SHA matches scorer manifest')
 $src=[D6FormalSyntheticSource]::new($bytes,[long]::MaxValue,4096)
 try{
  $src.Phase('compact')
  $geom=Get-ChappyFatGeometryTrust -Stream $src
  $mirror=Get-ChappyFatMirrorWindows -Stream $src -Fat1OffsetBytes $geom.geometry.fat1OffsetBytes -Fat2OffsetBytes $geom.geometry.fat2OffsetBytes -FatLengthBytes $geom.geometry.fatLengthBytes -WindowEntries 128 -MaxWindows 1 -MaxReadBytes 1024
  Assert-R6 ($geom.trustDecision -ceq 'reject' -and $geom.writePermitted -eq $false -and
      $mirror.metrics.differentEntries -eq $c.difference) ($c.id+' compact FAT32-like geometry not authenticated; measured fixed mirror differences')
  Assert-R6 ($src.Actual -le 2048 -and $src.Unique -le $src.Actual -and
      $mirror.metrics.bytesRead -eq 1024 -and $mirror.metrics.entriesChecked -eq 128) ($c.id+' compact independently metered bounded physical source')
  if($c.id -eq 'X02'){
   $r2score.UNKNOWN++
   Assert-R6 ($geom.reasons -contains 'geometry.partition_exceeds_stream') 'X02 physically short partition metadata rejected; zero sampled FAT differences cannot imply file health'
  } else {
   $hit=($mirror.metrics.differentEntries -gt 0)
   if($c.truth){if($hit){$r2score.TP++}else{$r2score.FN++}}
   else{if($hit){$r2score.FP++}else{$r2score.TN++}}
  }
  Assert-R6 ((Hash-R6 $bytes) -ceq $hash) ($c.id+' compact input SHA unchanged')
  $r2actual+=$src.Actual;$r2unique+=$src.Unique;$r2calls+=$src.Calls
  Write-Host ('R6 compact {0}: mirrorDifference={1} geometry=reject sourceActual/Unique={2}/{3} calls={4} scorer={5}' -f $c.id,$mirror.metrics.differentEntries,$src.Actual,$src.Unique,$src.Calls,$c.truth)
 }finally{$src.Dispose()}
}
Assert-R6 ($r2score.TP -eq 1 -and $r2score.FP -eq 0 -and $r2score.FN -eq 0 -and
  $r2score.TN -eq 2 -and $r2score.UNKNOWN -eq 1) 'Compact R2 sampled-mirror TP1 FP0 FN0 TN2 UNKNOWN1 (not reconstructed file rate)'
# Real physical EOF after one sector and only partial FAT data.
$earlyFixture=New-ChappyA3DDamagedFixture -Case M00 -Seed 202611
$earlyHash=Hash-R6 $earlyFixture.image
$earlySource=[D6FormalSyntheticSource]::new($earlyFixture.image,1200L,4096)
try{
 $geometry=Get-ChappyFatGeometryTrust -Stream $earlySource
 $earlyMirror=Get-ChappyFatMirrorWindows -Stream $earlySource -Fat1OffsetBytes $geometry.geometry.fat1OffsetBytes -Fat2OffsetBytes $geometry.geometry.fat2OffsetBytes -FatLengthBytes $geometry.geometry.fatLengthBytes -WindowEntries 128 -MaxWindows 1 -MaxReadBytes 1024
 Assert-R6 ($earlySource.Actual -eq 1200 -and $earlySource.Early -gt 0 -and
   $earlyMirror.scanIncomplete -and $earlyMirror.metrics.bytesRead -eq 176 -and
   (Hash-R6 $earlyFixture.image) -ceq $earlyHash) 'Compact extra physical EOF 1200B: FAT partial and no clean inference'
}finally{$earlySource.Dispose()}

# Standards-shaped R3 independent scenarios: scorer owns planted locations.
# Numeric FAT start hints are fixed [4,8] for every case. NOT file owners.
$standard=@(
 [pscustomobject]@{id='clean';seed=202623;spc=1;fault='none';bad=$false;shared=$false;stop=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='healthy_fragment';seed=202624;spc=2;fault='fragment';bad=$false;shared=$false;stop=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='fat2_missing';seed=202623;spc=1;fault='onefree';bad=$true;shared=$false;stop=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='identical_both_cycle';seed=202624;spc=2;fault='cycle';bad=$true;shared=$false;stop=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='numeric_crosslink';seed=202623;spc=1;fault='shared';bad=$false;shared=$true;stop=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='far_60000';seed=202624;spc=2;fault='far';bad=$null;shared=$null;stop=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='true_early_1100';seed=202623;spc=1;fault='none';bad=$null;shared=$null;stop=1100L;chunk=7},
 [pscustomobject]@{id='backup_contradiction';seed=202624;spc=2;fault='backup';bad=$null;shared=$null;stop=[long]::MaxValue;chunk=4096}
)
$r3bad=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0}
$r3shared=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0}
$r3actual=0L;$r3unique=0L;$r3calls=0L
foreach($c in $standard){
 $fixture=New-ChappyA3DStandardFixture -Seed $c.seed -SectorsPerCluster $c.spc -Fragment3Mf:($c.fault -eq 'fragment')
 [byte[]]$bytes=$fixture.image
 $fatBytes=[long][Math]::Ceiling((4.0*(65541+2))/512.0)*512L
 $fat1=33L*512L;$fat2=$fat1+$fatBytes
 # Independent artificial source setup, separate from D module input.
 foreach($f in @($fat1,$fat2)){
  Put-R6 $bytes ($f+16L) ([uint32]6)
  Put-R6 $bytes ($f+24L) ([uint32]0x0FFFFFFF)
  Put-R6 $bytes ($f+32L) ([uint32]9)
  Put-R6 $bytes ($f+36L) ([uint32]0x0FFFFFFF)
 }
 switch($c.fault){
  'onefree' {Put-R6 $bytes ($fat2+16L) ([uint32]0)}
  'cycle' {foreach($f in @($fat1,$fat2)){Put-R6 $bytes ($f+24L) ([uint32]4)}}
  'shared' {foreach($f in @($fat1,$fat2)){Put-R6 $bytes ($f+32L) ([uint32]6)}}
  'far' {Put-R6 $bytes ($fat2+4L*60000L) ([uint32]1)}
  'backup' {[Array]::Copy([BitConverter]::GetBytes([uint16]33),0,$bytes,(512+6*512+14),2)}
 }
 $hash=Hash-R6 $bytes
 $src=[D6FormalSyntheticSource]::new($bytes,$c.stop,$c.chunk)
 try{
  $src.Phase('fat')
  $guard=Get-ChappyFatGuardedResult -Stream $src -EnableGuardedDiagnostics -MaxPhysicalReadBytes 4096 -MaxPhysicalReadCalls 512
  $guardBytes=$src.Actual;$guardCalls=$src.Calls;$guardUnique=$src.Unique
  $outerEvents=@($src.Events)
  $joined=Compare-ChappyFatGuardedReturnedSourceEvents -GuardedResult $guard -OuterReturnedEvents $outerEvents -SourceLengthBytes ([long]$bytes.Length) -OuterPhysicalReadCalls $src.Calls -OuterPrematureZeroReads $src.Early
  Assert-R6 ($guard.metrics.actualReturnedBytes -eq $guardBytes -and
    $guard.metrics.uniqueReturnedBytes -eq $guardUnique -and
    $guard.metrics.physicalReadCalls -eq $guardCalls -and
    $joined.outerEventAgreement -and
    $src.Actual -le 8192 -and $src.Calls -le 640) ($c.id+' standards FAT evidence reconciled with independent source actual/unique/call/phase spans')
  Assert-R6 ($guard.contractVersion -ceq 'd6_guarded_fat_result_v1' -and
    -not $guard.canRepair -and -not $guard.canExport -and
    -not $guard.writePermitted -and
    $guard.fatCopyWinner -ceq 'not_selected' -and
    $guard.fileOwner -ceq 'unknown' -and
    $joined.sourceAuthenticity -ceq 'not_proven') ($c.id+' no original owner/source authenticity/FAT winner/repair/export')
  $chain=$null
  if($null -eq $c.bad){
   $r3bad.UNKNOWN++;$r3shared.UNKNOWN++
   if($c.fault -ceq 'far'){
    Assert-R6 ($guard.evidence.pairedFullyObservedEntries -eq 128 -and
      $guard.evidence.unobservedPairedEntryIndices -eq 65536 -and
      -not $src.Has4(($fat2+4L*60000L)) -and
      $joined.metrics.unobservedPairedEntryIndices -eq 65536) 'Remote FAT2 index60000 physically not returned: UNKNOWN not healthy'
   }elseif($c.fault -ceq 'backup'){
    Assert-R6 ($guard.guardDecision -ceq 'blocked_conflicting_geometry' -and
      $guard.metrics.fatFixedReturnedBytes -eq 0 -and
      $null -eq $joined.metrics.pairedCoveragePercent -and
      $joined.decision -ceq 'consistent_blocked_unattested') 'Contradictory backup geometry denies ALL FAT reads, numeric source only'
   }else{
    Assert-R6 ($guard.metrics.fatFixedReturnedBytes -eq 0 -and
      $guard.metrics.prematureSourceZeroReads -gt 0 -and
      $null -eq $joined.metrics.pairedCoveragePercent -and
      $joined.decision -ceq 'unknown') ($c.id+' true physical EOF yields UNKNOWN')
   }
  }else{
   Assert-R6 ($guard.guardDecision -ceq 'candidate_geometry_unverified' -and
     $guard.fatProbeState -ceq 'fixed_baseline_sampled' -and
     $guard.evidence.pairedFullyObservedEntries -eq 128 -and
     $guard.evidence.totalDeclaredEntriesPerCopy -eq 65664 -and
     $guard.evidence.unobservedPairedEntryIndices -eq 65536 -and
     $joined.decision -ceq 'consistent_numeric_candidate_unattested') ($c.id+' standards physically complete FAT4B pair 128/65664; rest UNKNOWN')
   $src.Phase('chain')
   $chain=Get-ChappyFatSharedChainEvidence -Stream $src -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $fatBytes -MaxDataCluster 65542L -StartClusters ([long[]]@(4,8)) -MaxReadBytes 256 -MaxReadCalls 128 -MaxStepsPerChain 8
   Assert-R6 ($chain.metrics.actualReturnedBytes -eq ($src.Actual-$guardBytes) -and
     $chain.metrics.physicalReadCalls -eq ($src.Calls-$guardCalls) -and
     $chain.fileOwner -ceq 'unknown' -and
     $chain.fatCopyWinner -ceq 'not_selected' -and -not $chain.writePermitted) ($c.id+' bounded numeric hinted-chain evidence independently metered without ownership claim')
   $badTerminals=@('free','bad_cluster','reserved','cycle','out_of_range')
   $hit=($guard.evidence.mirrorDifferentEntries -gt 0 -or
     @($chain.items|Where-Object {$badTerminals -contains $_.terminal}).Count -gt 0)
   $shared=($chain.sharedObservedInCopies -eq 2)
   if($c.bad){if($hit){$r3bad.TP++}else{$r3bad.FN++}}
   else{if($hit){$r3bad.FP++}else{$r3bad.TN++}}
   if($c.shared){if($shared){$r3shared.TP++}else{$r3shared.FN++}}
   else{if($shared){$r3shared.FP++}else{$r3shared.TN++}}
   Assert-R6 ($hit -eq $c.bad -and $shared -eq $c.shared) ($c.id+' invalid-link and numeric-shared observation assessed as separate units')
   if($c.fault -ceq 'cycle'){
    Assert-R6 ($guard.evidence.mirrorDifferentEntries -eq 0 -and
      @($chain.items|Where-Object {$_.terminal -eq 'cycle'}).Count -eq 2) 'Both mirror-identical cycles observed, not healthy despite equal copies'
   }
   if($c.fault -ceq 'shared'){
    Assert-R6 ($chain.sharedObservedInCopies -eq 2 -and
      $chain.copies[0].sharedObservedClusterCount -eq 1 -and
      $chain.copies[1].sharedObservedClusterCount -eq 1) 'Both FAT copies exhibit numeric shared-node, NOT real two-file ownership'
   }
  }
  Assert-R6 ((Hash-R6 $bytes) -ceq $hash) ($c.id+' standards generated input unchanged SHA')
  Assert-R6 ($src.Actual -le 8192 -and $src.Calls -le 640 -and $src.Unique -le $src.Actual) ($c.id+' external complete case physical resource limits')
  $r3actual+=$src.Actual;$r3unique+=$src.Unique;$r3calls+=$src.Calls
  Write-Host ('R6 standards {0}: guard={1} paired={2}/65664 sourceActual/Unique={3}/{4} calls={5} badTruth={6} sharedTruth={7}' -f $c.id,$guard.guardDecision,$guard.evidence.pairedFullyObservedEntries,$src.Actual,$src.Unique,$src.Calls,$c.bad,$c.shared)
 }finally{$src.Dispose()}
 $fixture=$null;$bytes=$null
 [GC]::Collect()
}
Assert-R6 ($r3bad.TP -eq 2 -and $r3bad.FP -eq 0 -and
  $r3bad.FN -eq 0 -and $r3bad.TN -eq 3 -and $r3bad.UNKNOWN -eq 3) 'Standards invalid/copy discrepancy TP2 FP0 FN0 TN3 UNKNOWN3; withheld remote/EOF/geometry excluded'
Assert-R6 ($r3shared.TP -eq 1 -and $r3shared.FP -eq 0 -and
  $r3shared.FN -eq 0 -and $r3shared.TN -eq 4 -and $r3shared.UNKNOWN -eq 3) 'Standards shared numeric node TP1 FP0 FN0 TN4 UNKNOWN3; never original owner'
Write-Host ('R6 formal two-track: compact TP/FP/FN/TN/U={0}/{1}/{2}/{3}/{4}, standards bad={5}/{6}/{7}/{8}/{9}, standards numericShared={10}/{11}/{12}/{13}/{14}' -f
 $r2score.TP,$r2score.FP,$r2score.FN,$r2score.TN,$r2score.UNKNOWN,
 $r3bad.TP,$r3bad.FP,$r3bad.FN,$r3bad.TN,$r3bad.UNKNOWN,
 $r3shared.TP,$r3shared.FP,$r3shared.FN,$r3shared.TN,$r3shared.UNKNOWN)
Write-Host ('R6 formal physically returned: compact {0} B unique {1} B calls {2}; standards {3} B unique {4} B calls {5}; independent source-local sums only' -f
 $r2actual,$r2unique,$r2calls,$r3actual,$r3unique,$r3calls)
Write-Host ('Team D ORIGINAL R6 two-track acceptance: {0} PASS / {1} FAIL' -f $script:Pass,$script:Fail)
if($script:Fail -gt 0){exit 1}
