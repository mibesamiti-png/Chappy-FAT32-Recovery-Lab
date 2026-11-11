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
        [Parameter(Mandatory)][ValidateSet('M00', 'M02', 'P02', 'P03')][string]$Case,
        [ValidateRange(1, 999999)][int]$Seed = 202611
    )

    # Construct the source internally. No external image, stream, or offset
    # can reach the mutation code. ToArray returns an independent copy.
    $clean = New-ChappyA3DCleanFixture -Seed $Seed
    $source = [IO.MemoryStream]::new($clean.image, $false)
    try {
        $sourceHash = Get-A3DSha256 $clean.image
        [byte[]]$image = $source.ToArray()
        $changes = @()
        $affectedId = $null
        $layer = 'none'
        $caseId = $Case.ToUpperInvariant()
        switch ($caseId) {
            'M02' {
                $truth = $clean.oracle[1]
                $layer = 'fat1'
                $offset = $clean.layout.fat1OffsetBytes + (4 * $truth.firstCluster)
                # Mark the first 3MF chain link free in FAT1 only.
                $replacement = [byte[]]@(0, 0, 0, 0)
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
        }
        if ($caseId -ne 'M00') {
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
            }
        }
    } finally { $source.Dispose() }
}
