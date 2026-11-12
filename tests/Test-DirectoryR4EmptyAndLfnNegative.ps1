#requires -Version 5.1
# Team B R4 continuation: negative controls on ONLY generated synthetic bytes.
# Dot-sourced from Test-DirectoryScanner.ps1 after New-Chappy3DDamagedFixture.ps1.
# Oracle labels remain in this test (scorer); scanner receives only readonly bytes.

$r4NSeed = 202611
$r4NGood = New-ChappyA3DDamagedFixture -Case M00 -Seed $r4NSeed
# The damaged-fixture wrapper exposes image/manifest only; take layout
# from the same-seed standalone clean synthetic generator (test-side only).
$r4NLayout = (New-ChappyA3DCleanFixture -Seed $r4NSeed).layout
[byte[]]$r4NBytes = [byte[]]$r4NGood.image.Clone()
$r4NRootAt = [int]$r4NLayout.rootOffsetBytes
if ($r4NRootAt -lt 0 -or ($r4NRootAt + 160) -gt $r4NBytes.Length -or
    $r4NBytes[$r4NRootAt+96] -ne 0 -or
    $r4NBytes[$r4NRootAt+128] -ne 0) {
    throw 'R4 negative-control root slots not empty as expected in frozen seed'
}

# Two independently declared LEGITIMATE empty files: common zero cluster
# and an allocated nonzero cluster field. The latter is intentionally
# ambiguous to a FAT-independent scanner. No filenames reach GitHub outputs.
[byte[]]$r4NEmptyZero = New-ShortB 'EMPTY0  TXT' 0x20 0 0
[byte[]]$r4NEmptyNine = New-ShortB 'EMPTY9  TXT' 0x20 9 0
[Array]::Copy($r4NEmptyZero, 0, $r4NBytes, ($r4NRootAt+96), 32)
[Array]::Copy($r4NEmptyNine, 0, $r4NBytes, ($r4NRootAt+128), 32)

# External synthetic truth says cluster 9 is allocated in both FAT copies.
# This mutation only prepares an invented TEST IMAGE. B scanner never
# reads the FAT; the truth does not become an algorithm input.
foreach($r4NFatStart in @([int]$r4NLayout.fat1OffsetBytes,
                          [int]$r4NLayout.fat2OffsetBytes)) {
    $r4NFatEntryAt = $r4NFatStart + 9*4
    if ($r4NFatEntryAt -lt 0 -or $r4NFatEntryAt+4 -gt $r4NBytes.Length -or
        [BitConverter]::ToUInt32($r4NBytes,$r4NFatEntryAt) -ne 0) {
        throw 'R4 synthetic empty cluster 9 not free or FAT bounds unexpected'
    }
    [Array]::Copy([BitConverter]::GetBytes([uint32]0x0FFFFFFF),
                  0,$r4NBytes,$r4NFatEntryAt,4)
}
$r4NGoodHash = Get-A3DSha256 $r4NBytes
$r4NUnchanged = $true
$r4NBaseWatch = [Diagnostics.Stopwatch]::new()
$r4NCandidateWatch = [Diagnostics.Stopwatch]::new()
$r4NReadBytes = 0L
$r4NActualTP = 0
$r4NActualFP = 0
$r4NActualFN = 0
$r4NActualTN = 0
$r4NRetainedCandidates = 0

# Equal caps, same arrays and byte order. The hypothesis is explicitly:
# size-zero + valid nonzero start FIELD => uncertain, not proven damaged.
$r4NFixtures = @(
    [pscustomobject]@{ id='M00_two_clean_empty'; image=$r4NBytes; damaged=$false },
    [pscustomobject]@{ id='M04_known_damaged_size'; image=(New-ChappyA3DDamagedFixture -Case M04 -Seed $r4NSeed).image; damaged=$true }
)
foreach($r4NCase in $r4NFixtures) {
    [byte[]]$r4NCaseBytes = [byte[]]$r4NCase.image
    $r4NBefore = Get-A3DSha256 $r4NCaseBytes
    $r4NBaseStream = [IO.MemoryStream]::new($r4NCaseBytes,$false)
    $r4NCandidateStream = [IO.MemoryStream]::new($r4NCaseBytes,$false)
    try {
        $r4NBaseWatch.Start()
        $r4NBase = Get-ChappyDirectoryCandidates -Stream $r4NBaseStream -MaxScanBytes 1024 -MaxCandidates 32 -MaxDirectories 16
        $r4NBaseWatch.Stop()
        $r4NCandidateWatch.Start()
        $r4NCandidate = Get-ChappyDirectoryCandidates -Stream $r4NCandidateStream -MaxScanBytes 1024 -MaxCandidates 32 -MaxDirectories 16 -ExperimentalFlagZeroSizeNonzeroStartCluster
        $r4NCandidateWatch.Stop()
        Assert-B (-not $r4NBaseStream.CanWrite -and -not $r4NCandidateStream.CanWrite -and
            $r4NBase.metrics.bytesRead -eq 1024 -and $r4NCandidate.metrics.bytesRead -eq 1024 -and
            $r4NBase.scanIncomplete -and $r4NCandidate.scanIncomplete -and
            $r4NBase.items.Count -eq $r4NCandidate.items.Count -and
            $r4NBase.directoryContainers.Count -eq $r4NCandidate.directoryContainers.Count) "R4 $($r4NCase.id) same capped readonly input and retained observations"
        $r4NReadBytes += [long]$r4NBase.metrics.bytesRead + [long]$r4NCandidate.metrics.bytesRead
        $r4NRetainedCandidates += [int]$r4NCandidate.items.Count
        if (-not $r4NCase.damaged) {
            $r4NZero = @($r4NCandidate.items | Where-Object {
                -not $_.isDirectory -and $_.sizeBytes -eq 0 -and $_.startCluster -eq 0
            })
            $r4NNine = @($r4NCandidate.items | Where-Object {
                -not $_.isDirectory -and $_.sizeBytes -eq 0 -and $_.startCluster -eq 9
            })
            Assert-B ($r4NZero.Count -eq 1 -and $r4NZero[0].confidence -eq 'probable' -and
                $r4NZero[0].evidence -notcontains 'zero_size_with_nonzero_start_cluster') 'R4 legitimate empty start=0 not flagged'
            Assert-B ($r4NNine.Count -eq 1 -and $r4NNine[0].confidence -eq 'partial' -and
                $r4NNine[0].evidence -contains 'zero_size_with_nonzero_start_cluster') 'R4 legitimate empty nonzero start is retained but ambiguous (known false flag)'
            $r4NActualTN++
            $r4NActualFP++ # Explicit external truth: allocated zero-length file is not damaged.
        } else {
            $r4NMarked = @($r4NCandidate.items | Where-Object {
                -not $_.isDirectory -and $_.sizeBytes -eq 0 -and $_.startCluster -ge 2 -and
                $_.evidence -contains 'zero_size_with_nonzero_start_cluster'
            })
            Assert-B ($r4NMarked.Count -eq 1 -and $r4NMarked[0].confidence -eq 'partial') 'R4 M04 independent damaged-size control remains partial'
            $r4NActualTP++
        }
        $r4NGraph = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4NCandidate -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
        Assert-B ($r4NGraph.scanIncomplete -and $r4NGraph.metrics.probableEdgeAssertions -eq 0 -and
            $r4NGraph.edges.Count -eq 0 -and
            (ConvertTo-Json -InputObject $r4NGraph -Depth 8) -notmatch 'originalPath|verified|EMPTY[09]') 'R4 partial root-only scan never claims a complete original path'
        Assert-B (@($r4NCandidate.items | Where-Object {$null -ne $_.name -or $null -ne $_.shortName}).Count -eq 0) 'R4 default scan does not leak invented names'
    } finally {
        $r4NBaseStream.Dispose()
        $r4NCandidateStream.Dispose()
    }
    Assert-B ((Get-A3DSha256 $r4NCaseBytes) -ceq $r4NBefore) "R4 $($r4NCase.id) source hash unchanged"
}
Assert-B ($r4NActualTP -eq 1 -and $r4NActualFP -eq 1 -and
    $r4NActualFN -eq 0 -and $r4NActualTN -eq 1) 'R4 negative-control warning TP1 FP1 FN0 TN1; nonzero-start empty is false flag'
Assert-B ($r4NReadBytes -eq 4096 -and $r4NRetainedCandidates -ge 8) 'R4 baseline+candidate directory-data reads 4096 bytes with no dropped records'
Assert-B ((Get-A3DSha256 $r4NBytes) -ceq $r4NGoodHash) 'R4 altered artificial positive-control bytes unchanged by scanner'

# Separate oracle-labeled corrupted LFN case, same 1024-byte cap and no
# external clean name exposed to the scanner. This is not a recovered name.
$r4NLfnFixture = New-ChappyA3DDamagedFixture -Case M04L -Seed $r4NSeed
[byte[]]$r4NLfnBytes = [byte[]]$r4NLfnFixture.image
$r4NLfnHash = Get-A3DSha256 $r4NLfnBytes
$r4NLfnStream = [IO.MemoryStream]::new($r4NLfnBytes,$false)
try {
    $r4NLfnScan = Get-ChappyDirectoryCandidates -Stream $r4NLfnStream -MaxScanBytes 1024 -MaxCandidates 32 -MaxDirectories 16
    $r4NReadBytes += [long]$r4NLfnScan.metrics.bytesRead
    $r4NLfnFallback = @($r4NLfnScan.items | Where-Object {
        $_.evidence -contains 'lfn_rejected_short_fallback' -and
        $_.confidence -eq 'partial' -and $_.nameSource -eq 'short_8_3'
    })
    Assert-B ($r4NLfnScan.metrics.bytesRead -eq 1024 -and $r4NLfnFallback.Count -eq 1 -and
        $r4NLfnScan.scanIncomplete -and
        @($r4NLfnScan.items | Where-Object {$null -ne $_.name}).Count -eq 0) 'R4 M04L bad checksum falls back to redacted short alias with partial confidence'
    $r4NLfnGraph = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4NLfnScan -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16
    Assert-B ($r4NLfnGraph.scanIncomplete -and $r4NLfnGraph.metrics.probableEdgeAssertions -eq 0 -and
        (ConvertTo-Json -InputObject $r4NLfnGraph -Depth 8) -notmatch 'originalPath|verified') 'R4 M04L invalid LFN cannot justify an original path'
    Assert-B (-not $r4NLfnStream.CanWrite -and
        (Get-A3DSha256 $r4NLfnBytes) -ceq $r4NLfnHash) 'R4 M04L artificial source SHA unchanged and strictly readonly'
} finally { $r4NLfnStream.Dispose() }

Write-Host ('SYNTHETIC B R4 negative controls ONLY: warning TP={0} FP={1} FN={2} TN={3}; M04L LFN fallback=1; directory-data bytes baseline+candidate+LFN={4}; elapsed-ms baseline={5} candidate={6}; no original path/file verified' -f
    $r4NActualTP,$r4NActualFP,$r4NActualFN,$r4NActualTN,$r4NReadBytes,$r4NBaseWatch.ElapsedMilliseconds,$r4NCandidateWatch.ElapsedMilliseconds)
