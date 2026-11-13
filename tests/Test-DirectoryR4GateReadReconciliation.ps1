#requires -Version 5.1
# B4-04: B-only pure receipt-consistency comparator and independent fake-A-
# shaped test-side source-return event recorder, generated-only.
. (Join-Path (Join-Path $PSScriptRoot '..\modules\directory') 'DirectoryReadReconciliation.ps1')
. (Join-Path (Join-Path $PSScriptRoot '..\modules\directory') 'DirectoryEvidenceEnvelope.ps1')
function New-B404AEventCopies {
    param([object[]]$SourceEvents,[long]$DataOffset)
    $all=New-Object System.Collections.ArrayList
    foreach($e in $SourceEvents){
        if([long]$e.Returned -lt 1){continue}
        [void]$all.Add([pscustomobject]@{
            Consumer=$(if([long]$e.Offset -ge $DataOffset){'directory'}else{'geometry'})
            OffsetBytes=[long]$e.Offset
            ReturnedBytes=[int]$e.Returned
        })
    }
    return ,@($all.ToArray())
}
function Copy-B404Report([psobject]$Report){
    return ($Report|ConvertTo-Json -Depth 12 -Compress|ConvertFrom-Json)
}
function Test-B404Claim {
    param([psobject]$Evidence,[object[]]$Events,[long]$Length,
        [string]$Decision,[string]$Code,[string]$Label)
    $actual=Compare-ChappyBDirectoryReturnedEvidenceV1 -DirectoryEnvelope $Evidence -OuterReadEvents $Events -SourceLengthBytes $Length
    Write-Host ('B4-04 TRACE: {0}, decision={1}, reason={2}, Breturned={3}, outerReturned={4}, unique={5}, events={6}, spans={7}, matched={8}' -f $Label,$actual.decision,([string]::Join(',',@($actual.reasonCodes))),$actual.metrics.bClaimedReturnedDirectoryBytes,$actual.metrics.outerDirectoryReturnedBytes,$actual.metrics.outerDirectoryUniqueBytes,$actual.metrics.outerDirectoryReadEvents,$actual.metrics.bClaimedCompletedSpans,$actual.metrics.matchingCompletedSpans)
    Assert-B ($actual.schemaVersion -ceq 'b_directory_outer_reconciliation_v1' -and
        $actual.decision -ceq $Decision -and
        $actual.reasonCodes -contains $Code -and
        $actual.originalIdentity -eq 'unknown' -and
        $actual.sourceAuthenticity -eq 'not_proven' -and
        $actual.outerEventAuthority -eq 'caller_supplied_not_B_or_A_receipt' -and
        $actual.parentConfidence -eq 'partial' -and
        -not $actual.canExport -and -not $actual.canSelectFatCopy -and
        $actual.metrics.additionalStreamReads -eq 0) ('B4-04 '+$Label+' => '+$Decision)
    return $actual
}

$b404Seeds=@(202611,202612,202613)
$b404Cases=@('M00','M01','M04')
$b404ControlScans=0
$b404ControlActualReturned=0L
$b404ControlDirectoryReturned=0L
$b404ControlCalls=0L
$b404CompleteSpans=0
$b404Contradictions=0
$b404Unknown=0
$b404Root=0L
$b404Source=$null
$b404Result=$null
$b404Events=@()
foreach($seed in $b404Seeds){
    foreach($testCase in $b404Cases){
        $fixture=New-ChappyA3DDamagedFixture -Case $testCase -Seed $seed
        [byte[]]$image=[byte[]]$fixture.image.Clone()
        $clean=New-ChappyA3DCleanFixture -Seed $seed
        $dataOffset=[long]$clean.layout.rootOffsetBytes
        $before=Get-A3DSha256 $image
        $stream=[ChappyBR4ObservedParentPositive.MeteredStream]::new($image,97,-1L,128)
        try {
            $report=Get-ChappyBDirectoryEvidenceV1 -Stream $stream -EnableDirectoryEvidenceV1 -MaxScanBytes 1024 -MaxReadSpans 8
            $physical=@($stream.Events)
            Assert-B ((Test-BR4EventsMatchInput $physical $image) -and
                -not $stream.CanWrite -and $stream.Calls -le 128 -and
                $report.metrics.bReturnedDirectoryBytes -eq 1024 -and
                $report.metrics.bCompletedDirectoryBytes -eq 1024) ('B4-04 actual source-returned hashed synthetic reads '+$seed+' '+$testCase)
            $events=@(New-B404AEventCopies $physical $dataOffset)
            $result=Test-B404Claim $report $events $image.Length 'consistent_unattested' 'b4_04_returned_intervals_consistent_not_authenticated' ('matched full directory reads '+$seed+' '+$testCase)
            Assert-B ($result.metrics.outerDirectoryReturnedBytes -eq 1024 -and
                $result.metrics.outerDirectoryUniqueBytes -eq 1024 -and
                $result.metrics.outerDirectoryOverlapBytes -eq 0 -and
                $result.metrics.bClaimedCompletedDirectoryBytes -eq 1024 -and
                $result.metrics.bClaimedIncompleteReturnedBytes -eq 0 -and
                $result.metrics.bClaimedCompletedSpans -eq 2 -and
                $result.metrics.matchingCompletedSpans -eq 2 -and
                $result.metrics.outsideCompletedSpanBytes -eq 0) ('B4-04 two completed clusters physically covered with no duplicate bytes '+$seed+' '+$testCase)
            $b404ControlScans++
            $b404ControlActualReturned += [long]$stream.ReturnedBytes
            $b404ControlDirectoryReturned += [long]$result.metrics.outerDirectoryReturnedBytes
            $b404ControlCalls += [long]$stream.Calls
            $b404CompleteSpans += [int]$result.metrics.matchingCompletedSpans
            if($seed -eq 202611 -and $testCase -eq 'M00'){
                $b404Root=$dataOffset
                $b404Source=[byte[]]$image.Clone()
                $b404Result=Copy-B404Report $report
                $b404Events=@($events)
            }
        } finally {$stream.Dispose()}
        Assert-B ((Get-A3DSha256 $image) -ceq $before) ('B4-04 source original synthetic SHA unchanged '+$seed+' '+$testCase)
    }
}
Assert-B ($b404ControlScans -eq 9 -and $b404ControlActualReturned -eq 18432 -and
    $b404ControlDirectoryReturned -eq 9216 -and $b404ControlCalls -eq 216 -and
    $b404CompleteSpans -eq 18) 'B4-04 fixed 9 sources 18432 returned / 9216 directory / 216 Read calls and 18 completed spans'

# Contradiction 1: B self-ledger lies about an extra completed cluster.
$forge=Copy-B404Report $b404Result
$forgedSpan=[pscustomobject]@{
    offsetBytes=($b404Root+1024);lengthBytes=512;cluster=4;attestation='unattested'
}
$forge.directoryReadSpans=@($forge.directoryReadSpans)+@($forgedSpan)
$forge.metrics.bCompletedReadSpans=3
$forge.metrics.bCompletedDirectoryBytes=1536
$forge.metrics.bReturnedDirectoryBytes=1536
$r=Test-B404Claim $forge $b404Events $b404Source.Length 'contradicted' 'b4_04_directory_returned_bytes_disagree' 'forged 3rd completed B cluster (no outer return)'
$b404Contradictions++

# Contradiction 2: B declares a complete span but recorded events are shifted.
$shifted=New-Object System.Collections.ArrayList
foreach($e in $b404Events){
    $move=if($e.Consumer -eq 'directory'){512L}else{0L}
    [void]$shifted.Add([pscustomobject]@{
        Consumer=$e.Consumer;OffsetBytes=([long]$e.OffsetBytes+$move)
        ReturnedBytes=[int]$e.ReturnedBytes
    })
}
$r=Test-B404Claim $b404Result @($shifted.ToArray()) $b404Source.Length 'contradicted' 'b4_04_completed_span_not_observed' 'source-offset shifted returned data'
$b404Contradictions++

# Contradiction 3: missing actual physical return under a correct B ledger.
$omitted=New-Object System.Collections.ArrayList
$skipped=$false
foreach($e in $b404Events){
    if(-not $skipped -and $e.Consumer -eq 'directory'){$skipped=$true;continue}
    [void]$omitted.Add($e)
}
$r=Test-B404Claim $b404Result @($omitted.ToArray()) $b404Source.Length 'contradicted' 'b4_04_directory_returned_bytes_disagree' 'one missing outer directory event'
$b404Contradictions++

# Contradiction 4: duplicate/overlap that would double-count successful bytes.
$duped=New-Object System.Collections.ArrayList
foreach($e in $b404Events){[void]$duped.Add($e)}
$first=@($b404Events|Where-Object{$_.Consumer -eq 'directory'})[0]
[void]$duped.Add([pscustomobject]@{Consumer='directory';OffsetBytes=[long]$first.OffsetBytes;ReturnedBytes=[int]$first.ReturnedBytes})
$r=Test-B404Claim $b404Result @($duped.ToArray()) $b404Source.Length 'contradicted' 'b4_04_duplicate_or_overlapping_outer_returns' 'duplicate physical event cannot inflate B evidence'
$b404Contradictions++

# Contradiction 5: same total but two distinct outer returns overlap.
$overlapped=New-Object System.Collections.ArrayList
$seenDirectory=0
foreach($e in $b404Events){
    $at=[long]$e.OffsetBytes
    if($e.Consumer -eq 'directory'){
        $seenDirectory++
        if($seenDirectory -eq 2){$at=[long]$first.OffsetBytes}
    }
    [void]$overlapped.Add([pscustomobject]@{Consumer=$e.Consumer;OffsetBytes=$at;ReturnedBytes=[int]$e.ReturnedBytes})
}
$r=Test-B404Claim $b404Result @($overlapped.ToArray()) $b404Source.Length 'contradicted' 'b4_04_duplicate_or_overlapping_outer_returns' 'equal totals but physical interval overlap'
$b404Contradictions++

# Contradiction 6: wrong source length makes all completed B spans impossible.
$r=Test-B404Claim $b404Result $b404Events 1024 'contradicted' 'b4_04_b_span_out_of_bounds' 'external source length smaller than B intervals'
$b404Contradictions++

# Contradiction 7: geometry-phase reads cannot be relabelled as directory.
$mislabel=New-Object System.Collections.ArrayList
$mutated=$false
foreach($e in $b404Events){
    $consumer=$e.Consumer
    if(-not $mutated -and $consumer -eq 'geometry'){$consumer='directory';$mutated=$true}
    [void]$mislabel.Add([pscustomobject]@{Consumer=$consumer;OffsetBytes=[long]$e.OffsetBytes;ReturnedBytes=[int]$e.ReturnedBytes})
}
$r=Test-B404Claim $b404Result @($mislabel.ToArray()) $b404Source.Length 'contradicted' 'b4_04_directory_returned_bytes_disagree' 'geometry returns mislabelled as directory'
$b404Contradictions++

# Absent or too-many read events cannot be promoted from B self-ledger alone.
$none=Test-B404Claim $b404Result @() $b404Source.Length 'contradicted' 'b4_04_directory_returned_bytes_disagree' 'missing outer read events'
$b404Contradictions++
$smallCap=Compare-ChappyBDirectoryReturnedEvidenceV1 -DirectoryEnvelope $b404Result -OuterReadEvents $b404Events -SourceLengthBytes $b404Source.Length -MaxEvents 1
Assert-B ($smallCap.decision -eq 'unknown' -and
    $smallCap.reasonCodes -contains 'b4_04_outer_event_cap_unknown') 'B4-04 event cap exhaust => UNKNOWN not invented complete'
$b404Unknown++

# Short actual partial cluster: 17 returned, ZERO completed, zero spans,
# and actual geometry bytes 1024 are unrelated to directory provenance.
$shortImg=[byte[]]$b404Source.Clone()
$shortBefore=Get-A3DSha256 $shortImg
$short=[ChappyBR4ObservedParentPositive.MeteredStream]::new($shortImg,97,$b404Root+17,128)
try {
    $shortReport=Get-ChappyBDirectoryEvidenceV1 -Stream $short -EnableDirectoryEvidenceV1 -MaxScanBytes 512
    $shortEvents=@(New-B404AEventCopies @($short.Events) $b404Root)
    Assert-B ((Test-BR4EventsMatchInput @($short.Events) $shortImg) -and
        $short.ReturnedBytes -eq 1041 -and
        $shortReport.metrics.bReturnedDirectoryBytes -eq 17 -and
        $shortReport.metrics.bCompletedDirectoryBytes -eq 0 -and
        $shortReport.metrics.bIncompleteReturnedBytes -eq 17 -and
        $shortReport.directoryReadSpans.Count -eq 0) 'B4-04 partial EOF truth independently measured (1041 total vs 17B directory)'
    $shortCheck=Test-B404Claim $shortReport $shortEvents $shortImg.Length 'partial_unknown' 'b4_04_short_return_no_complete_claim' '17/512 short EOF is UNKNOWN not complete'
    Assert-B ($shortCheck.metrics.outerDirectoryReturnedBytes -eq 17 -and
        $shortCheck.metrics.outerDirectoryUniqueBytes -eq 17 -and
        $shortCheck.metrics.matchingCompletedSpans -eq 0 -and
        $shortCheck.metrics.outsideCompletedSpanBytes -eq 17) 'B4-04 short EOF actual 17B not a valid full cluster'
    $b404Unknown++
} finally {$short.Dispose()}
Assert-B ((Get-A3DSha256 $shortImg) -ceq $shortBefore) 'B4-04 generated partial EOF source unchanged'
Assert-B ($b404Contradictions -eq 8 -and $b404Unknown -eq 2) 'B4-04 independently scored: 9 consistent-unattested; 8 contradicted; 2 unknown/partial, all original identities UNKNOWN'
Write-Host ('B4-04 MATRIX: consistent_unattested={0}, contradicted={1}, unknown_or_partial={2}; actual returned={3}B, directory={4}B, calls={5}, completedSpans={6}; EOF=17B/512B, original identity UNKNOWN, no A receipts' -f
    $b404ControlScans,$b404Contradictions,$b404Unknown,$b404ControlActualReturned,$b404ControlDirectoryReturned,$b404ControlCalls,$b404CompleteSpans)
