#Requires -Version 5.1
# Team A isolated synthetic-only, clean 3MF/STL/G-code FAT32-LIKE round-trip.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'helpers\New-Chappy3DCleanFixture.ps1')

function Assert-A3D([bool]$Ok, [string]$Code) {
    if (-not $Ok) { throw ('A3D_SYNTHETIC_FAIL: ' + $Code) }
}
function Read-A3DRecord([byte[]]$Image, [string]$Alias) {
    # Independent *test-only* FAT chain reader. It receives the damaged/clean
    # image, never the oracle extent list or oracle original bytes.
    $partitionStart = [int][BitConverter]::ToUInt32($Image, 454) * 512
    $bps = [int][BitConverter]::ToUInt16($Image, $partitionStart + 11)
    $spc = [int]$Image[$partitionStart + 13]
    $reserved = [int][BitConverter]::ToUInt16($Image, $partitionStart + 14)
    $copies = [int]$Image[$partitionStart + 16]
    $fatSectors = [int][BitConverter]::ToUInt32($Image, $partitionStart + 36)
    $fatStart = $partitionStart + ($reserved * $bps)
    $dataStart = $fatStart + ($copies * $fatSectors * $bps)
    Assert-A3D ($bps -eq 512 -and $spc -eq 1 -and $copies -eq 2 -and
                $fatSectors -eq 40 -and $dataStart -eq 57856) 'fixture_geometry'
    $record = $null
    for ($i = 0; $i -lt 3; $i++) {
        $off = $dataStart + (32 * $i)
        $name = [Text.Encoding]::ASCII.GetString($Image, $off, 11)
        if ($name -ceq $Alias) { $record = $off; break }
    }
    Assert-A3D ($null -ne $record) 'expected_artificial_directory_record'
    $size = [int][BitConverter]::ToUInt32($Image, ([int]$record + 28))
    $cluster = [int][BitConverter]::ToUInt16($Image, ([int]$record + 26))
    Assert-A3D ($size -ge 1 -and $size -le 2048) 'known_clean_file_size_budget'
    $seen = New-Object 'System.Collections.Generic.HashSet[int]'
    $ms = New-Object IO.MemoryStream
    try {
        $left = $size
        while ($left -gt 0) {
            Assert-A3D ($cluster -ge 3 -and $cluster -le 8 -and
                        $seen.Count -lt 4 -and $seen.Add($cluster)) 'invalid_or_cyclic_test_fat_chain'
            $at = $dataStart + (($cluster - 2) * 512)
            $n = [int][Math]::Min(512, $left)
            Assert-A3D ($at -ge 0 -and ([long]$at + $n) -le $Image.Length) 'test_extent_outside_image'
            $ms.Write($Image, $at, $n)
            $left -= $n
            $next = [uint32]([BitConverter]::ToUInt32($Image, $fatStart + (4 * $cluster)) -band 0x0FFFFFFF)
            if ($left -gt 0) {
                Assert-A3D ($next -ge 3 -and $next -le 8) 'test_fat_chain_truncated'
                $cluster = [int]$next
            } else {
                Assert-A3D ($next -ge [uint32]0x0FFFFFF8) 'test_fat_chain_not_terminated'
            }
        }
        return ,$ms.ToArray()
    } finally { $ms.Dispose() }
}
function Confirm-A3D3Mf([byte[]]$Bytes) {
    $ms = [IO.MemoryStream]::new($Bytes, $false)
    $zip = [IO.Compression.ZipArchive]::new($ms, [IO.Compression.ZipArchiveMode]::Read, $true)
    try {
        Assert-A3D ($zip.Entries.Count -eq 3) '3mf_zip_parts'
        $parts = @('[Content_Types].xml', '_rels/.rels', '3D/3dmodel.model')
        foreach ($p in $parts) {
            $entry = $zip.GetEntry($p)
            Assert-A3D ($null -ne $entry -and $entry.Length -gt 0 -and $entry.Length -lt 4096) '3mf_expected_part'
            $stream = $entry.Open()
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
            try {
                [xml]$xml = $reader.ReadToEnd()
                Assert-A3D ($null -ne $xml.DocumentElement) '3mf_well_formed_xml'
                if ($p -eq '3D/3dmodel.model') {
                    $tri = $xml.SelectNodes("//*[local-name()='triangle']")
                    $obj = $xml.SelectNodes("//*[local-name()='object']")
                    $build = $xml.SelectNodes("//*[local-name()='item']")
                    Assert-A3D ($tri.Count -eq 4 -and $obj.Count -eq 1 -and $build.Count -eq 1) '3mf_mesh_model_build'
                }
            } finally { $reader.Dispose() }
        }
    } finally { $zip.Dispose(); $ms.Dispose() }
}
function Confirm-A3DStl([byte[]]$Bytes) {
    Assert-A3D ($Bytes.Length -ge 84) 'binary_stl_min_length'
    $n = [uint32][BitConverter]::ToUInt32($Bytes, 80)
    Assert-A3D ($n -eq 4 -and [long]$Bytes.Length -eq (84L + 50L * [long]$n)) 'stl_count_size_identity'
    for ($i = 0; $i -lt $n; $i++) {
        for ($j = 0; $j -lt 12; $j++) {
            $v = [BitConverter]::ToSingle($Bytes, (84 + 50 * $i + 4 * $j))
            Assert-A3D (-not [single]::IsNaN($v) -and -not [single]::IsInfinity($v)) 'stl_nonfinite_coordinate'
        }
    }
}
function Confirm-A3DGcode([byte[]]$Bytes) {
    $text = [Text.Encoding]::ASCII.GetString($Bytes)
    Assert-A3D ($text.StartsWith(';CHAPPY-ARTIFICIAL-GCODE') -and
                $text.Contains('G28') -and $text.Contains('M84')) 'gcode_artificial_marker'
}

$first = New-ChappyA3DCleanFixture -Seed 202611
$again = New-ChappyA3DCleanFixture -Seed 202611
Assert-A3D ($first.image.Length -eq 2097152 -and
            $first.oracle.Count -eq 3 -and
            $first.layout.kind -eq 'synthetic_FAT32_like_not_standards_volume') 'bounded_fixture_schema'
Assert-A3D ((Get-A3DSha256 $first.image) -ceq (Get-A3DSha256 $again.image)) 'deterministic_full_image'
# Re-check deterministic oracle directly using stable indices (no source-image data provided to validator).
for ($i = 0; $i -lt 3; $i++) {
    Assert-A3D ($first.oracle[$i].sha256 -ceq $again.oracle[$i].sha256) 'stable_oracle_entry_hash'
}
$before = Get-A3DSha256 $first.image
$expected = @('gcode', '3mf', 'stl_binary')
for ($i = 0; $i -lt $first.oracle.Count; $i++) {
    $truth = $first.oracle[$i]
    Assert-A3D ($truth.format -eq $expected[$i]) 'expected_format_order'
    # Only synthetic image and its invented short-name label are given to independent FAT reader.
    [byte[]]$bytes = Read-A3DRecord $first.image $truth.shortName
    Assert-A3D ($bytes.Length -eq $truth.lengthBytes) 'file_size_round_trip'
    Assert-A3D ((Get-A3DSha256 $bytes) -ceq $truth.sha256) 'original_synthetic_sha256_exact'
    $n = 0
    foreach ($part in $truth.extents) {
        Assert-A3D ($part.lengthBytes -gt 0 -and $part.lengthBytes -le 512 -and
                    $part.offsetBytes -ge 0 -and ($part.offsetBytes + $part.lengthBytes) -le $first.image.Length) 'oracle_extent_bounds'
        $n += $part.lengthBytes
    }
    Assert-A3D ($n -eq $truth.lengthBytes) 'oracle_extent_sum'
    switch ($truth.format) {
        '3mf' { Confirm-A3D3Mf $bytes }
        'stl_binary' { Confirm-A3DStl $bytes }
        'gcode' { Confirm-A3DGcode $bytes }
    }
    Write-Host ('A3D CLEAN synthetic_only format={0} length={1} exact_sha256=true' -f $truth.format,$bytes.Length)
}
Assert-A3D ((Get-A3DSha256 $first.image) -ceq $before) 'in_memory_source_not_modified'

# Negative control: an independently mutated *copy* must not be byte-identical to the original oracle.
[byte[]]$mutated = [byte[]]$first.image.Clone()
$mutated[60928 + 84] = [byte]($mutated[60928 + 84] -bxor 0x01)
[byte[]]$badStl = Read-A3DRecord $mutated 'MESH    STL'
Assert-A3D ((Get-A3DSha256 $badStl) -cne $first.oracle[2].sha256) 'content_mutation_not_silent'
Assert-A3D ((Get-A3DSha256 $first.image) -ceq $before) 'source_immutable_after_mutation'

# Disposable artificial on-disk control; no command-line input path or device is accepted.
$temp = Join-Path ([IO.Path]::GetTempPath()) ('ChappyA3DClean_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
    $file = Join-Path $temp 'synthetic_clean.img'
    [IO.File]::WriteAllBytes($file, $first.image)
    $diskBefore = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    $stream = [IO.File]::Open($file, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        Assert-A3D ($stream.CanRead -and $stream.CanSeek -and -not $stream.CanWrite) 'disposable_source_readonly'
        [byte[]]$probe = New-Object 'byte[]' 16
        [void]$stream.Read($probe, 0, $probe.Length)
    } finally { $stream.Dispose() }
    Assert-A3D ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ceq $diskBefore) 'disposable_disk_sha_unchanged'
} finally {
    if ([IO.Directory]::Exists($temp)) { [IO.Directory]::Delete($temp, $true) }
}
Write-Host 'PASS: A3D P0.1 clean 3MF/STL/G-code, oracle SHA256, bounded FAT-chain round-trip, synthetic corruption negative, unchanged source.'
Write-Host 'This is not a real FAT32-sized filesystem or actual user-file recovery test.'
