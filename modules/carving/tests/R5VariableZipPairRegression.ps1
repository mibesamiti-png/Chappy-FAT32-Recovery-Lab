#requires -Version 5.1
# Team C Issue #72 external scorer. Only this test knows artificial
# source extents, first-piece length, deliberate mutations or original SHA.
function Assert-CVariable([bool]$Ok,[string]$Why) {
    if(-not $Ok){throw ('C_VARIABLE_FAIL: '+$Why)}
}
function New-CVariableSyntheticCase([byte[]]$CleanImage,[byte[]]$Original,[string]$Kind) {
    [byte[]]$image=[byte[]]$CleanImage.Clone()
    $firstBase=58880;$tailBase=60416
    [Array]::Clear($image,$firstBase,1024)
    $firstLen=if($Kind -eq 'M01_control' -or $Kind -eq 'offgrid_first') {512} else {544}
    $firstPhase=if($Kind -eq 'offgrid_first'){1}else{0}
    $tailPhase=if($Kind -in @('non512_offgrid_tail','fake_eocd','alternate_zip_metadata')){1}else{0}
    Assert-CVariable ($Original.Length -gt $firstLen -and $Original.Length-$firstLen -le 512) 'constructed artificial prefix/suffix fit one bounded tail'
    [Array]::Copy($Original,0,$image,($firstBase+$firstPhase),$firstLen)
    $hasTail=($Kind -ne 'missing_tail')
    if($hasTail) {
        [Array]::Copy($Original,$firstLen,$image,($tailBase+$tailPhase),($Original.Length-$firstLen))
    }
    if($Kind -eq 'fake_eocd'){
        # EOCD-shaped false positive in an invented unused sector.
        [Array]::Copy([byte[]]@(0x50,0x4b,0x05,0x06),0,$image,(61440+24),4)
    }
    if($Kind -eq 'alternate_zip_metadata'){
        [byte[]]$altered=[byte[]]$Original.Clone()
        $mark=-1
        for($k=$firstLen;$k -le $Original.Length-46;$k++){
            if([BitConverter]::ToUInt32($altered,$k) -eq 0x02014B50){$mark=$k+4;break}
        }
        Assert-CVariable ($mark -ge $firstLen) 'independent modified ZIP metadata is in tail'
        $altered[$mark]=[byte]($altered[$mark] -bxor 1)
        [Array]::Copy($altered,$firstLen,$image,(61952+1),($altered.Length-$firstLen))
    }
    return [pscustomobject]@{
        image=$image;hasOriginal=$hasTail
        trueFirst=$firstBase+$firstPhase
        trueSecond=$tailBase+$tailPhase
        trueFirstBytes=$firstLen
        trueSecondBytes=$Original.Length-$firstLen
    }
}
function Invoke-CVariableFragmentEvidence {
    $repo=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $repo 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
    $clean=New-ChappyA3DCleanFixture -Seed 202611
    $truth=$clean.oracle[1]
    [byte[]]$original=New-Object byte[] ([int]$truth.lengthBytes)
    $written=0
    foreach($span in $truth.extents){
        [Array]::Copy($clean.image,[int]$span.offsetBytes,$original,$written,[int]$span.lengthBytes)
        $written+=[int]$span.lengthBytes
    }
    Assert-CVariable ($written -eq $truth.lengthBytes -and (Get-A3DSha256 $original) -ceq $truth.sha256) 'independent invented source truth'
    $cases=@('M01_control','non512_offgrid_tail','offgrid_first','fake_eocd','alternate_zip_metadata','missing_tail')
    $baselineTP=0;$baselineFP=0;$baselineFN=0;$baselineTN=0
    $trialTP=0;$trialFP=0;$trialFN=0;$trialTN=0
    $baselineBytes=0L;$trialBytes=0L;$baselineMemory=0L;$trialMemory=0L
    $basePairs=0;$testPairs=0;$testStarts=0;$testTails=0;$testProbes=0
    $baseMs=0L;$trialMs=0L
    $single=0;$ambiguous=0;$unknown=0;$falseOriginal=0
    foreach($kind in $cases){
        $case=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind $kind
        $before=Get-A3DSha256 $case.image
        $a=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($case.image,$false))
        try{
            $old=Test-CM01FiniteZipPairs -Source $a
            Assert-CVariable ($a.BytesRead -eq $old.metrics.sourceBytesRead -and $a.BytesRead -le 73728) ($kind+': original helper bounded source reads')
            $baselineBytes += $a.BytesRead
            $baselineMemory += [long]$old.metrics.validatorBytesRead
            $basePairs += [int]$old.metrics.pairsEvaluated
            $baseMs += [long]$old.metrics.elapsedMilliseconds
        }finally{$a.Dispose()}
        $b=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($case.image,$false))
        try{
            $result=Test-CVariableZipPairs -Source $b -WindowBytes 65536 -MaxSourceBytes 81920 -MaxPairs 16 -MaxStarts 4 -MaxTails 8 -MaxValidationBytes 98304
            Assert-CVariable ($b.BytesRead -eq $result.metrics.sourceBytesRead -and $b.BytesRead -le 81920) ($kind+': actual research source I/O matches')
            Assert-CVariable ($result.metrics.validatorBytesRead -le 98304 -and $result.metrics.pairAttempts -le 16 -and $result.metrics.sectorProbes -eq 128) ($kind+': bounded validation and scan')
            Assert-CVariable (-not $b.CanWrite) ($kind+': input is strictly nonwritable')
            $trialBytes += $b.BytesRead
            $trialMemory += [long]$result.metrics.validatorBytesRead
            $testPairs += [int]$result.metrics.pairAttempts
            $testStarts += [int]$result.metrics.startCandidates
            $testTails += [int]$result.metrics.tailCandidates
            $testProbes += [int]$result.metrics.sectorProbes
            $trialMs += [long]$result.metrics.elapsedMilliseconds
        }finally{$b.Dispose()}
        Assert-CVariable ((Get-A3DSha256 $case.image) -ceq $before) ($kind+': artificial source SHA invariant')

        $oldAccepted=@($old.items | Where-Object {$_.possible})
        $oldCorrect=@($oldAccepted | Where-Object {$_.candidateSha256 -ceq $truth.sha256})
        $newAccepted=@($result.items | Where-Object {$_.possible})
        $newCorrect=@($newAccepted | Where-Object {$_.candidateSha256 -ceq $truth.sha256})
        $baselineTP += $oldCorrect.Count
        $baselineFP += ($oldAccepted.Count-$oldCorrect.Count)
        $trialTP += $newCorrect.Count
        $trialFP += ($newAccepted.Count-$newCorrect.Count)
        $baselineTN += @($old.items | Where-Object {-not $_.possible}).Count
        $trialTN += @($result.items | Where-Object {-not $_.possible}).Count
        if($case.hasOriginal -and $oldCorrect.Count -eq 0){$baselineFN++}
        if($case.hasOriginal -and $newCorrect.Count -eq 0){$trialFN++}
        foreach($item in $result.items){
            Assert-CVariable ($item.originalIdentity -ceq 'unknown' -and $item.integrityScope -ceq 'structural_only_not_original_file_integrity') ($kind+': no false original-file provenance')
        }
        $falseOriginal += @($result.items | Where-Object {$_.originalIdentity -cne 'unknown'}).Count
        if($kind -eq 'M01_control'){
            Assert-CVariable ($oldCorrect.Count -eq 1 -and $newCorrect.Count -eq 1) 'unchanged 512B-aligned positive control'
        }
        if($kind -eq 'missing_tail'){
            Assert-CVariable ($result.status -eq 'ok' -and $result.decision -eq 'unknown' -and $newAccepted.Count -eq 0) 'tail absent stays unknown'
        } else {
            Assert-CVariable ($result.status -eq 'ok' -and $newCorrect.Count -eq 1) ($kind+': exactly one artificial exact original candidate')
        }
        if($kind -eq 'alternate_zip_metadata'){
            Assert-CVariable ($result.decision -eq 'ambiguous' -and $newAccepted.Count -eq 2) 'structurally valid wrong metadata tail never chosen as original'
        }
        if($kind -eq 'fake_eocd'){
            Assert-CVariable ($result.metrics.tailCandidates -ge 4 -and @($result.items | Where-Object {-not $_.possible}).Count -gt 0) 'false EOCD discovered then rejected'
        }
        if($result.decision -eq 'one_possible'){$single++}
        elseif($result.decision -eq 'ambiguous'){$ambiguous++}
        elseif($result.decision -eq 'unknown'){$unknown++}
        Write-Host ('C VARIABLE CASE={0} old={1} candidate={2} starts={3} tails={4} pairs={5} exact={6} plausible_wrong={7} source_bytes={8} memory_bytes={9}' -f
            $kind,$old.decision,$result.decision,$result.metrics.startCandidates,$result.metrics.tailCandidates,$result.metrics.pairAttempts,$newCorrect.Count,($newAccepted.Count-$newCorrect.Count),$result.metrics.sourceBytesRead,$result.metrics.validatorBytesRead)
    }
    Assert-CVariable ($trialTP -eq 5 -and $trialFP -eq 1 -and $trialFN -eq 0) 'independent 5 present originals and 1 plausible false metadata join'
    Assert-CVariable ($single -eq 4 -and $ambiguous -eq 1 -and $unknown -eq 1 -and $falseOriginal -eq 0) 'four unique one ambiguous one unknown and no original claim'
    Write-Host ('C VARIABLE SYNTHETIC METRICS cases=6 old_TP={0} old_FP={1} old_FN={2} old_TN={3} test_TP={4} test_FP={5} test_FN={6} test_TN={7} single={8} ambiguous={9} unknown={10} baseline_source_bytes={11} test_source_bytes={12} baseline_memory_bytes={13} test_memory_bytes={14} baseline_pairs={15} test_pairs={16} test_starts={17} test_tails={18} grid_probes={19} baseline_ms={20} test_ms={21} false_original_claims={22}' -f
        $baselineTP,$baselineFP,$baselineFN,$baselineTN,$trialTP,$trialFP,$trialFN,$trialTN,$single,$ambiguous,$unknown,$baselineBytes,$trialBytes,$baselineMemory,$trialMemory,$basePairs,$testPairs,$testStarts,$testTails,$testProbes,$baseMs,$trialMs,$falseOriginal)
    $missing=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind 'missing_tail'
    $small=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($missing.image,$false))
    try{
        $guard=Test-CVariableZipPairs -Source $small -MaxSourceBytes 4096
        Assert-CVariable ($guard.status -eq 'partial' -and $guard.decision -eq 'incomplete' -and $guard.metrics.sourceBytesRead -eq 0 -and $small.BytesRead -eq 0) 'small source quota fails before scouting'
    }finally{$small.Dispose()}
    $cut=[IO.MemoryStream]::new($missing.image,0,32768,$false)
    try{
        $guard=Test-CVariableZipPairs -Source $cut
        Assert-CVariable ($guard.status -eq 'partial' -and $guard.decision -eq 'incomplete' -and $guard.metrics.sourceBytesRead -eq 0) 'truncated search window fails closed'
    }finally{$cut.Dispose()}
    $writeable=[IO.MemoryStream]::new($missing.image,$true)
    try{
        $denied=$false
        try{Test-CVariableZipPairs -Source $writeable | Out-Null}catch{$denied=$true}
        Assert-CVariable $denied 'writable source refused'
    }finally{$writeable.Dispose()}
    $fake=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind 'fake_eocd'
    $over=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($fake.image,$false))
    try{
        $guard=Test-CVariableZipPairs -Source $over -MaxPairs 1
        Assert-CVariable ($guard.status -eq 'partial' -and $guard.decision -eq 'incomplete' -and $guard.metrics.pairAttempts -eq 0 -and @($guard.items).Count -eq 0) 'pair flood fails before choosing true item'
        Assert-CVariable ($over.BytesRead -eq $guard.metrics.sourceBytesRead -and $over.BytesRead -le 81920) 'pair overflow read budget'
    }finally{$over.Dispose()}
    Write-Host 'PASS: C variable 512/544 and off-grid two-piece ZIP synthetic A/B; missing/fake/ambiguous and quota guards'
}
