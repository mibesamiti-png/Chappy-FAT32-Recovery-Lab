#Requires -Version 5.1
# Team D #73 P4 — scorer-only adversarial provenance A/B; never original media.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32ObservedIoEvidence.psm1') -Force
$script:Pass=0;$script:Fail=0
function Check-D14 {
    param([bool]$Condition,[string]$Label)
    if($Condition){$script:Pass++;Write-Host ('PASS '+$Label)}
    else{$script:Fail++;Write-Host ('FAIL '+$Label)}
}
function Hash-D14 {
    param([byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','')}
    finally{$sha.Dispose()}
}
function Throws-D14 {
    param([scriptblock]$Action)
    try { $null=(& $Action);return $false } catch {return $true}
}
# External scorer's independent physical-byte observer, not passed to the FAT
# wrapper as a truth label; wraps only invented memory bytes. ReadRequests on
# this underlying stream exclude calls blocked by the D wrapper's budget.
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D14ExternalReadObserver : Stream {
    private readonly MemoryStream input;
    private readonly HashSet<long> unique=new HashSet<long>();
    private readonly long stopAfter;
    private readonly int maxChunk;
    private long actual=0;
    private long calls=0;
    public D14ExternalReadObserver(byte[] bytes,long limit,int chunk) {
        input=new MemoryStream(bytes,false);
        stopAfter=limit;maxChunk=chunk;
    }
    public long ActualBytes {get{return actual;}}
    public long UniqueBytes {get{return unique.Count;}}
    public long ReadCalls {get{return calls;}}
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return input.Length;}}
    public override long Position {get{return input.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long pos,SeekOrigin origin){return input.Seek(pos,origin);}
    public override int Read(byte[] buffer,int offset,int count) {
        calls++;
        if(actual>=stopAfter)return 0;
        long start=input.Position;
        int returned=input.Read(buffer,offset,(int)Math.Min((long)maxChunk,Math.Min((long)count,stopAfter-actual)));
        actual+=returned;
        for(int i=0;i<returned;i++)unique.Add(start+i);
        return returned;
    }
    public override void Flush(){}
    public override void SetLength(long n){throw new NotSupportedException();}
    public override void Write(byte[] b,int off,int count){throw new NotSupportedException();}
    protected override void Dispose(bool disposing){if(disposing)input.Dispose();base.Dispose(disposing);}
}
'@

# External oracle builds its own union from the observed read spans.
# It is NEVER supplied to Get-ChappyFatObservedIoEvidence.
function Get-D14ExternalUnion {
    param($EventList)
    $seen=New-Object 'System.Collections.Generic.HashSet[long]'
    $sum=0L
    $phaseBytes=@{}
    $invalid=0
    foreach($e in $EventList){
        $n=[long]$e.returnedBytes;$start=[long]$e.offsetBytes
        if($n -lt 1 -or $n -gt 2048 -or $start -lt 0 -or
            ([long]$e.endExclusiveBytes -ne ($start+$n))){
            $invalid++;continue
        }
        $sum+=$n
        $phase=[string]$e.phase
        if(-not $phaseBytes.ContainsKey($phase)){$phaseBytes[$phase]=0L}
        $phaseBytes[$phase]+=$n
        for($j=0L;$j -lt $n;$j++){[void]$seen.Add($start+$j)}
    }
    return [pscustomobject]@{
        actual=$sum;unique=[long]$seen.Count;duplicates=($sum-$seen.Count)
        phaseBytes=$phaseBytes;invalid=$invalid
    }
}
function Test-D14Report {
    param($Report,[string]$CaseName,[long]$SourceLength,$External,[int]$Budget)
    $oracle=Get-D14ExternalUnion $Report.readEvents
    $spanSum=0L;$priorEnd=-1L
    foreach($span in $Report.uniqueReadRanges){
        $begin=[long]$span.offsetBytes;$end=[long]$span.endExclusiveBytes
        $length=[long]$span.lengthBytes
        if($begin -lt 0 -or $end -gt $SourceLength -or $length -le 0 -or
            $end -ne ($begin+$length) -or $begin -le $priorEnd){
            Check-D14 $false ($CaseName+' invalid unique interval');break
        }
        $priorEnd=$end-1
        $spanSum+=$length
    }
    $sumPhase=0L
    foreach($p in $Report.phaseSummaries){
        $key=[string]$p.phase
        $want=$(if($oracle.phaseBytes.ContainsKey($key)){$oracle.phaseBytes[$key]}else{0L})
        Check-D14 ($want -eq [long]$p.bytesRead) ($CaseName+' phase provenance '+$key)
        $sumPhase+=[long]$p.bytesRead
    }
    Check-D14 ($oracle.invalid -eq 0 -and $oracle.actual -eq [long]$Report.metrics.bytesRead -and
        $oracle.actual -eq $External.ActualBytes) ($CaseName+' independent successful Read() byte accounting')
    Check-D14 ($oracle.unique -eq [long]$Report.metrics.uniquePhysicalBytes -and
        $oracle.unique -eq $External.UniqueBytes -and
        $oracle.unique -eq $spanSum) ($CaseName+' independent physical union and distinct-range sum')
    Check-D14 ($oracle.duplicates -eq [long]$Report.metrics.duplicatePhysicalBytes -and
        $oracle.actual -ge $oracle.unique) ($CaseName+' repeats are not new byte coverage')
    Check-D14 ($sumPhase -eq $oracle.actual -and $oracle.actual -le $Budget -and
        $Report.metrics.maximumGlobalReadBytes -eq $Budget -and
        $Report.metrics.totalReadCapShared) ($CaseName+' phase totals enforce a single global byte budget')
    Check-D14 ($Report.metrics.readRequests -ge $External.ReadCalls -and
        $Report.metrics.successfulReadEvents -le $Report.metrics.readRequests) ($CaseName+' Read() attempts distinguish zero/budget blocked')
    $eventIndex=0
    foreach($event in $Report.readEvents){
        Check-D14 ($event.evidenceId -ceq ('D13-{0:D4}' -f $eventIndex)) ($CaseName+' stable observed event ID '+$eventIndex)
        $eventIndex++
        $p=[string]$event.phase
        $fat=[string]$event.fatCopyIndex
        $known=($p -eq 'geometry' -or $p -eq 'mirror_window_0' -or $p -match '^chain_probe_[2-8]$')
        $actualCopy=$null
        if($p -ne 'geometry'){
            if($event.offsetBytes -ge 16896 -and $event.endExclusiveBytes -le 37376){$actualCopy=0}
            elseif($event.offsetBytes -ge 37376 -and $event.endExclusiveBytes -le 57856){$actualCopy=1}
        }
        Check-D14 ($known -and
            (($null -eq $actualCopy -and $null -eq $event.fatCopyIndex) -or
             ($null -ne $actualCopy -and $event.fatCopyIndex -eq $actualCopy))) ($CaseName+' phase and FAT-copy are numeric read-origin only')
        Check-D14 ($event.provenance -eq 'observed_stream_read' -and
            $event.offsetBytes -ge 0 -and $event.endExclusiveBytes -le $SourceLength) ($CaseName+' observed spans do not invent bytes outside source')
    }
    $json=$Report|ConvertTo-Json -Depth 16
    Check-D14 ($json -notmatch 'userFilename|sourcePath|recoveredFile|originalSha256|rawBytes|repairTarget|fileOwner|trueSourceCopy') ($CaseName+' no original/owner/repair/path disclosures')
    Check-D14 ($Report.sourceDecision -eq 'not_selected' -and $null -eq $Report.selectedCandidate -and
        -not $Report.writePermitted -and $Report.experimentalDefaultOff) ($CaseName+' no unsupported FAT winner, verified owner or writer')
    return $oracle
}

# Cases and truth are held by the scorer. Full 2MiB artificial images are never
# persisted or passed into the repository as binary files.
$cases=@(
    [pscustomobject]@{id='M00';mode='MirrorOnly';limit=2048;stop=[long]::MaxValue;chunk=4096;corrupt=$false},
    [pscustomobject]@{id='M00';mode='MirrorAndChain';limit=2048;stop=[long]::MaxValue;chunk=4096;corrupt=$false},
    [pscustomobject]@{id='M02';mode='MirrorOnly';limit=2048;stop=[long]::MaxValue;chunk=4096;corrupt=$false},
    [pscustomobject]@{id='M02';mode='MirrorAndChain';limit=2048;stop=[long]::MaxValue;chunk=4096;corrupt=$false},
    [pscustomobject]@{id='M03';mode='MirrorOnly';limit=2048;stop=[long]::MaxValue;chunk=4096;corrupt=$false},
    [pscustomobject]@{id='M03';mode='MirrorAndChain';limit=2048;stop=[long]::MaxValue;chunk=4096;corrupt=$false},
    [pscustomobject]@{id='X02';mode='MirrorOnly';limit=2048;stop=[long]::MaxValue;chunk=4096;corrupt=$false},
    [pscustomobject]@{id='M03';mode='MirrorAndChain';limit=2048;stop=1200L;chunk=1;corrupt=$false},
    [pscustomobject]@{id='M03';mode='MirrorAndChain';limit=1050;stop=[long]::MaxValue;chunk=4096;corrupt=$false},
    [pscustomobject]@{id='M03';mode='MirrorAndChain';limit=32;stop=[long]::MaxValue;chunk=4096;corrupt=$false},
    [pscustomobject]@{id='M00';mode='MirrorAndChain';limit=2048;stop=[long]::MaxValue;chunk=4096;corrupt=$true}
)
$bTP=0;$bFP=0;$bFN=0;$bTN=0
$vTP=0;$vFP=0;$vFN=0;$vTN=0
$expectedUnknown=0;$actualTotal=0L;$uniqueTotal=0L;$requestsTotal=0L
foreach($item in $cases){
    $fixture=New-ChappyA3DDamagedFixture -Seed 202611 -Case $item.id
    [byte[]]$bytes=$fixture.image
    if($item.corrupt){
        # Deliberately invalid BPB sectors-per-cluster in the artificial
        # boot sector, never source media. Data change belongs to the scorer.
        $bytes=[byte[]]$bytes.Clone()
        $bytes[525]=0
    }
    $hashBefore=Hash-D14 $bytes
    if(-not $item.corrupt){
        Check-D14 ($hashBefore -ceq $fixture.manifest.imageSha256) ($item.id+' scorer-only generated source hash')
    }
    $tag=('{0}/{1}/cap{2}/chunk{3}' -f $item.id,$item.mode,$item.limit,$item.chunk)
    if($item.corrupt){$tag+='-invalid-bpb'}
    $source=[D14ExternalReadObserver]::new($bytes,[long]$item.stop,[int]$item.chunk)
    try{
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $result=Get-ChappyFatObservedIoEvidence -Stream $source -Mode $item.mode -MaxReadBytes $item.limit
        $watch.Stop()
        $independent=Test-D14Report $result $tag $bytes.Length $source $item.limit
        # Naive A: every returned Read() byte treated as previously unseen;
        # Conservative B: union of distinct byte positions, checked against
        # independently metered underlying source.
        $truthPositive=($source.ActualBytes -gt $source.UniqueBytes)
        $naivePositive=$false
        $unionPositive=($result.metrics.duplicatePhysicalBytes -gt 0)
        if($truthPositive){
            if($naivePositive){$bTP++}else{$bFN++}
            if($unionPositive){$vTP++}else{$vFN++}
        }else{
            if($naivePositive){$bFP++}else{$bTN++}
            if($unionPositive){$vFP++}else{$vTN++}
        }
        if($item.id -eq 'M03' -and $item.limit -eq 2048 -and $item.stop -eq [long]::MaxValue -and
           $item.chunk -eq 4096){
            Check-D14 ($result.evidence.mirrorDifferentEntries -eq 0 -and
                $result.evidence.observedCycles -ge 2) ($tag+' identical corrupt FAT mirrors do not imply integrity')
        }
        if($item.id -eq 'X02'){
            $expectedUnknown++
            Check-D14 ($result.geometryReasonCodes -contains 'geometry.partition_exceeds_stream') ($tag+' out-of-volume metadata remains rejected')
        }
        if($item.corrupt){
            $expectedUnknown++
            Check-D14 ($result.geometryTrustDecision -ne 'trusted' -and $result.status -eq 'partial') ($tag+' malformed synthetic BPB cannot authenticate FAT or imply complete coverage')
        }
        if($item.stop -ne [long]::MaxValue){
            $expectedUnknown++
            Check-D14 ($result.status -eq 'partial' -and $result.scanIncomplete -and
                $result.metrics.prematureSourceZeroReads -gt 0) ($tag+' genuine premature EOF is unknown, not complete')
        }
        if($item.limit -lt 2048){
            $expectedUnknown++
            Check-D14 ($result.status -eq 'partial' -and $result.scanIncomplete -and
                $result.metrics.bytesRead -le $item.limit -and $result.metrics.globalBudgetClipped) ($tag+' byte-limit clipping does not promote incomplete evidence')
        }
        $actualTotal+=$source.ActualBytes
        $uniqueTotal+=$source.UniqueBytes
        $requestsTotal+=$source.ReadCalls
        Check-D14 ((Hash-D14 $bytes) -ceq $hashBefore) ($tag+' artificial source byte-identical after analysis')
        Write-Host ('D14 case={0} actual={1} unique={2} duplicate={3} physicalReadCalls={4} wrapperReadCalls={5} partial={6} milliseconds={7}' -f
            $tag,$result.metrics.bytesRead,$result.metrics.uniquePhysicalBytes,
            $result.metrics.duplicatePhysicalBytes,$source.ReadCalls,
            $result.metrics.readRequests,$result.scanIncomplete,$watch.ElapsedMilliseconds)
    }finally{$source.Dispose()}
}
Check-D14 ($bTP -eq 0 -and $bFP -eq 0 -and $bFN -gt 0 -and $bTN -gt 0) 'Naive sum-of-reads fails to flag duplicate-coverage positives without false alerts')
Check-D14 ($vTP -eq $bFN -and $vFP -eq 0 -and $vFN -eq 0 -and $vTN -eq $bTN) 'Observed unique interval union matches external physical read oracle on every case')
Check-D14 ($expectedUnknown -eq 5) 'Expected uncertainty cases reported separately, never scored as recovered files'
Write-Host ('D14 read-repeat A/B TP/FP/FN/TN naive={0}/{1}/{2}/{3} union={4}/{5}/{6}/{7}, expectedUnknownControls={8}' -f
    $bTP,$bFP,$bFN,$bTN,$vTP,$vFP,$vFN,$vTN,$expectedUnknown)
Write-Host ('D14 source totals actual={0}, unique={1}, duplicates={2}, underlying Read() calls={3}' -f
    $actualTotal,$uniqueTotal,($actualTotal-$uniqueTotal),$requestsTotal)
$fake=New-ChappyA3DDamagedFixture -Seed 202611 -Case M00
$w=[IO.MemoryStream]::new($fake.image,$true)
try{
    Check-D14 (Throws-D14 {Get-ChappyFatObservedIoEvidence -Stream $w -Mode MirrorAndChain}) 'Writable input refused before first source read'
}finally{$w.Dispose()}
Write-Host ('Team D R6-P4 interval negatives: {0} passed; {1} failed.' -f $script:Pass,$script:Fail)
if($script:Fail -gt 0){exit 1}
