#requires -Version 5.1
# B R4 research-only: generated damaged data; oracle labels stay in this test.
# Dot-source after Test-DirectoryR4EmptyAndLfnNegative.ps1, no real media.

$r4PSeed=202611
$r4PRootOffset=[long]$r4NLayout.rootOffsetBytes
$r4PFull=New-ChappyA3DDamagedFixture -Case M00 -Seed $r4PSeed
[byte[]]$r4PFakeParentBytes=[byte[]]$r4PFull.image.Clone()
if($r4PFakeParentBytes[$r4PRootOffset+96] -ne 0){throw 'Artificial false-parent slot occupied'}
[byte[]]$r4PFakeEntry=New-ShortB 'BAITDIR    ' 0x10 27 0
[Array]::Copy($r4PFakeEntry,0,$r4PFakeParentBytes,([int]$r4PRootOffset+96),32)
$r4PCases=@(
    [pscustomobject]@{id='genuine_empty_start_0_and_9';bytes=[byte[]]$r4NBytes.Clone()},
    [pscustomobject]@{id='M04_damaged_size';bytes=[byte[]](New-ChappyA3DDamagedFixture -Case M04 -Seed $r4PSeed).image},
    [pscustomobject]@{id='M04L_bad_LFN';bytes=[byte[]](New-ChappyA3DDamagedFixture -Case M04L -Seed $r4PSeed).image},
    [pscustomobject]@{id='false_parent_missing_child';bytes=$r4PFakeParentBytes},
    [pscustomobject]@{id='X02_truncated_before_data';bytes=[byte[]](New-ChappyA3DDamagedFixture -Case X02 -Seed $r4PSeed).image}
)
$r4PBaselineMs=0L;$r4PVariantMs=0L;$r4PDirectoryDataBytes=0L
$r4PObservedSpans=0;$r4PUnknown=0;$r4PConfusions=@{TP=0;FP=0;FN=0;TN=0}
foreach($r4PCase in $r4PCases){
    [byte[]]$r4PImage=$r4PCase.bytes
    $r4PHash=Get-A3DSha256 $r4PImage
    $r4PBaseStream=[IO.MemoryStream]::new($r4PImage,$false)
    $r4PTestStream=[IO.MemoryStream]::new($r4PImage,$false)
    try {
        $r4PWatch=[Diagnostics.Stopwatch]::StartNew()
        $r4PBase=Get-ChappyDirectoryCandidates -Stream $r4PBaseStream -MaxScanBytes 1024 -MaxCandidates 32 -MaxDirectories 16 -ExperimentalFlagZeroSizeNonzeroStartCluster
        $r4PWatch.Stop();$r4PBaselineMs+=$r4PWatch.ElapsedMilliseconds
        $r4PWatch=[Diagnostics.Stopwatch]::StartNew()
        $r4PTest=Get-ChappyDirectoryCandidates -Stream $r4PTestStream -MaxScanBytes 1024 -MaxCandidates 32 -MaxDirectories 16 -ExperimentalFlagZeroSizeNonzeroStartCluster -RecordDirectoryReadSpans -MaxDirectoryReadSpans 8
        $r4PWatch.Stop();$r4PVariantMs+=$r4PWatch.ElapsedMilliseconds
        Assert-B (-not $r4PBaseStream.CanWrite -and -not $r4PTestStream.CanWrite -and $r4PBase.status -eq $r4PTest.status -and $r4PBase.scanIncomplete -eq $r4PTest.scanIncomplete -and $r4PBase.items.Count -eq $r4PTest.items.Count -and $r4PBase.directoryContainers.Count -eq $r4PTest.directoryContainers.Count -and $r4PBase.metrics.bytesRead -eq $r4PTest.metrics.bytesRead -and $null -eq $r4PBase.directoryReadEvidence) ('R4 provenance preserves scanner candidate counts: '+$r4PCase.id)
        $r4PJsonBase=ConvertTo-Json -InputObject @($r4PBase.items) -Depth 8 -Compress
        $r4PJsonTest=ConvertTo-Json -InputObject @($r4PTest.items) -Depth 8 -Compress
        Assert-B ($r4PJsonBase -ceq $r4PJsonTest) ('R4 same candidate metadata, no confidence promotion: '+$r4PCase.id)
        $r4PDirectoryDataBytes += [long]$r4PBase.metrics.bytesRead+[long]$r4PTest.metrics.bytesRead
        if($r4PCase.id -eq 'X02_truncated_before_data'){
            $r4PUnknown++
            Assert-B ($r4PTest.metrics.bytesRead -eq 0 -and $r4PTest.status -eq 'error' -and $r4PTest.directoryReadEvidence.status -eq 'no_successful_reads' -and $r4PTest.directoryReadEvidence.readEvents -eq 0 -and $r4PTest.directoryReadEvidence.spans.Count -eq 0) 'R4 X02 no successful directory read; not classified as negative'
        } else {
            Assert-B ($r4PTest.metrics.bytesRead -eq 512 -and $r4PTest.scanIncomplete -and $r4PTest.directoryReadEvidence.status -eq 'recorded' -and $r4PTest.directoryReadEvidence.source -eq 'directory_scanner_successful_cluster_reads_v1' -and $r4PTest.directoryReadEvidence.readEvents -eq 1 -and $r4PTest.directoryReadEvidence.recordedSpans -eq 1 -and $r4PTest.directoryReadEvidence.spans[0].offsetBytes -eq $r4PRootOffset -and $r4PTest.directoryReadEvidence.spans[0].lengthBytes -eq 512 -and $r4PTest.directoryReadEvidence.spans[0].cluster -eq 2) ('R4 successful root read yields numeric byte range: '+$r4PCase.id)
            $r4PObservedSpans++
            $r4PGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4PTest -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
            $r4PGraphJson=ConvertTo-Json -InputObject $r4PGraph -Depth 8
            Assert-B ($r4PGraph.scanIncomplete -and $r4PGraph.metrics.probableEdgeAssertions -eq 0 -and $r4PGraph.metrics.edgeAssertions -eq 0 -and $r4PGraphJson -notmatch 'originalPath|verified|BAITDIR|EMPTY') ('R4 partial root scan never certifies original parent: '+$r4PCase.id)
            if($r4PCase.id -eq 'false_parent_missing_child'){
                Assert-B (@($r4PTest.items|Where-Object{$_.isDirectory -and $_.startCluster -eq 27}).Count -eq 1 -and $r4PGraph.metrics.unresolvedTargetReferences -eq 1 -and $r4PGraph.nodes.Count -eq 1) 'R4 false-parent entry retained; unobserved child has no graph edge'
            }
            if($r4PCase.id -eq 'M04L_bad_LFN'){
                Assert-B (@($r4PTest.items|Where-Object{$_.evidence -contains 'lfn_rejected_short_fallback' -and $_.confidence -eq 'partial'}).Count -eq 1) 'R4 damaged LFN remains partial short-alias fallback'
            }
            if($r4PCase.id -eq 'M04_damaged_size'){
                $r4PDamage=@($r4PTest.items|Where-Object{-not $_.isDirectory -and $_.sizeBytes -eq 0 -and $_.startCluster -ge 2 -and $_.evidence -contains 'zero_size_with_nonzero_start_cluster'})
                Assert-B ($r4PDamage.Count -eq 1 -and $r4PDamage[0].confidence -eq 'partial') 'R4 M04 observed size-warning is not proof of corruption'
                $r4PConfusions.TP++
            }
            if($r4PCase.id -eq 'genuine_empty_start_0_and_9'){
                $r4PZero=@($r4PTest.items|Where-Object{-not $_.isDirectory -and $_.sizeBytes -eq 0 -and $_.startCluster -eq 0})
                $r4PNine=@($r4PTest.items|Where-Object{-not $_.isDirectory -and $_.sizeBytes -eq 0 -and $_.startCluster -eq 9})
                Assert-B ($r4PZero.Count -eq 1 -and $r4PZero[0].confidence -eq 'probable' -and $r4PNine.Count -eq 1 -and $r4PNine[0].confidence -eq 'partial' -and $r4PNine[0].evidence -contains 'zero_size_with_nonzero_start_cluster') 'R4 genuine empty start9 stays explicit false warning, candidate retained'
                $r4PConfusions.TN++;$r4PConfusions.FP++
            }
        }
        $r4PLedgerJson=ConvertTo-Json -InputObject $r4PTest.directoryReadEvidence -Depth 6
        Assert-B (@($r4PTest.items|Where-Object{$null -ne $_.name -or $null -ne $_.shortName}).Count -eq 0 -and $r4PLedgerJson -notmatch 'EMPTY|BAITDIR|MODEL|PRINT|originalPath') ('R4 redacted names and numeric-only read ledger: '+$r4PCase.id)
    } finally {$r4PBaseStream.Dispose();$r4PTestStream.Dispose()}
    Assert-B ((Get-A3DSha256 $r4PImage) -ceq $r4PHash) ('R4 synthetic source unchanged: '+$r4PCase.id)
}
Assert-B ($r4PConfusions.TP -eq 1 -and $r4PConfusions.FP -eq 1 -and $r4PConfusions.FN -eq 0 -and $r4PConfusions.TN -eq 1 -and $r4PUnknown -eq 1) 'R4 observed-range A/B preserves warning TP1 FP1 FN0 TN1 with X02 unknown'
Assert-B ($r4PDirectoryDataBytes -eq 4096 -and $r4PObservedSpans -eq 4) 'R4 equal-corpus 4096B directory data reads, four measured spans; geometry reads excluded'

$r4PCapSource=New-ChappyA3DDamagedFixture -Case M00 -Seed $r4PSeed
[byte[]]$r4PCapImage=$r4PCapSource.image
$r4PCapHash=Get-A3DSha256 $r4PCapImage
$r4PCapStream=[IO.MemoryStream]::new($r4PCapImage,$false)
try {
    $r4PCapScan=Get-ChappyDirectoryCandidates -Stream $r4PCapStream -MaxScanBytes 2048 -MaxCandidates 32 -MaxDirectories 16 -RecordDirectoryReadSpans -MaxDirectoryReadSpans 1
    Assert-B ($r4PCapScan.directoryReadEvidence.status -eq 'span_limit' -and $r4PCapScan.directoryReadEvidence.readEvents -eq 4 -and $r4PCapScan.directoryReadEvidence.recordedSpans -eq 1 -and $r4PCapScan.metrics.bytesRead -eq 2048 -and $r4PCapScan.directoryReadEvidence.spans[0].offsetBytes -eq $r4PRootOffset -and -not $r4PCapStream.CanWrite) 'R4 span quota exceeded: evidence partial, candidates unaffected'
} finally {$r4PCapStream.Dispose()}
Assert-B ((Get-A3DSha256 $r4PCapImage) -ceq $r4PCapHash) 'R4 bounded trace never mutates generated input'
Write-Host ('SYNTHETIC B R4 P1 ONLY: warning TP={0} FP={1} FN={2} TN={3} unknown={4}; observed root spans={5}; same-corpus directory-read bytes={6}; times-ms old={7} new={8}; no original identity verified' -f $r4PConfusions.TP,$r4PConfusions.FP,$r4PConfusions.FN,$r4PConfusions.TN,$r4PUnknown,$r4PObservedSpans,$r4PDirectoryDataBytes,$r4PBaselineMs,$r4PVariantMs)
