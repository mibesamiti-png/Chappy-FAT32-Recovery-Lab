#Requires -Version 5.1
# Team D Issue #73 R6-P5: test-only source-identity negative study.
# Real disks/images are never used. Oracle identities do not enter Team D.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32ObservedIoEvidence.psm1') -Force
$script:ok=0;$script:bad=0
function Check-D16 {
    param([bool]$Good,[string]$Label)
    if($Good){$script:ok++;Write-Host ('PASS '+$Label)}
    else{$script:bad++;Write-Host ('FAIL '+$Label)}
}
function Hash-D16 {
    param([byte[]]$Data)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($Data)).Replace('-','')}
    finally{$sha.Dispose()}
}
# Test-only source: the image stays in memory, is seekable and NOT writable.
# A chunk limit or premature physical zero read simulates faulty I/O.
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class D16SyntheticFaultSource : Stream {
    private readonly MemoryStream mem;
    private readonly int maxChunk;
    private readonly long stopAfter;
    private long readBytes=0;
    private long calls=0;
    public D16SyntheticFaultSource(byte[] bytes,int chunk,long cutoff){
        mem=new MemoryStream(bytes,false); maxChunk=chunk; stopAfter=cutoff;
    }
    public long ActualBytes {get{return readBytes;}}
    public long ReadCalls {get{return calls;}}
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return mem.Length;}}
    public override long Position {get{return mem.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long offset,SeekOrigin origin){return mem.Seek(offset,origin);}
    public override int Read(byte[] b,int off,int count){
        calls++;
        if(readBytes>=stopAfter)return 0;
        int n=mem.Read(b,off,(int)Math.Min((long)count,Math.Min((long)maxChunk,stopAfter-readBytes)));
        readBytes+=n;return n;
    }
    public override void Flush(){}
    public override void Write(byte[] b,int off,int count){throw new NotSupportedException();}
    public override void SetLength(long n){throw new NotSupportedException();}
    protected override void Dispose(bool disposing){if(disposing)mem.Dispose();base.Dispose(disposing);}
}
'@
$images=@{}
foreach($name in @('M00','M02','M03','M03independent')){
    $fixtureCase=$(if($name -eq 'M03independent'){'M03'}else{$name})
    $f=New-ChappyA3DDamagedFixture -Case $fixtureCase -Seed 202611
    $hash=Hash-D16 $f.image
    Check-D16 ($hash -ceq $f.manifest.imageSha256) ('Artificial scorer SHA correct '+$name)
    $images[$name]=[pscustomobject]@{
        raw=[byte[]]$f.image;digest=$hash;sourceKey=('external_synthetic_'+$name)
    }
}
Check-D16 ($images['M03'].digest -ceq $images['M03independent'].digest) 'Separate generated M03 sources are byte-identical yet source-distinct'
Check-D16 ($images['M00'].digest -cne $images['M02'].digest) 'M00 and M02 have different content despite overlapping FAT offsets'

function Get-D16SourceScopedUnion {
    param($A,$B,[string]$TrustedKeyA,[string]$TrustedKeyB,[bool]$VerifiedA,[bool]$VerifiedB)
    if(-not $VerifiedA -or -not $VerifiedB -or
        [string]::IsNullOrWhiteSpace($TrustedKeyA) -or
        [string]::IsNullOrWhiteSpace($TrustedKeyB)){
        return [pscustomobject]@{
            relation='unknown';sourceScopedUniqueBytes=$null;sourceScopedDuplicateBytes=$null
            originalIdentity='unknown';fatWinner='not_selected';writePermitted=$false
        }
    }
    $unique=New-Object 'System.Collections.Generic.HashSet[string]'
    $actual=0L
    foreach($item in @(
        [pscustomobject]@{report=$A;key=$TrustedKeyA},
        [pscustomobject]@{report=$B;key=$TrustedKeyB}
    )){
        foreach($event in @($item.report.readEvents)){
            $start=[long]$event.offsetBytes;$n=[long]$event.returnedBytes
            $actual+=$n
            for($i=0L;$i -lt $n;$i++){
                [void]$unique.Add(($item.key+':'+($start+$i)))
            }
        }
    }
    return [pscustomobject]@{
        relation=$(if($TrustedKeyA -ceq $TrustedKeyB){'same_source'}else{'different_source'})
        sourceScopedUniqueBytes=[long]$unique.Count
        sourceScopedDuplicateBytes=[long]($actual-$unique.Count)
        originalIdentity='unknown';fatWinner='not_selected';writePermitted=$false
    }
}
function Has-D16NaiveOverlap {
    param($A,$B)
    $seen=New-Object 'System.Collections.Generic.HashSet[long]'
    foreach($e in @($A.readEvents)){
        for($i=0L;$i -lt [long]$e.returnedBytes;$i++){
            [void]$seen.Add(([long]$e.offsetBytes+$i))
        }
    }
    foreach($e in @($B.readEvents)){
        for($i=0L;$i -lt [long]$e.returnedBytes;$i++){
            if($seen.Contains(([long]$e.offsetBytes+$i))){return $true}
        }
    }
    return $false
}
# Scorer owns the identity labels, never provided to D analyzer.
# Nine pairs: four SAME, three DIFFERENT and two UNKNOWN/missing attestations.
$pairs=@(
 [pscustomobject]@{id='same_wrapped_clean';a='M00';b='M00';mode='MirrorOnly';cap=2048;cut=[long]::MaxValue;chunk=4096;attA=$true;attB=$true},
 [pscustomobject]@{id='different_similar_geometry';a='M00';b='M02';mode='MirrorAndChain';cap=2048;cut=[long]::MaxValue;chunk=4096;attA=$true;attB=$true},
 [pscustomobject]@{id='same_mirror_disagreement';a='M02';b='M02';mode='MirrorAndChain';cap=2048;cut=[long]::MaxValue;chunk=4096;attA=$true;attB=$true},
 [pscustomobject]@{id='different_identical_image_bytes';a='M03';b='M03independent';mode='MirrorAndChain';cap=2048;cut=[long]::MaxValue;chunk=4096;attA=$true;attB=$true},
 [pscustomobject]@{id='different_corrupt_fat';a='M02';b='M03';mode='MirrorAndChain';cap=2048;cut=[long]::MaxValue;chunk=4096;attA=$true;attB=$true},
 [pscustomobject]@{id='same_partial_source_read';a='M03';b='M03';mode='MirrorAndChain';cap=2048;cut=1150L;chunk=7;attA=$true;attB=$true},
 [pscustomobject]@{id='same_tight_global_budget';a='M03';b='M03';mode='MirrorAndChain';cap=32;cut=[long]::MaxValue;chunk=4096;attA=$true;attB=$true},
 [pscustomobject]@{id='unknown_no_outer_id';a='M00';b='M02';mode='MirrorAndChain';cap=2048;cut=[long]::MaxValue;chunk=4096;attA=$true;attB=$false},
 [pscustomobject]@{id='unknown_forged_equal_id';a='M03';b='M03independent';mode='MirrorAndChain';cap=2048;cut=[long]::MaxValue;chunk=4096;attA=$false;attB=$false}
)
$baseTP=0;$baseFP=0;$baseFN=0;$baseTN=0
$guardTP=0;$guardFP=0;$guardFN=0;$guardTN=0
$unknown=0;$physicalTotal=0L;$localUniqueTotal=0L;$callsTotal=0L
foreach($p in $pairs){
    $a=$images[$p.a];$b=$images[$p.b]
    $beforeA=Hash-D16 $a.raw;$beforeB=Hash-D16 $b.raw
    $sourceA=[D16SyntheticFaultSource]::new($a.raw,4096,[long]::MaxValue)
    $sourceB=[D16SyntheticFaultSource]::new($b.raw,[int]$p.chunk,[long]$p.cut)
    try{
        $reportA=Get-ChappyFatObservedIoEvidence -Stream $sourceA -Mode $p.mode -MaxReadBytes 2048
        $reportB=Get-ChappyFatObservedIoEvidence -Stream $sourceB -Mode $p.mode -MaxReadBytes $p.cap
        $naive=Has-D16NaiveOverlap $reportA $reportB
        $joined=Get-D16SourceScopedUnion $reportA $reportB $a.sourceKey $b.sourceKey $p.attA $p.attB
        $truth=$(if(-not $p.attA -or -not $p.attB){'unknown'}
            elseif($a.sourceKey -ceq $b.sourceKey){'same_source'}else{'different_source'})
        Check-D16 $naive ($p.id+' overlapping numeric FAT offsets observed; not authentic identity')
        Check-D16 ($joined.relation -eq $truth -and
            $joined.originalIdentity -eq 'unknown' -and $joined.fatWinner -eq 'not_selected' -and
            -not $joined.writePermitted) ($p.id+' source identity only from external attestation; no file claim')
        if($truth -eq 'unknown'){
            $unknown++
            Check-D16 ($null -eq $joined.sourceScopedUniqueBytes -and
                $null -eq $joined.sourceScopedDuplicateBytes) ($p.id+' unattested source cannot be physically joined')
        }else{
            # Cross-source union under true *scorer* identities, independently
            # recomputed from each observed interval, never from module claims.
            $expectedCount=Get-D16SourceScopedUnion $reportA $reportB $a.sourceKey $b.sourceKey $true $true
            Check-D16 ($joined.sourceScopedUniqueBytes -eq $expectedCount.sourceScopedUniqueBytes) ($p.id+' source-scoped physical byte accounting')
            $positive=($truth -eq 'same_source')
            $guardPositive=($joined.relation -eq 'same_source')
            if($positive){
                if($naive){$baseTP++}else{$baseFN++}
                if($guardPositive){$guardTP++}else{$guardFN++}
            }else{
                if($naive){$baseFP++}else{$baseTN++}
                if($guardPositive){$guardFP++}else{$guardTN++}
            }
            if($truth -eq 'different_source'){
                Check-D16 ($joined.sourceScopedUniqueBytes -eq
                    ([long]$reportA.metrics.uniquePhysicalBytes+[long]$reportB.metrics.uniquePhysicalBytes)) ($p.id+' independent images never share physical byte union')
            }
        }
        foreach($entry in @(
            [pscustomobject]@{report=$reportA;meter=$sourceA;cap=2048},
            [pscustomobject]@{report=$reportB;meter=$sourceB;cap=[int]$p.cap}
        )){
            $rep=$entry.report;$meter=$entry.meter
            $sum=0L;foreach($e in @($rep.readEvents)){$sum+=[long]$e.returnedBytes}
            Check-D16 ($sum -eq $meter.ActualBytes -and $sum -eq [long]$rep.metrics.bytesRead -and
                $sum -le $entry.cap -and $rep.metrics.uniquePhysicalBytes -le $sum) ($p.id+' actual source bytes and budget are independently accounted')
            Check-D16 ($rep.metrics.readRequests -ge $meter.ReadCalls -and
                $rep.metrics.totalReadCapShared -and $rep.status -eq 'partial') ($p.id+' no full-FAT coverage from bounded source reads')
            Check-D16 ($rep.geometryTrustDecision -eq 'reject' -and
                $rep.sourceDecision -eq 'not_selected' -and $null -eq $rep.selectedCandidate -and
                -not $rep.writePermitted -and
                $null -eq $rep.PSObject.Properties['sourceIdentity']) ($p.id+' no invented source/FAT winner or ownership')
        }
        if($p.id -eq 'different_identical_image_bytes'){
            Check-D16 ($beforeA -ceq $beforeB -and $joined.relation -eq 'different_source') 'Byte-identical independent synthetic images still have distinct external sources'
        }
        if($p.id -eq 'same_partial_source_read'){
            Check-D16 ($sourceB.ActualBytes -eq 1150 -and
                $reportB.metrics.prematureSourceZeroReads -gt 0 -and
                $reportB.scanIncomplete -and $reportB.status -eq 'partial') 'Premature partial read preserves uncertainty even with same source token'
        }
        if($p.id -eq 'same_tight_global_budget'){
            Check-D16 ($sourceB.ActualBytes -le 32 -and $reportB.metrics.globalBudgetClipped -and
                $reportB.scanIncomplete) 'Global 32-byte limit does not assert evidence completeness'
        }
        $physicalTotal+=[long]$sourceA.ActualBytes+[long]$sourceB.ActualBytes
        $localUniqueTotal+=[long]$reportA.metrics.uniquePhysicalBytes+[long]$reportB.metrics.uniquePhysicalBytes
        $callsTotal+=[long]$sourceA.ReadCalls+[long]$sourceB.ReadCalls
        Check-D16 ((Hash-D16 $a.raw) -ceq $beforeA -and (Hash-D16 $b.raw) -ceq $beforeB) ($p.id+' no synthetic source modification')
        Write-Host ('D P5 {0} truth={1} naiveOverlap={2} resolved={3} actual={4}+{5} unique={6}+{7} calls={8}+{9}' -f
            $p.id,$truth,$naive,$joined.relation,$reportA.metrics.bytesRead,$reportB.metrics.bytesRead,
            $reportA.metrics.uniquePhysicalBytes,$reportB.metrics.uniquePhysicalBytes,
            $sourceA.ReadCalls,$sourceB.ReadCalls)
    }finally{$sourceA.Dispose();$sourceB.Dispose()}
}
Check-D16 ($baseTP -eq 4 -and $baseFP -eq 3 -and $baseFN -eq 0 -and $baseTN -eq 0) 'Offset-only naive baseline falsely joins three distinct synthetic sources'
Check-D16 ($guardTP -eq 4 -and $guardFP -eq 0 -and $guardFN -eq 0 -and $guardTN -eq 3) 'Attested outer source-scoped union does not conflate different streams'
Check-D16 ($unknown -eq 2) 'Two missing/untrusted source identities excluded from binary source-identity scores'
Check-D16 ($localUniqueTotal -le $physicalTotal -and $callsTotal -gt 18) 'Aggregate physical read and local unique totals bounded'
Write-Host ('D P5 source-ID-only A/B naive TP/FP/FN/TN={0}/{1}/{2}/{3}; guarded={4}/{5}/{6}/{7}; unknown={8}' -f
    $baseTP,$baseFP,$baseFN,$baseTN,$guardTP,$guardFP,$guardFN,$guardTN,$unknown)
Write-Host ('D P5 physical per-observation bytes={0}, sum source-local unique={1}, source Read() calls={2}' -f
    $physicalTotal,$localUniqueTotal,$callsTotal)
Write-Host ('Team D R6 P5 synthetic source identity: {0} passed, {1} failed' -f $script:ok,$script:bad)
if($script:bad -gt 0){exit 1}
