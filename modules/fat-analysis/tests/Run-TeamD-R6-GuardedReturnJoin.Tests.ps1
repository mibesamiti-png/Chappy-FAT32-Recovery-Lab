#Requires -Version 5.1
# D6-04 guarded D physical event join: only generated artificial memory streams.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32GuardedResult.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32GuardedReturnedSourceJoin.psm1') -Force
$script:Pass=0;$script:Fail=0
function Check-D604([bool]$Good,[string]$Label){
 if($Good){$script:Pass++;Write-Host ('PASS '+$Label)}
 else{$script:Fail++;Write-Host ('FAIL '+$Label)}
}
function Hash-D604([byte[]]$B){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($sha.ComputeHash($B)).Replace('-','')}
 finally{$sha.Dispose()}
}
function Put-D604([byte[]]$B,[int]$At,[uint32]$N){
 [Array]::Copy([BitConverter]::GetBytes($N),0,$B,$At,4)
}
if(-not ('D604OuterSpan' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D604OuterSpan {
 public string Consumer{get;set;}
 public long OffsetBytes{get;set;}
 public int ReturnedBytes{get;set;}
}
public sealed class D604SyntheticMeter:Stream{
 readonly MemoryStream input;
 readonly List<D604OuterSpan> events=new List<D604OuterSpan>();
 readonly HashSet<long> union=new HashSet<long>();
 readonly long stop;
 readonly int chunk;
 long bytes=0,calls=0,early=0;
 public D604SyntheticMeter(byte[] data,long stopAt,int maxChunk){
  if(data==null||stopAt<0||maxChunk<1||maxChunk>4096)
    throw new ArgumentException("Artificial source only");
  input=new MemoryStream(data,false);stop=stopAt;chunk=maxChunk;
 }
 public D604OuterSpan[] Events{get{return events.ToArray();}}
 public long Returned{get{return bytes;}}
 public long Unique{get{return union.Count;}}
 public long Calls{get{return calls;}}
 public long PrematureZero{get{return early;}}
 public override bool CanRead{get{return true;}}
 public override bool CanSeek{get{return true;}}
 public override bool CanWrite{get{return false;}}
 public override long Length{get{return input.Length;}}
 public override long Position{get{return input.Position;}set{throw new NotSupportedException();}}
 public override long Seek(long at,SeekOrigin origin){return input.Seek(at,origin);}
 public override int Read(byte[] buf,int off,int count){
  if(buf==null||off<0||count<0||off>buf.Length-count)
    throw new ArgumentException("Bad Read()");
  if(calls>=640||count>8192-bytes)throw new IOException("outer_source_quota");
  calls++;
  long at=input.Position;
  if(bytes>=stop){if(at<input.Length)early++;return 0;}
  int requested=(int)Math.Min((long)count,Math.Min((long)chunk,stop-bytes));
  int got=input.Read(buf,off,requested);
  if(got==0&&at<input.Length)early++;
  if(got>0){
    bytes+=got;events.Add(new D604OuterSpan{Consumer="fat",OffsetBytes=at,ReturnedBytes=got});
    for(int i=0;i<got;i++)union.Add(at+i);
  }
  return got;
 }
 public override void Flush(){}
 public override void SetLength(long n){throw new NotSupportedException();}
 public override void Write(byte[] x,int o,int n){throw new NotSupportedException();}
 protected override void Dispose(bool disposing){if(disposing)input.Dispose();base.Dispose(disposing);}
}
'@
}
function Run-D604([byte[]]$Image,[long]$Stop,[int]$Chunk){
 $source=[D604SyntheticMeter]::new($Image,$Stop,$Chunk)
 try{
  $d=Get-ChappyFatGuardedResult -Stream $source -EnableGuardedDiagnostics -MaxPhysicalReadBytes 4096 -MaxPhysicalReadCalls 512
  $events=@($source.Events)
  $joined=Compare-ChappyFatGuardedReturnedSourceEvents -GuardedResult $d -OuterReturnedEvents $events -SourceLengthBytes ([long]$Image.Length) -OuterPhysicalReadCalls $source.Calls -OuterPrematureZeroReads $source.PrematureZero
  return [pscustomobject]@{d=$d;j=$joined;events=$events;actual=$source.Returned;unique=$source.Unique;calls=$source.Calls;early=$source.PrematureZero}
 }finally{$source.Dispose()}
}
$cases=@(
 [pscustomobject]@{id='clean_spc1';seed=202621;spc=1;fault='none';stop=[long]::MaxValue;chunk=4096;expect='numeric'},
 [pscustomobject]@{id='clean_spc2';seed=202622;spc=2;fault='none';stop=[long]::MaxValue;chunk=4096;expect='numeric'},
 [pscustomobject]@{id='fat2_missing';seed=202621;spc=1;fault='one';stop=[long]::MaxValue;chunk=4096;expect='numeric'},
 [pscustomobject]@{id='both_copies_cycle';seed=202622;spc=2;fault='both';stop=[long]::MaxValue;chunk=4096;expect='numeric'},
 [pscustomobject]@{id='remote_entry60000';seed=202621;spc=1;fault='far';stop=[long]::MaxValue;chunk=4096;expect='numeric'},
 [pscustomobject]@{id='short_successive_32B';seed=202622;spc=2;fault='none';stop=[long]::MaxValue;chunk=32;expect='numeric'},
 [pscustomobject]@{id='backup_bpB_conflict';seed=202621;spc=1;fault='backup';stop=[long]::MaxValue;chunk=4096;expect='blocked'},
 [pscustomobject]@{id='matching_unsupported_flags';seed=202622;spc=2;fault='flags';stop=[long]::MaxValue;chunk=4096;expect='blocked'},
 [pscustomobject]@{id='invalid_SPC';seed=202621;spc=1;fault='spc';stop=[long]::MaxValue;chunk=4096;expect='blocked'},
 [pscustomobject]@{id='early_zero_1100';seed=202622;spc=2;fault='none';stop=1100L;chunk=7;expect='unknown'},
 [pscustomobject]@{id='early_zero_after_3_FAT_bytes';seed=202621;spc=1;fault='none';stop=3075L;chunk=4096;expect='unknown'}
)
$numeric=0;$blocked=0;$unknown=0;$actual=0L;$unique=0L;$calls=0L
$sample=$null;$sampleLength=0L
foreach($c in $cases){
 $fixture=New-ChappyA3DStandardFixture -Seed $c.seed -SectorsPerCluster $c.spc
 [byte[]]$bytes=$fixture.image
 $fatsz=[long]([Math]::Ceiling(4.0*(65541+2)/512.0)*512)
 $f1=33L*512L;$f2=$f1+$fatsz
 switch($c.fault){
  'one' {Put-D604 $bytes ([int]($f2+4*4)) ([uint32]0)}
  'both' {Put-D604 $bytes ([int]($f1+4*4)) ([uint32]4);Put-D604 $bytes ([int]($f2+4*4)) ([uint32]4)}
  'far' {Put-D604 $bytes ([int]($f2+4*60000)) ([uint32]1)}
  'backup' {[Array]::Copy([BitConverter]::GetBytes([uint16]33),0,$bytes,(512+6*512+14),2)}
  'flags' {[Array]::Copy([BitConverter]::GetBytes([uint16]128),0,$bytes,(512+40),2);[Array]::Copy([BitConverter]::GetBytes([uint16]128),0,$bytes,(512+6*512+40),2)}
  'spc' {$bytes[512+13]=0;$bytes[512+6*512+13]=0}
 }
 $hash=Hash-D604 $bytes
 $x=Run-D604 -Image $bytes -Stop $c.stop -Chunk $c.chunk
 $d=$x.d;$j=$x.j
 Check-D604 ($d.contractVersion -ceq 'd6_guarded_fat_result_v1' -and -not $d.writePermitted -and -not $d.canExport -and
     $d.originalIdentity -ceq 'unknown' -and $d.fatCopyWinner -ceq 'not_selected' -and
     $j.sourceAuthenticity -ceq 'not_proven' -and -not $j.wholeFatVerified -and -not $j.writePermitted) ($c.id+' immutable no owner/source authenticity/writer assertion')
 Check-D604 ($x.actual -eq [long]$d.metrics.actualReturnedBytes -and
     $x.unique -eq [long]$d.metrics.uniqueReturnedBytes -and
     $x.calls -eq [long]$d.metrics.physicalReadCalls -and
     $x.actual -le 4096 -and $x.calls -le 512 -and
     @($d.sourceReturnedEvents).Count -eq $x.events.Count) ($c.id+' outer actual/unique/calls/transcript match D guarded v1')
 Check-D604 ((Hash-D604 $bytes) -ceq $hash) ($c.id+' input image SHA unchanged')
 if($c.expect -ceq 'numeric'){
  $numeric++
  Check-D604 ($d.guardDecision -ceq 'candidate_geometry_unverified' -and
      $d.fatProbeState -ceq 'fixed_baseline_sampled' -and
      $j.decision -ceq 'consistent_numeric_candidate_unattested' -and
      $j.outerEventAgreement -and $j.metrics.readCallCountMatched) ($c.id+' guarded fixed FAT phase paired to external physical events')
  Check-D604 ($j.metrics.pairedFullyObservedEntries -eq 128 -and
      $j.metrics.totalDeclaredEntriesPerCopy -eq 65664 -and
      $j.metrics.unobservedPairedEntryIndices -eq 65536 -and
      $j.metrics.unobservedPairPercent -gt 99.8) ($c.id+' exactly observed 128/65664 paired entries, rest UNKNOWN')
  if($c.fault -ceq 'one'){Check-D604 ($d.evidence.mirrorDifferentEntries -gt 0 -and $j.fatCopyWinner -ceq 'not_selected') 'FAT2 missing anomaly observed, no winner'}
  if($c.fault -ceq 'both'){Check-D604 ($d.evidence.mirrorDifferentEntries -eq 0 -and $j.originalIdentity -ceq 'unknown') 'Both FATs identically corrupt not proven healthy'}
  if($c.fault -ceq 'far'){Check-D604 ($j.metrics.unobservedPairedEntryIndices -gt 65000) 'Remote FAT2 index60000 remains UNKNOWN'}
  if($c.id -ceq 'clean_spc1'){$sample=$x;$sampleLength=[long]$bytes.Length}
 }elseif($c.expect -ceq 'blocked'){
  $blocked++
  Check-D604 ($d.guardDecision -cne 'candidate_geometry_unverified' -and
      $d.metrics.fatFixedReturnedBytes -eq 0 -and $j.decision -ceq 'consistent_blocked_unattested' -and
      $null -eq $j.metrics.pairedCoveragePercent) ($c.id+' unsafe geometry no FAT reads and no invented paired coverage')
 }else{
  $unknown++
  Check-D604 ($d.metrics.prematureSourceZeroReads -gt 0 -and
      $j.decision -ceq 'unknown' -and $null -eq $j.metrics.pairedCoveragePercent -and
      $null -eq $j.metrics.pairedFullyObservedEntries) ($c.id+' incomplete physical returned 4B becomes UNKNOWN')
 }
 $actual+=$x.actual;$unique+=$x.unique;$calls+=$x.calls
 Write-Host ('D6-04 case={0} guard={1} join={2} paired={3}/65664 actual/unique={4}/{5} calls={6} zero={7}' -f $c.id,$d.guardDecision,$j.decision,$j.metrics.pairedFullyObservedEntries,$x.actual,$x.unique,$x.calls,$x.early)
 $bytes=$null;$fixture=$null
 [GC]::Collect()
}
Check-D604 ($numeric -eq 6 -and $blocked -eq 3 -and $unknown -eq 2) 'Frozen corpus 6 numeric, 3 BPB blocked, 2 physical EOF UNKNOWN'
Check-D604 ($null -ne $sample -and @($sample.events).Count -gt 4) 'External successful event baseline retained for adversarial mutation tests'
$args=@{GuardedResult=$sample.d;SourceLengthBytes=$sampleLength;OuterPhysicalReadCalls=$sample.calls;OuterPrematureZeroReads=$sample.early}
$ok=Compare-ChappyFatGuardedReturnedSourceEvents @args -OuterReturnedEvents $sample.events
Check-D604 ($ok.decision -ceq 'consistent_numeric_candidate_unattested') 'Unmodified independent source receipt positions agree, authenticity still unknown'
$missing=@($sample.events | Select-Object -Skip 1)
$bad=Compare-ChappyFatGuardedReturnedSourceEvents @args -OuterReturnedEvents $missing
Check-D604 ($bad.decision -ceq 'unknown' -and $null -eq $bad.metrics.pairedCoveragePercent) 'Missing success event rejected'
$replay=@($sample.events)+@($sample.events[0])
$bad=Compare-ChappyFatGuardedReturnedSourceEvents @args -OuterReturnedEvents $replay
Check-D604 ($bad.decision -ceq 'unknown') 'Replay source event rejected'
$shift=@(foreach($ev in $sample.events){[pscustomobject]@{Consumer='fat';OffsetBytes=[long]$ev.OffsetBytes;ReturnedBytes=[long]$ev.ReturnedBytes}})
$shift[0].OffsetBytes++
$bad=Compare-ChappyFatGuardedReturnedSourceEvents @args -OuterReturnedEvents $shift
Check-D604 ($bad.decision -ceq 'unknown') 'Shifted event same bytes refused'
$reordered=@($sample.events)
$tmp=$reordered[0];$reordered[0]=$reordered[1];$reordered[1]=$tmp
$bad=Compare-ChappyFatGuardedReturnedSourceEvents @args -OuterReturnedEvents $reordered
Check-D604 ($bad.decision -ceq 'unknown') 'Reordered success events refused'
$wrong=@(foreach($ev in $sample.events){[pscustomobject]@{Consumer='fat';OffsetBytes=[long]$ev.OffsetBytes;ReturnedBytes=[long]$ev.ReturnedBytes}})
$wrong[0].Consumer='directory'
$bad=Compare-ChappyFatGuardedReturnedSourceEvents @args -OuterReturnedEvents $wrong
Check-D604 ($bad.decision -ceq 'unknown') 'External source-event from another consumer refused'
$bad=Compare-ChappyFatGuardedReturnedSourceEvents -GuardedResult $sample.d -OuterReturnedEvents $sample.events -SourceLengthBytes $sampleLength -OuterPhysicalReadCalls ($sample.calls+1) -OuterPrematureZeroReads $sample.early
Check-D604 ($bad.decision -ceq 'unknown') 'Independent physical Read call count mismatch refused'
$fakeD=($sample.d | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
$fakeD.evidence.pairedFullyObservedEntries++
$bad=Compare-ChappyFatGuardedReturnedSourceEvents -GuardedResult $fakeD -OuterReturnedEvents $sample.events -SourceLengthBytes $sampleLength -OuterPhysicalReadCalls $sample.calls -OuterPrematureZeroReads $sample.early
Check-D604 ($bad.decision -ceq 'unknown' -and $null -eq $bad.metrics.pairedFullyObservedEntries) 'Forged D pair count independently rejected'
$fakeD=($sample.d | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
$fakeD.metrics.uniqueReturnedBytes++
$bad=Compare-ChappyFatGuardedReturnedSourceEvents -GuardedResult $fakeD -OuterReturnedEvents $sample.events -SourceLengthBytes $sampleLength -OuterPhysicalReadCalls $sample.calls -OuterPrematureZeroReads $sample.early
Check-D604 ($bad.decision -ceq 'unknown') 'Forged D unique return byte total refused'
$fake=[byte[]]::new(8192)
$w=[IO.MemoryStream]::new($fake,$true)
try{
 $d=Get-ChappyFatGuardedResult -Stream $w -EnableGuardedDiagnostics
 Check-D604 ($d.status -ceq 'unknown' -and $d.metrics.actualReturnedBytes -eq 0 -and
     @($d.sourceReturnedEvents).Count -eq 0 -and -not $d.writePermitted) 'Writable stream refused before physical Read and no transcript'
}finally{$w.Dispose()}
$disabled=Get-ChappyFatGuardedResult
Check-D604 ($disabled.status -ceq 'disabled' -and @($disabled.sourceReturnedEvents).Count -eq 0) 'D guard remains disabled by default, even with event extension'
Write-Host ('D6-04 SYNTHETIC 11 cases: numeric={0} blocked={1} UNKNOWN={2} actualB={3} summedUnique={4} repeated={5} physicalReads={6}' -f $numeric,$blocked,$unknown,$actual,$unique,($actual-$unique),$calls)
Write-Host ('Team D D6-04 guarded source-join: {0} PASS / {1} FAIL' -f $script:Pass,$script:Fail)
if($script:Fail -gt 0){exit 1}
