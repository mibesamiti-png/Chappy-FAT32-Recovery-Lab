#Requires -Version 5.1
# D6-04: pure, deny-by-default comparison of guarded D successful-return
# events against a separate caller-provided outer Stream.Read event transcript.
# Does not read an image; does not issue or verify A source receipts.
Set-StrictMode -Version 2.0

function Compare-ChappyFatGuardedReturnedSourceEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$GuardedResult,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$OuterReturnedEvents,
        [Parameter(Mandatory=$true)][long]$SourceLengthBytes,
        [ValidateRange(-1,512)][long]$OuterPhysicalReadCalls=-1,
        [ValidateRange(-1,512)][long]$OuterPrematureZeroReads=-1,
        [ValidateRange(2048,4096)][int]$MaxReturnedBytes=4096,
        [ValidateRange(1,512)][int]$MaxSuccessfulEvents=512
    )
    $out=[ordered]@{
        schemaVersion='1';team='D'
        mode='read_only_guarded_fat_outer_returned_source_join'
        decision='unknown';outerEventAgreement=$false
        sourceAuthenticity='not_proven'
        sourceReadProvenance='caller_outer_events_NOT_A_attested'
        geometryAuthenticity='unknown'
        originalIdentity='unknown';fileOwner='unknown'
        fatCopyWinner='not_selected';sourceDecision='not_selected'
        selectedCandidate=$null;writePermitted=$false
        canRepair=$false;canExport=$false;wholeFatVerified=$false
        scanIncomplete=$true
        reasonCodes=@('d604.source_event_join_unavailable_UNKNOWN')
        warnings=@(
            'd604.caller_event_list_cannot_authenticate_A_source',
            'd604.candidate_geometry_not_volume_truth',
            'd604.unobserved_remote_FAT_indices_UNKNOWN',
            'd604.no_original_owner_or_FAT_copy_winner'
        )
        metrics=[pscustomobject]@{
            actualReturnedBytes=$null;uniqueReturnedBytes=$null
            repeatedReturnedBytes=$null;successfulReadEvents=$null
            geometryReturnedBytes=$null;fatFixedReturnedBytes=$null
            outerPhysicalReadCalls=$(if($OuterPhysicalReadCalls -ge 0){$OuterPhysicalReadCalls}else{$null})
            readCallCountMatched=$null
            reportedPrematureZeroCount=$(if($OuterPrematureZeroReads -ge 0){$OuterPrematureZeroReads}else{$null})
            fullyObservedFat1Entries=$null;fullyObservedFat2Entries=$null
            pairedFullyObservedEntries=$null;totalDeclaredEntriesPerCopy=$null
            unobservedPairedEntryIndices=$null;pairedCoveragePercent=$null
            unobservedPairPercent=$null;maxReturnedBytes=$MaxReturnedBytes
            maxSuccessfulEvents=$MaxSuccessfulEvents
        }
    }
    $reason=New-Object System.Collections.ArrayList
    $inner=@($GuardedResult.sourceReturnedEvents)
    $outer=@($OuterReturnedEvents)
    if($GuardedResult.contractVersion -cne 'd6_guarded_fat_result_v1' -or
       $GuardedResult.team -cne 'D' -or
       $GuardedResult.sourceReadProvenance -cne 'internal_D_source_events_NOT_A_attested' -or
       $GuardedResult.writePermitted -or $GuardedResult.canRepair -or
       $GuardedResult.canExport -or
       $GuardedResult.fatCopyWinner -cne 'not_selected' -or
       $GuardedResult.sourceDecision -cne 'not_selected' -or
       $null -ne $GuardedResult.selectedCandidate){
        [void]$reason.Add('guard.contract_or_provenance_invalid')
    }
    if($SourceLengthBytes -lt 0 -or $SourceLengthBytes -gt [long]::MaxValue){
        [void]$reason.Add('source.length_invalid')
    }
    if($inner.Count -eq 0 -or $outer.Count -eq 0 -or
       $inner.Count -gt $MaxSuccessfulEvents -or
       $outer.Count -gt $MaxSuccessfulEvents){
        [void]$reason.Add('source.successful_event_count_missing_or_over_cap')
    }
    if($inner.Count -ne $outer.Count){
        [void]$reason.Add('source.successful_event_count_mismatch')
    }
    if($GuardedResult.status -ceq 'disabled'){
        [void]$reason.Add('guard.default_off_unknown')
    }
    if($reason.Count -gt 0){
        $out.reasonCodes=@($reason.ToArray())
        return [pscustomobject]$out
    }

    $seen=New-Object 'System.Collections.Generic.HashSet[long]'
    $fat1Seen=New-Object 'System.Collections.Generic.HashSet[long]'
    $fat2Seen=New-Object 'System.Collections.Generic.HashSet[long]'
    $actual=0L;$geoBytes=0L;$fatBytes=0L
    $lastWasFat=$false
    for($i=0;$i -lt $outer.Count;$i++){
        $a=$outer[$i];$d=$inner[$i]
        if($null -eq $a -or $null -eq $d -or
           $null -eq $a.PSObject.Properties['OffsetBytes'] -or
           $null -eq $a.PSObject.Properties['ReturnedBytes'] -or
           $null -eq $d.PSObject.Properties['phase']){
            [void]$reason.Add('source.event_field_missing')
            break
        }
        try {
            $start=[long]$a.OffsetBytes
            $n=[long]$a.ReturnedBytes
            $di=[long]$d.offsetBytes
            $dn=[long]$d.returnedBytes
            $dend=[long]$d.endExclusiveBytes
            $phase=[string]$d.phase
        } catch {
            [void]$reason.Add('source.event_field_not_numeric')
            break
        }
        if($null -ne $a.PSObject.Properties['Consumer'] -and
           [string]$a.Consumer -cne 'fat'){
            [void]$reason.Add('source.outer_consumer_not_fat')
            break
        }
        if($phase -cne 'geometry_gate' -and $phase -cne 'fat_fixed'){
            [void]$reason.Add('source.D_phase_unrecognized')
            break
        }
        if($lastWasFat -and $phase -cne 'fat_fixed'){
            [void]$reason.Add('source.D_phase_reordered')
            break
        }
        if($n -lt 1 -or $n -gt $MaxReturnedBytes -or
           $start -lt 0 -or $start -gt $SourceLengthBytes -or
           $n -gt ($SourceLengthBytes-$start) -or
           $actual -gt ($MaxReturnedBytes-$n)){
            [void]$reason.Add('source.returned_event_outside_bounds_or_budget')
            break
        }
        if($di -ne $start -or $dn -ne $n -or $dend -ne ($start+$n)){
            [void]$reason.Add('source.ordered_returned_spans_disagree')
            break
        }
        if($phase -ceq 'fat_fixed'){
            $lastWasFat=$true;$fatBytes+=$n
        }else{
            $geoBytes+=$n
        }
        for($j=0L;$j -lt $n;$j++){
            [void]$seen.Add([long]($start+$j))
            # FAT physical bytes below are classified after numeric geometry
            # validation; no source bytes are read or supplied to this helper.
        }
        $actual+=$n
    }
    if($reason.Count -gt 0){
        $out.reasonCodes=@($reason.ToArray())
        return [pscustomobject]$out
    }
    $m=$GuardedResult.metrics
    if($actual -ne [long]$m.actualReturnedBytes -or
       [long]$seen.Count -ne [long]$m.uniqueReturnedBytes -or
       ($actual-[long]$seen.Count) -ne [long]$m.repeatedReturnedBytes -or
       $outer.Count -ne [long]$m.successfulSourceReadEvents -or
       $geoBytes -ne [long]$m.geometryGateReturnedBytes -or
       $fatBytes -ne [long]$m.fatFixedReturnedBytes -or
       $actual -gt [long]$m.maxPhysicalReadBytes -or
       [long]$m.physicalReadCalls -gt [long]$m.maxPhysicalReadCalls){
        [void]$reason.Add('source.physical_or_phase_accounting_disagrees')
    }
    if($OuterPhysicalReadCalls -ge 0 -and
       $OuterPhysicalReadCalls -ne [long]$m.physicalReadCalls){
        [void]$reason.Add('source.physical_Read_call_count_disagrees')
    }
    if($OuterPrematureZeroReads -ge 0 -and
       $OuterPrematureZeroReads -ne [long]$m.prematureSourceZeroReads){
        [void]$reason.Add('source.premature_zero_count_disagrees')
    }
    if($reason.Count -gt 0){
        $out.reasonCodes=@($reason.ToArray())
        return [pscustomobject]$out
    }
    $out.outerEventAgreement=$true
    $out.metrics.actualReturnedBytes=$actual
    $out.metrics.uniqueReturnedBytes=[long]$seen.Count
    $out.metrics.repeatedReturnedBytes=[long]($actual-$seen.Count)
    $out.metrics.successfulReadEvents=$outer.Count
    $out.metrics.geometryReturnedBytes=$geoBytes
    $out.metrics.fatFixedReturnedBytes=$fatBytes
    if($OuterPhysicalReadCalls -ge 0){
        $out.metrics.readCallCountMatched=$true
    }
    if([long]$m.prematureSourceZeroReads -gt 0 -or
       [long]$m.refusedReadCalls -gt 0 -or
       $GuardedResult.status -ceq 'unknown' -or
       $GuardedResult.fatProbeState -ceq 'incomplete_source_or_budget_UNKNOWN'){
        $out.reasonCodes=@('source.incomplete_or_early_zero_UNKNOWN')
        return [pscustomobject]$out
    }
    if($GuardedResult.guardDecision -cne 'candidate_geometry_unverified' -or
       $GuardedResult.fatProbeState -cne 'fixed_baseline_sampled'){
        if($fatBytes -gt 0 -or
           $GuardedResult.fatProbeState -ceq 'fixed_baseline_sampled'){
            $out.reasonCodes=@('fat.unexpected_physical_reads_when_guard_blocked')
            $out.outerEventAgreement=$false
            return [pscustomobject]$out
        }
        # Only structurally measured boot-region reads; paired coverage remains
        # UNKNOWN, never zero pairs or a positive FAT health assertion.
        $out.decision='consistent_blocked_unattested'
        $out.reasonCodes=@('fat.no_fixed_read_after_geometry_refusal')
        return [pscustomobject]$out
    }
    if($GuardedResult.evidence.coverageStatus -cne 'partial_numeric_candidate_only' -or
       $GuardedResult.wholeFatVerified -or
       @($GuardedResult.hypotheses).Count -ne 2){
        $out.reasonCodes=@('fat.no_complete_numeric_candidate_evidence')
        return [pscustomobject]$out
    }
    $g0=$GuardedResult.hypotheses[0]
    $g1=$GuardedResult.hypotheses[1]
    if($g0.plausibility -cne 'plausible_unverified' -or
       $g1.plausibility -cne 'plausible_unverified' -or
       $null -eq $g0.numericGeometry -or
       $null -eq $g1.numericGeometry){
        $out.reasonCodes=@('fat.BPB_hypotheses_not_numeric_unverified')
        return [pscustomobject]$out
    }
    $f1=[long]$g0.numericGeometry.fat1OffsetBytes
    $f2=[long]$g0.numericGeometry.fat2OffsetBytes
    $fb=[long]$g0.numericGeometry.fatLengthBytes
    if($f1 -ne [long]$g1.numericGeometry.fat1OffsetBytes -or
       $f2 -ne [long]$g1.numericGeometry.fat2OffsetBytes -or
       $fb -ne [long]$g1.numericGeometry.fatLengthBytes -or
       $f1 -lt 0 -or $f2 -lt 0 -or $fb -lt 12 -or
       ($f1%4) -ne 0 -or ($f2%4) -ne 0 -or ($fb%4) -ne 0 -or
       $fb -gt $SourceLengthBytes -or
       $f1 -gt ($SourceLengthBytes-$fb) -or
       $f2 -gt ($SourceLengthBytes-$fb)){
        $out.reasonCodes=@('fat.caller_hypothesis_invalid_or_divergent')
        return [pscustomobject]$out
    }
    if($f1 -lt ($f2+$fb) -and $f2 -lt ($f1+$fb)){
        $out.reasonCodes=@('fat.numeric_FAT_regions_overlap')
        return [pscustomobject]$out
    }
    $fat1End=$f1+$fb;$fat2End=$f2+$fb
    for($idx=0;$idx -lt $outer.Count;$idx++){
        # Same positional ordering as D internal transcript established above.
        if([string]$inner[$idx].phase -cne 'fat_fixed'){continue}
        $event=$outer[$idx]
        $start=[long]$event.OffsetBytes;$n=[long]$event.ReturnedBytes
        for($i=0L;$i -lt $n;$i++){
            $at=[long]($start+$i)
            if($at -ge $f1 -and $at -lt $fat1End){[void]$fat1Seen.Add($at)}
            elseif($at -ge $f2 -and $at -lt $fat2End){[void]$fat2Seen.Add($at)}
        }
    }
    $complete1=New-Object 'System.Collections.Generic.HashSet[long]'
    $complete2=New-Object 'System.Collections.Generic.HashSet[long]'
    foreach($source in @(
        [pscustomobject]@{base=$f1;positions=$fat1Seen;complete=$complete1},
        [pscustomobject]@{base=$f2;positions=$fat2Seen;complete=$complete2}
    )){
        $indices=New-Object 'System.Collections.Generic.HashSet[long]'
        foreach($position in $source.positions){
            [void]$indices.Add([long][Math]::Floor(($position-$source.base)/4.0))
        }
        foreach($index in $indices){
            $at=[long]($source.base+$index*4L)
            if($source.positions.Contains($at) -and
               $source.positions.Contains(($at+1L)) -and
               $source.positions.Contains(($at+2L)) -and
               $source.positions.Contains(($at+3L))){
                [void]$source.complete.Add([long]$index)
            }
        }
    }
    $pairs=0L
    foreach($entry in $complete1){
        if($complete2.Contains($entry)){$pairs++}
    }
    $entries=[long]($fb/4)
    $missing=[long]($entries-$pairs)
    $percent=[Math]::Round(([double]$pairs/[double]$entries)*100.0,8)
    $missingPercent=[Math]::Round(100.0-$percent,8)
    if(@($GuardedResult.copies).Count -ne 2 -or
       $GuardedResult.copies[0].fullyObservedEntries -ne $complete1.Count -or
       $GuardedResult.copies[1].fullyObservedEntries -ne $complete2.Count -or
       $GuardedResult.evidence.pairedFullyObservedEntries -ne $pairs -or
       $GuardedResult.evidence.totalDeclaredEntriesPerCopy -ne $entries -or
       $GuardedResult.evidence.unobservedPairedEntryIndices -ne $missing -or
       [Math]::Abs([double]$GuardedResult.evidence.pairedCoveragePercent-$percent) -gt 0.00000001 -or
       [Math]::Abs([double]$GuardedResult.evidence.unobservedPairPercent-$missingPercent) -gt 0.00000001){
        $out.reasonCodes=@('fat.physical_pair_count_disagrees_with_D_guard')
        return [pscustomobject]$out
    }
    $out.decision='consistent_numeric_candidate_unattested'
    $out.reasonCodes=@('fat.complete_returned_4byte_pairs_match_D_numeric_candidate')
    $out.metrics.fullyObservedFat1Entries=[long]$complete1.Count
    $out.metrics.fullyObservedFat2Entries=[long]$complete2.Count
    $out.metrics.pairedFullyObservedEntries=$pairs
    $out.metrics.totalDeclaredEntriesPerCopy=$entries
    $out.metrics.unobservedPairedEntryIndices=$missing
    $out.metrics.pairedCoveragePercent=$percent
    $out.metrics.unobservedPairPercent=$missingPercent
    return [pscustomobject]$out
}
Export-ModuleMember -Function Compare-ChappyFatGuardedReturnedSourceEvents
