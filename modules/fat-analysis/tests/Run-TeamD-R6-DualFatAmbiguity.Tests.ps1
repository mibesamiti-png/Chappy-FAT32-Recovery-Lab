#Requires -Version 5.1
# Team D Issue #73 P6. Test-only synthetic FAT mirror ambiguity A/B.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32ObservedIoEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32GeometryTrust.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32ChainStats.psm1') -Force
$script:passed=0;$script:failed=0
function Check-D19([bool]$good,[string]$label){
    if($good){$script:passed++;Write-Host ('PASS '+$label)}
    else{$script:failed++;Write-Host ('FAIL '+$label)}
}
function Hash-D19([byte[]]$bytes){
    $s=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($s.ComputeHash($bytes)).Replace('-','')}
    finally{$s.Dispose()}
}
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D19Meter : Stream {
    private readonly MemoryStream inner;
    private readonly HashSet<long> distinct=new HashSet<long>();
    private readonly long cutoff;
    private readonly int chunk;
    private long actual=0;
    private long calls=0;
    public D19Meter(byte[] data,long stop,int maxChunk){
        inner=new MemoryStream(data,false);cutoff=stop;chunk=maxChunk;
    }
    public long Actual {get{return actual;}}
    public long Unique {get{return distinct.Count;}}
    public long Calls {get{return calls;}}
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return inner.Length;}}
    public override long Position {get{return inner.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long offset,SeekOrigin origin){return inner.Seek(offset,origin);}
    public override int Read(byte[] b,int off,int count){
        calls++;
        if(actual>=cutoff)return 0;
        long start=inner.Position;
        int n=inner.Read(b,off,(int)Math.Min((long)count,Math.Min((long)chunk,cutoff-actual)));
        for(int i=0;i<n;i++)distinct.Add(start+i);
        actual+=n;return n;
    }
    public override void Flush(){}
    public override void SetLength(long n){throw new NotSupportedException();}
    public override void Write(byte[] b,int off,int count){throw new NotSupportedException();}
    protected override void Dispose(bool disposing){if(disposing)inner.Dispose();base.Dispose(disposing);}
}
'@
function Invoke-D19 {
    param([byte[]]$Data,[string]$Mode,[int]$Cap,[long]$Stop,[int]$Chunk)
    $meter=[D19Meter]::new($Data,$Stop,$Chunk)
    try{
        $report=Get-ChappyFatObservedIoEvidence -Stream $meter -Mode $Mode -MaxReadBytes $Cap
        return [pscustomobject]@{
            report=$report
            actual=[long]$meter.Actual
            unique=[long]$meter.Unique
            calls=[long]$meter.Calls
        }
    }finally{$meter.Dispose()}
}
function Check-D19Observation {
    param($Trial,[int]$Cap,[int]$SourceLength,[string]$Tag)
    $r=$Trial.report;$sum=0L;$invalid=0
    foreach($event in @($r.readEvents)){
        $from=[long]$event.offsetBytes;$n=[long]$event.returnedBytes
        if($from -lt 0 -or $n -le 0 -or ($from+$n) -gt $SourceLength -or
            [long]$event.endExclusiveBytes -ne ($from+$n)){$invalid++}
        $sum+=$n
    }
    $union=0L;$previousEnd=-1L
    foreach($range in @($r.uniqueReadRanges)){
        $start=[long]$range.offsetBytes;$end=[long]$range.endExclusiveBytes
        if($start -le $previousEnd -or $end -le $start -or $end -gt $SourceLength -or
            [long]$range.lengthBytes -ne ($end-$start)){$invalid++}
        $union+=($end-$start);$previousEnd=$end-1
    }
    $phaseBytes=0L
    foreach($phase in @($r.phaseSummaries)){$phaseBytes+=[long]$phase.bytesRead}
    Check-D19 ($invalid -eq 0 -and $sum -eq $Trial.actual -and
        $sum -eq $r.metrics.bytesRead -and $phaseBytes -eq $sum -and $sum -le $Cap) ($Tag+' true returned bytes and phase budget match independent meter')
    Check-D19 ($union -eq $Trial.unique -and $union -eq $r.metrics.uniquePhysicalBytes -and
        $r.metrics.duplicatePhysicalBytes -eq ($Trial.actual-$Trial.unique)) ($Tag+' source-local unique span union and duplicates exact')
    Check-D19 ($r.metrics.readRequests -ge $Trial.calls -and
        $r.metrics.maximumGlobalReadBytes -eq $Cap -and $r.metrics.totalReadCapShared) ($Tag+' bounded source requests counted')
    Check-D19 ($r.scanIncomplete -and $r.status -eq 'partial' -and
        $r.sourceDecision -eq 'not_selected' -and $null -eq $r.selectedCandidate -and
        -not $r.writePermitted) ($Tag+' never certify whole FAT, winning copy or repair')
    $j=$r|ConvertTo-Json -Depth 13
    Check-D19 ($j -notmatch 'originalFilename|originalSha256|sourcePath|repairTarget|trueFatCopy|fileOwner|recoveredOriginal') ($Tag+' numeric provenance only; scorer private truth excluded')
}
$images=@{}
foreach($case in @('M00','M01','M02','M03','M05','X02')){
    $f=New-ChappyA3DDamagedFixture -Case $case -Seed 202611
    $hash=Hash-D19 $f.image
    Check-D19 ($hash -ceq $f.manifest.imageSha256) ('Scorer SHA of generated '+$case)
    $images[$case]=[byte[]]$f.image
}
$fat1=16896;$fat2=37376
$clean=$images['M00']
Check-D19 ([BitConverter]::ToUInt32($clean,$fat1+16) -eq 5 -and
    [BitConverter]::ToUInt32($clean,$fat2+16) -eq 5) 'Frozen artificial FAT offsets and original cluster 4 link checked by scorer'
Check-D19 ([BitConverter]::ToUInt32($clean,$fat1+20) -ge 268435448 -and
    [BitConverter]::ToUInt32($clean,$fat2+24) -ge 268435448) 'Artificial cluster 5 and 6 both terminate EOC'
[byte[]]$conflict=[byte[]]$clean.Clone()
[Array]::Copy([BitConverter]::GetBytes([uint32]6),0,$conflict,$fat2+16,4)
$images['CONFLICT']=$conflict
Check-D19 ((Hash-D19 $conflict) -cne (Hash-D19 $clean)) 'Scorer-only contradictory link FAT2 cluster4 to 6 planted'
[byte[]]$remote=[byte[]]$clean.Clone()
[Array]::Copy([BitConverter]::GetBytes([uint32]1),0,$remote,$fat2+256*4,4)
$images['REMOTE']=$remote
Check-D19 ((Hash-D19 $remote) -cne (Hash-D19 $clean)) 'Scorer-only anomalous FAT2 entry 256 planted outside windows'
$cases=@(
 [pscustomobject]@{id='M00';positive=$false;cap=2048;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='M01';positive=$false;cap=2048;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='M02';positive=$true;cap=2048;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='M03';positive=$true;cap=2048;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='CONFLICT';positive=$true;cap=2048;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='M05';positive=$null;cap=2048;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='X02';positive=$null;cap=2048;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='REMOTE';positive=$null;cap=2048;cut=[long]::MaxValue;chunk=4096},
 [pscustomobject]@{id='M02-short';positive=$null;cap=2048;cut=1150L;chunk=7},
 [pscustomobject]@{id='M03-cap32';positive=$null;cap=32;cut=[long]::MaxValue;chunk=4096}
)
$bTP=0;$bFP=0;$bFN=0;$bTN=0
$cTP=0;$cFP=0;$cFN=0;$cTN=0
$unknown=0;$naiveFalseHealthy=0;$bRead=0L;$cRead=0L;$bUnique=0L;$cUnique=0L;$bCalls=0L;$cCalls=0L
foreach($case in $cases){
    $key=($case.id -replace '-short$','' -replace '-cap32$','')
    [byte[]]$image=$images[$key]
    $oldHash=Hash-D19 $image
    $base=Invoke-D19 -Data $image -Mode MirrorOnly -Cap $case.cap -Stop $case.cut -Chunk $case.chunk
    $cand=Invoke-D19 -Data $image -Mode MirrorAndChain -Cap $case.cap -Stop $case.cut -Chunk $case.chunk
    Check-D19 ((Hash-D19 $image) -ceq $oldHash) ($case.id+' synthetic image unchanged')
    Check-D19Observation $base $case.cap $image.Length ($case.id+' mirror')
    Check-D19Observation $cand $case.cap $image.Length ($case.id+' mirror+chain')
    $baselineHit=([long]$base.report.evidence.mirrorDifferentEntries -gt 0)
    $candidateHit=([long]$cand.report.evidence.mirrorDifferentEntries -gt 0 -or
        [long]$cand.report.evidence.observedCycles -gt 0)
    if($null -eq $case.positive){$unknown++}
    elseif($case.positive){
        if($baselineHit){$bTP++}else{$bFN++}
        if($candidateHit){$cTP++}else{$cFN++}
    }else{
        if($baselineHit){$bFP++}else{$bTN++}
        if($candidateHit){$cFP++}else{$cTN++}
    }
    switch($case.id){
        'M00' {Check-D19 (-not $baselineHit -and -not $candidateHit) 'Healthy artificial negative has no sampled anomaly'}
        'M01' {Check-D19 (-not $baselineHit -and -not $candidateHit) 'Legitimate fragmentation not mislabeled as cycle'}
        'M02' {Check-D19 ($base.report.evidence.mirrorDifferentEntries -eq 1 -and
            $cand.report.evidence.mirrorDifferentEntries -eq 1) 'One-copy FAT link loss gives observed mismatch, not FAT2 winner'}
        'M03' {Check-D19 ($base.report.evidence.mirrorDifferentEntries -eq 0 -and
            $cand.report.evidence.mirrorDifferentEntries -eq 0 -and
            $cand.report.evidence.observedCycles -ge 2) 'Identically corrupted mirrors conceal a cycle from mirror-only observation'}
        'CONFLICT' {Check-D19 ($base.report.evidence.mirrorDifferentEntries -eq 1 -and
            $cand.report.evidence.mirrorDifferentEntries -eq 1 -and
            $cand.report.evidence.observedCycles -eq 0) 'Conflicting FAT chain link observed without choosing source winner'}
        'M05' {Check-D19 (-not $baselineHit -and -not $candidateHit) 'Common-mode crosslink ownership unresolved without directory proof'}
        'X02' {Check-D19 ($cand.report.geometryReasonCodes -contains 'geometry.partition_exceeds_stream' -and
            -not $candidateHit) 'Image payload truncation remains a separate geometry warning'}
        'REMOTE' {Check-D19 (-not $baselineHit -and -not $candidateHit -and
            $cand.report.scanIncomplete) 'Entry256 outside observed FAT window stays unknown'}
        'M02-short' {Check-D19 ($base.actual -eq 1150 -and $cand.actual -eq 1150 -and
            $base.report.metrics.prematureSourceZeroReads -gt 0 -and
            $cand.report.metrics.prematureSourceZeroReads -gt 0) 'Short-read EOF not promoted to complete FAT scan'}
        'M03-cap32' {Check-D19 ($base.actual -le 32 -and $cand.actual -le 32 -and
            $base.report.geometryTrustDecision -eq 'insufficient_evidence' -and
            $cand.report.geometryTrustDecision -eq 'insufficient_evidence') '32-byte budget returns insufficient evidence, not authentic geometry'}
    }
    if(($case.id -eq 'M03' -or $case.id -eq 'M05' -or $case.id -eq 'X02' -or $case.id -eq 'REMOTE') -and -not $baselineHit){$naiveFalseHealthy++}
    $bRead+=$base.actual;$cRead+=$cand.actual;$bUnique+=$base.unique;$cUnique+=$cand.unique;$bCalls+=$base.calls;$cCalls+=$cand.calls
    Write-Host ('D P6 {0}: mismatches={1}; cycles={2}; old actual/unique={3}/{4} calls={5}; new actual/unique={6}/{7} calls={8}' -f
        $case.id,$base.report.evidence.mirrorDifferentEntries,$cand.report.evidence.observedCycles,
        $base.actual,$base.unique,$base.calls,$cand.actual,$cand.unique,$cand.calls)
}
Check-D19 ($bTP -eq 2 -and $bFP -eq 0 -and $bFN -eq 1 -and $bTN -eq 2) 'Observed in-window anomaly baseline TP2 FP0 FN1 TN2 on five selected cases'
Check-D19 ($cTP -eq 3 -and $cFP -eq 0 -and $cFN -eq 0 -and $cTN -eq 2) 'Mirror+cycle TP3 FP0 FN0 TN2 on same five selected cases'
Check-D19 ($unknown -eq 5) 'Five unobserved/ownership/truncated controls remain unscored unknown'
Check-D19 ($naiveFalseHealthy -eq 4) 'Mirror agreement alone could falsely certify four known-bad or unread artificial scenarios'
Write-Host ('D P6 A/B TP/FP/FN/TN mirror={0}/{1}/{2}/{3}, mirror+chain={4}/{5}/{6}/{7}; unknown={8}; naiveFalseHealthy={9}' -f
    $bTP,$bFP,$bFN,$bTN,$cTP,$cFP,$cFN,$cTN,$unknown,$naiveFalseHealthy)
Write-Host ('D P6 10-case physical actual/unique mirror={0}/{1}, mirror+chain={2}/{3}; source Read calls={4}/{5}' -f
    $bRead,$bUnique,$cRead,$cUnique,$bCalls,$cCalls)
# Independent, supplemental 64-byte chain test; deliberately OUTSIDE the
# preceding per-mode A/B budgets. It checks terminal equality != link equality.
$meter=[D19Meter]::new($conflict,[long]::MaxValue,4096)
try{
    $g=Get-ChappyFatGeometryTrust -Stream $meter
    $args=@{
        Stream=$meter
        Fat1OffsetBytes=[long]$g.geometry.fat1OffsetBytes
        Fat2OffsetBytes=[long]$g.geometry.fat2OffsetBytes
        FatLengthBytes=[long]$g.geometry.fatLengthBytes
        MaxDataCluster=([long]$g.geometry.dataClusterCount+1L)
        StartClusters=@([long]4)
        MaxStepsPerChain=8
        MaxTotalEntries=8
        MaxReadBytes=64
    }
    $chains=Get-ChappyFatChainAnomalyStats @args
    Check-D19 (@($chains.items).Count -eq 2 -and
        @($chains.items|Where-Object {$_.terminal -eq 'eoc'}).Count -eq 2 -and
        $chains.metrics.differentMirrorTerminals -eq 0) 'Different FAT links both terminate EOC; terminal equality is not a correct-copy proof'
    Check-D19 ($meter.Actual -le 2048 -and -not $chains.writePermitted) 'Separate supplementary trace accounted and strictly read-only'
    Write-Host ('D P6 supplemental direct chain actual/unique={0}/{1}, ReadCalls={2}' -f $meter.Actual,$meter.Unique,$meter.Calls)
}finally{$meter.Dispose()}
$writable=[IO.MemoryStream]::new($clean,$true)
try{
    $reject=$false
    try{$null=Get-ChappyFatObservedIoEvidence -Stream $writable -Mode MirrorAndChain}catch{$reject=$true}
    Check-D19 $reject 'Writable input rejected before any repair or source scan'
}finally{$writable.Dispose()}
Write-Host ('Team D R6-P6 dual-mirror ambiguity: {0} passed, {1} failed.' -f $script:passed,$script:failed)
if($script:failed -gt 0){exit 1}
