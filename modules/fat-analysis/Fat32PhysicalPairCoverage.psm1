#Requires -Version 5.1
# Team D D6-04: no I/O; conservative paired-FAT coverage from returned-source events.
# Independent source events are caller supplied and MUST NOT be claimed A-attested.
Set-StrictMode -Version 2.0

function Get-ChappyFatPhysicalPairCoverage {
    <#
    .SYNOPSIS
    Reconcile D's successful read spans with independently captured returned
    Stream.Read spans; count complete 4-byte FAT entries only.
    .DESCRIPTION
    Pure numeric interpretation. Performs NO Stream/file/device I/O. Requires
    two ordered lists of successful returned-byte spans. Checks exact order,
    offsets, lengths, byte union and D summary; rejects inconsistent or
    incomplete-source evidence as UNKNOWN. External events are NOT verified
    A-issued receipts; all FAT geometry is caller-supplied/unverified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Observation,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$OuterReturnedEvents,
        [Parameter(Mandatory=$true)][long]$Fat1OffsetBytes,
        [Parameter(Mandatory=$true)][long]$Fat2OffsetBytes,
        [Parameter(Mandatory=$true)][long]$FatLengthBytes,
        [Parameter(Mandatory=$true)][long]$SourceLengthBytes,
        [ValidateRange(32,2048)][int]$MaxReturnedBytes=2048,
        [ValidateRange(1,256)][int]$MaxSuccessfulEvents=256
    )
    $reasons=New-Object System.Collections.ArrayList
    $observed1=New-Object 'System.Collections.Generic.HashSet[long]'
    $observed2=New-Object 'System.Collections.Generic.HashSet[long]'
    $physicalUnion=New-Object 'System.Collections.Generic.HashSet[long]'
    $actual=0L;$matched=$false
    $internal=@($Observation.readEvents)
    $outer=@($OuterReturnedEvents)
    $count=$outer.Count

    if($Observation.team -cne 'D' -or
       $Observation.mode -cne 'experimental_observed_fat_io_provenance' -or
       -not $Observation.experimentalDefaultOff -or $Observation.writePermitted -or
       $Observation.sourceDecision -cne 'not_selected' -or
       $null -ne $Observation.selectedCandidate){
        [void]$reasons.Add('input.not_D_read_only_observation')
    }
    if($SourceLengthBytes -lt 0 -or $Fat1OffsetBytes -lt 0 -or
       $Fat2OffsetBytes -lt 0 -or $FatLengthBytes -lt 12 -or
       ($Fat1OffsetBytes % 4) -ne 0 -or
       ($Fat2OffsetBytes % 4) -ne 0 -or
       ($FatLengthBytes % 4) -ne 0 -or
       $FatLengthBytes -gt $SourceLengthBytes){
        [void]$reasons.Add('geometry.invalid_or_unaligned')
    } elseif($Fat1OffsetBytes -gt ($SourceLengthBytes-$FatLengthBytes) -or
           $Fat2OffsetBytes -gt ($SourceLengthBytes-$FatLengthBytes)){
        [void]$reasons.Add('geometry.fat_regions_outside_source')
    } else {
        $end1=$Fat1OffsetBytes+$FatLengthBytes
        $end2=$Fat2OffsetBytes+$FatLengthBytes
        if($Fat1OffsetBytes -lt $end2 -and $Fat2OffsetBytes -lt $end1){
            [void]$reasons.Add('geometry.fat_regions_overlap')
        }
    }
    if($internal.Count -gt $MaxSuccessfulEvents -or
       $outer.Count -gt $MaxSuccessfulEvents -or
       $count -eq 0){
        [void]$reasons.Add('coverage.events_missing_or_exceed_cap')
    }
    if($internal.Count -ne $count){
        [void]$reasons.Add('source.event_count_mismatch')
    }
    # D13 intentionally budgets only 1024B for MBR+primary VBR, but the
    # older geometry parser expects four 512B sectors. After that phase cap
    # it labels *unread backup and FSInfo* as truncated/reject. These two
    # reason codes are NOT physical source EOF or BPB contradiction.
    # Permit only bounded NUMERIC arithmetic on explicitly unverified caller
    # FAT offsets when these are the sole reasons. Never promote BPB trust.
    $unobservedSecondaryCodes=@(
        'io.backup_vbr_truncated','io.fsinfo_truncated',
        'budget.backup_vbr_unread','budget.fsinfo_unread'
    )
    $hardReasons=@($Observation.geometryReasonCodes |
        Where-Object { $unobservedSecondaryCodes -cnotcontains [string]$_ })
    $geometryPhase=@($Observation.phaseSummaries |
        Where-Object {$_.phase -ceq 'geometry'})
    $secondaryUnreadOnly=(
        $Observation.geometryTrustDecision -ceq 'reject' -and
        $hardReasons.Count -eq 0 -and
        @($Observation.geometryReasonCodes).Count -gt 0 -and
        $Observation.metrics.phaseBudgetClipped -and
        $geometryPhase.Count -eq 1 -and
        [long]$geometryPhase[0].bytesRead -eq 1024
    )
    if($Observation.geometryTrustDecision -cne 'plausible_unverified' -and
       -not $secondaryUnreadOnly){
        [void]$reasons.Add('geometry.hard_contradiction_or_unread_primary_UNKNOWN')
    }
    if([long]$Observation.metrics.prematureSourceZeroReads -gt 0){
        [void]$reasons.Add('io.premature_source_zero_UNKNOWN')
    }
    if([long]$Observation.metrics.bytesRead -gt $MaxReturnedBytes){
        [void]$reasons.Add('budget.internal_bytes_over_cap')
    }

    # Only bounded event spans are enumerated, <=2048 distinct byte offsets.
    # If one event is invalid, refuse ALL numeric coverage, not just that event.
    if($reasons.Count -eq 0){
        $bad=$false
        for($i=0;$i -lt $count;$i++){
            try{
                $event=$outer[$i]
                $inner=$internal[$i]
                $at=[long]$event.OffsetBytes
                $n=[long]$event.ReturnedBytes
                $innerAt=[long]$inner.offsetBytes
                $innerN=[long]$inner.returnedBytes
                $endAt=[long]$inner.endExclusiveBytes
            } catch {
                [void]$reasons.Add('source.event_shape_invalid')
                $bad=$true;break
            }
            if($n -lt 1 -or $n -gt $MaxReturnedBytes -or
               $at -lt 0 -or $at -gt $SourceLengthBytes -or
               $n -gt ($SourceLengthBytes-$at) -or
               $actual -gt ($MaxReturnedBytes-$n)){
                [void]$reasons.Add('source.event_out_of_bounds_or_budget')
                $bad=$true;break
            }
            if($at -ne $innerAt -or $n -ne $innerN -or
               $endAt -ne ($at+$n)){
                [void]$reasons.Add('source.returned_span_disagrees_with_D')
                $bad=$true;break
            }
            for($j=0L;$j -lt $n;$j++){
                $position=[long]($at+$j)
                [void]$physicalUnion.Add($position)
                if($reasons.Count -eq 0 -and $FatLengthBytes -ge 12){
                    if($position -ge $Fat1OffsetBytes -and
                       $position -lt ($Fat1OffsetBytes+$FatLengthBytes)){
                        [void]$observed1.Add($position)
                    } elseif($position -ge $Fat2OffsetBytes -and
                             $position -lt ($Fat2OffsetBytes+$FatLengthBytes)){
                        [void]$observed2.Add($position)
                    }
                }
            }
            $actual+=$n
        }
        if(-not $bad){
            $unique=[long]$physicalUnion.Count
            if($actual -ne [long]$Observation.metrics.bytesRead -or
               $unique -ne [long]$Observation.metrics.uniquePhysicalBytes -or
               ($actual-$unique) -ne [long]$Observation.metrics.duplicatePhysicalBytes -or
               $count -ne [int]$Observation.metrics.successfulReadEvents){
                [void]$reasons.Add('source.accounting_disagrees_with_D')
            } else {
                $matched=$true
            }
        }
    }

    $complete1=New-Object 'System.Collections.Generic.HashSet[long]'
    $complete2=New-Object 'System.Collections.Generic.HashSet[long]'
    $paired=0L;$denominator=$null;$unobserved=$null
    $percentage=$null;$unknownPercentage=$null
    if($matched -and $reasons.Count -eq 0){
        $denominator=[long]($FatLengthBytes/4)
        foreach($pair in @(
            [pscustomobject]@{base=$Fat1OffsetBytes;bytes=$observed1;indices=$complete1},
            [pscustomobject]@{base=$Fat2OffsetBytes;bytes=$observed2;indices=$complete2}
        )){
            $indices=New-Object 'System.Collections.Generic.HashSet[long]'
            foreach($physical in $pair.bytes){
                [void]$indices.Add([long][Math]::Floor(($physical-$pair.base)/4.0))
            }
            foreach($entry in $indices){
                $offset=[long]($pair.base+$entry*4)
                if($pair.bytes.Contains($offset) -and
                   $pair.bytes.Contains(($offset+1L)) -and
                   $pair.bytes.Contains(($offset+2L)) -and
                   $pair.bytes.Contains(($offset+3L))){
                    [void]$pair.indices.Add([long]$entry)
                }
            }
        }
        foreach($idx in $complete1){
            if($complete2.Contains($idx)){$paired++}
        }
        $unobserved=[long]($denominator-$paired)
        $percentage=[Math]::Round(100.0*[double]$paired/[double]$denominator,8)
        $unknownPercentage=[Math]::Round(100.0-$percentage,8)
    }
    if($matched -and $reasons.Count -eq 0){
        [void]$reasons.Add('coverage.only_returned_4byte_pairs_observed')
    }
    return [pscustomobject]@{
        schemaVersion='1';team='D'
        mode='read_only_unattested_physical_FAT_pair_coverage'
        status=$(if($matched){'partial_numeric_candidate_only'}else{'unknown'})
        externalEventAgreement=$matched
        scanIncomplete=$true
        sourceReadProvenance='outer_events_caller_supplied_NOT_A_attested'
        geometryProvenance='caller_supplied_unverified'
        originalIdentity='unknown';fileOwner='unknown'
        fatCopyWinner='not_selected';sourceDecision='not_selected'
        writePermitted=$false;wholeFatVerified=$false
        reasons=@($reasons.ToArray())
        warnings=@(
            'source.outer_event_list_not_A_issued_attestation',
            'geometry.numeric_offsets_not_authenticated',
            'fat.remote_unobserved_UNKNOWN_not_clean',
            'coverage.paired_not_original_file_integrity',
            'real_master_img_trial_not_authorized'
        )
        metrics=[pscustomobject]@{
            externalSuccessfulReadEvents=$count
            physicalReturnedBytes=$(if($matched){$actual}else{$null})
            physicalUniqueBytes=$(if($matched){[long]$physicalUnion.Count}else{$null})
            physicalRepeatedBytes=$(if($matched){($actual-[long]$physicalUnion.Count)}else{$null})
            totalDeclaredFatEntriesPerCopy=$denominator
            fullyObservedFat1Entries=$(if($matched){[long]$complete1.Count}else{$null})
            fullyObservedFat2Entries=$(if($matched){[long]$complete2.Count}else{$null})
            pairedFullyObservedEntries=$(if($matched){$paired}else{$null})
            unobservedPairedEntryIndices=$unobserved
            pairedCoveragePercent=$percentage
            unobservedPairPercent=$unknownPercentage
            maxReturnedBytes=$MaxReturnedBytes
            maxSuccessfulEvents=$MaxSuccessfulEvents
        }
    }
}
Export-ModuleMember -Function Get-ChappyFatPhysicalPairCoverage
