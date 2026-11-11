#Requires -Version 5.1
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-Chappy3DDamagedFixture.ps1')
. (Join-Path $root 'modules\directory\DirectoryScanner.ps1')
Import-Module (Join-Path $root 'modules\carving\Chappy.Carving.psm1') -Force
Import-Module (Join-Path $root 'modules\fat-analysis\Fat32MirrorWindows.psm1') -Force

function Assert-A3DEvidence([bool]$Condition, [string]$Reason) {
    if (-not $Condition) { throw "A3D_EVIDENCE_FAIL: $Reason" }
}

function Read-A3DModuleEvidence([IO.Stream]$Source) {
    Assert-A3DEvidence ($Source.CanRead -and $Source.CanSeek -and -not $Source.CanWrite) 'nonwritable_input'
    $geometry = Get-ChappyFat32Geometry -Stream $Source
    Assert-A3DEvidence ($geometry.fatCount -eq 2) 'mirror_geometry'
    $fatBytes = [long]$geometry.fatSizeSectors * $geometry.bytesPerSector
    $fat1 = $geometry.dataOffsetBytes - 2 * $fatBytes
    $directory = Get-ChappyDirectoryCandidates -Stream $Source -Geometry $geometry -MaxScanBytes 512 -MaxCandidates 16 -MaxDirectories 4
    $carving = Get-ChappyCarvingCandidates -Stream $Source -MaxScanBytes 65536 -ExtraValidationReadBytes 32768 -MaxFileBytes 4096 -MaxCandidates 16 -MaxProbes 16 -MaxProbeBytes 8192
    $mirrors = Get-ChappyFatMirrorWindows -Stream $Source -Fat1OffsetBytes $fat1 -Fat2OffsetBytes ($fat1 + $fatBytes) -FatLengthBytes $fatBytes -WindowEntries 128 -MaxWindows 1 -MaxReadBytes 1024
    Assert-A3DEvidence ($directory.status -ne 'error' -and $carving.status -ne 'error' -and $mirrors.status -ne 'error') 'analysis_status'
    Assert-A3DEvidence ($directory.metrics.bytesRead -eq 512 -and $carving.metrics.bytesRead -le 98304 -and
        $mirrors.metrics.bytesRead -eq 1024) 'module_read_budgets'
    Assert-A3DEvidence ($directory.scanIncomplete -and $mirrors.scanIncomplete) 'partial_coverage_preserved'

    [pscustomobject]@{ directory = $directory; carving = $carving; mirrors = $mirrors }
}

# Only the scorer sees the original layout and SHA. The analysis receives just
# the artificial stream and fixed limits. These cases keep the model contiguous.
$seed = 202611
$clean = New-ChappyA3DCleanFixture -Seed $seed
$truth = $clean.oracle[1]
$modelOffset = $truth.extents[0].offsetBytes
$entryOffset = $clean.layout.rootOffsetBytes + 32
foreach ($case in @('M00', 'M02', 'M04', 'P02')) {
    $fixture = New-ChappyA3DDamagedFixture -Seed $seed -Case $case
    $source = [IO.MemoryStream]::new($fixture.image, $false)
    try { $evidence = Read-A3DModuleEvidence $source }
    finally { $source.Dispose() }
    Assert-A3DEvidence ((Get-A3DSha256 $fixture.image) -ceq $fixture.manifest.imageSha256) 'analysis_source_unchanged'

    $entries = @($evidence.directory.items | Where-Object { $_.offsetBytes -eq $entryOffset })
    $candidates = @($evidence.carving.items | Where-Object { $_.offsetBytes -eq $modelOffset -and $_.format -eq '3mf' })
    Assert-A3DEvidence ($entries.Count -eq 1 -and $candidates.Count -eq 1) 'known_synthetic_observations_present'
    $candidate = $candidates[0]
    Assert-A3DEvidence ($candidate.lengthBytes -eq $truth.lengthBytes -and $candidate.confidence -eq 'verified') 'C_structure_check'
    $expectedSize = if ($case -eq 'M04') { 0 } else { $truth.lengthBytes }
    Assert-A3DEvidence ($entries[0].sizeBytes -eq $expectedSize) 'B_reported_metadata_size'
    $expectedDifferences = if ($case -eq 'M02') { 1 } else { 0 }
    Assert-A3DEvidence ($evidence.mirrors.metrics.differentEntries -eq $expectedDifferences) 'D_sampled_mirror_difference'

    $observedBytes = [byte[]]::new([int]$candidate.lengthBytes)
    [Array]::Copy($fixture.image, $candidate.offsetBytes, $observedBytes, 0, $observedBytes.Length)
    $match = (Get-A3DSha256 $observedBytes) -ceq $truth.sha256
    Assert-A3DEvidence ($match -eq ($case -ne 'P02')) 'scorer_original_identity'
    Write-Host ('A3D evidence {0}: B size={1}, C structure={2}, D sampled differences={3}, oracle exact={4}; B/C/D reported bytes={5}/{6}/{7}.' -f
        $case, $entries[0].sizeBytes, $candidate.confidence, $evidence.mirrors.metrics.differentEntries, $match,
        $evidence.directory.metrics.bytesRead, $evidence.carving.metrics.bytesRead, $evidence.mirrors.metrics.bytesRead)
}
Write-Host 'PASS: A3D shared evidence baseline, four synthetic cases, independent SHA and read-only source.'
