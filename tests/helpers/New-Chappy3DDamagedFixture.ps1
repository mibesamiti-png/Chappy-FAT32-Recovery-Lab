#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'New-Chappy3DCleanFixture.ps1')

function Get-A3DModelPayloadOffset([byte[]]$Image, $Truth) {
    # The P0.1 generator places this ZIP contiguously and writes three local
    # headers with sizes populated by ZipArchive on a seekable memory stream.
    $cursor = [int]$Truth.extents[0].offsetBytes
    $end = $cursor + $Truth.lengthBytes
    for ($entry = 0; $entry -lt 3; $entry++) {
        if ($cursor + 30 -gt $end -or [BitConverter]::ToUInt32($Image, $cursor) -ne 0x04034B50) {
            throw 'Unexpected local header in generated 3MF'
        }
        $flags = [BitConverter]::ToUInt16($Image, $cursor + 6)
        $method = [BitConverter]::ToUInt16($Image, $cursor + 8)
        $size = [BitConverter]::ToUInt32($Image, $cursor + 18)
        $nameLength = [BitConverter]::ToUInt16($Image, $cursor + 26)
        $extraLength = [BitConverter]::ToUInt16($Image, $cursor + 28)
        $data = $cursor + 30 + $nameLength + $extraLength
        if (($flags -band 8) -ne 0 -or $method -ne 8 -or $size -eq 0 -or
            ([long]$data + $size) -gt $end) {
            throw 'Unexpected compressed member in generated 3MF'
        }
        $name = [Text.Encoding]::ASCII.GetString($Image, $cursor + 30, $nameLength)
        if ($name -ceq '3D/3dmodel.model') {
            return $data + ($size -shr 1)
        }
        $cursor = [int]($data + $size)
    }
    throw 'Generated 3MF model member is missing'
}

function New-ChappyA3DDamagedFixture {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('M00', 'M01', 'M02', 'M03', 'M04', 'M04L', 'M05', 'M05L', 'P01', 'P02', 'P03', 'X02', 'M02-P02')]
        [string]$Case,
        [ValidateRange(1, 999999)][int]$Seed = 202611
    )

    # Construct the source internally. No external image, stream, or offset
    # can reach the mutation code. ToArray returns an independent copy.
    $clean = New-ChappyA3DCleanFixture -Seed $Seed -IncludeFormatControls:($Case -eq 'M04L')
    $source = [IO.MemoryStream]::new($clean.image, $false)
    try {
        $sourceHash = Get-A3DSha256 $clean.image
        [byte[]]$image = $source.ToArray()
        $changes = @()
        $removedRange = $null
        $affectedId = $null
        $layer = 'none'
        $caseId = $Case.ToUpperInvariant()
        switch ($caseId) {
            'M01' {
                $truth = $clean.oracle[1]
                if ($truth.extents.Count -ne 2) { throw 'M01 requires a two-cluster generated 3MF' }
                $layer = 'valid_fragmentation'
                $offset = $clean.layout.fat1OffsetBytes
                # Move the second cluster from 5 to unused cluster 7.
                # Include both FATs and the bounded relocation window.
                $replacement = [byte[]]$image[$offset..60927]
                [Array]::Copy($image, 59392, $replacement, (60416 - $offset), 512)
                [Array]::Clear($replacement, (59392 - $offset), 512)
                foreach ($fat in @($clean.layout.fat1OffsetBytes, $clean.layout.fat2OffsetBytes)) {
                    Set-A3DUint32 $replacement ($fat - $offset + 16) 7
                    Set-A3DUint32 $replacement ($fat - $offset + 20) 0
                    Set-A3DUint32 $replacement ($fat - $offset + 28) 0x0FFFFFFF
                }
            }
            'M02' {
                $truth = $clean.oracle[1]
                $layer = 'fat1'
                $offset = $clean.layout.fat1OffsetBytes + (4 * $truth.firstCluster)
                # Mark the first 3MF chain link free in FAT1 only.
                $replacement = [byte[]]@(0, 0, 0, 0)
            }
            'M03' {
                $truth = $clean.oracle[1]
                if ($truth.extents.Count -ne 2) { throw 'M03 requires a two-cluster generated 3MF' }
                $layer = 'both_fat_cycle'
                # The second cluster points back to the first in each FAT.
                $offset = $clean.layout.fat1OffsetBytes + 20
                $last = $clean.layout.fat2OffsetBytes + 23
                $replacement = [byte[]]$image[$offset..$last]
                Set-A3DUint32 $replacement 0 4
                Set-A3DUint32 $replacement ($last - $offset - 3) 4
            }
            'M04' {
                $truth = $clean.oracle[1]
                $layer = 'directory_file_size'
                # Second root entry, four-byte size field.
                $offset = $clean.layout.rootOffsetBytes + 32 + 28
                $replacement = [byte[]]::new(4)
            }
            'M04L' {
                $truth = $clean.oracle[3]
                $layer = 'directory_lfn_checksum'
                $offset = $clean.layout.rootOffsetBytes + 3 * 32 + 13
                $replacement = [byte[]]@($image[$offset] -bxor 1)
            }
            'M05' {
                $truth = $clean.oracle[1]
                if ($truth.extents.Count -ne 2) { throw 'M05 requires a two-cluster generated 3MF' }
                $layer = 'both_fat_cross_link'
                # Link the 3MF into the STL's first cluster in each FAT.
                $offset = $clean.layout.fat1OffsetBytes + 16
                $last = $clean.layout.fat2OffsetBytes + 19
                $replacement = [byte[]]$image[$offset..$last]
                Set-A3DUint32 $replacement 0 $clean.oracle[2].firstCluster
                Set-A3DUint32 $replacement ($last - $offset - 3) $clean.oracle[2].firstCluster
            }
            'M05L' {
                $truth = $clean.oracle[1]
                if ($truth.extents.Count -ne 2) { throw 'M05L requires a two-cluster generated 3MF' }
                $layer = '3mf_tail_erased'
                $offset = $truth.extents[1].offsetBytes
                $replacement = [byte[]]::new($truth.extents[1].lengthBytes)
            }
            'P01' {
                $truth = $clean.oracle[1]
                $layer = '3mf_zip_eocd'
                # This generated ZIP has no comment. Erase its EOCD record.
                $offset = $truth.extents[0].offsetBytes + $truth.lengthBytes - 22
                if ([BitConverter]::ToUInt32($image, $offset) -ne 0x06054B50) {
                    throw 'Unexpected end record in generated 3MF'
                }
                $replacement = [byte[]]::new(22)
            }
            'P02' {
                $truth = $clean.oracle[1]
                $layer = '3mf_model_payload'
                $offset = Get-A3DModelPayloadOffset $image $truth
                $replacement = [byte[]]@($image[$offset] -bxor 1)
            }
            'P03' {
                $truth = $clean.oracle[2]
                $layer = 'stl_vertex_payload'
                # First facet begins at 84. Skip its 12-byte normal.
                $offset = $truth.extents[0].offsetBytes + 84 + 12
                $replacement = [byte[]]@($image[$offset] -bxor 1)
            }
            'M02-P02' {
                $truth = $clean.oracle[1]
                $layer = 'fat1_and_3mf_model_payload'
                $offset = $clean.layout.fat1OffsetBytes + (4 * $truth.firstCluster)
                $payloadOffset = Get-A3DModelPayloadOffset $image $truth
                $replacement = [byte[]]$image[$offset..$payloadOffset]
                [Array]::Clear($replacement, 0, 4)
                $replacement[$payloadOffset - $offset] = $image[$payloadOffset] -bxor 1
            }
            'X02' {
                $truth = $clean.oracle[1]
                $layer = 'image_truncation'
                # Keep the directory and FATs, but end inside the 3MF payload.
                $end = $truth.extents[0].offsetBytes + 512 + 128
                $removedRange = [pscustomobject]@{
                    offsetBytes = $end
                    lengthBytes = $image.Length - $end
                }
                [Array]::Resize([ref]$image, $end)
            }
        }
        if ($caseId -eq 'X02') {
            $affectedId = $truth.artificialId
        } elseif ($caseId -ne 'M00') {
            $affectedId = $truth.artificialId
            $changes = @(for ($i = 0; $i -lt $replacement.Length; $i++) {
                $at = $offset + $i
                if ($image[$at] -ne $replacement[$i]) {
                    [pscustomobject]@{
                        offsetBytes = $at
                        beforeByte = $image[$at]
                        afterByte = $replacement[$i]
                    }
                    $image[$at] = $replacement[$i]
                }
            })
            if ($changes.Count -eq 0) { throw 'Synthetic mutation changed no bytes' }
        }
        $sourceHashAfter = Get-A3DSha256 $clean.image
        if ($sourceHashAfter -cne $sourceHash) { throw 'Synthetic source changed during mutation' }
        return [pscustomobject]@{
            image = $image
            manifest = [pscustomobject]@{
                mutationVersion = 'A3D-damage-r1'
                generatorVersion = $clean.generatorVersion
                seed = $Seed
                caseId = $caseId
                layer = $layer
                affectedArtificialId = $affectedId
                imageBytes = $image.Length
                sourceSha256Before = $sourceHash
                sourceSha256After = $sourceHashAfter
                imageSha256 = Get-A3DSha256 $image
                changes = $changes
                removedRange = $removedRange
            }
        }
    } finally { $source.Dispose() }
}
