#Requires -Version 5.1
# Team D gate D6-02. All byte arrays are generated artificial fixtures.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32SharedChainEvidence.psm1') -Force
$script:Pass=0;$script:Fail=0
function Assert-D26([bool]$Yes,[string]$Label) {
    if($Yes){$script:Pass++;Write-Host ('PASS '+$Label)}
    else{$script:Fail++;Write-Host ('FAIL '+$Label)}
}
function Throws-D26([scriptblock]$Code) {
    try{$null=& $Code;return $false}catch{return $true}
}
function Hash-D26([byte[]]$Data) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($Data)).Replace('-','')}
    finally{$sha.Dispose()}
}
function Set-D26Entry([byte[]]$Data,[long]$Offset,[uint32]$Value) {
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$Data,[int]$Offset,4)
}
# Independent physical source-return meter; nothing is written to disk.
if(-not ('D26ExternalSource' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D26ExternalSource : Stream {
    readonly MemoryStream m;
    readonly HashSet<long> unique=new HashSet<long>();
    readonly long limit,stop;
    readonly int chunk,maxCalls;
    long actual=0,calls=0,early=0,denied=0;
    public D26ExternalSource(byte[] data,long cap,long stopAfter,int chunkSize,int callsCap) {
        if(data==null||cap<16||cap>1024||stopAfter<0||chunkSize<1||chunkSize>1024||callsCap<1||callsCap>256)
            throw new ArgumentException("Invalid generated source limits");
        m=new MemoryStream(data,false);
        limit=cap;stop=stopAfter;chunk=chunkSize;maxCalls=callsCap;
    }
    public long Actual {get{return actual;}}
    public long Unique {get{return unique.Count;}}
    public long Calls {get{return calls;}}
    public long Early {get{return early;}}
    public long Denied {get{return denied;}}
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return m.Length;}}
    public override long Position {get{return m.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long x,SeekOrigin origin){return m.Seek(x,origin);}
    public override int Read(byte[] b,int off,int count) {
        if(b==null||off<0||count<0||off>b.Length-count)throw new ArgumentException("Invalid Read");
        if(calls>=maxCalls||count>limit-actual){denied++;throw new IOException("D26.outer_cap");}
        calls++;
        if(count==0)return 0;
        long at=m.Position;
        if(actual>=stop){if(at<m.Length)early++;return 0;}
        int n=m.Read(b,off,(int)Math.Min((long)count,Math.Min((long)chunk,stop-actual)));
        if(n==0&&at<m.Length)early++;
        for(int i=0;i<n;i++)unique.Add(at+i);
        actual+=n;return n;
    }
    public override void Flush(){}
    public override void SetLength(long x){throw new NotSupportedException();}
    public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
    protected override void Dispose(bool disposing){if(disposing)m.Dispose();base.Dispose(disposing);}
}
'@
}
function Observe-D26 {
    param([byte[]]$Image,[long]$Fat1,[long]$Fat2,[long]$FatLength,[long]$MaxCluster,
          [int]$Cap=256,[int]$Steps=8,[int]$Calls=128,
          [long]$Stop=[long]::MaxValue,[int]$Chunk=1024)
    $src=[D26ExternalSource]::new($Image,[long]$Cap,$Stop,$Chunk,$Calls)
    try{
        $args=@{Stream=$src;Fat1OffsetBytes=$Fat1;Fat2OffsetBytes=$Fat2;
            FatLengthBytes=$FatLength;MaxDataCluster=$MaxCluster;
            StartClusters=([long[]]@(4,8));MaxReadBytes=$Cap;
            MaxStepsPerChain=$Steps;MaxReadCalls=$Calls}
        $r=Get-ChappyFatSharedChainEvidence @args
        return [pscustomobject]@{r=$r;actual=$src.Actual;unique=$src.Unique;
            calls=$src.Calls;early=$src.Early;denied=$src.Denied}
    }finally{$src.Dispose()}
}
function Check-D26Bound($trial,[string]$case,[int]$cap) {
    $r=$trial.r
    Assert-D26 ($trial.actual -eq $r.metrics.actualReturnedBytes -and
        $trial.unique -eq $r.metrics.uniqueReturnedBytes -and
        $trial.calls -eq $r.metrics.physicalReadCalls -and
        $r.metrics.repeatedReturnedBytes -eq ($trial.actual-$trial.unique) -and
        $trial.actual -le $cap -and $trial.calls -le 256 -and $trial.denied -eq 0) ($case+' independent physical returned/unique/call accounting')
    Assert-D26 ($r.team -ceq 'D' -and $r.schemaVersion -ceq '1' -and
        $r.fileOwner -ceq 'unknown' -and $r.originalIdentity -ceq 'unknown' -and
        $r.fatCopyWinner -ceq 'not_selected' -and -not $r.writePermitted -and
        $r.scanIncomplete -and
        $r.sourceObservationProvenance -ceq 'internal_read_not_A_attested') ($case+' no owner, source receipt, repair or FAT winner claim')
}
# Known M00/M01/M02/M03/M05/X02 labels stay in external scorer only.
$fixtureCases=@(
    [pscustomobject]@{id='M00';expected=0;score=$false},
    [pscustomobject]@{id='M01';expected=0;score=$false},
    [pscustomobject]@{id='M02';expected=0;score=$false},
    [pscustomobject]@{id='M03';expected=0;score=$false},
    [pscustomobject]@{id='M05';expected=2;score=$true},
    [pscustomobject]@{id='X02';expected=0;score=$null}
)
$tp=0;$fp=0;$fn=0;$tn=0;$unknown=0
$totalActual=0L;$totalUnique=0L;$totalCalls=0L
foreach($c in $fixtureCases){
    $f=New-ChappyA3DDamagedFixture -Case $c.id -Seed 202611
    [byte[]]$data=$f.image
    $before=Hash-D26 $data
    Assert-D26 ($before -ceq $f.manifest.imageSha256) ($c.id+' external synthetic scorer SHA agrees')
    $x=Observe-D26 -Image $data -Fat1 16896L -Fat2 37376L -FatLength 20480L -MaxCluster 3990L
    $r=$x.r
    Check-D26Bound $x $c.id 256
    Assert-D26 ((Hash-D26 $data) -ceq $before) ($c.id+' generated source unchanged')
    Assert-D26 ($r.sharedObservedInCopies -eq $c.expected -and
        $r.copies.Count -eq 2 -and $r.items.Count -eq 4) ($c.id+' 2 FAT copies and 2 hint chains, numeric shared detection')
    Assert-D26 ($r.warnings -contains 'fat.shared_cluster_not_file_ownership' -and
        $r.warnings -contains 'coverage.sampled_chains_not_whole_fat') ($c.id+' samples and owners not certified')
    if($c.id -eq 'M05'){
        Assert-D26 ($r.copies[0].sharedObservedClusterCount -ge 1 -and
            $r.copies[1].sharedObservedClusterCount -ge 1 -and
            $r.metrics.repeatedReturnedBytes -gt 0) 'M05 both FATs physically share cluster 8 yet owner remains unknown'
    }
    if($c.id -eq 'M02'){
        Assert-D26 (@($r.items|Where-Object {$_.fatCopyIndex -eq 0 -and
            $_.startCluster -eq 4 -and $_.terminal -eq 'free'}).Count -eq 1 -and
            @($r.items|Where-Object {$_.fatCopyIndex -eq 1 -and
            $_.startCluster -eq 4 -and $_.terminal -eq 'eoc'}).Count -eq 1) 'M02 lost FAT1 link observed, no FAT2 winner'
    }
    if($c.id -eq 'M03'){
        Assert-D26 (@($r.items|Where-Object {$_.terminal -eq 'cycle'}).Count -eq 2) 'M03 identical two-copy cycle observed'
    }
    if($c.id -eq 'X02'){
        Assert-D26 ($r.scanIncomplete -and $r.geometryProvenance -ceq 'caller_supplied_unverified') 'X02 payload beyond FAT window not authenticated'
    }
    if($null -eq $c.score){$unknown++}
    elseif($c.score){if($r.sharedObservedInCopies -gt 0){$tp++}else{$fn++}}
    else{if($r.sharedObservedInCopies -gt 0){$fp++}else{$tn++}}
    $totalActual+=$x.actual;$totalUnique+=$x.unique;$totalCalls+=$x.calls
    Write-Host ('D6-02 R2 case={0} sharedCopies={1} physical actual/unique={2}/{3} calls={4} original=UNKNOWN' -f
        $c.id,$r.sharedObservedInCopies,$x.actual,$x.unique,$x.calls)
}
Assert-D26 ($tp -eq 1 -and $fp -eq 0 -and $fn -eq 0 -and $tn -eq 4 -and
    $unknown -eq 1) 'Scored unit shared-numeric-FAT-node TP1 FP0 FN0 TN4, X02 UNKNOWN: not original files'
# Tiny independent generated controls, no outside images or names.
function New-D26Tiny {
    [byte[]]$data=[byte[]]::new(8192)
    foreach($fat in @(512,4096)){
        Set-D26Entry $data ($fat+16) ([uint32]6)
        Set-D26Entry $data ($fat+24) ([uint32]0x0FFFFFFF)
        Set-D26Entry $data ($fat+32) ([uint32]9)
        Set-D26Entry $data ($fat+36) ([uint32]0x0FFFFFFF)
    }
    return ,$data
}
[byte[]]$small=New-D26Tiny
$smallSha=Hash-D26 $small
$base=Observe-D26 -Image $small -Fat1 512 -Fat2 4096 -FatLength 1024 -MaxCluster 100
Check-D26Bound $base 'tiny healthy independent chains' 256
Assert-D26 ($base.r.sharedObservedInCopies -eq 0 -and
    @($base.r.items|Where-Object {$_.terminal -eq 'eoc'}).Count -eq 4) 'Healthy separate chains: no invented sharing'
$one=[byte[]]$small.Clone()
Set-D26Entry $one (4096+32) ([uint32]6)
$oneR=Observe-D26 -Image $one -Fat1 512 -Fat2 4096 -FatLength 1024 -MaxCluster 100
Check-D26Bound $oneR 'FAT2 only convergence' 256
Assert-D26 ($oneR.r.sharedObservedInCopies -eq 1 -and
    $oneR.r.copies[0].sharedObservedClusterCount -eq 0 -and
    $oneR.r.copies[1].sharedObservedClusterCount -eq 1) 'One-copy convergence is not an authentic FAT winner'
$free=[byte[]]$small.Clone()
foreach($fat in @(512,4096)){Set-D26Entry $free ($fat+16) ([uint32]0)}
$freeR=Observe-D26 -Image $free -Fat1 512 -Fat2 4096 -FatLength 1024 -MaxCluster 100
Assert-D26 (@($freeR.r.items|Where-Object {$_.terminal -eq 'free'}).Count -eq 2 -and
    $freeR.r.sharedObservedInCopies -eq 0) 'Free/missing links are distinct from shared or healthy'
$reserved=[byte[]]$small.Clone()
foreach($fat in @(512,4096)){Set-D26Entry $reserved ($fat+16) ([uint32]1)}
$reservedR=Observe-D26 -Image $reserved -Fat1 512 -Fat2 4096 -FatLength 1024 -MaxCluster 100
Assert-D26 (@($reservedR.r.items|Where-Object {$_.terminal -eq 'reserved'}).Count -eq 2) 'Reserved link detected without continuing walk'
$far=[byte[]]$small.Clone()
foreach($fat in @(512,4096)){Set-D26Entry $far ($fat+16) ([uint32]150)}
$farR=Observe-D26 -Image $far -Fat1 512 -Fat2 4096 -FatLength 1024 -MaxCluster 100
Assert-D26 (@($farR.r.items|Where-Object {$_.terminal -eq 'out_of_range'}).Count -eq 2 -and
    $farR.r.sharedObservedInCopies -eq 0) 'Out-of-data-range FAT links never followed'
$cycle=[byte[]]$small.Clone()
foreach($fat in @(512,4096)){Set-D26Entry $cycle ($fat+24) ([uint32]4)}
$cycleR=Observe-D26 -Image $cycle -Fat1 512 -Fat2 4096 -FatLength 1024 -MaxCluster 100
Assert-D26 (@($cycleR.r.items|Where-Object {$_.terminal -eq 'cycle'}).Count -eq 2) 'Two-copy bounded cycle is not a shared-cluster owner claim'
$short=Observe-D26 -Image $small -Fat1 512 -Fat2 4096 -FatLength 1024 -MaxCluster 100 -Stop 7L -Chunk 2
Check-D26Bound $short '7-byte early zero' 256
Assert-D26 ($short.r.tracesIncomplete -and $short.r.status -eq 'partial' -and
    $short.actual -eq 7 -and $short.early -gt 0 -and
    $short.r.metrics.prematureZeroBeforeStreamEnd -gt 0) 'Short returned 4-byte entry and premature zero stay incomplete'
$bounded=Observe-D26 -Image $small -Fat1 512 -Fat2 4096 -FatLength 1024 -MaxCluster 100 -Cap 16
Assert-D26 ($bounded.r.tracesIncomplete -and $bounded.actual -le 16 -and
    @($bounded.r.items|Where-Object {$_.terminal -eq 'byte_cap'}).Count -gt 0) 'Equal FAT quotas limit returned source bytes'
$stepped=Observe-D26 -Image $small -Fat1 512 -Fat2 4096 -FatLength 1024 -MaxCluster 100 -Steps 1
Assert-D26 ($stepped.r.tracesIncomplete -and
    @($stepped.r.items|Where-Object {$_.terminal -eq 'step_cap'}).Count -gt 0) 'Finite chain step bound'
$callLimited=Observe-D26 -Image $small -Fat1 512 -Fat2 4096 -FatLength 1024 -MaxCluster 100 -Calls 4 -Chunk 1
Assert-D26 ($callLimited.r.tracesIncomplete -and $callLimited.calls -le 4 -and
    @($callLimited.r.items|Where-Object {$_.terminal -eq 'read_call_cap'}).Count -gt 0) 'Physical call cap handles one-byte short returns'
Assert-D26 ((Hash-D26 $small) -ceq $smallSha) 'Tiny artificial fixture unchanged'
$writable=[IO.MemoryStream]::new($small,$true)
try{
    $a=@{Stream=$writable;Fat1OffsetBytes=512L;Fat2OffsetBytes=4096L;
        FatLengthBytes=1024L;MaxDataCluster=100L;StartClusters=([long[]]@(4,8))}
    Assert-D26 (Throws-D26 {Get-ChappyFatSharedChainEvidence @a}) 'Writable source rejected'
}finally{$writable.Dispose()}
$ro=[IO.MemoryStream]::new($small,$false)
try{
    $a=@{Stream=$ro;Fat1OffsetBytes=512L;Fat2OffsetBytes=4096L;
        FatLengthBytes=1024L;MaxDataCluster=100L;StartClusters=([long[]]@(4,8))}
    $v=$a.Clone();$v.StartClusters=[long[]]@(4,4)
    Assert-D26 (Throws-D26 {Get-ChappyFatSharedChainEvidence @v}) 'Duplicate chain-start hints rejected'
    $v=$a.Clone();$v.Fat2OffsetBytes=1024L
    Assert-D26 (Throws-D26 {Get-ChappyFatSharedChainEvidence @v}) 'Overlapping FAT copies rejected'
    $v=$a.Clone();$v.Fat2OffsetBytes=[long]::MaxValue-3
    Assert-D26 (Throws-D26 {Get-ChappyFatSharedChainEvidence @v}) 'Overflowing FAT geometry rejected'
    $v=$a.Clone();$v.FatLengthBytes=4096L
    Assert-D26 (Throws-D26 {Get-ChappyFatSharedChainEvidence @v}) 'Invalid FAT extents rejected'
    $v=$a.Clone();$v.MaxReadBytes=1025
    Assert-D26 (Throws-D26 {Get-ChappyFatSharedChainEvidence @v}) 'Max returned-byte budget hard capped'
}finally{$ro.Dispose()}
# Standards-shaped 32.5MiB generated FAT32 control: one positive and
# one negative under exact same source cap, without passing the scorer's truth
# or mutation coordinates to the numeric observation module.
. (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
$standard=New-ChappyA3DStandardFixture -Seed 202614 -SectorsPerCluster 1
[byte[]]$stdClean=$standard.image
$stdOriginalSha=Hash-D26 $stdClean
$stdFatBytes=[long][Math]::Ceiling((4.0*(65541+2))/512.0)*512L
$stdF1=33L*512L
$stdF2=$stdF1+$stdFatBytes
$stdNoShare=Observe-D26 -Image $stdClean -Fat1 $stdF1 -Fat2 $stdF2 -FatLength $stdFatBytes -MaxCluster 65542L
Check-D26Bound $stdNoShare 'standards FAT32 clean' 256
Assert-D26 ($stdNoShare.r.sharedObservedInCopies -eq 0 -and
    $stdNoShare.r.status -ceq 'ok') 'Standards-sized 65541 data clusters clean case remains unshared and candidate-only'
[byte[]]$stdShared=[byte[]]$stdClean.Clone()
foreach($fat in @($stdF1,$stdF2)) {
    Set-D26Entry $stdShared ($fat+16L) ([uint32]8)
}
$stdMutatedSha=Hash-D26 $stdShared
$stdWitness=Observe-D26 -Image $stdShared -Fat1 $stdF1 -Fat2 $stdF2 -FatLength $stdFatBytes -MaxCluster 65542L
Check-D26Bound $stdWitness 'standards FAT32 shared-node' 256
Assert-D26 ($stdWitness.r.sharedObservedInCopies -eq 2 -and
    $stdWitness.r.copies[0].sharedObservedClusterCount -eq 1 -and
    $stdWitness.r.copies[1].sharedObservedClusterCount -eq 1 -and
    $stdWitness.r.fileOwner -ceq 'unknown') 'Standards-shaped both FAT copies observe shared node, without real file owner inference'
Assert-D26 ((Hash-D26 $stdClean) -ceq $stdOriginalSha -and
    (Hash-D26 $stdShared) -ceq $stdMutatedSha) 'Both standard-size synthetic SHA values unchanged after read-only analysis'
Write-Host ('D6-02 standard FAT32 numeric witness: clean shared=0, synthetic link4-to8 sharedCopies={0}; actual/unique={1}/{2} bytes' -f
    $stdWitness.r.sharedObservedInCopies,$stdWitness.actual,$stdWitness.unique)
$standard=$null;$stdClean=$null;$stdShared=$null
[GC]::Collect()
$serialized=$oneR.r|ConvertTo-Json -Depth 8
Assert-D26 ($serialized -notmatch '(?i)originalFilename|sourcePath|repairTarget|recoveredPayload|fileSha256' -and
    $serialized -match 'fileOwner' -and $serialized -match 'unknown') 'Public-safe numeric result excludes payload, private name and original SHA'
Write-Host ('D6-02 scorer unit=observed_numeric_shared_node: TP/FP/FN/TN={0}/{1}/{2}/{3}, UNKNOWN={4}' -f $tp,$fp,$fn,$tn,$unknown)
Write-Host ('D6-02 R2 six artificial sources actual/unique returned={0}/{1} repeated={2} physical calls={3}' -f
    $totalActual,$totalUnique,($totalActual-$totalUnique),$totalCalls)
Write-Host ('Team D R6 D6-02 guarded shared-node: {0} passed; {1} failed.' -f $script:Pass,$script:Fail)
if($script:Fail -gt 0){exit 1}
