#Requires -Version 5.1
# Team A: real C-discovered ambiguous 3MF candidates, A-owned physical receipts.
# ONLY generated nonwritable synthetic bytes, no IMG path or extraction.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
# The pre-existing baseline defines the A-owned physical stream meter and
# reruns its already-accepted synthetic candidate receipt regression.
. (Join-Path $PSScriptRoot 'Test-A3DLiveCCandidateReceipts.ps1')
. (Join-Path $root 'modules\carving\tests\R5VariableZipPairResearch.ps1')
. (Join-Path $root 'modules\carving\tests\R5VariableZipPairRegression.ps1')
. (Join-Path $root 'modules\carving\tests\R5AmbiguousFalseJoinGuard.ps1')
. (Join-Path $root 'modules\carving\tests\R5MultiCandidateValidationResearch.ps1')
# This scorer-only helper produces a true 17-byte early-return/EOF stream,
# distinct from the A meter's budget-refusal IOException.
. (Join-Path $root 'modules\carving\tests\R5CandidateValidatorOriginRegression.ps1')
function Assert-A7Discovered([bool]$Ok,[string]$Reason){
    if(-not $Ok){throw ('A7_DISCOVERED_FAIL: '+$Reason)}
}
function Get-A7OrderedKey([object[]]$Spans) {
    return ('3mf:{0}+{1},{2}+{3}' -f
        $Spans[0].offsetBytes,$Spans[0].lengthBytes,
        $Spans[1].offsetBytes,$Spans[1].lengthBytes)
}
$clean=New-ChappyA3DCleanFixture -Seed 202611
$truth=$clean.oracle[1]
[byte[]]$original=[byte[]]::new([int]$truth.lengthBytes)
$writeOffset=0
foreach($span in @($truth.extents)){
    [Array]::Copy($clean.image,[int]$span.offsetBytes,$original,$writeOffset,[int]$span.lengthBytes)
    $writeOffset += [int]$span.lengthBytes
}
Assert-A7Discovered ($writeOffset -eq $original.Length -and
    (Get-A3DSha256 $original) -ceq $truth.sha256) 'synthetic_oracle_only_in_external_scorer'
$case=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind 'alternate_zip_metadata'
[byte[]]$raw=[byte[]]$case.image
$inputSha=Get-A3DSha256 $raw

$stream=[IO.MemoryStream]::new($raw,$false)
$token='A7_discovered_ambiguous_M01'
$meter=[ChappyA7CandidateMeter]::new($stream,$token,120000L)
try{
    $meter.BeginPhase('scan','')
    $scan=Test-CVariableZipPairs -Source $meter -WindowBytes 65536 -MaxSourceBytes 81920 -MaxPairs 16 -MaxStarts 4 -MaxTails 8 -MaxValidationBytes 98304
    $guard=Resolve-CFragmentFalseJoinEvidence -ScanResult $scan
    Assert-A7Discovered ($scan.status -ceq 'ok' -and $scan.decision -ceq 'ambiguous' -and
        $guard.status -ceq 'ok' -and $guard.decision -ceq 'ambiguous') 'real_C_discovered_multiple_valid_physical_candidates'
    $hypotheses=@($guard.formatConsistentHypotheses)
    Assert-A7Discovered ($hypotheses.Count -eq 2 -and
        $hypotheses[0].candidateKey -cne $hypotheses[1].candidateKey) 'two_distinct_ordered_sources'
    $scoutBytes=$meter.BytesRead
    Assert-A7Discovered ($scoutBytes -eq [long]$scan.metrics.sourceBytesRead -and
        $meter.ReadRequests -gt 0) 'scout_physically_metered'
    $records=New-Object 'System.Collections.Generic.List[object]'
    $receiptsByKey=@{}
    foreach($h in $hypotheses){
        $extents=@(
            [pscustomobject]@{offsetBytes=[long]$h.firstOffset;lengthBytes=[long]$h.firstBytes},
            [pscustomobject]@{offsetBytes=[long]$h.secondOffset;lengthBytes=[long]$h.secondBytes}
        )
        $key=Get-A7OrderedKey $extents
        Assert-A7Discovered ($key -ceq $h.candidateKey) 'C_scout_candidate_key_matches_A_order'
        $preEvents=@($meter.GetEvents()).Count
        $beforeBytes=$meter.BytesRead
        $meter.BeginPhase('candidate_validation',$key)
        $v=Test-CObservedCandidateValidation -Source $meter -Candidate ([pscustomobject]@{sourceSpans=$extents})
        $afterEvents=@($meter.GetEvents())
        $newEvents=@($afterEvents|Select-Object -Skip $preEvents)
        $ids=@($newEvents|ForEach-Object {$_.EvidenceId})
        $sum=0L
        foreach($evt in $newEvents) {$sum += [long]$evt.ReturnedBytes}
        Assert-A7Discovered ($v.status -ceq 'format_consistent' -and
            $v.originStatus -ceq 'unattributed_pending_A_meter_receipt' -and
            $v.originalIdentity -ceq 'unknown' -and
            $ids.Count -ge 2 -and
            $v.metrics.sourceBytesRead -eq $sum -and
            ($meter.BytesRead-$beforeBytes) -eq $sum) 'live_C_recheck_against_A_actual_physical_source'
        $diagnostics=@($v.observedPhysicalReads)
        Assert-A7Discovered ($diagnostics.Count -eq $newEvents.Count) 'C_actual_read_events_align_A'
        for($i=0;$i -lt $diagnostics.Count;$i++){
            Assert-A7Discovered ($diagnostics[$i].offsetBytes -eq $newEvents[$i].OffsetBytes -and
                $diagnostics[$i].returnedBytes -eq $newEvents[$i].ReturnedBytes -and
                $diagnostics[$i].candidateKey -ceq $key -and
                $newEvents[$i].Purpose -ceq 'candidate_validation' -and
                $newEvents[$i].CandidateId -ceq $key -and
                $null -eq $diagnostics[$i].PSObject.Properties['EvidenceId']) 'A_receipts_never_forged_by_C'
        }
        $receiptsByKey[$key]=$ids
        $records.Add([pscustomobject]@{key=$key;extents=$extents;structural=$v.status;candidateSha=$v.candidateSha256;ids=$ids;bytes=$sum})
    }
    $all=@($meter.GetEvents())
    $results=New-Object 'System.Collections.Generic.List[object]'
    $validatorSum=0L;$exact=0
    for($j=0;$j -lt $records.Count;$j++){
        $rec=$records[$j]
        $resolved=Resolve-A3DReadEvidence -ImageLengthBytes ([long]$raw.Length) -SourceToken $token -CandidateId $rec.key -CandidateExtents $rec.extents -MeterEvents $all -ClaimedEventIds $rec.ids -MaxPhysicalReadBytes 120000L
        $joined=[long]$rec.extents[0].lengthBytes+[long]$rec.extents[1].lengthBytes
        Assert-A7Discovered ($resolved.status -ceq 'source_observed' -and
            $resolved.candidateReadBytes -eq $joined -and
            $resolved.originalIdentity -ceq 'unknown' -and
            $resolved.sourceActualReadBytes -eq $meter.BytesRead) 'each_separately_A_attested_candidate_only_source_observed'
        $validatorSum += $rec.bytes
        # Only the independent artificial scorer is allowed to compare an
        # observed candidate SHA with the original synthetic file oracle.
        if($rec.candidateSha -ceq $truth.sha256) {$exact++}
        $results.Add($resolved)
    }
    Assert-A7Discovered ($exact -eq 1 -and $records.Count -eq 2 -and
        $validatorSum -eq $meter.BytesRead-$scoutBytes -and
        $meter.BytesRead -le $meter.Maximum -and -not $meter.CanWrite) 'one_oracle_exact_but_both_structurally_possible'
    $wrong=Resolve-A3DReadEvidence -ImageLengthBytes ([long]$raw.Length) -SourceToken $token -CandidateId $records[0].key -CandidateExtents $records[0].extents -MeterEvents $all -ClaimedEventIds $records[1].ids -MaxPhysicalReadBytes 120000
    Assert-A7Discovered ($wrong.status -ceq 'unattributed' -and
        $wrong.reasons -contains 'origin.not_candidate_validation' -and
        $wrong.candidateReadBytes -eq 0) 'different_C_discovered_candidate_receipts_cannot_swap'
    $scoutIds=@($all|Where-Object {$_.Purpose -ceq 'scan'}|Select-Object -First 1|ForEach-Object {$_.EvidenceId})
    $scanFake=Resolve-A3DReadEvidence -ImageLengthBytes ([long]$raw.Length) -SourceToken $token -CandidateId $records[0].key -CandidateExtents $records[0].extents -MeterEvents $all -ClaimedEventIds $scoutIds -MaxPhysicalReadBytes 120000
    Assert-A7Discovered ($scanFake.status -ceq 'unattributed' -and
        $scanFake.reasons -contains 'origin.not_candidate_validation') 'scan_receipt_is_not_validation'
    Assert-A7Discovered ((Get-A3DSha256 $raw) -ceq $inputSha) 'synthetic_source_unmodified'
    Write-Host ('A7 AMBIGUOUS C-discovered=2 structure_valid=2 synthetic_original_SHA_matches={0} A_source_total={1} scout={2} recheck={3} identity=unknown' -f $exact,$meter.BytesRead,$scoutBytes,$validatorSum)
}finally {$stream.Dispose()}

# Genuine short-return/EOF control: separate physical source yields only
# first candidate fully and 17B from the second, independent of A's quota.
$first=$records[0];$second=$records[1]
$shortMax=[int]$first.bytes+17
$shortBase=[IO.MemoryStream]::new($raw,$false)
$shortPhysical=[CArtificialShortValidationStream]::new($shortBase,$shortMax)
$shortToken='A7_discovered_EOF_short'
$shortMeter=[ChappyA7CandidateMeter]::new($shortPhysical,$shortToken,120000L)
try{
    $shortMeter.BeginPhase('candidate_validation',$first.key)
    $p=Test-CObservedCandidateValidation -Source $shortMeter -Candidate ([pscustomobject]@{sourceSpans=$first.extents})
    Assert-A7Discovered ($p.status -ceq 'format_consistent' -and
        $p.metrics.sourceBytesRead -eq $first.bytes) 'real_17B_chunks_first_candidate_complete'
    $shortMeter.BeginPhase('candidate_validation',$second.key)
    $q=Test-CObservedCandidateValidation -Source $shortMeter -Candidate ([pscustomobject]@{sourceSpans=$second.extents})
    Assert-A7Discovered ($q.status -ceq 'partial' -and
        $q.metrics.sourceBytesRead -eq 17 -and
        $q.reason -ceq 'validation.short_read' -and
        $shortMeter.BytesRead -eq $shortMax) 'second_candidate_physical_early_EOF_after_17B'
    $shortEvents=@($shortMeter.GetEvents())
    $idsFirst=@($shortEvents|Where-Object{$_.CandidateId -ceq $first.key}|ForEach-Object {$_.EvidenceId})
    $idsSecond=@($shortEvents|Where-Object{$_.CandidateId -ceq $second.key}|ForEach-Object {$_.EvidenceId})
    Assert-A7Discovered ($idsFirst.Count -gt 32 -and $idsFirst.Count -le 128) 'real_short_chunks_require_more_than_previous_32_receipts'
    $tooMany=New-Object 'System.Collections.Generic.List[string]'
    for($k=0;$k -lt 129;$k++){ $tooMany.Add($idsFirst[0]) }
    $limitRejected=$false
    try{
        $null=Resolve-A3DReadEvidence -ImageLengthBytes ([long]$raw.Length) -SourceToken $shortToken -CandidateId $first.key -CandidateExtents $first.extents -MeterEvents $shortEvents -ClaimedEventIds @($tooMany.ToArray()) -MaxPhysicalReadBytes 120000L
    }catch{
        $limitRejected=($_.Exception.Message -match 'Invalid A7 evidence contract limits')
    }
    Assert-A7Discovered $limitRejected 'more_than_128_receipts_still_refused'
    $base=@{ImageLengthBytes=[long]$raw.Length;SourceToken=$shortToken;MeterEvents=$shortEvents;MaxPhysicalReadBytes=120000L}
    $valid=Resolve-A3DReadEvidence @base -CandidateId $first.key -CandidateExtents $first.extents -ClaimedEventIds $idsFirst
    $incomplete=Resolve-A3DReadEvidence @base -CandidateId $second.key -CandidateExtents $second.extents -ClaimedEventIds $idsSecond
    Assert-A7Discovered ($valid.status -ceq 'source_observed' -and
        $incomplete.status -ceq 'unattributed' -and
        $incomplete.reasons -contains 'coverage.candidate_bytes_not_fully_read' -and
        $incomplete.originalIdentity -ceq 'unknown' -and -not $shortMeter.CanWrite) 'short_return_never_promotes_second_original'
    Assert-A7Discovered ((Get-A3DSha256 $raw) -ceq $inputSha) 'early_EOF_source_unchanged'
    Write-Host ('A7 SHORT first={0} second={1} source_total={2} A_first={3} A_second={4}' -f
        $p.status,$q.status,$shortMeter.BytesRead,$valid.status,$incomplete.status)
}finally {
    $shortMeter.Dispose()
    $shortBase.Dispose()
}
Write-Host 'PASS: A7 physically C-discovered ambiguous 3MF candidates separately metered; true short-return EOF fails closed.'
