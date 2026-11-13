#requires -Version 5.1
# Team B B4-03: read-free structural parent-to-dotdot observation join.
# Caller-supplied source events are never an A-issued source receipt.
. (Join-Path $PSScriptRoot 'DirectoryReadReconciliation.ps1')

function Test-ChappyBReturnedRecordCovered {
    param([object[]]$OuterReadEvents,[long]$At,[long]$Length=32)
    if($At -lt 0 -or $Length -ne 32){return $false}
    $cursor=$At;$end=$At+$Length
    foreach($ev in @($OuterReadEvents|Where-Object{
        $_.Consumer -ceq 'directory' -and [long]$_.ReturnedBytes -gt 0
    }|Sort-Object OffsetBytes)){
        $start=[long]$ev.OffsetBytes;$finish=$start+[long]$ev.ReturnedBytes
        if($finish -le $cursor){continue}
        if($start -gt $cursor){break}
        $cursor=[Math]::Min($end,$finish)
        if($cursor -ge $end){return $true}
    }
    return $false
}
function Test-ChappyBCompletedRecordSpan {
    param([object[]]$ReadSpans,[long]$Cluster,[long]$At)
    foreach($s in $ReadSpans){
        if([long]$s.cluster -eq $Cluster -and [long]$s.offsetBytes -le $At -and
            ([long]$s.offsetBytes+[long]$s.lengthBytes) -ge ($At+32L)){
            return $true
        }
    }
    return $false
}
function Get-ChappyBParentObservationV1 {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory=$true)][psobject]$DirectoryEnvelope,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$OuterReadEvents,
        [Parameter(Mandatory=$true)][ValidateRange(1,1073741824)][long]$SourceLengthBytes,
        [ValidateRange(1,32)][int]$MaxEdges=16,
        [ValidateRange(1,32)][int]$MaxSpans=16,
        [ValidateRange(1,512)][int]$MaxEvents=256
    )
    $metrics=[pscustomobject]@{
        parentEdgeCount=0;observedPairUnattested=0;ambiguousStructural=0
        unobservedUnknown=0;contradictedReadLedger=0;originalParentUnknown=0
        outerDirectoryReturnedBytes=$null;matchedCompletedSpans=0;additionalStreamReads=0
    }
    $result=[ordered]@{
        schemaVersion='b_parent_observation_v1';team='B'
        status='unknown';intervalJoin='not_established'
        sourceAuthenticity='not_proven'
        outerEventAuthority='caller_supplied_not_A_issued_receipt'
        originalIdentity='unknown';originalParent='unknown'
        originalPath='not_reconstructed';parentConfidence='partial'
        canExport=$false;canSelectFatCopy=$false
        parentObservations=@();reasons=@('b4_03_incomplete_or_invalid_evidence')
        metrics=$metrics
    }
    try{
        if($DirectoryEnvelope.schemaVersion -cne 'b_directory_evidence_v1' -or
            $DirectoryEnvelope.originalIdentity -cne 'unknown' -or
            $DirectoryEnvelope.sourceAuthority -cne 'B_scanner_report_unattested_not_A_receipt' -or
            $DirectoryEnvelope.canExport -or $DirectoryEnvelope.canSelectFatCopy -or
            $null -eq $DirectoryEnvelope.geometry -or
            $DirectoryEnvelope.geometry.attestation -cne 'unattested'){
            return [pscustomobject]$result
        }
        $edges=@($DirectoryEnvelope.parentEdges)
        $spans=@($DirectoryEnvelope.directoryReadSpans)
        $nodes=@($DirectoryEnvelope.nodes)
        $hints=@($DirectoryEnvelope.parentHints)
        if($edges.Count -gt $MaxEdges -or $spans.Count -gt $MaxSpans -or
            $OuterReadEvents.Count -gt $MaxEvents){
            $result.reasons=@('b4_03_candidate_or_event_cap_unknown')
            return [pscustomobject]$result
        }
        [long]$dataAt=$DirectoryEnvelope.geometry.dataOffsetBytes
        [long]$clusterBytes=$DirectoryEnvelope.geometry.clusterSizeBytes
        [long]$maxCluster=$DirectoryEnvelope.geometry.maxCluster
        if($dataAt -lt 0 -or $clusterBytes -lt 64 -or $clusterBytes -gt 131072 -or
            ($clusterBytes%32) -ne 0 -or $maxCluster -lt 2 -or
            $maxCluster -gt 1073741824 -or $dataAt -gt $SourceLengthBytes){
            $result.reasons=@('b4_03_geometry_invalid_unknown')
            return [pscustomobject]$result
        }
        $check=Compare-ChappyBDirectoryReturnedEvidenceV1 -DirectoryEnvelope $DirectoryEnvelope -OuterReadEvents $OuterReadEvents -SourceLengthBytes $SourceLengthBytes -MaxEvents $MaxEvents -MaxSpans $MaxSpans
        $result.intervalJoin=[string]$check.decision
        $result.metrics.outerDirectoryReturnedBytes=$check.metrics.outerDirectoryReturnedBytes
        $result.metrics.matchedCompletedSpans=[int]$check.metrics.matchingCompletedSpans
        if($check.decision -eq 'consistent_unattested'){
            $result.status='partial';$result.reasons=@('b4_03_consistent_intervals_not_source_attestation')
        }elseif($check.decision -eq 'contradicted'){
            $result.status='contradicted';$result.reasons=@('b4_03_outer_read_ledger_contradicted')
        }else{
            $result.status='unknown';$result.reasons=@('b4_03_physical_coverage_unknown')
        }
        $rows=New-Object System.Collections.ArrayList
        foreach($edge in $edges){
            [long]$parent=[long]$edge.parentCluster
            [long]$child=[long]$edge.childCluster
            [long]$entryAt=[long]$edge.entryOffsetBytes
            $relation=[string]$edge.relationStatus
            $dotdotAt=$null
            $observation='unobserved_unknown'
            $reason='b4_03_unobserved_or_incomplete'
            if($check.decision -eq 'contradicted'){
                $observation='contradicted_read_ledger'
                $reason='b4_03_b_vs_outer_source_contradicted'
            }elseif($check.decision -ne 'consistent_unattested'){
                $reason='b4_03_source_returns_unavailable'
            }elseif($edge.sourceAttestation -cne 'unattested' -or
                $edge.confidence -cne 'partial' -or $edge.originalIdentity -cne 'unknown'){
                $observation='ambiguous_structural'
                $reason='b4_03_untrusted_edge_grade'
            }elseif($parent -lt 2 -or $child -lt 2 -or $parent -gt $maxCluster -or
                $child -gt $maxCluster -or
                $dataAt+(($parent-2L)*$clusterBytes) -gt ($SourceLengthBytes-$clusterBytes) -or
                $dataAt+(($child-2L)*$clusterBytes) -gt ($SourceLengthBytes-$clusterBytes)){
                $observation='ambiguous_structural'
                $reason='b4_03_edge_cluster_out_of_geometry'
            }else{
                [long]$parentAt=$dataAt+(($parent-2L)*$clusterBytes)
                [long]$childAt=$dataAt+(($child-2L)*$clusterBytes)
                [long]$dotdot=$childAt+32L;$dotdotAt=$dotdot
                $sameChild=@($edges|Where-Object{[long]$_.childCluster -eq $child}).Count
                $matchHint=@($hints|Where-Object{
                    [long]$_.childCluster -eq $child -and
                    [long]$_.hintedParentCluster -eq $parent -and
                    $_.relationStatus -ceq 'hint_matches_directory_entry'
                }).Count
                $matchNode=@($nodes|Where-Object{
                    [long]$_.cluster -eq $child -and -not $_.isRoot -and
                    $_.linkStatus -ceq 'referenced_candidate'
                }).Count
                if($relation -cne 'parent_hint_corroborated' -or $sameChild -ne 1 -or
                    $matchHint -ne 1 -or $matchNode -ne 1 -or $parent -eq $child){
                    $observation='ambiguous_structural'
                    $reason='b4_03_conflicting_duplicate_cyclic_or_missing_hint'
                }elseif($entryAt -lt $parentAt -or
                    $entryAt -gt ($parentAt+$clusterBytes-32L) -or
                    (($entryAt-$parentAt)%32L) -ne 0 -or
                    -not (Test-ChappyBCompletedRecordSpan $spans $parent $entryAt) -or
                    -not (Test-ChappyBCompletedRecordSpan $spans $child $dotdot) -or
                    -not (Test-ChappyBReturnedRecordCovered $OuterReadEvents $entryAt 32) -or
                    -not (Test-ChappyBReturnedRecordCovered $OuterReadEvents $dotdot 32)){
                    $reason='b4_03_parent_entry_or_dotdot_not_physically_covered'
                }else{
                    $observation='observed_pair_unattested'
                    $reason='b4_03_both_structural_records_returned_not_original'
                }
            }
            if($relation -cnotmatch '^[a-z][a-z0-9_]{0,63}$'){$relation='unknown'}
            [void]$rows.Add([pscustomobject]@{
                parentCluster=$parent;childCluster=$child;entryOffsetBytes=$entryAt
                childDotDotOffsetBytes=$dotdotAt;relationStatus=$relation
                observation=$observation;confidence='partial'
                sourceAuthenticity='not_proven';originalIdentity='unknown'
                reasonCode=$reason
            })
        }
        $result.parentObservations=@($rows.ToArray())
        $result.metrics=[pscustomobject]@{
            parentEdgeCount=$result.parentObservations.Count
            observedPairUnattested=@($result.parentObservations|Where-Object{$_.observation -eq 'observed_pair_unattested'}).Count
            ambiguousStructural=@($result.parentObservations|Where-Object{$_.observation -eq 'ambiguous_structural'}).Count
            unobservedUnknown=@($result.parentObservations|Where-Object{$_.observation -eq 'unobserved_unknown'}).Count
            contradictedReadLedger=@($result.parentObservations|Where-Object{$_.observation -eq 'contradicted_read_ledger'}).Count
            originalParentUnknown=$result.parentObservations.Count
            outerDirectoryReturnedBytes=$check.metrics.outerDirectoryReturnedBytes
            matchedCompletedSpans=[int]$check.metrics.matchingCompletedSpans
            additionalStreamReads=0
        }
        if($edges.Count -eq 0){
            $result.reasons=@('b4_03_no_parent_assertion_original_unknown')
            if($check.decision -eq 'consistent_unattested'){$result.status='partial'}
        }
    }catch{
        # Do not expose raw exceptions, source buffers, names, or paths.
        $result.status='unknown';$result.intervalJoin='not_established'
        $result.parentObservations=@()
        $result.reasons=@('b4_03_bad_or_incomplete_structural_metadata')
        $result.metrics=$metrics
    }
    return [pscustomobject]$result
}
