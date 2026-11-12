#Requires -Version 5.1
# Team D Issue 73 P8: synthetic-only two fixed 3-window sampling schedules A/B.
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
function Check-D21([bool]$ok,[string]$name) {
    if($ok){$script:good++;Write-Host ('PASS '+$name)}
    else{$script:bad++;Write-Host ('FAIL '+$name)}
}
function Hash-D21([byte[]]$bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}
    finally{$sha.Dispose()}
}
function Throws-D21([scriptblock]$action) {
    try{$null=& $action;return $false}catch{return $true}
}
# Physical Stream.Read() meter, outside both D diagnostic algorithms.
# Actual returned bytes, distinct physical positions, and calls have one
# common hard per-invocation ceiling. Source is strictly nonwritable.
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D21PhysicalMeter : Stream {
    readonly MemoryStream m;
    readonly HashSet<long> covered=new HashSet<long>();
    readonly long maxBytes,maxCalls,earlyStop;
    readonly int chunk;
    long used=0,calls=0;
    bool early=false,callClipped=false;
    public D21PhysicalMeter(byte[] data,long bytes,long callsLimit,long stop,int chunkSize) {
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
function Get-D21Schedule {
    param([Parameter(Mandatory=$true)][IO.Stream]$Stream,
          [Parameter(Mandatory=$true)][ValidateSet('old','new')][string]$Schedule)
    if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite) {
        throw 'Read-only, seekable, nonwritable source required'
    }
    $g=Get-ChappyFatGeometryTrust -Stream $Stream -MaxReadBytes 1024
    $different=0L;$cycles=0L;$windows=0;$fault=$false
    if($null -ne $g.geometry -and $null -ne $g.geometry.fat1OffsetBytes -and
       $null -ne $g.geometry.fat2OffsetBytes -and
       $null -ne $g.geometry.fatLengthBytes -and
       $null -ne $g.geometry.dataClusterCount){
        $mirrorArgs=@{
            Stream=$Stream
            Fat1OffsetBytes=[long]$g.geometry.fat1OffsetBytes
            Fat2OffsetBytes=[long]$g.geometry.fat2OffsetBytes
            FatLengthBytes=[long]$g.geometry.fatLengthBytes
            MaxWindows=1;WindowEntries=16;MaxReadBytes=128
        }
        # Frozen before the scorer created/planted synthetic anomalies.
        $starts=$(if($Schedule -eq 'old'){@(0,128,256)}else{@(0,256,512)})
        foreach($first in $starts){
            try{
                $m=Get-ChappyFatMirrorWindows @mirrorArgs -StartEntry ([long]$first)
                $different += [long]$m.metrics.differentEntries
                $windows++
                if($m.scanIncomplete){$fault=$true}
            }catch{$fault=$true}
        }
        try{
            $chainArgs=@{
                Stream=$Stream
                Fat1OffsetBytes=[long]$g.geometry.fat1OffsetBytes
                Fat2OffsetBytes=[long]$g.geometry.fat2OffsetBytes
                FatLengthBytes=[long]$g.geometry.fatLengthBytes
                MaxDataCluster=([long]$g.geometry.dataClusterCount+1L)
                StartClusters=@([long[]]@(2,3,4,5,6,7,8))
                MaxStepsPerChain=8;MaxTotalEntries=32;MaxReadBytes=448
            }
            $trace=Get-ChappyFatChainAnomalyStats @chainArgs
            $cycles=@($trace.items|Where-Object {$_.terminal -eq 'cycle'}).Count
            if($trace.scanIncomplete){$fault=$true}
        }catch{$fault=$true}
    }else{$fault=$true}
    return [pscustomobject]@{
        mirrorDifferentEntries=$different
        observedCycles=$cycles
        windowsObserved=$windows
        readFaultOrLimit=$fault
        geometryDecision=[string]$g.trustDecision
        geometryReasonCodes=@($g.reasons)
        scanIncomplete=$true
        sourceDecision='not_selected'
        selectedCandidate=$null
        originalIdentity='unknown'
        writePermitted=$false
        fullFatVerified=$false
    }
}
function Invoke-D21 {
    param([byte[]]$Bytes,[string]$Schedule,[int]$Budget=2048,
          [long]$Stop=[long]::MaxValue,[int]$Chunk=4096)
    $source=[D21PhysicalMeter]::new($Bytes,$Budget,256L,$Stop,$Chunk)
    try{
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $r=Get-D21Schedule -Stream $source -Schedule $Schedule
        $watch.Stop()
        $positions=@([long]37888,[long]38400,[long]39424,[long]40448)
        return [pscustomobject]@{
            schedule=$Schedule
            report=$r
            detected=($r.mirrorDifferentEntries -gt 0 -or $r.observedCycles -gt 0)
            actual=[long]$source.Actual
            unique=[long]$source.Unique
            calls=[long]$source.Calls
            early=$source.Early
            callClipped=$source.CallClipped
            observed128=$source.Has($positions[0],4)
            observed256=$source.Has($positions[1],4)
            observed512=$source.Has($positions[2],4)
            observed768=$source.Has($positions[3],4)
            timeMs=[long]$watch.ElapsedMilliseconds
        }
    }finally{$source.Dispose()}
}

# External scorer's synthetic-only fixture oracle. Never sent to analyzers.
$fixture=@{}
foreach($id in @('M00','M01','M02','M03','M05','X02')){
    $f=New-ChappyA3DDamagedFixture -Case $id -Seed 202611
    $sha=Hash-D21 $f.image
    Check-D21 ($sha -ceq $f.manifest.imageSha256) ('External scorer fixture SHA '+$id)
    $fixture[$id]=[pscustomobject]@{raw=[byte[]]$f.image;sha=$sha}
}
[byte[]]$clean=$fixture['M00'].raw
Check-D21 ([BitConverter]::ToUInt32($clean,37392) -eq 5 -and
    [BitConverter]::ToUInt32($clean,37408) -ge 268435448) 'External scorer confirms FAT2 cluster4-to-5 and cluster8 EOC'
# All mutations apply only to independently cloned artificial images. The
# scored geometry/FAT offsets never become input to either sample plan.
foreach($mutation in @(
    [pscustomobject]@{id='REMOTE128';offset=37888;value=[uint32]1},
    [pscustomobject]@{id='REMOTE256';offset=38400;value=[uint32]1},
    [pscustomobject]@{id='REMOTE512';offset=39424;value=[uint32]1},
    [pscustomobject]@{id='REMOTE768';offset=40448;value=[uint32]1},
    [pscustomobject]@{id='CONFLICT';offset=37392;value=[uint32]8}
)){
    [byte[]]$clone=[byte[]]$clean.Clone()
    [Array]::Copy([BitConverter]::GetBytes($mutation.value),0,$clone,[int]$mutation.offset,4)
    $fixture[$mutation.id]=[pscustomobject]@{raw=$clone;sha=(Hash-D21 $clone)}
    Check-D21 ($fixture[$mutation.id].sha -cne $fixture['M00'].sha) ($mutation.id+' planted artificial FAT mutation changes source bytes')
}
[byte[]]$badBpb=[byte[]]$clean.Clone()
$badBpb[525]=0
$fixture['INVALID_BPB']=[pscustomobject]@{raw=$badBpb;sha=(Hash-D21 $badBpb)}
Check-D21 ($fixture['INVALID_BPB'].sha -cne $fixture['M00'].sha) 'Invalid BPB synthetic negative actually changes source bytes'
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
 [pscustomobject]@{id='M05';src='M05';truth=$null;cap=2048;stop=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='X02';src='X02';truth=$null;cap=2048;stop=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='EARLY_STOP';src='M02';truth=$null;cap=2048;stop=1200L;chunk=7},
 [pscustomobject]@{id='CAP32';src='M03';truth=$null;cap=32;stop=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='INVALID_BPB';src='INVALID_BPB';truth=$null;cap=2048;stop=[long]::MaxValue;chunk=4096}
)
$otp=0;$ofp=0;$ofn=0;$otn=0
$ntp=0;$nfp=0;$nfn=0;$ntn=0
$unknown=0;$oactual=0L;$nactual=0L;$ounique=0L;$nunique=0L;$ocalls=0L;$ncalls=0L
$coverageFaults=0
foreach($c in $rows){
    $bytes=[byte[]]$fixture[$c.src].raw
    $before=Hash-D21 $bytes
    $old=Invoke-D21 -Bytes $bytes -Schedule old -Budget $c.cap -Stop $c.stop -Chunk $c.chunk
    $new=Invoke-D21 -Bytes $bytes -Schedule new -Budget $c.cap -Stop $c.stop -Chunk $c.chunk
    Check-D21 ((Hash-D21 $bytes) -ceq $before) ($c.id+' scorer original synthetic SHA preserved')
    foreach($run in @($old,$new)){
        Check-D21 ($run.actual -le $c.cap -and $run.unique -le $run.actual -and
            $run.calls -le 256) ($c.id+' '+$run.schedule+' single hard physical byte/call ceiling')
        Check-D21 ($run.report.scanIncomplete -and
            -not $run.report.fullFatVerified -and
            $run.report.sourceDecision -eq 'not_selected' -and
            $null -eq $run.report.selectedCandidate -and
            $run.report.originalIdentity -eq 'unknown' -and
            -not $run.report.writePermitted) ($c.id+' '+$run.schedule+' no unobserved-healthy/winner/owner or repair inference')
    }
    if($null -ne $c.truth){
        if($c.truth){
            if($old.detected){$otp++}else{$ofn++}
            if($new.detected){$ntp++}else{$nfn++}
        }else{
            if($old.detected){$ofp++}else{$otn++}
            if($new.detected){$nfp++}else{$ntn++}
        }
    }else{$unknown++}
    switch($c.id){
        'M00' {Check-D21 (-not $old.detected -and -not $new.detected) 'Healthy synthetic control: neither schedule invents FAT corruption'}
        'M01' {Check-D21 (-not $old.detected -and -not $new.detected) 'Normal fragmentation stays nonanomalous'}
        'M02' {Check-D21 ($old.detected -and $new.detected -and
            $old.report.mirrorDifferentEntries -eq 1 -and $new.report.mirrorDifferentEntries -eq 1) 'Both schedules observe original low-FAT mismatch'}
        'M03' {Check-D21 ($old.detected -and $new.detected -and
            $old.report.mirrorDifferentEntries -eq 0 -and $new.report.mirrorDifferentEntries -eq 0 -and
            $old.report.observedCycles -gt 0 -and $new.report.observedCycles -gt 0) 'Both schedules retain common-mode two-mirror cycle evidence'}
        'CONFLICT' {Check-D21 ($old.detected -and $new.detected -and
            $old.report.mirrorDifferentEntries -eq 1 -and $new.report.mirrorDifferentEntries -eq 1) 'Conflicting links to separately EOC chains cannot select authentic FAT winner'}
        'REMOTE128' {Check-D21 ($old.detected -and -not $new.detected -and
            $old.observed128 -and -not $new.observed128) 'Switch loses entry128 evidence, never silently counts it healthy'}
        'REMOTE256' {Check-D21 ($old.detected -and $new.detected -and
            $old.observed256 -and $new.observed256) 'Both schedules independently observe planted entry256 mismatch'}
        'REMOTE512' {Check-D21 (-not $old.detected -and $new.detected -and
            -not $old.observed512 -and $new.observed512) 'Switch gains entry512 evidence, no authenticated FAT winner'}
        'REMOTE768' {Check-D21 (-not $old.detected -and -not $new.detected -and
            -not $old.observed768 -and -not $new.observed768) 'Both schedules miss 768; unknown not healthy'}
        'M05' {Check-D21 (-not $old.detected -and -not $new.detected) 'FAT-only cross-file ownership cannot be inferred'}
        'X02' {Check-D21 ($old.report.geometryReasonCodes -contains 'geometry.partition_exceeds_stream' -and
            $new.report.geometryReasonCodes -contains 'geometry.partition_exceeds_stream') 'Truncated artificial extent stays rejected/unverified'}
        'EARLY_STOP' {Check-D21 ($old.actual -eq 1200 -and $new.actual -eq 1200 -and
            $old.early -and $new.early -and $old.report.scanIncomplete -and $new.report.scanIncomplete) 'Genuine premature source read zero after 1200 bytes stays partial'}
        'CAP32' {Check-D21 ($old.actual -le 32 -and $new.actual -le 32 -and
            $old.report.geometryDecision -eq 'insufficient_evidence' -and
            $new.report.geometryDecision -eq 'insufficient_evidence') 'Only 32 returned bytes: geometry insufficient, no false trust'}
        'INVALID_BPB' {Check-D21 ($old.report.geometryDecision -ne 'plausible_unverified' -and
            $new.report.geometryDecision -ne 'plausible_unverified' -and
            -not $old.detected -and -not $new.detected) 'Malformed synthetic BPB is not promoted to FAT health'}
    }
    $oactual+=$old.actual;$nactual+=$new.actual
    $ounique+=$old.unique;$nunique+=$new.unique
    $ocalls+=$old.calls;$ncalls+=$new.calls
    if($old.early -or $new.early -or $old.callClipped -or $new.callClipped){$coverageFaults++}
    Write-Host ('D P8 {0}: old anomaly={1}, read={2}/{3}, calls={4}; new anomaly={5}, read={6}/{7}, calls={8}; observed128={9}/{10}, observed512={11}/{12}' -f
        $c.id,$old.detected,$old.actual,$old.unique,$old.calls,
        $new.detected,$new.actual,$new.unique,$new.calls,
        $old.observed128,$new.observed128,$old.observed512,$new.observed512)
}
Check-D21 ($otp -eq 5 -and $ofp -eq 0 -and $ofn -eq 1 -and $otn -eq 2) 'Old 0/128/256 schedule eight selected TP5 FP0 FN1 TN2'
Check-D21 ($ntp -eq 5 -and $nfp -eq 0 -and $nfn -eq 1 -and $ntn -eq 2) 'New 0/256/512 schedule eight selected TP5 FP0 FN1 TN2'
Check-D21 ($unknown -eq 6) 'Six remote/owner/incomplete/invalid cases scored UNKNOWN, never healthy/recovered'
Check-D21 ($oactual -ge $ounique -and $nactual -ge $nunique -and
    $ocalls -ge 0 -and $ncalls -ge 0) 'Physical returned/unique/read-request totals remain internally bounded'
$writable=[IO.MemoryStream]::new($clean,$true)
try{
    Check-D21 (Throws-D21 {Get-D21Schedule -Stream $writable -Schedule new}) 'New fixed-window research method refuses writable source'
}finally{$writable.Dispose()}
Write-Host ('D P8 same eight artificial cases old TP/FP/FN/TN={0}/{1}/{2}/{3}; new={4}/{5}/{6}/{7}; UNKNOWN={8}' -f $otp,$ofp,$ofn,$otn,$ntp,$nfp,$nfn,$ntn,$unknown)
Write-Host ('D P8 14 case physical bytes old actual/unique={0}/{1}, new={2}/{3}; physical Read() calls old/new={4}/{5}; early/call faults={6}' -f $oactual,$ounique,$nactual,$nunique,$ocalls,$ncalls,$coverageFaults)
Write-Host ('Team D R6 P8 remote512 tradeoff: {0} passed; {1} failed.' -f $script:good,$script:bad)
if($script:bad -gt 0){exit 1}
