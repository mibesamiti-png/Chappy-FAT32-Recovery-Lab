#requires -Version 5.1
# Team B R4: entirely artificial, in-memory FAT32-like cluster layout.
# Called from Test-DirectoryScanner.ps1 after synthetic fixture helpers exist.
# It does not read actual files, perform extraction, or trust FAT pointers.

function New-R4Records {
    return ,(New-Object System.Collections.ArrayList)
}
function Write-R4Cluster {
    param([byte[]]$Image, [int]$Cluster, [System.Collections.IList]$Records,
          [bool]$FillDeleted = $false)
    if ($Cluster -lt 2 -or $Cluster -gt 31) { throw 'Artificial cluster outside fixture' }
    $offset = 8192 + ($Cluster - 2)*1024
    [byte[]]$buf = New-Object byte[] 1024
    if ($FillDeleted) {
        for ($k=0;$k -lt $buf.Length;$k++) { $buf[$k] = 0xE5 }
    }
    $at = 0
    foreach ($record in $Records) {
        [byte[]]$e = [byte[]]$record
        if ($e.Length -ne 32 -or $at -gt 992) { throw 'Artificial cluster record out of bounds' }
        [Array]::Copy($e,0,$buf,$at,32)
        $at+=32
    }
    [Array]::Copy($buf,0,$Image,$offset,1024)
}
function New-R4ReadonlyStream([byte[]]$Image) {
    return [System.IO.MemoryStream]::new($Image, $false)
}
function Get-R4Sha256([byte[]]$Image) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hash.ComputeHash($Image)) }
    finally { $hash.Dispose() }
}

$size = 65536
[byte[]]$r4Image = New-Object byte[] $size
# Simulate two unusable FAT copies in the pre-data region. The B scanner
# receives externally supplied geometry and MUST NOT look up either chain.
for ($i=512;$i -lt 4096;$i+=2) { $r4Image[$i]=0xEB; $r4Image[$i+1]=0x58 }
$r4Geo = [pscustomobject]@{
    clusterSizeBytes = 1024L
    dataOffsetBytes = 8192L
    maxCluster = 31L
    clusterCount = 30L
    rootCluster = 2L
    partitionEndBytes = [long]$size
}
$dirA = New-ShortB 'SCATTERA   ' 0x10 6 0
$dirB = New-ShortB 'SCATTERB   ' 0x10 13 0
$orphanDir = New-ShortB 'OLDLINK    ' 0x10 27 0
$outerData = New-ShortB 'ROOT    TXT' 0x20 18 11
$innerData = New-ShortB 'INNER   TXT' 0x20 22 19
$orphanData = New-ShortB 'ORPHAN  TXT' 0x20 23 12

# Logical parent 2 -> 6 -> 13 while actual clusters are not adjacent.
$records = New-R4Records
[void]$records.Add($dirA); [void]$records.Add($outerData)
[byte[]]$deletedLink = [byte[]]$orphanDir.Clone()
$deletedLink[0] = 0xE5
[void]$records.Add($deletedLink)
Write-R4Cluster $r4Image 2 $records

$records = New-R4Records
[void]$records.Add((New-ShortB '.          ' 0x10 6 0))
[void]$records.Add((New-ShortB '..         ' 0x10 2 0))
[void]$records.Add($dirB)
Write-R4Cluster $r4Image 6 $records

$records = New-R4Records
[void]$records.Add((New-ShortB '.          ' 0x10 13 0))
[void]$records.Add((New-ShortB '..         ' 0x10 6 0))
[void]$records.Add($innerData)
Write-R4Cluster $r4Image 13 $records

# Valid-looking directory with no live parent reference. Its only
# parent claim is a dotdot root marker, not evidence of a verified path.
$records = New-R4Records
[void]$records.Add((New-ShortB '.          ' 0x10 27 0))
[void]$records.Add((New-ShortB '..         ' 0x10 0 0))
[void]$records.Add($orphanData)
Write-R4Cluster $r4Image 27 $records

# Known synthetic negative: lone plausible record in arbitrary data.
$records = New-R4Records
[void]$records.Add((New-ShortB 'LONE    TXT' 0x20 19 33))
Write-R4Cluster $r4Image 9 $records

# Known synthetic negative: misleading ordered dot and invalid dotdot.
$records = New-R4Records
[void]$records.Add((New-ShortB '.          ' 0x10 11 0))
[void]$records.Add((New-ShortB '..         ' 0x10 999 0))
[void]$records.Add((New-ShortB 'BAIT    TXT' 0x20 19 10))
Write-R4Cluster $r4Image 11 $records

# Deliberately place an LFN record in the final 32 bytes of cluster 20,
# followed by its short alias in unrelated cluster 21. Even though they
# are physically adjacent, the scanner cannot join their records.
$shortAfterBoundary = New-ShortB 'SPLIT~1 TXT' 0x20 24 28
$lfnSegments = (New-LfnB 'SplitAcrossClusters.txt' $shortAfterBoundary)
$records = New-R4Records
[void]$records.Add((New-ShortB '.          ' 0x10 20 0))
[void]$records.Add((New-ShortB '..         ' 0x10 0 0))
# Ensure exact last slot is an orphaned LFN, with deleted bytes before it.
[byte[]]$boundaryCluster = New-Object byte[] 1024
for ($k=0;$k -lt 1024;$k++) { $boundaryCluster[$k]=0xE5 }
[Array]::Copy([byte[]]$lfnSegments[0],0,$boundaryCluster,992,32)
[Array]::Copy($boundaryCluster,0,$r4Image,(8192+(20-2)*1024),1024)

$records = New-R4Records
[void]$records.Add((New-ShortB '.          ' 0x10 21 0))
[void]$records.Add((New-ShortB '..         ' 0x10 0 0))
[void]$records.Add($shortAfterBoundary)
Write-R4Cluster $r4Image 21 $records

# Known synthetic false-positive risk: two file-like records in arbitrary
# file data followed by a zero marker satisfy a weak container heuristic.
# Keep this visible as an observed limitation, not a verified directory.
$records = New-R4Records
[void]$records.Add((New-ShortB 'LURE1   TXT' 0x20 29 5))
[void]$records.Add((New-ShortB 'LURE2   TXT' 0x20 30 6))
Write-R4Cluster $r4Image 25 $records

$hashBefore = Get-R4Sha256 $r4Image
$r4Stream = New-R4ReadonlyStream $r4Image
try {
    Assert-B (-not $r4Stream.CanWrite -and $r4Stream.CanRead -and $r4Stream.CanSeek) 'R4 scattered synthetic stream strictly read-only'
    $scan = Get-ChappyDirectoryCandidates -Stream $r4Stream -Geometry $r4Geo -MaxScanBytes 30720 -IncludeDeleted
    Assert-B ($scan.status -eq 'ok' -and -not $scan.scanIncomplete -and
        $scan.metrics.bytesRead -eq 30720 -and $scan.errors.Count -eq 0) 'R4 full scattered-cluster scan bounded and complete'
    $actualContainers = @($scan.directoryContainers | ForEach-Object { [long]$_.cluster })
    Assert-B (@(2,6,13,27,21 | Where-Object { $actualContainers -notcontains $_ }).Count -eq 0) 'R4 noncontiguous and orphan candidate clusters independently discovered'
    Assert-B ($actualContainers -notcontains 9 -and $actualContainers -notcontains 11) 'R4 lone-entry and malformed-dot lure clusters rejected'
    Assert-B (@($scan.items | Where-Object { $_.deleted -and $_.containerCluster -eq 2 }).Count -eq 1) 'R4 deleted directory reference remains candidate metadata only'
    Assert-B (@($scan.items | Where-Object { $_.containerCluster -eq 21 -and $_.nameSource -eq 'short_8_3' }).Count -eq 1 -and
        @($scan.items | Where-Object {$_.containerCluster -eq 20}).Count -eq 0) 'R4 adjacent clusters never splice split LFN records'
    Assert-B (@($scan.items | Where-Object {$null -ne $_.name -or $null -ne $_.shortName}).Count -eq 0) 'R4 default name redaction preserved'
    $graph = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $scan
    Assert-B (@($graph.edges | Where-Object { $_.parentCluster -eq 2 -and $_.childCluster -eq 6 -and
        $_.relationStatus -eq 'parent_hint_corroborated' }).Count -eq 1 -and
        @($graph.edges | Where-Object { $_.parentCluster -eq 6 -and $_.childCluster -eq 13 -and
        $_.relationStatus -eq 'parent_hint_corroborated' }).Count -eq 1) 'R4 scattered clusters corroborate only observed parent-child assertions'
    Assert-B (@($graph.nodes | Where-Object { $_.cluster -eq 27 -and $_.linkStatus -eq 'orphan_candidate' }).Count -eq 1 -and
        @($graph.edges | Where-Object {$_.childCluster -eq 27}).Count -eq 0) 'R4 deleted parent reference cannot fabricate orphan path'
    Assert-B (@($graph.parentHints | Where-Object { $_.childCluster -eq 27 -and
        $_.relationStatus -eq 'root_marker_not_path' }).Count -eq 1) 'R4 orphan dotdot root marker is not verified hierarchy'
    Assert-B (@($scan.directoryContainers | Where-Object { $_.cluster -eq 25 -and
        $_.decisionReason -eq 'multiple_entries_with_end_marker' }).Count -eq 1) 'R4 synthetic file-data masquerade reproduces weak two-entry heuristic risk'

    # A second image with identical data-region bytes but entirely different
    # pre-data FAT bytes must produce identical redacted scanner candidates.
    [byte[]]$fatAlternate = [byte[]]$r4Image.Clone()
    [Array]::Clear($fatAlternate,0,8192)
    $otherStream = New-R4ReadonlyStream $fatAlternate
    try {
        $sameData = Get-ChappyDirectoryCandidates -Stream $otherStream -Geometry $r4Geo -MaxScanBytes 30720 -IncludeDeleted
        $sig1 = @($scan.items | ForEach-Object { "$($_.containerCluster):$($_.offsetBytes):$($_.startCluster):$($_.deleted)" }) -join '|'
        $sig2 = @($sameData.items | ForEach-Object { "$($_.containerCluster):$($_.offsetBytes):$($_.startCluster):$($_.deleted)" }) -join '|'
        Assert-B ($sig1 -eq $sig2 -and
            $scan.metrics.bytesRead -eq $sameData.metrics.bytesRead) 'R4 corrupted versus zeroed FAT copies do not alter FAT-independent directory candidates'
    } finally { $otherStream.Dispose() }

    $partial = Get-ChappyDirectoryCandidates -Stream $r4Stream -Geometry $r4Geo -MaxScanBytes 1024
    $partialGraph = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $partial
    Assert-B ($partial.scanIncomplete -and $partial.metrics.bytesRead -eq 1024 -and
        $partialGraph.scanIncomplete -and $partialGraph.metrics.unresolvedTargetReferences -ge 1) 'R4 insufficient scan budget leaves unresolved child instead of inventing path'
    $budget = Get-ChappyDirectoryCandidates -Stream $r4Stream -Geometry $r4Geo -StartCluster 6 -MaxScanBytes 2048
    Assert-B ($budget.scanIncomplete -and $budget.metrics.bytesRead -eq 2048 -and
        @($budget.directoryContainers | Where-Object { $_.cluster -eq 13 }).Count -eq 0) 'R4 start-cluster budget cannot follow noncontiguous child implicitly'

    # Duplicate synthetic parent entry scenario; result must remain ambiguous.
    [byte[]]$dupImage = [byte[]]$r4Image.Clone()
    $records = New-R4Records
    [void]$records.Add($dirA); [void]$records.Add($dirA); [void]$records.Add($outerData)
    Write-R4Cluster $dupImage 2 $records
    $dupStream = New-R4ReadonlyStream $dupImage
    try {
        $dupScan = Get-ChappyDirectoryCandidates -Stream $dupStream -Geometry $r4Geo -MaxScanBytes 30720
        $dupGraph = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $dupScan
        Assert-B (@($dupGraph.edges | Where-Object { $_.childCluster -eq 6 -and
            $_.relationStatus -eq 'duplicate_parent_assertion' }).Count -eq 2) 'R4 duplicate parent records stay ambiguous, never form proven path'
    } finally { $dupStream.Dispose() }

    Assert-B ((Get-R4Sha256 $r4Image) -eq $hashBefore) 'R4 synthetic source SHA-256 unchanged after multiple scans'
    Write-Host 'SYNTHETIC R4 ONLY: noncontiguous live directories=3; orphan candidates=2; known weak-heuristic decoy=1; no original paths verified'
} finally { $r4Stream.Dispose() }
