#requires -Version 5.1
# Team C R5 Issue #72. External artificial truth scorer is the ONLY
# component allowed to use original SHA and scenario labels.
function Assert-CFalseJoin([bool]$Ok,[string]$Why) {
    if(-not $Ok){throw ('C_FALSEJOIN_FAIL: '+$Why)}
}
function Invoke-CFalseJoinNegativeRegression {
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
    $clean=New-ChappyA3DCleanFixture -Seed 202611
    $oracle=$clean.oracle[1]
    [byte[]]$original=New-Object byte[] ([int]$oracle.lengthBytes)
    $cursor=0
    foreach($span in $oracle.extents){
        [Array]::Copy($clean.image,[int]$span.offsetBytes,$original,$cursor,[int]$span.lengthBytes)
        $cursor += [int]$span.lengthBytes
    }
    Assert-CFalseJoin ($cursor -eq $oracle.lengthBytes -and
        (Get-A3DSha256 $original) -ceq $oracle.sha256) 'independent synthetic original oracle'
    $scenarioNames=@(
        'M01_control','non512_offgrid_tail','alternate_zip_metadata',
        'fake_eocd','missing_tail','offgrid_plus_two','nonlisted_first_560'
    )
    $baseTP=0;$baseFP=0;$baseFN=0;$baseTN=0
    $newTP=0;$newFP=0;$newFN=0;$newTN=0
    $originalSelections=0;$unique=0;$ambiguous=0;$unknown=0
    $originalExact=0;$falseOriginalClaims=0
    $baselineSource=0L;$guardSource=0L
    $baselineMemory=0L;$guardMemory=0L
    $baselinePairs=0;$guardPairs=0
    $baselineMs=0L;$guardScannerMs=0L;$guardDecisionMs=0L
    $allSourcesUnchanged=0
    $altScan=$null;$altEvidence=$null
    foreach($name in $scenarioNames){
        $fixture=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind $name
        [byte[]]$bytes=$fixture.image
        $initialSha=Get-A3DSha256 $bytes
        $oldStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($bytes,$false))
        try{
            $baseline=Test-CVariableZipPairs -Source $oldStream -WindowBytes 65536 -MaxSourceBytes 81920 -MaxPairs 16 -MaxStarts 4 -MaxTails 8 -MaxValidationBytes 98304 -MaxMilliseconds 30000
            Assert-CFalseJoin ($oldStream.BytesRead -eq $baseline.metrics.sourceBytesRead -and
                $oldStream.BytesRead -le 81920) ($name+': actual baseline source bytes')
            $baselineSource += $oldStream.BytesRead
            $baselineMemory += [long]$baseline.metrics.validatorBytesRead
            $baselinePairs += [int]$baseline.metrics.pairAttempts
            $baselineMs += [long]$baseline.metrics.elapsedMilliseconds
        }finally{$oldStream.Dispose()}
        $newStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($bytes,$false))
        try{
            $scan=Test-CVariableZipPairs -Source $newStream -WindowBytes 65536 -MaxSourceBytes 81920 -MaxPairs 16 -MaxStarts 4 -MaxTails 8 -MaxValidationBytes 98304 -MaxMilliseconds 30000
            $beforeDecision=$newStream.BytesRead
            $safe=Resolve-CFragmentFalseJoinEvidence -ScanResult $scan -MaxPairs 16 -MaxSourceBytes 81920 -MaxValidatorBytes 98304
            Assert-CFalseJoin ($beforeDecision -eq $newStream.BytesRead -and
                $safe.metrics.additionalSourceBytesRead -eq 0 -and
                $safe.metrics.additionalMemoryValidatorBytesRead -eq 0) ($name+': guard adds no physical or validator reads')
            Assert-CFalseJoin ($newStream.BytesRead -eq $scan.metrics.sourceBytesRead -and
                $newStream.BytesRead -le 81920) ($name+': same bounded scanner source reads')
            Assert-CFalseJoin ($safe.status -eq 'ok' -and $scan.status -eq 'ok' -and
                $safe.decision -ceq $scan.decision) ($name+': no falsified scanner decision')
            Assert-CFalseJoin ($safe.originalIdentity -ceq 'unknown' -and
                -not $safe.canAutoSelectOriginal -and $null -eq $safe.selectedOriginal) ($name+': no original promotion or winner')
            $guardSource += $newStream.BytesRead
            $guardMemory += [long]$scan.metrics.validatorBytesRead
            $guardPairs += [int]$scan.metrics.pairAttempts
            $guardScannerMs += [long]$scan.metrics.elapsedMilliseconds
            $guardDecisionMs += [long]$safe.metrics.elapsedMilliseconds
        }finally{$newStream.Dispose()}
        Assert-CFalseJoin ((Get-A3DSha256 $bytes) -ceq $initialSha) ($name+': artificial image SHA unchanged')
        Assert-CFalseJoin ($baseline.metrics.sourceBytesRead -eq $scan.metrics.sourceBytesRead -and
            $baseline.metrics.validatorBytesRead -eq $scan.metrics.validatorBytesRead -and
            $baseline.metrics.pairAttempts -eq $scan.metrics.pairAttempts) ($name+': same data same scan/probe/byte costs')
        $baseAccepted=@($baseline.items | Where-Object {$_.possible})
        $newAccepted=@($scan.items | Where-Object {$_.possible})
        $baseTrue=@($baseAccepted | Where-Object {$_.candidateSha256 -ceq $oracle.sha256})
        $newTrue=@($newAccepted | Where-Object {$_.candidateSha256 -ceq $oracle.sha256})
        $baseTP += $baseTrue.Count
        $baseFP += $baseAccepted.Count-$baseTrue.Count
        $baseTN += @($baseline.items | Where-Object {-not $_.possible}).Count
        $newTP += $newTrue.Count
        $newFP += $newAccepted.Count-$newTrue.Count
        $newTN += @($scan.items | Where-Object {-not $_.possible}).Count
        if($fixture.hasOriginal -and $baseTrue.Count -eq 0){$baseFN++}
        if($fixture.hasOriginal -and $newTrue.Count -eq 0){$newFN++}
        $originalExact += $newTrue.Count
        $falseOriginalClaims += @($safe.formatConsistentHypotheses | Where-Object {$_.originalIdentity -cne 'unknown'}).Count
        $originalSelections += $(if($null -ne $safe.selectedOriginal){1}else{0})
        switch($safe.decision){
            'one_possible' {$unique++}
            'ambiguous' {$ambiguous++}
            'unknown' {$unknown++}
        }
        if($name -eq 'alternate_zip_metadata'){
            $altScan=$scan;$altEvidence=$safe
            Assert-CFalseJoin ($safe.decision -eq 'ambiguous' -and
                @($safe.formatConsistentHypotheses).Count -eq 2 -and
                $newTrue.Count -eq 1 -and $newAccepted.Count -eq 2) 'CRC-valid metadata alternative is not original winner'
            $keys=@($safe.formatConsistentHypotheses | ForEach-Object {$_.candidateKey})
            Assert-CFalseJoin ($keys[0] -cne $keys[1]) 'distinct ordered physical source identities preserved'
        }elseif($name -in @('offgrid_plus_two','nonlisted_first_560','missing_tail')){
            Assert-CFalseJoin ($safe.decision -eq 'unknown' -and
                $safe.formatConsistentHypotheses.Count -eq 0) ($name+': no fabricated original')
        }else{
            Assert-CFalseJoin ($safe.decision -eq 'one_possible' -and
                $safe.formatConsistentHypotheses.Count -eq 1) ($name+': possible is not verified original')
        }
        $allSourcesUnchanged++
        Write-Host ('C FALSEJOIN CASE={0} baseline={1} safe={2} accepted={3} byte_exact={4} source_bytes={5} memory_validator_bytes={6} pair_attempts={7}' -f
            $name,$baseline.decision,$safe.decision,$newAccepted.Count,$newTrue.Count,$scan.metrics.sourceBytesRead,$scan.metrics.validatorBytesRead,$scan.metrics.pairAttempts)
    }
    Assert-CFalseJoin ($baseTP -eq 4 -and $baseFP -eq 1 -and $baseFN -eq 2) 'old artificial truth outcomes'
    Assert-CFalseJoin ($newTP -eq $baseTP -and $newFP -eq $baseFP -and
        $newFN -eq $baseFN -and $newTN -eq $baseTN) 'guard has same candidate-level truth, no invented accuracy'
    Assert-CFalseJoin ($unique -eq 3 -and $ambiguous -eq 1 -and $unknown -eq 3 -and
        $originalExact -eq 4 -and $falseOriginalClaims -eq 0 -and
        $originalSelections -eq 0) 'uncertainty preserved, no winner'
    Assert-CFalseJoin ($baselineSource -eq $guardSource -and
        $baselineMemory -eq $guardMemory -and
        $baselinePairs -eq $guardPairs) 'equal physical and validator costs; decision-only guard'
    Assert-CFalseJoin ($null -ne $altScan -and $null -ne $altEvidence) 'ambiguous case retained for negative contracts'
    # A duplicate *hypothesis record*, separately introduced as deliberately
    # malformed test input, must NOT be mistaken for two independent originals.
    $validAlt=@($altScan.items | Where-Object {$_.possible})
    $duplicated=[pscustomobject]@{
        status='ok';decision='ambiguous';metrics=$altScan.metrics
        items=@($validAlt[0],$validAlt[1],$validAlt[0])
    }
    $dupe=Resolve-CFragmentFalseJoinEvidence -ScanResult $duplicated
    Assert-CFalseJoin ($dupe.status -eq 'partial' -and $dupe.decision -eq 'incomplete' -and
        $dupe.reason -ceq 'guard.duplicate_physical_hypothesis' -and
        $null -eq $dupe.selectedOriginal) 'duplicate physical identity blocks auto-selection'
    # Partial scan/budget is never made safe by a plausible prefix candidate.
    $incomplete=[pscustomobject]@{
        status='partial';decision='incomplete';metrics=$altScan.metrics
        items=@($validAlt)
    }
    $blocked=Resolve-CFragmentFalseJoinEvidence -ScanResult $incomplete
    Assert-CFalseJoin ($blocked.decision -eq 'incomplete' -and $blocked.formatConsistentHypotheses.Count -eq 0) 'incomplete upstream search cannot be promoted'
    # Adversarial untrusted RESULT metadata, not altered original fixture
    # labels: the guard must detect a scanner lying about ambiguity.
    $concealed=[pscustomobject]@{
        status='ok';decision='one_possible';metrics=$altScan.metrics
        items=@($altScan.items)
    }
    $notUnique=Resolve-CFragmentFalseJoinEvidence -ScanResult $concealed
    Assert-CFalseJoin ($notUnique.status -eq 'partial' -and
        $notUnique.decision -eq 'incomplete' -and
        $notUnique.reason -ceq 'guard.scan_decision_mismatch' -and
        $null -eq $notUnique.selectedOriginal) 'claimed single must not hide two CRC-consistent joins'
    # A forged original verified field cannot be accepted from the C scan.
    $forged=[pscustomobject]@{
        possible=$true;originalIdentity='verified'
        integrityScope='structural_only_not_original_file_integrity'
        sourceSpans=@($validAlt[0].sourceSpans)
    }
    $forgedScan=[pscustomobject]@{
        status='ok';decision='one_possible';metrics=$altScan.metrics
        items=@($forged)
    }
    $forgedResult=Resolve-CFragmentFalseJoinEvidence -ScanResult $forgedScan
    Assert-CFalseJoin ($forgedResult.status -eq 'partial' -and
        $forgedResult.reason -ceq 'guard.invalid_original_claim' -and
        $null -eq $forgedResult.selectedOriginal) 'forged original claim rejected'
    $badNumbers=[pscustomobject]@{
        status='ok';decision='unknown';items=@()
        metrics=[pscustomobject]@{
            pairAttempts=-1;sourceBytesRead=-1;validatorBytesRead=-1
        }
    }
    $negativeMetrics=Resolve-CFragmentFalseJoinEvidence -ScanResult $badNumbers
    Assert-CFalseJoin ($negativeMetrics.decision -eq 'incomplete' -and
        $negativeMetrics.reason -ceq 'guard.invalid_metrics') 'negative read metrics cannot certify evidence'
    $budgetStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($clean.image,$false))
    try{
        $over=Test-CVariableZipPairs -Source $budgetStream -MaxSourceBytes 4096
        $guard=Resolve-CFragmentFalseJoinEvidence -ScanResult $over
        Assert-CFalseJoin ($guard.status -eq 'partial' -and $guard.decision -eq 'incomplete' -and
            $guard.metrics.additionalSourceBytesRead -eq 0 -and
            $budgetStream.BytesRead -eq 0) 'too-small source quota fails closed before reads'
    }finally{$budgetStream.Dispose()}
    Write-Host ('C FALSEJOIN SYNTHETIC METRICS cases={0} pair_trials={1} baseline_TP={2} baseline_FP={3} baseline_FN={4} baseline_TN={5} guard_TP={6} guard_FP={7} guard_FN={8} guard_TN={9} unique={10} ambiguous={11} unknown={12} clean_SHA_matches={13} false_original_claims={14} original_auto_selections={15} source_bytes_each_path={16} memory_validator_bytes_each_path={17} baseline_scan_ms={18} guard_scan_ms={19} decision_only_ms={20} guard_extra_reads=0' -f
        $allSourcesUnchanged,$baselinePairs,$baseTP,$baseFP,$baseFN,$baseTN,
        $newTP,$newFP,$newFN,$newTN,$unique,$ambiguous,$unknown,$originalExact,
        $falseOriginalClaims,$originalSelections,$baselineSource,$baselineMemory,$baselineMs,$guardScannerMs,$guardDecisionMs)
    Write-Host 'PASS: C R5 true ordered fragment hypotheses retained, CRC-consistent false join remains ambiguous, off-grid/missing unknown, original winner withheld'
}
