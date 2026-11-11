#Requires -Version 5.1
<#
Opt-in LOCAL-ONLY, read-only FAT32 candidate diagnostics.
Only a regular .img file on an absolute local drive is allowed, with explicit
consent. Prints a fixed-schema numeric summary. No output file or extraction.
DO NOT use on the real 31GB master IMG until Team A reviews this experimental
runner. GitHub CI uses temporary artificial images only.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ImagePath,
    [switch]$IUnderstandReadOnlyLocal,
    [ValidateRange(16384,16777216)][long]$MaxDirectoryScanBytes=1048576,
    [ValidateRange(8,1048576)][int]$MaxMirrorReadBytes=32768,
    [ValidateRange(512,131584)][int]$MaxEb58ReadBytes=8704,
    [long]$PartitionOffsetBytes=-1
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not $IUnderstandReadOnlyLocal) {
    throw 'READ_ONLY_CONSENT_REQUIRED: specify -IUnderstandReadOnlyLocal for explicit local-only invocation'
}
if ($PartitionOffsetBytes -lt -1) { throw 'INVALID_PARTITION_OFFSET' }
if ($ImagePath -cnotmatch '^[A-Za-z]:[\\/]') {
    throw 'LOCAL_IMAGE_PATH_REQUIRED: UNC, device and relative paths prohibited'
}
$stream=$null
try {
    $full=[IO.Path]::GetFullPath($ImagePath)
    if ([IO.Path]::GetExtension($full) -ine '.img') { throw 'IMAGE_EXTENSION_REJECTED' }
    $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    if ($full.StartsWith($root.TrimEnd([char[]]@('\','/'))+'\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'IMAGE_INSIDE_PUBLIC_REPOSITORY_REJECTED'
    }
    $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($full))
    if ($drive.DriveType -notin @([IO.DriveType]::Fixed,[IO.DriveType]::Removable)) {
        throw 'NONLOCAL_DRIVE_REJECTED'
    }
    if (-not [IO.File]::Exists($full)) { throw 'REGULAR_IMAGE_REQUIRED' }
    $info=[IO.FileInfo]::new($full)
    if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        ($info.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
        throw 'REPARSE_OR_DIRECTORY_REJECTED'
    }
    $cursor=$info.Directory
    while ($null -ne $cursor) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'REPARSE_PARENT_REJECTED'
        }
        $cursor=$cursor.Parent
    }
    if ($info.Length -lt 512) { throw 'IMAGE_TOO_SMALL' }

    # This is the ONLY source file-open call; never opens a writable stream.
    $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    if (-not $stream.CanRead -or -not $stream.CanSeek -or $stream.CanWrite) {
        throw 'READ_ONLY_STREAM_REQUIRED'
    }
    $moduleRoot=Join-Path $root 'modules'
    . (Join-Path $moduleRoot 'directory\DirectoryScanner.ps1')
    . (Join-Path $moduleRoot 'directory\DirectoryHierarchy.ps1')
    Import-Module (Join-Path $moduleRoot 'fat-analysis\Fat32MirrorWindows.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $moduleRoot 'fat-analysis\Fat32Eb58Map.psm1') -Force -ErrorAction Stop

    $geo=Get-ChappyFat32Geometry -Stream $stream -PartitionOffsetBytes $PartitionOffsetBytes
    if ([long]$geo.fatCount -ne 2) { throw 'TWO_FAT_COPIES_REQUIRED_FOR_COMPARISON' }
    $fatLength=[long]$geo.fatSizeSectors*[long]$geo.bytesPerSector
    $fat1=[long]$geo.dataOffsetBytes-([long]$geo.fatCount*$fatLength)
    $fat2=$fat1+$fatLength
    if ($fat1 -lt 0 -or $fat2 -le $fat1) { throw 'INCONSISTENT_FAT_GEOMETRY' }

    $dir=Get-ChappyDirectoryCandidates -Stream $stream -Geometry $geo -MaxScanBytes $MaxDirectoryScanBytes -MaxCandidates 256 -MaxDirectories 64
    $hierarchy=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $dir -MaxNodes 128 -MaxEdges 512 -MaxMetadataItems 4096 -MaxAncestorDepth 32 -MaxAncestorSteps 8192
    $mirrors=Get-ChappyFatMirrorWindows -Stream $stream -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $fatLength -WindowEntries 128 -MaxWindows 16 -MaxReadBytes $MaxMirrorReadBytes
    $patterns=Get-ChappyFatEb58Map -Stream $stream -VolumeOffsetBytes ([long]$geo.partitionOffsetBytes) -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $fatLength -ProbeBytesPerFat 4096 -MaxReadBytes $MaxEb58ReadBytes

    # Fixed-schema numeric aggregates only: no original names, source path,
    # raw bytes, arbitrary upstream strings, or local report files.
    $incomplete=($dir.scanIncomplete -or $hierarchy.scanIncomplete -or
        $mirrors.scanIncomplete -or $patterns.scanIncomplete)
    [pscustomobject]@{
        schemaVersion='1';team='A';mode='local_read_only_preflight'
        status=$(if($incomplete){'partial'}else{'ok'})
        scanIncomplete=[bool]$incomplete
        imageLengthBytes=[long]$stream.Length
        sourceOpenedReadOnly=$true
        extractionAttempted=$false;repairAttempted=$false
        reportFileWritten=$false;privateNamesIncluded=$false
        geometry=[pscustomobject]@{
            partitionOffsetBytes=[long]$geo.partitionOffsetBytes
            clusterSizeBytes=[long]$geo.clusterSizeBytes
            rootCluster=[long]$geo.rootCluster
            fat1OffsetBytes=$fat1;fat2OffsetBytes=$fat2
            declaredFatLengthBytes=$fatLength
        }
        directory=[pscustomobject]@{
            status=$(if($dir.scanIncomplete){'partial'}else{'ok'})
            candidateRecords=[long]$dir.items.Count
            acceptedContainers=[long]$dir.directoryContainers.Count
            bytesReadReported=[long]$dir.metrics.bytesRead
        }
        hierarchy=[pscustomobject]@{
            status=[string]$hierarchy.status
            nodes=[long]$hierarchy.metrics.nodes
            candidateEdges=[long]$hierarchy.metrics.edgeAssertions
            uncertainTargets=[long]$hierarchy.metrics.unresolvedTargetReferences
        }
        fatMirrors=[pscustomobject]@{
            status=[string]$mirrors.status
            comparedEntries=[long]$mirrors.metrics.entriesChecked
            differentEntries=[long]$mirrors.metrics.differentEntries
            bytesRead=[long]$mirrors.metrics.bytesRead
            comparisonCoveragePercent=[double]$mirrors.metrics.comparisonCoveragePercent
        }
        eb58=[pscustomobject]@{
            status=[string]$patterns.status
            observedPatternRuns=[long]$patterns.metrics.totalPatternRuns
            observedPairs=[long]$patterns.metrics.totalObservedPatternPairs
            bytesRead=[long]$patterns.metrics.bytesRead
            bpbOffsetsDisagree=[bool]$patterns.geometryComparison.suppliedOffsetsDisagreeWithBpb
        }
        limitations=@('synthetic_ci_only_until_local_review','candidate_metadata_not_file_integrity',
            'no_repair_or_extraction','partial_scans_do_not_prove_absence')
    }
} catch {
    # Arbitrary .NET exception text may contain private local paths.
    throw ('LOCAL_PREFLIGHT_FAILED_'+$_.Exception.GetType().Name)
} finally {
    if ($null -ne $stream) {$stream.Dispose()}
}