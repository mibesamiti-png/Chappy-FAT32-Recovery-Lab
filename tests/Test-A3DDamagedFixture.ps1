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
