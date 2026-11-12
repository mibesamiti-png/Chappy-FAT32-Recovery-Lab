#Requires -Version 5.1
# Issue #73 R6-P11 — only artificial memory images; preregistered R0/R1:
# https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6826717174
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32GeometryTrust.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32MirrorWindows.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32ChainStats.psm1') -Force
$script:good=0;$script:bad=0
function Assert-D25([bool]$yes,[string]$msg) {
    if($yes){$script:good++;Write-Host ('PASS '+$msg)}
    else{$script:bad++;Write-Host ('FAIL '+$msg)}
}
function Throws-D25([scriptblock]$fn) {
    try{$null=& $fn;return $false}catch{return $true}
}
# Physical returned bytes, not claimed spans or attempted source requests.
if(-not ('D25ReadMeter' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D25Span {
    public long Start {get;set;}
    public int Size {get;set;}
}
public sealed class D25ReadMeter : Stream {
    readonly MemoryStream backing;
    readonly Dictionary<long,byte> seen=new Dictionary<long,byte>();
    readonly List<D25Span> spans=new List<D25Span>();
    readonly long dLimit,aLimit,stop;
    readonly int maxCalls,chunk;
    long used=0,calls=0,zeros=0,denied=0;
    public D25ReadMeter(byte[] image,long dCap,long aCap,int callCap,long earlyStop,int maxChunk){
        if(image==null || dCap<32 || dCap>2048 || aCap<dCap || aCap>120000 ||
           callCap<1 || callCap>256 || earlyStop<0 || maxChunk<1 || maxChunk>4096)
           throw new ArgumentException("Invalid artificial source budget");
        backing=new MemoryStream(image,false);
        dLimit=dCap;aLimit=aCap;maxCalls=callCap;stop=earlyStop;chunk=maxChunk;
    }
    public long Actual {get{return used;}}
    public long Unique {get{return seen.Count;}}
    public long Duplicate {get{return used-seen.Count;}}
    public long Calls {get{return calls;}}
    public long EarlyZeros {get{return zeros;}}
    public long Denied {get{return denied;}}
    public bool Has(long p,int n){
        if(p<0 || n<0 || p>long.MaxValue-n)return false;
        for(int i=0;i<n;i++)if(!seen.ContainsKey(p+i))return false;
        return true;
    }
    public uint ObservedUInt32(long p){
        if(!Has(p,4))throw new InvalidOperationException("Not physically returned");
        return (uint)(seen[p]|((uint)seen[p+1]<<8)|((uint)seen[p+2]<<16)|((uint)seen[p+3]<<24));
    }
    public HashSet<long> Complete(long start,long size){
        var full=new HashSet<long>();
        if(start<0 || size<=0 || size%4!=0 || start>long.MaxValue-size)return full;
        var candidates=new HashSet<long>();
        long end=start+size;
        foreach(var span in spans){
            long lo=Math.Max(start,span.Start),hi=Math.Min(end,span.Start+span.Size);
            for(long p=lo;p<hi;p++)candidates.Add((p-start)/4);
        }
        foreach(long i in candidates)if(Has(start+i*4,4))full.Add(i);
        return full;
    }
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return backing.Length;}}
    public override long Position {get{return backing.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long p,SeekOrigin o){return backing.Seek(p,o);}
    public override int Read(byte[] b,int offset,int count){
        if(b==null || offset<0 || count<0 || offset>b.Length-count)throw new ArgumentException("Invalid Read");
        if(calls>=maxCalls || count>dLimit-used || count>aLimit-used){
            denied++;throw new IOException("D25.bound_rejected");
        }
        calls++;
        if(count==0)return 0;
        long p=backing.Position;
        if(used>=stop){if(p<backing.Length)zeros++;return 0;}
        int n=backing.Read(b,offset,(int)Math.Min((long)count,Math.Min((long)chunk,stop-used)));
        if(n==0 && p<backing.Length)zeros++;
        if(n>0){
            used+=n;spans.Add(new D25Span{Start=p,Size=n});
            for(int i=0;i<n;i++)seen[p+i]=b[offset+i];
        }
        return n;
    }
    public override void Flush(){}
    public override void SetLength(long n){throw new NotSupportedException();}
    public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
    protected override void Dispose(bool disposing){if(disposing)backing.Dispose();base.Dispose(disposing);}
}
'@
}
function Get-D25Sample {
    param([D25ReadMeter]$Source,[ValidateSet('fixed','adaptive')][string]$Method)
    if(-not $Source.CanRead -or -not $Source.CanSeek -or $Source.CanWrite){
        throw 'Require nonwritable readable seekable input'
    }
    $unknown=[pscustomobject]@{state='unknown';n=$null;f1=$null;f2=$null;pairs=$null;pct=$null;
        diff=0L;cycles=0L;detected=$false;target=$null;starts=@();scanIncomplete=$true;
        copyWinner='not_selected';owner='unknown';original='unknown';writePermitted=$false}
    $geo=Get-ChappyFatGeometryTrust -Stream $Source -MaxReadBytes 1024
    if($geo.trustDecision -eq 'reject' -or $null -eq $geo.geometry -or
       $null -eq $geo.geometry.fat1OffsetBytes -or
       $null -eq $geo.geometry.fat2OffsetBytes -or
       $null -eq $geo.geometry.fatLengthBytes -or
       $null -eq $geo.geometry.dataClusterCount){return $unknown}
    $a=[long]$geo.geometry.fat1OffsetBytes;$b=[long]$geo.geometry.fat2OffsetBytes
    $length=[long]$geo.geometry.fatLengthBytes;$clusters=[long]$geo.geometry.dataClusterCount
    $entries=[long]($length/4L)
    if($a -lt 0 -or $b -le $a -or $length -le 0 -or $length%4 -ne 0 -or
       $entries -gt 1000000 -or $clusters -lt 65525 -or $entries -lt ($clusters+2) -or
       $a -gt $Source.Length-$length -or $b -gt $Source.Length-$length -or
       $a+$length -gt $b){return $unknown}
    $args=@{Stream=$Source;Fat1OffsetBytes=$a;Fat2OffsetBytes=$b;
        FatLengthBytes=$length;WindowEntries=16;MaxWindows=1;MaxReadBytes=128}
    $first=Get-ChappyFatMirrorWindows @args -StartEntry 0
    $diff=[long]$first.metrics.differentEntries
    $starts=@([long]0);$target=$null
    # Distinguish one incomplete 16-entry read from the whole-FAT partial flag.
    $prefixComplete=(@($first.items).Count -eq 1 -and
        $first.items[0].comparedEntries -eq 16 -and -not $first.items[0].scanIncomplete)
    if($Method -eq 'adaptive' -and $prefixComplete) {
        foreach($i in 9..15) {
            $p=$a+[long]$i*4L;$q=$b+[long]$i*4L
            if(-not $Source.Has($p,4) -or -not $Source.Has($q,4)){continue}
            $x=([long]$Source.ObservedUInt32($p)) -band 0x0FFFFFFF
            $y=([long]$Source.ObservedUInt32($q)) -band 0x0FFFFFFF
            if($x -eq $y -and $x -ge 16 -and $x -le ($clusters+1L) -and
               $x -le ($entries-16L)){$target=[long]$x;break}
        }
    }
    $later=@([long]128,[long]256)
    if($null -ne $target){$later=@([long]$target,[long]128)}
    foreach($entry in $later){
        $m=Get-ChappyFatMirrorWindows @args -StartEntry ([long]$entry)
        $diff += [long]$m.metrics.differentEntries
        $starts += [long]$entry
    }
    $chainArgs=@{Stream=$Source;Fat1OffsetBytes=$a;Fat2OffsetBytes=$b;
        FatLengthBytes=$length;MaxDataCluster=($clusters+1L);
        StartClusters=([long[]]@(2,3,4,5,6,7,8));MaxStepsPerChain=8;
        MaxTotalEntries=32;MaxReadBytes=448}
    $chain=Get-ChappyFatChainAnomalyStats @chainArgs
    $cycles=@($chain.items|Where-Object {$_.terminal -eq 'cycle'}).Count
    if($Source.EarlyZeros -gt 0 -or -not $prefixComplete){return $unknown}
    $s1=$Source.Complete($a,$length);$s2=$Source.Complete($b,$length)
    $pair=0L
    foreach($idx in $s1){if($s2.Contains($idx)){$pair++}}
    return [pscustomobject]@{state='partial_numeric_only';n=$entries;f1=$s1.Count;
        f2=$s2.Count;pairs=$pair;pct=(100.0*$pair/[double]$entries);
        diff=$diff;cycles=$cycles;detected=($diff -gt 0 -or $cycles -gt 0);
        target=$target;starts=@($starts);scanIncomplete=$true;
        copyWinner='not_selected';owner='unknown';original='unknown';writePermitted=$false}
}
function Invoke-D25Trial {
    param([byte[]]$Bytes,[string]$Method,[long]$Stop,[int]$Chunk)
    $source=[D25ReadMeter]::new($Bytes,2048L,120000L,256,$Stop,$Chunk)
    try {
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $result=Get-D25Sample -Source $source -Method $Method
        $watch.Stop()
        return [pscustomobject]@{mode=$Method;res=$result;actual=$source.Actual;
            unique=$source.Unique;repeat=$source.Duplicate;calls=$source.Calls;
            early=$source.EarlyZeros;denied=$source.Denied;ms=$watch.ElapsedMilliseconds}
    }finally{$source.Dispose()}
}
function Patch-D25([byte[]]$Data,[long]$Offset,[uint32]$Value){
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$Data,[int]$Offset,4)
}
function Sha-D25([byte[]]$Data){
    $h=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($h.ComputeHash($Data)).Replace('-','')}
    finally{$h.Dispose()}
}
# The only holder of seed, mutation position, original SHA and labels is scorer.
$cases=@(
    [pscustomobject]@{id='clean';truth=$false;unknown=$false;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='healthy_long_link';truth=$false;unknown=$false;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='long_link_remote_fault';truth=$true;unknown=$false;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='long_link_displaced256';truth=$true;unknown=$false;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='fat2_cycle';truth=$true;unknown=$false;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='both_copy_cycle';truth=$true;unknown=$false;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='unlinked_remote60000';truth=$true;unknown=$false;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='bad_spc';truth=$null;unknown=$true;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='bad_fat';truth=$null;unknown=$true;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='early_zero';truth=$null;unknown=$true;stop=1100L;chunk=7}
)
$scores=@{fixed=@{TP=0;FP=0;FN=0;TN=0};adaptive=@{TP=0;FP=0;FN=0;TN=0}}
$totals=@{fixed=@{actual=0L;unique=0L;calls=0L};adaptive=@{actual=0L;unique=0L;calls=0L}}
$unknownCount=0;$heldOutCount=0
foreach($seed in @(202611,202612,202613)){
    $spc=$(if($seed -eq 202612){2}else{1})
    $remote=2048+(($seed*97)%40000) # scorer-only, not candidate algorithm
    foreach($c in $cases){
        $fixture=New-ChappyA3DStandardFixture -Seed $seed -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
        [byte[]]$data=$fixture.image
        $fatSectors=[long][Math]::Ceiling(4.0*(65541+2)/512.0)
        $fat1=33L*512L;$fat2=$fat1+$fatSectors*512L
        if($c.id -match '^(healthy_long|long_link)'){
            foreach($fat in @($fat1,$fat2)){
                Patch-D25 $data ($fat+56L) ([uint32]$remote)
                Patch-D25 $data ($fat+[long]$remote*4L) ([uint32]0x0FFFFFFF)
            }
        }
        switch($c.id){
            'long_link_remote_fault' {Patch-D25 $data ($fat2+[long]$remote*4L) ([uint32]1)}
            'long_link_displaced256' {Patch-D25 $data ($fat2+1024L) ([uint32]1)}
            'fat2_cycle' {Patch-D25 $data ($fat2+16L) ([uint32]4)}
            'both_copy_cycle' {
                Patch-D25 $data ($fat1+16L) ([uint32]4)
                Patch-D25 $data ($fat2+16L) ([uint32]4)
            }
            'unlinked_remote60000' {Patch-D25 $data ($fat2+240000L) ([uint32]1)}
            'bad_spc' {$data[525]=0}
            'bad_fat' {Patch-D25 $data 548L ([uint32]::MaxValue)}
        }
        $sha=Sha-D25 $data
        $old=Invoke-D25Trial -Bytes $data -Method fixed -Stop $c.stop -Chunk $c.chunk
        $new=Invoke-D25Trial -Bytes $data -Method adaptive -Stop $c.stop -Chunk $c.chunk
        Assert-D25 ((Sha-D25 $data) -ceq $sha) ($seed.ToString()+' '+$c.id+' source unchanged')
        foreach($test in @($old,$new)){
            $res=$test.res
            Assert-D25 ($test.actual -le 2048 -and $test.actual -le 120000 -and
                $test.unique -le $test.actual -and $test.repeat -eq ($test.actual-$test.unique) -and
                $test.calls -le 256 -and $test.denied -eq 0) ($seed.ToString()+' '+$c.id+' '+$test.mode+' physical bounds')
            Assert-D25 ($res.scanIncomplete -and $res.copyWinner -ceq 'not_selected' -and
                $res.owner -ceq 'unknown' -and $res.original -ceq 'unknown' -and
                -not $res.writePermitted) ($seed.ToString()+' '+$c.id+' '+$test.mode+' no owner/winner/repair')
            if($c.unknown){
                Assert-D25 ($res.state -ceq 'unknown' -and $null -eq $res.n -and
                    $null -eq $res.pct) ($seed.ToString()+' '+$c.id+' '+$test.mode+' UNKNOWN')
            }else{
                Assert-D25 ($res.state -ceq 'partial_numeric_only' -and $res.n -eq 65664 -and
                    $res.f1 -gt 0 -and $res.f2 -gt 0 -and $res.pairs -gt 0 -and
                    $res.pairs -lt $res.n -and $res.pct -lt 1) ($seed.ToString()+' '+$c.id+' '+$test.mode+' physical FAT coverage partial')
            }
            $totals[$test.mode].actual+=$test.actual
            $totals[$test.mode].unique+=$test.unique
            $totals[$test.mode].calls+=$test.calls
        }
        if($c.unknown){
            $unknownCount++
            if($c.id -eq 'early_zero'){
                Assert-D25 ($old.early -gt 0 -and $new.early -gt 0 -and
                    $old.actual -eq 1100 -and $new.actual -eq 1100) ($seed.ToString()+' physical short zero remains UNKNOWN')
            }
        }else{
            foreach($test in @($old,$new)){
                $score=$scores[$test.mode]
                if($c.truth){
                    if($test.res.detected){$score.TP++}else{$score.FN++}
                }else{
                    if($test.res.detected){$score.FP++}else{$score.TN++}
                }
            }
            if($c.id -match '^(healthy_long|long_link)'){
                Assert-D25 ($new.res.target -eq $remote -and $new.res.starts[1] -eq $remote -and
                    $old.res.starts[2] -eq 256) ($seed.ToString()+' nonoracle link-driven remote sample')
            }else{
                Assert-D25 ($null -eq $new.res.target -and ($new.res.starts -join ',') -ceq '0,128,256') ($seed.ToString()+' no observed long link, fixed fallback')
            }
            if($c.id -eq 'long_link_remote_fault'){
                Assert-D25 (-not $old.res.detected -and $new.res.detected) ($seed.ToString()+' adaptive remote advantage measured')
            }
            if($c.id -eq 'long_link_displaced256'){
                Assert-D25 ($old.res.detected -and -not $new.res.detected) ($seed.ToString()+' adaptive displaced index256 regression measured')
            }
            if($c.id -eq 'both_copy_cycle'){
                Assert-D25 ($old.res.diff -eq 0 -and $new.res.diff -eq 0 -and
                    $old.res.cycles -gt 0 -and $new.res.cycles -gt 0) ($seed.ToString()+' identical corruption not healthy')
            }
            if($c.id -eq 'unlinked_remote60000'){
                Assert-D25 (-not $old.res.detected -and -not $new.res.detected) ($seed.ToString()+' unsampled far corruption missed honestly')
            }
        }
        if($seed -ne 202611){$heldOutCount++}
        Write-Host ('D P11 seed={0} case={1} fixed={2}/{3} adaptive={4}/{5} FAT paired={6}/{7} actualBytes={8}/{9} calls={10}/{11} original=UNKNOWN' -f
            $seed,$c.id,$old.res.detected,$old.res.state,$new.res.detected,
            $new.res.state,$old.res.pairs,$new.res.pairs,$old.actual,$new.actual,
            $old.calls,$new.calls)
        $data=$null;$fixture=$null;[GC]::Collect()
    }
}
Assert-D25 ($heldOutCount -eq 20 -and $unknownCount -eq 9) 'Two held-out seeds, nine UNKNOWN conditions'
foreach($mode in @('fixed','adaptive')){
    $s=$scores[$mode]
    Assert-D25 (($s.TP+$s.FN) -eq 15 -and ($s.FP+$s.TN) -eq 6 -and $s.FP -eq 0) ($mode+' controlled artificial scorer labels')
}
Assert-D25 ($scores.adaptive.TP -eq $scores.fixed.TP) 'No aggregate improvement: remote gain offsets index256 miss'
# Standalone oracle-free bad numeric target: both sampled FAT entry14 values
# point outside the geometry. Never follow, probe, or infer an owner from them.
$outside=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster 1
[byte[]]$outsideBytes=$outside.image
$outsideFatSectors=[long][Math]::Ceiling(4.0*(65541+2)/512.0)
$outsideFat1=33L*512L
$outsideFat2=$outsideFat1+$outsideFatSectors*512L
Patch-D25 $outsideBytes ($outsideFat1+56L) ([uint32]70000)
Patch-D25 $outsideBytes ($outsideFat2+56L) ([uint32]70000)
$outsideSha=Sha-D25 $outsideBytes
$outsideBase=Invoke-D25Trial -Bytes $outsideBytes -Method fixed -Stop ([long]::MaxValue) -Chunk 4096
$outsideTest=Invoke-D25Trial -Bytes $outsideBytes -Method adaptive -Stop ([long]::MaxValue) -Chunk 4096
Assert-D25 ($null -eq $outsideTest.res.target -and
    ($outsideTest.res.starts -join ',') -ceq '0,128,256') 'Out-of-range observed link is rejected, fixed safe fallback'
Assert-D25 ($outsideTest.actual -le 2048 -and $outsideTest.denied -eq 0 -and
    $outsideTest.res.state -ceq 'partial_numeric_only' -and
    $outsideTest.res.original -ceq 'unknown' -and
    -not $outsideTest.res.writePermitted) 'Rejected numeric link never authorizes identity/repair'
Assert-D25 ($outsideBase.actual -eq $outsideTest.actual -and
    (Sha-D25 $outsideBytes) -ceq $outsideSha) 'Out-of-range negative input unchanged and same physical returned bytes'
$outside=$null;$outsideBytes=$null
[GC]::Collect()
$fake=[byte[]]::new(4096)
$meter=[D25ReadMeter]::new($fake,2048L,120000L,256,[long]::MaxValue,4096)
try{
    $tooLarge=[byte[]]::new(2049)
    Assert-D25 (Throws-D25 {[void]$meter.Read($tooLarge,0,2049)}) 'Physical source overrun refused'
    Assert-D25 ($meter.Actual -eq 0 -and $meter.Unique -eq 0 -and $meter.Denied -eq 1) 'Refusal creates no false evidence'
}finally{$meter.Dispose()}
$writable=[IO.MemoryStream]::new($fake,$true)
try{
    Assert-D25 (Throws-D25 {Get-ChappyFatGeometryTrust -Stream $writable -MaxReadBytes 1024}) 'D module rejects writable stream'
}finally{$writable.Dispose()}
foreach($mode in @('fixed','adaptive')){
    $s=$scores[$mode];$t=$totals[$mode]
    Write-Host ('D P11 {0}: TP={1} FP={2} FN={3} TN={4} UNKNOWN={5} physical returned={6} unique-per-source sum={7} duplicates={8} calls={9}' -f
        $mode,$s.TP,$s.FP,$s.FN,$s.TN,$unknownCount,
        $t.actual,$t.unique,($t.actual-$t.unique),$t.calls)
}
Write-Host ('Team D R6-P11 adaptive FAT research: {0} PASS, {1} FAIL' -f $script:good,$script:bad)
if($script:bad -gt 0){exit 1}
