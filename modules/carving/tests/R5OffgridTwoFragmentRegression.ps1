#requires -Version 5.1
# Team C Issue #72: external truth scorer only. Candidate search receives
# neither planted original SHA/offsets nor case label. All bytes invented.
function Assert-COffgrid([bool]$Okay,[string]$Reason) {
    if(-not $Okay){throw ('C_OFFGRID_FAIL: '+$Reason)}
}
function Invoke-COffgridTwoFragmentRegression {
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
    Assert-COffgrid ($cursor -eq $oracle.lengthBytes -and
        (Get-A3DSha256 $original) -ceq $oracle.sha256) 'independent invented file truth unchanged'

    $kinds=@('M01_control','non512_offgrid_tail','offgrid_first',
             'offgrid_plus_two','nonlisted_first_560',
             'alternate_zip_metadata','fake_eocd','missing_tail')
    $oldTP=0;$oldFP=0;$oldTN=0;$oldFN=0
    $newTP=0;$newFP=0;$newTN=0;$newFN=0
    $oldUnknown=0;$newUnknown=0;$newAmbiguous=0;$newPossible=0;$newIncomplete=0
    $oldBytes=0L;$newBytes=0L;$oldMemory=0L;$newMemory=0L
    $oldReadCalls=0;$newReadCalls=0;$oldPairs=0;$newPairs=0
    $oldStarts=0;$newStarts=0;$oldTails=0;$newTails=0
    $oldMs=0L;$newMs=0L;$unchanged=0;$originalClaims=0;$autoWinners=0
    $plusTwoImage=$null;$plusTwoScan=$null;$altImage=$null;$altScan=$null

    foreach($kind in $kinds){
        $fixture=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind $kind
        [byte[]]$image=$fixture.image
        $shaBefore=Get-A3DSha256 $image
        $oldStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($image,$false))
        try{
            $old=Test-CVariableZipPairs -Source $oldStream -WindowBytes 65536 -MaxStarts 4 -MaxTails 8 -MaxPairs 16 -MaxSourceBytes 81920 -MaxValidationBytes 98304 -MaxMilliseconds 30000
            Assert-COffgrid ($oldStream.BytesRead -eq $old.metrics.sourceBytesRead -and
                $oldStream.BytesRead -le 81920 -and $old.status -eq 'ok') ($kind+': baseline complete, actually read and bounded')
            $oldBytes += $oldStream.BytesRead
            $oldMemory += [long]$old.metrics.validatorBytesRead
            $oldReadCalls += [int]$old.metrics.readRequests
            $oldPairs += [int]$old.metrics.pairAttempts
            $oldStarts += [int]$old.metrics.startCandidates
            $oldTails += [int]$old.metrics.tailCandidates
            $oldMs += [long]$old.metrics.elapsedMilliseconds
        }finally{$oldStream.Dispose()}
        $newStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($image,$false))
        try{
            $trial=Test-CVariableZipPairs -Source $newStream -IncludeStartPhasePlusTwo -WindowBytes 65536 -MaxStarts 4 -MaxTails 8 -MaxPairs 16 -MaxSourceBytes 81920 -MaxValidationBytes 98304 -MaxMilliseconds 30000
            Assert-COffgrid ($newStream.BytesRead -eq $trial.metrics.sourceBytesRead -and
                $newStream.BytesRead -le 81920 -and $trial.metrics.validatorBytesRead -le 98304 -and
                $trial.metrics.pairAttempts -le 16 -and $trial.metrics.sectorProbes -eq 128) ($kind+': expanded phase bounded and actual bytes counted')
            Assert-COffgrid ($trial.status -eq 'ok') ($kind+': expanded scan complete in frozen corpus')
            $newBytes += $newStream.BytesRead
            $newMemory += [long]$trial.metrics.validatorBytesRead
            $newReadCalls += [int]$trial.metrics.readRequests
            $newPairs += [int]$trial.metrics.pairAttempts
            $newStarts += [int]$trial.metrics.startCandidates
            $newTails += [int]$trial.metrics.tailCandidates
            $newMs += [long]$trial.metrics.elapsedMilliseconds
        }finally{$newStream.Dispose()}
        Assert-COffgrid ((Get-A3DSha256 $image) -ceq $shaBefore) ($kind+': no artificial source mutation')
        $unchanged++

        $oldAccepted=@($old.items | Where-Object {$_.possible})
        $newAccepted=@($trial.items | Where-Object {$_.possible})
        $oldTrue=@($oldAccepted | Where-Object {$_.candidateSha256 -ceq $oracle.sha256})
        $newTrue=@($newAccepted | Where-Object {$_.candidateSha256 -ceq $oracle.sha256})
        $oldTP += $oldTrue.Count;$oldFP += ($oldAccepted.Count-$oldTrue.Count)
        $newTP += $newTrue.Count;$newFP += ($newAccepted.Count-$newTrue.Count)
        $oldTN += @($old.items | Where-Object {-not $_.possible}).Count
        $newTN += @($trial.items | Where-Object {-not $_.possible}).Count
        if($fixture.hasOriginal -and $oldTrue.Count -eq 0){$oldFN++}
        if($fixture.hasOriginal -and $newTrue.Count -eq 0){$newFN++}
        if($old.decision -eq 'unknown'){$oldUnknown++}
        switch($trial.decision){
            'unknown' {$newUnknown++}
            'one_possible' {$newPossible++}
            'ambiguous' {$newAmbiguous++}
            'incomplete' {$newIncomplete++}
        }
        $guard=Resolve-CFragmentFalseJoinEvidence -ScanResult $trial
        Assert-COffgrid ($guard.status -eq 'ok' -and $guard.decision -ceq $trial.decision -and
            $guard.metrics.additionalSourceBytesRead -eq 0 -and
            $guard.originalIdentity -eq 'unknown' -and -not $guard.canAutoSelectOriginal -and
            $null -eq $guard.selectedOriginal) ($kind+': policy preserves ambiguity without original winner')
        $autoWinners += $(if($null -ne $guard.selectedOriginal){1}else{0})
        foreach($item in $trial.items){
            Assert-COffgrid ($item.originalIdentity -ceq 'unknown' -and
                $item.integrityScope -ceq 'structural_only_not_original_file_integrity' -and
                $null -eq $item.PSObject.Properties['evidenceId'] -and
                $null -eq $item.PSObject.Properties['sourceToken']) ($kind+': no original claim or A-origin spoofing')
        }
        $originalClaims += @($trial.items | Where-Object {$_.originalIdentity -cne 'unknown'}).Count

        if($kind -eq 'offgrid_plus_two'){
            Assert-COffgrid ($old.decision -eq 'unknown' -and $oldTrue.Count -eq 0 -and
                $trial.decision -eq 'one_possible' -and $newTrue.Count -eq 1 -and
                $newAccepted.Count -eq 1) 'new +2 phase finds previously missed invented original'
            $plusTwoImage=$image;$plusTwoScan=$trial
        }
        if($kind -eq 'nonlisted_first_560'){
            Assert-COffgrid ($old.decision -eq 'unknown' -and $trial.decision -eq 'unknown' -and
                $newTrue.Count -eq 0) '560B start outside fixed choices stays unknown'
        }
        if($kind -eq 'alternate_zip_metadata'){
            Assert-COffgrid ($trial.decision -eq 'ambiguous' -and $newAccepted.Count -eq 2 -and
                $newTrue.Count -eq 1 -and $newFP -gt 0) 'CRC-consistent wrong ZIP tail retained alongside true'
            $altImage=$image;$altScan=$trial
        }
        if($kind -eq 'fake_eocd'){
            Assert-COffgrid ($trial.decision -eq 'one_possible' -and
                @($trial.items | Where-Object {-not $_.possible}).Count -gt 0) 'fake EOCD rejected, true survives'
        }
        if($kind -eq 'missing_tail'){
            Assert-COffgrid ($trial.decision -eq 'unknown' -and $newAccepted.Count -eq 0) 'missing genuine tail unknown'
        }
        Write-Host ('C OFFGRID CASE={0} old={1} new={2} oldTP={3} newTP={4} newFP={5} oldSource={6} newSource={7} oldMemory={8} newMemory={9} oldPairs={10} newPairs={11}' -f
            $kind,$old.decision,$trial.decision,$oldTrue.Count,$newTrue.Count,($newAccepted.Count-$newTrue.Count),
            $old.metrics.sourceBytesRead,$trial.metrics.sourceBytesRead,$old.metrics.validatorBytesRead,$trial.metrics.validatorBytesRead,
            $old.metrics.pairAttempts,$trial.metrics.pairAttempts)
    }
    Assert-COffgrid ($unchanged -eq 8 -and $null -ne $plusTwoScan -and $null -ne $altScan) 'all eight independent fixture cases scored'
    Assert-COffgrid ($newTP -eq ($oldTP+1) -and $newFP -eq $oldFP -and
        $newFN -eq ($oldFN-1) -and $newIncomplete -eq 0) 'only +2 known-original candidate gained; no new false original or loss'
    Assert-COffgrid ($newAmbiguous -eq 1 -and $newUnknown -eq ($oldUnknown-1) -and
        $originalClaims -eq 0 -and $autoWinners -eq 0) 'ambiguity and unknown not promoted to original'
    Assert-COffgrid ($newMemory -le (8L*98304L) -and $newBytes -le (8L*81920L)) 'aggregate bounds across eight cases'

    # Unsigned/reversed physical candidate ordering cannot validate as the
    # same original. Only artificial scorer knows the original SHA.
    $truePlusTwo=@($plusTwoScan.items | Where-Object {$_.possible})[0]
    $reverse=[pscustomobject]@{sourceSpans=@($truePlusTwo.sourceSpans[1],$truePlusTwo.sourceSpans[0])}
    $reverseStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($plusTwoImage,$false))
    try{
        $result=Test-CObservedCandidateValidation -Source $reverseStream -Candidate $reverse
        Assert-COffgrid ($result.status -ne 'format_consistent' -and
            $result.originalIdentity -eq 'unknown' -and
            $reverseStream.BytesRead -eq $result.metrics.sourceBytesRead) 'reversed physical fragment order rejected'
    }finally{$reverseStream.Dispose()}

    # Partial Source.Read(17B) then EOF cannot certify full coverage.
    $short=[ChappyCountingReadStream]::new([CArtificialShortValidationStream]::new([IO.MemoryStream]::new($plusTwoImage,$false),17))
    try{
        $result=Test-CVariableZipPairs -Source $short -IncludeStartPhasePlusTwo
        Assert-COffgrid ($result.status -eq 'partial' -and $result.decision -eq 'incomplete' -and
            $result.metrics.sourceBytesRead -eq 17 -and $short.BytesRead -eq 17 -and
            @($result.items).Count -eq 0) 'short source return cannot be complete discovery'
    }finally{$short.Dispose()}

    # A deliberately invented extra PK-start at sector+2 must not be
    # cherry-picked if start hypotheses exceed a reduced bound.
    [byte[]]$flood=[byte[]]$altImage.Clone()
    [Array]::Copy([byte[]]@(0x50,0x4b,0x03,0x04),0,$flood,(65024+2),4)
    $floodStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($flood,$false))
    try{
        $result=Test-CVariableZipPairs -Source $floodStream -IncludeStartPhasePlusTwo -MaxStarts 1
        Assert-COffgrid ($result.status -eq 'partial' -and $result.decision -eq 'incomplete' -and
            $result.metrics.stopCode -eq 'search.start_limit' -and
            @($result.items).Count -eq 0 -and $floodStream.BytesRead -eq $result.metrics.sourceBytesRead) 'extra fake +2 PK cannot cherry-pick true start'
    }finally{$floodStream.Dispose()}

    $cap=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($plusTwoImage,$false))
    try{
        $result=Test-CVariableZipPairs -Source $cap -IncludeStartPhasePlusTwo -MaxSourceBytes 1024
        Assert-COffgrid ($result.status -eq 'partial' -and $result.decision -eq 'incomplete' -and
            $result.metrics.sourceBytesRead -eq 0 -and $cap.BytesRead -eq 0) 'too-small source budget no reads'
    }finally{$cap.Dispose()}

    $writable=[IO.MemoryStream]::new($plusTwoImage,$true)
    try{
        $denied=$false
        try{Test-CVariableZipPairs -Source $writable -IncludeStartPhasePlusTwo | Out-Null}catch{$denied=$true}
        Assert-COffgrid $denied 'writable source forbidden'
    }finally{$writable.Dispose()}

    Write-Host ('C OFFGRID SYNTHETIC METRICS cases={0} old_TP={1} old_FP={2} old_FN_cases={3} old_TN_pairs={4} new_TP={5} new_FP={6} new_FN_cases={7} new_TN_pairs={8} old_unknown={9} new_unknown={10} new_one_possible={11} new_ambiguous={12} new_incomplete={13} old_source_bytes={14} new_source_bytes={15} old_memory_bytes={16} new_memory_bytes={17} old_read_calls={18} new_read_calls={19} old_pairs={20} new_pairs={21} old_start_hypotheses={22} new_start_hypotheses={23} old_tail_hypotheses={24} new_tail_hypotheses={25} old_elapsed_ms={26} new_elapsed_ms={27} false_original_claims={28} original_auto_selections={29} A_receipts_minted=0' -f
        $unchanged,$oldTP,$oldFP,$oldFN,$oldTN,$newTP,$newFP,$newFN,$newTN,
        $oldUnknown,$newUnknown,$newPossible,$newAmbiguous,$newIncomplete,
        $oldBytes,$newBytes,$oldMemory,$newMemory,$oldReadCalls,$newReadCalls,
        $oldPairs,$newPairs,$oldStarts,$newStarts,$oldTails,$newTails,$oldMs,$newMs,
        $originalClaims,$autoWinners)
    Write-Host 'PASS: C R5 opt-in +2 start-phase coverage, CRC-consistent decoy ambiguity, false EOCD, +560 unsupported, partial and cap fail closed'
}
