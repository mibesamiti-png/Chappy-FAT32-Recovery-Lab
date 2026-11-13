#requires -Version 5.1
# Team C #72 C5-05: independent C-owned meter wrapping existing C scanners.
# C observations are UNATTESTED: only Team A may issue physical read receipts.
# Pure caller-supplied Stream; no paths, writing, extraction or file SHA.
Set-StrictMode -Version Latest
if (-not ('ChappyC5ReturnedByteMeterV1' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class ChappyC5ReturnedByteMeterV1 : Stream {
    private sealed class Span { public long Start; public long End; }
    private readonly Stream inner;
    private readonly long maxReturned;
    private readonly int maxCalls;
    private readonly List<Span> observed = new List<Span>();
    public long ReturnedBytes { get; private set; }
    public int ReadCalls { get; private set; }
    public int PositiveReadCalls { get; private set; }
    public int ZeroByteReadCalls { get; private set; }
    public bool RefusedBudget { get; private set; }
    public int ObservationCount { get { return observed.Count; } }
    public ChappyC5ReturnedByteMeterV1(Stream source,long returnedLimit,int callLimit) {
        if(source==null||!source.CanRead||!source.CanSeek||source.CanWrite)
            throw new ArgumentException("non-writable readable seekable stream only");
        if(returnedLimit<1 || returnedLimit>98304 || callLimit<2 || callLimit>4096)
            throw new ArgumentOutOfRangeException("meter cap");
        inner=source;maxReturned=returnedLimit;maxCalls=callLimit;
    }
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return inner.Length;}}
    public override long Position {get{return inner.Position;}set{inner.Position=value;}}
    public override int Read(byte[] buffer,int offset,int count) {
        ReadCalls++;
        if(ReadCalls>maxCalls || (count>0 && ReturnedBytes>=maxReturned)) {
            RefusedBudget=true;
            throw new IOException("C5 returned-byte/read-call guard exhausted");
        }
        int request=(int)Math.Min((long)count,maxReturned-ReturnedBytes);
        long at=inner.Position;
        int got=inner.Read(buffer,offset,request);
        if(got<0 || got>request) {
            RefusedBudget=true;
            throw new IOException("invalid returned byte count");
        }
        if(got==0){ZeroByteReadCalls++;return 0;}
        ReturnedBytes+=got;
        PositiveReadCalls++;
        observed.Add(new Span{Start=at,End=at+got});
        return got;
    }
    public long UniqueReturnedBytes {
        get {
            if(observed.Count==0)return 0;
            var ordered=new List<Span>(observed);
            ordered.Sort((a,b)=>a.Start.CompareTo(b.Start));
            long covered=0,lo=ordered[0].Start,hi=ordered[0].End;
            for(int i=1;i<ordered.Count;i++){
                if(ordered[i].Start>hi){
                    covered+=hi-lo;lo=ordered[i].Start;hi=ordered[i].End;
                }else if(ordered[i].End>hi){hi=ordered[i].End;}
            }
            return covered+hi-lo;
        }
    }
    public override long Seek(long offset,SeekOrigin origin){return inner.Seek(offset,origin);}
    public override void Flush(){}
    public override void SetLength(long n){throw new NotSupportedException();}
    public override void Write(byte[] buffer,int offset,int count){throw new NotSupportedException();}
    // Intentionally does not dispose caller-owned source stream.
    protected override void Dispose(bool disposing){base.Dispose(disposing);}
}
'@
}
function Get-ChappyCarvingCoverageEvidence {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][IO.Stream]$Source,
        [switch]$EnableCoverageEvidence,
        [ValidateSet('Fragment','Window')][string]$Mode='Fragment',
        [ValidateRange(0,9223372036854775806)][long]$StartOffsetBytes=0,
        [ValidateRange(1,98304)][long]$MaxSourceBytes=98304,
        [ValidateRange(2,4096)][int]$MaxReadCalls=4096,
        [ValidateRange(100,30000)][int]$MaxMilliseconds=30000
    )
    $m=[ordered]@{
        actualReturnedBytes=0L;uniqueReturnedBytes=0L;repeatedReturnedBytes=0L
        readCalls=0;successfulReadCalls=0;zeroByteReadCalls=0;observedReadIntervals=0
        sectorProbes=0;formatProbes=0;pairAttempts=0;candidateCount=0
        validatorMemoryReadBytes=$null;validatorMemoryReadStatus='not_measured'
        maxPhysicalReturnedBytesAllowed=[long]$MaxSourceBytes
        maxObservedReadCallsAllowed=$MaxReadCalls
        maxPairBufferBytes=$(if($Mode -eq 'Fragment'){1056}else{0})
        maxSectorScratchBytes=$(if($Mode -eq 'Fragment'){512}else{0})
        maxScannerChunkBytes=$(if($Mode -eq 'Window'){16384}else{0})
        peakProcessMemoryBytes=$null;peakProcessMemoryStatus='not_measured'
        elapsedMilliseconds=0;stopCode='coverage.optin_required'
    }
    $out=[ordered]@{
        schemaVersion='c5_source_coverage_v1';team='C';status='disabled';decision='unknown'
        mode=$Mode;scanIncomplete=$true
        originalIdentity='unknown';sourceReadAttestation='C_unattested_A_outer_receipt_required'
        selectedOriginal=$null;canAutoSelectOriginal=$false
        items=@();warnings=@('coverage.optin_required');metrics=[pscustomobject]$m
    }
    # No property access (including stream.Length), seeks or reads when disabled.
    if(-not $EnableCoverageEvidence){return [pscustomobject]$out}
    $out.status='partial';$out.decision='incomplete'
    $out.warnings=@('coverage.unavailable')
    $m.stopCode='coverage.unavailable'
    if(-not $Source.CanRead -or -not $Source.CanSeek -or $Source.CanWrite){
        $m.stopCode='coverage.readonly_source_required'
        $out.warnings=@($m.stopCode)
        return [pscustomobject]$out
    }
    # A bounded call cannot be tricked into examining a real disk sized
    # source. The caller is responsible for ensuring generated test memory.
    if(($Mode -eq 'Fragment' -and ($Source.Length -gt 2097152L -or
            $Source.Length -lt 65536L -or $MaxSourceBytes -lt 65536L)) -or
       ($Mode -eq 'Window' -and ($Source.Length -gt 134217728L -or
            $MaxSourceBytes -lt 65536L -or
            $StartOffsetBytes -gt ($Source.Length-65536L)))) {
        $m.stopCode='coverage.source_or_quota_preflight'
        $out.warnings=@($m.stopCode)
        return [pscustomobject]$out
    }
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $observed=$null
    try {
        $observed=[ChappyC5ReturnedByteMeterV1]::new($Source,$MaxSourceBytes,$MaxReadCalls)
        if($Mode -eq 'Fragment'){
            Import-Module (Join-Path $PSScriptRoot 'Chappy.FragmentEvidence.psm1') -ErrorAction Stop
            $args=@{Source=$observed;EnableFragmentEvidence=$true
                WindowBytes=65536;MaxStarts=4;MaxTails=8;MaxPairs=16
                MaxSourceBytes=([long][Math]::Min(81920L,$MaxSourceBytes))
                MaxValidationBytes=98304;MaxMilliseconds=$MaxMilliseconds}
            $scan=Get-ChappyFragmentCandidates @args
            $m.sectorProbes=[int]$scan.metrics.sectorProbes
            $m.pairAttempts=[int]$scan.metrics.pairAttempts
            $m.validatorMemoryReadBytes=[long]$scan.metrics.validatorBytesRead
            $m.validatorMemoryReadStatus='measured_in_memory_only'
            $scanItems=@($scan.items)
            $out.decision=[string]$scan.decision
            $out.scanIncomplete=[bool]$scan.scanIncomplete
        }else{
            Import-Module (Join-Path $PSScriptRoot 'Chappy.Carving.psm1') -ErrorAction Stop
            $args=@{Stream=$observed;StartOffset=$StartOffsetBytes
                MaxScanBytes=65536;MaxFileBytes=4096;ExtraValidationReadBytes=32768
                MaxCandidates=16;MaxProbes=16;MaxProbeBytes=8192
                MaxWorkMilliseconds=$MaxMilliseconds;EnableSmallDeflateCrc=$true}
            $scan=Get-ChappyCarvingCandidates @args
            $m.formatProbes=[int]$scan.metrics.entriesChecked
            $scanItems=@($scan.items)
            $out.decision='source_window_partial_coverage'
            $out.scanIncomplete=$true
            # C existing scanner does not report in-memory ZIP parser bytes:
            # physical source rereads ARE included in actualReturnedBytes.
            $m.validatorMemoryReadBytes=$null
            $m.validatorMemoryReadStatus='not_separately_instrumented'
        }
        if($scanItems.Count -gt 16){throw 'coverage.unexpected_candidate_overflow'}
        # C source observations do not certify authentic original bytes.
        $safe=New-Object 'System.Collections.Generic.List[object]'
        foreach($entry in $scanItems){
            if($Mode -eq 'Fragment'){
                if($entry.originalIdentity -cne 'unknown' -or
                    $entry.integrityScope -cne 'structural_only_not_original_file_integrity' -or
                    @($entry.sourceSpans).Count -ne 2){throw 'coverage.untrusted_candidate'}
                $a=$entry.sourceSpans[0];$b=$entry.sourceSpans[1]
                $safe.Add([pscustomobject]@{
                    candidateKey=[string]$entry.candidateKey;format='3mf'
                    firstOffset=[long]$a.offsetBytes;firstBytes=[long]$a.lengthBytes
                    secondOffset=[long]$b.offsetBytes;secondBytes=[long]$b.lengthBytes
                    confidence='probable'
                    originalIdentity='unknown'
                    integrityScope='structural_only_not_original_file_integrity'
                })
            }else{
                if($entry.integrityScope -ceq 'original_file_integrity'){throw 'coverage.untrusted_original_claim'}
                $safe.Add([pscustomobject]@{
                    format=[string]$entry.format
                    offsetBytes=[long]$entry.offsetBytes;lengthBytes=[long]$entry.lengthBytes
                    confidence=[string]$entry.confidence
                    originalIdentity='unknown';integrityScope=[string]$entry.integrityScope
                })
            }
        }
        $m.candidateCount=$safe.Count
        if($scan.status -eq 'ok' -and -not $observed.RefusedBudget){
            $out.items=@($safe.ToArray())
            $out.status='partial'
            $m.stopCode='coverage.unscanned_source_unknown'
            $out.warnings=@('coverage.unscanned_source_unknown')
        }else{
            # No early successes on truncated/over-budget source evidence.
            $m.candidateCount=0
            $out.items=@();$out.status='partial';$out.decision='incomplete'
            $m.stopCode='coverage.scanner_incomplete'
            $out.warnings=@($m.stopCode)
        }
    }catch{
        $out.status='partial';$out.decision='incomplete'
        $out.items=@();$m.candidateCount=0
        $m.stopCode='coverage.source_or_meter_error'
        $out.warnings=@($m.stopCode)
    }finally{
        $timer.Stop()
        $m.elapsedMilliseconds=[long]$timer.ElapsedMilliseconds
        if($null -ne $observed){
            $m.actualReturnedBytes=[long]$observed.ReturnedBytes
            $m.uniqueReturnedBytes=[long]$observed.UniqueReturnedBytes
            $m.repeatedReturnedBytes=[long]($observed.ReturnedBytes-$observed.UniqueReturnedBytes)
            $m.readCalls=[int]$observed.ReadCalls
            $m.successfulReadCalls=[int]$observed.PositiveReadCalls
            $m.zeroByteReadCalls=[int]$observed.ZeroByteReadCalls
            $m.observedReadIntervals=[int]$observed.ObservationCount
            if($observed.RefusedBudget){
                $out.items=@();$m.candidateCount=0;$out.status='partial';$out.decision='incomplete'
                $m.stopCode='coverage.meter_budget_refused'
                $out.warnings=@($m.stopCode)
            }
            $observed.Dispose()
        }
    }
    return [pscustomobject]$out
}
Export-ModuleMember -Function Get-ChappyCarvingCoverageEvidence
