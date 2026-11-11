#Requires -Version 5.1
# Team D R9: deterministic, entirely synthetic 64KiB FAT layouts and same-corpus A/B.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\Fat32VbrMirrorCrossEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32StratifiedAnomalies.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32AdditiveAnomalyEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32LongCycleRemoteEvidence.psm1') -Force
$script:Pass=0;$script:Fail=0
function Check-D9 {
    param([bool]$Condition,[string]$Label)
    if($Condition){Write-Host "PASS $Label";$script:Pass++}
    else{Write-Host "FAIL $Label";$script:Fail++}
}
function Throws-D9 {
    param([scriptblock]$Code)
    try{$null=& $Code;return $false}catch{return $true}
}
function Set-D9Entry {
    param([byte[]]$B,[int]$Fat,[int]$Index,[uint32]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$B,($Fat+4*$Index),4)
}
function New-D9Fixture {
    $b=New-Object 'byte[]' 65536
    $eoc=[Convert]::ToUInt32('0FFFFFFF',16)
    $reserved=[Convert]::ToUInt32('0FFFFFF8',16)
    foreach($fat in @(4096,4608,8192,8704)){
        Set-D9Entry $b $fat 0 $reserved
        for($i=1;$i -lt 40;$i++){Set-D9Entry $b $fat $i $eoc}
    }
    [Text.Encoding]::ASCII.GetBytes('INVENTED-PRIVATE-CANARY-NO-EXPORT').CopyTo($b,49000)
    return ,$b
}
function New-D9Candidates {
    $a=[pscustomobject]@{plausibility='plausible_unverified';geometry=[pscustomobject]@{
        fat1OffsetBytes=4096L;fat2OffsetBytes=4608L;fatLengthBytes=512L
        rootCluster=2L;dataClusterCount=32L;volumeEndExclusiveBytes=65536L
    }}
    $b=[pscustomobject]@{plausibility='plausible_unverified';geometry=[pscustomobject]@{
        fat1OffsetBytes=8192L;fat2OffsetBytes=8704L;fatLengthBytes=512L
        rootCluster=3L;dataClusterCount=32L;volumeEndExclusiveBytes=65536L
    }}
    return ,@($a,$b)
}
function Hash-D9 {
    param([byte[]]$B)
    $hash=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($hash.ComputeHash($B)).Replace('-','')}
    finally{$hash.Dispose()}
}
# This memory-only instrument accounts physical 4-byte locations for all four
# algorithms on the same synthetic stream without modifying their production APIs.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D9ObservedMemoryStream : Stream {
    private readonly MemoryStream inner;
    private readonly HashSet<long> locations = new HashSet<long>();
    private readonly int chunk;
    private readonly long cutoff;
    private long actualBytes;
    private long requests;
    public D9ObservedMemoryStream(byte[] bytes, int chunkSize, long cutoffAt) {
        inner=new MemoryStream(bytes,false);
        chunk=chunkSize;cutoff=cutoffAt;
    }
    public int DistinctEntries {get {return locations.Count;}}
    public long ActualReadBytes {get {return actualBytes;}}
    public long ReadRequests {get {return requests;}}
    public override bool CanRead {get {return true;}}
    public override bool CanSeek {get {return true;}}
    public override bool CanWrite {get {return false;}}
    public override long Length {get {return inner.Length;}}
    public override long Position {get {return inner.Position;} set {inner.Position=value;}}
    public override int Read(byte[] b,int offset,int count){
        requests++;
        long start=inner.Position;
        if(start>=cutoff){return 0;}
        int size=inner.Read(b,offset,(int)Math.Min(count,Math.Min(chunk,cutoff-start)));
        actualBytes+=size;
        for(int n=0;n<size;n++){long pos=start+n;locations.Add((pos/4)*4);}
        return size;
    }
    public override long Seek(long offset, SeekOrigin origin) {return inner.Seek(offset,origin);}
    public override void Flush(){}
    public override void SetLength(long len){throw new NotSupportedException();}
    public override void Write(byte[] b,int offset,int count){throw new NotSupportedException();}
}
'@
function Run-D9 {
    param([byte[]]$Data,$C,[string]$Mode,[int]$Bytes=160,[int]$Entries=40,[int]$Chunk=4,[long]$Cutoff=[long]::MaxValue)
    $s=[D9ObservedMemoryStream]::new($Data,$Chunk,$Cutoff)
    try{
        $r=$(switch($Mode){
            'r6' {Get-ChappyFatVbrMirrorCrossEvidence -Stream $s -Candidates $C -RootWindowEntries 8 -MaxReadBytes $Bytes -MaxEntries $Entries}
            'r7' {Get-ChappyFatStratifiedAnomalyEvidence -Stream $s -Candidates $C -MaxReadBytes $Bytes -MaxEntries $Entries}
            'r8' {Get-ChappyFatAdditiveAnomalyEvidence -Stream $s -Candidates $C -MaxReadBytes $Bytes -MaxEntries $Entries}
            'r9' {Get-ChappyFatLongCycleRemoteEvidence -Stream $s -Candidates $C -MaxReadBytes $Bytes -MaxEntries $Entries}
        })
        return [pscustomobject]@{result=$r;unique=$s.DistinctEntries;actualBytes=$s.ActualReadBytes;requests=$s.ReadRequests}
    }finally{$s.Dispose()}
}
function Positive-D9 {
    param($R,[string]$Mode)
    if($Mode -eq 'r6'){
        return ($R.metrics.totalAnomalyObservations -gt 0 -or $R.items[0].mirrors.differentEntries -gt 0 -or $R.items[1].mirrors.differentEntries -gt 0)
    }
    if($Mode -eq 'r7'){
        return ($R.metrics.suspiciousEntries -gt 0 -or $R.items[0].mirrors.differingEntries -gt 0 -or $R.items[1].mirrors.differingEntries -gt 0)
    }
    if($Mode -eq 'r8'){
        return ($R.rootSuspiciousObserved -or $R.remoteSuspiciousObserved -or $R.mirrorDisagreementObserved)
    }
    return ($R.metrics.anomalyIndicators -gt 0 -or $R.metrics.detectedRootCycles -gt 0 -or
        $R.items[0].mirrors.differingEntries -gt 0 -or $R.items[1].mirrors.differingEntries -gt 0)
}

$good=New-D9Fixture
$cands=New-D9Candidates
$original=Hash-D9 $good
$p=Run-D9 $good $cands 'r9'
$r=$p.result
Check-D9 ($r.schemaVersion -eq '1' -and $r.team -eq 'D' -and $r.mode -eq 'experimental_long_root_far_fat_evidence') 'R9 schema and identity'
Check-D9 ($r.experimentalDefaultOff -and -not $r.writePermitted -and $null -eq $r.selectedCandidate -and $r.sourceDecision -eq 'not_selected') 'Default OFF, no selection and no writes'
Check-D9 ($r.crossEvidence -eq 'ambiguous_samples_no_selection' -and -not $r.scanIncomplete) 'Clean selected sample stays ambiguous not healthy'
Check-D9 ($r.metrics.bytesRead -eq 160 -and $r.metrics.entriesRead -eq 40 -and $r.metrics.uniquePhysicalEntries -eq 40) 'Normal R9 four copies read 40 unique 4B entries'
Check-D9 ($r.metrics.duplicatePhysicalEntryReads -eq 0 -and $r.metrics.perCopyEntryQuota -eq 10) 'No overlap in normal geometry and fixed 10 per-copy quota'
Check-D9 ($r.items[0].fatCopies[0].sampleWindows.Count -eq 4 -and $r.items[0].fatCopies[0].sampleWindows[3].region -eq 'far') 'Four bounded windows per copy'
Check-D9 ($r.items[0].fatCopies[0].observedUniqueEntries -eq 10 -and $r.items[0].fatCopies[0].unknownDeclaredEntries -eq 118) '118 of 128 FAT entries remain unknown per copy'
Check-D9 ($p.unique -eq $r.metrics.uniquePhysicalEntries -and $p.actualBytes -eq 160) 'Independent instrument confirms true physical distinct entry count and bytes'
Check-D9 ($r.warnings -contains 'real_master_img_trial_not_authorized' -and $r.warnings -contains 'coverage.unsampled_entries_unknown') 'No original media approval or healthy original inference'
$json=$r|ConvertTo-Json -Depth 15
Check-D9 ($json -notmatch 'INVENTED-PRIVATE|CANARY|rawBytes|sourcePath|SHA256|originalFilename|repairTarget') 'No raw byte, names, hashes, paths or repair instruction in JSON'
Check-D9 ((Hash-D9 $good) -eq $original) 'Synthetic original unchanged'

$cases=@(
    [pscustomobject]@{name='clean';kind='clean';positive=$false},
    [pscustomobject]@{name='legal_mid_free';kind='mid_free';positive=$false},
    [pscustomobject]@{name='legal_far_free';kind='far_free';positive=$false},
    [pscustomobject]@{name='root_cycle2';kind='cycle2';positive=$true},
    [pscustomobject]@{name='root_cycle3';kind='cycle3';positive=$true},
    [pscustomobject]@{name='root_cycle4';kind='cycle4';positive=$true},
    [pscustomobject]@{name='noncontiguous_root_cycle';kind='noncontig_cycle';positive=$true},
    [pscustomobject]@{name='mid_bad_identical';kind='mid_bad';positive=$true},
    [pscustomobject]@{name='far_bad_identical';kind='far_bad';positive=$true},
    [pscustomobject]@{name='far_eb58';kind='far_eb58';positive=$true},
    [pscustomobject]@{name='far_out_of_range';kind='far_out';positive=$true},
    [pscustomobject]@{name='root_free';kind='root_free';positive=$true},
    [pscustomobject]@{name='fake_prefix_eb58';kind='prefix_eb58';positive=$true},
    [pscustomobject]@{name='mid_eb58';kind='mid_eb58';positive=$true},
    [pscustomobject]@{name='noncontiguous_valid_link';kind='noncontig_ok';positive=$false}
)
$matrix=@{}
foreach($mode in @('r6','r7','r8','r9')){
    $matrix[$mode]=@{tp=0;fp=0;fn=0;tn=0;bytes=0;entries=0;unique=0;requests=0;unknownRuns=0}
}
$wrongClaims=0
$clocks=@{r6=[Diagnostics.Stopwatch]::new();r7=[Diagnostics.Stopwatch]::new();r8=[Diagnostics.Stopwatch]::new();r9=[Diagnostics.Stopwatch]::new()}
foreach($case in $cases){
    $b=New-D9Fixture
    $eoc=[Convert]::ToUInt32('0FFFFFFF',16)
    switch($case.kind){
        'mid_free' {foreach($fat in @(4096,4608)){Set-D9Entry $b $fat 17 0}}
        'far_free' {foreach($fat in @(4096,4608)){Set-D9Entry $b $fat 25 0}}
        'cycle2' {foreach($fat in @(4096,4608)){Set-D9Entry $b $fat 2 3;Set-D9Entry $b $fat 3 2}}
        'cycle3' {foreach($fat in @(4096,4608)){Set-D9Entry $b $fat 2 3;Set-D9Entry $b $fat 3 4;Set-D9Entry $b $fat 4 2}}
        'cycle4' {foreach($fat in @(4096,4608)){Set-D9Entry $b $fat 2 3;Set-D9Entry $b $fat 3 4;Set-D9Entry $b $fat 4 5;Set-D9Entry $b $fat 5 2}}
        'noncontig_cycle' {foreach($fat in @(4096,4608)){Set-D9Entry $b $fat 2 9;Set-D9Entry $b $fat 9 10;Set-D9Entry $b $fat 10 2}}
        'noncontig_ok' {foreach($fat in @(4096,4608)){Set-D9Entry $b $fat 2 9;Set-D9Entry $b $fat 9 $eoc}}
        'mid_bad' {foreach($fat in @(4096,4608)){Set-D9Entry $b $fat 17 ([Convert]::ToUInt32('0FFFFFF7',16))}}
        'far_bad' {foreach($fat in @(4096,4608)){Set-D9Entry $b $fat 25 ([Convert]::ToUInt32('0FFFFFF7',16))}}
        'far_eb58' {Set-D9Entry $b 4096 25 ([Convert]::ToUInt32('000058EB',16))}
        'far_out' {Set-D9Entry $b 4096 25 40}
        'root_free' {Set-D9Entry $b 4096 2 0}
        'prefix_eb58' {Set-D9Entry $b 4096 0 ([Convert]::ToUInt32('000058EB',16))}
        'mid_eb58' {Set-D9Entry $b 4096 17 ([Convert]::ToUInt32('000058EB',16))}
    }
    $before=Hash-D9 $b
    foreach($mode in @('r6','r7','r8','r9')){
        $clocks[$mode].Start()
        $p=Run-D9 $b $cands $mode
        $clocks[$mode].Stop()
        $r=$p.result
        $hit=Positive-D9 $r $mode
        if($case.positive){
            if($hit){$matrix[$mode].tp++}else{$matrix[$mode].fn++}
        }else{
            if($hit){$matrix[$mode].fp++}else{$matrix[$mode].tn++}
        }
        $matrix[$mode].bytes+=$p.actualBytes
        $matrix[$mode].entries+=$r.metrics.entriesRead
        $matrix[$mode].unique+=$p.unique
        $matrix[$mode].requests+=$p.requests
        if($r.scanIncomplete){$matrix[$mode].unknownRuns++}
        if($r.sourceDecision -ne 'not_selected' -or $null -ne $r.selectedCandidate -or
           $r.crossEvidence -match 'healthy|verified' -or $r.writePermitted){
            $wrongClaims++
        }
        Check-D9 ($r.metrics.bytesRead -eq $p.actualBytes -and $p.actualBytes -le 160 -and $r.metrics.entriesRead -le 40) ('Per-run actual byte and entry caps '+$mode+' '+$case.name)
        Check-D9 ($p.unique -le $r.metrics.entriesRead) ('Independent physical coverage <= charged entries '+$mode+' '+$case.name)
        if($mode -eq 'r9'){
            Check-D9 ($r.metrics.uniquePhysicalEntries -eq $p.unique -and $r.metrics.duplicatePhysicalEntryReads -eq ($r.metrics.entriesRead-$p.unique)) ('R9 unique coverage matches measured source offsets '+$case.name)
            if($case.kind -eq 'cycle4'){
                Check-D9 ($r.metrics.detectedRootCycles -eq 2 -and $hit) 'Four-link mirrored root cycle detected by R9'
            }
            if($case.kind -eq 'far_bad'){
                Check-D9 ($hit -and $r.items[0].fatCopies[0].anomalyIndicators -gt 0) 'Distant identically corrupted FAT copies flagged'
            }
            if($case.kind -eq 'noncontig_cycle'){
                Check-D9 ($r.scanIncomplete -and $r.items[0].fatCopies[0].rootChainEvidence -eq 'chain_outside_sample') 'Noncontiguous cycle beyond window is unknown, never claimed recovered'
            }
        }
    }
    Check-D9 ((Hash-D9 $b) -eq $before) ('All four preserve artificial source SHA '+$case.name)
}
Check-D9 ($wrongClaims -eq 0) 'No winner, healthy/verified-original or writer claims from any method'
Check-D9 ($matrix['r9'].fp -eq 0 -and $matrix['r9'].fn -ge 1) 'Explicit known root fragmentation FN and no invented perfect detection'
Check-D9 ($matrix['r9'].tp -gt $matrix['r8'].tp) 'R9 detects more selected artificial cases than R8 under equal upper budget'
foreach($mode in @('r6','r7','r8','r9')){
    $v=$matrix[$mode]
    Write-Host ('D9 MATRIX '+$mode+' TP='+$v.tp+' FP='+$v.fp+' FN='+$v.fn+' TN='+$v.tn+
        ' bytes='+$v.bytes+' chargedEntries='+$v.entries+' uniquePhysical='+$v.unique+
        ' duplicateReads='+($v.entries-$v.unique)+' readRequests='+$v.requests+
        ' incompleteCases='+$v.unknownRuns+' stopwatchMs='+$clocks[$mode].ElapsedMilliseconds)
}
Write-Host ('D9 SAMPLES artificial='+$cases.Count+' positive='+@($cases | Where-Object {$_.positive}).Count+' negative='+@($cases | Where-Object {-not $_.positive}).Count)

# Overlapping windows within R9: root2..5, midpoint4..5, far5..6.
$overlap=New-D9Candidates
foreach($c in $overlap){$c.geometry.rootCluster=2L;$c.geometry.dataClusterCount=6L}
$p=Run-D9 $good $overlap 'r9'
$r=$p.result
Check-D9 ($r.metrics.bytesRead -eq 112 -and $r.metrics.entriesRead -eq 28) 'Overlapping root, midpoint and far windows only charge 28 actual entries'
Check-D9 ($r.metrics.uniquePhysicalEntries -eq 28 -and $r.items[0].fatCopies[0].observedUniqueEntries -eq 7) 'Seven unique indices per FAT copy with overlapping windows'
# Both candidates point to same FAT pair: same source offsets are reread as distinct
# hypotheses and charged but counted uniquely in physical coverage.
$duplicates=New-D9Candidates
$duplicates[1].geometry.fat1OffsetBytes=4096L
$duplicates[1].geometry.fat2OffsetBytes=4608L
$duplicates[1].geometry.rootCluster=2L
$p=Run-D9 $good $duplicates 'r9'
$r=$p.result
Check-D9 ($r.metrics.bytesRead -eq 160 -and $r.metrics.entriesRead -eq 40) 'Repeated source location across VBR candidates charged twice'
Check-D9 ($r.metrics.uniquePhysicalEntries -eq 20 -and $r.metrics.duplicatePhysicalEntryReads -eq 20) 'Repeated physical FAT copy views do not inflate unique coverage'
Check-D9 ($p.unique -eq 20) 'Instrument independently confirms twenty actual physical locations'

$invalid=New-D9Candidates
$invalid[1].geometry.fat1OffsetBytes=[long]::MaxValue-10
$invalid[1].geometry.fat2OffsetBytes=[long]::MaxValue-5
$p=Run-D9 $good $invalid 'r9';$r=$p.result
Check-D9 ($r.scanIncomplete -and $r.items[1].status -eq 'insufficient_evidence' -and $r.metrics.bytesRead -le 80) 'Huge malicious FAT offsets rejected before unsafe read'
$invalid=New-D9Candidates
$invalid[1].geometry.fat2OffsetBytes=8200L
$p=Run-D9 $good $invalid 'r9'
Check-D9 ($p.result.scanIncomplete -and $p.result.items[1].status -eq 'insufficient_evidence') 'Misaligned and shifted FAT2 refused'
$invalid=New-D9Candidates
$invalid[1].plausibility='contradicted'
$p=Run-D9 $good $invalid 'r9'
Check-D9 ($p.result.scanIncomplete -and $p.result.items[1].reasonCodes -contains 'candidate.not_plausible') 'Previously rejected VBR cannot be rehabilitated'

$p=Run-D9 $good $cands 'r9' -Bytes 16 -Entries 4
Check-D9 ($p.result.metrics.entriesRead -eq 4 -and $p.result.scanIncomplete -and $p.result.crossEvidence -eq 'insufficient_evidence') 'Extreme budget remains unknown and hard capped'
$p=Run-D9 $good $cands 'r9' -Bytes 32 -Entries 8
Check-D9 ($p.result.metrics.bytesRead -eq 32 -and $p.result.scanIncomplete) '32-byte budget cannot imply complete sample'
$p=Run-D9 $good $cands 'r9' -Bytes 256 -Entries 40
Check-D9 ($p.result.metrics.entriesRead -eq 40 -and $p.result.metrics.bytesRead -eq 160) '256-byte allowed cap still charges 40-entry max'
$p=Run-D9 $good $cands 'r9' -Bytes 160 -Entries 40 -Chunk 1
Check-D9 ($p.result.metrics.bytesRead -eq 160 -and $p.actualBytes -eq 160 -and $p.result.metrics.uniquePhysicalEntries -eq 40) 'One-byte fragmented reads reassembled, bytes accounted'
$p=Run-D9 $good $cands 'r9' -Bytes 160 -Entries 40 -Chunk 4 -Cutoff 8709
Check-D9 ($p.result.scanIncomplete -and $p.result.metrics.bytesRead -le 160 -and $p.result.status -eq 'partial') 'Premature EOF in mirror FAT is incomplete'
$w=[IO.MemoryStream]::new($good,$true)
try{Check-D9 (Throws-D9 {Get-ChappyFatLongCycleRemoteEvidence -Stream $w -Candidates $cands}) 'Writable stream explicitly rejected'}
finally{$w.Dispose()}
$s=[IO.MemoryStream]::new($good,$false)
try{
    Check-D9 (Throws-D9 {Get-ChappyFatLongCycleRemoteEvidence -Stream $s -Candidates @($cands[0])}) 'Exactly two candidate records required'
    Check-D9 (Throws-D9 {Get-ChappyFatLongCycleRemoteEvidence -Stream $s -Candidates $cands -MaxEntries 41}) 'Global 40-entry maximum enforced'
    Check-D9 (Throws-D9 {Get-ChappyFatLongCycleRemoteEvidence -Stream $s -Candidates $cands -MaxReadBytes 257}) 'Global 256-byte maximum enforced'
}finally{$s.Dispose()}
Check-D9 ((Hash-D9 $good) -eq $original) 'Original synthetic source SHA invariant'
Write-Host "Team D R9-P1 result: $script:Pass passed; $script:Fail failed."
if($script:Fail -gt 0){exit 1}
