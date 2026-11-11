#requires -Version 5.1
# Team B R2: pure metadata graph. No stream, file IO, FAT access or path reconstruction.
# Dot-source this file; call after Get-ChappyDirectoryCandidates.

# Confidence grades are structural candidate evidence, never verified paths.
# Old/unrecognized upstream grades intentionally fall back to partial.
function Get-ChappyBHierarchyEvidenceGrade {
    param([object]$Value)
    if ($Value -is [string] -and $Value -ceq 'probable') { return 'probable' }
    return 'partial'
}

function Get-ChappyDirectoryHierarchyEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$DirectoryResult,
        [int]$MaxNodes = 1000,
        [int]$MaxEdges = 10000,
        [int]$MaxMetadataItems = 200000,
        [int]$MaxAncestorDepth = 64,
        [int]$MaxAncestorSteps = 200000
    )
    if ($MaxNodes -lt 1 -or $MaxNodes -gt 100000 -or
        $MaxEdges -lt 1 -or $MaxEdges -gt 200000 -or
        $MaxMetadataItems -lt 1 -or $MaxMetadataItems -gt 200000 -or
        $MaxAncestorDepth -lt 1 -or $MaxAncestorDepth -gt 256 -or
        $MaxAncestorSteps -lt 1 -or $MaxAncestorSteps -gt 2000000) {
        throw 'Invalid hierarchy analysis limits'
    }
    if ($null -eq $DirectoryResult.PSObject.Properties['directoryContainers'] -or
        $null -eq $DirectoryResult.PSObject.Properties['items']) {
        throw 'Directory scan result must contain directoryContainers and items'
    }

    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList
    $hints = New-Object System.Collections.ArrayList
    $warnings = New-Object System.Collections.ArrayList
    $nodeMap = @{}
    $parentsByChild = @{}
    $incomplete = [bool]$DirectoryResult.scanIncomplete
    $unobservedTargets = 0L
    $metadataSeen = 0L

    # Accepted containers are explicit. Entries alone cannot represent a
    # directory with no ordinary file records; never infer unscanned nodes.
    foreach ($c in @($DirectoryResult.directoryContainers)) {
        if ($null -eq $c) { continue }
        if ($nodes.Count -ge $MaxNodes) {
            $incomplete = $true
            [void]$warnings.Add('hierarchy_node_limit')
            break
        }
        $cluster = [long]$c.cluster
        if ($cluster -lt 2) { continue }
        $key = [string]$cluster
        if ($nodeMap.ContainsKey($key)) { continue }
        $nodeGrade = Get-ChappyBHierarchyEvidenceGrade $c.confidence
        $node = [pscustomobject]@{
            cluster = $cluster
            isRoot = [bool]$c.isRoot
            acceptanceReason = [string]$c.decisionReason
            confidence = $nodeGrade
            parentClusterHint = $c.parentClusterHint
            linkStatus = 'unclassified_candidate'
        }
        $nodeMap[$key] = $node
        [void]$nodes.Add($node)
    }

    # Edges require TWO observed records: an accepted parent container and
    # its actual directory-type entry pointing at an accepted child container.
    # Deleted entries cannot justify links. A dotdot hint alone creates no edge.
    foreach ($entry in @($DirectoryResult.items)) {
        if ($null -eq $entry) { continue }
        $metadataSeen++
        if ($metadataSeen -gt $MaxMetadataItems) {
            $incomplete = $true
            [void]$warnings.Add('hierarchy_metadata_limit')
            break
        }
        if (-not $entry.isDirectory -or $entry.deleted) { continue }
        $parent = [long]$entry.containerCluster
        $child = [long]$entry.startCluster
        $parentKey = [string]$parent
        $childKey = [string]$child
        if (-not $nodeMap.ContainsKey($parentKey)) { continue }
        if (-not $nodeMap.ContainsKey($childKey)) {
            $unobservedTargets++
            continue
        }
        if ($edges.Count -ge $MaxEdges) {
            $incomplete = $true
            [void]$warnings.Add('hierarchy_edge_limit')
            break
        }
        $parentGrade = [string]$nodeMap[$parentKey].confidence
        $childGrade = [string]$nodeMap[$childKey].confidence
        $entryGrade = Get-ChappyBHierarchyEvidenceGrade $entry.confidence
        $edgeEvidence = @('accepted_parent_container', 'directory_entry', 'accepted_child_container')
        if ($parentGrade -ne 'probable') { $edgeEvidence += 'parent_container_weak_or_ungraded' }
        if ($childGrade -ne 'probable') { $edgeEvidence += 'child_container_weak_or_ungraded' }
        if ($entryGrade -ne 'probable') { $edgeEvidence += 'directory_entry_weak_or_ungraded' }
        $edge = [pscustomobject]@{
            parentCluster = $parent
            childCluster = $child
            entryOffsetBytes = [long]$entry.offsetBytes
            source = 'observed_directory_entry'
            relationStatus = 'pending_evidence'
            # A link can only be probable when both containers and the
            # directory entry are probable AND the dotdot hint corroborates.
            confidence = 'partial'
            parentContainerConfidence = $parentGrade
            childContainerConfidence = $childGrade
            directoryEntryConfidence = $entryGrade
            evidence = @($edgeEvidence)
        }
        [void]$edges.Add($edge)
        if (-not $parentsByChild.ContainsKey($childKey)) { $parentsByChild[$childKey] = @{} }
        $p = $parentsByChild[$childKey]
        if (-not $p.ContainsKey($parentKey)) { $p[$parentKey] = 0 }
        $p[$parentKey] = [int]$p[$parentKey] + 1
    }

    # The dotdot relation remains a separate hint; it must not create a path.
    foreach ($node in $nodes) {
        $key = [string]$node.cluster
        $refParents = $parentsByChild[$key]
        $hint = $node.parentClusterHint
        if ($node.isRoot) {
            $node.linkStatus = 'root_candidate'
        } elseif ($null -eq $refParents -or $refParents.Count -eq 0) {
            $node.linkStatus = 'orphan_candidate'
        } elseif ($refParents.Count -gt 1) {
            $node.linkStatus = 'ambiguous_multiple_parents'
        } else {
            $node.linkStatus = 'referenced_candidate'
        }

        if ($null -ne $hint -and -not $node.isRoot) {
            $hintStatus = 'unmatched_parent_hint'
            if ([long]$hint -eq 0) {
                $hintStatus = 'root_marker_not_path'
            } elseif (-not $nodeMap.ContainsKey([string]([long]$hint))) {
                $hintStatus = 'hinted_parent_not_scanned'
            } elseif ($null -ne $refParents -and $refParents.ContainsKey([string]([long]$hint))) {
                $hintStatus = 'hint_matches_directory_entry'
            }
            [void]$hints.Add([pscustomobject]@{
                childCluster = $node.cluster
                hintedParentCluster = [long]$hint
                source = 'validated_dotdot_record'
                relationStatus = $hintStatus
            })
        }
    }

    # Repeated links and two different parents are explicitly ambiguous.
    # Even mutually consistent dotdot/parent assertions are only *probable*.
    $uniqueParent = @{}
    foreach ($edge in $edges) {
        $childKey = [string]$edge.childCluster
        $parentKey = [string]$edge.parentCluster
        $childNode = $nodeMap[$childKey]
        $parentRefs = $parentsByChild[$childKey]
        $hint = $childNode.parentClusterHint
        if ($childNode.isRoot) {
            $edge.relationStatus = 'root_has_incoming_reference'
        } elseif ($edge.parentCluster -eq $edge.childCluster) {
            $edge.relationStatus = 'self_reference'
        } elseif ($parentRefs.Count -gt 1) {
            $edge.relationStatus = 'ambiguous_multiple_parents'
        } elseif ([int]$parentRefs[$parentKey] -gt 1) {
            $edge.relationStatus = 'duplicate_parent_assertion'
        } elseif ($null -eq $hint) {
            $edge.relationStatus = 'parent_hint_absent'
        } elseif ([long]$hint -ne $edge.parentCluster) {
            $edge.relationStatus = 'parent_hint_conflict'
        } else {
            $edge.relationStatus = 'parent_hint_corroborated'
            if ($edge.parentContainerConfidence -eq 'probable' -and
                $edge.childContainerConfidence -eq 'probable' -and
                $edge.directoryEntryConfidence -eq 'probable') {
                $edge.confidence = 'probable'
            }
            $edge.evidence = @($edge.evidence) + @('validated_dotdot_matches')
        }
        if ($parentRefs.Count -eq 1 -and [int]$parentRefs[$parentKey] -eq 1 -and
            -not $childNode.isRoot) {
            $uniqueParent[$childKey] = $edge.parentCluster
        }
    }

    # Follow only unique observed parent assertions. Bound each ancestor walk;
    # cycles and depth cutoffs are NOT converted into reconstructed paths.
    $depthLimited = 0L
    $ancestorSteps = 0L
    $ancestorWorkLimited = $false
    foreach ($edge in $edges) {
        if ($edge.relationStatus -eq 'self_reference') {
            $edge.relationStatus = 'cycle_detected'
            continue
        }
        if ($edge.relationStatus -eq 'ambiguous_multiple_parents' -or
            $edge.relationStatus -eq 'duplicate_parent_assertion' -or
            $edge.relationStatus -eq 'root_has_incoming_reference') { continue }
        $cursor = [long]$edge.parentCluster
        $seen = @{}
        for ($depth = 0; $depth -lt $MaxAncestorDepth; $depth++) {
            if ($ancestorSteps -ge $MaxAncestorSteps) {
                $edge.relationStatus = 'ancestor_work_limit'
                $edge.confidence = 'partial'
                $ancestorWorkLimited = $true
                $incomplete = $true
                break
            }
            $ancestorSteps++
            if ($cursor -eq $edge.childCluster) {
                $edge.relationStatus = 'cycle_detected'
                $edge.confidence = 'partial'
                break
            }
            $cursorKey = [string]$cursor
            if ($seen.ContainsKey($cursorKey) -or -not $uniqueParent.ContainsKey($cursorKey)) { break }
            $seen[$cursorKey] = $true
            $cursor = [long]$uniqueParent[$cursorKey]
            if ($depth -eq ($MaxAncestorDepth - 1)) {
                $edge.relationStatus = 'ancestor_depth_limit'
                $edge.confidence = 'partial'
                $depthLimited++
                $incomplete = $true
            }
        }
    }
    if ($depthLimited -gt 0) { [void]$warnings.Add('hierarchy_ancestor_depth_limit') }
    if ($ancestorWorkLimited) { [void]$warnings.Add('hierarchy_ancestor_work_limit') }

    # An incomplete graph cannot rule out unseen, conflicting parent entries.
    # Preserve all links as candidates but never elevate them to probable.
    $probableEdges = 0L
    $partialEdges = 0L
    foreach ($edge in $edges) {
        if ($incomplete -and $edge.confidence -eq 'probable') {
            $edge.confidence = 'partial'
            $edge.evidence = @($edge.evidence) + @('hierarchy_coverage_incomplete')
        }
        if ($edge.confidence -eq 'probable') { $probableEdges++ }
        else { $partialEdges++ }
    }

    # Build a set of conflicted children once. O(nodes+edges), not O(nodes*edges).
    $conflictedChildren = @{}
    foreach ($edge in $edges) {
        if (@('cycle_detected', 'parent_hint_conflict', 'ancestor_depth_limit',
              'ancestor_work_limit', 'duplicate_parent_assertion') -contains $edge.relationStatus) {
            $conflictedChildren[[string]$edge.childCluster] = $true
        }
    }
    foreach ($node in $nodes) {
        if ($node.linkStatus -eq 'referenced_candidate' -and
            $conflictedChildren.ContainsKey([string]$node.cluster)) {
            $node.linkStatus = 'conflicted_candidate'
        }
    }

    return [pscustomobject]@{
        schemaVersion = '1'
        team = 'B'
        status = $(if ($incomplete) { 'partial' } else { 'ok' })
        scanIncomplete = [bool]$incomplete
        nodes = @($nodes.ToArray())
        edges = @($edges.ToArray())
        parentHints = @($hints.ToArray())
        warnings = @($warnings.ToArray())
        metrics = [pscustomobject]@{
            nodes = $nodes.Count
            edgeAssertions = $edges.Count
            probableEdgeAssertions = $probableEdges
            partialEdgeAssertions = $partialEdges
            hintCount = $hints.Count
            unresolvedTargetReferences = $unobservedTargets
            metadataItemsVisited = $metadataSeen
            ancestorDepthCutoffs = $depthLimited
            ancestorSteps = $ancestorSteps
        }
        notes = @('candidate graph only', 'no path reconstruction', 'no FAT reads', 'no file content validation')
    }
}
