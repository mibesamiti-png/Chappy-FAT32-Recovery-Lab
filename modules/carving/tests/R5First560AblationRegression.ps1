#requires -Version 5.1
# Team C Issue #72: 560B first-piece hypothesis is DEFAULT OFF.
# This independent scorer alone knows original SHA, physical positions,
# fixture labels, and which byte-identical candidate is true.
function Assert-CFirst560([bool]$Okay,[string]$Why){
    if(-not $Okay){throw ('C_560_FAIL: '+$Why)}
}
function Invoke-CFirst560AblationRegression {
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
    $clean=New-ChappyA3DCleanFixture -Seed 202611
    $truth=$clean.oracle[1]
    [byte[]]$original=New-Object byte[] ([int]$truth.lengthBytes)
    $cursor=0
    foreach($e in $truth.extents){
        [Array]::Copy($clean.image,[int]$e.offsetBytes,$original,$cursor,[int]$e.lengthBytes)
        $cursor += [int]$e.lengthBytes
    }
    Assert-CFirst560 ($cursor -eq $truth.lengthBytes -and
        (Get-A3DSha256 $original) -ceq $truth.sha256) 'independently reconstructed artificial oracle'
    $kinds=@('M01_control','non512_offgrid_tail','offgrid_first','offgrid_plus_two',
             'nonlisted_first_560','alternate_zip_metadata','fake_eocd','missing_tail')
    $arms=@('default','plus2','len560','both')
    $totals=@{};$results=@{}
    foreach($arm in $arms){
        $totals[$arm]=[pscustomobject]@{
            cases=0;tp=0;fp=0;tn=0;fnCases=0;unknown=0;ambiguous=0
            possible=0;incomplete=0;physical=0L;memory=0L;readCalls=0
            starts=0;tails=0;pairs=0;sectors=0;elapsedMs=0L
            originalSelections=0;falseOriginalClaims=0;sourceUnchanged=0
        }
    }
    foreach($kind in $kinds){
        $fixture=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind $kind
        [byte[]]$bytes=$fixture.image
        $originalInputSha=Get-A3DSha256 $bytes
        $results[$kind]=@{}
        foreach($arm in $arms){
            # Selection is an experimental control, not information about
            # the correct first piece or original byte identity.
            $flags=@{}
            if($arm -in @('plus2','both')){$flags['IncludeStartPhasePlusTwo']=$true}
            if($arm -in @('len560','both')){$flags['IncludeFirstPiece560']=$true}
            $input=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($bytes,$false))
            try{
                $scan=Test-CVariableZipPairs -Source $input -WindowBytes 65536 -MaxStarts 4 -MaxTails 8 -MaxPairs 16 -MaxSourceBytes 81920 -MaxValidationBytes 98304 -MaxMilliseconds 30000 @flags
                Assert-CFirst560 ($scan.status -eq 'ok' -and
                    $scan.metrics.sectorProbes -eq 128 -and
                    $input.BytesRead -eq $scan.metrics.sourceBytesRead -and
                    $input.BytesRead -le 81920 -and $scan.metrics.validatorBytesRead -le 98304 -and
                    $scan.metrics.pairAttempts -le 16 -and -not $input.CanWrite) ($kind+'/'+$arm+': same cap and fully metered stream')
                $guard=Resolve-CFragmentFalseJoinEvidence -ScanResult $scan -AllowFirstPiece560:($arm -in @('len560','both'))
                Assert-CFirst560 ($guard.status -eq 'ok' -and
                    $guard.decision -ceq $scan.decision -and
                    $guard.originalIdentity -ceq 'unknown' -and
                    $null -eq $guard.selectedOriginal -and
                    -not $guard.canAutoSelectOriginal -and
                    $guard.metrics.additionalSourceBytesRead -eq 0) ($kind+'/'+$arm+': no original promotion')
                if($kind -eq 'nonlisted_first_560' -and $arm -eq 'len560'){
                    $oldGuard=Resolve-CFragmentFalseJoinEvidence -ScanResult $scan
                    Assert-CFirst560 ($oldGuard.status -eq 'partial' -and
                        $oldGuard.decision -eq 'incomplete' -and
                        $oldGuard.reason -eq 'guard.invalid_physical_spans' -and
                        $null -eq $oldGuard.selectedOriginal) 'old 544B guard refuses unreviewed 560B hypothesis unless explicitly enabled'
                }
                $accepted=@($scan.items | Where-Object {$_.possible})
                $exact=@($accepted | Where-Object {$_.candidateSha256 -ceq $truth.sha256})
                $rejected=@($scan.items | Where-Object {-not $_.possible})
                foreach($pair in $scan.items){
                    Assert-CFirst560 ($pair.originalIdentity -ceq 'unknown' -and
                        $pair.integrityScope -ceq 'structural_only_not_original_file_integrity' -and
                        $null -eq $pair.PSObject.Properties['evidenceId'] -and
                        $null -eq $pair.PSObject.Properties['sourceToken']) ($kind+'/'+$arm+': no spoofed A receipt or original SHA inference')
                }
                $total=$totals[$arm];$total.cases++
                $total.tp += $exact.Count
                $total.fp += $accepted.Count-$exact.Count
                $total.tn += $rejected.Count
                if($fixture.hasOriginal -and $exact.Count -eq 0){$total.fnCases++}
                switch($scan.decision){
                    'one_possible' {$total.possible++}
                    'ambiguous' {$total.ambiguous++}
                    'unknown' {$total.unknown++}
                    'incomplete' {$total.incomplete++}
                }
                $total.physical += [long]$scan.metrics.sourceBytesRead
                $total.memory += [long]$scan.metrics.validatorBytesRead
                $total.readCalls += [int]$scan.metrics.readRequests
                $total.starts += [int]$scan.metrics.startCandidates
                $total.tails += [int]$scan.metrics.tailCandidates
                $total.pairs += [int]$scan.metrics.pairAttempts
                $total.sectors += [int]$scan.metrics.sectorProbes
                $total.elapsedMs += [long]$scan.metrics.elapsedMilliseconds
                $total.originalSelections += $(if($null -ne $guard.selectedOriginal){1}else{0})
                $total.falseOriginalClaims += @($scan.items | Where-Object {$_.originalIdentity -cne 'unknown'}).Count
                $results[$kind][$arm]=[pscustomobject]@{
                    decision=$scan.decision;exact=$exact.Count;accepted=$accepted.Count
                    falseAccepted=$accepted.Count-$exact.Count
                    sourceBytes=[long]$scan.metrics.sourceBytesRead
                    memoryBytes=[long]$scan.metrics.validatorBytesRead
                    pairs=$scan.metrics.pairAttempts
                }
            }finally{$input.Dispose()}
            Assert-CFirst560 ((Get-A3DSha256 $bytes) -ceq $originalInputSha) ($kind+'/'+$arm+': same source SHA before and after')
            $totals[$arm].sourceUnchanged++
        }
        Write-Host ('C FIRST560 CASE={0} default={1} plus2={2} len560={3} both={4}' -f
            $kind,$results[$kind]['default'].decision,$results[$kind]['plus2'].decision,
            $results[$kind]['len560'].decision,$results[$kind]['both'].decision)
    }
    # These expectations describe only the fixed independently scored
    # artificial corpus. They are NOT passed into the candidate method.
    foreach($arm in $arms){
        Assert-CFirst560 ($totals[$arm].cases -eq 8 -and
            $totals[$arm].sourceUnchanged -eq 8 -and
            $totals[$arm].sectors -eq 1024 -and
            $totals[$arm].incomplete -eq 0 -and
            $totals[$arm].originalSelections -eq 0 -and
            $totals[$arm].falseOriginalClaims -eq 0) ($arm+': complete and no original identity claim')
    }
    Assert-CFirst560 ($results['nonlisted_first_560']['default'].decision -eq 'unknown' -and
        $results['nonlisted_first_560']['plus2'].decision -eq 'unknown' -and
        $results['nonlisted_first_560']['len560'].exact -eq 1 -and
        $results['nonlisted_first_560']['both'].exact -eq 1) 'one new 560B hypothesis finds a previously unobserved exact artificial original'
    Assert-CFirst560 ($results['offgrid_plus_two']['default'].decision -eq 'unknown' -and
        $results['offgrid_plus_two']['len560'].decision -eq 'unknown' -and
        $results['offgrid_plus_two']['plus2'].exact -eq 1 -and
        $results['offgrid_plus_two']['both'].exact -eq 1) 'start phase and first-part-size remain independent choices'
    foreach($arm in $arms){
        Assert-CFirst560 ($results['alternate_zip_metadata'][$arm].decision -eq 'ambiguous' -and
            $results['alternate_zip_metadata'][$arm].exact -eq 1 -and
            $results['alternate_zip_metadata'][$arm].falseAccepted -eq 1) ($arm+': byte-different CRC-consistent tail never selected')
        Assert-CFirst560 ($results['missing_tail'][$arm].decision -eq 'unknown' -and
            $results['missing_tail'][$arm].accepted -eq 0) ($arm+': missing true tail unknown')
        Assert-CFirst560 ($results['fake_eocd'][$arm].decision -eq 'one_possible') ($arm+': fake EOCD must not select original')
    }
    Assert-CFirst560 ($totals['len560'].tp -eq ($totals['default'].tp+1) -and
        $totals['len560'].fnCases -eq ($totals['default'].fnCases-1) -and
        $totals['both'].tp -eq ($totals['default'].tp+2) -and
        $totals['both'].fnCases -eq ($totals['default'].fnCases-2)) 'fixed synthetic size- and phase-limited coverage improvements'
    Assert-CFirst560 ($totals['len560'].fp -eq $totals['default'].fp -and
        $totals['both'].fp -eq $totals['default'].fp) 'no new accepted byte-wrong decoy on frozen artificial source'

    # Deliberately add invented PK0304/EOCD signatures to overload a
    # constrained hypothesis budget; never choose a truth by order.
    $bad=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind 'alternate_zip_metadata'
    [byte[]]$flood=[byte[]]$bad.image.Clone()
    [Array]::Copy([byte[]]@(0x50,0x4b,0x03,0x04),0,$flood,(65024+2),4)
    [Array]::Copy([byte[]]@(0x50,0x4b,0x05,0x06),0,$flood,(64000+24),4)
    $floodSha=Get-A3DSha256 $flood
    $floodInput=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($flood,$false))
    try{
        $r=Test-CVariableZipPairs -Source $floodInput -IncludeFirstPiece560 -IncludeStartPhasePlusTwo -MaxStarts 1
        Assert-CFirst560 ($r.status -eq 'partial' -and $r.decision -eq 'incomplete' -and
            $r.metrics.stopCode -eq 'search.start_limit' -and
            @($r.items).Count -eq 0 -and $floodInput.BytesRead -eq $r.metrics.sourceBytesRead) 'many fake signatures: fail closed'
    }finally{$floodInput.Dispose()}
    $pairFlood=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($bad.image,$false))
    try{
        $r=Test-CVariableZipPairs -Source $pairFlood -IncludeFirstPiece560 -MaxPairs 1
        Assert-CFirst560 ($r.status -eq 'partial' -and $r.decision -eq 'incomplete' -and
            $r.metrics.stopCode -eq 'search.pair_limit' -and
            $r.metrics.sourceBytesRead -eq 65536 -and @($r.items).Count -eq 0) 'candidate-count overflow cannot cherry-pick'
    }finally{$pairFlood.Dispose()}
    Assert-CFirst560 ((Get-A3DSha256 $flood) -ceq $floodSha) 'flood source unchanged'

    $good=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind 'nonlisted_first_560'
    $knownSha=Get-A3DSha256 $good.image
    $short=[ChappyCountingReadStream]::new([CArtificialShortValidationStream]::new([IO.MemoryStream]::new($good.image,$false),17))
    try{
        $r=Test-CVariableZipPairs -Source $short -IncludeFirstPiece560
        Assert-CFirst560 ($r.status -eq 'partial' -and $r.decision -eq 'incomplete' -and
            $r.metrics.sourceBytesRead -eq 17 -and $short.BytesRead -eq 17 -and
            @($r.items).Count -eq 0) '17 returned bytes followed by true zero EOF'
    }finally{$short.Dispose()}
    [byte[]]$truncated=New-Object byte[] 65535
    [Array]::Copy($good.image,0,$truncated,0,$truncated.Length)
    $truncatedInput=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($truncated,$false))
    try{
        $r=Test-CVariableZipPairs -Source $truncatedInput -IncludeFirstPiece560
        Assert-CFirst560 ($r.decision -eq 'incomplete' -and
            $r.metrics.stopCode -eq 'search.window_unavailable' -and
            $truncatedInput.BytesRead -eq 0) 'physically truncated source cannot claim full window'
    }finally{$truncatedInput.Dispose()}
    $budgetInput=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($good.image,$false))
    try{
        $r=Test-CVariableZipPairs -Source $budgetInput -IncludeFirstPiece560 -MaxSourceBytes 1024
        Assert-CFirst560 ($r.decision -eq 'incomplete' -and
            $r.metrics.stopCode -eq 'search.scout_budget_unavailable' -and
            $budgetInput.BytesRead -eq 0) 'source underbudget refuses before reads'
    }finally{$budgetInput.Dispose()}
    $memoryInput=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($good.image,$false))
    try{
        $r=Test-CVariableZipPairs -Source $memoryInput -IncludeFirstPiece560 -MaxValidationBytes 6144
        Assert-CFirst560 ($r.decision -eq 'incomplete' -and
            $r.metrics.stopCode -eq 'search.validation_limit' -and
            $memoryInput.BytesRead -eq $r.metrics.sourceBytesRead -and
            @($r.items).Count -eq 0) 'memory validator quota aborts with no accepted partial answers'
    }finally{$memoryInput.Dispose()}
    $writable=[IO.MemoryStream]::new($good.image,$true)
    try{
        $denied=$false
        try{Test-CVariableZipPairs -Source $writable -IncludeFirstPiece560 | Out-Null}catch{$denied=$true}
        Assert-CFirst560 $denied 'writable input refused'
    }finally{$writable.Dispose()}
    # Swapping order cannot preserve exact original SHA; independent
    # scoring only, and NO A receipt or original claim is minted.
    [byte[]]$reversed=New-Object byte[] $original.Length
    $cut=560
    [Array]::Copy($original,$cut,$reversed,0,($original.Length-$cut))
    [Array]::Copy($original,0,$reversed,($original.Length-$cut),$cut)
    Assert-CFirst560 ((Get-A3DSha256 $reversed) -cne $truth.sha256) 'reverse-order data cannot equal known artificial original'
    Assert-CFirst560 ((Get-A3DSha256 $good.image) -ceq $knownSha) 'short/budget negatives did not alter input'

    foreach($arm in $arms){
        $t=$totals[$arm]
        Write-Host ('C FIRST560 METRICS arm={0} cases={1} TP_pairs={2} FP_pairs={3} TN_pairs={4} FN_cases={5} unknown={6} one={7} ambiguous={8} incomplete={9} source_bytes={10} memory_bytes={11} read_calls={12} starts={13} tails={14} pairs={15} elapsed_ms={16} source_SHA_unchanged={17} false_original_claims={18} auto_winners={19} A_receipts_minted=0' -f
            $arm,$t.cases,$t.tp,$t.fp,$t.tn,$t.fnCases,$t.unknown,$t.possible,$t.ambiguous,$t.incomplete,
            $t.physical,$t.memory,$t.readCalls,$t.starts,$t.tails,$t.pairs,$t.elapsedMs,$t.sourceUnchanged,
            $t.falseOriginalClaims,$t.originalSelections)
    }
    Write-Host 'PASS: Team C R5 fixed 560B option, independent +2 and combined phases, false CRC metadata, 17B EOF, truncated, flood and quota fail closed'
}
