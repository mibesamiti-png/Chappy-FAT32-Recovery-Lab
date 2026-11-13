#Requires -Version 5.1
# Team D #73 D6-04. Independently observed synthetic source reads only.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32ObservedIoEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32PhysicalPairCoverage.psm1') -Force
$script:Pass=0;$script:Fail=0
function Check-D27([bool]$Okay,[string]$Label){
    if($Okay){$script:Pass++;Write-Host ('PASS '+$Label)}
    else{$script:Fail++;Write-Host ('FAIL '+$Label)}
}
function Throws-D27([scriptblock]$Action){
    try{$null=& $Action;return $false}catch{return $true}
}
function Hash-D27([byte[]]$Buffer){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($Buffer)).Replace('-','')}
    finally{$sha.Dispose()}
}
function Set-D27U32([byte[]]$Buffer,[int]$At,[uint32]$Value){
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$Buffer,$At,4)
}
# This test meter is independent from D13 and from the reconciliation helper.
# It alone has access to actual source bytes. It stores only successful READ
# spans for the D helper; private full bytes never enter a D report.
if(-not ('D27IndependentPhysicalSource' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D27ReturnedEvent {
    public long OffsetBytes {get;set;}
    public int ReturnedBytes {get;set;}
}
public sealed class D27IndependentPhysicalSource : Stream {
    readonly MemoryStream input;
    readonly HashSet<long> seen=new HashSet<long>();
    readonly List<D27ReturnedEvent> spans=new List<D27ReturnedEvent>();
    readonly long sourceCap,stop;
    readonly int maxChunk;
    long used=0,calls=0,early=0;
    public D27IndependentPhysicalSource(byte[] bytes,long ceiling,long cutoff,int chunk){
        if(bytes==null||ceiling<2048||ceiling>120000||cutoff<0||chunk<1||chunk>4096)
            throw new ArgumentException("Invalid artificial physical source limits");
        input=new MemoryStream(bytes,false);
        sourceCap=ceiling;stop=cutoff;maxChunk=chunk;
    }
    public long ActualBytes {get{return used;}}
    public long UniqueBytes {get{return seen.Count;}}
    public long ReadCalls {get{return calls;}}
    public long PrematureZero {get{return early;}}
    public D27ReturnedEvent[] GetSuccessfulEvents(){return spans.ToArray();}
    public bool HasAll(long start,int n) {
        if(start<0||n<0||start>long.MaxValue-n)return false;
        for(int i=0;i<n;i++)if(!seen.Contains(start+i))return false;
        return true;
    }
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return input.Length;}}
    public override long Position {get{return input.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long offset,SeekOrigin origin){return input.Seek(offset,origin);}
    public override int Read(byte[] bytes,int off,int count) {
        if(bytes==null||off<0||count<0||off>bytes.Length-count)throw new ArgumentException("Invalid Read");
        calls++;
        if(count>sourceCap-used)throw new IOException("D27.outer_source_cap_refused");
        if(count==0)return 0;
        long at=input.Position;
        if(used>=stop){if(at<input.Length)early++;return 0;}
        int allowed=(int)Math.Min((long)count,Math.Min((long)maxChunk,stop-used));
        int n=input.Read(bytes,off,allowed);
        if(n==0&&at<input.Length)early++;
        if(n>0){
            used+=n;
            spans.Add(new D27ReturnedEvent{OffsetBytes=at,ReturnedBytes=n});
            for(int i=0;i<n;i++)seen.Add(at+i);
        }
        return n;
    }
    public override void Flush(){}
    public override void SetLength(long n){throw new NotSupportedException();}
    public override void Write(byte[] b,int off,int n){throw new NotSupportedException();}
    protected override void Dispose(bool disposing){if(disposing)input.Dispose();base.Dispose(disposing);}
}
'@
}
function Run-D27 {
    param([byte[]]$Image,[long]$Fat1,[long]$Fat2,[long]$FatBytes,
        [long]$Stop=[long]::MaxValue,[int]$Chunk=4096,[int]$MaxRead=2048)
    $outer=[D27IndependentPhysicalSource]::new($Image,120000L,$Stop,$Chunk)
    try{
        $d=Get-ChappyFatObservedIoEvidence -Stream $outer -Mode MirrorAndChain -MaxReadBytes $MaxRead
        $args=@{
            Observation=$d;OuterReturnedEvents=@($outer.GetSuccessfulEvents())
            Fat1OffsetBytes=$Fat1;Fat2OffsetBytes=$Fat2
            FatLengthBytes=$FatBytes;SourceLengthBytes=([long]$Image.Length)
            MaxReturnedBytes=$MaxRead
        }
        $coverage=Get-ChappyFatPhysicalPairCoverage @args
        return [pscustomobject]@{
            report=$coverage;observation=$d;events=@($outer.GetSuccessfulEvents())
            actual=$outer.ActualBytes;unique=$outer.UniqueBytes
            calls=$outer.ReadCalls;early=$outer.PrematureZero
            first64Paired=@(0..63 | Where-Object {
                $i=[long]$_
                $outer.HasAll(($Fat1+$i*4),4) -and $outer.HasAll(($Fat2+$i*4),4)
            }).Count
        }
    }finally{$outer.Dispose()}
}
function Check-D27Scope($Case,$Result){
    $r=$Result.report
    Check-D27 ($r.team -ceq 'D' -and
        $r.mode -ceq 'read_only_unattested_physical_FAT_pair_coverage' -and
        -not $r.writePermitted -and -not $r.wholeFatVerified -and
        $r.originalIdentity -ceq 'unknown' -and $r.fileOwner -ceq 'unknown' -and
        $r.fatCopyWinner -ceq 'not_selected' -and
        $r.sourceReadProvenance -ceq 'outer_events_caller_supplied_NOT_A_attested' -and
        $r.geometryProvenance -ceq 'caller_supplied_unverified') ($Case+' independent D report never asserts original, FAT winner, A receipt or repair')
    Check-D27 ($Result.actual -le 2048 -and $Result.actual -le 120000 -and
        $Result.unique -le $Result.actual -and
        $Result.calls -ge $Result.events.Count -and
        $Result.observation.metrics.bytesRead -eq $Result.actual -and
        $Result.observation.metrics.uniquePhysicalBytes -eq $Result.unique) ($Case+' D13 and separate physical source match actual/unique and limits')
    $sum=0L
    foreach($e in $Result.events){$sum += [long]$e.ReturnedBytes}
    Check-D27 ($sum -eq $Result.actual -and
        $Result.observation.readEvents.Count -eq $Result.events.Count -and
        $Result.observation.metrics.prematureSourceZeroReads -eq $Result.early) ($Case+' independent successful bytes, events and premature zero accounted')
}
$cases=@(
    [pscustomobject]@{id='clean1';seed=202611;spc=1;fault='none';stop=[long]::MaxValue;chunk=4096;expected='partial_numeric_candidate_only'},
    [pscustomobject]@{id='clean2';seed=202612;spc=2;fault='none';stop=[long]::MaxValue;chunk=4096;expected='partial_numeric_candidate_only'},
    [pscustomobject]@{id='fat2_only';seed=202613;spc=1;fault='mirror';stop=[long]::MaxValue;chunk=4096;expected='partial_numeric_candidate_only'},
    [pscustomobject]@{id='both_cycle';seed=202611;spc=2;fault='cycle';stop=[long]::MaxValue;chunk=4096;expected='partial_numeric_candidate_only'},
    [pscustomobject]@{id='far60000';seed=202612;spc=2;fault='far';stop=[long]::MaxValue;chunk=4096;expected='partial_numeric_candidate_only'},
    [pscustomobject]@{id='malformed_spc';seed=202613;spc=1;fault='spc';stop=[long]::MaxValue;chunk=4096;expected='unknown'},
    [pscustomobject]@{id='malformed_fat';seed=202611;spc=1;fault='fat';stop=[long]::MaxValue;chunk=4096;expected='unknown'},
    [pscustomobject]@{id='early_zero_1100';seed=202612;spc=1;fault='none';stop=1100L;chunk=7;expected='unknown'},
    [pscustomobject]@{id='partial_fat_1026';seed=202613;spc=2;fault='none';stop=1026L;chunk=7;expected='unknown'}
)
$actualTotal=0L;$uniqueTotal=0L;$callTotal=0L
$known=0;$unknown=0;$matched=0
$sample=$null;$sampleArgs=$null;$sampleEvents=$null
foreach($case in $cases){
    $fixture=New-ChappyA3DStandardFixture -Seed $case.seed -SectorsPerCluster $case.spc
    [byte[]]$image=$fixture.image
    $fatSectors=[long][Math]::Ceiling((4.0*(65541+2))/512.0)
    $fatBytes=[long]($fatSectors*512)
    $fat1=33L*512L
    $fat2=$fat1+$fatBytes
    switch($case.fault){
        'mirror' {Set-D27U32 $image ([int]($fat2+16)) ([uint32]4)}
        'cycle' {
            Set-D27U32 $image ([int]($fat1+16)) ([uint32]4)
            Set-D27U32 $image ([int]($fat2+16)) ([uint32]4)
        }
        'far' {Set-D27U32 $image ([int]($fat2+4*60000)) ([uint32]1)}
        'spc' {$image[512+13]=0}
        'fat' {Set-D27U32 $image (512+36) ([uint32]::MaxValue)}
    }
    $before=Hash-D27 $image
    $x=Run-D27 -Image $image -Fat1 $fat1 -Fat2 $fat2 -FatBytes $fatBytes -Stop $case.stop -Chunk $case.chunk
    $r=$x.report
    Check-D27Scope $case.id $x
    Check-D27 ($r.status -ceq $case.expected) ($case.id+' report numeric candidate or conservatively UNKNOWN')
    Check-D27 ((Hash-D27 $image) -ceq $before) ($case.id+' SHA256 unchanged on synthetic input')
    if($case.expected -ceq 'unknown'){
        $unknown++
        Check-D27 (-not $r.externalEventAgreement -and
            $null -eq $r.metrics.pairedCoveragePercent -and
            $null -eq $r.metrics.totalDeclaredFatEntriesPerCopy -and
            $null -eq $r.metrics.pairedFullyObservedEntries) ($case.id+' malformed or premature zero yields no numeric pair percentage')
    }else{
        $known++;$matched++
        Check-D27 ($r.externalEventAgreement -and
            $r.metrics.totalDeclaredFatEntriesPerCopy -eq 65664L -and
            $r.metrics.fullyObservedFat1Entries -ge 64 -and
            $r.metrics.fullyObservedFat2Entries -ge 64 -and
            $r.metrics.pairedFullyObservedEntries -ge 64 -and
            $r.metrics.pairedFullyObservedEntries -lt $r.metrics.totalDeclaredFatEntriesPerCopy -and
            $r.metrics.unobservedPairPercent -gt 99.8) ($case.id+' exact 4B per-copy and paired physical coverage, huge UNKNOWN remote')
        Check-D27 ($x.first64Paired -eq 64) ($case.id+' independent source confirms first64 paired entries really returned')
        Check-D27 ($r.metrics.physicalReturnedBytes -eq $x.actual -and
            $r.metrics.physicalUniqueBytes -eq $x.unique -and
            $r.metrics.physicalRepeatedBytes -eq ($x.actual-$x.unique)) ($case.id+' exact actual/unique/repeated counters reconciled to outer events')
        if($case.id -ceq 'fat2_only'){
            Check-D27 ($x.observation.evidence.mirrorDifferentEntries -gt 0) 'Observed FAT2-only mismatch does not select FAT winner'
        }
        if($case.id -ceq 'both_cycle'){
            Check-D27 ($x.observation.evidence.mirrorDifferentEntries -eq 0 -and
                $x.observation.evidence.observedCycles -gt 0) 'Common-mode mirrored cycle is not clean'
        }
        if($case.id -ceq 'far60000'){
            Check-D27 ($r.metrics.unobservedPairedEntryIndices -gt 65000 -and
                $r.warnings -contains 'fat.remote_unobserved_UNKNOWN_not_clean') 'Remote FAT2 entry60000 remains inaccessible, not absence of damage'
        }
        if($case.id -ceq 'clean1'){
            $sample=$x.observation
            $sampleEvents=$x.events
            $sampleArgs=@{Fat1OffsetBytes=$fat1;Fat2OffsetBytes=$fat2;
                FatLengthBytes=$fatBytes;SourceLengthBytes=([long]$image.Length)}
        }
    }
    $actualTotal+=$x.actual;$uniqueTotal+=$x.unique;$callTotal+=$x.calls
    Write-Host ('D6-04 scenario={0} observedPair={1} / {2} unknown={3} physical actual/unique={4}/{5} reads={6} provenance=unattested' -f
        $case.id,$r.metrics.pairedFullyObservedEntries,$r.metrics.totalDeclaredFatEntriesPerCopy,
        $r.status,$x.actual,$x.unique,$x.calls)
    $fixture=$null;$image=$null
    [GC]::Collect()
}
Check-D27 ($known -eq 5 -and $unknown -eq 4) 'Predeclared nine test cases: five numeric candidate and four UNKNOWN'
Check-D27 ($sample -ne $null -and $sampleEvents.Count -gt 2) 'Independent clean source was retained for adversarial event replay'
# Event-list tampering: same total bytes does not mean correct physical spans.
$correct=Get-ChappyFatPhysicalPairCoverage -Observation $sample -OuterReturnedEvents $sampleEvents @sampleArgs
Check-D27 ($correct.externalEventAgreement -and $correct.metrics.pairedFullyObservedEntries -ge 64) 'Untampered outer source spans accepted as numeric-only candidate'
$missing=@($sampleEvents | Select-Object -Skip 1)
$bad=Get-ChappyFatPhysicalPairCoverage -Observation $sample -OuterReturnedEvents $missing @sampleArgs
Check-D27 ($bad.status -ceq 'unknown' -and -not $bad.externalEventAgreement -and
    $null -eq $bad.metrics.pairedCoveragePercent) 'Missing successful source event cannot create verified FAT coverage'
$shift=@(foreach($e in $sampleEvents){[pscustomobject]@{OffsetBytes=[long]$e.OffsetBytes;ReturnedBytes=[long]$e.ReturnedBytes}})
$shift[0].OffsetBytes+=1L
$bad=Get-ChappyFatPhysicalPairCoverage -Observation $sample -OuterReturnedEvents $shift @sampleArgs
Check-D27 ($bad.status -ceq 'unknown' -and $null -eq $bad.metrics.pairedFullyObservedEntries) 'Fabricated off-by-one event same counts is refused'
$reordered=@($sampleEvents)
$tmp=$reordered[0];$reordered[0]=$reordered[1];$reordered[1]=$tmp
$bad=Get-ChappyFatPhysicalPairCoverage -Observation $sample -OuterReturnedEvents $reordered @sampleArgs
Check-D27 ($bad.status -ceq 'unknown') 'Reordered physical Read events rejected despite same bytes and union'
$dup=@($sampleEvents)+@($sampleEvents[0])
$bad=Get-ChappyFatPhysicalPairCoverage -Observation $sample -OuterReturnedEvents $dup @sampleArgs
Check-D27 ($bad.status -ceq 'unknown') 'Replayed otherwise valid returned event refused'
$overlapArgs=$sampleArgs.Clone();$overlapArgs.Fat2OffsetBytes=$sampleArgs.Fat1OffsetBytes+4L
$bad=Get-ChappyFatPhysicalPairCoverage -Observation $sample -OuterReturnedEvents $sampleEvents @overlapArgs
Check-D27 ($bad.status -ceq 'unknown' -and $null -eq $bad.metrics.pairedCoveragePercent) 'Caller overlapping FAT geometry refused'
$hugeArgs=$sampleArgs.Clone();$hugeArgs.Fat1OffsetBytes=[long]::MaxValue-3
$bad=Get-ChappyFatPhysicalPairCoverage -Observation $sample -OuterReturnedEvents $sampleEvents @hugeArgs
Check-D27 ($bad.status -ceq 'unknown') 'Huge overflowing source offsets refused without any read'
$bad=Get-ChappyFatPhysicalPairCoverage -Observation $sample -OuterReturnedEvents $sampleEvents @sampleArgs -MaxReturnedBytes 512
Check-D27 ($bad.status -ceq 'unknown' -and $null -eq $bad.metrics.pairedCoveragePercent) 'Source return budget too small refuses rather than promoting coverage'
$forged=@([pscustomobject]@{OffsetBytes=0L;ReturnedBytes=5000L})
$bad=Get-ChappyFatPhysicalPairCoverage -Observation $sample -OuterReturnedEvents $forged @sampleArgs
Check-D27 ($bad.status -ceq 'unknown' -and $null -eq $bad.metrics.physicalReturnedBytes) 'Forged oversized event cannot claim numeric physical evidence'
$fake=[byte[]]::new(8192)
$writable=[IO.MemoryStream]::new($fake,$true)
try{
    Check-D27 (Throws-D27 {Get-ChappyFatObservedIoEvidence -Stream $writable -Mode MirrorAndChain}) 'Underlying D13 rejects writable source before any source read'
}finally{$writable.Dispose()}
Write-Host ('D6-04 totals 9 independent generated sources: actual={0} source-local unique={1} repeated={2} reads={3}; remote unobserved, original identity UNKNOWN' -f
    $actualTotal,$uniqueTotal,($actualTotal-$uniqueTotal),$callTotal)
Write-Host ('Team D D6-04 physically observed paired FAT entries: {0} PASS / {1} FAIL' -f $script:Pass,$script:Fail)
if($script:Fail -gt 0){exit 1}
