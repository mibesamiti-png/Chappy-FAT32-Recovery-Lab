#Requires -Version 5.1
# Team D / D6-05. Default OFF. A read-only, denied-by-default FAT evidence
# envelope. It is NOT an authenticated source receipt or an extraction API.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Fat32GeometryHypothesisGate.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Fat32ObservedIoEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Fat32PhysicalPairCoverage.psm1') -Force

if(-not ('ChappyD605BudgetedStream' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class ChappyD605ReturnedSpan {
    public string Phase {get;set;}
    public long OffsetBytes {get;set;}
    public int ReturnedBytes {get;set;}
}
public sealed class ChappyD605BudgetedStream : Stream {
    readonly Stream source;
    readonly long maxBytes;
    readonly int maxCalls;
    readonly HashSet<long> unique=new HashSet<long>();
    readonly List<ChappyD605ReturnedSpan> events=new List<ChappyD605ReturnedSpan>();
    string phase="";
    long used=0,calls=0,earlyZero=0,refused=0;
    public ChappyD605BudgetedStream(Stream stream,long byteCap,int callCap){
        if(stream==null||!stream.CanRead||!stream.CanSeek||stream.CanWrite)
            throw new ArgumentException("A strictly nonwritable seekable source is required");
        if(byteCap<2048||byteCap>4096||callCap<4||callCap>512)
            throw new ArgumentException("Invalid D6-05 bounds");
        source=stream;maxBytes=byteCap;maxCalls=callCap;
    }
    public void BeginPhase(string tag) {
        if(tag!="geometry_gate"&&tag!="fat_fixed")throw new ArgumentException("Invalid phase");
        phase=tag;
    }
    public ChappyD605ReturnedSpan[] GetReturnedEvents(string tag){
        List<ChappyD605ReturnedSpan> result=new List<ChappyD605ReturnedSpan>();
        foreach(ChappyD605ReturnedSpan e in events)if(e.Phase==tag)result.Add(e);
        return result.ToArray();
    }
    public long PhaseReturnedBytes(string tag) {
        long count=0;foreach(ChappyD605ReturnedSpan e in events)if(e.Phase==tag)count+=e.ReturnedBytes;
        return count;
    }
    public long ActualReturnedBytes {get{return used;}}
    public long UniqueReturnedBytes {get{return unique.Count;}}
    public long RepeatedReturnedBytes {get{return used-unique.Count;}}
    public long PhysicalReadCalls {get{return calls;}}
    public long PrematureSourceZero {get{return earlyZero;}}
    public long RefusedReadCalls {get{return refused;}}
    public int SuccessfulReadEvents {get{return events.Count;}}
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return source.Length;}}
    public override long Position {get{return source.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long offset,SeekOrigin origin){return source.Seek(offset,origin);}
    public override int Read(byte[] b,int off,int n){
        if(String.IsNullOrEmpty(phase))throw new InvalidOperationException("BeginPhase required");
        if(b==null||off<0||n<0||off>b.Length-n)throw new ArgumentException("Invalid Read");
        if(calls>=maxCalls||n>maxBytes-used){refused++;throw new IOException("d605.source_budget_refused");}
        calls++;
        long at=source.Position;
        int got=source.Read(b,off,n);
        if(got<0||got>n)throw new IOException("d605.invalid_return_count");
        if(got==0&&at<source.Length)earlyZero++;
        if(got>0){
            if(at<0||at>source.Length-got)throw new IOException("d605.return_outside_source");
            used+=got;
            events.Add(new ChappyD605ReturnedSpan{Phase=phase,OffsetBytes=at,ReturnedBytes=got});
            for(int k=0;k<got;k++)unique.Add(at+k);
        }
        return got;
    }
    public override void Flush(){}
    public override void SetLength(long n){throw new NotSupportedException();}
    public override void Write(byte[] b,int off,int n){throw new NotSupportedException();}
    // Caller owns the underlying source. This adapter does not close it.
    protected override void Dispose(bool disposing){base.Dispose(disposing);}
}
'@
}

function Get-ChappyFatGuardedResult {
    <#
    .SYNOPSIS
    Versioned D result. Geometry FIRST; no FAT probe on conflicting/unknown VBR.
    .DESCRIPTION
    Explicit synthetic-only opt-in. The result does not authorize source
    selection, physical-image operation, repair, copy or original-file claims.
    A must independently bind its own successful-returned source receipts.
    #>
    [CmdletBinding()]
    param(
        [IO.Stream]$Stream,
        [switch]$EnableGuardedDiagnostics,
        [switch]$IncludeFixedChainEvidence,
        [ValidateRange(2048,4096)][int]$MaxPhysicalReadBytes=4096,
        [ValidateRange(4,512)][int]$MaxPhysicalReadCalls=512
    )
    # All public slots are present on every path: disabled, success, blocked,
    # malformed source, prematurely zero returned and budget exception.
    $out=[ordered]@{
        schemaVersion='1'
        contractVersion='d6_guarded_fat_result_v1'
        team='D'
        mode='default_off_guarded_fixed_fat_diagnostics'
        status='disabled'
        guardDecision='not_evaluated'
        fatProbeState='not_attempted'
        geometryAuthenticity='unknown'
        sourceReadProvenance='internal_D_source_events_NOT_A_attested'
        sourceIdentity='unknown'
        originalIdentity='unknown'
        fileOwner='unknown'
        sourceDecision='not_selected'
        selectedCandidate=$null
        fatCopyWinner='not_selected'
        fatReadAllowed=$false
        wholeFatVerified=$false
        writePermitted=$false
        canRepair=$false
        canExport=$false
        scanIncomplete=$true
        hypotheses=@(
            [pscustomobject]@{sourceRole='primary';plausibility='insufficient_evidence';numericGeometry=$null},
            [pscustomobject]@{sourceRole='backup';plausibility='insufficient_evidence';numericGeometry=$null}
        )
        copies=@(
            [pscustomobject]@{fatCopyIndex=0;fullyObservedEntries=$null;status='unknown';authenticity='unknown'},
            [pscustomobject]@{fatCopyIndex=1;fullyObservedEntries=$null;status='unknown';authenticity='unknown'}
        )
        evidence=[pscustomobject]@{
            mirrorDifferentEntries=$null
            observedCycles=$null
            inspectedChainTraces=$null
            pairedFullyObservedEntries=$null
            totalDeclaredEntriesPerCopy=$null
            unobservedPairedEntryIndices=$null
            pairedCoveragePercent=$null
            unobservedPairPercent=$null
            coverageStatus='unknown'
        }
        reasonCodes=@('d6.enable_explicit_optin_required')
        warnings=@(
            'd6.unobserved_fat_entries_UNKNOWN_not_clean',
            'd6.source_events_not_A_issued_attestation',
            'd6.caller_geometry_not_volume_authenticity',
            'd6.no_auto_fat_winner_or_original_owner',
            'd6.real_card_and_master_img_NOT_APPROVED'
        )
        metrics=[pscustomobject]@{
            actualReturnedBytes=0L
            uniqueReturnedBytes=0L
            repeatedReturnedBytes=0L
            physicalReadCalls=0L
            prematureSourceZeroReads=0L
            refusedReadCalls=0L
            successfulSourceReadEvents=0
            geometryGateReturnedBytes=0L
            fatFixedReturnedBytes=0L
            maxPhysicalReadBytes=$MaxPhysicalReadBytes
            maxPhysicalReadCalls=$MaxPhysicalReadCalls
            maxGeometryGateReadBytes=2048
            maxFixedFatReadBytes=2048
        }
    }
    if(-not $EnableGuardedDiagnostics){return [pscustomobject]$out}
    $out.status='unknown'
    $out.reasonCodes=@('d6.source_unknown')
    if($null -eq $Stream -or -not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite) {
        $out.reasonCodes=@('input.strictly_nonwritable_seekable_stream_required')
        return [pscustomobject]$out
    }
    $meter=$null
    try{
        $meter=[ChappyD605BudgetedStream]::new($Stream,[long]$MaxPhysicalReadBytes,$MaxPhysicalReadCalls)
        $meter.BeginPhase('geometry_gate')
        $g=Get-ChappyFatGeometryHypothesisGate -Stream $meter -MaxReadBytes 2048 -MaxPhysicalReadCalls ([int][Math]::Min(256,$MaxPhysicalReadCalls))
        $out.guardDecision=[string]$g.gateDecision
        $out.hypotheses=@($g.hypotheses)
        $out.reasonCodes=@($g.reasonCodes)
        if($g.gateDecision -cne 'candidate_geometry_unverified' -or
           $g.scanIncomplete -or $meter.PrematureSourceZero -gt 0 -or
           $meter.RefusedReadCalls -gt 0){
            $out.status='partial'
            $out.fatProbeState='blocked_geometry_or_source_UNKNOWN'
        }else{
            $h=@($g.hypotheses)
            # Both hypotheses must match NUMERICALLY. None is authenticated.
            # Do not use the primary copy alone as an implicit winner.
            $a=$h[0].numericGeometry
            $b=$h[1].numericGeometry
            $same=($h.Count -eq 2 -and
                $h[0].plausibility -ceq 'plausible_unverified' -and
                $h[1].plausibility -ceq 'plausible_unverified' -and
                $null -ne $a -and $null -ne $b -and
                $a.fat1OffsetBytes -eq $b.fat1OffsetBytes -and
                $a.fat2OffsetBytes -eq $b.fat2OffsetBytes -and
                $a.fatLengthBytes -eq $b.fatLengthBytes)
            $f1=0L;$f2=0L;$fb=0L
            if($same){
                $f1=[long]$a.fat1OffsetBytes
                $f2=[long]$a.fat2OffsetBytes
                $fb=[long]$a.fatLengthBytes
                $same=($f1 -ge 0 -and $f2 -ge 0 -and
                    $fb -ge 12 -and $fb%4 -eq 0 -and
                    $f1 -le $Stream.Length-$fb -and
                    $f2 -le $Stream.Length-$fb -and
                    ($f1+$fb -le $f2 -or $f2+$fb -le $f1))
            }
            if(-not $same){
                $out.status='partial'
                $out.guardDecision='blocked_conflicting_geometry'
                $out.fatProbeState='blocked_numeric_candidate_mismatch'
                $out.reasonCodes=@('geometry.independent_hypotheses_cannot_be_combined')
            }else{
                $meter.BeginPhase('fat_fixed')
                $probeMode=$(if($IncludeFixedChainEvidence){'MirrorAndChain'}else{'MirrorOnly'})
                $fat=Get-ChappyFatObservedIoEvidence -Stream $meter -Mode $probeMode -MaxReadBytes 2048
                $out.fatProbeState='fixed_baseline_sampled'
                $out.status='partial'
                $out.reasonCodes=@(
                    'coverage.fixed_sample_only_unobserved_UNKNOWN',
                    'geometry.two_matching_VBRs_still_unverified'
                )
                $out.evidence.mirrorDifferentEntries=$fat.evidence.mirrorDifferentEntries
                $out.evidence.observedCycles=$fat.evidence.observedCycles
                $out.evidence.inspectedChainTraces=$fat.evidence.inspectedChainTraces

                # This separate D meter is NOT an A issued physical receipt.
                # It only permits a conservative internal two-layer check.
                $physical=@($meter.GetReturnedEvents('fat_fixed') | ForEach-Object {
                    [pscustomobject]@{
                        OffsetBytes=[long]$_.OffsetBytes
                        ReturnedBytes=[int]$_.ReturnedBytes
                    }
                })
                $arg=@{
                    Observation=$fat
                    OuterReturnedEvents=$physical
                    Fat1OffsetBytes=$f1;Fat2OffsetBytes=$f2
                    FatLengthBytes=$fb;SourceLengthBytes=([long]$Stream.Length)
                    MaxReturnedBytes=2048;MaxSuccessfulEvents=256
                }
                $coverage=Get-ChappyFatPhysicalPairCoverage @arg
                if($coverage.externalEventAgreement -and
                   $coverage.status -ceq 'partial_numeric_candidate_only' -and
                   $meter.PrematureSourceZero -eq 0 -and
                   $meter.RefusedReadCalls -eq 0){
                    $out.evidence=[pscustomobject]@{
                        mirrorDifferentEntries=$fat.evidence.mirrorDifferentEntries
                        observedCycles=$fat.evidence.observedCycles
                        inspectedChainTraces=$fat.evidence.inspectedChainTraces
                        pairedFullyObservedEntries=$coverage.metrics.pairedFullyObservedEntries
                        totalDeclaredEntriesPerCopy=$coverage.metrics.totalDeclaredFatEntriesPerCopy
                        unobservedPairedEntryIndices=$coverage.metrics.unobservedPairedEntryIndices
                        pairedCoveragePercent=$coverage.metrics.pairedCoveragePercent
                        unobservedPairPercent=$coverage.metrics.unobservedPairPercent
                        coverageStatus='partial_numeric_candidate_only'
                    }
                    $out.copies=@(
                        [pscustomobject]@{fatCopyIndex=0;fullyObservedEntries=$coverage.metrics.fullyObservedFat1Entries;status='partial_numeric_candidate_only';authenticity='unknown'},
                        [pscustomobject]@{fatCopyIndex=1;fullyObservedEntries=$coverage.metrics.fullyObservedFat2Entries;status='partial_numeric_candidate_only';authenticity='unknown'}
                    )
                }else{
                    $out.reasonCodes+= 'coverage.outer_meter_or_D_fat_observation_incomplete_UNKNOWN'
                    $out.reasonCodes+= @($coverage.reasons)
                    $out.fatProbeState='sampled_but_coverage_UNKNOWN'
                    if($meter.PhaseReturnedBytes('fat_fixed') -eq 0 -or
                       $meter.RefusedReadCalls -gt 0 -or
                       $meter.PrematureSourceZero -gt 0){
                        # No physical FAT bytes (or source quota failure):
                        # never call this a completed sample.
                        $out.status='unknown'
                        $out.fatProbeState='incomplete_source_or_budget_UNKNOWN'
                    }
                    # Never leave a positive mirror/cycle number on a source
                    # with premature physical zero or unmatched D returned spans.
                    if($meter.PrematureSourceZero -gt 0 -or $meter.RefusedReadCalls -gt 0){
                        $out.evidence.mirrorDifferentEntries=$null
                        $out.evidence.observedCycles=$null
                        $out.evidence.inspectedChainTraces=$null
                    }
                }
            }
        }
    }catch{
        # Deliberately do not expose arbitrary source exception text (paths,
        # payloads, private ids) through the public error contract.
        $out.status='unknown'
        $out.fatProbeState='incomplete_source_or_budget_UNKNOWN'
        $out.reasonCodes=@('d6.bounded_source_or_module_exception_UNKNOWN')
        $out.copies=@(
            [pscustomobject]@{fatCopyIndex=0;fullyObservedEntries=$null;status='unknown';authenticity='unknown'},
            [pscustomobject]@{fatCopyIndex=1;fullyObservedEntries=$null;status='unknown';authenticity='unknown'}
        )
        $out.evidence=[pscustomobject]@{
            mirrorDifferentEntries=$null;observedCycles=$null;inspectedChainTraces=$null
            pairedFullyObservedEntries=$null;totalDeclaredEntriesPerCopy=$null
            unobservedPairedEntryIndices=$null;pairedCoveragePercent=$null
            unobservedPairPercent=$null;coverageStatus='unknown'
        }
    }finally{
        if($null -ne $meter){
            $out.metrics=[pscustomobject]@{
                actualReturnedBytes=[long]$meter.ActualReturnedBytes
                uniqueReturnedBytes=[long]$meter.UniqueReturnedBytes
                repeatedReturnedBytes=[long]$meter.RepeatedReturnedBytes
                physicalReadCalls=[long]$meter.PhysicalReadCalls
                prematureSourceZeroReads=[long]$meter.PrematureSourceZero
                refusedReadCalls=[long]$meter.RefusedReadCalls
                successfulSourceReadEvents=[int]$meter.SuccessfulReadEvents
                geometryGateReturnedBytes=[long]$meter.PhaseReturnedBytes('geometry_gate')
                fatFixedReturnedBytes=[long]$meter.PhaseReturnedBytes('fat_fixed')
                maxPhysicalReadBytes=$MaxPhysicalReadBytes
                maxPhysicalReadCalls=$MaxPhysicalReadCalls
                maxGeometryGateReadBytes=2048
                maxFixedFatReadBytes=2048
            }
        }
    }
    return [pscustomobject]$out
}
Export-ModuleMember -Function Get-ChappyFatGuardedResult
