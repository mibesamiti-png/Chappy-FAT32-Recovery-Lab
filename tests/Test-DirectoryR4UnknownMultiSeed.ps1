#requires -Version 5.1
# B R4 research-only multi-seed UNKNOWN calibration. Synthetic sources ONLY.
# The scorer's actual file-size truth does not reach the directory scanner.
# Depends on the existing B synthetic tests' generated fixture/trace helpers.

function Add-R4ZScore {
    param([hashtable]$Scores,[string]$Arm,[bool]$Damaged,[string]$Verdict)
    if ($Verdict -eq 'unknown') {
        $Scores[$Arm].UNKNOWN++
        if ($Damaged) { $Scores[$Arm].UNKNOWN_DAMAGED++ }
        else { $Scores[$Arm].UNKNOWN_HEALTHY++ }
    } elseif ($Verdict -eq 'damage') {
        if ($Damaged) { $Scores[$Arm].TP++ } else { $Scores[$Arm].FP++ }
    } elseif ($Verdict -eq 'no_alert') {
        if ($Damaged) { $Scores[$Arm].FN++ } else { $Scores[$Arm].TN++ }
    } else {
        throw 'R4 Z invalid synthetic scorer classification'
    }
}

$r4ZSeeds=@(202611,202612,202613)
$r4ZArms=@('legacy','conservative')
$r4ZScores=@{
    legacy=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0;UNKNOWN_DAMAGED=0;UNKNOWN_HEALTHY=0}
    conservative=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0;UNKNOWN_DAMAGED=0;UNKNOWN_HEALTHY=0}
}
$r4ZCompletedBytes=0L
$r4ZReturnedDirectoryBytes=0L
$r4ZReturnedAllSourceBytes=0L
$r4ZReadCalls=0L
$r4ZUnknownControls=0
$r4ZFalseProbablePaths=0
$r4ZRetained=0
$r4ZTimings=@{legacy=0L;conservative=0L}
$r4ZSeedSourceHashes=New-Object System.Collections.ArrayList

foreach($r4ZSeed in $r4ZSeeds) {
    $r4ZLayout=(New-ChappyA3DCleanFixture -Seed $r4ZSeed).layout
    $r4ZRoot=[int]$r4ZLayout.rootOffsetBytes
    $r4ZClean=New-ChappyA3DDamagedFixture -Case M00 -Seed $r4ZSeed
    $r4ZBroken=New-ChappyA3DDamagedFixture -Case M04 -Seed $r4ZSeed
    $r4ZBadLfn=New-ChappyA3DDamagedFixture -Case M04L -Seed $r4ZSeed
    [byte[]]$r4ZGood=[byte[]]$r4ZClean.image.Clone()
    [byte[]]$r4ZDamaged=[byte[]]$r4ZBroken.image.Clone()
    [byte[]]$r4ZTwin=[byte[]]$r4ZDamaged.Clone()
    [byte[]]$r4ZLfn=[byte[]]$r4ZBadLfn.image.Clone()
    [byte[]]$r4ZDeleted=[byte[]]$r4ZDamaged.Clone()

    # Add two distinctly labelled genuine empty files in unused generated
    # slots. This is TEST oracle construction, never scanner input truth.
    if($r4ZGood[$r4ZRoot+96] -ne 0 -or
       $r4ZGood[$r4ZRoot+128] -ne 0 -or
       $r4ZGood[$r4ZRoot+160] -ne 0) {
        throw 'R4 Z seed has unexpectedly occupied synthetic empty slots'
    }
    [byte[]]$r4ZZero=New-ShortB 'EMPTY0  TXT' 0x20 0 0
    [byte[]]$r4ZNine=New-ShortB 'EMPTY9  TXT' 0x20 9 0
    [Array]::Copy($r4ZZero,0,$r4ZGood,($r4ZRoot+96),32)
    [Array]::Copy($r4ZNine,0,$r4ZGood,($r4ZRoot+128),32)
    foreach($r4ZFatStart in @([int]$r4ZLayout.fat1OffsetBytes,
                               [int]$r4ZLayout.fat2OffsetBytes)) {
        $r4ZNineEntry=$r4ZFatStart+9*4
        if([BitConverter]::ToUInt32($r4ZGood,$r4ZNineEntry) -ne 0) {
            throw 'R4 Z allocated-empty synthetic FAT slot unexpectedly in use'
        }
        [Array]::Copy([BitConverter]::GetBytes([uint32]0x0FFFFFFF),0,
                      $r4ZGood,$r4ZNineEntry,4)
    }

    # Paired observation-equivalent file: directory says size=0/start=4 on
    # both, but the scorer changes ONLY unscanned synthetic FAT/payload truth.
    $r4ZModelAt=$r4ZRoot+1024
    [Array]::Clear($r4ZTwin,$r4ZModelAt,1024)
    foreach($r4ZFatStart in @([int]$r4ZLayout.fat1OffsetBytes,
                               [int]$r4ZLayout.fat2OffsetBytes)) {
        [Array]::Copy([BitConverter]::GetBytes([uint32]0x0FFFFFFF),0,
                      $r4ZTwin,($r4ZFatStart+4*4),4)
        [Array]::Clear($r4ZTwin,($r4ZFatStart+5*4),4)
    }
    Assert-B ((Get-A3DSha256 $r4ZDamaged) -cne (Get-A3DSha256 $r4ZTwin)) ('R4 Z distinct truth sources for seed '+$r4ZSeed)
    $r4ZObservedMismatch=0
    for($r4ZIndex=0;$r4ZIndex -lt 1024;$r4ZIndex++){
        if($r4ZDamaged[$r4ZRoot+$r4ZIndex] -ne $r4ZTwin[$r4ZRoot+$r4ZIndex]){
            $r4ZObservedMismatch++
        }
    }
    Assert-B ($r4ZObservedMismatch -eq 0) ('R4 Z metadata-identical damaged/healthy synthetic twins seed '+$r4ZSeed)

    $r4ZDeletedAt=[int]$r4ZBroken.manifest.changes[0].offsetBytes-28
    if($r4ZDeletedAt -lt $r4ZRoot -or $r4ZDeletedAt -ge $r4ZRoot+512){
        throw 'R4 Z deleted synthetic entry outside root'
    }
    $r4ZDeleted[$r4ZDeletedAt]=0xE5
    [byte[]]$r4ZParent=[byte[]]$r4ZGood.Clone()
    [byte[]]$r4ZParentEntry=New-ShortB 'ORPHAN  DIR' 0x10 27 0
    [Array]::Copy($r4ZParentEntry,0,$r4ZParent,($r4ZRoot+160),32)
    [void]$r4ZSeedSourceHashes.Add((Get-A3DSha256 $r4ZGood))

    $r4ZCases=@(
       [pscustomobject]@{id='legitimate_empty_0_9';image=$r4ZGood;deleted=$false;kind='normal';spanCap=8},
       [pscustomobject]@{id='M04_damaged_size';image=$r4ZDamaged;deleted=$false;kind='normal';spanCap=8},
       [pscustomobject]@{id='M04_healthy_twin';image=$r4ZTwin;deleted=$false;kind='normal';spanCap=8},
       [pscustomobject]@{id='M04L_invalid_lfn';image=$r4ZLfn;deleted=$false;kind='normal';spanCap=8},
       [pscustomobject]@{id='M04_deleted';image=$r4ZDeleted;deleted=$true;kind='normal';spanCap=8},
       [pscustomobject]@{id='false_parent_span_cap';image=$r4ZParent;deleted=$false;kind='normal';spanCap=1},
       [pscustomobject]@{id='short_root_17_then_EOF';image=$r4ZGood;deleted=$false;kind='short';spanCap=8},
       [pscustomobject]@{id='X02_truncated_no_directory';image=[byte[]](New-ChappyA3DDamagedFixture -Case X02 -Seed $r4ZSeed).image;deleted=$false;kind='truncated';spanCap=8}
    )
    $r4ZPairReports=@{}
    $r4ZPairTraces=@{}
    foreach($r4ZCase in $r4ZCases){
        [byte[]]$r4ZBytes=$r4ZCase.image
        $r4ZBefore=Get-A3DSha256 $r4ZBytes
        $r4ZResults=@{}
        foreach($r4ZArm in $r4ZArms){
            # Only the EOF case limits root Read to 17 bytes. The wrapper
            # independently records actual positive returned source bytes.
            if($r4ZCase.kind -eq 'short'){
                $r4ZStream=[ChappyBR4Physical.TracedSyntheticReadStream]::new(
                    $r4ZBytes,[long]$r4ZRoot,17,17,[long]$r4ZRoot,1024)
            } else {
                $r4ZStream=[ChappyBR4Identifiability.ArtificialReadTrace]::new($r4ZBytes)
            }
            try {
                $r4ZParams=@{
                    Stream=$r4ZStream;MaxScanBytes=1024L;MaxCandidates=32;MaxDirectories=16;
                    RecordDirectoryReadSpans=$true;ClassifyIncompleteDirectoryReadOrigin=$true;
                    RecordDirectoryPhysicalReadBytes=$true;MaxDirectoryReadSpans=$r4ZCase.spanCap;
                    IncludeDeleted=$r4ZCase.deleted
                }
                if($r4ZArm -eq 'legacy'){
                    $r4ZParams.ExperimentalFlagZeroSizeNonzeroStartCluster=$true
                } else {
                    $r4ZParams.ExperimentalConservativeZeroSizeUnknown=$true
                }
                $r4ZTimer=[Diagnostics.Stopwatch]::StartNew()
                $r4ZResult=Get-ChappyDirectoryCandidates @r4ZParams
                $r4ZTimer.Stop();$r4ZTimings[$r4ZArm]+=$r4ZTimer.ElapsedMilliseconds
                $r4ZResults[$r4ZArm]=$r4ZResult
                $r4ZP=$r4ZResult.directoryPhysicalReadEvidence
                $r4ZCompletedBytes += [long]$r4ZResult.metrics.bytesRead
                $r4ZReturnedDirectoryBytes += [long]$r4ZP.streamReturnedBytes
                $r4ZReturnedAllSourceBytes += [long]$r4ZStream.AllSourceReturnedBytes
                $r4ZReadCalls += [long]$r4ZP.readCalls
                $r4ZRetained += $r4ZResult.items.Count
                Assert-B (-not $r4ZStream.CanWrite -and
                    $r4ZResult.scanIncomplete -and
                    $r4ZP.completedClusterBytes -eq $r4ZResult.metrics.bytesRead -and
                    $r4ZP.streamReturnedBytes -ge $r4ZP.completedClusterBytes -and
                    $r4ZStream.AllSourceReturnedBytes -ge $r4ZP.streamReturnedBytes -and
                    @($r4ZResult.items|Where-Object{$null -ne $_.name -or $null -ne $_.shortName}).Count -eq 0) ('R4 Z bounded readonly redacted input/source accounting: '+$r4ZSeed+' '+$r4ZCase.id+' '+$r4ZArm)
                if($r4ZCase.kind -eq 'normal'){
                    Assert-B ($r4ZResult.status -eq 'partial' -and
                        $r4ZResult.metrics.bytesRead -eq 1024 -and
                        $r4ZP.streamReturnedBytes -eq 1024 -and
                        $r4ZResult.directoryReadEvidence.readEvents -eq 2 -and
                        $r4ZResult.directoryReadEvidence.recordedSpans -eq [Math]::Min(2,$r4ZCase.spanCap)) ('R4 Z two successful cluster reads under fixed caps: '+$r4ZSeed+' '+$r4ZCase.id+' '+$r4ZArm)
                    $r4ZExpectedStatus=if($r4ZCase.spanCap -eq 1){'span_limit'}else{'scan_incomplete'}
                    Assert-B ($r4ZResult.directoryReadEvidence.status -eq $r4ZExpectedStatus) ('R4 Z honest scan/span coverage: '+$r4ZSeed+' '+$r4ZCase.id+' '+$r4ZArm)
                } elseif($r4ZCase.kind -eq 'short'){
                    Assert-B ($r4ZResult.status -eq 'error' -and
                        $r4ZResult.directoryReadEvidence.status -eq 'scan_error' -and
                        $r4ZResult.directoryReadEvidence.readEvents -eq 0 -and
                        $r4ZResult.metrics.bytesRead -eq 0 -and
                        $r4ZP.streamReturnedBytes -eq 17 -and
                        $r4ZP.incompleteClusterReturnedBytes -eq 17 -and
                        $r4ZStream.DirectorySourceReturnedBytes -eq 17 -and
                        $r4ZResult.items.Count -eq 0) ('R4 Z 17-byte short root error/UNKNOWN not TN: '+$r4ZSeed+' '+$r4ZArm)
                } else {
                    Assert-B ($r4ZResult.status -eq 'error' -and
                        $r4ZResult.metrics.bytesRead -eq 0 -and
                        $r4ZP.streamReturnedBytes -eq 0 -and
                        $r4ZResult.directoryReadEvidence.status -eq 'scan_error' -and
                        $r4ZResult.items.Count -eq 0) ('R4 Z X02 geometry truncated has no observed directory: '+$r4ZSeed+' '+$r4ZArm)
                }
                if($r4ZCase.id -eq 'M04_damaged_size' -or $r4ZCase.id -eq 'M04_healthy_twin'){
                    $r4ZPairReports[$r4ZCase.id+'_'+$r4ZArm]=
                        (ConvertTo-Json -InputObject $r4ZResult -Depth 10 -Compress)
                    $r4ZPairTraces[$r4ZCase.id+'_'+$r4ZArm]=
                        [string]::Join('|',$r4ZStream.Events.ToArray())
                }
            } finally {$r4ZStream.Dispose()}
            Assert-B ((Get-A3DSha256 $r4ZBytes) -ceq $r4ZBefore) ('R4 Z unchanged source hash: '+$r4ZSeed+' '+$r4ZCase.id+' '+$r4ZArm)
        }
        $r4ZOld=$r4ZResults.legacy
        $r4ZNew=$r4ZResults.conservative
        $r4ZOldShape=@($r4ZOld.items|ForEach-Object{
            ('{0}:{1}:{2}:{3}:{4}' -f $_.offsetBytes,$_.startCluster,$_.sizeBytes,$_.isDirectory,$_.deleted)
        })
        $r4ZNewShape=@($r4ZNew.items|ForEach-Object{
            ('{0}:{1}:{2}:{3}:{4}' -f $_.offsetBytes,$_.startCluster,$_.sizeBytes,$_.isDirectory,$_.deleted)
        })
        Assert-B ($r4ZOld.items.Count -eq $r4ZNew.items.Count -and
            ([string]::Join('|',$r4ZOldShape)) -ceq ([string]::Join('|',$r4ZNewShape)) -and
            $r4ZOld.metrics.bytesRead -eq $r4ZNew.metrics.bytesRead -and
            $r4ZOld.directoryReadEvidence.status -eq $r4ZNew.directoryReadEvidence.status) ('R4 Z baseline/conservative preserve metadata and read status: '+$r4ZSeed+' '+$r4ZCase.id)

        if($r4ZCase.id -eq 'legitimate_empty_0_9' -or
           $r4ZCase.id -eq 'M04_damaged_size' -or
           $r4ZCase.id -eq 'M04_healthy_twin'){
            $r4ZTargets=if($r4ZCase.id -eq 'legitimate_empty_0_9'){
                @([pscustomobject]@{cluster=0L;damaged=$false},
                  [pscustomobject]@{cluster=9L;damaged=$false})
            } else {
                @([pscustomobject]@{cluster=4L;damaged=($r4ZCase.id -eq 'M04_damaged_size')})
            }
            foreach($r4ZTarget in $r4ZTargets) {
                foreach($r4ZArm in $r4ZArms) {
                    $r4ZItemMatches=@($r4ZResults[$r4ZArm].items|Where-Object{
                        -not $_.isDirectory -and -not $_.deleted -and
                        $_.sizeBytes -eq 0 -and $_.startCluster -eq $r4ZTarget.cluster
                    })
                    Assert-B ($r4ZItemMatches.Count -eq 1) ('R4 Z independently labelled live file observed: '+$r4ZSeed+' '+$r4ZCase.id+' '+$r4ZArm)
                    $r4ZItem=$r4ZItemMatches[0]
                    $r4ZVerdict=if($r4ZArm -eq 'legacy'){
                        if($r4ZItem.evidence -contains 'zero_size_with_nonzero_start_cluster'){'damage'}else{'no_alert'}
                    } else {
                        if($r4ZItem.sizeIntegrity -eq 'unknown'){'unknown'}else{'no_alert'}
                    }
                    Add-R4ZScore -Scores $r4ZScores -Arm $r4ZArm -Damaged ([bool]$r4ZTarget.damaged) -Verdict $r4ZVerdict
                }
            }
        } elseif($r4ZCase.id -eq 'M04L_invalid_lfn'){
            Assert-B (@($r4ZNew.items|Where-Object{
                $_.nameSource -eq 'short_8_3' -and $_.confidence -eq 'partial' -and
                $_.evidence -contains 'lfn_rejected_short_fallback'
            }).Count -eq 1) ('R4 Z invalid LFN stays partial/short alias: '+$r4ZSeed)
            $r4ZUnknownControls++
        } elseif($r4ZCase.id -eq 'M04_deleted'){
            Assert-B (@($r4ZNew.items|Where-Object{
                $_.deleted -and $_.sizeBytes -eq 0 -and $_.startCluster -ge 2
            }).Count -eq 1 -and
                @($r4ZNew.items|Where-Object{
                    $_.deleted -and $_.sizeIntegrity -eq 'unknown'
                }).Count -eq 0) ('R4 Z deleted record retained but not live-size corruption evidence: '+$r4ZSeed)
            $r4ZUnknownControls++
        } elseif($r4ZCase.id -eq 'false_parent_span_cap'){
            $r4ZGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4ZNew -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
            Assert-B ($r4ZGraph.scanIncomplete -and
                $r4ZGraph.metrics.unresolvedTargetReferences -eq 1 -and
                $r4ZGraph.metrics.probableEdgeAssertions -eq 0 -and
                @($r4ZNew.items|Where-Object{$_.isDirectory -and $_.startCluster -eq 27}).Count -eq 1) ('R4 Z fake parent retained, unobserved child not verified: '+$r4ZSeed)
            $r4ZFalseProbablePaths += [int]$r4ZGraph.metrics.probableEdgeAssertions
            # Caller can forge a report; test must never take such a claim
            # as cryptographic proof or a completed original parent link.
            $r4ZForged=$r4ZNew | ConvertTo-Json -Depth 10 -Compress | ConvertFrom-Json
            $r4ZForged.scanIncomplete=$false
            $r4ZForged.directoryReadEvidence.status='recorded'
            $r4ZForged.metrics.bytesRead=[long]$r4ZForged.geometry.clusterCount*512L
            $r4ZForged | Add-Member NoteProperty coverageProvenance ([pscustomobject]@{
                source='scanner_read_events_v1';status='recorded'
                uniqueClusters=[long]$r4ZForged.geometry.clusterCount
                readEvents=[long]$r4ZForged.geometry.clusterCount
                duplicateReadEvents=0L
                intervals=@([pscustomobject]@{firstCluster=2L;lastCluster=[long]$r4ZForged.geometry.maxCluster})
            }) -Force
            $r4ZForgedGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4ZForged -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
            Assert-B ($r4ZForgedGraph.metrics.probableEdgeAssertions -eq 0 -and
                $r4ZForgedGraph.metrics.unresolvedTargetReferences -eq 1 -and
                $r4ZForgedGraph.edges.Count -eq 0) ('R4 Z forged counters cannot create nonexistent child in this artificial graph: '+$r4ZSeed)
            $r4ZUnknownControls++
        } else {
            # A short read and X02 are unobserved, never a true negative
            # for actual file-size integrity.
            Assert-B ($r4ZNew.status -eq 'error' -and $r4ZNew.items.Count -eq 0) ('R4 Z no file-size oracle when directory unobserved: '+$r4ZSeed+' '+$r4ZCase.id)
            $r4ZUnknownControls++
        }
    }
    foreach($r4ZArm in $r4ZArms){
        Assert-B ($r4ZPairReports['M04_damaged_size_'+$r4ZArm] -ceq
            $r4ZPairReports['M04_healthy_twin_'+$r4ZArm] -and
            $r4ZPairTraces['M04_damaged_size_'+$r4ZArm] -ceq
            $r4ZPairTraces['M04_healthy_twin_'+$r4ZArm]) ('R4 Z same B observed complete source-read transcript under different oracle truth: '+$r4ZSeed+' '+$r4ZArm)
    }
}
Assert-B (@($r4ZSeedSourceHashes|Select-Object -Unique).Count -eq 3) 'R4 Z all three clean artificial seeds generate distinct source hashes'
$r4ZL=$r4ZScores.legacy
$r4ZC=$r4ZScores.conservative
Assert-B ($r4ZL.TP -eq 3 -and $r4ZL.FP -eq 6 -and $r4ZL.FN -eq 0 -and $r4ZL.TN -eq 3 -and $r4ZL.UNKNOWN -eq 0 -and
    $r4ZC.TP -eq 0 -and $r4ZC.FP -eq 0 -and $r4ZC.FN -eq 0 -and $r4ZC.TN -eq 3 -and $r4ZC.UNKNOWN -eq 9 -and
    $r4ZC.UNKNOWN_DAMAGED -eq 3 -and $r4ZC.UNKNOWN_HEALTHY -eq 6) 'R4 Z 12 independent live-record scores across 3 seeds: legacy TP3 FP6 FN0 TN3; conservative TP0 FP0 FN0 TN3 UNKNOWN9'
Assert-B ($r4ZCompletedBytes -eq 36864L -and
    $r4ZReturnedDirectoryBytes -eq 36966L -and
    ($r4ZReturnedDirectoryBytes-$r4ZCompletedBytes) -eq 102L -and
    $r4ZUnknownControls -eq 15 -and $r4ZFalseProbablePaths -eq 0) 'R4 Z 36864 completed B bytes + 102 returned partial bytes, 15 unscored controls, zero false probable paths'
Write-Host ('SYNTHETIC B R4 Z MULTISEED ONLY: seeds=3 scoredLive=12; legacy TP={0} FP={1} FN={2} TN={3} UNKNOWN={4}; conservative TP={5} FP={6} FN={7} TN={8} UNKNOWN={9} (damaged={10}, healthy={11}); unscoredControls={12}; B completed bytes={13}, returned bytes={14}, partial returned={15}; outer source bytes={16}, B Read calls={17}; kept candidates={18}, false probable original paths={19}; elapsed-ms legacy={20} conservative={21}; original identity UNKNOWN' -f
    $r4ZL.TP,$r4ZL.FP,$r4ZL.FN,$r4ZL.TN,$r4ZL.UNKNOWN,
    $r4ZC.TP,$r4ZC.FP,$r4ZC.FN,$r4ZC.TN,$r4ZC.UNKNOWN,
    $r4ZC.UNKNOWN_DAMAGED,$r4ZC.UNKNOWN_HEALTHY,
    $r4ZUnknownControls,$r4ZCompletedBytes,$r4ZReturnedDirectoryBytes,
    ($r4ZReturnedDirectoryBytes-$r4ZCompletedBytes),
    $r4ZReturnedAllSourceBytes,$r4ZReadCalls,$r4ZRetained,
    $r4ZFalseProbablePaths,$r4ZTimings.legacy,$r4ZTimings.conservative)
