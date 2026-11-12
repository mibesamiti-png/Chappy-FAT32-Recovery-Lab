#requires -Version 5.1
# Team B R4 P1: conservative unknown vs binary corruption warning, SYNTHETIC ONLY.
# Truth/labels are held by this independent test; scanner sees only bytes.

$r4WSeed = 202611
$r4WRootAt = [int]$r4NLayout.rootOffsetBytes
[byte[]]$r4WLegitimate = [byte[]]$r4NBytes.Clone()
$r4WM04 = New-ChappyA3DDamagedFixture -Case M04 -Seed $r4WSeed
$r4WM04L = New-ChappyA3DDamagedFixture -Case M04L -Seed $r4WSeed
[byte[]]$r4WDamaged = [byte[]]$r4WM04.image.Clone()
[byte[]]$r4WLfn = [byte[]]$r4WM04L.image.Clone()
[byte[]]$r4WDeleted = [byte[]]$r4WDamaged.Clone()
$r4WDeletedEntryAt = [int]$r4WM04.manifest.changes[0].offsetBytes - 28
if ($r4WDeletedEntryAt -lt $r4WRootAt -or
    $r4WDeletedEntryAt -ge ($r4WRootAt + 512)) {
    throw 'R4 W synthetic deleted-record offset not in generated root'
}
$r4WDeleted[$r4WDeletedEntryAt] = 0xE5

[byte[]]$r4WFalseParent = [byte[]]$r4WLegitimate.Clone()
if ($r4WFalseParent[$r4WRootAt+160] -ne 0) {
    throw 'R4 W fake-parent root slot unexpectedly occupied'
}
[byte[]]$r4WFakeEntry = New-ShortB 'ORPHAN  DIR' 0x10 27 0
[Array]::Copy($r4WFakeEntry,0,$r4WFalseParent,($r4WRootAt+160),32)

$r4WCases = @(
    [pscustomobject]@{ id='legitimate_empty0_and_empty9'; image=$r4WLegitimate; includeDeleted=$false },
    [pscustomobject]@{ id='M04_corrupted_size'; image=$r4WDamaged; includeDeleted=$false },
    [pscustomobject]@{ id='M04L_bad_lfn'; image=$r4WLfn; includeDeleted=$false },
    [pscustomobject]@{ id='M04_deleted'; image=$r4WDeleted; includeDeleted=$true },
    [pscustomobject]@{ id='unobserved_parent27'; image=$r4WFalseParent; includeDeleted=$false },
    [pscustomobject]@{ id='X02_truncated_no_observation'; image=[byte[]](New-ChappyA3DDamagedFixture -Case X02 -Seed $r4WSeed).image; includeDeleted=$false }
)
$r4WOldTP=0; $r4WOldFP=0; $r4WOldFN=0; $r4WOldTN=0
$r4WNewTP=0; $r4WNewFP=0; $r4WNewFN=0; $r4WNewTN=0
$r4WUnknownDamaged=0; $r4WUnknownLegitimate=0; $r4WUnscorable=0
$r4WTotalDirBytes=0L; $r4WRetained=0; $r4WFalsePathClaims=0
$r4WOldMs=0L; $r4WNewMs=0L
foreach ($r4WCase in $r4WCases) {
    [byte[]]$r4WBytes=$r4WCase.image
    $r4WHash=Get-A3DSha256 $r4WBytes
    $r4WOldStream=[IO.MemoryStream]::new($r4WBytes,$false)
    $r4WNewStream=[IO.MemoryStream]::new($r4WBytes,$false)
    try {
        $r4WCommon=@{
            MaxScanBytes=1024L; MaxCandidates=32; MaxDirectories=16;
            ExperimentalFlagZeroSizeNonzeroStartCluster=$true;
            IncludeDeleted=$r4WCase.includeDeleted
        }
        $r4WTimer=[Diagnostics.Stopwatch]::StartNew()
        $r4WCommon.Stream=$r4WOldStream
        $r4WOld=Get-ChappyDirectoryCandidates @r4WCommon
        $r4WTimer.Stop();$r4WOldMs+=$r4WTimer.ElapsedMilliseconds
        $r4WTimer=[Diagnostics.Stopwatch]::StartNew()
        $r4WCommon.Stream=$r4WNewStream
        $r4WNew=Get-ChappyDirectoryCandidates @r4WCommon -ExperimentalConservativeZeroSizeUnknown
        $r4WTimer.Stop();$r4WNewMs+=$r4WTimer.ElapsedMilliseconds
        $r4WTotalDirBytes += [long]$r4WOld.metrics.bytesRead + [long]$r4WNew.metrics.bytesRead
        $r4WRetained += $r4WNew.items.Count

        Assert-B (-not $r4WOldStream.CanWrite -and -not $r4WNewStream.CanWrite -and
            $r4WOld.metrics.bytesRead -eq $r4WNew.metrics.bytesRead -and
            $r4WOld.items.Count -eq $r4WNew.items.Count -and
            $r4WOld.directoryContainers.Count -eq $r4WNew.directoryContainers.Count -and
            $r4WOld.status -eq $r4WNew.status -and
            $r4WOld.scanIncomplete -eq $r4WNew.scanIncomplete) ('R4 W bounded same-source parser equality: '+$r4WCase.id)
        $r4WOldGeometry=@($r4WOld.items | ForEach-Object {
            ('{0}:{1}:{2}:{3}:{4}' -f $_.offsetBytes,$_.startCluster,$_.sizeBytes,$_.isDirectory,$_.deleted)
        })
        $r4WNewGeometry=@($r4WNew.items | ForEach-Object {
            ('{0}:{1}:{2}:{3}:{4}' -f $_.offsetBytes,$_.startCluster,$_.sizeBytes,$_.isDirectory,$_.deleted)
        })
        Assert-B (([string]::Join('|',$r4WOldGeometry)) -ceq ([string]::Join('|',$r4WNewGeometry)) -and
            @($r4WOld.items|Where-Object{$null -ne $_.name -or $null -ne $_.shortName}).Count -eq 0 -and
            @($r4WNew.items|Where-Object{$null -ne $_.name -or $null -ne $_.shortName}).Count -eq 0) ('R4 W all candidates retained, no private names: '+$r4WCase.id)

        if ($r4WCase.id -eq 'legitimate_empty0_and_empty9') {
            $r4WZeroOld=@($r4WOld.items|Where-Object{-not $_.isDirectory -and $_.sizeBytes -eq 0 -and $_.startCluster -eq 0})
            $r4WZeroNew=@($r4WNew.items|Where-Object{-not $_.isDirectory -and $_.sizeBytes -eq 0 -and $_.startCluster -eq 0})
            $r4WNineOld=@($r4WOld.items|Where-Object{-not $_.isDirectory -and $_.sizeBytes -eq 0 -and $_.startCluster -eq 9})
            $r4WNineNew=@($r4WNew.items|Where-Object{-not $_.isDirectory -and $_.sizeBytes -eq 0 -and $_.startCluster -eq 9})
            Assert-B ($r4WZeroOld.Count -eq 1 -and $r4WZeroNew.Count -eq 1 -and
                $r4WZeroNew[0].confidence -eq 'probable' -and
                $r4WZeroNew[0].evidence -notcontains 'zero_size_start_field_integrity_unknown' -and
                $r4WZeroNew[0].evidence -notcontains 'zero_size_with_nonzero_start_cluster') 'R4 W genuine empty start=0 remains unflagged'
            Assert-B ($r4WNineOld.Count -eq 1 -and $r4WNineNew.Count -eq 1 -and
                $r4WNineOld[0].evidence -contains 'zero_size_with_nonzero_start_cluster' -and
                $r4WNineNew[0].sizeIntegrity -eq 'unknown' -and
                $r4WNineNew[0].confidence -eq 'partial' -and
                $r4WNineNew[0].evidence -contains 'zero_size_start_field_integrity_unknown' -and
                $r4WNineNew[0].evidence -notcontains 'zero_size_with_nonzero_start_cluster') 'R4 W genuine empty nonzero-start has neutral UNKNOWN, not damage warning'
            $r4WOldTN++;$r4WOldFP++
            $r4WNewTN++;$r4WUnknownLegitimate++
        } elseif ($r4WCase.id -eq 'M04_corrupted_size') {
            $r4WDamageOld=@($r4WOld.items|Where-Object{-not $_.isDirectory -and $_.sizeBytes -eq 0 -and $_.startCluster -ge 2 -and $_.evidence -contains 'zero_size_with_nonzero_start_cluster'})
            $r4WDamageNew=@($r4WNew.items|Where-Object{-not $_.isDirectory -and $_.sizeBytes -eq 0 -and $_.startCluster -ge 2 -and $_.evidence -contains 'zero_size_start_field_integrity_unknown'})
            Assert-B ($r4WDamageOld.Count -eq 1 -and $r4WDamageNew.Count -eq 1 -and
                $r4WDamageNew[0].sizeIntegrity -eq 'unknown' -and
                $r4WDamageNew[0].confidence -eq 'partial' -and
                $r4WDamageNew[0].evidence -notcontains 'zero_size_with_nonzero_start_cluster') 'R4 W true M04 damaged size is deliberately no longer called definite anomaly'
            $r4WOldTP++
            $r4WUnknownDamaged++
        } elseif ($r4WCase.id -eq 'M04L_bad_lfn') {
            Assert-B (@($r4WNew.items|Where-Object{$_.evidence -contains 'lfn_rejected_short_fallback' -and $_.confidence -eq 'partial' -and $_.nameSource -eq 'short_8_3'}).Count -eq 1 -and
                @($r4WNew.items|Where-Object{$_.evidence -contains 'zero_size_start_field_integrity_unknown'}).Count -eq 0) 'R4 W corrupt LFN remains partial short alias and not a size-warning'
            $r4WUnscorable++
        } elseif ($r4WCase.id -eq 'M04_deleted') {
            Assert-B (@($r4WNew.items|Where-Object{$_.deleted -and $_.sizeBytes -eq 0 -and $_.startCluster -ge 2}).Count -eq 1 -and
                @($r4WNew.items|Where-Object{$_.deleted -and $_.evidence -contains 'zero_size_start_field_integrity_unknown'}).Count -eq 0 -and
                @($r4WOld.items|Where-Object{$_.deleted -and $_.evidence -contains 'zero_size_with_nonzero_start_cluster'}).Count -eq 0) 'R4 W deleted candidate retained with deletion uncertainty and no live-file warning'
            $r4WUnscorable++
        } elseif ($r4WCase.id -eq 'unobserved_parent27') {
            Assert-B (@($r4WNew.items|Where-Object{$_.isDirectory -and $_.startCluster -eq 27}).Count -eq 1) 'R4 W artificial unobserved child reference is retained'
            $r4WGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4WNew -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
            Assert-B ($r4WGraph.scanIncomplete -and $r4WGraph.metrics.unresolvedTargetReferences -eq 1 -and
                $r4WGraph.metrics.probableEdgeAssertions -eq 0 -and
                (ConvertTo-Json -InputObject $r4WGraph -Depth 8) -notmatch 'originalPath|verified|ORPHAN') 'R4 W unknown parent never creates probable original path'
            $r4WFalsePathClaims += [int]$r4WGraph.metrics.probableEdgeAssertions
            $r4WUnscorable++
        } elseif ($r4WCase.id -eq 'X02_truncated_no_observation') {
            Assert-B ($r4WOld.status -eq 'error' -and $r4WNew.status -eq 'error' -and
                $r4WOld.metrics.bytesRead -eq 0 -and $r4WNew.metrics.bytesRead -eq 0 -and
                $r4WOld.items.Count -eq 0 -and $r4WNew.items.Count -eq 0) 'R4 W X02 no directory data observed, cannot score as healthy negative'
            $r4WUnscorable++
        }
    } finally {
        $r4WOldStream.Dispose()
        $r4WNewStream.Dispose()
    }
    Assert-B ((Get-A3DSha256 $r4WBytes) -ceq $r4WHash) ('R4 W artificial source unchanged SHA: '+$r4WCase.id)
}
Assert-B ($r4WOldTP -eq 1 -and $r4WOldFP -eq 1 -and $r4WOldFN -eq 0 -and $r4WOldTN -eq 1 -and
    $r4WNewTP -eq 0 -and $r4WNewFP -eq 0 -and $r4WNewFN -eq 0 -and $r4WNewTN -eq 1 -and
    $r4WUnknownDamaged -eq 1 -and $r4WUnknownLegitimate -eq 1 -and $r4WUnscorable -eq 4) 'R4 W predeclared live-record warning: old TP1 FP1 FN0 TN1; conservative TP0 FP0 TN1 UNKNOWN2 with damaged UNKNOWN1'
Assert-B ($r4WFalsePathClaims -eq 0 -and $r4WTotalDirBytes -eq 10240L -and
    $r4WRetained -ge 17) 'R4 W no false probable paths, equal 10240B paired scans, retained synthetic candidates'
Write-Host ('SYNTHETIC B R4 W: live size-integrity records old TP={0} FP={1} FN={2} TN={3}; conservative TP={4} FP={5} FN={6} TN={7}, abstain-unknown={8} (including {9} truly damaged); forced binary no-alert implies FN1; paired directory-only reads={10} B; elapsed-ms old={11} new={12}; no original identity verified' -f
    $r4WOldTP,$r4WOldFP,$r4WOldFN,$r4WOldTN,
    $r4WNewTP,$r4WNewFP,$r4WNewFN,$r4WNewTN,
    ($r4WUnknownDamaged+$r4WUnknownLegitimate),$r4WUnknownDamaged,$r4WTotalDirBytes,$r4WOldMs,$r4WNewMs)
