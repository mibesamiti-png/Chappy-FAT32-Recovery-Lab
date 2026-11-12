#Requires -Version 5.1
# Team D #73: experimental observed-I/O provenance. No paths, repair, or writer.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Fat32GeometryTrust.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Fat32MirrorWindows.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Fat32ChainStats.psm1') -Force
if (-not ('ChappyD13TraceStream' -as [type])) {
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class ChappyD13ReadEvent {
    public long StartOffset {get;set;}
    public int ReturnedBytes {get;set;}
    public string Phase {get;set;}
    public int ReadIndex {get;set;}
}
public sealed class ChappyD13UniqueRange {
    public long StartOffset {get;set;}
    public long Length {get;set;}
}
public sealed class ChappyD13TraceStream : Stream {
    private readonly Stream source;
    private readonly long limit;
    private readonly HashSet<long> unique=new HashSet<long>();
    private readonly List<ChappyD13ReadEvent> events=new List<ChappyD13ReadEvent>();
    private string phase="";
    private long phaseCap=0;
    private long phaseUsed=0;
    private long used=0;
    private long requests=0;
    private long earlyZero=0;
    private bool globalClipped=false;
    private bool phaseClipped=false;
    public ChappyD13TraceStream(Stream stream,long budget) {
        if(stream==null||!stream.CanRead||!stream.CanSeek||stream.CanWrite)
            throw new ArgumentException("Strict nonwritable readable seekable input required");
        if(budget<32||budget>2048)throw new ArgumentOutOfRangeException("budget");
        source=stream;limit=budget;
    }
    public void BeginPhase(string name,long budget) {
        if(String.IsNullOrEmpty(name)||name.Length>48||budget<0||budget>2048)
            throw new ArgumentException("Invalid phase");
        foreach(char c in name)if(!((c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='_'))
            throw new ArgumentException("Unsafe phase name");
        phase=name;phaseCap=budget;phaseUsed=0;
    }
    public ChappyD13ReadEvent[] GetEvents(){return events.ToArray();}
    public ChappyD13UniqueRange[] GetUniqueRanges(){
        List<long> offsets=new List<long>(unique);offsets.Sort();
        List<ChappyD13UniqueRange> output=new List<ChappyD13UniqueRange>();
        if(offsets.Count==0)return output.ToArray();
        long first=offsets[0],last=first;
        for(int i=1;i<offsets.Count;i++){
            long next=offsets[i];
            if(next==last+1){last=next;continue;}
            output.Add(new ChappyD13UniqueRange {StartOffset=first,Length=last-first+1});
            first=next;last=next;
        }
        output.Add(new ChappyD13UniqueRange {StartOffset=first,Length=last-first+1});
        return output.ToArray();
    }
    public long ActualBytes {get{return used;}}
    public long PhaseBytes {get{return phaseUsed;}}
    public long UniqueBytes {get{return unique.Count;}}
    public long ReadRequests {get{return requests;}}
    public long ZeroBeforeDeclaredEnd {get{return earlyZero;}}
    public bool GlobalClipped {get{return globalClipped;}}
    public bool PhaseClipped {get{return phaseClipped;}}
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return source.Length;}}
    public override long Position {get{return source.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long offset,SeekOrigin origin){return source.Seek(offset,origin);}
    public override int Read(byte[] buffer,int offset,int count) {
        if(String.IsNullOrEmpty(phase))throw new InvalidOperationException("BeginPhase required");
        if(count<0)throw new ArgumentOutOfRangeException("count");
        requests++;
        long remainGlobal=limit-used,remainPhase=phaseCap-phaseUsed;
        if(remainGlobal<count)globalClipped=true;
        if(remainPhase<count)phaseClipped=true;
        long allowed=Math.Min(count,Math.Min(remainGlobal,remainPhase));
        if(allowed<=0)return 0;
        long at=source.Position;
        int got=source.Read(buffer,offset,(int)allowed);
        if(got==0&&at<source.Length)earlyZero++;
        if(got>0){
            used+=got;phaseUsed+=got;
            events.Add(new ChappyD13ReadEvent{
                StartOffset=at,ReturnedBytes=got,Phase=phase,ReadIndex=events.Count
            });
            for(int i=0;i<got;i++)unique.Add(at+i);
        }
        return got;
    }
    public override void Flush(){}
    public override void SetLength(long length){throw new NotSupportedException();}
    public override void Write(byte[] buffer,int offset,int count){throw new NotSupportedException();}
    // The input Stream belongs to the caller; never close it.
}
'@
}

function Get-ChappyFatObservedIoEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [ValidateSet('MirrorOnly','MirrorAndChain')][string]$Mode='MirrorOnly',
        [ValidateRange(32,2048)][int]$MaxReadBytes=2048
    )
    if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite){
        throw 'Strictly nonwritable readable seekable input Stream required'
    }
    $trace=[ChappyD13TraceStream]::new($Stream,[long]$MaxReadBytes)
    $phases=New-Object System.Collections.ArrayList
    $reasons=New-Object System.Collections.ArrayList
    $geometry=$null;$mirror=$null;$fat1=0L;$fat2=0L;$fatSize=0L
    $cycles=0;$traces=0;$incompleteTraces=0
    $trace.BeginPhase('geometry',1024)
    try{$geometry=Get-ChappyFatGeometryTrust -Stream $trace}
    catch{[void]$reasons.Add('geometry.parser_failed')}
    [void]$phases.Add([pscustomobject]@{
        phase='geometry';producer='fat_geometry_trust';probeStartCluster=$null
        bytesRead=[long]$trace.PhaseBytes
    })
    if($null -eq $geometry -or $null -eq $geometry.geometry -or
       $null -eq $geometry.geometry.fat1OffsetBytes -or
       $null -eq $geometry.geometry.fat2OffsetBytes -or
       $null -eq $geometry.geometry.fatLengthBytes -or
       $null -eq $geometry.geometry.dataClusterCount){
        [void]$reasons.Add('geometry.numeric_values_unavailable')
    }else{
        $fat1=[long]$geometry.geometry.fat1OffsetBytes
        $fat2=[long]$geometry.geometry.fat2OffsetBytes
        $fatSize=[long]$geometry.geometry.fatLengthBytes
        $params=@{
            Stream=$trace;Fat1OffsetBytes=$fat1;Fat2OffsetBytes=$fat2
            FatLengthBytes=$fatSize;StartEntry=0L;MaxWindows=1
        }
        $mirrorBudget=$(if($Mode -eq 'MirrorOnly'){1024}else{512})
        $trace.BeginPhase('mirror_window_0',$mirrorBudget)
        try{
            $mirror=Get-ChappyFatMirrorWindows @params -WindowEntries $(if($Mode -eq 'MirrorOnly'){128}else{64}) -MaxReadBytes $mirrorBudget
        }catch{[void]$reasons.Add('mirror.read_failed_or_invalid_geometry')}
        [void]$phases.Add([pscustomobject]@{
            phase='mirror_window_0';producer='fat_mirror_windows'
            probeStartCluster=$null;bytesRead=[long]$trace.PhaseBytes
        })
        if($Mode -eq 'MirrorAndChain'){
            # Predetermined 2..8, never provided by the truth/scorer.
            for($start=2;$start -le 8;$start++){
                $phase='chain_probe_'+$start
                $trace.BeginPhase($phase,64)
                $args=@{
                    Stream=$trace;Fat1OffsetBytes=$fat1;Fat2OffsetBytes=$fat2
                    FatLengthBytes=$fatSize
                    MaxDataCluster=([long]$geometry.geometry.dataClusterCount+1L)
                    StartClusters=@([long]$start)
                    MaxStepsPerChain=8;MaxTotalEntries=8;MaxReadBytes=64
                }
                try{
                    $result=Get-ChappyFatChainAnomalyStats @args
                    $cycles+=@($result.items|Where-Object {$_.terminal -eq 'cycle'}).Count
                    $incompleteTraces+=@($result.items|Where-Object {$_.scanIncomplete}).Count
                    $traces+=@($result.items).Count
                }catch{[void]$reasons.Add('chain.probe_failed_or_invalid_geometry')}
                [void]$phases.Add([pscustomobject]@{
                    phase=$phase;producer='fat_chain_anomaly_stats'
                    probeStartCluster=$start;bytesRead=[long]$trace.PhaseBytes
                })
            }
        }
    }
    $events=New-Object System.Collections.ArrayList
    foreach($e in $trace.GetEvents()){
        $end=[long]($e.StartOffset+$e.ReturnedBytes)
        $copy=$null
        if($fatSize -gt 0 -and $e.Phase -ne 'geometry'){
            if($e.StartOffset -ge $fat1 -and $end -le ($fat1+$fatSize)){$copy=0}
            elseif($e.StartOffset -ge $fat2 -and $end -le ($fat2+$fatSize)){$copy=1}
        }
        [void]$events.Add([pscustomobject]@{
            evidenceId=('D13-{0:D4}' -f $e.ReadIndex)
            phase=$e.Phase;offsetBytes=[long]$e.StartOffset
            endExclusiveBytes=$end;returnedBytes=$e.ReturnedBytes
            fatCopyIndex=$copy;provenance='observed_stream_read'
        })
    }
    $ranges=New-Object System.Collections.ArrayList
    foreach($span in $trace.GetUniqueRanges()){
        [void]$ranges.Add([pscustomobject]@{
            offsetBytes=[long]$span.StartOffset
            endExclusiveBytes=[long]($span.StartOffset+$span.Length)
            lengthBytes=[long]$span.Length
        })
    }
    $decision=$(if($null -eq $geometry){'unknown'}else{[string]$geometry.trustDecision})
    if($decision -ne 'trusted'){[void]$reasons.Add('geometry.not_authenticated')}
    if($null -eq $mirror){[void]$reasons.Add('mirror.not_observed')}
    elseif($mirror.scanIncomplete){[void]$reasons.Add('coverage.fat_window_not_whole_fat')}
    if($incompleteTraces -gt 0){[void]$reasons.Add('coverage.chain_probes_incomplete')}
    if($trace.GlobalClipped){[void]$reasons.Add('budget.global_source_cap')}
    if($trace.PhaseClipped){[void]$reasons.Add('budget.phase_source_cap')}
    if($trace.ZeroBeforeDeclaredEnd -gt 0){[void]$reasons.Add('io.stopped_before_advertised_length')}
    $incomplete=($null -eq $mirror -or $mirror.scanIncomplete -or
        $incompleteTraces -gt 0 -or $trace.GlobalClipped -or
        $trace.PhaseClipped -or $trace.ZeroBeforeDeclaredEnd -gt 0)
    return [pscustomobject]@{
        schemaVersion='1';team='D'
        mode='experimental_observed_fat_io_provenance'
        experimentMode=$Mode;experimentalDefaultOff=$true
        status=$(if($incomplete){'partial'}else{'ok'})
        scanIncomplete=$incomplete
        geometryTrustDecision=$decision
        sourceDecision='not_selected';selectedCandidate=$null;writePermitted=$false
        evidence=[pscustomobject]@{
            mirrorDifferentEntries=$(if($null -eq $mirror){$null}else{[long]$mirror.metrics.differentEntries})
            observedCycles=$cycles
            incompleteChainTraces=$incompleteTraces;inspectedChainTraces=$traces
        }
        readEvents=@($events.ToArray())
        uniqueReadRanges=@($ranges.ToArray())
        phaseSummaries=@($phases.ToArray())
        warnings=@('geometry.numeric_positions_unverified',
            'coverage.read_spans_not_file_content',
            'fat.mirror_agreement_not_integrity',
            'fat.crosslinks_require_independent_owner_provenance',
            'source.no_fat_winner_or_repair',
            'real_master_img_trial_not_authorized')
        reasonCodes=@($reasons.ToArray());errors=@()
        metrics=[pscustomobject]@{
            bytesRead=[long]$trace.ActualBytes
            uniquePhysicalBytes=[long]$trace.UniqueBytes
            duplicatePhysicalBytes=[long]($trace.ActualBytes-$trace.UniqueBytes)
            readRequests=[long]$trace.ReadRequests
            successfulReadEvents=$events.Count
            uniqueRanges=$ranges.Count
            maximumGlobalReadBytes=$MaxReadBytes
            totalReadCapShared=$true
            globalBudgetClipped=$trace.GlobalClipped
            phaseBudgetClipped=$trace.PhaseClipped
            prematureSourceZeroReads=[long]$trace.ZeroBeforeDeclaredEnd
        }
    }
}
Export-ModuleMember -Function Get-ChappyFatObservedIoEvidence
