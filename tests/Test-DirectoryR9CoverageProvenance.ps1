#requires -Version 5.1
# R9 synthetic scanner event provenance, same-corpus R8/R9 A/B.
# Dot-source after R4/R7/R8 suites; never access user data.

$r9SourceHash=Get-R4Sha256 $r4Image
$r9Stream=New-R4ReadonlyStream $r4Image
try {
    $r9FullScan=Get-ChappyDirectoryCandidates -Stream $r9Stream -Geometry $r4Geo -MaxScanBytes 30720 -RecordClusterCoverage -MaxCoverageClusters 30 -MaxCoverageIntervals 8
    $r9StreamPosition=$r9Stream.Position
    Assert-B (-not $r9Stream.CanWrite -and $r9FullScan.status -eq 'ok' -and
        $r9FullScan.metrics.bytesRead -eq 30720 -and
        $r9FullScan.coverageProvenance.status -eq 'recorded' -and
        $r9FullScan.coverageProvenance.source -eq 'scanner_read_events_v1' -and
        $r9FullScan.coverageProvenance.uniqueClusters -eq 30 -and
        $r9FullScan.coverageProvenance.duplicateReadEvents -eq 0 -and
        $r9FullScan.coverageProvenance.intervals.Count -eq 1 -and
        $r9FullScan.coverageProvenance.intervals[0].firstCluster -eq 2 -and
        $r9FullScan.coverageProvenance.intervals[0].lastCluster -eq 31) 'R9 artificial scanner records 30 unique read-event clusters in one interval'
    $r9CompleteGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r9FullScan -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxContainerObservations 30
    Assert-B ($r9CompleteGraph.metrics.coverageEvidence -eq 'scanner_reported_interval_consistent' -and
        $r9CompleteGraph.metrics.probableEdgeAssertions -ge 2 -and
        $r9Stream.Position -eq $r9StreamPosition -and
        (Get-R4Sha256 $r4Image) -eq $r9SourceHash) 'R9 complete artificial scanner-to-graph integration has no extra source reads or writes'
    $r9PartialScan=Get-ChappyDirectoryCandidates -Stream $r9Stream -Geometry $r4Geo -MaxScanBytes 5120 -RecordClusterCoverage -MaxCoverageClusters 30
    $r9PartialGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r9PartialScan -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxContainerObservations 30
    Assert-B ($r9PartialScan.metrics.bytesRead -eq 5120 -and
        $r9PartialScan.coverageProvenance.uniqueClusters -eq 5 -and
        $r9PartialScan.coverageProvenance.intervals[0].firstCluster -eq 2 -and
        $r9PartialScan.coverageProvenance.intervals[0].lastCluster -eq 6 -and
        $r9PartialGraph.scanIncomplete -and $r9PartialGraph.metrics.probableEdgeAssertions -eq 0 -and
        $r9PartialGraph.warnings -contains 'hierarchy_cluster_interval_coverage_unproven') 'R9 partial artificial cluster interval explicitly unknown'
    $r9CapScan=Get-ChappyDirectoryCandidates -Stream $r9Stream -Geometry $r4Geo -MaxScanBytes 30720 -RecordClusterCoverage -MaxCoverageClusters 8
    $r9CapGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r9CapScan -RequireObservedClusterIntervals -MaxNodes 30
    Assert-B ($r9CapScan.coverageProvenance.status -eq 'cluster_limit' -and
        $r9CapScan.coverageProvenance.intervals.Count -eq 0 -and
        $r9CapScan.directoryContainers.Count -eq $r9FullScan.directoryContainers.Count -and
        $r9CapGraph.metrics.probableEdgeAssertions -eq 0) 'R9 tiny memory cap retains candidate nodes but rejects unproven coverage'
    $r9Untraced=Get-ChappyDirectoryCandidates -Stream $r9Stream -Geometry $r4Geo -MaxScanBytes 30720
    Assert-B ($null -eq $r9Untraced.coverageProvenance -and
        $r9Untraced.items.Count -eq $r9FullScan.items.Count -and
        (Get-R4Sha256 $r4Image) -eq $r9SourceHash) 'R9 default-OFF tracing preserves original artificial candidate counts and SHA'
} finally {$r9Stream.Dispose()}

function New-R9GraphCase([string]$Id,[object]$FullLedger) {
    if ($Id -in @('duplicate_cluster_reads','hidden_later_parent_cluster','forged_full_ledger')) {
        $sample=New-R8GraphCase 'spoofed_full_count'
        $sample.id=$Id
        $sample.truth=$false
        if ($Id -eq 'duplicate_cluster_reads') {
            $sample.input | Add-Member NoteProperty coverageProvenance ([pscustomobject]@{
                source='scanner_read_events_v1';status='recorded'
                uniqueClusters=15L;readEvents=30L;duplicateReadEvents=15L
                intervals=@(
                    [pscustomobject]@{firstCluster=2L;lastCluster=16L}
                    [pscustomobject]@{firstCluster=2L;lastCluster=16L}
                )
            })
        } elseif ($Id -eq 'hidden_later_parent_cluster') {
            $sample.input | Add-Member NoteProperty coverageProvenance ([pscustomobject]@{
                source='scanner_read_events_v1';status='recorded'
                uniqueClusters=17L;readEvents=17L;duplicateReadEvents=0L
                intervals=@([pscustomobject]@{firstCluster=2L;lastCluster=18L})
            })
        } else {
            # The fake perfectly matching full-ledger case stays a negative.
            # Caller-supplied objects are NOT authenticated by this method.
            $sample.input | Add-Member NoteProperty coverageProvenance $FullLedger
        }
        return $sample
    }
    $sample=New-R8GraphCase $Id
    if ($Id -in @('good_full','good_full_duplicate')) {
        $sample.input | Add-Member NoteProperty coverageProvenance $FullLedger
    }
    return $sample
}
$r9CaseIds=@($r8Ids)+@('duplicate_cluster_reads','hidden_later_parent_cluster','forged_full_ledger')
$r9Base=@{TP=0;FP=0;FN=0;TN=0}
$r9Variant=@{TP=0;FP=0;FN=0;TN=0}
$r9BaselineMs=0L;$r9VariantMs=0L
$r9UniqueIds=New-Object 'System.Collections.Generic.HashSet[string]'
foreach($r9Id in $r9CaseIds) {
    if(-not $r9UniqueIds.Add($r9Id)){throw 'Duplicate R9 test case'}
    $r9Case=New-R9GraphCase $r9Id $r9FullScan.coverageProvenance
    $r9BeforeJson=ConvertTo-Json -InputObject $r9Case.input -Depth 10 -Compress
    $r9Clock=[Diagnostics.Stopwatch]::StartNew()
    $r9Old=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r9Case.input -DetectConflictingContainerObservations -RequireCompleteClusterCoverageEvidence -MaxContainerObservations 16 -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
    $r9Clock.Stop();$r9BaselineMs+=$r9Clock.ElapsedMilliseconds
    $r9Clock=[Diagnostics.Stopwatch]::StartNew()
    $r9New=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r9Case.input -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxContainerObservations 16 -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
    $r9Clock.Stop();$r9VariantMs+=$r9Clock.ElapsedMilliseconds
    if((ConvertTo-Json -InputObject $r9Case.input -Depth 10 -Compress) -cne $r9BeforeJson){
        throw ('R9 mutated artificial graph input: '+$r9Id)
    }
    $r9OldPositive=@($r9Old.edges|Where-Object{$_.parentCluster -eq 2 -and $_.childCluster -eq 7 -and $_.confidence -eq 'probable'}).Count -gt 0
    $r9NewPositive=@($r9New.edges|Where-Object{$_.parentCluster -eq 2 -and $_.childCluster -eq 7 -and $_.confidence -eq 'probable'}).Count -gt 0
    foreach($r9M in @(@{result=$r9Base;positive=$r9OldPositive},@{result=$r9Variant;positive=$r9NewPositive})){
        $r9Class=if($r9Case.truth){if($r9M.positive){'TP'}else{'FN'}}else{if($r9M.positive){'FP'}else{'TN'}}
        $r9M.result[$r9Class]++
    }
    if($r9Old.metrics.nodes -ne $r9New.metrics.nodes -or
       $r9Old.metrics.edgeAssertions -ne $r9New.metrics.edgeAssertions -or
       $r9Old.metrics.metadataItemsVisited -ne $r9New.metrics.metadataItemsVisited){
        throw ('R9 discarded candidate evidence: '+$r9Id)
    }
    if($r9New.scanIncomplete -and $r9New.metrics.probableEdgeAssertions -ne 0){
        throw ('R9 incomplete coverage promoted parent edge: '+$r9Id)
    }
    if((ConvertTo-Json -InputObject $r9New -Depth 10) -match 'INVENTED_R7_NAME|R7SYNTH.TXT|verified|originalPath'){
        throw ('R9 metadata output leaked invented names or claimed original path: '+$r9Id)
    }
    if($r9Id -in @('duplicate_cluster_reads','hidden_later_parent_cluster') -and
       ($r9New.metrics.coverageEvidence -ne 'unproven' -or
        $r9New.warnings -notcontains 'hierarchy_cluster_interval_coverage_unproven' -or $r9NewPositive)){
        throw ('R9 missed duplicate or hidden later observation: '+$r9Id)
    }
    if($r9Id -eq 'forged_full_ledger' -and
       (-not $r9NewPositive -or $r9New.metrics.coverageEvidence -ne 'scanner_reported_interval_consistent')){
        throw 'R9 must preserve known fabricated-ledger residual false positive'
    }
}
Assert-B ($r9CaseIds.Count -eq 17 -and $r9UniqueIds.Count -eq 17) 'R9 same 14 R8 cases plus three independently specified negatives'
Assert-B ($r9Base.TP -eq 2 -and $r9Base.FP -eq 11 -and $r9Base.FN -eq 0 -and $r9Base.TN -eq 4) 'R9 R8 baseline artificial structural TP2 FP11 FN0 TN4'
Assert-B ($r9Variant.TP -eq 2 -and $r9Variant.FP -eq 1 -and $r9Variant.FN -eq 0 -and $r9Variant.TN -eq 14) 'R9 opt-in interval guard artificial TP2 FP1 FN0 TN14 with fabricated ledger residual'
Assert-B ($r9Variant.TP -eq $r9Base.TP -and $r9Variant.FP -lt $r9Base.FP) 'R9 no lost artificial positive and fewer false probable edges'
Assert-B ((Get-R4Sha256 $r4Image) -eq $r9SourceHash) 'R9 synthetic source SHA unchanged after matching A/B'
Write-Host ('SYNTHETIC R9 ONLY: cases={0}; R8 TP={1} FP={2} FN={3} TN={4}; R9 TP={5} FP={6} FN={7} TN={8}; forged-ledger FP remains; elapsed-ms baseline={9} variant={10}; original file recovery=not performed' -f $r9CaseIds.Count,$r9Base.TP,$r9Base.FP,$r9Base.FN,$r9Base.TN,$r9Variant.TP,$r9Variant.FP,$r9Variant.FN,$r9Variant.TN,$r9BaselineMs,$r9VariantMs)
