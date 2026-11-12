#Requires -Version 5.1
# Team D Issue #73 P2. Only A-generated artificial FAT32-like memory fixtures.
# The mutation manifest and clean-file oracle are scorer-only, never analyzer input.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32GeometryTrust.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32MirrorWindows.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32ChainStats.psm1') -Force
$script:passed=0;$script:failed=0

function Check-D11 {
    param([bool]$Condition,[string]$Message)
    if($Condition){Write-Host "PASS $Message";$script:passed++}
    else{Write-Host "FAIL $Message";$script:failed++}
}
function Get-D11Hash {
    param([byte[]]$Bytes)
    $hash=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($hash.ComputeHash($Bytes)).Replace('-','')}
    finally{$hash.Dispose()}
}
function Throws-D11 {
    param([scriptblock]$Code)
    try{$null=& $Code;return $false}catch{return $true}
}

# Counts actual returned bytes, distinct physical byte offsets and Read() calls,
# including rereads of one entry through different generic candidate starts.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D11CountingStream : Stream {
    private readonly MemoryStream inner;
    private readonly HashSet<long> observed = new HashSet<long>();
    private readonly long cutoff;
    private long actual;
    private long calls;
    public D11CountingStream(byte[] bytes,long maxReturnedBytes) {
        inner=new MemoryStream(bytes,false);
        cutoff=maxReturnedBytes;
    }
    public long ActualBytes { get {return actual;} }
    public long UniqueBytes { get {return observed.Count;} }
    public long ReadCalls { get {return calls;} }
    public override bool CanRead {get {return true;} }
    public override bool CanWrite {get {return false;} }
    public override bool CanSeek {get {return true;} }
    public override long Length {get {return inner.Length;} }
    public override long Position {get {return inner.Position;} set {throw new NotSupportedException();} }
    public override long Seek(long offset,SeekOrigin origin){return inner.Seek(offset,origin);}
    public override void Flush(){}
    public override int Read(byte[] bytes,int offset,int count) {
        calls++;
        if(actual>=cutoff){return 0;}
        long at=inner.Position;
        int n=inner.Read(bytes,offset,(int)Math.Min((long)count,cutoff-actual));
        for(int i=0;i<n;i++){observed.Add(at+i);}
        actual+=n;
        return n;
    }
    public override void SetLength(long value){throw new NotSupportedException();}
    public override void Write(byte[] bytes,int offset,int count){throw new NotSupportedException();}
    protected override void Dispose(bool disposing){if(disposing)inner.Dispose();base.Dispose(disposing);}
}
'@

function Run-D11 {
    param([byte[]]$Image,[string]$Mode,[long]$MaxReturned=[long]::MaxValue)
    $source=[D11CountingStream]::new($Image,$MaxReturned)
    try {
        # The analyzer sees only the stream, geometry derived from its actual
        # observed BPB/MBR and a FIXED finite start-index sweep. Never the
        # mutation manifest, truth, filenames, hash or any fixture offsets.
        $g=Get-ChappyFatGeometryTrust -Stream $source
        if($null -eq $g.geometry){throw 'No bounded untrusted numeric geometry found'}
        $common=@{
            Stream=$source
            Fat1OffsetBytes=[long]$g.geometry.fat1OffsetBytes
            Fat2OffsetBytes=[long]$g.geometry.fat2OffsetBytes
            FatLengthBytes=[long]$g.geometry.fatLengthBytes
        }
        $candidateMirror=$null
        if($Mode -eq 'mirror') {
            $args=$common.Clone()
            $args.WindowEntries=128
            $args.MaxWindows=1
            $args.MaxReadBytes=1024
            $finding=Get-ChappyFatMirrorWindows @args
        }else{
            # Independent one-pass candidate, not a decision assembled from two
            # separate source runs. Both samples share one 2048-byte ceiling:
            # up to 1024 geometry + 512 mirror + 512 chain bytes.
            $mirrorArgs=$common.Clone()
            $mirrorArgs.WindowEntries=64
            $mirrorArgs.MaxWindows=1
            $mirrorArgs.MaxReadBytes=512
            $candidateMirror=Get-ChappyFatMirrorWindows @mirrorArgs
            $args=$common.Clone()
            $args.MaxDataCluster=([long]$g.geometry.dataClusterCount + 1L)
            # No case-specific cluster choice, no oracle truth leak.
            $args.StartClusters=[long[]]@(2,3,4,5,6,7,8)
            $args.MaxStepsPerChain=16
            $args.MaxTotalEntries=32
            $args.MaxReadBytes=512
            $finding=Get-ChappyFatChainAnomalyStats @args
        }
        return [pscustomobject]@{
            trust=$g.trustDecision
            geometryReasons=@($g.reasons)
            mirrorEvidence=$candidateMirror
            evidence=$finding
            actualBytes=[long]$source.ActualBytes
            uniqueBytes=[long]$source.UniqueBytes
            readCalls=[long]$source.ReadCalls
        }
    }finally{$source.Dispose()}
}
function Count-D11Cycles {
    param($Evidence)
    return @($Evidence.items | Where-Object {$_.terminal -eq 'cycle'}).Count
}

$cases=@(
    [pscustomobject]@{id='M00';truth='normal';anomaly=$false},
    [pscustomobject]@{id='M01';truth='valid_fragmentation';anomaly=$false},
    [pscustomobject]@{id='M02';truth='one_copy_disagreement';anomaly=$true},
    [pscustomobject]@{id='M03';truth='identical_mirror_cycle';anomaly=$true},
    [pscustomobject]@{id='M05';truth='cross_file_link_unknown_without_directory';anomaly=$null},
    [pscustomobject]@{id='X02';truth='payload_truncation_unknown_to_fat';anomaly=$null}
)
$oldTP=0;$oldFP=0;$oldFN=0;$oldTN=0
$newTP=0;$newFP=0;$newFN=0;$newTN=0
$oldBytes=0L;$newBytes=0L
$oldUnique=0L;$newUnique=0L
$oldRequests=0L;$newRequests=0L
$uncertain=0
foreach($item in $cases){
    $fixture=New-ChappyA3DDamagedFixture -Seed 202611 -Case $item.id
    $before=Get-D11Hash $fixture.image
    Check-D11 ($before -ceq $fixture.manifest.imageSha256) ("Generated scorer-only manifest valid: "+$item.id)
    $base=Run-D11 -Image $fixture.image -Mode mirror
    $variant=Run-D11 -Image $fixture.image -Mode chains
    Check-D11 ((Get-D11Hash $fixture.image) -ceq $before) ("Image unchanged after paired observations: "+$item.id)
    Check-D11 ($base.actualBytes -le 2048 -and $variant.actualBytes -le 2048 -and
        $base.uniqueBytes -le $base.actualBytes -and $variant.uniqueBytes -le $variant.actualBytes) ("Actual/unique 2048-byte caps: "+$item.id)
    Check-D11 ($base.trust -eq 'reject' -and $variant.trust -eq 'reject') ("Untrusted FAT32-like BPB not promoted: "+$item.id)
    $different=([long]$base.evidence.metrics.differentEntries -gt 0)
    $cycles=Count-D11Cycles $variant.evidence
    $detected=([long]$variant.mirrorEvidence.metrics.differentEntries -gt 0 -or $cycles -gt 0)
    Check-D11 (-not $base.evidence.writePermitted -and -not $variant.evidence.writePermitted -and
        -not $variant.mirrorEvidence.writePermitted) ("No write surface: "+$item.id)
    Check-D11 ($base.evidence.metrics.entriesChecked -eq 128 -and
        $variant.mirrorEvidence.metrics.entriesChecked -eq 64) ("Baseline 128 and candidate 64 mirror entries: "+$item.id)
    if($null -ne $item.anomaly){
        if($item.anomaly){
            if($different){$oldTP++}else{$oldFN++}
            if($detected){$newTP++}else{$newFN++}
        }else{
            if($different){$oldFP++}else{$oldTN++}
            if($detected){$newFP++}else{$newTN++}
        }
    }else{$uncertain++}
    $oldBytes+=$base.actualBytes;$newBytes+=$variant.actualBytes
    $oldUnique+=$base.uniqueBytes;$newUnique+=$variant.uniqueBytes
    $oldRequests+=$base.readCalls;$newRequests+=$variant.readCalls
    switch ($item.id){
        'M00' {
            Check-D11 (-not $different -and $cycles -eq 0) 'M00 healthy synthetic has no mismatch/cycle observed'
        }
        'M01' {
            Check-D11 (-not $different -and $cycles -eq 0) 'M01 valid fragmented chain is NOT a cycle'
            Check-D11 (@($variant.evidence.items | Where-Object {$_.terminal -eq 'eoc'}).Count -gt 0) 'M01 EOC observed on generic chain starts, no original-file proof'
        }
        'M02' {
            Check-D11 ($base.evidence.metrics.differentEntries -eq 1 -and $cycles -eq 0) 'M02 one-mirror disagreement observed without fabricated cycle'
        }
        'M03' {
            Check-D11 ($base.evidence.metrics.differentEntries -eq 0 -and $cycles -ge 2) 'M03 both identical corrupted FATs have observed cycles'
            Check-D11 ($variant.uniqueBytes -lt $variant.actualBytes) 'M03 repeated physical FAT reads distinguished from unique coverage'
        }
        'M05' {
            Check-D11 (-not $different -and $cycles -eq 0) 'M05 cross-file alias is not proven by mirror or cycle scan alone'
        }
        'X02' {
            Check-D11 ($base.geometryReasons -contains 'geometry.partition_exceeds_stream') 'X02 payload truncation cannot be ignored because FATs match'
            Check-D11 (-not $different -and $cycles -eq 0) 'X02 no false FAT-cycle inference from payload EOF'
        }
    }
    Write-Host ("D P2 artificial {0}: mirrorDifferences={1}; observedCycles={2}; mirrorRead(actual/unique)={3}/{4}; chainsRead(actual/unique)={5}/{6}; geometryTrusted=false." -f
        $item.id,$base.evidence.metrics.differentEntries,$cycles,
        $base.actualBytes,$base.uniqueBytes,$variant.actualBytes,$variant.uniqueBytes)
}
Check-D11 ($oldTP -eq 1 -and $oldFP -eq 0 -and $oldFN -eq 1 -and $oldTN -eq 2) 'Old mirror-only 4-case confusion matrix TP1 FP0 FN1 TN2'
Check-D11 ($newTP -eq 2 -and $newFP -eq 0 -and $newFN -eq 0 -and $newTN -eq 2) 'Additive observed-cycle 4-case confusion matrix TP2 FP0 FN0 TN2'
Check-D11 ($uncertain -eq 2) 'M05 cross-file alias and X02 payload truncation remain unscored unknown'
Check-D11 ($newUnique -le $newBytes -and $oldUnique -le $oldBytes) 'Cumulative unique observations cannot exceed physical reads'
Write-Host ("D P2 measured 4-case A/B: mirror TP={0} FP={1} FN={2} TN={3}; mirror+cycle TP={4} FP={5} FN={6} TN={7}; uncertainExcluded={8}" -f
    $oldTP,$oldFP,$oldFN,$oldTN,$newTP,$newFP,$newFN,$newTN,$uncertain)
Write-Host ("D P2 measured 6-case actual / unique bytes: mirror={0}/{1}, chain={2}/{3}; read requests mirror={4}, chains={5}" -f
    $oldBytes,$oldUnique,$newBytes,$newUnique,$oldRequests,$newRequests)

# Same fixture, deliberately injected aggregate returned-byte cap.
$shortFixture=New-ChappyA3DDamagedFixture -Seed 202611 -Case M03
$shortHash=Get-D11Hash $shortFixture.image
$shortBase=Run-D11 -Image $shortFixture.image -Mode mirror -MaxReturned 1032
$shortVariant=Run-D11 -Image $shortFixture.image -Mode chains -MaxReturned 1032
Check-D11 ($shortBase.actualBytes -eq 1032 -and $shortVariant.actualBytes -eq 1032) 'Injected early-stop budget exact aggregate bytes'
Check-D11 ($shortBase.evidence.scanIncomplete -and $shortVariant.evidence.scanIncomplete) 'Short-read evidence stays incomplete in both modes'
Check-D11 ((Get-D11Hash $shortFixture.image) -ceq $shortHash) 'Injected partial reads do not mutate artificial data'
Check-D11 (-not $shortBase.evidence.writePermitted -and -not $shortVariant.evidence.writePermitted) 'No write capability on partial evidence'

$writeSource=[IO.MemoryStream]::new($shortFixture.image,$true)
try{
    $geo=Run-D11 -Image $shortFixture.image -Mode chains
    Check-D11 (Throws-D11 {
        Get-ChappyFatChainAnomalyStats -Stream $writeSource -Fat1OffsetBytes 16896 -Fat2OffsetBytes 37376 -FatLengthBytes 20480 -MaxDataCluster 3990 -StartClusters @(2,3,4) -MaxReadBytes 1024 -MaxTotalEntries 32
    }) 'Writable input rejected by existing chain analyzer'
    Check-D11 (-not $geo.evidence.writePermitted) 'R6 P2 never gains repair privileges'
}finally{$writeSource.Dispose()}

Write-Host ("Team D R6 P2 result: {0} passed, {1} failed." -f $script:passed,$script:failed)
if($script:failed -gt 0){exit 1}
