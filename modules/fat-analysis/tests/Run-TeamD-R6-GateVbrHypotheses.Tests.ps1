#Requires -Version 5.1
# Team D #73 D6-03. Standards-shaped synthetic memory volumes only.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32GeometryHypothesisGate.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32VbrDisagreement.psm1') -Force
$script:Pass=0;$script:Fail=0
function Assert-D603([bool]$Pass,[string]$Message){
    if($Pass){$script:Pass++;Write-Host ('PASS '+$Message)}
    else{$script:Fail++;Write-Host ('FAIL '+$Message)}
}
function Throws-D603([scriptblock]$Action) {
    try{$null=& $Action;return $false}catch{return $true}
}
function Hash-D603([byte[]]$Image) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($Image)).Replace('-','')}
    finally{$sha.Dispose()}
}
function U16-D603([byte[]]$Image,[int]$Offset,[uint16]$Value) {
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$Image,$Offset,2)
}
function U32-D603([byte[]]$Image,[int]$Offset,[uint32]$Value) {
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$Image,$Offset,4)
}
# External scorer sees source returns independently of D internal events. It
# never feeds actual mutation positions, source SHA or expected labels to D.
if(-not ('D603ExternalSource' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D603ExternalSource : Stream {
    readonly MemoryStream input;
    readonly HashSet<long> seen=new HashSet<long>();
    readonly long stop;
    readonly int chunk;
    long calls=0,returned=0,zeros=0;
    long fatReads=0,otherReads=0;
    public D603ExternalSource(byte[] image,long stopAfter,int maxChunk) {
        if(image==null||stopAfter<0||maxChunk<1||maxChunk>512)
            throw new ArgumentException("Invalid artificial source");
        input=new MemoryStream(image,false);stop=stopAfter;chunk=maxChunk;
    }
    public long Calls {get{return calls;}}
    public long Returned {get{return returned;}}
    public long Unique {get{return seen.Count;}}
    public long EarlyZeros {get{return zeros;}}
    public long FatReads {get{return fatReads;}}
    public long UnexpectedReads {get{return otherReads;}}
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return input.Length;}}
    public override long Position {get{return input.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long offset,SeekOrigin origin){return input.Seek(offset,origin);}
    public override int Read(byte[] buffer,int offset,int count) {
        if(buffer==null||offset<0||count<0||offset>buffer.Length-count)
            throw new ArgumentException("Invalid Read");
        calls++;
        long at=input.Position;
        // A-generated standard volume has MBR 0, VBR 512, FSInfo 1024,
        // primary-declared backup 3584, shifted locator 4096.
        bool structSector=(at>=0&&at<1536)||(at>=3584&&at<4608);
        if(!structSector)otherReads++;
        if(at>=16896&&at<540000)fatReads++;
        if(returned>=stop) {
            if(at<input.Length)zeros++;
            return 0;
        }
        int n=input.Read(buffer,offset,(int)Math.Min((long)count,Math.Min((long)chunk,stop-returned)));
        if(n==0&&at<input.Length)zeros++;
        for(int i=0;i<n;i++)seen.Add(at+i);
        returned+=n;
        return n;
    }
    public override void Flush(){}
    public override void SetLength(long x){throw new NotSupportedException();}
    public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
    protected override void Dispose(bool disposing){if(disposing)input.Dispose();base.Dispose(disposing);}
}
'@
}
function Run-D603 {
    param([byte[]]$Data,[int]$Bytes=2048,[int]$Calls=256,
          [long]$Stop=[long]::MaxValue,[int]$Chunk=512,
          [switch]$Baseline)
    $source=[D603ExternalSource]::new($Data,$Stop,$Chunk)
    try{
        if($Baseline) {
            $report=Get-ChappyFatVbrDisagreement -Stream $source -MaxReadBytes $Bytes
        }else{
            $report=Get-ChappyFatGeometryHypothesisGate -Stream $source -MaxReadBytes $Bytes -MaxPhysicalReadCalls $Calls
        }
        return [pscustomobject]@{r=$report;actual=$source.Returned;unique=$source.Unique;
            calls=$source.Calls;early=$source.EarlyZeros;fatReads=$source.FatReads;
            unexpected=$source.UnexpectedReads}
    }finally{$source.Dispose()}
}
function Check-D603Boundary($Trial,[string]$Case,[int]$Limit){
    $r=$Trial.r
    Assert-D603 ($Trial.actual -eq $r.metrics.actualReturnedBytes -and
        $Trial.unique -eq $r.metrics.uniqueReturnedBytes -and
        $Trial.calls -eq $r.metrics.physicalReadCalls -and
        $r.metrics.repeatedReturnedBytes -eq ($Trial.actual-$Trial.unique) -and
        $Trial.actual -le $Limit -and $Trial.calls -le $r.metrics.maxPhysicalReadCalls) ($Case+' independent actual/unique/repeated bytes and calls')
    Assert-D603 ($r.sourceDecision -ceq 'not_selected' -and
        $null -eq $r.selectedCandidate -and -not $r.fatReadAllowed -and
        -not $r.writePermitted -and $r.originalIdentity -ceq 'unknown' -and
        $r.geometryAuthenticity -ceq 'unknown' -and
        $r.sourceReadProvenance -ceq 'internal_not_A_attested') ($Case+' no automatic FAT offset, original, winner or repair')
    Assert-D603 ($Trial.fatReads -eq 0 -and $Trial.unexpected -eq 0 -and
        $r.fatRegionProbeCount -eq 0 -and $r.metrics.fatRegionReads -eq 0) ($Case+' only structural boot-sector ranges physically read')
    Assert-D603 (@($r.hypotheses).Count -eq 2 -and
        $r.hypotheses[0].sourceRole -ceq 'primary' -and
        $r.hypotheses[1].sourceRole -ceq 'backup') ($Case+' primary/backup independent candidates retained')
}
# Each scenario explicitly specifies a synthetic mutation. The analyzer sees
# only the resulting nonwritable memory source and has no case/seed input.
$scenarios=@(
    [pscustomobject]@{id='clean_spc1';seed=202614;spc=1;fault='none';expect='candidate_geometry_unverified';truth=$false;stop=[long]::MaxValue;chunk=512;budget=2048;calls=256},
    [pscustomobject]@{id='clean_spc2';seed=202615;spc=2;fault='none';expect='candidate_geometry_unverified';truth=$false;stop=[long]::MaxValue;chunk=512;budget=2048;calls=256},
    [pscustomobject]@{id='backup_reserve33';seed=202614;spc=1;fault='reserve';expect='blocked_conflicting_geometry';truth=$true;stop=[long]::MaxValue;chunk=512;budget=2048;calls=256},
    [pscustomobject]@{id='backup_root3';seed=202614;spc=1;fault='root';expect='blocked_conflicting_geometry';truth=$true;stop=[long]::MaxValue;chunk=512;budget=2048;calls=256},
    [pscustomobject]@{id='backup_fat_plus1';seed=202614;spc=1;fault='fat';expect='blocked_conflicting_geometry';truth=$true;stop=[long]::MaxValue;chunk=512;budget=2048;calls=256},
    [pscustomobject]@{id='backup_fsinfo2';seed=202614;spc=1;fault='fsinfo';expect='blocked_conflicting_geometry';truth=$true;stop=[long]::MaxValue;chunk=512;budget=2048;calls=256},
    [pscustomobject]@{id='invalid_backup_sig';seed=202614;spc=1;fault='backup_sig';expect='blocked_contradicted_geometry';truth=$true;stop=[long]::MaxValue;chunk=512;budget=2048;calls=256},
    [pscustomobject]@{id='backup_locator7';seed=202614;spc=1;fault='locator';expect='blocked_contradicted_geometry';truth=$true;stop=[long]::MaxValue;chunk=512;budget=2048;calls=256},
    [pscustomobject]@{id='invalid_mbr_sig';seed=202614;spc=1;fault='mbr_sig';expect='blocked_contradicted_geometry';truth=$null;stop=[long]::MaxValue;chunk=512;budget=2048;calls=256},
    [pscustomobject]@{id='short_return_early_zero';seed=202614;spc=1;fault='none';expect='blocked_insufficient_evidence';truth=$null;stop=1100L;chunk=7;budget=2048;calls=256},
    [pscustomobject]@{id='mbr_primary_only';seed=202614;spc=1;fault='none';expect='blocked_insufficient_evidence';truth=$null;stop=[long]::MaxValue;chunk=512;budget=1024;calls=256},
    [pscustomobject]@{id='read_calls4_one_byte';seed=202614;spc=1;fault='none';expect='blocked_insufficient_evidence';truth=$null;stop=[long]::MaxValue;chunk=1;budget=2048;calls=4}
)
$scored=@{TP=0;FP=0;FN=0;TN=0};$unknown=0
$bytes=0L;$unique=0L;$callsTotal=0L
foreach($c in $scenarios){
    $fix=New-ChappyA3DStandardFixture -Seed $c.seed -SectorsPerCluster $c.spc
    [byte[]]$image=$fix.image
    $boot=3584
    switch($c.fault){
        'reserve' {U16-D603 $image ($boot+14) 33}
        'root' {U32-D603 $image ($boot+44) 3}
        'fat' {
            $old=[BitConverter]::ToUInt32($image,($boot+36))
            U32-D603 $image ($boot+36) ([uint32]($old+1))
        }
        'fsinfo' {U16-D603 $image ($boot+48) 2}
        'backup_sig' {$image[$boot+510]=0}
        'locator' {U16-D603 $image (512+50) 7}
        'mbr_sig' {$image[510]=0}
    }
    $before=Hash-D603 $image
    $measure=Run-D603 -Data $image -Bytes $c.budget -Calls $c.calls -Stop $c.stop -Chunk $c.chunk
    $r=$measure.r
    Check-D603Boundary $measure $c.id $c.budget
    Assert-D603 ($r.gateDecision -ceq $c.expect) ($c.id+' correct deny-only geometry classification')
    Assert-D603 ((Hash-D603 $image) -ceq $before) ($c.id+' artificial image SHA unchanged')
    if($c.id -eq 'backup_reserve33'){
        Assert-D603 ($r.agreement -ceq 'disagree' -and
            $r.hypotheses[0].plausibility -ceq 'plausible_unverified' -and
            $r.hypotheses[1].plausibility -ceq 'plausible_unverified' -and
            $r.hypotheses[0].numericGeometry.fat1OffsetBytes -ne
            $r.hypotheses[1].numericGeometry.fat1OffsetBytes) 'Both in-bounds plausible but incompatible FAT offsets refused without winner'
        Assert-D603 (-not $r.scanIncomplete -and $r.geometryUnresolved -and
            $measure.actual -eq 2048 -and $r.gateDecision -ceq 'blocked_conflicting_geometry') 'Complete physical BPB observation still logically contradictory, not a fabricated short read'
    }
    if($c.id -eq 'backup_root3'){
        Assert-D603 ($r.agreement -ceq 'disagree' -and
            $r.hypotheses[0].numericGeometry.rootCluster -ne
            $r.hypotheses[1].numericGeometry.rootCluster) 'Different plausible root cluster not silently promoted'
    }
    if($c.id -eq 'backup_fsinfo2'){
        Assert-D603 ($r.hypotheses[1].plausibility -ceq 'insufficient_evidence' -and
            $r.hypotheses[1].unknownCodes -contains 'fsinfo.for_candidate_not_observed') 'FSInfo at primary location not borrowed for backup locator'
    }
    if($c.id -eq 'backup_locator7'){
        Assert-D603 ($r.hypotheses[1].probeOffsetBytes -eq 4096 -and
            $r.hypotheses[1].plausibility -ceq 'contradicted') 'Primary-declared backup locator only; no FAT fallback search'
    }
    if($c.id -eq 'short_return_early_zero'){
        Assert-D603 ($measure.actual -eq 1100 -and $measure.early -gt 0 -and
            $r.metrics.prematureSourceZeroReads -gt 0 -and
            $r.scanIncomplete) 'Physical early zero after 1100B retained UNKNOWN'
    }
    if($c.id -eq 'read_calls4_one_byte'){
        Assert-D603 ($r.metrics.refusedReadCalls -ge 1 -and
            $r.metrics.physicalReadCalls -eq 4 -and
            $measure.calls -eq 4) 'Physical Read-call cap refuses one-byte amplification'
        Assert-D603 ($r.hypotheses[0].plausibility -ceq 'insufficient_evidence' -and
            $r.hypotheses[1].plausibility -ceq 'insufficient_evidence' -and
            $null -eq $r.hypotheses[0].numericGeometry.fat1OffsetBytes -and
            $null -eq $r.hypotheses[1].numericGeometry.fat1OffsetBytes) 'Call-cap failure returns two explicitly UNKNOWN BPB roles, no guessed FAT offsets'
    }
    if($c.id -eq 'clean_spc1' -or $c.id -eq 'backup_reserve33') {
        $base=Run-D603 -Data $image -Bytes 2048 -Baseline
        Assert-D603 ($base.r.agreement -ceq $r.agreement -and
            $base.actual -eq $measure.actual -and
            $base.calls -eq $measure.calls -and $base.unique -eq $measure.unique) ($c.id+' frozen D5 baseline same source, bytes, calls and agreement')
    }
    if($null -eq $c.truth){$unknown++}
    else{
        $detected=($r.gateDecision -ceq 'blocked_conflicting_geometry' -or
                   $r.gateDecision -ceq 'blocked_contradicted_geometry')
        if($c.truth){if($detected){$scored.TP++}else{$scored.FN++}}
        else{if($detected){$scored.FP++}else{$scored.TN++}}
    }
    $bytes+=$measure.actual;$unique+=$measure.unique;$callsTotal+=$measure.calls
    Write-Host ('D6-03 case={0} gate={1} BPB={2} physical actual/unique={3}/{4} calls={5} FATreads={6} owner=UNKNOWN' -f
        $c.id,$r.gateDecision,$r.agreement,$measure.actual,$measure.unique,$measure.calls,$measure.fatReads)
    $fix=$null;$image=$null
    [GC]::Collect()
}
Assert-D603 ($scored.TP -eq 6 -and $scored.FP -eq 0 -and
    $scored.FN -eq 0 -and $scored.TN -eq 2 -and $unknown -eq 4) 'External scorer BPB contradictory cases TP6 FP0 FN0 TN2 UNKNOWN4, no file recovery labels'
$fake=[byte[]]::new(8192)
$w=[IO.MemoryStream]::new($fake,$true)
try{
    Assert-D603 (Throws-D603 {Get-ChappyFatGeometryHypothesisGate -Stream $w}) 'Writable caller Stream rejected before any read'
}finally{$w.Dispose()}
$ro=[IO.MemoryStream]::new($fake,$false)
try{
    Assert-D603 (Throws-D603 {Get-ChappyFatGeometryHypothesisGate -Stream $ro -MaxReadBytes 2049}) 'Global byte cap <=2048'
    Assert-D603 (Throws-D603 {Get-ChappyFatGeometryHypothesisGate -Stream $ro -MaxPhysicalReadCalls 257}) 'Global physical calls cap <=256'
    Assert-D603 (Throws-D603 {Get-ChappyFatGeometryHypothesisGate -Stream $ro -PartitionIndex 4}) 'MBR partition slot index bounded'
}finally{$ro.Dispose()}
Write-Host ('D6-03 synthetic scorer unit=unsafe BPB hypothesis conflict TP/FP/FN/TN {0}/{1}/{2}/{3} UNKNOWN={4}' -f
    $scored.TP,$scored.FP,$scored.FN,$scored.TN,$unknown)
Write-Host ('D6-03 source-local actual bytes={0}, unique sum={1}, repeated={2}, physical Read calls={3}, FAT region reads=0' -f
    $bytes,$unique,($bytes-$unique),$callsTotal)
Write-Host ('D6-03 guarded geometry source gate: {0} PASS / {1} FAIL' -f $script:Pass,$script:Fail)
if($script:Fail -gt 0){exit 1}
