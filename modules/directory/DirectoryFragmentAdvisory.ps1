#requires -Version 5.1
# B -> C5-03: read-free advisory after C's original two-fragment search.
# Never ranks, removes, selects, reconstructs or authenticates an original file.
. (Join-Path $PSScriptRoot 'DirectoryParentObservationJoin.ps1')

function Get-ChappyBFragmentAdvisoryV1 {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory)][psobject]$DirectoryEnvelope,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$OuterReadEvents,
        [Parameter(Mandatory)][psobject]$FragmentReport,
        [Parameter(Mandatory)][ValidateRange(1,1073741824)][long]$SourceLengthBytes,
        [switch]$EnableBFragmentAdvisory,
        [ValidateRange(1,32)][int]$MaxDirectoryCandidates=32,
        [ValidateRange(1,16)][int]$MaxFragmentCandidates=16,
        [ValidateRange(1,32)][int]$MaxSpans=16,
        [ValidateRange(1,256)][int]$MaxEvents=256
    )
    $empty=[pscustomobject]@{cCandidateCount=0;annotatedCount=0;sizeConsistentUnattested=0;sizeConflictUnknown=0;entryUnobservedUnknown=0;sourceUnknown=0;additionalSourceReadCalls=0;additionalSourceReturnedBytes=0;bDirectoryReturnedBytes=$null}
    $out=[ordered]@{
        schemaVersion='b_fragment_advisory_v1';team='B';status='disabled'
        decision='unknown';originalIdentity='unknown';originalParent='unknown'
        originalPath='not_reconstructed';sourceAuthenticity='not_proven'
        externalEventAuthority='caller_supplied_not_A_receipt'
        originalSha='not_tested';canSelectOriginal=$false;canExport=$false
        canSelectFatCopy=$false;advisoryOnly=$true
        annotations=@();warnings=@('bc503_explicit_optin_required');metrics=$empty
    }
    if(-not $EnableBFragmentAdvisory){return [pscustomobject]$out}
    $out.status='unknown'
    $out.warnings=@('bc503_incomplete_or_untrusted_input')
    try{
        if($DirectoryEnvelope.schemaVersion -cne 'b_directory_evidence_v1' -or
           $DirectoryEnvelope.team -cne 'B' -or
           $DirectoryEnvelope.sourceAuthority -cne 'B_scanner_report_unattested_not_A_receipt' -or
           $DirectoryEnvelope.originalIdentity -cne 'unknown' -or
           $DirectoryEnvelope.canExport -or $DirectoryEnvelope.canSelectFatCopy -or
           $null -eq $DirectoryEnvelope.geometry -or
           $DirectoryEnvelope.geometry.attestation -cne 'unattested' -or
           $null -eq $DirectoryEnvelope.metrics -or
           $DirectoryEnvelope.metrics.sourceReadAttestation -cne 'unattested' -or
           $FragmentReport.schemaVersion -cne '1' -or
           $FragmentReport.team -cne 'C' -or
           $FragmentReport.originalIdentity -cne 'unknown' -or
           $null -ne $FragmentReport.selectedOriginal -or $FragmentReport.canAutoSelectOriginal){
            return [pscustomobject]$out
        }
        $candidates=@($FragmentReport.items)
        $bCandidates=@($DirectoryEnvelope.candidates)
        $spans=@($DirectoryEnvelope.directoryReadSpans)
        $edges=@($DirectoryEnvelope.parentEdges)
        if($candidates.Count -gt $MaxFragmentCandidates -or
           $bCandidates.Count -gt $MaxDirectoryCandidates -or
           $spans.Count -gt $MaxSpans -or $OuterReadEvents.Count -gt $MaxEvents -or
           $edges.Count -gt 16){
            $out.warnings=@('bc503_metadata_cap_unknown')
            return [pscustomobject]$out
        }
        if($FragmentReport.status -cne 'ok' -or
           $DirectoryEnvelope.status -eq 'error'){
            $out.warnings=@('bc503_fragment_or_directory_incomplete_unknown')
            return [pscustomobject]$out
        }
        [long]$clusterSize=$DirectoryEnvelope.geometry.clusterSizeBytes
        [long]$dataAt=$DirectoryEnvelope.geometry.dataOffsetBytes
        [long]$maxCluster=$DirectoryEnvelope.geometry.maxCluster
        if($clusterSize -lt 64 -or $clusterSize -gt 131072 -or
           $dataAt -lt 0 -or $dataAt -gt $SourceLengthBytes -or
           $maxCluster -lt 2 -or $maxCluster -gt 1073741824){
            $out.warnings=@('bc503_geometry_unknown')
            return [pscustomobject]$out
        }
        $match=Compare-ChappyBDirectoryReturnedEvidenceV1 -DirectoryEnvelope $DirectoryEnvelope -OuterReadEvents $OuterReadEvents -SourceLengthBytes $SourceLengthBytes -MaxEvents $MaxEvents -MaxSpans $MaxSpans
        $safe=($match.decision -ceq 'consistent_unattested' -and
               [long]$DirectoryEnvelope.metrics.bIncompleteReturnedBytes -eq 0 -and
               $edges.Count -eq 0)
        $out.status=$(if($safe){'partial'}else{'unknown'})
        $out.warnings=$(if($safe){@('bc503_observed_metadata_not_source_attestation')}else{@('bc503_outer_or_parent_record_unknown')})
        $items=New-Object System.Collections.ArrayList
        $yes=0;$no=0;$missing=0;$uncertain=0
        for($i=0;$i -lt $candidates.Count;$i++){
            $c=$candidates[$i]
            $status='source_coverage_unknown';$reason='bc503_not_source_authenticated'
            if($safe){
                $status='entry_unobserved_unknown'
                $reason='bc503_unobserved_first_cluster'
                if($c.format -ceq '3mf' -and $c.possible -eq $true -and
                   $c.originalIdentity -ceq 'unknown' -and
                   $c.integrityScope -ceq 'structural_only_not_original_file_integrity' -and
                   [long]$c.firstOffset -ge 0 -and [long]$c.firstBytes -gt 0 -and
                   [long]$c.secondOffset -ge 0 -and [long]$c.secondBytes -gt 0 -and
                   [long]$c.firstOffset -le ($SourceLengthBytes-[long]$c.firstBytes) -and
                   [long]$c.secondOffset -le ($SourceLengthBytes-[long]$c.secondBytes) -and
                   [long]$c.lengthBytes -eq ([long]$c.firstBytes+[long]$c.secondBytes)){
                    $found=New-Object System.Collections.ArrayList
                    foreach($bc in $bCandidates){
                        if($bc.deleted -or $bc.isDirectory -or
                           $bc.originalIdentity -cne 'unknown'){continue}
                        [long]$start=[long]$bc.startCluster
                        [long]$parent=[long]$bc.containerCluster
                        [long]$at=[long]$bc.entryOffsetBytes
                        if($start -lt 2 -or $start -gt $maxCluster -or
                           $parent -lt 2 -or $parent -gt $maxCluster){continue}
                        if($dataAt+(($start-2L)*$clusterSize) -ne [long]$c.firstOffset){continue}
                        if(-not (Test-ChappyBCompletedRecordSpan $spans $parent $at) -or
                           -not (Test-ChappyBReturnedRecordCovered $OuterReadEvents $at 32)){continue}
                        [void]$found.Add($bc)
                    }
                    if($found.Count -eq 1){
                        [long]$size=$found[0].sizeBytes
                        if($size -gt 0 -and $size -eq [long]$c.lengthBytes){
                            $status='size_consistent_unattested'
                            $reason='bc503_size_agrees_but_not_original'
                        }elseif($size -gt 0){
                            $status='size_conflict_unknown'
                            $reason='bc503_size_disagrees_no_candidate_veto'
                        }else{$reason='bc503_size_not_observed'}
                    }elseif($found.Count -gt 1){$reason='bc503_duplicate_b_entries_unknown'}
                }else{$reason='bc503_malformed_or_unavailable_c_candidate'}
            }
            switch($status){
                'size_consistent_unattested' {$yes++}
                'size_conflict_unknown' {$no++}
                'entry_unobserved_unknown' {$missing++}
                default {$uncertain++}
            }
            [void]$items.Add([pscustomobject]@{
                cCandidateIndex=[int]$i;relation=$status;reasonCode=$reason
                originalIdentity='unknown';sourceAuthenticity='not_proven'
                canSelectOriginal=$false
            })
        }
        $out.annotations=@($items.ToArray())
        $out.metrics=[pscustomobject]@{
            cCandidateCount=$candidates.Count;annotatedCount=$items.Count
            sizeConsistentUnattested=$yes;sizeConflictUnknown=$no
            entryUnobservedUnknown=$missing;sourceUnknown=$uncertain
            additionalSourceReadCalls=0;additionalSourceReturnedBytes=0
            bDirectoryReturnedBytes=$match.metrics.outerDirectoryReturnedBytes
        }
        $out.decision=$(if($safe){'advisory_only'}else{'unknown'})
    }catch{
        # No raw exception, source data, actual name or user path in output.
        $out.status='unknown';$out.decision='unknown'
        $out.annotations=@();$out.warnings=@('bc503_bad_input_unknown')
        $out.metrics=$empty
    }
    return [pscustomobject]$out
}
