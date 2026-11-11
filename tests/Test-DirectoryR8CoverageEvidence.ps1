#requires -Version 5.1
# Team B R8: invented metadata only, default-off same-corpus A/B.
# Dot-source after R7 helper functions in Test-DirectoryScanner.ps1.

function New-R8GraphCase([string]$Id) {
    $fixture=New-R7GraphFixture 'good_single'
    $truth=$false
    if ($Id -eq 'good_full_duplicate') {
        $fixture=New-R7GraphFixture 'good_duplicate_identical'
    } elseif ($Id -eq 'observed_conflict') {
        $fixture=New-R7GraphFixture 'conflict_hint_later'
    } elseif ($Id -eq 'weak_parent') {
        $fixture=New-R7GraphFixture 'weak_parent'
    } elseif ($Id -eq 'no_dotdot_hint') {
        $fixture=New-R7GraphFixture 'missing_hint'
    }
    $fixture | Add-Member NoteProperty geometry ([pscustomobject]@{
        clusterCount=30L;maxCluster=31L;clusterSizeBytes=1024L
    })
    $fixture | Add-Member NoteProperty metrics ([pscustomobject]@{
        bytesRead=30720L
    })
    switch($Id) {
        'good_full' {$truth=$true}
        'good_full_duplicate' {$truth=$true}
        'hidden_late_no_metrics' {[void]$fixture.PSObject.Properties.Remove('metrics')}
        'hidden_late_underread' {$fixture.metrics.bytesRead=1024L}
        'hidden_other_block' {$fixture.metrics.bytesRead=5120L}
        'hidden_after_corrupt_lfn' {$fixture.metrics.bytesRead=2048L}
        'missing_geometry' {[void]$fixture.PSObject.Properties.Remove('geometry')}
        'bad_cluster_count' {$fixture.geometry.clusterCount=29L}
        'overreported_count' {$fixture.metrics.bytesRead=31744L}
        'spoofed_full_count' {} # mathematically undecidable from counters
        'observed_conflict' {}
        'declared_partial' {$fixture.scanIncomplete=$true;$fixture.metrics.bytesRead=5120L}
        'weak_parent' {}
        'no_dotdot_hint' {}
        default {throw ('Unknown invented R8 case: '+$Id)}
    }
    return [pscustomobject]@{id=$Id;truth=$truth;input=$fixture}
}
$r8Ids=@(
    'good_full','good_full_duplicate','hidden_late_no_metrics',
    'hidden_late_underread','hidden_other_block','hidden_after_corrupt_lfn',
    'missing_geometry','bad_cluster_count','overreported_count',
    'spoofed_full_count','observed_conflict','declared_partial',
    'weak_parent','no_dotdot_hint'
)
$r8Legacy=@{TP=0;FP=0;FN=0;TN=0}
$r8Optin=@{TP=0;FP=0;FN=0;TN=0}
$r8LegacyMs=0L;$r8OptinMs=0L
$r8Unique=New-Object 'System.Collections.Generic.HashSet[string]'
foreach($id in $r8Ids) {
    if(-not $r8Unique.Add($id)){throw 'Duplicate R8 fixture ID'}
    $case=New-R8GraphCase $id
    $r8BeforeJson=ConvertTo-Json -InputObject $case.input -Depth 9 -Compress
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $old=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $case.input -DetectConflictingContainerObservations -MaxContainerObservations 16 -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
    $watch.Stop();$r8LegacyMs+=$watch.ElapsedMilliseconds
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $new=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $case.input -DetectConflictingContainerObservations -RequireCompleteClusterCoverageEvidence -MaxContainerObservations 16 -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
    $watch.Stop();$r8OptinMs+=$watch.ElapsedMilliseconds
    if((ConvertTo-Json -InputObject $case.input -Depth 9 -Compress) -cne $r8BeforeJson) {
        throw ('R8 mutates input: '+$id)
    }
    $oldPositive=@($old.edges|Where-Object{$_.parentCluster -eq 2 -and $_.childCluster -eq 7 -and $_.confidence -eq 'probable'}).Count -gt 0
    $newPositive=@($new.edges|Where-Object{$_.parentCluster -eq 2 -and $_.childCluster -eq 7 -and $_.confidence -eq 'probable'}).Count -gt 0
    foreach($m in @(@{counts=$r8Legacy;pred=$oldPositive},@{counts=$r8Optin;pred=$newPositive})) {
        $grade=if($case.truth){if($m.pred){'TP'}else{'FN'}}else{if($m.pred){'FP'}else{'TN'}}
        $m.counts[$grade]++
    }
    if($old.metrics.nodes -ne $new.metrics.nodes -or
       $old.metrics.edgeAssertions -ne $new.metrics.edgeAssertions -or
       $old.metrics.metadataItemsVisited -ne $new.metrics.metadataItemsVisited) {
        throw ('R8 removed a candidate: '+$id)
    }
    if($new.scanIncomplete -and $new.metrics.probableEdgeAssertions -gt 0) {
        throw ('R8 incomplete graph promoted an edge: '+$id)
    }
    if((ConvertTo-Json -InputObject $new -Depth 8) -match 'INVENTED_R7_NAME|R7SYNTH.TXT|verified') {
        throw ('R8 output leaked invented names or verified claim: '+$id)
    }
    if($id -eq 'spoofed_full_count' -and (-not $newPositive -or
        $new.metrics.coverageEvidence -ne 'numeric_cluster_coverage_consistent')) {
        throw 'R8 matching fake counters limitation must be explicit'
    }
    if($id -eq 'hidden_late_underread' -and
        ($new.metrics.coverageEvidence -ne 'unproven' -or
         $new.warnings -notcontains 'hierarchy_cluster_coverage_unproven' -or
         $new.edges[0].evidence -notcontains 'hierarchy_coverage_incomplete')) {
        throw 'R8 fixed-code coverage uncertainty missing'
    }
}
Assert-B ($r8Unique.Count -eq 14) 'R8 fixed 14-case same-corpus synthetic A/B'
Assert-B ($r8Legacy.TP -eq 2 -and $r8Legacy.FP -eq 8 -and $r8Legacy.FN -eq 0 -and $r8Legacy.TN -eq 4) 'R8 R7 baseline TP2 FP8 FN0 TN4 on artificial truth'
Assert-B ($r8Optin.TP -eq 2 -and $r8Optin.FP -eq 1 -and $r8Optin.FN -eq 0 -and $r8Optin.TN -eq 11) 'R8 opt-in TP2 FP1 FN0 TN11: fake full counter remains risk'
Assert-B ($r8Optin.TP -eq $r8Legacy.TP -and $r8Optin.FP -lt $r8Legacy.FP) 'R8 confidence improves on invented cases with all candidate links retained'

# Real B scanner, but an entirely invented 64KiB R4 in-memory source.
$r8Hash=Get-R4Sha256 $r4Image
$r8Stream=New-R4ReadonlyStream $r4Image
try {
    $r8Full=Get-ChappyDirectoryCandidates -Stream $r8Stream -Geometry $r4Geo -MaxScanBytes 30720
    $r8Pos=$r8Stream.Position
    $r8OldGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r8Full -DetectConflictingContainerObservations -MaxContainerObservations 30
    $r8NewGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r8Full -DetectConflictingContainerObservations -RequireCompleteClusterCoverageEvidence -MaxContainerObservations 30
    Assert-B ($r8Full.metrics.bytesRead -eq 30720 -and -not $r8Full.scanIncomplete -and
        $r8NewGraph.metrics.coverageEvidence -eq 'numeric_cluster_coverage_consistent' -and
        $r8NewGraph.metrics.probableEdgeAssertions -eq $r8OldGraph.metrics.probableEdgeAssertions) 'R8 full synthetic scanner counts preserve probable relationships'
    Assert-B ($r8Pos -eq $r8Stream.Position -and -not $r8Stream.CanWrite -and
        (Get-R4Sha256 $r4Image) -eq $r8Hash) 'R8 hierarchy requires no source reads; artificial SHA unchanged'
    $r8Partial=Get-ChappyDirectoryCandidates -Stream $r8Stream -Geometry $r4Geo -MaxScanBytes 5120
    $r8PartialGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r8Partial -DetectConflictingContainerObservations -RequireCompleteClusterCoverageEvidence -MaxContainerObservations 30
    Assert-B ($r8Partial.metrics.bytesRead -eq 5120 -and $r8Partial.scanIncomplete -and
        $r8PartialGraph.scanIncomplete -and $r8PartialGraph.metrics.probableEdgeAssertions -eq 0 -and
        $r8PartialGraph.warnings -contains 'hierarchy_cluster_coverage_unproven') 'R8 artificial unscanned later block explicitly unknown'
} finally {$r8Stream.Dispose()}
$r8BadLimit=$false
try {$null=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult (New-R7GraphFixture 'good_single') -RequireCompleteClusterCoverageEvidence -MaxNodes 0} catch {$r8BadLimit=$true}
Assert-B $r8BadLimit 'R8 invalid node limit rejected'
Write-Host ('SYNTHETIC R8 A/B: {0} cases; baseline TP={1} FP={2} FN={3} TN={4}; opt-in TP={5} FP={6} FN={7} TN={8}; spoofable numeric coverage remains; elapsed-ms base={9} variant={10}; no original paths proven' -f $r8Ids.Count,$r8Legacy.TP,$r8Legacy.FP,$r8Legacy.FN,$r8Legacy.TN,$r8Optin.TP,$r8Optin.FP,$r8Optin.FN,$r8Optin.TN,$r8LegacyMs,$r8OptinMs)
