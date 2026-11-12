#requires -Version 5.1
# Team C R5 #72: TEST-ONLY ambiguity policy for bounded ZIP/3MF pairs.
# Consumes C's already-scanned finite candidates. No physical reread, oracle
# SHA, FAT links, A evidenceIds or original-file winner is ever generated.
function Resolve-CFragmentFalseJoinEvidence {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][object]$ScanResult,
        [ValidateRange(1,16)][int]$MaxPairs=16,
        [ValidateRange(1,81920)][long]$MaxSourceBytes=81920,
        [ValidateRange(1,98304)][long]$MaxValidatorBytes=98304,
        [ValidateRange(100,1000)][int]$MaxMilliseconds=1000,
        [switch]$AllowFirstPiece560
    )
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $hypotheses=New-Object 'System.Collections.Generic.List[object]'
    $identities=New-Object 'System.Collections.Generic.HashSet[string]'
    $reason='none'
    # Keep the previously reviewed 544B maximum by default. Only an
    # explicit test-only opt-in may validate the extra 560B hypothesis.
    $maxFirstSpan=if($AllowFirstPiece560){560L}else{544L}
    $incomplete=$false
    # A gate cannot upgrade an incomplete or unbounded scanner run.
    $metrics=$ScanResult.PSObject.Properties['metrics']
    $inputItems=$ScanResult.PSObject.Properties['items']
    if($null -eq $metrics -or $null -eq $inputItems){
        $incomplete=$true;$reason='guard.scan_contract_missing'
        $input=@()
    }else{
        $input=@($ScanResult.items)
        if($ScanResult.status -cne 'ok' -or $ScanResult.decision -ceq 'incomplete'){
            $incomplete=$true;$reason='guard.scan_incomplete'
        }elseif([long]$ScanResult.metrics.pairAttempts -lt 0 -or
           [long]$ScanResult.metrics.sourceBytesRead -lt 0 -or
           [long]$ScanResult.metrics.validatorBytesRead -lt 0){
            $incomplete=$true;$reason='guard.invalid_metrics'
        }elseif($input.Count -gt $MaxPairs -or
                [long]$ScanResult.metrics.pairAttempts -gt $MaxPairs -or
                [long]$ScanResult.metrics.sourceBytesRead -gt $MaxSourceBytes -or
                [long]$ScanResult.metrics.validatorBytesRead -gt $MaxValidatorBytes){
            $incomplete=$true;$reason='guard.budget_or_pair_cap'
        }elseif($input.Count -gt [int]$ScanResult.metrics.pairAttempts){
            $incomplete=$true;$reason='guard.invalid_pair_count'
        }
    }
    if(-not $incomplete){
        foreach($item in $input){
            if($timer.ElapsedMilliseconds -ge $MaxMilliseconds){
                $incomplete=$true;$reason='guard.time_limit';break
            }
            # Positive is structural plausibility, not actual original bytes.
            if(-not [bool]$item.possible){continue}
            if([string]$item.originalIdentity -cne 'unknown' -or
               [string]$item.integrityScope -cne 'structural_only_not_original_file_integrity'){
                $incomplete=$true;$reason='guard.invalid_original_claim';break
            }
            if(@($item.sourceSpans).Count -ne 2){
                $incomplete=$true;$reason='guard.invalid_span_count';break
            }
            $a=$item.sourceSpans[0];$b=$item.sourceSpans[1]
            $offsetA=[long]$a.offsetBytes;$sizeA=[long]$a.lengthBytes
            $offsetB=[long]$b.offsetBytes;$sizeB=[long]$b.lengthBytes
            if($offsetA -lt 0 -or $offsetB -lt 0 -or
               $sizeA -lt 1 -or $sizeA -gt $maxFirstSpan -or
               $sizeB -lt 1 -or $sizeB -gt 512 -or
               $offsetA -gt (2097152L-$sizeA) -or
               $offsetB -gt (2097152L-$sizeB) -or
               ($offsetA -lt $offsetB+$sizeB -and $offsetB -lt $offsetA+$sizeA)){
                $incomplete=$true;$reason='guard.invalid_physical_spans';break
            }
            # Exact ordered *physical* identity. Do NOT deduplicate by SHA.
            $key=('3mf:{0}+{1},{2}+{3}' -f $offsetA,$sizeA,$offsetB,$sizeB)
            if(-not $identities.Add($key)){
                $incomplete=$true;$reason='guard.duplicate_physical_hypothesis';break
            }
            $hypotheses.Add([pscustomobject]@{
                candidateKey=$key
                format='3mf'
                firstOffset=$offsetA
                firstBytes=$sizeA
                secondOffset=$offsetB
                secondBytes=$sizeB
                evidence='pair.zip_crc_consistent'
                originalIdentity='unknown'
                integrityScope='structural_only_not_original_file_integrity'
                sourceOrigin='unattributed_without_A_meter'
            })
        }
    }
    $derived=if($hypotheses.Count -eq 0){'unknown'}elseif($hypotheses.Count -eq 1){'one_possible'}else{'ambiguous'}
    if(-not $incomplete -and [string]$ScanResult.decision -cne $derived){
        $incomplete=$true;$reason='guard.scan_decision_mismatch'
    }
    $decision=if($incomplete){'incomplete'}else{$derived}
    # Partial results retain diagnostic hypotheses but never select a winner.
    $timer.Stop()
    return [pscustomobject]@{
        status=$(if($incomplete){'partial'}else{'ok'})
        decision=$decision
        originalIdentity='unknown'
        selectedOriginal=$null
        canAutoSelectOriginal=$false
        reason=$reason
        formatConsistentHypotheses=@($hypotheses.ToArray())
        metrics=[pscustomobject]@{
            inputPairCount=$input.Count
            acceptedDistinctPhysicalHypotheses=$hypotheses.Count
            additionalSourceBytesRead=0L
            additionalMemoryValidatorBytesRead=0L
            elapsedMilliseconds=$timer.ElapsedMilliseconds
            stopCode=$reason
        }
    }
}
