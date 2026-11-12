#Requires -Version 5.1
# Team A R7: real C standard data-region candidate -> A-only source-token /
# candidate-phase physical-read receipts on disposable artificial FAT32 volumes.
# No device, path, original IMG, export, write, or production authenticity.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Test-A3DSharedReadProvenance.ps1')
. (Join-Path $PSScriptRoot 'helpers\Resolve-A3DReadEvidence.ps1')
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')
. (Join-Path $root 'modules\carving\tests\R5StandardDataWindowResearch.ps1')

if(-not ('ChappyA7StandardCandidateScope' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class ChappyA7StandardShortSource : MemoryStream {
    public long StopAt { get; set; }
    public ChappyA7StandardShortSource(byte[] bytes) : base(bytes, false) {
        StopAt = bytes.LongLength;
    }
    public override int Read(byte[] buffer, int offset, int count) {
        if (Position >= StopAt) return 0;
        return base.Read(buffer, offset, (int)Math.Min(count, StopAt - Position));
    }
}
public sealed class ChappyA7StandardCandidateEvent {
    public string EvidenceId {get;set;}
    public string SourceToken {get;set;}
    public string Consumer {get;set;}
    public string Purpose {get;set;}
    public string CandidateId {get;set;}
    public long OffsetBytes {get;set;}
    public int ReturnedBytes {get;set;}
}
public sealed class ChappyA7StandardCandidateScope : Stream {
    private readonly Stream source;
    private readonly string token;
    private readonly long maximum;
    private readonly List<ChappyA7StandardCandidateEvent> events =
        new List<ChappyA7StandardCandidateEvent>();
    private long total=0, requests=0;
    private string phase="",candidate="";
    public ChappyA7StandardCandidateScope(Stream input,string id,long cap){
        if(input==null||!input.CanRead||!input.CanSeek||input.CanWrite)
            throw new ArgumentException("Nonwritable source required");
        if(String.IsNullOrEmpty(id)||id.Length>42||cap<1024||cap>120000)
            throw new ArgumentException("Invalid source token or cap");
        source=input;token=id;maximum=cap;
    }
    public void BeginPhase(string label,string id){
        if(label!="scan"&&label!="candidate_validation")
            throw new ArgumentException("Unrecognized receipt phase");
        if(label=="candidate_validation" &&
           (String.IsNullOrEmpty(id)||id.Length>128))
            throw new ArgumentException("Candidate key required");
        phase=label; candidate=label=="scan"?"":id;
    }
    public ChappyA7StandardCandidateEvent[] GetEvents(){return events.ToArray();}
    public long ActualBytes{get{return total;}}
    public long Requests{get{return requests;}}
    public override bool CanRead{get{return true;}}
    public override bool CanWrite{get{return false;}}
    public override bool CanSeek{get{return true;}}
    public override long Length{get{return source.Length;}}
    public override long Position{get{return source.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long x,SeekOrigin o){return source.Seek(x,o);}
    public override int Read(byte[] b,int o,int n){
        if(String.IsNullOrEmpty(phase)) throw new InvalidOperationException("BeginPhase required");
        if(b==null||o<0||n<0||o>b.Length-n) throw new ArgumentException("Invalid buffer");
        requests++;
        if(n>maximum-total)throw new IOException("A7.candidate_phase_budget_exhausted");
        long at=source.Position;
        int got=source.Read(b,o,n);
        if(got>0){
            total+=got;
            events.Add(new ChappyA7StandardCandidateEvent {
                EvidenceId=token+"#"+events.Count.ToString("D4"),
                SourceToken=token,Consumer="carving",Purpose=phase,
                CandidateId=candidate,OffsetBytes=at,ReturnedBytes=got
            });
        }
        return got;
    }
    public override void Flush(){}
    public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
    public override void SetLength(long x){throw new NotSupportedException();}
    // Caller owns source; this wrapper never writes or closes it.
}
'@
}
function Assert-A7Receipt([bool]$Okay,[string]$Code){
    if(-not $Okay){throw ('A7_STANDARD_C_RECEIPT_FAIL: '+$Code)}
}

$results=New-Object System.Collections.ArrayList
$totalPhysical=0L;$totalCandidateBytes=0L;$count=0
foreach($trial in @(1,2,3)){
    # Two separately instantiated, byte-identical sources must have distinct
    # A-issued source tokens even when candidate offsets and hashes match.
    $fixture=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster 2
    [byte[]]$img=$fixture.image
    $before=Get-A3DSha256 $img
    $source=[ChappyA7StandardShortSource]::new($img)
    $outer=[ChappyA7SharedSource]::new($source,120000L)
    $token=('A7standard_202611_spc2_'+$trial)
    $scoped=$null
    try{
        $outer.BeginConsumer('geometry')
        $geo=Get-ChappyFat32Geometry -Stream $outer
        Assert-A7Receipt ($geo.clusterCount -eq 65541 -and
            $geo.dataOffsetBytes -gt 65536L -and $geo.sectorsPerCluster -eq 2) 'B_read_numeric_geometry'

        $outer.BeginConsumer('directory')
        $directory=Get-ChappyDirectoryCandidates -Stream $outer -Geometry $geo -MaxScanBytes 1024 -MaxCandidates 16 -MaxDirectories 4 -RecordDirectoryReadSpans -MaxDirectoryReadSpans 8
        Assert-A7Receipt ($directory.team -ceq 'B' -and
            $directory.metrics.bytesRead -eq 1024L -and $directory.scanIncomplete) 'B_root_is_partial_coverage'

        $outer.BeginConsumer('carving')
        $scoped=[ChappyA7StandardCandidateScope]::new($outer,$token,120000L)
        $scoped.BeginPhase('scan','')
        $research=Invoke-CStandardDataTrial -Stream $scoped -Geometry $geo -EnableDataWindow
        $candidates=@($research.items|Where-Object {$_.format -ceq '3mf' -and
            $_.offsetBytes -ge [long]$geo.dataOffsetBytes -and
            $_.lengthBytes -gt 0 -and $_.lengthBytes -le 4096})
        Assert-A7Receipt ($research.status -ceq 'partial' -and
            $research.originalIdentity -ceq 'unknown' -and
            $research.start -eq [long]$geo.dataOffsetBytes -and
            $candidates.Count -eq 1 -and
            $research.metrics.sourceBytesRead -eq $scoped.ActualBytes) 'actual_C_candidate_not_oracle_selected'
        $candidate=$candidates[0]
        Assert-A7Receipt ($candidate.integrityScope -cne 'original_file_integrity' -and
            $null -eq $candidate.PSObject.Properties['sourceToken']) 'C_has_no_forged_A_token'
        $candidateId=('3mf:{0}+{1}' -f [long]$candidate.offsetBytes,[long]$candidate.lengthBytes)
        $extent=@([pscustomobject]@{offsetBytes=[long]$candidate.offsetBytes;lengthBytes=[long]$candidate.lengthBytes})
        $scanBytes=$scoped.ActualBytes
        $scoped.BeginPhase('candidate_validation',$candidateId)

        if($trial -eq 3){
            $start=[long]$candidate.offsetBytes
            $size=[int]$candidate.lengthBytes
            Assert-A7Receipt ($size -gt 17) 'EOF_prefix_smaller_than_candidate'
            $source.StopAt=$start+17L
            $beforeRequests=$outer.ReadRequests
            $beforeBytes=$outer.TotalBytes
            [byte[]]$prefix=[byte[]]::new($size)
            [void]$scoped.Seek($start,[IO.SeekOrigin]::Begin)
            $got=$scoped.Read($prefix,0,$size)
            Assert-A7Receipt ($got -eq 17) 'backing_source_returns_only_prefix'
            $eof=$scoped.Read($prefix,$got,$size-$got)
            Assert-A7Receipt ($eof -eq 0 -and ($outer.ReadRequests-$beforeRequests) -eq 2 -and
                ($outer.TotalBytes-$beforeBytes) -eq 17L -and $outer.TotalBytes -le 120000L) 'EOF_distinct_from_budget_refusal'
            $events=@($scoped.GetEvents())
            $physical=@($outer.GetEvents() | Where-Object {$_.Consumer -ceq 'carving'})
            $last=$events[-1]
            Assert-A7Receipt ($events.Count -eq $physical.Count -and
                $last.OffsetBytes -eq $start -and $last.ReturnedBytes -eq 17 -and
                $physical[-1].OffsetBytes -eq $start -and $physical[-1].ReturnedBytes -eq 17) 'partial_receipt_matches_source'
            $partial=Resolve-A3DReadEvidence -ImageLengthBytes $img.Length -SourceToken $token -CandidateId $candidateId -CandidateExtents $extent -MeterEvents $events -ClaimedEventIds @($last.EvidenceId) -MaxPhysicalReadBytes 120000L
            Assert-A7Receipt ($partial.status -ceq 'unattributed' -and $partial.candidateReadBytes -eq 17 -and
                $partial.originalIdentity -ceq 'unknown' -and
                $partial.reasons -contains 'coverage.candidate_bytes_not_fully_read') 'short_read_cannot_attest_full_candidate'
            Assert-A7Receipt ((Get-A3DSha256 $img) -ceq $before) 'EOF_fixture_source_unchanged'
            Write-Host ('PASS: A7 candidate source EOF returned {0}/{1} bytes in two reads, total {2}, coverage unattributed and identity UNKNOWN.' -f $got,$size,$outer.TotalBytes)
            continue
        }

        # Invoke the actual C parser again on a narrow region proposed by C,
        # under A's candidate-specific physical-read phase. Structural checks
        # are NOT a statement about original content or filesystem ownership.
        $checked=Get-ChappyCarvingCandidates -Stream $scoped -StartOffset ([long]$candidate.offsetBytes) -MaxScanBytes 4096 -ExtraValidationReadBytes 8192 -MaxFileBytes 4096 -MaxCandidates 4 -MaxProbes 4 -MaxProbeBytes 4096 -MaxWorkMilliseconds 5000
        Assert-A7Receipt ($checked.team -ceq 'C' -and $checked.status -ne 'error' -and
            @($checked.items|Where-Object {$_.format -ceq '3mf' -and
                $_.offsetBytes -eq $candidate.offsetBytes}).Count -ge 1) 'actual_C_parser_rerun_on_discovered_candidate'

        # C's structural probe need not physically cover every candidate byte.
        # A performs one bounded full-candidate reread, and only then may the
        # receipt state be 'source_observed'; still originalIdentity=unknown.
        $size=[int]$candidate.lengthBytes
        [byte[]]$observed=[byte[]]::new($size)
        [void]$scoped.Seek([long]$candidate.offsetBytes,[IO.SeekOrigin]::Begin)
        $written=0
        while($written -lt $size){
            $got=$scoped.Read($observed,$written,$size-$written)
            if($got -le 0){break}
            $written+=$got
        }
        Assert-A7Receipt ($written -eq $size -and $scoped.ActualBytes -gt $scanBytes) 'candidate_full_physical_reread'

        $outer.BeginConsumer('fat')
        $fat=Get-ChappyFatObservedIoEvidence -Stream $outer -Mode MirrorAndChain -MaxReadBytes 2048
        Assert-A7Receipt ($fat.team -ceq 'D' -and $fat.experimentalDefaultOff -and
            -not $fat.writePermitted -and $fat.sourceDecision -ceq 'not_selected') 'D_no_winner_or_repair'

        $all=@($scoped.GetEvents())
        $cActual=0L
        $innerReturned=@($all|ForEach-Object {$cActual+=[long]$_.ReturnedBytes})
        $carvingOuter=@($outer.GetEvents()|Where-Object {$_.Consumer -ceq 'carving'})
        Assert-A7Receipt ($carvingOuter.Count -eq $all.Count -and
            $scoped.ActualBytes -eq $cActual) 'every_scoped_read_event_physically_observed'
        for($j=0;$j -lt $all.Count;$j++){
            Assert-A7Receipt ($all[$j].OffsetBytes -eq $carvingOuter[$j].OffsetBytes -and
                $all[$j].ReturnedBytes -eq $carvingOuter[$j].ReturnedBytes) 'outer_real_physical_offset_and_return_match'
        }
        $outerReturned=0L
        foreach($evt in @($outer.GetEvents())){$outerReturned+=[long]$evt.ReturnedBytes}
        Assert-A7Receipt ($outerReturned -eq $outer.TotalBytes -and
            $outer.TotalBytes -le 120000L -and
            $outer.UniqueBytes -le $outer.TotalBytes -and
            $outer.DuplicateBytes -eq ($outer.TotalBytes-$outer.UniqueBytes)) 'one_shared_real_returned_byte_quota'

        $receiptIds=@($all|Where-Object {$_.Purpose -ceq 'candidate_validation' -and $_.CandidateId -ceq $candidateId}|ForEach-Object {$_.EvidenceId})
        Assert-A7Receipt ($receiptIds.Count -gt 0 -and $receiptIds.Count -le 128) 'A_scoped_candidate_phase_event_ids'
        $scope=@{
            ImageLengthBytes=[long]$img.Length;SourceToken=$token
            CandidateId=$candidateId;CandidateExtents=$extent
            MeterEvents=$all;MaxPhysicalReadBytes=120000L
        }
        $receipt=Resolve-A3DReadEvidence @scope -ClaimedEventIds $receiptIds
        Assert-A7Receipt ($receipt.status -ceq 'source_observed' -and
            $receipt.candidateReadBytes -eq $size -and
            $receipt.sourceActualReadBytes -eq $scoped.ActualBytes -and
            $receipt.originalIdentity -ceq 'unknown' -and
            $receipt.integrityScope -ceq 'source_read_coverage_only_not_original_integrity') 'A_candidate_specific_receipts_only_coverage'

        $scanned=@($all|Where-Object {$_.Purpose -ceq 'scan'})
        Assert-A7Receipt ($scanned.Count -gt 0) 'separate_scan_from_validator_events'
        $scanClaim=Resolve-A3DReadEvidence @scope -ClaimedEventIds @($scanned[0].EvidenceId)
        Assert-A7Receipt ($scanClaim.status -ceq 'unattributed' -and
            $scanClaim.reasons -contains 'origin.not_candidate_validation') 'scan_not_a_candidate_receipt'
        $ghost=Resolve-A3DReadEvidence @scope -ClaimedEventIds @('A7_GHOST_ID')
        Assert-A7Receipt ($ghost.status -ceq 'unattributed' -and
            $ghost.reasons -contains 'origin.event_not_observed') 'ghost_event_rejected'
        $wrong=$scope.Clone();$wrong.CandidateId=$candidateId+'_wrong'
        $wrongResult=Resolve-A3DReadEvidence @wrong -ClaimedEventIds $receiptIds
        Assert-A7Receipt ($wrongResult.status -ceq 'unattributed' -and
            $wrongResult.reasons -contains 'origin.not_candidate_validation') 'wrong_C_candidate_not_attested'
        $low=$scope.Clone();$low.MaxPhysicalReadBytes=1024L
        $limited=Resolve-A3DReadEvidence @low -ClaimedEventIds $receiptIds
        Assert-A7Receipt ($limited.status -ceq 'unattributed' -and
            $limited.reasons -contains 'budget.physical_read_limit') 'claimed_A_budget_too_low_rejected'

        # Artificial scorer only, AFTER all real C discovery/validation phases.
        $truth=@($fixture.oracle|Where-Object {$_.shortName -ceq 'MODEL   3MF'})[0]
        $scorerExact=((Get-A3DSha256 $observed) -ceq $truth.sha256)
        Assert-A7Receipt ($scorerExact -and
            (Get-A3DSha256 $img) -ceq $before -and
            -not $source.CanWrite -and -not $outer.CanWrite -and -not $scoped.CanWrite) 'synthetic_only_original_oracle_outside_modules'

        [void]$results.Add([pscustomobject]@{
            token=$token;id=$candidateId;ids=$receiptIds;events=$all
            extent=$extent;sourceLength=[long]$img.Length;bytes=$scoped.ActualBytes
            originalIdentity=$receipt.originalIdentity
        })
        $count++;$totalPhysical+=$outer.TotalBytes;$totalCandidateBytes+=$size
        Write-Host ('A7 STANDARD RECEIPT trial={0} C_candidate={1} A_total_physical={2} C_scan={3} C_scoped={4} candidate_read={5} IDs={6} source_observed=1 original=UNKNOWN' -f
            $trial,$candidateId,$outer.TotalBytes,$scanBytes,$scoped.ActualBytes,$size,$receiptIds.Count)
    } finally {$source.Dispose();$scoped=$null;$outer=$null;$fixture=$null;$img=$null;[GC]::Collect()}
}

# Cross-source negative: exact same synthetic bytes and candidate offsets do
# not allow another independently metered source's receipt IDs to attest.
$a=$results[0];$b=$results[1]
Assert-A7Receipt ($a.id -ceq $b.id -and $a.token -cne $b.token -and
    $a.ids[0] -cne $b.ids[0]) 'identical_candidate_distinct_source_tokens'
$other=Resolve-A3DReadEvidence -ImageLengthBytes $a.sourceLength -SourceToken $a.token -CandidateId $a.id -CandidateExtents $a.extent -MeterEvents (@($a.events)+@($b.events)) -ClaimedEventIds $b.ids -MaxPhysicalReadBytes 120000L
Assert-A7Receipt ($other.status -ceq 'unattributed' -and
    $other.reasons -contains 'origin.wrong_source' -and
    $other.originalIdentity -ceq 'unknown') 'cross_source_receipts_never_authenticate'
Assert-A7Receipt ($count -eq 2 -and $totalCandidateBytes -gt 0 -and
    $totalPhysical -le 240000L) 'two_generated_sources_and_one_cap_each'
Write-Host ('PASS: A7 standard C candidate source coverage, independent sources={0}, total physical={1}, full candidate reread bytes={2}, cross-source rejected, identity UNKNOWN; R7 partial, R8 blocked' -f
    $count,$totalPhysical,$totalCandidateBytes)
