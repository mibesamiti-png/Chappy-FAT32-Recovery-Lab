#requires -Version 5.1
# Team B R4 formal gate B4-01: same-corpus independently scored directory evidence.
# Frozen before code in Issue #71 comment 6849820245.
# Dot-sourced after existing Team B fixture helpers and positive control.
# Synthetic-only, readonly; full/original truth belongs exclusively to this scorer.

function Add-B4GateScore {
    param([hashtable]$Scores,[string]$Method,[string]$Truth,[string]$Verdict)
    if($Truth -eq 'unobserved') {
        if($Verdict -ne 'unknown') { throw 'B4-01 unobserved oracle must remain UNKNOWN' }
        $Scores[$Method].UNKNOWN++
        return
    }
    if($Verdict -eq 'unknown') {
        $Scores[$Method].UNKNOWN++
        if($Truth -eq 'damaged'){$Scores[$Method].UnknownDamaged++}
        elseif($Truth -eq 'healthy'){$Scores[$Method].UnknownHealthy++}
        else { throw 'B4-01 unexpected scorer truth' }
        return
    }
    if($Truth -eq 'damaged') {
        if($Verdict -eq 'warning'){$Scores[$Method].TP++}
        elseif($Verdict -eq 'no_alert'){$Scores[$Method].FN++}
        else {throw 'B4-01 invalid damaged verdict'}
    } elseif($Truth -eq 'healthy') {
        if($Verdict -eq 'warning'){$Scores[$Method].FP++}
        elseif($Verdict -eq 'no_alert'){$Scores[$Method].TN++}
        else {throw 'B4-01 invalid healthy verdict'}
    } else {throw 'B4-01 undefined synthetic scorer truth'}
}
$r4GateMethods=@('legacy','conservative')
$r4GateScores=@{
    legacy=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0;UnknownDamaged=0;UnknownHealthy=0}
    conservative=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0;UnknownDamaged=0;UnknownHealthy=0}
}
$r4GateCases=@('M00','M01','M04','X02')
$r4GateSeeds=@(202611,202612,202613)
$r4GateReturned=0L
$r4GateBComplete=0L
$r4GateBPhysical=0L
$r4GateCalls=0L
$r4GateRetained=@{legacy=0L;conservative=0L}
$r4GateNoOriginalClaims=0L
$r4GateUnobservedEdgeUnits=0L
$r4GateElapsed=@{legacy=0L;conservative=0L}
$r4GateLines=New-Object System.Collections.ArrayList
$r4GateDistinctSeedHashes=New-Object System.Collections.ArrayList

foreach($r4GateSeed in $r4GateSeeds) {
    $r4GateClean=New-ChappyA3DCleanFixture -Seed $r4GateSeed
    [void]$r4GateDistinctSeedHashes.Add((Get-A3DSha256 $r4GateClean.image))
    foreach($r4GateCase in $r4GateCases) {
        $r4GateRaw=New-ChappyA3DDamagedFixture -Case $r4GateCase -Seed $r4GateSeed
        [byte[]]$r4GateImage=[byte[]]$r4GateRaw.image.Clone()
        $r4GateRoot=[int]$r4GateClean.layout.rootOffsetBytes
        $r4GateHasDirectory=($r4GateCase -ne 'X02')
        if($r4GateHasDirectory) {
            # Artificial *legitimate* zero-byte allocated file; keep its
            # truth exclusively in this test. This extra root entry is at a
            # pre-declared empty slot, and test-side FAT9 is EOC in both copies.
            if($r4GateImage[$r4GateRoot+96] -ne 0) {throw 'B4-01 synthetic root slot occupied'}
            [byte[]]$r4GateEmpty=New-ShortB 'EMPTY9  TXT' 0x20 9 0
            [Array]::Copy($r4GateEmpty,0,$r4GateImage,$r4GateRoot+96,32)
            foreach($r4GateFat in @([int]$r4GateClean.layout.fat1OffsetBytes,[int]$r4GateClean.layout.fat2OffsetBytes)) {
                if([BitConverter]::ToUInt32($r4GateImage,$r4GateFat+9*4) -ne 0) {
                    throw 'B4-01 synthetic cluster9 not free before empty file allocation'
                }
                [byte[]]$r4GateEoc=[BitConverter]::GetBytes([uint32]0x0FFFFFFF)
                [Array]::Copy($r4GateEoc,0,$r4GateImage,$r4GateFat+9*4,4)
            }
        }
        $r4GateSourceSha=Get-A3DSha256 $r4GateImage
        foreach($r4GateMethod in $r4GateMethods) {
            $r4GateStream=[ChappyBR4ObservedParentPositive.MeteredStream]::new($r4GateImage,97,-1L,128)
            try {
                $r4GateParams=@{
                    Stream=$r4GateStream;MaxScanBytes=512L
                    MaxCandidates=16;MaxDirectories=8
                    RecordDirectoryReadSpans=$true;MaxDirectoryReadSpans=8
                    RecordDirectoryPhysicalReadBytes=$true
                    RecordClusterCoverage=$true
                    ClassifyIncompleteDirectoryReadOrigin=$true
                }
                if($r4GateMethod -eq 'legacy'){$r4GateParams.ExperimentalFlagZeroSizeNonzeroStartCluster=$true}
                else {$r4GateParams.ExperimentalConservativeZeroSizeUnknown=$true}
                $r4GateTimer=[Diagnostics.Stopwatch]::StartNew()
                $r4GateScan=Get-ChappyDirectoryCandidates @r4GateParams
                $r4GateGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4GateScan -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
                $r4GateTimer.Stop()
                $r4GateElapsed[$r4GateMethod]+=[long]$r4GateTimer.ElapsedMilliseconds
                $r4GateEvents=@($r4GateStream.Events)
                Assert-B (Test-BR4EventsMatchInput $r4GateEvents $r4GateImage) ('B4-01 synthetic physical event hashes/offsets match generated source: '+$r4GateSeed+' '+$r4GateCase+' '+$r4GateMethod)
                Assert-B (-not $r4GateStream.CanWrite -and $r4GateStream.CanRead -and
                    $r4GateStream.Calls -le 128 -and $r4GateStream.ReturnedBytes -le 1536L -and
                    $r4GateScan.scanIncomplete -and $r4GateGraph.scanIncomplete -and
                    $r4GateGraph.metrics.probableEdgeAssertions -eq 0 -and
                    $r4GateGraph.edges.Count -eq 0 -and
                    @($r4GateScan.items|Where-Object{$null -ne $_.name -or $null -ne $_.shortName -or
                        $_.PSObject.Properties.Name -contains 'originalPath'}).Count -eq 0) ('B4-01 bounded redacted incomplete source, no false original path: '+$r4GateSeed+' '+$r4GateCase+' '+$r4GateMethod)

                $r4GateModel=@($r4GateScan.items|Where-Object{
                    -not $_.isDirectory -and -not $_.deleted -and $_.startCluster -eq 4
                })
                $r4GateEmptyFound=@($r4GateScan.items|Where-Object{
                    -not $_.isDirectory -and -not $_.deleted -and $_.startCluster -eq 9
                })
                if($r4GateHasDirectory) {
                    Assert-B ($r4GateModel.Count -eq 1 -and $r4GateEmptyFound.Count -eq 1 -and
                        $r4GateScan.items.Count -eq 4 -and
                        $r4GateScan.metrics.bytesRead -eq 512L -and
                        $r4GateScan.directoryPhysicalReadEvidence.streamReturnedBytes -eq 512L -and
                        $r4GateScan.directoryPhysicalReadEvidence.incompleteClusterReturnedBytes -eq 0L -and
                        $r4GateStream.ReturnedBytes -eq 1536L -and
                        $r4GateScan.status -eq 'partial') ('B4-01 4 root entries and 512 physically returned directory bytes: '+$r4GateSeed+' '+$r4GateCase+' '+$r4GateMethod)
                    Assert-B (Test-BR4RangeReturned $r4GateEvents ($r4GateRoot+32) 32) ('B4-01 model directory entry was actually physically observed: '+$r4GateSeed+' '+$r4GateCase)
                    Assert-B (Test-BR4RangeReturned $r4GateEvents ($r4GateRoot+96) 32) ('B4-01 legitimate empty-file entry physically observed: '+$r4GateSeed+' '+$r4GateCase)
                    $r4GateTruthModel=if($r4GateCase -eq 'M04'){'damaged'}else{'healthy'}
                    $r4GateModelVerdict='no_alert'
                    $r4GateEmptyVerdict='no_alert'
                    if($r4GateMethod -eq 'legacy') {
                        if($r4GateModel[0].evidence -contains 'zero_size_with_nonzero_start_cluster') {$r4GateModelVerdict='warning'}
                        if($r4GateEmptyFound[0].evidence -contains 'zero_size_with_nonzero_start_cluster'){$r4GateEmptyVerdict='warning'}
                    } else {
                        if($r4GateModel[0].sizeIntegrity -eq 'unknown'){$r4GateModelVerdict='unknown'}
                        if($r4GateEmptyFound[0].sizeIntegrity -eq 'unknown'){$r4GateEmptyVerdict='unknown'}
                    }
                    Add-B4GateScore $r4GateScores $r4GateMethod $r4GateTruthModel $r4GateModelVerdict
                    Add-B4GateScore $r4GateScores $r4GateMethod 'healthy' $r4GateEmptyVerdict
                } else {
                    # X02 still holds an invented root but geometry is truncated
                    # before the scanner can *observe* any directory record.
                    Assert-B ($r4GateScan.items.Count -eq 0 -and
                        $r4GateScan.metrics.bytesRead -eq 0L -and
                        $r4GateScan.directoryPhysicalReadEvidence.streamReturnedBytes -eq 0L -and
                        $r4GateStream.ReturnedBytes -eq 1024L -and
                        $r4GateScan.status -eq 'error' -and
                        $r4GateScan.errors -contains 'directory_scan_error: Image truncated relative to BPB partition size') ('B4-01 X02 truncation before directory observation (UNKNOWN, not TN): '+$r4GateSeed+' '+$r4GateMethod)
                    Add-B4GateScore $r4GateScores $r4GateMethod 'unobserved' 'unknown'
                    Add-B4GateScore $r4GateScores $r4GateMethod 'unobserved' 'unknown'
                }
                $r4GateReturned+=[long]$r4GateStream.ReturnedBytes
                $r4GateBPhysical+=[long]$r4GateScan.directoryPhysicalReadEvidence.streamReturnedBytes
                $r4GateBComplete+=[long]$r4GateScan.metrics.bytesRead
                $r4GateCalls+=[long]$r4GateStream.Calls
                $r4GateRetained[$r4GateMethod]+=[long]$r4GateScan.items.Count
                $r4GateNoOriginalClaims+=[long]$r4GateGraph.metrics.probableEdgeAssertions
                # The R2 base corpus contains no established parent-child
                # assertions. Its edge unit is UNKNOWN (not a negative);
                # the independent 12-unit edge matrix is in #136.
                $r4GateUnobservedEdgeUnits++
                [void]$r4GateLines.Add(('{0}/{1}/{2}: model={3} empty={4} observedRoot={5} returned={6}B, UNKNOWN parent edge' -f
                    $r4GateSeed,$r4GateCase,$r4GateMethod,
                    $(if($r4GateHasDirectory){$r4GateModelVerdict}else{'unknown'}),
                    $(if($r4GateHasDirectory){$r4GateEmptyVerdict}else{'unknown'}),
                    $r4GateHasDirectory,$r4GateStream.ReturnedBytes))
            } finally {$r4GateStream.Dispose()}
            Assert-B ((Get-A3DSha256 $r4GateImage) -ceq $r4GateSourceSha) ('B4-01 full synthetic source SHA preserved: '+$r4GateSeed+' '+$r4GateCase+' '+$r4GateMethod)
        }
    }
}
Assert-B (@($r4GateDistinctSeedHashes|Select-Object -Unique).Count -eq 3) 'B4-01 three distinct invented clean seed hashes'
Assert-B ($r4GateScores.legacy.TP -eq 3 -and $r4GateScores.legacy.FP -eq 9 -and
    $r4GateScores.legacy.FN -eq 0 -and $r4GateScores.legacy.TN -eq 6 -and
    $r4GateScores.legacy.UNKNOWN -eq 6 -and
    $r4GateScores.conservative.TP -eq 0 -and $r4GateScores.conservative.FP -eq 0 -and
    $r4GateScores.conservative.FN -eq 0 -and $r4GateScores.conservative.TN -eq 6 -and
    $r4GateScores.conservative.UNKNOWN -eq 18 -and
    $r4GateScores.conservative.UnknownDamaged -eq 3 -and
    $r4GateScores.conservative.UnknownHealthy -eq 9) 'B4-01 24 units/arm, explicit damaged/healthy abstention and X02 unknown'
Assert-B ($r4GateReturned -eq 33792L -and $r4GateBPhysical -eq 9216L -and
    $r4GateBComplete -eq 9216L -and $r4GateCalls -eq 396L -and
    $r4GateRetained.legacy -eq 36L -and $r4GateRetained.conservative -eq 36L -and
    $r4GateUnobservedEdgeUnits -eq 24L -and $r4GateNoOriginalClaims -eq 0L) 'B4-01 actual 33792B physical source/9216B directory, 396 Read calls, 72 retained candidate instances'
foreach($r4GateLine in $r4GateLines){Write-Host ('B4-01 MATRIX: '+$r4GateLine)}
Write-Host ('B4-01 SYNTHETIC: 3 seeds x M00/M01/M04/X02, 24 size units per arm; legacy TP={0} FP={1} FN={2} TN={3} UNKNOWN={4}; conservative TP={5} FP={6} FN={7} TN={8} UNKNOWN={9} (damaged={10}, healthy={11}, X02=6); actual returned={12}B directoryReturned={13}B completed={14}B calls={15}; retained legacy={16} conservative={17}; base-corpus edge UNKNOWN={18}, no false original paths, source unchanged; distinct parent-edge matrix #136 TP3 FP0 FN0 TN3 UNKNOWN6' -f
    $r4GateScores.legacy.TP,$r4GateScores.legacy.FP,$r4GateScores.legacy.FN,$r4GateScores.legacy.TN,$r4GateScores.legacy.UNKNOWN,
    $r4GateScores.conservative.TP,$r4GateScores.conservative.FP,$r4GateScores.conservative.FN,$r4GateScores.conservative.TN,
    $r4GateScores.conservative.UNKNOWN,$r4GateScores.conservative.UnknownDamaged,$r4GateScores.conservative.UnknownHealthy,
    $r4GateReturned,$r4GateBPhysical,$r4GateBComplete,$r4GateCalls,$r4GateRetained.legacy,$r4GateRetained.conservative,
    $r4GateUnobservedEdgeUnits)
