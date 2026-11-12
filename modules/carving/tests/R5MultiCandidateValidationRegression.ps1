#requires -Version 5.1
# Team C Issue #72 synthetic independent scorer. Truth is never passed to
# Test-CMultiCandidateValidation or Test-CObservedCandidateValidation.
function Assert-CMultiCandidate([bool]$Ok,[string]$Why){
    if(-not $Ok){throw ('C_MULTICANDIDATE_FAIL: '+$Why)}
}
function Invoke-CMultiCandidateValidationRegression {
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
    $clean=New-ChappyA3DCleanFixture -Seed 202611
    $truth=$clean.oracle[1]
    [byte[]]$original=New-Object byte[] ([int]$truth.lengthBytes)
    $cursor=0
    foreach($e in $truth.extents){
        [Array]::Copy($clean.image,[int]$e.offsetBytes,$original,$cursor,[int]$e.lengthBytes)
        $cursor+=[int]$e.lengthBytes
    }
    Assert-CMultiCandidate ($cursor -eq $truth.lengthBytes -and
        (Get-A3DSha256 $original) -ceq $truth.sha256) 'external fabricated original SHA oracle'
    $caseNames=@('M01_control','alternate_zip_metadata','fake_eocd','missing_tail','offgrid_plus_two')
    $baselineBytes=0L;$recheckScanBytes=0L;$additionalBytes=0L
    $baselineValidator=0L;$recheckScanValidator=0L;$additionalValidator=0L
    $baselinePairs=0;$recheckPairs=0;$intervals=0;$requests=0
    $baselineMs=0L;$recheckScanMs=0L;$recheckMs=0L
    $truthTP=0;$truthFP=0;$truthTN=0;$missedCases=0
    $one=0;$ambig=0;$unknown=0;$originalClaims=0;$autoWinners=0
    $caseCount=0;$altBytes=$null;$altScan=$null;$altTraces=$null
    foreach($name in $caseNames){
        $case=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind $name
        [byte[]]$bytes=$case.image
        $before=Get-A3DSha256 $bytes
        $baselineStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($bytes,$false))
        try{
            $base=Test-CVariableZipPairs -Source $baselineStream -WindowBytes 65536 -MaxStarts 4 -MaxTails 8 -MaxPairs 16 -MaxSourceBytes 81920 -MaxValidationBytes 98304
            Assert-CMultiCandidate ($base.status -eq 'ok' -and $baselineStream.BytesRead -eq $base.metrics.sourceBytesRead -and
                $baselineStream.BytesRead -le 81920) ($name+': finite scan baseline complete and physically counted')
            $baselineBytes += $baselineStream.BytesRead
            $baselineValidator += [long]$base.metrics.validatorBytesRead
            $baselinePairs += [int]$base.metrics.pairAttempts
            $baselineMs += [long]$base.metrics.elapsedMilliseconds
        }finally{$baselineStream.Dispose()}
        $instrumented=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($bytes,$false))
        try{
            $scan=Test-CVariableZipPairs -Source $instrumented -WindowBytes 65536 -MaxStarts 4 -MaxTails 8 -MaxPairs 16 -MaxSourceBytes 81920 -MaxValidationBytes 98304
            $afterScan=$instrumented.BytesRead
            Assert-CMultiCandidate ($scan.status -eq 'ok' -and $afterScan -eq $scan.metrics.sourceBytesRead) ($name+': same physical scan')
            $rechecked=Test-CMultiCandidateValidation -Source $instrumented -ScanResult $scan
            Assert-CMultiCandidate (($instrumented.BytesRead-$afterScan) -eq $rechecked.metrics.additionalSourceBytesRead -and
                $rechecked.metrics.additionalSourceBytesRead -le 2048 -and
                $rechecked.metrics.additionalValidatorMemoryBytesRead -le 16384) ($name+': independent actual validator I/O')
            Assert-CMultiCandidate ($rechecked.status -eq 'ok' -and $rechecked.decision -ceq $scan.decision -and
                -not $rechecked.canAutoSelectOriginal -and $null -eq $rechecked.selectedOriginal -and
                $rechecked.originalIdentity -ceq 'unknown') ($name+': no original selection')
            Assert-CMultiCandidate ($rechecked.metrics.trustedAReceiptIdsMinted -eq 0 -and -not $instrumented.CanWrite) ($name+': no forged trusted receipts or writable stream')
            $recheckScanBytes += $afterScan
            $recheckScanValidator += [long]$scan.metrics.validatorBytesRead
            $recheckPairs += [int]$scan.metrics.pairAttempts
            $additionalBytes += [long]$rechecked.metrics.additionalSourceBytesRead
            $additionalValidator += [long]$rechecked.metrics.additionalValidatorMemoryBytesRead
            $intervals += [int]$rechecked.metrics.observedPhysicalReadIntervals
            $requests += [int]$rechecked.metrics.additionalSourceReadRequests
            $recheckScanMs += [long]$scan.metrics.elapsedMilliseconds
            $recheckMs += [long]$rechecked.metrics.elapsedMilliseconds
            $accepted=@($scan.items | Where-Object {$_.possible})
            $originalHits=@($accepted | Where-Object {$_.candidateSha256 -ceq $truth.sha256})
            $truthTP += $originalHits.Count
            $truthFP += ($accepted.Count-$originalHits.Count)
            $truthTN += @($scan.items | Where-Object {-not $_.possible}).Count
            if($case.hasOriginal -and $originalHits.Count -eq 0){$missedCases++}
            $traceKeys=@($rechecked.candidateTraces | ForEach-Object {$_.candidateKey})
            $physicalKeys=@($accepted | ForEach-Object {
                '3mf:{0}+{1},{2}+{3}' -f $_.sourceSpans[0].offsetBytes,$_.sourceSpans[0].lengthBytes,$_.sourceSpans[1].offsetBytes,$_.sourceSpans[1].lengthBytes
            })
            Assert-CMultiCandidate ($traceKeys.Count -eq $physicalKeys.Count) ($name+': all accepted physical hypotheses rechecked')
            for($i=0;$i -lt $traceKeys.Count;$i++){
                Assert-CMultiCandidate ($traceKeys[$i] -ceq $physicalKeys[$i]) ($name+': exact ordered candidate key preserved')
            }
            $allRead=0L
            foreach($trace in $rechecked.candidateTraces){
                Assert-CMultiCandidate ($trace.status -eq 'format_consistent' -and
                    $trace.originalIdentity -ceq 'unknown' -and
                    $trace.originStatus -ceq 'unattributed_pending_A_meter_receipt' -and
                    $trace.integrityScope -ceq 'structural_only_not_original_file_integrity') ($name+': rechecked structural candidate does not verify original or source')
                foreach($event in $trace.observedPhysicalReads){
                    $allRead += [long]$event.returnedBytes
                    Assert-CMultiCandidate ($event.candidateKey -ceq $trace.candidateKey -and
                        $event.purpose -ceq 'candidate_validation' -and
                        $null -eq $event.PSObject.Properties['evidenceId'] -and
                        $null -eq $event.PSObject.Properties['sourceToken']) ($name+': candidate event is diagnostic only')
                }
            }
            Assert-CMultiCandidate ($allRead -eq $rechecked.metrics.additionalSourceBytesRead) ($name+': sum actual physical returned intervals')
            $originalClaims += @($rechecked.candidateTraces | Where-Object {$_.originalIdentity -cne 'unknown'}).Count
            $autoWinners += $(if($null -ne $rechecked.selectedOriginal){1}else{0})
            switch($rechecked.decision){
                'one_possible' {$one++}
                'ambiguous' {$ambig++}
                'unknown' {$unknown++}
            }
            if($name -eq 'alternate_zip_metadata'){
                $altBytes=$bytes;$altScan=$scan;$altTraces=$rechecked
                Assert-CMultiCandidate ($traceKeys.Count -eq 2 -and $traceKeys[0] -cne $traceKeys[1] -and
                    $originalHits.Count -eq 1 -and $accepted.Count -eq 2 -and
                    $rechecked.decision -eq 'ambiguous') 'two physically different CRC-consistent candidates preserved'
            }
            if($name -in @('missing_tail','offgrid_plus_two')){
                Assert-CMultiCandidate ($rechecked.decision -eq 'unknown' -and $rechecked.candidateTraces.Count -eq 0) ($name+': no invented original')
            }
            $caseCount++
            Write-Host ('C MULTI CASE={0} scan={1} recheck={2} validPairs={3} exact={4} addedPhysical={5} addedMemory={6} intervals={7}' -f
                $name,$scan.decision,$rechecked.decision,$accepted.Count,$originalHits.Count,$rechecked.metrics.additionalSourceBytesRead,$rechecked.metrics.additionalValidatorMemoryBytesRead,$rechecked.metrics.observedPhysicalReadIntervals)
        }finally{$instrumented.Dispose()}
        Assert-CMultiCandidate ((Get-A3DSha256 $bytes) -ceq $before) ($name+': artificial image SHA unchanged')
    }
    Assert-CMultiCandidate ($caseCount -eq 5 -and $truthTP -eq 3 -and $truthFP -eq 1 -and
        $missedCases -eq 1 -and $ambig -eq 1 -and $one -eq 2 -and $unknown -eq 2 -and
        $originalClaims -eq 0 -and $autoWinners -eq 0) 'five declared artificial truth/decision outcomes'
    Assert-CMultiCandidate ($baselineBytes -eq $recheckScanBytes -and
        $baselineValidator -eq $recheckScanValidator -and $baselinePairs -eq $recheckPairs) 'same source baseline scan and candidate scan budget/work'
    Assert-CMultiCandidate ($null -ne $altScan -and $null -ne $altTraces) 'alternate fixture available to negative controls'
    $accepted=@($altScan.items | Where-Object {$_.possible})
    Assert-CMultiCandidate ($accepted.Count -eq 2) 'two CRC-consistent candidates independently discovered'
    $firstNeeded=[int]($accepted[0].sourceSpans[0].lengthBytes+$accepted[0].sourceSpans[1].lengthBytes)
    # First physical recheck completes. The shared cap blocks a second
    # candidate with no phantom original selection or fabricated coverage.
    $cap=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($altBytes,$false))
    try{
        $r=Test-CMultiCandidateValidation -Source $cap -ScanResult $altScan -MaxSourceBytes $firstNeeded
        Assert-CMultiCandidate ($r.decision -eq 'incomplete' -and $r.reason -eq 'multi.shared_physical_budget' -and
            $r.metrics.candidateRechecks -eq 1 -and $cap.BytesRead -eq $firstNeeded -and
            $r.originalIdentity -eq 'unknown' -and $null -eq $r.selectedOriginal) 'second candidate quota keeps incomplete'
    }finally{$cap.Dispose()}
    # Independent fake short-ending stream: returns all first candidate bytes
    # in 17B chunks, then only 17B of second candidate followed by zero.
    $short=[ChappyCountingReadStream]::new([CArtificialShortValidationStream]::new([IO.MemoryStream]::new($altBytes,$false),($firstNeeded+17)))
    try{
        $r=Test-CMultiCandidateValidation -Source $short -ScanResult $altScan
        Assert-CMultiCandidate ($r.decision -eq 'incomplete' -and $r.reason -eq 'multi.candidate_partial' -and
            $r.metrics.candidateRechecks -eq 2 -and $short.BytesRead -eq ($firstNeeded+17) -and
            $r.candidateTraces[1].readBytes -eq 17 -and
            $r.candidateTraces[1].reason -eq 'validation.short_read') 'partial second physical return has only observed 17B'
    }finally{$short.Dispose()}
    # Reverse a known ordered physical candidate, NEVER promote its
    # reconstructed bytes based on mere unsigned read intervals.
    $reverse=[pscustomobject]@{sourceSpans=@($accepted[0].sourceSpans[1],$accepted[0].sourceSpans[0])}
    $reverseInput=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($altBytes,$false))
    try{
        $r=Test-CObservedCandidateValidation -Source $reverseInput -Candidate $reverse
        Assert-CMultiCandidate ($r.status -ne 'format_consistent' -and
            $r.candidateKey -cne $altTraces.candidateTraces[0].candidateKey -and
            $r.originalIdentity -eq 'unknown') 'different physical fragment order not original'
    }finally{$reverseInput.Dispose()}
    $writable=[IO.MemoryStream]::new($altBytes,$true)
    try{
        $denied=$false
        try{Test-CMultiCandidateValidation -Source $writable -ScanResult $altScan | Out-Null}catch{$denied=$true}
        Assert-CMultiCandidate $denied 'writable artificial source rejected'
    }finally{$writable.Dispose()}
    Write-Host ('C MULTI SYNTHETIC METRICS cases={0} pairs={1} TP={2} FP={3} FN_cases={4} TN_pairs={5} one={6} ambiguous={7} unknown={8} false_original_claims={9} auto_winners={10} baseline_scan_source_bytes={11} recheck_scan_source_bytes={12} extra_validation_source_bytes={13} scan_memory_bytes={14} extra_validation_memory_bytes={15} observed_intervals={16} additional_read_requests={17} baseline_scan_ms={18} recheck_scan_ms={19} additional_validator_ms={20} A_receipts_minted=0' -f
        $caseCount,$baselinePairs,$truthTP,$truthFP,$missedCases,$truthTN,$one,$ambig,$unknown,
        $originalClaims,$autoWinners,$baselineBytes,$recheckScanBytes,$additionalBytes,$baselineValidator,
        $additionalValidator,$intervals,$requests,$baselineMs,$recheckScanMs,$recheckMs)
    Write-Host 'PASS: C multi-candidate physical reread retains two distinct CRC-valid ZIP tails, guards missing/short/budget/reorder, and never selects original'
}
