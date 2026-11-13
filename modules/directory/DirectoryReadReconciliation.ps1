#requires -Version 5.1
# Team B B4-04: PURE bounded comparison of B self-reported directory
# evidence with separately supplied outer Read() return events.
# Neither input can authenticate source identity; A owns actual receipts.
function Compare-ChappyBDirectoryReturnedEvidenceV1 {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory=$true)][psobject]$DirectoryEnvelope,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$OuterReadEvents,
        [ValidateRange(1,1073741824)][long]$SourceLengthBytes,
        [ValidateRange(1,512)][int]$MaxEvents=512,
        [ValidateRange(1,32)][int]$MaxSpans=32,
        [ValidateRange(1,131072)][int]$MaxEventBytes=131072
    )
    $out=[ordered]@{
        schemaVersion='b_directory_outer_reconciliation_v1'
        team='B';decision='unknown';reasonCodes=@('b4_04_missing_or_invalid_evidence')
        sourceAuthenticity='not_proven'
        outerEventAuthority='caller_supplied_not_B_or_A_receipt'
        originalIdentity='unknown';parentConfidence='partial'
        canExport=$false;canSelectFatCopy=$false
        metrics=[pscustomobject]@{
            outerDirectoryReturnedBytes=$null
            outerDirectoryUniqueBytes=$null
            outerDirectoryReadEvents=0
            outerDirectoryOverlapBytes=$null
            bClaimedReturnedDirectoryBytes=$null
            bClaimedCompletedDirectoryBytes=$null
            bClaimedIncompleteReturnedBytes=$null
            bClaimedCompletedSpans=0
            matchingCompletedSpans=0
            outsideCompletedSpanBytes=$null
            additionalStreamReads=0
        }
    }
    $decision='unknown'
    $reason='b4_04_missing_or_invalid_evidence'
    try {
        if($DirectoryEnvelope.schemaVersion -cne 'b_directory_evidence_v1' -or
            $DirectoryEnvelope.sourceAuthority -cne 'B_scanner_report_unattested_not_A_receipt' -or
            $null -eq $DirectoryEnvelope.metrics -or
            $DirectoryEnvelope.metrics.sourceReadAttestation -cne 'unattested' -or
            $DirectoryEnvelope.originalIdentity -cne 'unknown' -or
            $DirectoryEnvelope.canExport -or $DirectoryEnvelope.canSelectFatCopy){
            throw 'invalid B contract'
        }
        $bm=$DirectoryEnvelope.metrics
        if($null -eq $bm.bReturnedDirectoryBytes -or
           $null -eq $bm.bCompletedDirectoryBytes -or
           $null -eq $bm.bIncompleteReturnedBytes){
            $reason='b4_04_b_incomplete_accounting_unknown'
            throw 'incomplete source accounting'
        }
        [long]$bReturned=$bm.bReturnedDirectoryBytes
        [long]$bComplete=$bm.bCompletedDirectoryBytes
        [long]$bPartial=$bm.bIncompleteReturnedBytes
        if($bReturned -lt 0 -or $bComplete -lt 0 -or
           $bPartial -lt 0 -or $bReturned -ne ($bComplete+$bPartial) -or
           $bReturned -gt $SourceLengthBytes*32L){
            $decision='contradicted';$reason='b4_04_b_accounting_contradiction'
            throw 'B counters impossible'
        }
        $out.metrics.bClaimedReturnedDirectoryBytes=$bReturned
        $out.metrics.bClaimedCompletedDirectoryBytes=$bComplete
        $out.metrics.bClaimedIncompleteReturnedBytes=$bPartial
        $rawSpans=@($DirectoryEnvelope.directoryReadSpans)
        if($rawSpans.Count -gt $MaxSpans -or $rawSpans.Count -gt 32 -or
           [long]$bm.bCompletedReadSpans -ne $rawSpans.Count){
            $reason='b4_04_b_span_cap_or_count_unknown'
            throw 'B span unavailable'
        }
        $out.metrics.bClaimedCompletedSpans=$rawSpans.Count
        $spans=New-Object System.Collections.ArrayList
        foreach($s in $rawSpans) {
            if($s.attestation -cne 'unattested'){throw 'B claimed authenticated span'}
            [long]$at=$s.offsetBytes
            [long]$len=$s.lengthBytes
            if($at -lt 0 -or $len -lt 1 -or $len -gt 131072 -or
               $at -gt $SourceLengthBytes-$len){
                $decision='contradicted';$reason='b4_04_b_span_out_of_bounds'
                throw 'bad B span'
            }
            [void]$spans.Add([pscustomobject]@{start=$at;end=($at+$len)})
        }
        $orderedSpans=@($spans|Sort-Object start,end)
        $spanSum=0L;$lastSpanEnd=-1L
        foreach($s in $orderedSpans){
            if($s.start -lt $lastSpanEnd){
                $decision='contradicted';$reason='b4_04_duplicate_or_overlapping_b_span'
                throw 'overlap B spans'
            }
            $spanSum+=($s.end-$s.start)
            $lastSpanEnd=$s.end
        }
        if($spanSum -ne $bComplete){
            $decision='contradicted';$reason='b4_04_b_completed_span_sum_mismatch'
            throw 'completed span ledger mismatch'
        }
        if($OuterReadEvents.Count -gt $MaxEvents) {
            $reason='b4_04_outer_event_cap_unknown'
            throw 'outer records truncated'
        }
        $physical=New-Object System.Collections.ArrayList
        foreach($ev in $OuterReadEvents) {
            $consumer=[string]$ev.Consumer
            if($consumer -cnotin @('geometry','directory','carving','fat')){
                $reason='b4_04_outer_invalid_event'
                throw 'unknown consumer'
            }
            if($null -eq $ev.OffsetBytes -or $null -eq $ev.ReturnedBytes){
                $reason='b4_04_outer_invalid_event'
                throw 'missing fields'
            }
            [long]$offset=$ev.OffsetBytes
            [long]$returned=$ev.ReturnedBytes
            if($returned -lt 1 -or $returned -gt $MaxEventBytes -or
               $offset -lt 0 -or $offset -gt $SourceLengthBytes-$returned){
                $decision='contradicted';$reason='b4_04_outer_read_out_of_bounds'
                throw 'out-of-bounds outer return'
            }
            if($consumer -ceq 'directory'){
                [void]$physical.Add([pscustomobject]@{start=$offset;end=($offset+$returned)})
            }
        }
        $events=@($physical|Sort-Object start,end)
        $sum=0L;$unique=0L;$overlap=0L
        $lastEnd=-1L
        foreach($e in $events){
            $len=$e.end-$e.start
            $sum+=$len
            if($e.start -lt $lastEnd){
                $duplicate=[Math]::Min($lastEnd,$e.end)-$e.start
                if($duplicate -gt 0){$overlap+=$duplicate}
            }
            $unique+=($len-[Math]::Max(0L,[Math]::Min($lastEnd,$e.end)-$e.start))
            if($e.end -gt $lastEnd){$lastEnd=$e.end}
        }
        $out.metrics.outerDirectoryReturnedBytes=$sum
        $out.metrics.outerDirectoryUniqueBytes=$unique
        $out.metrics.outerDirectoryReadEvents=$events.Count
        $out.metrics.outerDirectoryOverlapBytes=$overlap
        if($overlap -ne 0){
            $decision='contradicted';$reason='b4_04_duplicate_or_overlapping_outer_returns'
            throw 'duplicate or overlapping physical returned intervals'
        }
        if($sum -ne $bReturned){
            $decision='contradicted';$reason='b4_04_directory_returned_bytes_disagree'
            throw 'actual returned count differs'
        }
        $matching=0
        foreach($s in $orderedSpans) {
            $cursor=[long]$s.start
            foreach($e in $events){
                if($e.end -le $cursor){continue}
                if($e.start -gt $cursor){break}
                if($e.end -gt $cursor){$cursor=[Math]::Min([long]$s.end,[long]$e.end)}
                if($cursor -ge $s.end){break}
            }
            if($cursor -ge $s.end){$matching++}
            else {
                $decision='contradicted';$reason='b4_04_completed_span_not_observed'
                $out.metrics.matchingCompletedSpans=$matching
                throw 'B complete span missing physical source returns'
            }
        }
        $covered=0L
        foreach($s in $orderedSpans){
            foreach($e in $events){
                $intersection=[Math]::Min([long]$s.end,[long]$e.end)-[Math]::Max([long]$s.start,[long]$e.start)
                if($intersection -gt 0){$covered+=$intersection}
            }
        }
        $out.metrics.matchingCompletedSpans=$matching
        $out.metrics.outsideCompletedSpanBytes=$sum-$covered
        if($covered -ne $bComplete -or ($sum-$covered) -ne $bPartial){
            $decision='contradicted';$reason='b4_04_completed_and_partial_return_disagree'
            throw 'completed/partial intervals disagree'
        }
        if($bPartial -gt 0 -or $DirectoryEnvelope.scanStatus -ceq 'error'){
            $decision='partial_unknown';$reason='b4_04_short_return_no_complete_claim'
        } elseif($DirectoryEnvelope.status -cnotin @('partial','error')){
            $decision='unknown';$reason='b4_04_unexpected_b_status'
        } else {
            # Equality of two caller-owned data structures is NOT attestation.
            $decision='consistent_unattested';$reason='b4_04_returned_intervals_consistent_not_authenticated'
        }
    }catch{
        # Deliberately do not expose raw exception text or origin filenames.
    }
    $out.decision=$decision
    $out.reasonCodes=@($reason)
    return [pscustomobject]$out
}
