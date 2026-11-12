#requires -Version 5.1
# Team B R4: synthetic-only LFN and parent-edge evidence under partial reads.
# R0/R1 are frozen in Issue #71, comment 6823207942 BEFORE this test.
# Truth belongs solely to test-side scorer; scanner receives only readonly bytes.

function Add-R4ParentLfnScore {
    param([hashtable]$Counts,[string]$Arm,[string]$Truth,[bool]$CalledPositive)
    if ($Truth -eq 'unknown') {
        $Counts[$Arm].UNKNOWN++
    } elseif ($Truth -eq 'supported') {
        if ($CalledPositive) { $Counts[$Arm].TP++ }
        else { $Counts[$Arm].FN++ }
    } elseif ($Truth -eq 'unsupported') {
        if ($CalledPositive) { $Counts[$Arm].FP++ }
        else { $Counts[$Arm].TN++ }
    } else { throw 'R4 Q unregistered oracle truth label' }
}

$r4QSeeds=@(202611,202612,202613)
$r4QArms=@('naive','bounded')
$r4QNameScores=@{
    naive=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0}
    bounded=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0}
}
$r4QParentScores=@{
    naive=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0}
    bounded=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0}
}
$r4QCompletedBytes=0L
$r4QReturnedBytes=0L
$r4QOuterSourceBytes=0L
$r4QReadCalls=0L
$r4QRetained=0L
$r4QFalseProbableOriginalPaths=0L
$r4QForgedApparentProbable=0L
$r4QForgedDisagreements=0L
$r4QMillis=@{naive=0L;bounded=0L}
$r4QMemoryDelta=@{naive=0L;bounded=0L}
$r4QSeedHashes=New-Object System.Collections.ArrayList

foreach($r4QSeed in $r4QSeeds){
    $r4QBase=New-ChappyA3DDamagedFixture -Case M00 -Seed $r4QSeed
    $r4QLayout=(New-ChappyA3DCleanFixture -Seed $r4QSeed).layout
    [byte[]]$r4QOriginal=[byte[]]$r4QBase.image.Clone()
    $r4QRoot=[int]$r4QLayout.rootOffsetBytes
    if($r4QRoot -ne 57856 -or $r4QRoot+2560 -ge $r4QOriginal.Length -or
        $r4QOriginal[$r4QRoot+96] -ne 0 -or
        $r4QOriginal[$r4QRoot+128] -ne 0 -or
        $r4QOriginal[$r4QRoot+160] -ne 0 -or
        $r4QOriginal[$r4QRoot+192] -ne 0) {
        throw 'R4 Q generated 2MiB root layout / four empty slots changed'
    }
    [void]$r4QSeedHashes.Add((Get-A3DSha256 $r4QOriginal))
    $r4QScenarios=@(
       [pscustomobject]@{id='valid_lfn_child_observed';nameTruth='supported';parentTruth='supported';budget=2560L;fault='none';deleted=$false},
       [pscustomobject]@{id='bad_checksum_child_observed';nameTruth='unsupported';parentTruth='supported';budget=2560L;fault='checksum';deleted=$false},
       [pscustomobject]@{id='deleted_between_lfn_and_link';nameTruth='unsupported';parentTruth='supported';budget=2560L;fault='interleaved';deleted=$true},
       [pscustomobject]@{id='duplicate_same_parent_link';nameTruth='supported';parentTruth='unsupported';budget=2560L;fault='duplicate';deleted=$false},
       [pscustomobject]@{id='child_unobserved_due_budget';nameTruth='supported';parentTruth='unknown';budget=512L;fault='unobserved';deleted=$false},
       [pscustomobject]@{id='child_conflicting_dotdot';nameTruth='supported';parentTruth='unsupported';budget=2560L;fault='hint_conflict';deleted=$false},
       [pscustomobject]@{id='short_EOF_on_second_block';nameTruth='supported';parentTruth='unknown';budget=2560L;fault='short_second';deleted=$false}
    )
    foreach($r4QCase in $r4QScenarios){
        # This is generated-only test construction, not production mutation.
        [byte[]]$r4QImage=[byte[]]$r4QOriginal.Clone()
        [byte[]]$r4QShort=New-ShortB 'CHILD6  DIR' 0x10 6 0
        $r4QLfns=New-LfnB 'artificial-parent-six' $r4QShort
        if($r4QLfns.Count -ne 2){throw 'R4 Q expected exactly two artificial LFN slots'}
        [Array]::Copy([byte[]]$r4QLfns[0],0,$r4QImage,($r4QRoot+96),32)
        [Array]::Copy([byte[]]$r4QLfns[1],0,$r4QImage,($r4QRoot+128),32)
        if($r4QCase.fault -eq 'checksum'){
            $r4QImage[$r4QRoot+96+13]=[byte](($r4QImage[$r4QRoot+96+13]+1) -band 255)
        }
        $r4QShortSlot=160
        if($r4QCase.fault -eq 'interleaved'){
            [byte[]]$r4QDeletedEntry=New-ShortB 'DELETE  TXT' 0x20 28 9
            $r4QDeletedEntry[0]=0xE5
            [Array]::Copy($r4QDeletedEntry,0,$r4QImage,($r4QRoot+160),32)
            $r4QShortSlot=192
        }
        [Array]::Copy($r4QShort,0,$r4QImage,($r4QRoot+$r4QShortSlot),32)
        if($r4QCase.fault -eq 'duplicate'){
            [byte[]]$r4QDuplicate=New-ShortB 'CHILD6~1DIR' 0x10 6 0
            [Array]::Copy($r4QDuplicate,0,$r4QImage,($r4QRoot+192),32)
        }

        # Artificial child cluster6 has ordered dot/dotdot; no FAT consulted.
        [byte[]]$r4QChild=New-Object byte[] 512
        [byte[]]$r4QDot=New-ShortB '.          ' 0x10 6 0
        $r4QParentHint=if($r4QCase.fault -eq 'hint_conflict'){9}else{2}
        [byte[]]$r4QDotDot=New-ShortB '..         ' 0x10 $r4QParentHint 0
        [Array]::Copy($r4QDot,0,$r4QChild,0,32)
        [Array]::Copy($r4QDotDot,0,$r4QChild,32,32)
        [byte[]]$r4QChildFile=New-ShortB 'SYNTH   TXT' 0x20 30 19
        [Array]::Copy($r4QChildFile,0,$r4QChild,64,32)
        [Array]::Copy($r4QChild,0,$r4QImage,($r4QRoot+2048),512)

        # Freeze the produced source bytes for both analyses.
        $r4QBefore=Get-A3DSha256 $r4QImage
        $r4QScans=@{}
        $r4QGraphs=@{}
        foreach($r4QArm in $r4QArms){
            # The existing test-only tracer intentionally returns 17 then EOF
            # on the SECOND directory block; the root must finish successfully.
            $r4QStop=if($r4QCase.fault -eq 'short_second'){17}else{-1}
            $r4QStream=[ChappyBR4Physical.TracedSyntheticReadStream]::new(
                $r4QImage,[long]($r4QRoot+512),512,$r4QStop,
                [long]$r4QRoot,2560)
            try {
                $r4QArgs=@{
                    Stream=$r4QStream;MaxScanBytes=$r4QCase.budget;
                    MaxCandidates=32;MaxDirectories=16;
                    MaxDirectoryReadSpans=8;RecordDirectoryReadSpans=$true;
                    ClassifyIncompleteDirectoryReadOrigin=$true;
                    RecordDirectoryPhysicalReadBytes=$true;
                    RecordClusterCoverage=$true;
                    IncludeDeleted=$r4QCase.deleted
                }
                $r4QBeforeMem=[GC]::GetTotalMemory($false)
                $r4QTime=[Diagnostics.Stopwatch]::StartNew()
                $r4QScan=Get-ChappyDirectoryCandidates @r4QArgs
                $r4QGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4QScan -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
                $r4QTime.Stop()
                $r4QMillis[$r4QArm]+=[long]$r4QTime.ElapsedMilliseconds
                $r4QMemoryDelta[$r4QArm]+=[long]([GC]::GetTotalMemory($false)-$r4QBeforeMem)
                $r4QScans[$r4QArm]=$r4QScan
                $r4QGraphs[$r4QArm]=$r4QGraph
                $r4QCompletedBytes += [long]$r4QScan.metrics.bytesRead
                $r4QReturnedBytes += [long]$r4QScan.directoryPhysicalReadEvidence.streamReturnedBytes
                $r4QOuterSourceBytes += [long]$r4QStream.AllSourceReturnedBytes
                $r4QReadCalls += [long]$r4QScan.directoryPhysicalReadEvidence.readCalls
                $r4QRetained += [long]$r4QScan.items.Count
                $r4QFalseProbableOriginalPaths += [long]$r4QGraph.metrics.probableEdgeAssertions
                Assert-B (-not $r4QStream.CanWrite -and
                    $r4QScan.scanIncomplete -and $r4QGraph.scanIncomplete -and
                    $r4QGraph.metrics.probableEdgeAssertions -eq 0 -and
                    $r4QStream.DirectorySourceReturnedBytes -eq $r4QScan.directoryPhysicalReadEvidence.streamReturnedBytes -and
                    $r4QScan.directoryPhysicalReadEvidence.completedClusterBytes -eq $r4QScan.metrics.bytesRead -and
                    $r4QStream.AllSourceReturnedBytes -ge $r4QStream.DirectorySourceReturnedBytes -and
                    @($r4QScan.items|Where-Object{$null -ne $_.name -or $null -ne $_.shortName}).Count -eq 0) ('R4 Q readonly partial, named metadata redacted, no probable original path: '+$r4QSeed+' '+$r4QCase.id+' '+$r4QArm)
                if($r4QCase.fault -eq 'short_second'){
                    Assert-B ($r4QScan.status -eq 'error' -and
                        $r4QScan.metrics.bytesRead -eq 512 -and
                        $r4QScan.directoryPhysicalReadEvidence.streamReturnedBytes -eq 529 -and
                        $r4QScan.directoryPhysicalReadEvidence.incompleteClusterReturnedBytes -eq 17 -and
                        $r4QScan.directoryReadEvidence.status -eq 'scan_error' -and
                        $r4QScan.directoryReadEvidence.readEvents -eq 1) ('R4 Q second directory block returned 17B then EOF: '+$r4QSeed+' '+$r4QArm)
                } elseif($r4QCase.fault -eq 'unobserved'){
                    Assert-B ($r4QScan.metrics.bytesRead -eq 512 -and
                        $r4QScan.directoryReadEvidence.status -eq 'scan_incomplete' -and
                        $r4QScan.directoryReadEvidence.readEvents -eq 1) ('R4 Q root read but child6 budget-unobserved: '+$r4QSeed+' '+$r4QArm)
                } else {
                    Assert-B ($r4QScan.metrics.bytesRead -eq 2560 -and
                        $r4QScan.directoryPhysicalReadEvidence.streamReturnedBytes -eq 2560 -and
                        $r4QScan.directoryReadEvidence.readEvents -eq 5 -and
                        $r4QScan.directoryReadEvidence.status -eq 'scan_incomplete') ('R4 Q bounded root and four subsequent directory blocks: '+$r4QSeed+' '+$r4QCase.id+' '+$r4QArm)
                }
            } finally { $r4QStream.Dispose() }
            Assert-B ((Get-A3DSha256 $r4QImage) -ceq $r4QBefore) ('R4 Q generated SHA unchanged: '+$r4QSeed+' '+$r4QCase.id+' '+$r4QArm)
        }
        # Same source/budgets/scan flags were applied to naive and guarded
        # scorer. No production code or A/C/D source was changed.
        $r4QNaiveScan=$r4QScans.naive
        $r4QGuardScan=$r4QScans.bounded
        $r4QGuardGraph=$r4QGraphs.bounded
        Assert-B ((ConvertTo-Json -InputObject $r4QNaiveScan -Depth 8 -Compress) -ceq
            (ConvertTo-Json -InputObject $r4QGuardScan -Depth 8 -Compress) -and
            (ConvertTo-Json -InputObject $r4QGraphs.naive -Depth 8 -Compress) -ceq
            (ConvertTo-Json -InputObject $r4QGuardGraph -Depth 8 -Compress)) ('R4 Q unchanged two-arm read/candidate/graph results: '+$r4QSeed+' '+$r4QCase.id)

        $r4QLinkItems=@($r4QGuardScan.items|Where-Object {
            $_.isDirectory -and -not $_.deleted -and $_.containerCluster -eq 2 -and $_.startCluster -eq 6
        })
        $r4QExpectedCount=if($r4QCase.fault -eq 'duplicate'){2}else{1}
        Assert-B ($r4QLinkItems.Count -eq $r4QExpectedCount) ('R4 Q existing root directory candidates retained: '+$r4QSeed+' '+$r4QCase.id)
        $r4QFirstLink=@($r4QLinkItems|Where-Object{$_.offsetBytes -eq ($r4QRoot+$r4QShortSlot)})
        Assert-B ($r4QFirstLink.Count -eq 1 -and
            @($r4QGuardScan.items|Where-Object{$_.deleted}).Count -eq $(if($r4QCase.deleted){1}else{0})) ('R4 Q target link and optional deleted interleaving retained: '+$r4QSeed+' '+$r4QCase.id)
        $r4QLink=$r4QFirstLink[0]
        Assert-B ($r4QLink.nameSource -eq $(if($r4QCase.nameTruth -eq 'supported'){'lfn_validated'}else{'short_8_3'}) -and
            $r4QLink.confidence -ne 'verified') ('R4 Q LFN checksum/adjacency association without original-name guarantee: '+$r4QSeed+' '+$r4QCase.id)
        $r4QNaiveName=($r4QImage[$r4QRoot+96+11] -eq 0x0F -and
                       $r4QImage[$r4QRoot+128+11] -eq 0x0F)
        $r4QGuardName=($r4QLink.nameSource -eq 'lfn_validated')
        Add-R4ParentLfnScore -Counts $r4QNameScores -Arm 'naive' -Truth $r4QCase.nameTruth -CalledPositive $r4QNaiveName
        Add-R4ParentLfnScore -Counts $r4QNameScores -Arm 'bounded' -Truth $r4QCase.nameTruth -CalledPositive $r4QGuardName

        $r4QNaiveParent=($r4QLinkItems.Count -gt 0)
        $r4QEdges=@($r4QGuardGraph.edges|Where-Object{$_.parentCluster -eq 2 -and $_.childCluster -eq 6})
        $r4QGuardParent=($r4QEdges.Count -eq 1 -and
                         $r4QEdges[0].relationStatus -eq 'parent_hint_corroborated' -and
                         $r4QGuardGraph.metrics.probableEdgeAssertions -eq 0)
        Add-R4ParentLfnScore -Counts $r4QParentScores -Arm 'naive' -Truth $r4QCase.parentTruth -CalledPositive $r4QNaiveParent
        Add-R4ParentLfnScore -Counts $r4QParentScores -Arm 'bounded' -Truth $r4QCase.parentTruth -CalledPositive $r4QGuardParent

        if($r4QCase.parentTruth -eq 'unknown'){
            Assert-B ($r4QEdges.Count -eq 0 -and
                $r4QGuardGraph.metrics.unresolvedTargetReferences -eq 1 -and
                $r4QGuardGraph.nodes.Count -eq 1) ('R4 Q truly unobserved child6 is UNKNOWN, not TN: '+$r4QSeed+' '+$r4QCase.id)
        } elseif($r4QCase.parentTruth -eq 'unsupported'){
            Assert-B ($r4QEdges.Count -eq $r4QExpectedCount -and
                @($r4QEdges|Where-Object{$_.relationStatus -eq 'parent_hint_corroborated'}).Count -eq 0) ('R4 Q duplicate or conflicting parent edge remains unsupported: '+$r4QSeed+' '+$r4QCase.id)
        } else {
            Assert-B ($r4QEdges.Count -eq 1 -and $r4QGuardParent -and
                $r4QEdges[0].confidence -eq 'partial') ('R4 Q corroborated structural parent is only partial candidate: '+$r4QSeed+' '+$r4QCase.id)
        }

        if($r4QCase.id -eq 'valid_lfn_child_observed'){
            # The caller can forge B's report: this is NOT an authenticated
            # physical read receipt. Measure susceptibility without endorsing.
            $r4QForged=$r4QGuardScan|ConvertTo-Json -Depth 10 -Compress|ConvertFrom-Json
            $r4QForged.scanIncomplete=$false
            $r4QForged.metrics.bytesRead=[long]$r4QForged.geometry.clusterCount*[long]$r4QForged.geometry.clusterSizeBytes
            $r4QForged.coverageProvenance.status='recorded'
            $r4QForged.coverageProvenance.source='scanner_read_events_v1'
            $r4QForged.coverageProvenance.uniqueClusters=[long]$r4QForged.geometry.clusterCount
            $r4QForged.coverageProvenance.readEvents=[long]$r4QForged.geometry.clusterCount
            $r4QForged.coverageProvenance.duplicateReadEvents=0L
            $r4QForged.coverageProvenance.intervals=@([pscustomobject]@{firstCluster=2L;lastCluster=[long]$r4QForged.geometry.maxCluster})
            $r4QGraphForged=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4QForged -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
            $r4QForgedApparent=[long]$r4QGraphForged.metrics.probableEdgeAssertions
            $r4QForgedApparentProbable+=$r4QForgedApparent
            # The independent source meter refutes the claimed full-volume
            # read even if the self-reported graph accepts this fake ledger.
            if($r4QForged.metrics.bytesRead -gt $r4QGuardScan.directoryPhysicalReadEvidence.streamReturnedBytes){
                $r4QForgedDisagreements++
            }
            Assert-B ($r4QForgedDisagreements -gt 0 -and
                $r4QGraphForged.metrics.edgeAssertions -eq 1 -and
                $r4QGuardGraph.metrics.probableEdgeAssertions -eq 0 -and
                $r4QForged.metrics.bytesRead -gt $r4QGuardScan.directoryPhysicalReadEvidence.streamReturnedBytes) ('R4 Q forged full-volume counters conflict with independent observed source bytes: '+$r4QSeed)
        }
    }
}
$r4QLNaive=$r4QNameScores.naive
$r4QLGuard=$r4QNameScores.bounded
$r4QPNaive=$r4QParentScores.naive
$r4QPGuard=$r4QParentScores.bounded
Assert-B ($r4QLNaive.TP -eq 15 -and $r4QLNaive.FP -eq 6 -and $r4QLNaive.FN -eq 0 -and $r4QLNaive.TN -eq 0 -and
    $r4QLGuard.TP -eq 15 -and $r4QLGuard.FP -eq 0 -and $r4QLGuard.FN -eq 0 -and $r4QLGuard.TN -eq 6) 'R4 Q 21 LFN association units: naive TP15 FP6 FN0 TN0 vs checksum+adjacency TP15 FP0 FN0 TN6'
Assert-B ($r4QPNaive.TP -eq 9 -and $r4QPNaive.FP -eq 6 -and $r4QPNaive.FN -eq 0 -and $r4QPNaive.TN -eq 0 -and $r4QPNaive.UNKNOWN -eq 6 -and
    $r4QPGuard.TP -eq 9 -and $r4QPGuard.FP -eq 0 -and $r4QPGuard.FN -eq 0 -and $r4QPGuard.TN -eq 6 -and $r4QPGuard.UNKNOWN -eq 6) 'R4 Q 21 parent relation units: naive TP9 FP6 FN0 TN0 UNKNOWN6 vs corroborated partial TP9 FP0 FN0 TN6 UNKNOWN6'
Assert-B ($r4QCompletedBytes -eq 82944L -and
    $r4QReturnedBytes -eq 83046L -and
    ($r4QReturnedBytes - $r4QCompletedBytes) -eq 102L -and
    $r4QFalseProbableOriginalPaths -eq 0L -and
    $r4QForgedDisagreements -eq 3) 'R4 Q three-seed 82944B complete plus 102B partial; no actual probable original paths; forged source claims detected'
Assert-B (@($r4QSeedHashes|Select-Object -Unique).Count -eq 3) 'R4 Q three generated seed images have distinct synthetic SHA'
Write-Host ('SYNTHETIC B R4 Q LFN/PARENT ONLY: seeds=3 cases=21; LFN naive TP={0} FP={1} FN={2} TN={3}; LFN guarded TP={4} FP={5} FN={6} TN={7}; parent naive TP={8} FP={9} FN={10} TN={11} UNKNOWN={12}; parent guarded TP={13} FP={14} FN={15} TN={16} UNKNOWN={17}; B completed={18} returned={19} partial={20}, actual source returns incl geometry={21}, B Read calls={22}; retained across same-corpus scans={23}; false actual probable original paths={24}; forged-coverage apparent probable={25}, forged independently disagreed={26}; elapsed-ms naive={27} guarded={28}; approx-GC-delta naive={29} guarded={30}; no verified original name/path' -f
    $r4QLNaive.TP,$r4QLNaive.FP,$r4QLNaive.FN,$r4QLNaive.TN,
    $r4QLGuard.TP,$r4QLGuard.FP,$r4QLGuard.FN,$r4QLGuard.TN,
    $r4QPNaive.TP,$r4QPNaive.FP,$r4QPNaive.FN,$r4QPNaive.TN,$r4QPNaive.UNKNOWN,
    $r4QPGuard.TP,$r4QPGuard.FP,$r4QPGuard.FN,$r4QPGuard.TN,$r4QPGuard.UNKNOWN,
    $r4QCompletedBytes,$r4QReturnedBytes,($r4QReturnedBytes-$r4QCompletedBytes),
    $r4QOuterSourceBytes,$r4QReadCalls,$r4QRetained,$r4QFalseProbableOriginalPaths,
    $r4QForgedApparentProbable,$r4QForgedDisagreements,
    $r4QMillis.naive,$r4QMillis.bounded,$r4QMemoryDelta.naive,$r4QMemoryDelta.bounded)
