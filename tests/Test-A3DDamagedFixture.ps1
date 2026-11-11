#Requires -Version 5.1
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'helpers\New-Chappy3DDamagedFixture.ps1')

function Assert-Damage([bool]$Ok, [string]$Check) {
    if (-not $Ok) { throw "A3D_DAMAGE_FAIL: $Check" }
}

function Read-DamageOracleBytes([IO.Stream]$Source, $Truth) {
    Assert-Damage ($Source.CanRead -and $Source.CanSeek -and -not $Source.CanWrite) 'read_only_source'
    [byte[]]$bytes = New-Object 'byte[]' $Truth.lengthBytes
    $written = 0
    # Scoring uses the original known extents, including when FAT1 is broken.
    foreach ($extent in $Truth.extents) {
        $Source.Position = $extent.offsetBytes
        $read = $Source.Read($bytes, $written, $extent.lengthBytes)
        Assert-Damage ($read -eq $extent.lengthBytes) 'short_oracle_read'
        $written += $read
    }
    Assert-Damage ($written -eq $bytes.Length) 'oracle_length'
    return ,$bytes
}

$seed = 202611
$clean = New-ChappyA3DCleanFixture -Seed $seed
$cleanSha = Get-A3DSha256 $clean.image

# Derive the model's expected compressed offset from the ZIP directory as read
# by ZipArchive. The P0.1 fixture writes ASCII names and no local extra fields.
$cleanSource = [IO.MemoryStream]::new($clean.image, $false)
try { [byte[]]$package = Read-DamageOracleBytes $cleanSource $clean.oracle[1] }
finally { $cleanSource.Dispose() }
$zipSource = [IO.MemoryStream]::new($package, $false)
try {
    $zip = [IO.Compression.ZipArchive]::new($zipSource, [IO.Compression.ZipArchiveMode]::Read)
    try {
        Assert-Damage ($zip.Entries[2].FullName -ceq '3D/3dmodel.model') 'model_member_order'
        $modelPayload = $clean.oracle[1].extents[0].offsetBytes
        foreach ($entry in $zip.Entries) {
            $modelPayload += 30 + $entry.FullName.Length
            if ($entry.FullName -ceq '3D/3dmodel.model') {
                $modelPayload += $entry.CompressedLength -shr 1
                break
            }
            $modelPayload += $entry.CompressedLength
        }
    } finally { $zip.Dispose() }
} finally { $zipSource.Dispose() }

$cases = @(
    @{ id = 'M00'; layer = 'none'; affected = $null; mismatch = $null; offset = $null },
    @{ id = 'M02'; layer = 'fat1'; affected = 'artificial_3mf'; mismatch = $null; offset = 16912 },
    @{ id = 'P02'; layer = '3mf_model_payload'; affected = 'artificial_3mf'; mismatch = 'artificial_3mf'; offset = $modelPayload },
    @{ id = 'P03'; layer = 'stl_vertex_payload'; affected = 'artificial_binary_stl'; mismatch = 'artificial_binary_stl'; offset = 61024 }
)
foreach ($case in $cases) {
    $result = New-ChappyA3DDamagedFixture -Case $case.id -Seed $seed
    $repeat = New-ChappyA3DDamagedFixture -Case $case.id -Seed $seed
    $manifest = $result.manifest
    Assert-Damage ($manifest.caseId -ceq $case.id -and $manifest.seed -eq $seed -and
        $manifest.layer -ceq $case.layer -and $manifest.affectedArtificialId -ceq $case.affected) 'case_identity'
    Assert-Damage ($manifest.generatorVersion -ceq $clean.generatorVersion -and
        $manifest.mutationVersion -ceq 'A3D-damage-r1') 'manifest_versions'
    Assert-Damage ($manifest.imageBytes -eq 2097152 -and $result.image.Length -eq 2097152) 'image_budget'
    Assert-Damage ($manifest.sourceSha256Before -ceq $cleanSha -and
        $manifest.sourceSha256After -ceq $cleanSha) 'source_sha_unchanged'
    Assert-Damage ((ConvertTo-Json $manifest -Depth 4 -Compress) -ceq
        (ConvertTo-Json $repeat.manifest -Depth 4 -Compress)) 'reproducible_manifest'
    Assert-Damage (-not [object]::ReferenceEquals($result.image, $repeat.image)) 'independent_copy'
    Assert-Damage ((Get-A3DSha256 $result.image) -ceq $manifest.imageSha256 -and
        (Get-A3DSha256 $repeat.image) -ceq $manifest.imageSha256) 'reproducible_image_sha'

    if ($case.id -eq 'M00') {
        Assert-Damage ($manifest.changes.Count -eq 0 -and $manifest.imageSha256 -ceq $cleanSha) 'clean_control'
    } else {
        Assert-Damage ($manifest.changes.Count -eq 1 -and $manifest.changes[0].offsetBytes -eq $case.offset -and
            $manifest.imageSha256 -cne $cleanSha) 'expected_single_byte_change'
        $change = $manifest.changes[0]
        $expected = if ($case.id -eq 'M02') { 0 } else { $clean.image[$case.offset] -bxor 1 }
        Assert-Damage ($change.beforeByte -eq $clean.image[$case.offset] -and
            $change.afterByte -eq $result.image[$case.offset] -and
            $change.afterByte -eq $expected) 'manifest_byte_values'
        [byte[]]$restored = $result.image.Clone()
        $restored[$case.offset] = $change.beforeByte
        Assert-Damage ((Get-A3DSha256 $restored) -ceq $cleanSha) 'no_unrecorded_changes'
    }

    $fat1Link = [BitConverter]::ToUInt32($result.image, 16912)
    $fat2Link = [BitConverter]::ToUInt32($result.image, 37392)
    Assert-Damage ($fat2Link -eq 5) 'fat2_chain_preserved'
    $expectedFat1Link = if ($case.id -eq 'M02') { 0 } else { 5 }
    Assert-Damage ($fat1Link -eq $expectedFat1Link) 'fat1_chain_state'

    $matches = 0
    $source = [IO.MemoryStream]::new($result.image, $false)
    try {
        foreach ($truth in $clean.oracle) {
            [byte[]]$bytes = Read-DamageOracleBytes $source $truth
            $match = (Get-A3DSha256 $bytes) -ceq $truth.sha256
            Assert-Damage ($match -eq ($truth.artificialId -cne $case.mismatch)) 'original_file_sha'
            if ($match) { $matches++ }
        }
    } finally { $source.Dispose() }
    Assert-Damage ((Get-A3DSha256 $result.image) -ceq $manifest.imageSha256) 'scored_source_sha_unchanged'
    $offsets = ($manifest.changes | ForEach-Object { $_.offsetBytes }) -join ','
    Write-Host ('A3D DAMAGE synthetic_only case={0} changes={1} offsets={2} exact_payload_sha={3}/3' -f
        $case.id, $manifest.changes.Count, $offsets, $matches)
}

$rejected = 0
foreach ($arguments in @(
    @{ Case = 'M02'; ImagePath = 'unused-artificial-placeholder.img' },
    @{ Case = 'M02'; Source = [IO.Stream]::Null },
    @{ Case = 'M02'; Seed = 0 },
    @{ Case = 'M02,P02' }
)) {
    try { $null = New-ChappyA3DDamagedFixture @arguments }
    catch [System.Management.Automation.ParameterBindingException] { $rejected++ }
}
Assert-Damage ($rejected -eq 4) 'reject_external_source_or_invalid_case_seed'
Assert-Damage ((Get-A3DSha256 $clean.image) -ceq $cleanSha) 'reference_fixture_unchanged'
Write-Host 'PASS: A3D P0.2 isolated synthetic mutations, exact byte manifests, payload oracle and read-only sources.'

# Reuse the independent bounded directory/FAT reader and format validators
# from the clean fixture suite. It receives no oracle extent positions.
. (Join-Path $PSScriptRoot 'Test-A3DCleanFixture.ps1')
$fragmented = New-ChappyA3DDamagedFixture -Case M01
$repeat = New-ChappyA3DDamagedFixture -Case M01
$original = New-ChappyA3DCleanFixture
$before = Get-A3DSha256 $fragmented.image
Assert-Damage ((ConvertTo-Json $fragmented.manifest -Depth 4 -Compress) -ceq
    (ConvertTo-Json $repeat.manifest -Depth 4 -Compress)) 'fragment_manifest_repeat'
[byte[]]$reversed = $fragmented.image.Clone()
foreach ($change in $fragmented.manifest.changes) {
    Assert-Damage ($original.image[$change.offsetBytes] -eq $change.beforeByte -and
        $fragmented.image[$change.offsetBytes] -eq $change.afterByte) 'fragment_manifest_bytes'
    $reversed[$change.offsetBytes] = $change.beforeByte
}
Assert-Damage ((Get-A3DSha256 $reversed) -ceq (Get-A3DSha256 $original.image)) 'fragment_manifest_complete'
foreach ($fat in @(16896, 37376)) {
    Assert-Damage ([BitConverter]::ToUInt32($fragmented.image, $fat + 16) -eq 7 -and
        [BitConverter]::ToUInt32($fragmented.image, $fat + 20) -eq 0 -and
        [BitConverter]::ToUInt32($fragmented.image, $fat + 28) -eq 0x0FFFFFFF) 'fragment_chain'
}
foreach ($truth in $original.oracle) {
    [byte[]]$bytes = Read-A3DRecord $fragmented.image $truth.shortName
    Assert-Damage ((Get-A3DSha256 $bytes) -ceq $truth.sha256) 'fragment_full_file_sha'
    if ($truth.format -eq '3mf') { Confirm-A3D3Mf $bytes }
}
$length = $original.oracle[1].lengthBytes
[byte[]]$contiguous = $fragmented.image[58880..(58880 + $length - 1)]
Assert-Damage ((Get-A3DSha256 $contiguous) -cne $original.oracle[1].sha256) 'contiguous_negative'
Assert-Damage ((Get-A3DSha256 $fragmented.image) -ceq $before -and
    $fragmented.manifest.sourceSha256Before -ceq $fragmented.manifest.sourceSha256After) 'fragment_source_unchanged'
Write-Host 'PASS: M01 fragmented 3MF chain 4->7, full-file SHA 3/3, ZIP/XML valid, contiguous negative, complete mutation manifest.'

function Assert-A3DReadStops([byte[]]$Image, [string]$Alias, [int]$MaxPayloadBytes, [string]$Reason) {
    try { $null = Read-A3DRecord $Image $Alias $MaxPayloadBytes }
    catch {
        if ($_.Exception.Message -ceq "A3D_SYNTHETIC_FAIL: $Reason") { return }
        throw
    }
    throw "A3D_DAMAGE_FAIL: expected $Reason"
}

$modelTruth = $original.oracle[1]
$directoryDamage = New-ChappyA3DDamagedFixture -Case M04
$eocdDamage = New-ChappyA3DDamagedFixture -Case P01
$truncated = New-ChappyA3DDamagedFixture -Case X02
$eocdOffset = 58880 + $modelTruth.lengthBytes - 22
foreach ($scenario in @(
    @{ result = $directoryDamage; offset = 57916; length = 4 },
    @{ result = $eocdDamage; offset = $eocdOffset; length = 22 }
)) {
    $result = $scenario.result
    $expectedOffsets = @($scenario.offset..($scenario.offset + $scenario.length - 1) |
        Where-Object { $original.image[$_] -ne 0 })
    Assert-Damage ($expectedOffsets.Count -gt 0 -and
        ($expectedOffsets -join ',') -ceq ($result.manifest.changes.offsetBytes -join ',')) 'expected_zeroed_offsets'
    [byte[]]$reversed = $result.image.Clone()
    foreach ($change in $result.manifest.changes) {
        Assert-Damage ($change.afterByte -eq 0 -and $result.image[$change.offsetBytes] -eq 0) 'zeroed_byte'
        $reversed[$change.offsetBytes] = $change.beforeByte
    }
    Assert-Damage ((Get-A3DSha256 $reversed) -ceq (Get-A3DSha256 $original.image)) 'only_recorded_zeroed_bytes'
}
Assert-A3DReadStops $directoryDamage.image $modelTruth.shortName 2048 'known_clean_file_size_budget'
$source = [IO.MemoryStream]::new($directoryDamage.image, $false)
try {
    foreach ($truth in $original.oracle) {
        [byte[]]$bytes = Read-DamageOracleBytes $source $truth
        Assert-Damage ((Get-A3DSha256 $bytes) -ceq $truth.sha256) 'M04_payload_intact'
    }
} finally { $source.Dispose() }
[byte[]]$brokenZip = Read-A3DRecord $eocdDamage.image $modelTruth.shortName
Assert-Damage ((Get-A3DSha256 $brokenZip) -cne $modelTruth.sha256) 'P01_sha_mismatch'
$source = [IO.MemoryStream]::new($brokenZip, $false)
$zipRejected = $false
try {
    $zip = [IO.Compression.ZipArchive]::new($source, [IO.Compression.ZipArchiveMode]::Read)
    $zip.Dispose()
} catch {
    $zipRejected = $_.Exception.InnerException -is [IO.InvalidDataException]
    if (-not $zipRejected) { throw }
} finally { $source.Dispose() }
Assert-Damage $zipRejected 'P01_missing_end_record_rejected'

$removed = $truncated.manifest.removedRange
Assert-Damage ($removed.offsetBytes -eq 59520 -and $truncated.image.Length -eq $removed.offsetBytes -and
    ($removed.offsetBytes + $removed.lengthBytes) -eq $original.image.Length -and
    $truncated.manifest.changes.Count -eq 0) 'X02_removed_range'
[byte[]]$prefix = $original.image[0..($removed.offsetBytes - 1)]
Assert-Damage ((Get-A3DSha256 $prefix) -ceq $truncated.manifest.imageSha256) 'X02_retained_prefix'

# Compare identical payload budgets on clean, fragmented and truncated media.
foreach ($image in @($original.image, $fragmented.image, $truncated.image)) {
    Assert-A3DReadStops $image $modelTruth.shortName 512 'test_payload_budget_exhausted'
}
Assert-A3DReadStops $truncated.image $modelTruth.shortName 2048 'test_extent_outside_image'
foreach ($result in @($directoryDamage, $eocdDamage, $truncated)) {
    $repeat = New-ChappyA3DDamagedFixture -Case $result.manifest.caseId
    Assert-Damage ((ConvertTo-Json $result.manifest -Depth 4 -Compress) -ceq
        (ConvertTo-Json $repeat.manifest -Depth 4 -Compress)) 'repeat_manifest'
    Assert-Damage ((Get-A3DSha256 $result.image) -ceq $result.manifest.imageSha256 -and
        $result.manifest.sourceSha256Before -ceq $result.manifest.sourceSha256After) 'source_sha_unchanged'
}
Write-Host 'PASS: M04 zero directory size, original payload SHA 3/3; P01 missing ZIP end record rejected; X02 truncated extent rejected with 2048-byte budget and clean/fragmented/truncated payload budget stops at 512.'
