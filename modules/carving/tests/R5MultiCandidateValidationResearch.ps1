#requires -Version 5.1
# Team C R5 Issue #72: TEST ONLY. Independently reread every selected
# structurally consistent physical hypothesis, but NEVER choose an original.
# Self-reported intervals are not A-issued source receipts.
function Test-CMultiCandidateValidation {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][IO.Stream]$Source,
        [Parameter(Mandatory=$true)][object]$ScanResult,
        [ValidateRange(1,2)][int]$MaxCandidates=2,
        [ValidateRange(1,2048)][long]$MaxSourceBytes=2048,
        [ValidateRange(1,16384)][long]$MaxValidatorBytes=16384,
        [ValidateRange(100,10000)][int]$MaxMilliseconds=10000
    )
    if(-not $Source.CanRead -or -not $Source.CanSeek -or $Source.CanWrite){
        throw 'C multi candidate requires readable seekable NONWRITABLE source'
    }
    if($Source.Length -gt 2097152L){throw 'C multi candidate synthetic source exceeds 2MiB'}
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $traces=New-Object 'System.Collections.Generic.List[object]'
    $seen=New-Object 'System.Collections.Generic.HashSet[string]'
    $bytes=0L;$memoryBytes=0L;$requests=0;$intervals=0;$verified=0
    $status='ok';$reason='none'
    $guard=Resolve-CFragmentFalseJoinEvidence -ScanResult $ScanResult
    if($guard.status -ne 'ok'){
        $status='partial';$reason='multi.incomplete_scanner'
    }
    $input=@($guard.formatConsistentHypotheses)
    if($status -eq 'ok' -and $input.Count -gt $MaxCandidates){
        $status='partial';$reason='multi.too_many_valid_hypotheses'
    }
    if($status -eq 'ok'){
        foreach($p in $input){
            if($timer.ElapsedMilliseconds -ge $MaxMilliseconds){
                $status='partial';$reason='multi.time_limit';break
            }
            $spans=@(
                [pscustomobject]@{offsetBytes=[long]$p.firstOffset;lengthBytes=[long]$p.firstBytes},
                [pscustomobject]@{offsetBytes=[long]$p.secondOffset;lengthBytes=[long]$p.secondBytes}
            )
            $key=('3mf:{0}+{1},{2}+{3}' -f $p.firstOffset,$p.firstBytes,$p.secondOffset,$p.secondBytes)
            if(-not $seen.Add($key) -or $key -cne [string]$p.candidateKey){
                $status='partial';$reason='multi.duplicate_or_invalid_order';break
            }
            $minimum=[long]$p.firstBytes+[long]$p.secondBytes
            # Do not partially revalidate a prefix when there is no budget
            # left for an entire hypothesis. In the deliberately short-read
            # test, however, physical Stream.Read may STILL return fewer bytes.
            if($minimum -gt $MaxSourceBytes-$bytes){
                $status='partial';$reason='multi.shared_physical_budget';break
            }
            if(6144L -gt $MaxValidatorBytes-$memoryBytes){
                $status='partial';$reason='multi.shared_validator_budget';break
            }
            $candidate=[pscustomobject]@{sourceSpans=$spans}
            $remaining=[int][Math]::Min(5000,[Math]::Max(100,($MaxMilliseconds-$timer.ElapsedMilliseconds)))
            $check=Test-CObservedCandidateValidation -Source $Source -Candidate $candidate -MaxSourceBytes ([long][Math]::Min(2048,($MaxSourceBytes-$bytes))) -MaxValidatorBytes ([long][Math]::Min(8192,($MaxValidatorBytes-$memoryBytes))) -MaxMilliseconds $remaining
            $bytes += [long]$check.metrics.sourceBytesRead
            $memoryBytes += [long]$check.metrics.memoryValidatorBytesRead
            $requests += [int]$check.metrics.sourceReadRequests
            $intervals += [int]$check.metrics.sourceObservedIntervals
            if($bytes -gt $MaxSourceBytes -or $memoryBytes -gt $MaxValidatorBytes){
                throw 'C multi candidate cumulative accounting invariant'
            }
            $traces.Add([pscustomobject]@{
                candidateKey=$key
                sourceSpans=@($spans)
                status=$check.status
                decision=$check.decision
                # Hash of rejoined candidate bytes is NOT an original hash.
                candidateSha256=$check.candidateSha256
                observedPhysicalReads=@($check.observedPhysicalReads)
                readBytes=[long]$check.metrics.sourceBytesRead
                memoryBytes=[long]$check.metrics.memoryValidatorBytesRead
                reason=$check.reason
                originStatus='unattributed_pending_A_meter_receipt'
                originalIdentity='unknown'
                integrityScope='structural_only_not_original_file_integrity'
            })
            if($check.status -ne 'format_consistent'){
                $status='partial';$reason=$(if($check.status -eq 'partial'){'multi.candidate_partial'}else{'multi.validation_disagrees'});break
            }
            $verified++
        }
    }
    $decision=if($status -ne 'ok'){'incomplete'}elseif($verified -eq 0){'unknown'}elseif($verified -eq 1){'one_possible'}else{'ambiguous'}
    if($status -eq 'ok' -and $decision -cne [string]$guard.decision){
        $status='partial';$reason='multi.scan_validation_disagreement';$decision='incomplete'
    }
    $timer.Stop()
    return [pscustomobject]@{
        status=$status;decision=$decision;reason=$reason
        originalIdentity='unknown';selectedOriginal=$null;canAutoSelectOriginal=$false
        sourceOrigin='unattributed_pending_A_meter_receipt'
        candidateTraces=@($traces.ToArray())
        metrics=[pscustomobject]@{
            distinctPossiblePhysicalPairs=$input.Count
            candidateRechecks=$traces.Count
            formatConsistent=$verified
            additionalSourceBytesRead=$bytes
            additionalValidatorMemoryBytesRead=$memoryBytes
            additionalSourceReadRequests=$requests
            observedPhysicalReadIntervals=$intervals
            elapsedMilliseconds=$timer.ElapsedMilliseconds
            trustedAReceiptIdsMinted=0
            stopCode=$reason
        }
    }
}
