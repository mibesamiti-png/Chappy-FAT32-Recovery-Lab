#Requires -Version 5.1
# Team D Issue 73 P7: synthetic-only fixed FAT sampling A/B.
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
function Check-D20([bool]$ok,[string]$name) {
    if($ok){$script:good++;Write-Host ('PASS '+$name)}
    else{$script:bad++;Write-Host ('FAIL '+$name)}
}
function Hash-D20([byte[]]$bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}
    finally{$sha.Dispose()}
}
function Throws-D20([scriptblock]$action) {
    try{$null=& $action;return $false}catch{return $true}
}
# Physical Stream.Read() meter, outside both D diagnostic algorithms.
# Actual returned bytes, distinct physical positions, and calls have one
# common hard per-invocation ceiling. Source is strictly nonwritable.
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D20PhysicalMeter : Stream {
    readonly MemoryStream m;
    readonly HashSet<long> covered=new HashSet<long>();
    readonly long maxBytes,maxCalls,earlyStop;
    readonly int chunk;
    long used=0,calls=0;
    bool early=false,callClipped=false;
    public D20PhysicalMeter(byte[] data,long bytes,long callsLimit,long stop,int chunkSize) {
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

# Optional candidate lives only in this test. Never added to production.
# Fixed windows 0/128/256 are used for ALL artificial cases, never oracle.
function Get-D20Stratified {
    param([Parameter(Mandatory=$true)][IO.Stream]$Stream)
    if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite) {
        throw 'Strict readonly seekable source needed'
    }
    $g=Get-ChappyFatGeometryTrust -Stream $Stream -MaxReadBytes 1024
    $diff=0L;$cycles=0L;$windows=0;$fault=$false
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
        foreach($entry in @(0,128,256)){
            try{
                $w=Get-ChappyFatMirrorWindows @mirrorArgs -StartEntry $entry
                $diff += [long]$w.metrics.differentEntries
                $windows++
                if($w.scanIncomplete){$fault=$true}
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
        mirrorDifferentEntries=$diff;observedCycles=$cycles
        windowsObserved=$windows;readFaultOrLimit=$fault
        geometryDecision=[string]$g.trustDecision
        geometryReasonCodes=@($g.reasons)
        # Sparse sampling never validates an entire FAT copy or file.
        scanIncomplete=$true
        sourceDecision='not_selected';selectedCandidate=$null
        originalIdentity='unknown';writePermitted=$false
    }
}

function Invoke-D20 {
    param([byte[]]$Bytes,[string]$Mode,[int]$Budget=2048,
          [long]$Stop=[long]::MaxValue,[int]$Chunk=4096)
    $source=[D20PhysicalMeter]::new($Bytes,$Budget,256L,$Stop,$Chunk)
    try{
        $watch=[Diagnostics.Stopwatch]::StartNew()
        if($Mode -eq 'baseline') {
            $r=Get-ChappyFatObservedIoEvidence -Stream $source -Mode MirrorAndChain -MaxReadBytes $Budget
            $diff=[long]$r.evidence.mirrorDifferentEntries
            $cycles=[long]$r.evidence.observedCycles
            $reasons=@($r.geometryReasonCodes)
        }else {
            $r=Get-D20Stratified -Stream $source
            $diff=[long]$r.mirrorDifferentEntries
            $cycles=[long]$r.observedCycles
            $reasons=@($r.geometryReasonCodes)
        }
        $watch.Stop()
        return [pscustomobject]@{
            kind=$Mode
            report=$r
            different=$diff;cycles=$cycles;reasons=$reasons
            actual=[long]$source.Actual;unique=[long]$source.Unique
            calls=[long]$source.Calls
            earlyStop=$source.Early;callClipped=$source.CallClipped
            saw256=$source.Has(38400L,4)
            saw512=$source.Has(39424L,4)
            timeMs=[long]$watch.ElapsedMilliseconds
        }
    }finally{$source.Dispose()}
}

# Scorer-alone truth and corruption; no mutation location passed to D.
$fixtures=@{}
foreach($caseName in @('M00','M01','M02','M03','M05','X02')) {
    $fix=New-ChappyA3DDamagedFixture -Case $caseName -Seed 202611
    $digest=Hash-D20 $fix.image
    Check-D20 ($digest -ceq $fix.manifest.imageSha256) ('Scorer-only fixture integrity '+$caseName)
    $fixtures[$caseName]=[pscustomobject]@{raw=[byte[]]$fix.image;sha=$digest}
}
[byte[]]$clean=$fixtures['M00'].raw
Check-D20 ([BitConverter]::ToUInt32($clean,37392) -eq 5 -and
    [BitConverter]::ToUInt32($clean,37408) -ge 268435448) 'Scorer confirms clean FAT2 cluster 4 points 5 and cluster 8 is EOC'
[byte[]]$contradict=[byte[]]$clean.Clone()
[Array]::Copy([BitConverter]::GetBytes([uint32]8),0,$contradict,37392,4)
$fixtures['CONFLICT']=[pscustomobject]@{raw=$contradict;sha=(Hash-D20 $contradict)}
[byte[]]$remote256=[byte[]]$clean.Clone()
[Array]::Copy([BitConverter]::GetBytes([uint32]1),0,$remote256,38400,4)
$fixtures['REMOTE256']=[pscustomobject]@{raw=$remote256;sha=(Hash-D20 $remote256)}
[byte[]]$remote512=[byte[]]$clean.Clone()
[Array]::Copy([BitConverter]::GetBytes([uint32]1),0,$remote512,39424,4)
$fixtures['REMOTE512']=[pscustomobject]@{raw=$remote512;sha=(Hash-D20 $remote512)}
Check-D20 ($fixtures['CONFLICT'].sha -cne $fixtures['M00'].sha -and
    $fixtures['REMOTE256'].sha -cne $fixtures['M00'].sha -and
    $fixtures['REMOTE512'].sha -cne $fixtures['M00'].sha) 'All scorer-only mutations differ from unchanged synthetic source'

$rows=@(
    [pscustomobject]@{id='M00';source='M00';truth=$false;cap=2048;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='M01';source='M01';truth=$false;cap=2048;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='M02';source='M02';truth=$true;cap=2048;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='M03';source='M03';truth=$true;cap=2048;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='CONFLICT';source='CONFLICT';truth=$true;cap=2048;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='REMOTE256';source='REMOTE256';truth=$true;cap=2048;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='M05';source='M05';truth=$null;cap=2048;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='X02';source='X02';truth=$null;cap=2048;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='REMOTE512';source='REMOTE512';truth=$null;cap=2048;stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='EARLY_STOP';source='M02';truth=$null;cap=2048;stop=1200L;chunk=7},
    [pscustomobject]@{id='CAP32';source='M03';truth=$null;cap=32;stop=[long]::MaxValue;chunk=4096}
)
$btp=0;$bfp=0;$bfn=0;$btn=0;$vtp=0;$vfp=0;$vfn=0;$vtn=0;$unknown=0
$ba=0L;$bu=0L;$bc=0L;$va=0L;$vu=0L;$vc=0L
foreach($row in $rows) {
    $data=[byte[]]$fixtures[$row.source].raw
    $before=Hash-D20 $data
    $base=Invoke-D20 -Bytes $data -Mode baseline -Budget $row.cap -Stop $row.stop -Chunk $row.chunk
    $variant=Invoke-D20 -Bytes $data -Mode stratified -Budget $row.cap -Stop $row.stop -Chunk $row.chunk
    Check-D20 ((Hash-D20 $data) -ceq $before) ($row.id+' scorer input remains byte-identical')
    foreach($trial in @($base,$variant)){
        Check-D20 ($trial.actual -le $row.cap -and
            $trial.unique -le $trial.actual -and
            $trial.calls -le 256) ($row.id+' '+$trial.kind+' same global byte and physical Read() ceilings')
        Check-D20 ($trial.report.scanIncomplete -and
            $trial.report.sourceDecision -eq 'not_selected' -and
            $null -eq $trial.report.selectedCandidate -and
            -not $trial.report.writePermitted) ($row.id+' '+$trial.kind+' partial FAT, no winner/repair')
    }
    $bh=($base.different -gt 0 -or $base.cycles -gt 0)
    $vh=($variant.different -gt 0 -or $variant.cycles -gt 0)
    if($null -ne $row.truth){
        if($row.truth){
            if($bh){$btp++}else{$bfn++}
            if($vh){$vtp++}else{$vfn++}
        }else{
            if($bh){$bfp++}else{$btn++}
            if($vh){$vfp++}else{$vtn++}
        }
    }else{$unknown++}
    switch($row.id){
        'M00' {Check-D20 (-not $bh -and -not $vh) 'M00 clean sampled windows not corrupted'}
        'M01' {Check-D20 (-not $bh -and -not $vh) 'M01 valid nonadjacent fragmentation is not cyclic'}
        'M02' {Check-D20 ($base.different -eq 1 -and $variant.different -eq 1) 'M02 first-window FAT disagreement found in both'}
        'M03' {Check-D20 ($base.different -eq 0 -and $variant.different -eq 0 -and
            $base.cycles -gt 0 -and $variant.cycles -gt 0) 'M03 both matching corrupted FAT mirrors have observable cycles'}
        'CONFLICT' {Check-D20 ($base.different -eq 1 -and $variant.different -eq 1) 'CONFLICT both EOC paths, source copy remains undecidable'}
        'REMOTE256' {Check-D20 (-not $bh -and $vh -and
            -not $base.saw256 -and $variant.saw256) 'Remote entry256 damaged: only the fixed stratified schedule observes it'}
        'M05' {Check-D20 (-not $bh -and -not $vh) 'M05 same-link cross-file ownership cannot be proved from FAT only'}
        'X02' {Check-D20 (($base.reasons -contains 'geometry.partition_exceeds_stream') -and
            ($variant.reasons -contains 'geometry.partition_exceeds_stream')) 'X02 declared partition larger than physical synthetic input'}
        'REMOTE512' {Check-D20 (-not $bh -and -not $vh -and
            -not $base.saw512 -and -not $variant.saw512) 'Remote entry512 UNKNOWN because neither schedule observes it'}
        'EARLY_STOP' {Check-D20 ($base.actual -eq 1200 -and $variant.actual -eq 1200 -and
            $base.earlyStop -and $variant.earlyStop) 'Actual premature physical read stop remains bounded and incomplete'}
        'CAP32' {Check-D20 ($base.actual -le 32 -and $variant.actual -le 32 -and
            ($base.reasons -contains 'io.mbr_truncated') -and
            ($variant.reasons -contains 'io.mbr_truncated')) '32-byte geometry sample insufficient, no FAT inference'}
    }
    $ba+=$base.actual;$bu+=$base.unique;$bc+=$base.calls
    $va+=$variant.actual;$vu+=$variant.unique;$vc+=$variant.calls
    Write-Host ('D P7 {0}: old anomaly={1}, read={2}/{3}, calls={4}; fixed anomaly={5}, read={6}/{7}, calls={8}' -f
        $row.id,$bh,$base.actual,$base.unique,$base.calls,$vh,$variant.actual,$variant.unique,$variant.calls)
}
Check-D20 ($btp -eq 3 -and $bfp -eq 0 -and $bfn -eq 1 -and $btn -eq 2) 'Prefix+chain baseline six artificial TP3 FP0 FN1 TN2'
Check-D20 ($vtp -eq 4 -and $vfp -eq 0 -and $vfn -eq 0 -and $vtn -eq 2) 'Fixed three-window+chain six artificial TP4 FP0 FN0 TN2'
Check-D20 ($unknown -eq 5) 'Five uncovered/owner/short-read synthetic cases remain unknown'
Check-D20 ($ba -ge $bu -and $va -ge $vu -and $bc -ge 0 -and $vc -ge 0) 'Cumulative observed physical byte unions valid'
$writable=[IO.MemoryStream]::new($clean,$true)
try{Check-D20 (Throws-D20 {Get-D20Stratified -Stream $writable}) 'Stratified research function rejects writable stream'}
finally{$writable.Dispose()}
Write-Host ('D P7 six artificial anomaly cases baseline TP/FP/FN/TN={0}/{1}/{2}/{3}; stratified={4}/{5}/{6}/{7}; unknown={8}' -f $btp,$bfp,$bfn,$btn,$vtp,$vfp,$vfn,$vtn,$unknown)
Write-Host ('D P7 eleven artificial cases physical bytes baseline actual/unique={0}/{1}, stratified={2}/{3}; Read calls={4}/{5}' -f $ba,$bu,$va,$vu,$bc,$vc)
Write-Host ('Team D R6-P7 blindspots: {0} passed; {1} failed.' -f $script:good,$script:bad)
if($script:bad -gt 0){exit 1}
