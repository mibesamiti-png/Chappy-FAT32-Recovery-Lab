#requires -Version 5.1
# Team B R6: artificial graph and 64KiB synthetic in-memory R4 source only.
# Dot-sourced from Test-DirectoryScanner.ps1 after R4/R5 helper tests.

function New-R6Container([long]$Cluster, [object]$Hint, [bool]$Root, [object]$Confidence) {
    return [pscustomobject]@{
        cluster = $Cluster
        parentClusterHint = $Hint
        isRoot = $Root
        decisionReason = 'artificial_container'
        confidence = $Confidence
    }
}
function New-R6Link([long]$Parent, [long]$Child, [string]$Confidence, [bool]$Deleted = $false) {
    return [pscustomobject]@{
        containerCluster = $Parent
        startCluster = $Child
        isDirectory = $true
        deleted = $Deleted
        offsetBytes = (($Parent*1024L)+$Child)
        confidence = $Confidence
        name = 'INVENTED_SENTINEL_NAME'
        shortName = 'INVENTED.TXT'
    }
}
$sim = [pscustomobject]@{
    scanIncomplete = $false
    directoryContainers = @(
        (New-R6Container 2 $null $true 'probable')
        (New-R6Container 7 2 $false 'probable')
        (New-R6Container 9 2 $false 'partial')
        (New-R6Container 12 9 $false 'probable')
        (New-R6Container 15 2 $false 'partial')
        (New-R6Container 18 2 $false 'probable')
        (New-R6Container 25 2 $false 'verified') # untrusted grade must NOT be promoted
        (New-R6Container 31 2 $false 'probable')
        (New-R6Container 32 2 $false 'probable')
        (New-R6Container 40 41 $false 'probable')
        (New-R6Container 41 40 $false 'probable')
        (New-R6Container 30 2 $false 'partial') # orphan: deleted incoming link
    )
    items = @(
        (New-R6Link 2 7 'probable')
        (New-R6Link 2 9 'probable')
        (New-R6Link 9 12 'probable')
        (New-R6Link 2 15 'probable')
        (New-R6Link 2 18 'partial')
        (New-R6Link 2 25 'probable')
        (New-R6Link 2 31 'probable')
        (New-R6Link 2 32 'probable')
        (New-R6Link 7 32 'probable') # multiple incoming parents
        (New-R6Link 40 41 'probable')
        (New-R6Link 41 40 'probable') # two-edge cycle
        (New-R6Link 2 30 'probable' $true) # deleted link not evidence
        (New-R6Link 2 99 'probable') # missing scanned target
        (New-R6Link 2 2 'probable')  # root incoming is not a valid path
    )
}
$graph = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $sim
Assert-B ($graph.status -eq 'ok' -and -not $graph.scanIncomplete -and
    $graph.metrics.nodes -eq 12 -and $graph.metrics.edgeAssertions -eq 12) 'R6 artificial graph retains bounded nodes and links'

$strong = @($graph.edges | Where-Object { $_.confidence -eq 'probable' })
$corroborated = @($graph.edges | Where-Object { $_.relationStatus -eq 'parent_hint_corroborated' })
Assert-B ($strong.Count -eq 2 -and $corroborated.Count -eq 7 -and
    $graph.metrics.probableEdgeAssertions -eq 2 -and
    $graph.metrics.partialEdgeAssertions -eq 10) 'R6 modeled previous corroboration 7 versus confidence-qualified 2 edges'
Assert-B (@($strong | Where-Object {
    ($_.parentCluster -eq 2 -and $_.childCluster -eq 7) -or
    ($_.parentCluster -eq 2 -and $_.childCluster -eq 31)
}).Count -eq 2 -and @($strong | Where-Object {
    $_.parentContainerConfidence -ne 'probable' -or
    $_.childContainerConfidence -ne 'probable' -or
    $_.directoryEntryConfidence -ne 'probable'
}).Count -eq 0) 'R6 probable links require three independent probable structural inputs'

$weakParent = @($graph.edges | Where-Object {$_.parentCluster -eq 9 -and $_.childCluster -eq 12})
Assert-B ($weakParent.Count -eq 1 -and $weakParent[0].relationStatus -eq 'parent_hint_corroborated' -and
    $weakParent[0].confidence -eq 'partial' -and
    $weakParent[0].evidence -contains 'parent_container_weak_or_ungraded') 'R6 weak parent is never promoted by matching child dotdot'

$weakChild = @($graph.edges | Where-Object {$_.parentCluster -eq 2 -and $_.childCluster -eq 9})
Assert-B ($weakChild.Count -eq 1 -and $weakChild[0].confidence -eq 'partial' -and
    $weakChild[0].evidence -contains 'child_container_weak_or_ungraded') 'R6 weak child stays partial even with a probable root parent'

$weakEntry = @($graph.edges | Where-Object {$_.parentCluster -eq 2 -and $_.childCluster -eq 18})
Assert-B ($weakEntry.Count -eq 1 -and $weakEntry[0].confidence -eq 'partial' -and
    $weakEntry[0].evidence -contains 'directory_entry_weak_or_ungraded') 'R6 weak link metadata cannot be upgraded by probable containers'

$spoof = @($graph.edges | Where-Object {$_.parentCluster -eq 2 -and $_.childCluster -eq 25})
Assert-B ($spoof.Count -eq 1 -and $spoof[0].confidence -eq 'partial' -and
    $spoof[0].childContainerConfidence -eq 'partial' -and
    @($graph.nodes | Where-Object {$_.cluster -eq 25 -and $_.confidence -eq 'partial'}).Count -eq 1) 'R6 unsupported verified grade downgrades to partial rather than certifying a path'

Assert-B (@($graph.edges | Where-Object {
    $_.childCluster -eq 32 -and $_.relationStatus -eq 'ambiguous_multiple_parents' -and
    $_.confidence -eq 'partial'
}).Count -eq 2 -and
    @($graph.edges | Where-Object {
        $_.relationStatus -eq 'cycle_detected' -and $_.confidence -eq 'partial'
    }).Count -eq 2) 'R6 ambiguous parent assertions and cycles never become probable'

Assert-B (@($graph.nodes | Where-Object {
    $_.cluster -eq 30 -and $_.linkStatus -eq 'orphan_candidate' -and
    $_.confidence -eq 'partial'
}).Count -eq 1 -and
    @($graph.edges | Where-Object {$_.childCluster -eq 30}).Count -eq 0 -and
    $graph.metrics.unresolvedTargetReferences -eq 1) 'R6 deleted links and missing targets do not fabricate parent paths'

Assert-B ((ConvertTo-Json -InputObject $graph -Depth 8) -notmatch 'INVENTED_SENTINEL_NAME|INVENTED.TXT|verified' -and
    @($graph.edges | Where-Object {$_.confidence -notin @('probable','partial')}).Count -eq 0) 'R6 confidence output only fixed grades and never includes file names or verified paths'

# Legacy/ungraded metadata may be from a partially migrated caller: accept
# it as candidate evidence, never manufacture a probable relationship.
$legacy = [pscustomobject]@{
    scanIncomplete = $false
    directoryContainers = @(
        (New-HierarchyContainerB 2 $null $true)
        (New-HierarchyContainerB 7 2 $false)
    )
    items = @((New-HierarchyLinkB 2 7 123))
}
$legacyGraph = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $legacy
Assert-B ($legacyGraph.edges.Count -eq 1 -and
    $legacyGraph.edges[0].relationStatus -eq 'parent_hint_corroborated' -and
    $legacyGraph.edges[0].confidence -eq 'partial' -and
    $legacyGraph.nodes[0].confidence -eq 'partial') 'R6 legacy missing confidence defaults safely to partial'

# Artificial incomplete reads or graph limits could hide conflicting parents.
# No link in an incomplete graph may remain structurally probable.
$r6IncompleteInput = [pscustomobject]@{
    scanIncomplete = $true
    directoryContainers = $sim.directoryContainers
    items = $sim.items
}
$incompleteGraph = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r6IncompleteInput
Assert-B ($incompleteGraph.scanIncomplete -and $incompleteGraph.status -eq 'partial' -and
    $incompleteGraph.metrics.probableEdgeAssertions -eq 0 -and
    @($incompleteGraph.edges | Where-Object {$_.confidence -ne 'partial'}).Count -eq 0 -and
    @($incompleteGraph.edges | Where-Object {
        $_.evidence -contains 'hierarchy_coverage_incomplete'
    }).Count -ge 2) 'R6 incomplete source scan downgrades previously probable links with evidence'

$nodesLimited = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $sim -MaxNodes 3 -MaxEdges 2
Assert-B ($nodesLimited.scanIncomplete -and
    $nodesLimited.metrics.nodes -le 3 -and $nodesLimited.metrics.edgeAssertions -le 2 -and
    $nodesLimited.metrics.probableEdgeAssertions -eq 0) 'R6 graph node/edge limits cannot leave probable path links'

$workLimited = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $sim -MaxAncestorSteps 1
Assert-B ($workLimited.scanIncomplete -and
    $workLimited.metrics.ancestorSteps -le 1 -and
    $workLimited.metrics.probableEdgeAssertions -eq 0) 'R6 global ancestor-work limit downgrades all links'

# Integrate against R4's invented 64KiB in-memory IMG to test the real
# B scanner -> B hierarchy pipeline with corrupted FAT area, no device access.
$r4Hash = Get-R4Sha256 $r4Image
$readOnly = New-R4ReadonlyStream $r4Image
try {
    $syntheticScan = Get-ChappyDirectoryCandidates -Stream $readOnly -Geometry $r4Geo -MaxScanBytes 30720
    $streamPos = $readOnly.Position
    $syntheticGraph = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $syntheticScan
    Assert-B ($syntheticScan.status -eq 'ok' -and $syntheticGraph.status -eq 'ok' -and
        $syntheticGraph.metrics.probableEdgeAssertions -ge 2 -and
        @($syntheticGraph.edges | Where-Object {
            $_.parentCluster -eq 2 -and $_.childCluster -eq 6 -and $_.confidence -eq 'probable'
        }).Count -eq 1) 'R6 real scanner output corroborates strong artificial parent-child links'
    Assert-B (@($syntheticScan.directoryContainers | Where-Object {
        $_.cluster -eq 25 -and $_.confidence -eq 'partial'
    }).Count -eq 1 -and
        @($syntheticGraph.nodes | Where-Object {
            $_.cluster -eq 25 -and $_.confidence -eq 'partial' -and $_.linkStatus -eq 'orphan_candidate'
        }).Count -eq 1) 'R6 scanner-to-graph weak artificial file-data masquerade remains orphan partial'
    Assert-B (-not $readOnly.CanWrite -and $streamPos -eq $readOnly.Position -and
        (Get-R4Sha256 $r4Image) -eq $r4Hash -and
        (ConvertTo-Json -InputObject $syntheticGraph -Depth 8) -notmatch 'INVENTED_SENTINEL_NAME') 'R6 graph computation makes no reads/writes and source hash remains unchanged'
} finally { $readOnly.Dispose() }
Write-Host 'SYNTHETIC R6 ONLY: corroborated=7, confidence-qualified probable=2, unknown paths remain candidate-only'
