#Requires -Version 5.1
# Team D Issue 73 P9: synthetic-only non-oracle rotating FAT windows vs fixed A/B.
# All mutations, labels and hashes stay in the external test scorer.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32ObservedIoEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32GeometryTrust.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32MirrorWindows.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32ChainStats.psm1') -Force

$script:good=0;$script:bad=0
function Check-D22([bool]$ok,[string]$name) {
    if($ok){$script:good++;Write-Host ('PASS '+$name)}
    else{$script:bad++;Write-Host ('FAIL '+$name)}
}
function Hash-D22([byte[]]$bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}
    finally{$sha.Dispose()}
}
function Throws-D22([scriptblock]$action) {
    try{$null=& $action;return $false}catch{return $true}
}
# Physical Stream.Read() meter, outside both D diagnostic algorithms.
# Actual returned bytes, distinct physical positions, and calls have one
# common hard per-invocation ceiling. Source is strictly nonwritable.
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D22PhysicalMeter : Stream {
    readonly MemoryStream m;
    readonly HashSet<long> covered=new HashSet<long>();
    readonly long maxBytes,maxCalls,earlyStop;
    readonly int chunk;
    long used=0,calls=0;
    bool early=false,callClipped=false;
    public D22PhysicalMeter(byte[] data,long bytes,long callsLimit,long stop,int chunkSize) {
        m=new MemoryStream(data,false);
        maxBytes=bytes;maxCalls=callsLimit;earlyStop=stop;chunk=chunkSize;
    }
    public long Actual {get{return used;}}
    public long Unique {get{return covered.Count;}}
    public long Calls {get{return calls;}}
    public bool Early {get{return early;}}
    public bool CallClipped {get{return callClipped;}}
    public bool Has(long at,int n) {
        for(int i=0;i<n;i++)if(!covered.Contains(at+i))return false;
        return true;
    }
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return m.Length;}}
    public override long Position {get{return m.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long x,SeekOrigin o){return m.Seek(x,o);}
    public override int Read(byte[] b,int off,int count) {
        if(calls>=maxCalls){callClipped=true;return 0;}
        calls++;
        if(used>=maxBytes)return 0;
        if(used>=earlyStop){early=true;return 0;}
        long at=m.Position;
        int n=m.Read(b,off,(int)Math.Min((long)count,Math.Min((long)chunk,
            Math.Min(maxBytes-used,earlyStop-used))));
        used+=n;
        for(int i=0;i<n;i++)covered.Add(at+i);
        return n;
    }
    public override void Flush(){}
    public override void SetLength(long n){throw new NotSupportedException();}
    public override void Write(byte[] b,int off,int n){throw new NotSupportedException();}
    protected override void Dispose(bool disposing){if(disposing)m.Dispose();base.Dispose(disposing);}
}
'@

# Both schedules are fixed for every case. The external scorer's mutation
# labels, data offsets and original SHA are NEVER passed to these functions.
# A single test-only bounded alternative. No file identity, mutation site,
# scorer truth or original SHA enters this function.
function Get-D22Evidence {
    param([IO.Stream]$Stream,[string]$Mode,[int]$PublicSeed)
    if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite) {
        throw 'Strictly nonwritable seekable Stream required'
    }
    $g=Get-ChappyFatGeometryTrust -Stream $Stream -MaxReadBytes 1024
    $diff=0L;$cycle=0L;$windows=0;$declared=0L
    $starts=@();$partial=$false
    if($null -ne $g.geometry -and $null -ne $g.geometry.fat1OffsetBytes -and
        $null -ne $g.geometry.fat2OffsetBytes -and
        $null -ne $g.geometry.fatLengthBytes -and
        $null -ne $g.geometry.dataClusterCount){
        $fat1=[long]$g.geometry.fat1OffsetBytes
        $fat2=[long]$g.geometry.fat2OffsetBytes
        $length=[long]$g.geometry.fatLengthBytes
        $declared=[long][Math]::Floor($length/4)
        $salt=[long][Math]::Floor($fat1/512)+[long][Math]::Floor($length/512)
        if($Mode -eq 'fixed'){
            $starts=@([long]0,[long]128,[long]256)
        }else{
            $first=64L+16L*((([long]$PublicSeed*37L+$salt)%22L))
            $second=416L+16L*((([long]$PublicSeed*17L+$declared)%72L))
            $starts=@([long]0,[long]$first,[long]$second)
        }
        $a=@{Stream=$Stream;Fat1OffsetBytes=$fat1;Fat2OffsetBytes=$fat2
            FatLengthBytes=$length;WindowEntries=16;MaxWindows=1;MaxReadBytes=128}
        foreach($e in $starts){
            if($e -lt 0 -or $e+16 -gt $declared){$partial=$true;continue}
            try{
                $m=Get-ChappyFatMirrorWindows @a -StartEntry ([long]$e)
                $diff += [long]$m.metrics.differentEntries
                $windows++
                if(@($m.items)[0].scanIncomplete){$partial=$true}
            }catch{$partial=$true}
        }
        try{
            $c=@{Stream=$Stream;Fat1OffsetBytes=$fat1;Fat2OffsetBytes=$fat2
                FatLengthBytes=$length
                MaxDataCluster=([long]$g.geometry.dataClusterCount+1L)
                StartClusters=@([long[]]@(2,3,4,5,6,7,8))
                MaxStepsPerChain=8;MaxTotalEntries=32;MaxReadBytes=448}
            $chains=Get-ChappyFatChainAnomalyStats @c
            $cycle=@($chains.items | Where-Object {$_.terminal -eq 'cycle'}).Count
            if($chains.scanIncomplete){$partial=$true}
        }catch{$partial=$true}
    }else{$partial=$true}
    return [pscustomobject]@{
        starts=@($starts);comparedWindowEntries=16*$windows
        fatEntriesDeclared=$declared
        different=$diff;cycles=$cycle
        parserDecision=[string]$g.trustDecision
        parserReasons=@($g.reasons)
        partialSourceEvidence=$partial
        scanIncomplete=$true;fullFatVerified=$false
        fileOwner='unknown';originalIdentity='unknown'
        fatWinner='not_selected';writePermitted=$false
    }
}
function Invoke-D22 {
    param([byte[]]$Data,[string]$Mode,[int]$Seed,
        [int]$Cap=2048,[long]$Early=[long]::MaxValue,[int]$Chunk=4096)
    $physical=[D22PhysicalMeter]::new($Data,$Cap,256L,$Early,$Chunk)
    try{
        $sw=[Diagnostics.Stopwatch]::StartNew()
        $r=Get-D22Evidence -Stream $physical -Mode $Mode -PublicSeed $Seed
        $sw.Stop()
        return [pscustomobject]@{
            result=$r
            detected=($r.different -gt 0 -or $r.cycles -gt 0)
            actual=[long]$physical.Actual
            unique=[long]$physical.Unique
            calls=[long]$physical.Calls
            early=$physical.Early
            saw128=$physical.Has(37888L,4)
            saw256=$physical.Has(38400L,4)
            saw512=$physical.Has(39424L,4)
            saw768=$physical.Has(40448L,4)
            saw3000=$physical.Has(49376L,4)
            timeMs=[long]$sw.ElapsedMilliseconds
        }
    }finally{$physical.Dispose()}
}
# External artificial scorer, never a diagnostic parameter.
$fp=0;$tp=0;$fn=0;$tn=0;$rp=0;$rfp=0;$rfn=0;$rtn=0;$unknown=0
$oldBytes=0L;$newBytes=0L;$oldUnique=0L;$newUnique=0L
$oldCalls=0L;$newCalls=0L
$plans=New-Object 'System.Collections.Generic.HashSet[string]'
$locations=New-Object 'System.Collections.Generic.HashSet[long]'
foreach($seed in @(202611,202612,202613)){
    $images=@{}
    foreach($id in @('M00','M01','M02','M03','M05','X02')){
        $f=New-ChappyA3DDamagedFixture -Case $id -Seed $seed
        Check-D22 ((Hash-D22 $f.image) -ceq $f.manifest.imageSha256) ($seed+' fixture SHA '+$id)
        $images[$id]=[byte[]]$f.image
    }
    [byte[]]$clean=$images['M00']
    Check-D22 ([BitConverter]::ToUInt32($clean,37392) -eq 5) ($seed+' scorer confirms FAT2 synthetic cluster4 link')
    foreach($m in @(
        [pscustomobject]@{id='CONFLICT';at=37392;v=[uint32]8},
        [pscustomobject]@{id='REMOTE128';at=37888;v=[uint32]1},
        [pscustomobject]@{id='REMOTE256';at=38400;v=[uint32]1},
        [pscustomobject]@{id='REMOTE512';at=39424;v=[uint32]1},
        [pscustomobject]@{id='REMOTE768';at=40448;v=[uint32]1},
        [pscustomobject]@{id='REMOTE3000';at=49376;v=[uint32]1}
    )){
        [byte[]]$copy=[byte[]]$clean.Clone()
        [Array]::Copy([BitConverter]::GetBytes($m.v),0,$copy,[int]$m.at,4)
        Check-D22 ((Hash-D22 $copy) -cne (Hash-D22 $clean)) ($seed+' scorer-only mutation '+$m.id)
        $images[$m.id]=$copy
    }
    [byte[]]$bad=[byte[]]$clean.Clone();$bad[525]=0
    $images['INVALID_BPB']=$bad
    Check-D22 ((Hash-D22 $bad) -cne (Hash-D22 $clean)) ($seed+' BPB corruption present')
    $rows=@(
        [pscustomobject]@{id='M00';src='M00';truth=$false;cap=2048;stop=[long]::MaxValue;chunk=4096},
        [pscustomobject]@{id='M01';src='M01';truth=$false;cap=2048;stop=[long]::MaxValue;chunk=4096},
        [pscustomobject]@{id='M02';src='M02';truth=$true;cap=2048;stop=[long]::MaxValue;chunk=4096},
        [pscustomobject]@{id='M03';src='M03';truth=$true;cap=2048;stop=[long]::MaxValue;chunk=4096},
        [pscustomobject]@{id='CONFLICT';src='CONFLICT';truth=$true;cap=2048;stop=[long]::MaxValue;chunk=4096},
        [pscustomobject]@{id='REMOTE128';src='REMOTE128';truth=$true;cap=2048;stop=[long]::MaxValue;chunk=4096},
        [pscustomobject]@{id='REMOTE256';src='REMOTE256';truth=$true;cap=2048;stop=[long]::MaxValue;chunk=4096},
        [pscustomobject]@{id='REMOTE512';src='REMOTE512';truth=$true;cap=2048;stop=[long]::MaxValue;chunk=4096},
        [pscustomobject]@{id='REMOTE768';src='REMOTE768';truth=$null;cap=2048;stop=[long]::MaxValue;chunk=4096},
        [pscustomobject]@{id='REMOTE3000';src='REMOTE3000';truth=$null;cap=2048;stop=[long]::MaxValue;chunk=4096},
        [pscustomobject]@{id='M05';src='M05';truth=$null;cap=2048;stop=[long]::MaxValue;chunk=4096},
        [pscustomobject]@{id='X02';src='X02';truth=$null;cap=2048;stop=[long]::MaxValue;chunk=4096},
        [pscustomobject]@{id='EARLY_STOP';src='M02';truth=$null;cap=2048;stop=1200L;chunk=7},
        [pscustomobject]@{id='CAP32';src='M03';truth=$null;cap=32;stop=[long]::MaxValue;chunk=4096},
        [pscustomobject]@{id='INVALID_BPB';src='INVALID_BPB';truth=$null;cap=2048;stop=[long]::MaxValue;chunk=4096}
    )
    $seedOld=0;$seedRot=0
    foreach($x in $rows){
        [byte[]]$bytes=$images[$x.src]
        $before=Hash-D22 $bytes
        $o=Invoke-D22 -Data $bytes -Mode fixed -Seed $seed -Cap $x.cap -Early $x.stop -Chunk $x.chunk
        $n=Invoke-D22 -Data $bytes -Mode rotate -Seed $seed -Cap $x.cap -Early $x.stop -Chunk $x.chunk
        Check-D22 ((Hash-D22 $bytes) -ceq $before) ($seed+' '+$x.id+' synthetic input unmodified after A/B')
        foreach($r in @($o,$n)){
            Check-D22 ($r.actual -le $x.cap -and $r.unique -le $r.actual -and
                $r.calls -le 256) ($seed+' '+$x.id+' physical bytes/Read() cap')
            Check-D22 ($r.result.scanIncomplete -and -not $r.result.fullFatVerified -and
                -not $r.result.writePermitted -and $r.result.fatWinner -eq 'not_selected' -and
                $r.result.originalIdentity -eq 'unknown' -and
                $r.result.fileOwner -eq 'unknown') ($seed+' '+$x.id+' no authentic FAT/file/owner claims')
            Check-D22 ($r.result.comparedWindowEntries -le 48 -and
                $r.result.fatEntriesDeclared -le 5120) ($seed+' '+$x.id+' bounded FAT sample not full FAT')
        }
        if($null -ne $x.truth){
            if($x.truth){
                if($o.detected){$tp++;$seedOld++}else{$fn++}
                if($n.detected){$rp++;$seedRot++}else{$rfn++}
            }else{
                if($o.detected){$fp++}else{$tn++}
                if($n.detected){$rfp++}else{$rtn++}
            }
        }else{$unknown++}
        switch($x.id){
            'M00' {Check-D22 (-not $o.detected -and -not $n.detected) ($seed+' clean observation negative')}
            'M01' {Check-D22 (-not $o.detected -and -not $n.detected) ($seed+' legitimate fragmentation negative')}
            'M02' {Check-D22 ($o.detected -and $n.detected) ($seed+' FAT1 link-only corruption found')}
            'M03' {Check-D22 ($o.result.different -eq 0 -and $n.result.different -eq 0 -and
                $o.result.cycles -gt 0 -and $n.result.cycles -gt 0) ($seed+' common-mode cycle not hidden by mirror agreement')}
            'CONFLICT' {Check-D22 ($o.detected -and $n.detected) ($seed+' contradictory two-EOC paths remain unresolved')}
            'REMOTE128' {Check-D22 ($o.detected -and $o.saw128 -and $n.detected -eq $n.saw128) ($seed+' remote128 observed-or-missed honestly')}
            'REMOTE256' {Check-D22 ($o.detected -and $o.saw256 -and $n.detected -eq $n.saw256) ($seed+' remote256 observed-or-missed honestly')}
            'REMOTE512' {Check-D22 (-not $o.detected -and -not $o.saw512 -and $n.detected -eq $n.saw512) ($seed+' remote512 observed-or-missed honestly')}
            'REMOTE768' {Check-D22 (-not $o.detected -and $n.detected -eq $n.saw768) ($seed+' remote768 unscored, not certified healthy')}
            'REMOTE3000' {Check-D22 (-not $o.detected -and -not $n.detected -and
                -not $o.saw3000 -and -not $n.saw3000) ($seed+' remote3000 unobserved by both')}
            'M05' {Check-D22 (-not $o.detected -and -not $n.detected) ($seed+' no cross-file FAT owner inferred')}
            'X02' {Check-D22 ($o.result.parserReasons -contains 'geometry.partition_exceeds_stream' -and
                $n.result.parserReasons -contains 'geometry.partition_exceeds_stream') ($seed+' source truncation untrusted')}
            'EARLY_STOP' {Check-D22 ($o.actual -eq 1200 -and $n.actual -eq 1200 -and $o.early -and $n.early) ($seed+' 7B chunk EOF at 1200 actual B')}
            'CAP32' {Check-D22 ($o.actual -le 32 -and $n.actual -le 32 -and
                $o.result.parserDecision -eq 'insufficient_evidence' -and
                $n.result.parserDecision -eq 'insufficient_evidence') ($seed+' byte cap 32 yields insufficient geometry')}
            'INVALID_BPB' {Check-D22 ($o.result.parserDecision -ne 'plausible_unverified' -and
                $n.result.parserDecision -ne 'plausible_unverified' -and -not $o.detected -and -not $n.detected) ($seed+' invalid BPB never trusted')}
        }
        if($x.id -eq 'M00'){
            $plan=(@($n.result.starts) -join ',')
            [void]$plans.Add($plan)
            foreach($w in @($n.result.starts)){[void]$locations.Add([long]$w)}
            Check-D22 ($o.result.comparedWindowEntries -eq 48 -and
                $n.result.comparedWindowEntries -eq 48 -and
                $n.result.fatEntriesDeclared -eq 5120) ($seed+' exact 48/5120 entries sampled per schedule')
            Write-Host ('D P9 seed={0} old=0,128,256 rotating={1}; 48/5120 FAT entries observed=0.9375%, 99.0625% unobserved' -f $seed,$plan)
        }
        $oldBytes+=$o.actual;$newBytes+=$n.actual
        $oldUnique+=$o.unique;$newUnique+=$n.unique
        $oldCalls+=$o.calls;$newCalls+=$n.calls
        if($x.id -match '^REMOTE'){
            Write-Host ('D P9 {0} {1} fixed={2} rotate={3}; actual B={4}/{5}, unique B={6}/{7}, Read calls={8}/{9}' -f
                $seed,$x.id,$o.detected,$n.detected,$o.actual,$n.actual,$o.unique,$n.unique,$o.calls,$n.calls)
        }
    }
    Check-D22 ($seedOld -eq 5) ($seed+' fixed baseline sees five of six selected artificial damage cases')
    Write-Host ('D P9 seed {0} detected anomaly positives fixed={1}/6, rotate={2}/6' -f $seed,$seedOld,$seedRot)
}
Check-D22 ($tp -eq 15 -and $fp -eq 0 -and $fn -eq 3 -and $tn -eq 6) 'Baseline 24 selected artificial FAT anomaly TP15 FP0 FN3 TN6'
Check-D22 ($rp+$rfn -eq 18 -and $rfp -eq 0 -and $rtn -eq 6) 'Rotating all selected positives accounted as TP or missed FN'
Check-D22 ($unknown -eq 21) '21 out-of-window / owner / source-limit negatives remain unscored UNKNOWN'
Check-D22 ($plans.Count -eq 3 -and $locations.Count -ge 5) 'Three public-seed rotating schedules produce distinct sample locations'
Check-D22 ($oldBytes -ge $oldUnique -and $newBytes -ge $newUnique) 'Independent source-local distinct/duplicate-byte bounds valid'
$writable=[IO.MemoryStream]::new($clean,$true)
try{Check-D22 (Throws-D22 {Get-D22Evidence -Stream $writable -Mode rotate -PublicSeed 202611}) 'Research-only rotating helper rejects writable source'}
finally{$writable.Dispose()}
Write-Host ('D P9 24 selected artificial FAT anomaly cases fixed TP/FP/FN/TN={0}/{1}/{2}/{3}; rotate={4}/{5}/{6}/{7}; UNKNOWN={8}' -f $tp,$fp,$fn,$tn,$rp,$rfp,$rfn,$rtn,$unknown)
Write-Host ('D P9 returned/unique bytes fixed={0}/{1} rotate={2}/{3}; duplicates={4}/{5}, Read calls={6}/{7}' -f $oldBytes,$oldUnique,$newBytes,$newUnique,($oldBytes-$oldUnique),($newBytes-$newUnique),$oldCalls,$newCalls)
Write-Host ('Team D R6 P9 nonoracle rotating windows: {0} passed; {1} failed.' -f $script:good,$script:bad)
if($script:bad -gt 0){exit 1}
