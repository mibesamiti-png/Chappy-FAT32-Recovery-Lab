#Requires -Version 5.1
# Team D R6-P1 — fully artificial memory fixtures only.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\Fat32VbrMirrorCrossEvidence.psm1') -Force
$script:Pass=0;$script:Fail=0
function Check-D6 {
    param([bool]$Good,[string]$Label)
    if($Good){Write-Host "PASS $Label";$script:Pass++}
    else{Write-Host "FAIL $Label";$script:Fail++}
}
function Throws-D6 {
    param([scriptblock]$Code)
    try{$null=& $Code;return $false}catch{return $true}
}
function Make-D6Candidates {
    param([long]$BackupRoot=3,[long]$BackupOffset=8192)
    $one=[pscustomobject]@{
        plausibility='plausible_unverified'
        geometry=[pscustomobject]@{
            fat1OffsetBytes=4096L
            fat2OffsetBytes=4608L
            fatLengthBytes=512L
            rootCluster=2L
            dataClusterCount=32L
            volumeEndExclusiveBytes=65536L
        }
    }
    $two=[pscustomobject]@{
        plausibility='plausible_unverified'
        geometry=[pscustomobject]@{
            fat1OffsetBytes=$BackupOffset
            fat2OffsetBytes=($BackupOffset+512L)
            fatLengthBytes=512L
            rootCluster=$BackupRoot
            dataClusterCount=32L
            volumeEndExclusiveBytes=65536L
        }
    }
    return ,@($one,$two)
}
function Set-D6Fat {
    param([byte[]]$B,[long]$Base,[int]$Index,[uint32]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$B,([int]($Base+$Index*4)),4)
}
function Make-D6Fixture {
    $b=New-Object 'byte[]' 65536
    $eoc=[Convert]::ToUInt32('0FFFFFFF',16)
    $reserved=[Convert]::ToUInt32('0FFFFFF8',16)
    foreach($base in @(4096,4608,8192,8704)){
        Set-D6Fat $b $base 0 $reserved
        Set-D6Fat $b $base 1 $eoc
        Set-D6Fat $b $base 2 $eoc
        Set-D6Fat $b $base 3 $eoc
        Set-D6Fat $b $base 4 $eoc
        Set-D6Fat $b $base 5 $eoc
        Set-D6Fat $b $base 6 $eoc
        Set-D6Fat $b $base 7 $eoc
        Set-D6Fat $b $base 8 $eoc
        Set-D6Fat $b $base 9 $eoc
        Set-D6Fat $b $base 10 $eoc
    }
    [Text.Encoding]::ASCII.GetBytes('PRIVATE-PATH-AND-NAME-CANARY').CopyTo($b,50000)
    return ,$b
}
function Run-D6 {
    param([byte[]]$Bytes,$Candidates,[int]$Budget=128,[int]$Entries=32,[int]$RootWindow=4)
    $s=[IO.MemoryStream]::new($Bytes,$false)
    try {
        $args=@{Stream=$s;Candidates=$Candidates;MaxReadBytes=$Budget;MaxEntries=$Entries;RootWindowEntries=$RootWindow}
        return Get-ChappyFatVbrMirrorCrossEvidence @args
    }finally{$s.Dispose()}
}
function Hash-D6 {
    param([byte[]]$B)
    $h=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($h.ComputeHash($B)).Replace('-','')}
    finally{$h.Dispose()}
}
$healthy=Make-D6Fixture
$cands=Make-D6Candidates
$before=Hash-D6 $healthy
$r=Run-D6 $healthy $cands
Check-D6 ($r.schemaVersion -eq '1' -and $r.team -eq 'D' -and $r.mode -eq 'read_only_vbr_fat_mirror_cross_evidence') 'V1 result envelope and separate D research mode'
Check-D6 ($r.status -eq 'ok' -and -not $r.scanIncomplete) 'Synthetic EOC control fully sampled'
Check-D6 ($r.sourceDecision -eq 'not_selected' -and $null -eq $r.selectedCandidate -and -not $r.writePermitted) 'Source and repair never selected'
Check-D6 ($r.crossEvidence -eq 'ambiguous_equal_plausibility') 'Equal plausibility is ambiguous, not ranked'
Check-D6 ($r.differingCandidateGeometry -contains 'geometry.fat1OffsetBytes' -and $r.differingCandidateGeometry -contains 'geometry.rootCluster') 'Conflicting FAT offsets and roots reported'
Check-D6 ($r.items.Count -eq 2 -and $r.items[0].sourceRole -eq 'primary' -and $r.items[1].sourceRole -eq 'backup') 'Exactly two candidates in stable order'
Check-D6 ($r.items[0].fatCopies.Count -eq 2 -and $r.items[1].fatCopies.Count -eq 2) 'Two mirror copies under each independent geometry'
Check-D6 ($r.metrics.bytesRead -eq 96 -and $r.metrics.entriesRead -eq 24) 'Four copies x six entries equals 96 actual bytes'
Check-D6 ($r.metrics.perCopyEntryQuota -eq 8 -and $r.metrics.maxWindowsPerCopy -eq 2) 'Fair fixed quota across four hypotheses'
Check-D6 ($r.items[0].mirrors.commonEntries -eq 6 -and $r.items[0].mirrors.matchingEntries -eq 6 -and $r.items[0].mirrors.differentEntries -eq 0) 'Mirror common and matching counts exact'
Check-D6 ($r.items[0].mirrors.bothCopiesAgree -and $r.items[1].mirrors.bothCopiesAgree) 'Both copy pairs agree only in sample'
Check-D6 ($r.items[0].fatCopies[0].rootChainEvidence -eq 'eoc_observed' -and $r.items[1].fatCopies[1].rootChainEvidence -eq 'eoc_observed') 'Both root EOC observations'
Check-D6 ($r.metrics.totalAnomalyObservations -eq 0) 'No anomaly in artificial control'
Check-D6 ($r.warnings -contains 'fat.mirror_agreement_not_integrity' -and $r.warnings -contains 'real_master_img_trial_not_authorized') 'No real IMG health or approval claim'
$json=$r|ConvertTo-Json -Depth 12
Check-D6 ($json -notmatch 'PRIVATE-PATH|CANARY|SHA256|rawBytes|sourcePath|recoveredFilename|repairTarget') 'JSON excludes private canary or repair advice'
Check-D6 ((Hash-D6 $healthy) -eq $before) 'Artificial IMG remains unchanged'

$diff=Make-D6Fixture
Set-D6Fat $diff 4608 2 0
$r=Run-D6 $diff $cands
Check-D6 ($r.items[0].mirrors.differentEntries -eq 1 -and $r.items[0].mirrors.matchingEntries -eq 5) 'One primary-mirror mismatch counted'
Check-D6 ($r.items[0].fatCopies[1].rootChainEvidence -eq 'free_link_observed') 'Free link observed in one FAT'
Check-D6 ($r.items[1].mirrors.differentEntries -eq 0 -and $r.items[1].fatCopies[1].rootChainEvidence -eq 'eoc_observed') 'Other candidate geometry independently unaffected'
Check-D6 ($r.crossEvidence -eq 'observed_conflicts_no_selection' -and $null -eq $r.selectedCandidate) 'No winning candidate despite different evidence'

$bad=Make-D6Fixture
Set-D6Fat $bad 4096 2 0
Set-D6Fat $bad 4608 2 0
$r=Run-D6 $bad $cands
Check-D6 ($r.items[0].mirrors.bothCopiesAgree -and $r.items[0].mirrors.differentEntries -eq 0) 'Corrupt mirrors agree exactly'
Check-D6 ($r.items[0].fatCopies[0].rootChainEvidence -eq 'free_link_observed' -and $r.items[0].fatCopies[1].rootChainEvidence -eq 'free_link_observed') 'Both copies have the same free-cluster anomaly'
Check-D6 ($r.items[0].fatCopies[0].anomalyCount -ge 1 -and $r.crossEvidence -eq 'observed_conflicts_no_selection') 'Matching corrupted copies not healthy'
Check-D6 ($r.sourceDecision -eq 'not_selected') 'No chosen repair for matching corruption'

$cycle=Make-D6Fixture
foreach($base in @(4096,4608)){
    Set-D6Fat $cycle $base 2 3
    Set-D6Fat $cycle $base 3 2
}
$r=Run-D6 $cycle $cands
Check-D6 ($r.items[0].fatCopies[0].rootChainEvidence -eq 'cycle_observed' -and $r.items[0].fatCopies[1].rootChainEvidence -eq 'cycle_observed') 'Two-link FAT chain cycle detected'
Check-D6 ($r.metrics.bytesRead -eq 96 -and $r.metrics.totalAnomalyObservations -eq 2) 'Cycle does not trigger unbounded additional reads'

$out=Make-D6Fixture
Set-D6Fat $out 4096 2 40
$r=Run-D6 $out $cands
Check-D6 ($r.items[0].fatCopies[0].rootChainEvidence -eq 'out_of_range_link_observed') 'Out-of-range link observed'
$out=Make-D6Fixture
Set-D6Fat $out 4096 2 ([Convert]::ToUInt32('0FFFFFF7',16))
$r=Run-D6 $out $cands
Check-D6 ($r.items[0].fatCopies[0].rootChainEvidence -eq 'bad_link_observed') 'Bad cluster marker'
$out=Make-D6Fixture
Set-D6Fat $out 4096 2 1
$r=Run-D6 $out $cands
Check-D6 ($r.items[0].fatCopies[0].rootChainEvidence -eq 'reserved_link_observed') 'Reserved link detected'

$fake=Make-D6Fixture
$fake[4096]=0xEB;$fake[4097]=0x58;$fake[4098]=0x90
$fake[4096+510]=0x55;$fake[4096+511]=0xAA
$r=Run-D6 $fake $cands
Check-D6 ($r.items[0].fatCopies[0].prefixAnomalies -gt 0) 'Fake EB5890 at FAT start is suspicious FAT data'
Check-D6 ($r.sourceDecision -eq 'not_selected' -and $r.metrics.bytesRead -eq 96) 'Fake VBR-looking FAT data triggers no additional probes'

$badGeo=Make-D6Candidates
$badGeo[1].geometry.fat1OffsetBytes=65024L
$badGeo[1].geometry.fat2OffsetBytes=65536L
$r=Run-D6 $healthy $badGeo
Check-D6 ($r.items[1].status -eq 'insufficient_evidence' -and $r.items[1].reasonCodes -contains 'geometry.fat_regions_outside_volume') 'Out-of-image candidate refused'
Check-D6 ($r.metrics.bytesRead -eq 48 -and $r.scanIncomplete) 'Invalid candidate uses zero of its own quota'
Check-D6 ($r.crossEvidence -eq 'insufficient_evidence' -and $null -eq $r.selectedCandidate) 'No promotion of other candidate'

$huge=Make-D6Candidates
$huge[1].geometry.fat1OffsetBytes=[long]::MaxValue-100
$huge[1].geometry.fat2OffsetBytes=[long]::MaxValue-50
$r=Run-D6 $healthy $huge
Check-D6 ($r.items[1].reasonCodes -contains 'geometry.invalid_or_overflow') 'Int64 range overflow rejected'
Check-D6 ($r.metrics.bytesRead -eq 48) 'Overflow does not consume bytes'
$overlap=Make-D6Candidates
$overlap[1].geometry.fat2OffsetBytes=8300L
$r=Run-D6 $healthy $overlap
Check-D6 ($r.items[1].reasonCodes -contains 'geometry.fat_regions_outside_volume') 'Noncontiguous or overlapping FAT layout rejected'
$badRoot=Make-D6Candidates -BackupRoot 900
$r=Run-D6 $healthy $badRoot
Check-D6 ($r.items[1].reasonCodes -contains 'geometry.cluster_capacity_invalid') 'Root outside candidate cluster range rejected'

$notPlausible=Make-D6Candidates
$notPlausible[1].plausibility='contradicted'
$r=Run-D6 $healthy $notPlausible
Check-D6 ($r.items[1].reasonCodes -contains 'candidate.upstream_not_plausible') 'Untrusted upstream candidate cannot be upgraded'
Check-D6 ($r.metrics.bytesRead -eq 48 -and $r.sourceDecision -eq 'not_selected') 'Contradicted input does not cause automatic source selection'

$r=Run-D6 $healthy $cands -Budget 16 -Entries 4
Check-D6 ($r.metrics.bytesRead -eq 16 -and $r.metrics.entriesRead -eq 4) 'Minimum 16-byte four-entry cumulative cap'
Check-D6 ($r.metrics.perCopyEntryQuota -eq 1 -and $r.scanIncomplete -and $r.status -eq 'partial') 'Four equal entry quotas and incomplete coverage'
Check-D6 ($r.crossEvidence -eq 'insufficient_evidence') 'Budget exhaustion cannot rank candidate'
Check-D6 ($r.items[1].fatCopies[1].reasonCodes -contains 'budget.copy_quota_exhausted') 'Fourth FAT copy quota noted'
$r=Run-D6 $healthy $cands -Budget 32 -Entries 8
Check-D6 ($r.metrics.bytesRead -eq 32 -and $r.metrics.entriesRead -eq 8) 'Eight total entries and exact bytes'
Check-D6 ($r.items[0].fatCopies[0].rootChainEvidence -eq 'chain_outside_sample') 'Root chain not invented from header-only sample'
$r=Run-D6 $healthy $cands -Budget 256 -Entries 40 -RootWindow 8
Check-D6 ($r.metrics.bytesRead -eq 160 -and $r.metrics.entriesRead -eq 40) 'Max root window with 40 total entries bounded'
Check-D6 ($r.metrics.bytesRead -le $r.metrics.maxReadBytes -and $r.metrics.entriesRead -le $r.metrics.maxEntries) 'Global byte and entry caps never exceeded'

Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class D6ReadStream : Stream {
    private readonly MemoryStream inner;
    private readonly long cutoff;
    private readonly int chunk;
    public D6ReadStream(byte[] bytes, long cutoff, int chunk) {
        inner=new MemoryStream(bytes,false); this.cutoff=cutoff; this.chunk=chunk;
    }
    public override bool CanRead { get { return true; } }
    public override bool CanWrite { get { return false; } }
    public override bool CanSeek { get { return true; } }
    public override long Length { get { return inner.Length; } }
    public override long Position { get { return inner.Position; } set { inner.Position=value; } }
    public override long Seek(long offset,SeekOrigin origin) { return inner.Seek(offset,origin); }
    public override void Flush() {}
    public override int Read(byte[] buffer,int offset,int count) {
        if(inner.Position>=cutoff){return 0;}
        return inner.Read(buffer,offset,(int)Math.Min(Math.Min(count,chunk),cutoff-inner.Position));
    }
    public override void SetLength(long length) { throw new NotSupportedException(); }
    public override void Write(byte[] buffer,int offset,int count) { throw new NotSupportedException(); }
}
'@
$split=[D6ReadStream]::new($healthy,[long]::MaxValue,2)
try {
    $r=Get-ChappyFatVbrMirrorCrossEvidence -Stream $split -Candidates $cands
    Check-D6 ($r.crossEvidence -eq 'ambiguous_equal_plausibility' -and $r.metrics.bytesRead -eq 96) '2-byte fragmented source reads accurately assembled'
}finally{$split.Dispose()}
$stop=[D6ReadStream]::new($healthy,8709L,4)
try {
    $r=Get-ChappyFatVbrMirrorCrossEvidence -Stream $stop -Candidates $cands
    Check-D6 ($r.scanIncomplete -and $r.status -eq 'partial') 'Early end in backup FAT2 marks incomplete'
    Check-D6 ($r.items[1].fatCopies[1].reasonCodes -contains 'io.fat_entry_truncated') 'Partial FAT entry noted'
    Check-D6 ($r.metrics.bytesRead -eq 81) 'Actual short return counted, not requested bytes'
}finally{$stop.Dispose()}
$w=[IO.MemoryStream]::new($healthy,$true)
try {Check-D6 (Throws-D6 {Get-ChappyFatVbrMirrorCrossEvidence -Stream $w -Candidates $cands}) 'Writable stream rejected'}
finally{$w.Dispose()}
$s=[IO.MemoryStream]::new($healthy,$false)
try {
    Check-D6 (Throws-D6 {Get-ChappyFatVbrMirrorCrossEvidence -Stream $s -Candidates @($cands[0])}) 'Exactly two candidates required'
    Check-D6 (Throws-D6 {Get-ChappyFatVbrMirrorCrossEvidence -Stream $s -Candidates $cands -MaxReadBytes 257}) 'Global byte budget capped at 256'
    Check-D6 (Throws-D6 {Get-ChappyFatVbrMirrorCrossEvidence -Stream $s -Candidates $cands -MaxEntries 41}) 'Global entry count capped at 40'
    Check-D6 (Throws-D6 {Get-ChappyFatVbrMirrorCrossEvidence -Stream $s -Candidates $cands -RootWindowEntries 9}) 'Root window entries capped at eight'
}finally{$s.Dispose()}
Check-D6 ((Hash-D6 $healthy) -eq $before) 'Artificial source SHA unchanged'
Write-Host "Team D R6-P1 result: $script:Pass passed; $script:Fail failed."
if($script:Fail -gt 0){exit 1}
