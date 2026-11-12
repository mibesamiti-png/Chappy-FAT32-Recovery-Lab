#Requires -Version 5.1
# Team D #73 P3. Scorer-only artificial manifest; analyzer never receives truth.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$repoRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $repoRoot 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32ObservedIoEvidence.psm1') -Force
$script:Pass=0;$script:Fail=0
function Check-D13 {
    param([bool]$Ok,[string]$Message)
    if($Ok){Write-Host "PASS $Message";$script:Pass++}
    else{Write-Host "FAIL $Message";$script:Fail++}
}
function Throws-D13 {
    param([scriptblock]$Code)
    try{$null=& $Code;return $false}catch{return $true}
}
function Hash-D13 {
    param([byte[]]$Data)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($Data)).Replace('-','')}
    finally{$sha.Dispose()}
}
function Run-D13 {
    param([byte[]]$Data,[string]$Mode='MirrorOnly',[int]$Cap=2048)
    $inputStream=[IO.MemoryStream]::new($Data,$false)
    try{
        return Get-ChappyFatObservedIoEvidence -Stream $inputStream -Mode $Mode -MaxReadBytes $Cap
    }finally{$inputStream.Dispose()}
}
function Check-D13Provenance {
    param($Report,[string]$Tag,[int]$Cap=2048)
    $sumEvents=0L
    $fatEvidence=0;$phaseGeometry=0;$phaseMirror=0;$phaseChain=0
    $lastId=-1
    foreach($ev in $Report.readEvents){
        $sumEvents+=[long]$ev.returnedBytes
        if($ev.returnedBytes -le 0 -or $ev.endExclusiveBytes -ne ($ev.offsetBytes+$ev.returnedBytes)){
            Check-D13 $false ($Tag+' read event exact bounds');break
        }
        $eventNum=[int]($ev.evidenceId.Substring(4))
        if($eventNum -ne ($lastId+1)){Check-D13 $false ($Tag+' sequential evidence IDs');break}
        $lastId=$eventNum
        if($ev.phase -eq 'geometry'){
            $phaseGeometry++
            Check-D13 ($null -eq $ev.fatCopyIndex) ($Tag+' geometry not mislabeled as FAT copy')
        }elseif($ev.phase -eq 'mirror_window_0'){
            $phaseMirror++
            if($null -ne $ev.fatCopyIndex){$fatEvidence++}
        }elseif($ev.phase -match '^chain_probe_[2-8]$'){
            $phaseChain++
            if($null -ne $ev.fatCopyIndex){$fatEvidence++}
        }else{Check-D13 $false ($Tag+' unexpected provenance phase')}
    }
    $uniqueBytes=0L;$prev=-1L
    foreach($range in $Report.uniqueReadRanges){
        $uniqueBytes+=[long]$range.lengthBytes
        if($range.lengthBytes -le 0 -or $range.offsetBytes -le $prev -or
            $range.endExclusiveBytes -ne ($range.offsetBytes+$range.lengthBytes)){
            Check-D13 $false ($Tag+' unique spans invalid or overlapping');break
        }
        $prev=$range.endExclusiveBytes - 1
    }
    $sumPhases=0L
    foreach($phase in $Report.phaseSummaries){$sumPhases+=[long]$phase.bytesRead}
    Check-D13 ($sumEvents -eq $Report.metrics.bytesRead -and $sumPhases -eq $sumEvents) ($Tag+' per-event and per-phase actual bytes reconcile')
    Check-D13 ($uniqueBytes -eq $Report.metrics.uniquePhysicalBytes -and
        $Report.metrics.duplicatePhysicalBytes -eq ($sumEvents-$uniqueBytes)) ($Tag+' exact numeric union, duplicate bytes count')
    Check-D13 ($sumEvents -le $Cap -and $Report.metrics.maximumGlobalReadBytes -eq $Cap -and
        $Report.metrics.totalReadCapShared) ($Tag+' shared global physical read cap')
    Check-D13 ($phaseGeometry -gt 0 -and $phaseMirror -gt 0 -and $fatEvidence -gt 0) ($Tag+' geometry and both FAT-copy stages trace to observed offsets')
    Check-D13 (($Report.experimentMode -eq 'MirrorAndChain' -and $phaseChain -gt 0) -or
        ($Report.experimentMode -eq 'MirrorOnly' -and $phaseChain -eq 0)) ($Tag+' optional chain provenance controlled by experiment mode')
}

# Normal read-only artificial fixture with 4B observed FAT entries.
$cases=@(
    [pscustomobject]@{id='M00';positive=$false},
    [pscustomobject]@{id='M01';positive=$false},
    [pscustomobject]@{id='M02';positive=$true},
    [pscustomobject]@{id='M03';positive=$true},
    [pscustomobject]@{id='X02';positive=$null}
)
$bTP=0;$bFP=0;$bFN=0;$bTN=0
$nTP=0;$nFP=0;$nFN=0;$nTN=0
$baselineBytes=0L;$newBytes=0L;$baselineUnique=0L;$newUnique=0L
$baselineRequests=0L;$newRequests=0L
foreach($case in $cases){
    $fixture=New-ChappyA3DDamagedFixture -Case $case.id -Seed 202611
    $before=Hash-D13 $fixture.image
    Check-D13 ($before -ceq $fixture.manifest.imageSha256) ($case.id+' external scorer fixture SHA valid')
    # The public D analyzer receives ONLY generated raw bytes and experiment mode.
    $old=Run-D13 $fixture.image 'MirrorOnly'
    $new=Run-D13 $fixture.image 'MirrorAndChain'
    Check-D13 ((Hash-D13 $fixture.image) -ceq $before) ($case.id+' synthetic source SHA unchanged')
    Check-D13 ($old.schemaVersion -eq '1' -and $new.schemaVersion -eq '1' -and
        $new.team -eq 'D' -and $new.experimentalDefaultOff) ($case.id+' result contract, opt-in only')
    Check-D13 ($old.sourceDecision -eq 'not_selected' -and $new.sourceDecision -eq 'not_selected' -and
        $null -eq $old.selectedCandidate -and $null -eq $new.selectedCandidate -and
        -not $old.writePermitted -and -not $new.writePermitted) ($case.id+' no FAT winner/repair')
    Check-D13 ($old.geometryTrustDecision -eq 'reject' -and
        $new.geometryTrustDecision -eq 'reject') ($case.id+' FAT32-like geometry never authenticated')
    Check-D13 ($new.phaseSummaries.Count -eq 9 -and $old.phaseSummaries.Count -eq 2) ($case.id+' exactly geometry, mirror, fixed chain probes')
    Check-D13 ($new.phaseSummaries[2].phase -eq 'chain_probe_2' -and
        $new.phaseSummaries[8].phase -eq 'chain_probe_8') ($case.id+' same non-oracle fixed chain starts')
    Check-D13 ($old.metrics.bytesRead -eq 2048 -and
        $new.metrics.bytesRead -le 2048 -and $new.metrics.bytesRead -ge 1536) ($case.id+' 2048 hard cap; no hidden extra source reads')
    Check-D13 ($new.metrics.uniquePhysicalBytes -le $new.metrics.bytesRead -and
        $new.metrics.readRequests -ge 2) ($case.id+' unique observations separate from requested reads')
    Check-D13Provenance $old ($case.id+' mirror')
    Check-D13Provenance $new ($case.id+' mirror+chain')
    $bHit=($old.evidence.mirrorDifferentEntries -gt 0)
    $nHit=($new.evidence.mirrorDifferentEntries -gt 0 -or $new.evidence.observedCycles -gt 0)
    if($null -ne $case.positive){
        if($case.positive){
            if($bHit){$bTP++}else{$bFN++}
            if($nHit){$nTP++}else{$nFN++}
        }else{
            if($bHit){$bFP++}else{$bTN++}
            if($nHit){$nFP++}else{$nTN++}
        }
    }
    switch($case.id){
        'M00' {Check-D13 (-not $bHit -and -not $nHit) 'M00 clean control remains nonanomalous'}
        'M01' {Check-D13 (-not $bHit -and -not $nHit) 'M01 valid fragmentation is not a cycle'}
        'M02' {Check-D13 ($old.evidence.mirrorDifferentEntries -eq 1 -and
            $new.evidence.mirrorDifferentEntries -eq 1 -and $new.evidence.observedCycles -eq 0) 'M02 both modes detect exactly one FAT-copy mismatch'}
        'M03' {Check-D13 ($old.evidence.mirrorDifferentEntries -eq 0 -and
            $new.evidence.mirrorDifferentEntries -eq 0 -and $new.evidence.observedCycles -ge 2) 'M03 identical corrupt mirrors have observed cycles'}
        'X02' {Check-D13 ($new.geometryReasonCodes -contains 'geometry.partition_exceeds_stream' -and
            -not $nHit) 'X02 remains partial/unknown payload extent, no false FAT anomaly'}
    }
    $baselineBytes+=$old.metrics.bytesRead;$newBytes+=$new.metrics.bytesRead
    $baselineUnique+=$old.metrics.uniquePhysicalBytes;$newUnique+=$new.metrics.uniquePhysicalBytes
    $baselineRequests+=$old.metrics.readRequests;$newRequests+=$new.metrics.readRequests
    $json=$new|ConvertTo-Json -Depth 16
    Check-D13 ($json -notmatch 'originalFilename|sourcePath|rawBytes|PRIVATE|MANIFEST|repairTarget|originalSha256|recoveredFile') ($case.id+' numeric/fixed-code JSON no oracle/path/raw source data')
    Write-Host ('D observed I/O {0}: mirror={1}; cycle={2}; baseline actual/unique={3}/{4}; opt-in actual/unique={5}/{6}; reads={7}/{8}' -f
        $case.id,$new.evidence.mirrorDifferentEntries,$new.evidence.observedCycles,
        $old.metrics.bytesRead,$old.metrics.uniquePhysicalBytes,$new.metrics.bytesRead,
        $new.metrics.uniquePhysicalBytes,$old.metrics.readRequests,$new.metrics.readRequests)
}
Check-D13 ($bTP -eq 1 -and $bFP -eq 0 -and $bFN -eq 1 -and $bTN -eq 2) 'Baseline four-case injection confusion TP1 FP0 FN1 TN2'
Check-D13 ($nTP -eq 2 -and $nFP -eq 0 -and $nFN -eq 0 -and $nTN -eq 2) 'Opt-in four-case injection confusion TP2 FP0 FN0 TN2'
Check-D13 ($newBytes -le 10240 -and $baselineBytes -eq 10240 -and
    $newUnique -le $newBytes -and $baselineUnique -eq $baselineBytes) 'Five-case physical byte totals and distinct union are bounded'
Write-Host ('D 5-case A/B actual bytes base/opt-in={0}/{1}, distinct bytes={2}/{3}, Read() requests={4}/{5}' -f
    $baselineBytes,$newBytes,$baselineUnique,$newUnique,$baselineRequests,$newRequests)

# The wrapped stream must preserve true short-returning behavior. The advertised
# Length is unchanged; actual partial reads and unexpected zero return are tracked.
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class D13FaultStream : Stream {
    private readonly MemoryStream inner;
    private readonly long cutoff;
    private readonly int chunk;
    private long used;
    public D13FaultStream(byte[] bytes,long stopAfter,int maxChunk){
        inner=new MemoryStream(bytes,false);cutoff=stopAfter;chunk=maxChunk;
    }
    public override bool CanRead {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override bool CanSeek {get{return true;}}
    public override long Length {get{return inner.Length;}}
    public override long Position {get{return inner.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long off,SeekOrigin origin){return inner.Seek(off,origin);}
    public override int Read(byte[] b,int off,int count){
        if(used>=cutoff)return 0;
        int n=inner.Read(b,off,(int)Math.Min(Math.Min(count,chunk),cutoff-used));
        used+=n;return n;
    }
    public override void Flush(){}
    public override void SetLength(long n){throw new NotSupportedException();}
    public override void Write(byte[] b,int off,int count){throw new NotSupportedException();}
}
'@
$synthetic=New-ChappyA3DDamagedFixture -Case M03 -Seed 202611
$expected=Hash-D13 $synthetic.image
$short=[D13FaultStream]::new($synthetic.image,1150L,7)
try{
    $r=Get-ChappyFatObservedIoEvidence -Stream $short -Mode MirrorAndChain
    Check-D13 ($r.metrics.bytesRead -eq 1150 -and $r.metrics.uniquePhysicalBytes -eq 1150) 'Injected premature EOF exact actual/unique returned bytes'
    Check-D13 ($r.scanIncomplete -and $r.metrics.prematureSourceZeroReads -gt 0 -and
        $r.reasonCodes -contains 'io.stopped_before_advertised_length') 'Premature zero-read explicitly partial, not a healthy FAT verdict'
    Check-D13 ($r.evidence.observedCycles -eq 0 -and $r.sourceDecision -eq 'not_selected') 'Insufficient FAT evidence cannot invent cycles or select winner'
}finally{$short.Dispose()}
$fragmented=[D13FaultStream]::new($synthetic.image,[long]::MaxValue,7)
try{
    $r=Get-ChappyFatObservedIoEvidence -Stream $fragmented -Mode MirrorAndChain
    Check-D13 ($r.metrics.bytesRead -le 2048 -and $r.evidence.observedCycles -ge 2) '7-byte fragmented source reads are assembled without losing observed cycles'
    Check-D13 ($r.metrics.readRequests -gt 100 -and $r.metrics.uniquePhysicalBytes -le $r.metrics.bytesRead) 'Fragmented reads charged by actual events, not expected request sizes'
}finally{$fragmented.Dispose()}
$tight=Run-D13 $synthetic.image 'MirrorAndChain' 1050
Check-D13 ($tight.metrics.bytesRead -eq 1050 -and $tight.metrics.globalBudgetClipped -and
    $tight.reasonCodes -contains 'budget.global_source_cap') 'Tight single global source cap enforced across phases'
Check-D13 ($tight.scanIncomplete -and $tight.evidence.observedCycles -eq 0) 'Budget exhaustion cannot invent complete FAT chain'
$veryTight=Run-D13 $synthetic.image 'MirrorAndChain' 32
Check-D13 ($veryTight.metrics.bytesRead -le 32 -and $veryTight.status -eq 'partial') 'Even tiny byte cap cannot overrun or return full-confidence evidence'

$writeInput=[IO.MemoryStream]::new($synthetic.image,$true)
try{
    Check-D13 (Throws-D13 {Get-ChappyFatObservedIoEvidence -Stream $writeInput -Mode MirrorOnly}) 'Writable source stream rejected before any read'
}finally{$writeInput.Dispose()}
$readOnly=[IO.MemoryStream]::new($synthetic.image,$false)
try{
    Check-D13 (Throws-D13 {Get-ChappyFatObservedIoEvidence -Stream $readOnly -Mode MirrorAndChain -MaxReadBytes 2049}) 'Beyond 2048-byte global cap parameter refused'
}finally{$readOnly.Dispose()}
Check-D13 ((Hash-D13 $synthetic.image) -ceq $expected) 'Artificial original SHA unchanged after injected and limited reads'
Write-Host ("Team D Issue73 observed-I/O P3: {0} passed; {1} failed." -f $script:Pass,$script:Fail)
if($script:Fail -gt 0){exit 1}
