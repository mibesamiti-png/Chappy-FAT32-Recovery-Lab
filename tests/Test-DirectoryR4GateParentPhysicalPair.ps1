#requires -Version 5.1
# B4-03: per-parent actual returned directory entry and child dotdot
# evidence, never a genuine original-parent/source authentication.
# Earlier B tests supply only generated fixtures and independent meter.
. (Join-Path (Join-Path $PSScriptRoot '..\modules\directory') 'DirectoryParentObservationJoin.ps1')

function Copy-B403SyntheticEnvelope {
    param([psobject]$Evidence)
    return ($Evidence|ConvertTo-Json -Depth 16 -Compress|ConvertFrom-Json)
}
function Test-B403Safety {
    param([psobject]$Result,[string]$Label)
    Assert-B ($Result.schemaVersion -ceq 'b_parent_observation_v1' -and
        $Result.originalIdentity -ceq 'unknown' -and
        $Result.originalParent -ceq 'unknown' -and
        $Result.originalPath -ceq 'not_reconstructed' -and
        $Result.sourceAuthenticity -ceq 'not_proven' -and
        $Result.outerEventAuthority -ceq 'caller_supplied_not_A_issued_receipt' -and
        $Result.parentConfidence -ceq 'partial' -and
        $Result.metrics.additionalStreamReads -eq 0 -and
        -not $Result.canExport -and -not $Result.canSelectFatCopy -and
        @($Result.parentObservations|Where-Object{
            $_.originalIdentity -ne 'unknown' -or $_.confidence -ne 'partial' -or
            $_.sourceAuthenticity -ne 'not_proven'
        }).Count -eq 0) ('B4-03 original identity/source remains unverified: '+$Label)
}
$b403Geo=[pscustomobject]@{
    dataOffsetBytes=1024L;clusterSizeBytes=512L;rootCluster=2L
    maxCluster=4L;partitionEndBytes=2560L;clusterCount=3L
}
$b403Seeds=@(202611,202612,202613)
$b403Cases=@('matched_parent','duplicate_parent','short_child','orphan')
$b403Scans=0;$b403ActualBytes=0L;$b403BDirectory=0L
$b403Calls=0L;$b403Observed=0;$b403Ambiguous=0;$b403ShortUnknown=0;$b403NoParent=0
$b403CaseRows=New-Object System.Collections.ArrayList
$b403Good=$null;$b403GoodEvents=@();$b403GoodBytes=0L
foreach($seed in $b403Seeds){
    foreach($case in $b403Cases){
        [byte[]]$img=New-BR4ParentImage -Seed $seed -Case $case
        $sha=Get-BR4Sha $img
        $stop=if($case -eq 'short_child'){1553L}else{-1L}
        $reader=[ChappyBR4ObservedParentPositive.MeteredStream]::new($img,97,$stop,128)
        try {
            $b=Get-ChappyBDirectoryEvidenceV1 -Stream $reader -Geometry $b403Geo -EnableDirectoryEvidenceV1 -MaxScanBytes 1536 -MaxCandidates 16 -MaxDirectories 8 -MaxReadSpans 8 -MaxNodes 16 -MaxEdges 16
            $observed=@($reader.Events)
            Assert-B (-not $reader.CanWrite -and $reader.Calls -le 128 -and
                (Test-BR4EventsMatchInput $observed $img)) ('B4-03 synthetic physical source SHA match '+$seed+' '+$case)
            $events=@(New-B404AEventCopies $observed 1024L)
            $readingCount=$reader.Calls
            $r=Get-ChappyBParentObservationV1 -DirectoryEnvelope $b -OuterReadEvents $events -SourceLengthBytes $img.Length -MaxEdges 16 -MaxSpans 8 -MaxEvents 128
            Assert-B ($readingCount -eq $reader.Calls -and
                $r.metrics.additionalStreamReads -eq 0 -and
                $r.metrics.outerDirectoryReturnedBytes -eq $b.metrics.bReturnedDirectoryBytes -and
                $r.metrics.parentEdgeCount -eq $b.parentEdges.Count) ('B4-03 metadata-only B4-05/B4-04 physical span join '+$seed+' '+$case)
            Test-B403Safety $r ($seed.ToString()+'/'+$case)
            if($case -eq 'matched_parent'){
                Assert-B ($r.status -eq 'partial' -and
                    $r.intervalJoin -eq 'consistent_unattested' -and
                    $r.parentObservations.Count -eq 1 -and
                    $r.parentObservations[0].observation -eq 'observed_pair_unattested' -and
                    $r.parentObservations[0].parentCluster -eq 2 -and
                    $r.parentObservations[0].childCluster -eq 3 -and
                    $r.parentObservations[0].entryOffsetBytes -eq 1024 -and
                    $r.parentObservations[0].childDotDotOffsetBytes -eq 1568 -and
                    $r.metrics.observedPairUnattested -eq 1 -and
                    $r.metrics.ambiguousStructural -eq 0 -and
                    $r.metrics.originalParentUnknown -eq 1) ('B4-03 both returned 32B records structural pair but original UNKNOWN '+$seed)
                $b403Observed++
                if($seed -eq 202611){
                    $b403Good=Copy-B403SyntheticEnvelope $b
                    $b403GoodEvents=@($events)
                    $b403GoodBytes=$img.Length
                }
            }elseif($case -eq 'duplicate_parent'){
                Assert-B ($r.intervalJoin -eq 'consistent_unattested' -and
                    $r.metrics.observedPairUnattested -eq 0 -and
                    $r.parentObservations.Count -eq 2 -and
                    $r.metrics.ambiguousStructural -eq 2 -and
                    @($r.parentObservations|Where-Object{
                        $_.relationStatus -ne 'ambiguous_multiple_parents' -or
                        $_.observation -ne 'ambiguous_structural'
                    }).Count -eq 0) ('B4-03 true source-returned competing parent records remain ambiguous '+$seed)
                $b403Ambiguous++
            }elseif($case -eq 'short_child'){
                Assert-B ($r.metrics.observedPairUnattested -eq 0 -and
                    $r.status -ne 'verified' -and
                    $r.intervalJoin -eq 'partial_unknown' -and
                    $reader.ReturnedBytes -eq 529 -and
                    $b.metrics.bReturnedDirectoryBytes -eq 529 -and
                    $b.metrics.bCompletedDirectoryBytes -eq 512 -and
                    $b.metrics.bIncompleteReturnedBytes -eq 17) ('B4-03 early child dotdot 17B cannot validate complete 32B original entry '+$seed)
                $b403ShortUnknown++
            }else{
                Assert-B ($r.parentObservations.Count -eq 0 -and
                    $r.metrics.observedPairUnattested -eq 0 -and
                    $r.reasons -contains 'b4_03_no_parent_assertion_original_unknown' -and
                    $r.intervalJoin -eq 'consistent_unattested') ('B4-03 genuine orphan has no inferred parent from dotdot marker '+$seed)
                $b403NoParent++
            }
            [void]$b403CaseRows.Add(('{0}/{1} scans={2} bytes={3} calls={4} physicalJoin={5} observedPair={6} ambiguous={7} originalParent=UNKNOWN' -f
                $seed,$case,$b.parentEdges.Count,$reader.ReturnedBytes,$reader.Calls,
                $r.intervalJoin,$r.metrics.observedPairUnattested,$r.metrics.ambiguousStructural))
            $b403Scans++
            $b403ActualBytes += [long]$reader.ReturnedBytes
            $b403BDirectory += [long]$b.metrics.bReturnedDirectoryBytes
            $b403Calls += [long]$reader.Calls
        }finally{$reader.Dispose()}
        Assert-B ((Get-BR4Sha $img) -ceq $sha) ('B4-03 artificial source before-after SHA unchanged '+$seed+' '+$case)
    }
}
Assert-B ($b403Scans -eq 12 -and $b403Observed -eq 3 -and
    $b403Ambiguous -eq 3 -and $b403ShortUnknown -eq 3 -and
    $b403NoParent -eq 3 -and $b403ActualBytes -eq 15411 -and
    $b403BDirectory -eq 15411 -and $b403Calls -eq 186) 'B4-03 expected 12 seeded parent controls physical 15411B and 186 calls'

# Same actually returned source, hostile caller MUTATES B's claims.
function Test-B403Adversarial {
    param([psobject]$Envelope,[object[]]$Events,[string]$Expected,[string]$Label)
    $x=Get-ChappyBParentObservationV1 -DirectoryEnvelope $Envelope -OuterReadEvents $Events -SourceLengthBytes $b403GoodBytes
    Assert-B ($x.metrics.observedPairUnattested -eq 0 -and
        @($x.parentObservations|Where-Object{$_.observation -eq 'observed_pair_unattested'}).Count -eq 0 -and
        ($x.metrics.ambiguousStructural -gt 0 -or
         $x.metrics.unobservedUnknown -gt 0 -or
         $x.metrics.contradictedReadLedger -gt 0) -and
        $x.parentObservations[0].observation -eq $Expected) ('B4-03 adversarial '+$Label+' fail closed')
    Test-B403Safety $x $Label
}
# One forged edge with wrong child node/hint, still carries 'corroborated' label.
$wrongChild=Copy-B403SyntheticEnvelope $b403Good
$wrongChild.parentEdges[0].childCluster=4L
Test-B403Adversarial $wrongChild $b403GoodEvents 'ambiguous_structural' 'forged child target lacks dotdot match'
# Missing even one dotdot hint cannot produce an observed structural pair.
$missingHint=Copy-B403SyntheticEnvelope $b403Good
$missingHint.parentHints=@()
Test-B403Adversarial $missingHint $b403GoodEvents 'ambiguous_structural' 'forged missing child dotdot hint'
# One duplicate parent assertion, even matching source intervals.
$dup=Copy-B403SyntheticEnvelope $b403Good
$dup.parentEdges=@($dup.parentEdges)+@(Copy-B403SyntheticEnvelope $dup.parentEdges[0])
Test-B403Adversarial $dup $b403GoodEvents 'ambiguous_structural' 'fabricated duplicate parent entry'
# Cyclic/self-reference status is NEVER structural positive even with returned intervals.
$cycle=Copy-B403SyntheticEnvelope $b403Good
$cycle.parentEdges[0].relationStatus='cycle_detected'
Test-B403Adversarial $cycle $b403GoodEvents 'ambiguous_structural' 'cyclic parent status'
# Change source-relative entry offset from root to child; root interval no longer matches.
$shift=Copy-B403SyntheticEnvelope $b403Good
$shift.parentEdges[0].entryOffsetBytes=1536L
Test-B403Adversarial $shift $b403GoodEvents 'unobserved_unknown' 'parent entry offset shifted to child cluster'
# Self-forged complete B cluster with no actual returned source bytes.
$fakeRead=Copy-B403SyntheticEnvelope $b403Good
$fakeRead.directoryReadSpans[2].offsetBytes=2560L
Test-B403Adversarial $fakeRead $b403GoodEvents 'contradicted_read_ledger' 'forged B completed read span'
# Same B report but missing actual A-shaped outer source event (not source receipt).
$less=New-Object System.Collections.ArrayList
$removed=$false
foreach($event in $b403GoodEvents){
    if(-not $removed -and $event.Consumer -eq 'directory'){$removed=$true;continue}
    [void]$less.Add($event)
}
Test-B403Adversarial $b403Good @($less.ToArray()) 'contradicted_read_ledger' 'one physical source-return event missing'
# Equally untrusted forged metadata alone can make a self-consistent pair:
# the B result can never claim A/real-source authenticity even on matching spans.
$flag=Copy-B403SyntheticEnvelope $b403Good
$flag|Add-Member -NotePropertyName callerSaysAttested -NotePropertyValue $true -Force
$still=Get-ChappyBParentObservationV1 -DirectoryEnvelope $flag -OuterReadEvents $b403GoodEvents -SourceLengthBytes $b403GoodBytes
Assert-B ($still.metrics.observedPairUnattested -eq 1 -and
    $still.sourceAuthenticity -eq 'not_proven' -and
    $still.parentConfidence -eq 'partial' -and
    $still.originalParent -eq 'unknown' -and
    -not $still.canExport) 'B4-03 forged caller attested flag cannot elevate a structurally observed pair to verified original'
# No A-source meter available: the same B self-ledger cannot justify a pair.
$noEvents=Get-ChappyBParentObservationV1 -DirectoryEnvelope $b403Good -OuterReadEvents @() -SourceLengthBytes $b403GoodBytes
Assert-B ($noEvents.metrics.observedPairUnattested -eq 0 -and
    $noEvents.intervalJoin -eq 'contradicted' -and
    $noEvents.originalIdentity -eq 'unknown') 'B4-03 B self-only scan never earns physical structural label'
# B4-03 SUPPLEMENTAL (separate from frozen 12-source matrix): an ACTUAL
# synthetically returned 3<->4 cyclic parent graph, not merely a forged
# relationStatus in post-scan metadata. Root2 is empty; both unlinked
# directory containers contain real dot/dotdot and an opposing child entry.
[byte[]]$b403CycleBytes=New-Object byte[] 2560
Add-BR4Entries $b403CycleBytes 1536 @(
    (New-BR4Entry '.          ' 0x10 3 0)
    (New-BR4Entry '..         ' 0x10 4 0)
    (New-BR4Entry 'CYC4    DIR' 0x10 4 0)
)
Add-BR4Entries $b403CycleBytes 2048 @(
    (New-BR4Entry '.          ' 0x10 4 0)
    (New-BR4Entry '..         ' 0x10 3 0)
    (New-BR4Entry 'CYC3    DIR' 0x10 3 0)
)
$b403CycleBefore=Get-BR4Sha $b403CycleBytes
$b403CycleReader=[ChappyBR4ObservedParentPositive.MeteredStream]::new($b403CycleBytes,97,-1L,128)
try {
    $b403CycleB=Get-ChappyBDirectoryEvidenceV1 -Stream $b403CycleReader -Geometry $b403Geo -EnableDirectoryEvidenceV1 -MaxScanBytes 1536 -MaxCandidates 16 -MaxDirectories 8 -MaxReadSpans 8
    $b403CycleEvents=@(New-B404AEventCopies @($b403CycleReader.Events) 1024L)
    $b403CycleResult=Get-ChappyBParentObservationV1 -DirectoryEnvelope $b403CycleB -OuterReadEvents $b403CycleEvents -SourceLengthBytes $b403CycleBytes.Length
    Assert-B ($b403CycleReader.ReturnedBytes -eq 1536 -and
        $b403CycleReader.Calls -eq 18 -and
        (Test-BR4EventsMatchInput @($b403CycleReader.Events) $b403CycleBytes) -and
        $b403CycleResult.intervalJoin -eq 'consistent_unattested') 'B4-03 supplemented ACTUAL synthetic cyclic parent source returns 1536B and 18 calls'
    Assert-B ($b403CycleB.parentEdges.Count -ge 2 -and
        @($b403CycleB.parentEdges|Where-Object{
            $_.relationStatus -eq 'cycle_detected'
        }).Count -ge 1 -and
        $b403CycleResult.metrics.observedPairUnattested -eq 0 -and
        $b403CycleResult.metrics.ambiguousStructural -ge 1 -and
        @($b403CycleResult.parentObservations|Where-Object{
            $_.relationStatus -eq 'cycle_detected' -and
            $_.observation -eq 'ambiguous_structural'
        }).Count -ge 1) 'B4-03 actual observed cycle links remain ambiguous structural, never original parent'
    Test-B403Safety $b403CycleResult 'physically-observed-cycle-separate-supplemental'
    Write-Host ('B4-03 SUPPLEMENTAL PHYSICAL CYCLE: B edges={0}, cycle reasons={1}, structural positives={2}, source returned={3}B calls={4}, original parent UNKNOWN' -f $b403CycleB.parentEdges.Count,@($b403CycleB.parentEdges|Where-Object{$_.relationStatus -eq 'cycle_detected'}).Count,$b403CycleResult.metrics.observedPairUnattested,$b403CycleReader.ReturnedBytes,$b403CycleReader.Calls)
}finally{$b403CycleReader.Dispose()}
Assert-B ((Get-BR4Sha $b403CycleBytes) -ceq $b403CycleBefore) 'B4-03 supplemental cyclic source SHA-256 unchanged'

foreach($row in $b403CaseRows){Write-Host ('B4-03 PARENT MATRIX: '+$row)}
Write-Host ('B4-03 PARENT OBSERVATION: 3 seeds * 4 cases = {0} genuine synthetic scans; matched structural observed-but-unattested={1}, competing-parent ambiguous cases={2}, early-EOF UNKNOWN={3}, orphan/no-parent={4}; actual returned={5}B, directory returned={6}B, Read calls={7}; 7 injected metadata attacks denied, 1 caller-attested spoof does NOT upgrade, original path always UNKNOWN' -f
    $b403Scans,$b403Observed,$b403Ambiguous,$b403ShortUnknown,$b403NoParent,
    $b403ActualBytes,$b403BDirectory,$b403Calls)
