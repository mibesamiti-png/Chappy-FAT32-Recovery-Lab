#requires -Version 5.1
# Issue #72 research regression. Only this scorer knows oracle SHA/locations.
function Assert-CM01([bool]$Good,[string]$Why) {
    if(-not $Good){throw "CM01_SYNTHETIC_FAIL: $Why"}
}
function Invoke-R5M01FragmentEvidence {
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
    $clean=New-ChappyA3DCleanFixture -Seed 202611
    $truth=$clean.oracle[1]
    $TP=0;$FP=0;$TN=0;$FN=0
    $baseTotal=0L;$candidateTotal=0L;$validatorTotal=0L
    foreach($id in @('M00','M01')){
        $fixture=New-ChappyA3DDamagedFixture -Seed 202611 -Case $id
        $before=Get-A3DSha256 $fixture.image
        Assert-CM01 ($before -ceq $fixture.manifest.imageSha256) ($id+': pinned artificial input SHA')
        $baselineStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($fixture.image,$false))
        try{
            $base=Get-ChappyCarvingCandidates -Stream $baselineStream -StartOffset 0 -MaxScanBytes 65536 -MaxFileBytes 4096 -ExtraValidationReadBytes 32768 -MaxCandidates 16 -MaxProbes 16 -MaxProbeBytes 8192
            Assert-CM01 ($baselineStream.BytesRead -eq $base.metrics.bytesRead -and $baselineStream.BytesRead -le 98304) ($id+': baseline exact source read accounting')
            $baseTotal+=[long]$baselineStream.BytesRead
        }finally{$baselineStream.Dispose()}
        $scanStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($fixture.image,$false))
        try{
            $found=Test-CM01FiniteZipPairs -Source $scanStream
            Assert-CM01 ($scanStream.BytesRead -eq $found.metrics.sourceBytesRead -and $scanStream.BytesRead -le 73728) ($id+': actual source reads match candidate budget')
            Assert-CM01 ($found.metrics.validatorBytesRead -le 40960 -and -not $scanStream.CanWrite) ($id+': bounded memory rechecks on nonwritable stream')
            Assert-CM01 ($found.metrics.sampledSectors -eq 128 -and $found.metrics.startCandidates -le 4 -and $found.metrics.tailCandidates -le 8 -and $found.metrics.pairsEvaluated -le 8) ($id+': bounded sampling and candidate-pair limits')
        }finally{$scanStream.Dispose()}
        Assert-CM01 ($found.status -eq 'ok' -and $found.decision -eq 'one_possible') ($id+': one format-consistent pair')
        $accepted=@($found.items | Where-Object {$_.possible})
        $correct=@($accepted | Where-Object {$_.candidateSha256 -ceq $truth.sha256})
        Assert-CM01 ($accepted.Count -eq 1 -and $correct.Count -eq 1) ($id+': candidate bytes equal original independent SHA')
        Assert-CM01 ($correct[0].firstOffset -eq $truth.extents[0].offsetBytes -and $correct[0].sourceSpans.Count -eq 2) ($id+': scorer-only extent proof')
        Assert-CM01 ($correct[0].originalIdentity -eq 'unknown' -and $correct[0].integrityScope -eq 'structural_only_not_original_file_integrity') ($id+': no original identity claims from structure')
        $complete=@($base.items | Where-Object {$_.format -eq '3mf' -and $_.offsetBytes -eq $truth.extents[0].offsetBytes -and $_.lengthBytes -eq $truth.lengthBytes})
        if($id -eq 'M00') {
            Assert-CM01 ($complete.Count -eq 1) 'M00 contiguous positive baseline'
        }else {
            Assert-CM01 ($complete.Count -eq 0) 'M01 physical split not reconstructed by contiguous baseline'
        }
        $TP+=$correct.Count
        $TN+=@($found.items | Where-Object {-not $_.possible}).Count
        $candidateTotal+=[long]$found.metrics.sourceBytesRead
        $validatorTotal+=[long]$found.metrics.validatorBytesRead
        Assert-CM01 ((Get-A3DSha256 $fixture.image) -ceq $before) ($id+': artificial input unchanged')
        Write-Host ('R5 M01 {0}: baselineBytes={1} sourceBytes={2} memoryBytes={3} starts={4} tails={5} pairs={6} exact={7}' -f $id,$base.metrics.bytesRead,$found.metrics.sourceBytesRead,$found.metrics.validatorBytesRead,$found.metrics.startCandidates,$found.metrics.tailCandidates,$found.metrics.pairsEvaluated,$correct.Count)
    }
    $m01=New-ChappyA3DDamagedFixture -Case M01 -Seed 202611
    [byte[]]$decoy=[byte[]]$m01.image.Clone()
    # An EOCD-shaped signature at an unused synthetic cluster. Not a hint to
    # Test-CM01FiniteZipPairs, which never sees its intended location.
    $fakeAt=61440
    [Array]::Copy([byte[]]@(0x50,0x4b,0x05,0x06),0,$decoy,($fakeAt+24),4)
    $beforeDecoy=Get-A3DSha256 $decoy
    $decoyStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($decoy,$false))
    try{
        $tested=Test-CM01FiniteZipPairs -Source $decoyStream
        Assert-CM01 ($decoyStream.BytesRead -eq $tested.metrics.sourceBytesRead -and $decoyStream.BytesRead -le 73728) 'decoy read accounting'
    }finally{$decoyStream.Dispose()}
    $decoyAccepted=@($tested.items | Where-Object {$_.possible})
    $decoyRejected=@($tested.items | Where-Object {-not $_.possible})
    Assert-CM01 ($tested.status -eq 'ok' -and $tested.decision -eq 'one_possible') 'single true synthetic pair despite fake EOCD'
    Assert-CM01 ($tested.metrics.tailCandidates -eq 2 -and $tested.metrics.pairsEvaluated -eq 2 -and $decoyRejected.Count -eq 1) 'fake EOCD enumerated then rejected, not silently omitted'
    Assert-CM01 ($decoyAccepted.Count -eq 1 -and $decoyAccepted[0].candidateSha256 -ceq $truth.sha256) 'decoy cannot replace original artificial-byte SHA'
    Assert-CM01 ((Get-A3DSha256 $decoy) -ceq $beforeDecoy) 'decoy source unchanged'
    $TP++;$TN+=$decoyRejected.Count
    $candidateTotal+=[long]$tested.metrics.sourceBytesRead
    $validatorTotal+=[long]$tested.metrics.validatorBytesRead

    # Logical reverse-order trial is scored outside the discovery helper.
    $knownFirst=[int]$truth.extents[0].offsetBytes
    $knownTail=60416
    $tailSize=[int]($truth.lengthBytes-512)
    [byte[]]$wrong=New-Object byte[] ([int]$truth.lengthBytes)
    [Array]::Copy($m01.image,$knownTail,$wrong,0,$tailSize)
    [Array]::Copy($m01.image,$knownFirst,$wrong,$tailSize,512)
    $rev=[IO.MemoryStream]::new($wrong,$false)
    try{
        $r=Get-ChappyCarvingCandidates -Stream $rev -MaxScanBytes $wrong.Length -MaxFileBytes 4096 -ExtraValidationReadBytes 4096 -MaxCandidates 4 -MaxProbes 8 -MaxProbeBytes 4096 -EnableSmallDeflateCrc
        Assert-CM01 (@($r.items | Where-Object {$_.format -eq '3mf' -and $_.offsetBytes -eq 0 -and $_.lengthBytes -eq $wrong.Length}).Count -eq 0) 'reversed logical order never creates an intact original 3MF'
    }finally{$rev.Dispose()}
    $reverseOrderRejected=1 # Separate control, NOT part of candidate-pair TN.

    $tooSmall=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($m01.image,$false))
    try{
        $r=Test-CM01FiniteZipPairs -Source $tooSmall -MaxSourceBytes 4096
        Assert-CM01 ($r.status -eq 'partial' -and $r.decision -eq 'incomplete' -and $r.metrics.sourceBytesRead -eq 0 -and $tooSmall.BytesRead -eq 0) 'insufficient scout budget fails before any read'
    }finally{$tooSmall.Dispose()}
    $tooMany=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($decoy,$false))
    try{
        $r=Test-CM01FiniteZipPairs -Source $tooMany -MaxPairs 1
        Assert-CM01 ($r.status -eq 'partial' -and $r.decision -eq 'incomplete' -and $r.metrics.pairsEvaluated -eq 0 -and $r.metrics.tailCandidates -eq 2) 'pair budget fail closed, no cherry-picked true candidate'
    }finally{$tooMany.Dispose()}
    [byte[]]$short=[byte[]]$m01.image[0..32767]
    $shortStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($short,$false))
    try{
        $r=Test-CM01FiniteZipPairs -Source $shortStream
        Assert-CM01 ($r.status -eq 'partial' -and $r.decision -eq 'incomplete' -and $r.metrics.sourceBytesRead -eq 0) 'short synthetic source never satisfies scan window'
    }finally{$shortStream.Dispose()}
    # Adversarial false ZIP local headers: never select just the first four
    # signatures if the complete 64KiB grid offers more than the allowed cap.
    [byte[]]$fakeStarts=[byte[]]$m01.image.Clone()
    foreach($fakeHeaderAt in @(61440,61952,62464,62976)){
        [Array]::Copy([byte[]]@(0x50,0x4b,0x03,0x04),0,$fakeStarts,$fakeHeaderAt,4)
    }
    $fakeStartsInput=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($fakeStarts,$false))
    try{
        $overflow=Test-CM01FiniteZipPairs -Source $fakeStartsInput -MaxStarts 4
        Assert-CM01 ($overflow.status -eq 'partial' -and $overflow.decision -eq 'incomplete' -and
            $overflow.metrics.stopCode -eq 'search.start_limit' -and $overflow.metrics.pairsEvaluated -eq 0) 'five ZIP starts never cause arbitrary choice of real start'
        Assert-CM01 ($fakeStartsInput.BytesRead -eq $overflow.metrics.sourceBytesRead -and $fakeStartsInput.BytesRead -le 73728) 'fake header flood remains source-bound'
    }finally{$fakeStartsInput.Dispose()}
    $limitedWindowInput=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($m01.image,$false))
    try{
        $missing=Test-CM01FiniteZipPairs -Source $limitedWindowInput -WindowBytes 57344
        Assert-CM01 ($missing.status -eq 'ok' -and $missing.decision -eq 'unknown' -and
            $missing.metrics.startCandidates -eq 0) 'complete small window with no observed header yields unknown, not recovered'
        Assert-CM01 ($limitedWindowInput.BytesRead -eq $missing.metrics.sourceBytesRead -and $missing.metrics.sourceBytesRead -eq 57344) 'small-window actual scan bytes measured'
    }finally{$limitedWindowInput.Dispose()}
    Write-Host 'PASS: R5 M01 fake local-header flood fails closed; uncovered first-fragment location stays unknown'
    Assert-CM01 ($TP -eq 3 -and $FP -eq 0 -and $FN -eq 0 -and $TN -eq 1 -and $reverseOrderRejected -eq 1) 'candidate-pair TP3 FP0 FN0 TN1; reversed trial is separate and rejected'
    Write-Host ('R5 M01 SYNTHETIC METRICS TP={0} FP={1} FN={2} TN={3} reverse_rejected={7} baseline_source_bytes={4} experiment_source_bytes={5} in_memory_bytes={6} artificial_trials=3' -f $TP,$FP,$FN,$TN,$baseTotal,$candidateTotal,$validatorTotal,$reverseOrderRejected)
    Write-Host 'PASS: R5 M01 unhinted sector-grid two-piece 3MF research and conservative failure controls'
}