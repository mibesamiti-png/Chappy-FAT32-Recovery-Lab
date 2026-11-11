#requires -Version 5.1
# Team B R7: fixed artificial same-corpus A/B, no real media.
# Expected to be dot-sourced after the existing R4/R5/R6 synthetic helpers.

function New-R7Container([long]$Cluster,[object]$Hint,[bool]$IsRoot,[object]$Grade) {
    return [pscustomobject]@{
        cluster=$Cluster; isRoot=$IsRoot; parentClusterHint=$Hint
        confidence=$Grade; decisionReason='artificial_container'
    }
}
function New-R7Link([long]$Parent,[long]$Child,[bool]$Deleted=$false) {
    return [pscustomobject]@{
        containerCluster=$Parent; startCluster=$Child; isDirectory=$true
        deleted=$Deleted; confidence='probable'
        offsetBytes=([long]($Parent*1000+$Child))
        name='INVENTED_R7_NAME'; shortName='R7SYNTH.TXT'
    }
}
function New-R7GraphFixture([string]$Scenario) {
    $nodes=New-Object System.Collections.ArrayList
    $entries=New-Object System.Collections.ArrayList
    [void]$nodes.Add((New-R7Container 2 $null $true 'probable'))
    [void]$nodes.Add((New-R7Container 7 2 $false 'probable'))
    [void]$entries.Add((New-R7Link 2 7))
    $partialSource=$false
    switch($Scenario) {
        'good_single' {}
        'good_duplicate_identical' { [void]$nodes.Add((New-R7Container 7 2 $false 'probable')) }
        'conflict_hint_later' { [void]$nodes.Add((New-R7Container 7 9 $false 'probable')) }
        'conflict_hint_earlier' {
            $nodes[1]=(New-R7Container 7 9 $false 'probable')
            [void]$nodes.Add((New-R7Container 7 2 $false 'probable'))
        }
        'conflict_grade_later' { [void]$nodes.Add((New-R7Container 7 2 $false 'partial')) }
        'conflict_root_later' { [void]$nodes.Add((New-R7Container 7 2 $true 'probable')) }
        'weak_parent' { $nodes[0]=(New-R7Container 2 $null $true 'partial') }
        'missing_hint' { $nodes[1]=(New-R7Container 7 $null $false 'probable') }
        'incomplete_source' { $partialSource=$true }
        'duplicate_edges' { [void]$entries.Add((New-R7Link 2 7)) }
        'ambiguous_parents' {
            [void]$nodes.Add((New-R7Container 9 2 $false 'probable'))
            [void]$entries.Add((New-R7Link 9 7))
        }
        'deleted_only' {
            $entries.Clear()
            [void]$entries.Add((New-R7Link 2 7 $true))
        }
        'invalid_parent_offset' { $nodes[1]=(New-R7Container 7 -9 $false 'probable') }
        default { throw 'Unknown R7 synthetic scenario' }
    }
    return [pscustomobject]@{
        scanIncomplete=$partialSource
        directoryContainers=@($nodes.ToArray())
        items=@($entries.ToArray())
    }
}

# Ground truth is NOT an original recovered path: it labels whether the
# complete artificial evidence permits a structurally probable association.
$r7Truth=[ordered]@{
    good_single=$true
    good_duplicate_identical=$true
    conflict_hint_later=$false
    conflict_hint_earlier=$false
    conflict_grade_later=$false
    conflict_root_later=$false
    weak_parent=$false
    missing_hint=$false
    incomplete_source=$false
    duplicate_edges=$false
    ambiguous_parents=$false
    deleted_only=$false
    invalid_parent_offset=$false
}
$r7Baseline=@{TP=0;FP=0;FN=0;TN=0}
$r7Variant=@{TP=0;FP=0;FN=0;TN=0}
$r7CaseCount=0
$r7Unique=New-Object 'System.Collections.Generic.HashSet[string]'
$r7BaselineMillis=0L
$r7VariantMillis=0L
foreach($id in $r7Truth.Keys) {
    if(-not $r7Unique.Add($id)) { throw 'Duplicate R7 scenario ID' }
    $fixture=New-R7GraphFixture $id
    $r7FixtureBefore=ConvertTo-Json -InputObject $fixture -Depth 8 -Compress
    $t=[System.Diagnostics.Stopwatch]::StartNew()
    $old=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $fixture -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
    $t.Stop();$r7BaselineMillis += $t.ElapsedMilliseconds
    $t=[System.Diagnostics.Stopwatch]::StartNew()
    $new=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $fixture -DetectConflictingContainerObservations -MaxContainerObservations 16 -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
    $t.Stop();$r7VariantMillis += $t.ElapsedMilliseconds
    if((ConvertTo-Json -InputObject $fixture -Depth 8 -Compress) -cne $r7FixtureBefore) {
        throw 'R7 A/B modified an artificial input fixture'
    }
    $oldProbable=(@($old.edges | Where-Object { $_.parentCluster -eq 2 -and $_.childCluster -eq 7 -and $_.confidence -eq 'probable' }).Count -gt 0)
    $newProbable=(@($new.edges | Where-Object { $_.parentCluster -eq 2 -and $_.childCluster -eq 7 -and $_.confidence -eq 'probable' }).Count -gt 0)
    foreach($method in @(@{m=$r7Baseline;pred=$oldProbable},@{m=$r7Variant;pred=$newProbable})) {
        $name=if($r7Truth[$id]){if($method.pred){'TP'}else{'FN'}}else{if($method.pred){'FP'}else{'TN'}}
        $method.m[$name]++
    }
    if($old.metrics.nodes -ne $new.metrics.nodes -or
        $old.metrics.edgeAssertions -ne $new.metrics.edgeAssertions -or
        $old.metrics.metadataItemsVisited -ne $new.metrics.metadataItemsVisited -or
        $old.scanIncomplete -ne $fixture.scanIncomplete -and
        $id -notin @('incomplete_source')) {
        throw ('R7 method changed accepted candidate coverage: '+$id)
    }
    if(@($new.nodes|Where-Object {$_.confidence -eq 'verified'}).Count -ne 0 -or
        @($new.edges|Where-Object {$_.confidence -eq 'verified'}).Count -ne 0 -or
        (ConvertTo-Json -InputObject $new -Depth 8) -match 'INVENTED_R7_NAME|R7SYNTH.TXT') {
        throw ('R7 leaked private-like synthetic names / verified assertion: '+$id)
    }
    if($id -eq 'conflict_hint_later' -or $id -eq 'conflict_grade_later' -or $id -eq 'conflict_root_later' -or $id -eq 'conflict_hint_earlier') {
        if(-not $new.nodes[1].observationConflict -or
           $new.nodes[1].confidence -ne 'partial' -or
           $new.nodes[1].evidence -notcontains 'conflicting_container_observation' -or
           $new.metrics.conflictingContainerClusters -ne 1 -or
           $new.edges[0].evidence -notcontains 'conflicting_container_observation') {
           throw ('R7 missed fixed conflict evidence: '+$id)
        }
    }
    if($id -eq 'good_duplicate_identical' -and
       ($new.metrics.conflictingContainerClusters -ne 0 -or -not $newProbable)) {
       throw 'R7 benign overlapping repeat is not a conflict'
    }
    if($id -eq 'deleted_only' -and
       ($new.edges.Count -ne 0 -or
        @($new.nodes|Where-Object {$_.cluster -eq 7 -and $_.linkStatus -eq 'orphan_candidate'}).Count -ne 1)) {
        throw 'R7 deleted incoming link invented a parent'
    }
    $r7CaseCount++
}
Assert-B ($r7CaseCount -eq 13 -and $r7Unique.Count -eq 13) 'R7 fixed thirteen-scenario same-corpus truth set and unique IDs'
Assert-B ($r7Baseline.TP -eq 2 -and $r7Baseline.FP -eq 3 -and
    $r7Baseline.FN -eq 0 -and $r7Baseline.TN -eq 8) 'R7 baseline A/B synthetic structural TP2 FP3 FN0 TN8'
Assert-B ($r7Variant.TP -eq 2 -and $r7Variant.FP -eq 0 -and
    $r7Variant.FN -eq 0 -and $r7Variant.TN -eq 11) 'R7 opt-in provenance guard synthetic structural TP2 FP0 FN0 TN11'
Assert-B ($r7Baseline.TP -eq $r7Variant.TP -and
    $r7Baseline.FN -eq $r7Variant.FN -and
    $r7Variant.FP -lt $r7Baseline.FP) 'R7 improved artificial confidence precision without losing accepted nodes or known positive links'

# Work-budget negative: duplicated observations must be capped even if the
# unique node count is small. Incomplete coverage cannot leave probable edges.
$overlap=New-R7GraphFixture 'good_duplicate_identical'
$overlapCut=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $overlap -DetectConflictingContainerObservations -MaxContainerObservations 2 -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
Assert-B ($overlapCut.scanIncomplete -and $overlapCut.metrics.containerObservationsVisited -eq 2 -and
    $overlapCut.warnings -contains 'hierarchy_container_observation_limit' -and
    $overlapCut.metrics.probableEdgeAssertions -eq 0) 'R7 duplicate-observation quota enforces unknown coverage'
$r7InvalidLimit=$false
try {
    $null=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $overlap -DetectConflictingContainerObservations -MaxContainerObservations 0
} catch { $r7InvalidLimit=$true }
Assert-B $r7InvalidLimit 'R7 reject zero observation quota'

# Scanner-level adversarial controls: all input bytes invented, scanner uses
# fixed read-only 64KiB in-memory source and never crosses LFN cluster borders.
[byte[]]$r7Image= [byte[]]$r4Image.Clone()
$alias=New-ShortB 'SCATTERA   ' 0x10 6 0
$segments=(New-LfnB 'Synthetic-LFN.txt' $alias)
[byte[]]$badLfn=[byte[]]$segments[0].Clone()
$badLfn[13]=[byte](($badLfn[13]+1) -band 255)
$records=New-R4Records
[void]$records.Add($badLfn);[void]$records.Add($alias)
[void]$records.Add((New-ShortB 'ROOT    TXT' 0x20 18 11))
Write-R4Cluster $r7Image 2 $records
$r7Hash=Get-R4Sha256 $r7Image
$r7Read=New-R4ReadonlyStream $r7Image
try {
    $scan=Get-ChappyDirectoryCandidates -Stream $r7Read -Geometry $r4Geo -MaxScanBytes 30720
    $position=$r7Read.Position
    $links=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $scan -DetectConflictingContainerObservations -MaxContainerObservations 30
    Assert-B ($scan.metrics.bytesRead -eq 30720 -and -not $scan.scanIncomplete -and
        @($scan.items|Where-Object {$_.containerCluster -eq 2 -and $_.startCluster -eq 6 -and
            $_.confidence -eq 'partial' -and $_.evidence -contains 'lfn_rejected_short_fallback'}).Count -eq 1) 'R7 corrupted artificial LFN checksum produces partial short fallback'
    Assert-B (@($links.edges|Where-Object {$_.parentCluster -eq 2 -and $_.childCluster -eq 6 -and
        $_.confidence -eq 'partial' -and $_.evidence -contains 'directory_entry_weak_or_ungraded'}).Count -eq 1) 'R7 partial LFN link cannot become probable from corroborated dotdot'
    Assert-B (@($scan.items|Where-Object {$_.containerCluster -eq 20 -and $_.nameSource -eq 'lfn_validated'}).Count -eq 0 -and
        @($scan.items|Where-Object {$_.containerCluster -eq 21 -and $_.nameSource -eq 'short_8_3'}).Count -ge 1) 'R7 cross-cluster LFN truncation does not create invented long name'
    Assert-B (@($scan.items|Where-Object {$null -ne $_.name -or $null -ne $_.shortName}).Count -eq 0 -and
        $r7Read.Position -eq $position -and -not $r7Read.CanWrite -and
        (Get-R4Sha256 $r7Image) -eq $r7Hash) 'R7 default names redacted; graph no source reads or writes; artificial SHA unchanged'
} finally { $r7Read.Dispose() }

# Deceptive dot/dotdot with invalid parent address is not a valid header.
[byte[]]$r7DotImage=[byte[]]$r4Image.Clone()
$badRecords=New-R4Records
[void]$badRecords.Add((New-ShortB '.          ' 0x10 6 0))
[void]$badRecords.Add((New-ShortB '..         ' 0x10 999 0))
[void]$badRecords.Add((New-ShortB 'BAIT    TXT' 0x20 22 12))
Write-R4Cluster $r7DotImage 6 $badRecords
$r7DotHash=Get-R4Sha256 $r7DotImage
$r7DotRead=New-R4ReadonlyStream $r7DotImage
try {
    $badScan=Get-ChappyDirectoryCandidates -Stream $r7DotRead -Geometry $r4Geo -MaxScanBytes 30720
    $badGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $badScan -DetectConflictingContainerObservations -MaxContainerObservations 30
    Assert-B (@($badScan.directoryContainers|Where-Object {$_.cluster -eq 6}).Count -eq 0 -and
        @($badGraph.edges|Where-Object {$_.childCluster -eq 6}).Count -eq 0 -and
        $badGraph.metrics.unresolvedTargetReferences -ge 1) 'R7 bogus dotdot cluster cannot validate unscanned child as original path'
    Assert-B ($badScan.metrics.bytesRead -eq 30720 -and -not $r7DotRead.CanWrite -and
        (Get-R4Sha256 $r7DotImage) -eq $r7DotHash) 'R7 malformed-dot budget and source hash preserved'
} finally { $r7DotRead.Dispose() }

Write-Host ('SYNTHETIC R7 A/B ONLY: cases={0} baseline TP={1} FP={2} FN={3} TN={4}; candidate TP={5} FP={6} FN={7} TN={8}; elapsed-ms baseline={9} candidate={10}; original-path-verification=not-performed' -f
$r7CaseCount,$r7Baseline.TP,$r7Baseline.FP,$r7Baseline.FN,$r7Baseline.TN,$r7Variant.TP,$r7Variant.FP,$r7Variant.FN,$r7Variant.TN,$r7BaselineMillis,$r7VariantMillis)
