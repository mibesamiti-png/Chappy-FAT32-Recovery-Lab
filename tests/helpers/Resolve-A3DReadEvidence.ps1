#Requires -Version 5.1
# Team A R7 synthetic-only contract: source read coverage is not file authenticity.
# Use ONLY with events issued by A's outer physical Stream meter; arbitrary module
# claims are never trusted as physical reads.
function Resolve-A3DReadEvidence {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory)][ValidateRange(1,100MB)][long]$ImageLengthBytes,
        [Parameter(Mandatory)][string]$SourceToken,
        [Parameter(Mandatory)][string]$CandidateId,
        [Parameter(Mandatory)][object[]]$CandidateExtents,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$MeterEvents,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ClaimedEventIds,
        [ValidateRange(1,131072)][long]$MaxPhysicalReadBytes=131072
    )
    if([string]::IsNullOrWhiteSpace($SourceToken) -or $SourceToken.Length -gt 64 -or
       [string]::IsNullOrWhiteSpace($CandidateId) -or $CandidateId.Length -gt 128 -or
       $CandidateExtents.Count -lt 1 -or $CandidateExtents.Count -gt 4 -or
       $MeterEvents.Count -gt 256 -or $ClaimedEventIds.Count -gt 32){
        throw 'Invalid A7 evidence contract limits'
    }
    $extentList=New-Object System.Collections.ArrayList
    foreach($x in $CandidateExtents){
        $start=[long]$x.offsetBytes; $length=[long]$x.lengthBytes
        if($start -lt 0 -or $length -le 0 -or
           $start -gt $ImageLengthBytes-$length){throw 'Invalid A7 candidate extent'}
        [void]$extentList.Add([pscustomobject]@{offsetBytes=$start;endExclusiveBytes=($start+$length)})
    }
    $prior=-1L
    foreach($x in @($extentList | Sort-Object offsetBytes)){
        if($x.offsetBytes -lt $prior){throw 'Overlapping A7 candidate extents'}
        $prior=$x.endExclusiveBytes
    }
    $byId=@{}
    $physicalBytes=0L
    foreach($e in $MeterEvents){
        $id=[string]$e.evidenceId
        $offset=[long]$e.offsetBytes; $len=[long]$e.returnedBytes
        if([string]::IsNullOrWhiteSpace($id) -or $id.Length -gt 64 -or
           $byId.ContainsKey($id) -or $offset -lt 0 -or $len -le 0 -or
           $offset -gt $ImageLengthBytes-$len){
            throw 'Invalid or duplicate A7 meter event'
        }
        $byId[$id]=$e
        if([string]$e.sourceToken -ceq $SourceToken){
            $physicalBytes += $len
        }
    }
    $reasons=New-Object System.Collections.ArrayList
    if($physicalBytes -gt $MaxPhysicalReadBytes){
        [void]$reasons.Add('budget.physical_read_limit')
    }
    if($ClaimedEventIds.Count -eq 0){
        [void]$reasons.Add('origin.no_candidate_specific_receipt')
    }
    $seenClaims=@{}
    $validated=New-Object System.Collections.ArrayList
    foreach($id in $ClaimedEventIds){
        if($seenClaims.ContainsKey($id)){
            [void]$reasons.Add('origin.duplicate_claim')
            continue
        }
        $seenClaims[$id]=$true
        if(-not $byId.ContainsKey($id)){
            [void]$reasons.Add('origin.event_not_observed')
            continue
        }
        $e=$byId[$id]
        if([string]$e.sourceToken -cne $SourceToken){
            [void]$reasons.Add('origin.wrong_source')
        } elseif([string]$e.consumer -cne 'carving' -or
                 [string]$e.purpose -cne 'candidate_validation' -or
                 [string]$e.candidateId -cne $CandidateId){
            # Whole-window scans are not candidate-specific validator evidence.
            [void]$reasons.Add('origin.not_candidate_validation')
        } else {
            [void]$validated.Add([pscustomobject]@{
                offsetBytes=[long]$e.offsetBytes
                endExclusiveBytes=([long]$e.offsetBytes+[long]$e.returnedBytes)
            })
        }
    }
    $covered=0L
    $allCovered=$true
    foreach($extent in $extentList){
        $intervals=New-Object System.Collections.ArrayList
        foreach($e in $validated){
            $lo=[Math]::Max($extent.offsetBytes,$e.offsetBytes)
            $hi=[Math]::Min($extent.endExclusiveBytes,$e.endExclusiveBytes)
            if($hi -gt $lo){
                [void]$intervals.Add([pscustomobject]@{start=$lo;end=$hi})
            }
        }
        $cursor=$extent.offsetBytes
        $thisCovered=0L
        foreach($interval in @($intervals | Sort-Object start,end)){
            if($interval.end -gt $cursor){
                $from=[Math]::Max($interval.start,$cursor)
                if($interval.end -gt $from){$thisCovered+=($interval.end-$from)}
                $cursor=$interval.end
            }
        }
        $covered+=$thisCovered
        if($thisCovered -ne ($extent.endExclusiveBytes-$extent.offsetBytes)){
            $allCovered=$false
        }
    }
    if(-not $allCovered){[void]$reasons.Add('coverage.candidate_bytes_not_fully_read')}
    $ok=($allCovered -and $reasons.Count -eq 0)
    return [pscustomobject]@{
        status=$(if($ok){'source_observed'}else{'unattributed'})
        originalIdentity='unknown'
        integrityScope='source_read_coverage_only_not_original_integrity'
        candidateReadBytes=$covered
        sourceActualReadBytes=$physicalBytes
        sourceTokenMatches=$true
        reasons=@($reasons.ToArray() | Sort-Object -Unique)
    }
}
