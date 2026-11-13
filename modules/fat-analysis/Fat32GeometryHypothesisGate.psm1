#Requires -Version 5.1
# Team D gate D6-03: guarded read-only VBR/backup hypotheses.
# Never chooses a FAT source, an original owner, or a repair target.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Fat32VbrDisagreement.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Fat32ObservedIoEvidence.psm1') -Force

if(-not ('ChappyD603PhysicalReadCallGate' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class ChappyD603PhysicalReadCallGate : Stream {
    readonly Stream source;
    readonly int cap;
    long count=0,refused=0;
    public ChappyD603PhysicalReadCallGate(Stream input,int maxCalls) {
        if(input==null||!input.CanRead||!input.CanSeek||input.CanWrite)
            throw new ArgumentException("Strictly nonwritable seekable Stream required");
        if(maxCalls<4||maxCalls>256)
            throw new ArgumentException("Physical call limit must be 4..256");
        source=input;cap=maxCalls;
    }
    public long PhysicalReadCalls {get{return count;}}
    public long RefusedReadCalls {get{return refused;}}
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return source.Length;}}
    public override long Position {get{return source.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long o,SeekOrigin origin){return source.Seek(o,origin);}
    public override int Read(byte[] b,int off,int n) {
        if(b==null||off<0||n<0||off>b.Length-n)throw new ArgumentException("Bad Read");
        if(count>=cap){refused++;throw new IOException("d603.physical_read_cap");}
        count++;
        return source.Read(b,off,n);
    }
    public override void Flush(){}
    public override void SetLength(long x){throw new NotSupportedException();}
    public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
    protected override void Dispose(bool disposing){base.Dispose(disposing);}
}
'@
}

function Get-ChappyFatGeometryHypothesisGate {
    <#
    .SYNOPSIS
    Deny automatic FAT-region probing when primary/backup BPB hypotheses
    disagree or are unreadable. Both matching candidates remain unverified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [ValidateRange(0,3)][int]$PartitionIndex=0,
        [ValidateRange(512,2048)][int]$MaxReadBytes=2048,
        [ValidateRange(4,256)][int]$MaxPhysicalReadCalls=256
    )
    if($null -eq $Stream -or -not $Stream.CanRead -or
       -not $Stream.CanSeek -or $Stream.CanWrite) {
        throw 'Strictly nonwritable readable seekable source required'
    }
    $quota=[ChappyD603PhysicalReadCallGate]::new($Stream,$MaxPhysicalReadCalls)
    $trace=[ChappyD13TraceStream]::new($quota,[long]$MaxReadBytes)
    $trace.BeginPhase('geometry_hypotheses',[long]$MaxReadBytes)
    $comparison=$null
    $reasons=New-Object System.Collections.ArrayList
    try {
        $args=@{Stream=$trace;PartitionIndex=$PartitionIndex;MaxReadBytes=$MaxReadBytes}
        $comparison=Get-ChappyFatVbrDisagreement @args
    } catch {
        [void]$reasons.Add('io.bounded_structure_observation_failed')
    }
    $hypotheses=New-Object System.Collections.ArrayList
    $grades=New-Object System.Collections.ArrayList
    $agreement='insufficient_evidence'
    if($null -ne $comparison){
        $agreement=[string]$comparison.agreement
        foreach($c in @($comparison.candidates)){
            [void]$grades.Add([string]$c.plausibility)
            [void]$hypotheses.Add([pscustomobject]@{
                sourceRole=[string]$c.sourceRole
                locatorTrust='primary_declared_unverified'
                probeOffsetBytes=$c.probeOffsetBytes
                plausibility=[string]$c.plausibility
                contradictionCodes=@($c.reasonCodes)
                unknownCodes=@($c.unknownCodes)
                numericGeometry=[pscustomobject]@{
                    fat1OffsetBytes=$c.geometry.fat1OffsetBytes
                    fat2OffsetBytes=$c.geometry.fat2OffsetBytes
                    fatLengthBytes=$c.geometry.fatLengthBytes
                    dataClusterCount=$c.geometry.dataClusterCount
                    rootCluster=$c.geometry.rootCluster
                    bytesPerSector=$c.geometry.bytesPerSector
                    sectorsPerCluster=$c.geometry.sectorsPerCluster
                }
                sourceIdentity='unknown'
            })
        }
    }
    # Even if the caller's source stops or the physical read-call ceiling
    # aborts parsing, preserve a stable two-role result. These are explicitly
    # UNKNOWN placeholders, never reconstructed or preferred geometries.
    if($null -eq $comparison){
        foreach($role in @('primary','backup')){
            [void]$hypotheses.Add([pscustomobject]@{
                sourceRole=$role;locatorTrust='unobserved'
                probeOffsetBytes=$null
                plausibility='insufficient_evidence'
                contradictionCodes=@()
                unknownCodes=@('io.bounded_structure_observation_failed')
                numericGeometry=[pscustomobject]@{
                    fat1OffsetBytes=$null;fat2OffsetBytes=$null
                    fatLengthBytes=$null;dataClusterCount=$null
                    rootCluster=$null;bytesPerSector=$null
                    sectorsPerCluster=$null
                }
                sourceIdentity='unknown'
            })
        }
    }
    $gate='blocked_insufficient_evidence'
    if($null -eq $comparison -or $trace.ZeroBeforeDeclaredEnd -gt 0 -or
       $quota.RefusedReadCalls -gt 0) {
        [void]$reasons.Add('io.physical_source_incomplete')
    } elseif($grades -contains 'contradicted'){
        $gate='blocked_contradicted_geometry'
        [void]$reasons.Add('geometry.one_or_both_hypotheses_contradicted')
    } elseif($agreement -eq 'disagree'){
        $gate='blocked_conflicting_geometry'
        [void]$reasons.Add('geometry.primary_backup_disagree')
        [void]$reasons.Add('fat.auto_probe_refused_conflicting_geometry')
    } elseif($agreement -eq 'agree' -and $grades.Count -eq 2 -and
           $grades[0] -eq 'plausible_unverified' -and
           $grades[1] -eq 'plausible_unverified' -and
           -not $comparison.scanIncomplete){
        $gate='candidate_geometry_unverified'
        [void]$reasons.Add('geometry.match_only_not_authenticity')
    } else {
        [void]$reasons.Add('geometry.unresolved_or_unread')
    }
    if($gate -eq 'blocked_insufficient_evidence'){
        [void]$reasons.Add('fat.auto_probe_refused_unknown_geometry')
    }
    $observed=@($trace.GetUniqueRanges() | ForEach-Object {
        [pscustomobject]@{
            offsetBytes=[long]$_.StartOffset
            lengthBytes=[long]$_.Length
            endExclusiveBytes=[long]($_.StartOffset+$_.Length)
        }
    })
    $actual=[long]$trace.ActualBytes
    $unique=[long]$trace.UniqueBytes
    # A numeric match is not permission to seek FAT offsets. All execution
    # paths only invoked the existing four structural-sector comparison.
    return [pscustomobject]@{
        schemaVersion='1';team='D';mode='read_only_geometry_hypothesis_refusal'
        gateDecision=$gate;agreement=$agreement
        # A complete read can still contain contradictory hypotheses.
        # Do not turn logical disagreement into fabricated physical EOF.
        scanIncomplete=($null -eq $comparison -or
            $comparison.scanIncomplete -or $trace.ZeroBeforeDeclaredEnd -gt 0 -or
            $quota.RefusedReadCalls -gt 0)
        geometryUnresolved=($gate -ne 'candidate_geometry_unverified')
        matchedNumericHypotheses=($gate -eq 'candidate_geometry_unverified')
        geometryAuthenticity='unknown';originalIdentity='unknown'
        sourceDecision='not_selected';selectedCandidate=$null
        fatReadAllowed=$false;writePermitted=$false;fatRegionProbeCount=0
        sourceReadProvenance='internal_not_A_attested'
        hypotheses=@($hypotheses.ToArray())
        reasonCodes=@($reasons.ToArray())
        warnings=@(
            'backup.locator_from_primary_unverified',
            'geometry.no_automatic_fat_followup',
            'geometry.duplicate_boot_records_not_authenticity',
            'source.physical_read_ranges_internal_not_A_receipts',
            'real_master_img_trial_not_authorized'
        )
        observedReadRanges=@($observed)
        metrics=[pscustomobject]@{
            actualReturnedBytes=$actual
            uniqueReturnedBytes=$unique
            repeatedReturnedBytes=($actual-$unique)
            physicalReadCalls=[long]$quota.PhysicalReadCalls
            totalReadRequests=[long]$trace.ReadRequests
            prematureSourceZeroReads=[long]$trace.ZeroBeforeDeclaredEnd
            refusedReadCalls=[long]$quota.RefusedReadCalls
            maxReadBytes=$MaxReadBytes;maxPhysicalReadCalls=$MaxPhysicalReadCalls
            readByteBudgetClipped=$trace.GlobalClipped
            distinctObservedSourceRanges=$observed.Count
            fatRegionReads=0
        }
    }
}
Export-ModuleMember -Function Get-ChappyFatGeometryHypothesisGate
