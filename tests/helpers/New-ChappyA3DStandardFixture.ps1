#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'New-Chappy3DCleanFixture.ps1')

function New-ChappyA3DStandardFixture {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [ValidateRange(1, 999999)][int]$Seed = 202611,
        [ValidateSet(1, 2)][int]$SectorsPerCluster = 1,
        [switch]$Fragment3Mf
    )

    $clean = New-ChappyA3DCleanFixture -Seed $Seed
    $sectorBytes = 512
    $partitionStart = 1
    $reserved = 32
    # Leave 16 data clusters above the FAT16/FAT32 classification boundary.
    # Geometry reference: Microsoft FAT32 specification v1.03, pp. 13–15, 21–22.
    $clusterCount = 65541
    $clusterBytes = $SectorsPerCluster * $sectorBytes
    $fatSectors = [int][Math]::Ceiling(4 * ($clusterCount + 2) / [double]$sectorBytes)
    $partitionSectors = $reserved + 2 * $fatSectors + $clusterCount * $SectorsPerCluster
    $image = [byte[]]::new(($partitionStart + $partitionSectors) * $sectorBytes)
    $fat1 = ($partitionStart + $reserved) * $sectorBytes
    $fat2 = $fat1 + $fatSectors * $sectorBytes
    $dataStart = $fat2 + $fatSectors * $sectorBytes

    $image[450] = 0x0C
    Set-A3DUint32 $image 454 $partitionStart
    Set-A3DUint32 $image 458 $partitionSectors
    Set-A3DUint16 $image 510 0xAA55

    $boot = [byte[]]::new($sectorBytes)
    Copy-A3DBytes $boot 0 ([byte[]]@(0xEB, 0x58, 0x90))
    Copy-A3DBytes $boot 3 ([Text.Encoding]::ASCII.GetBytes('CHAPPY  '))
    Set-A3DUint16 $boot 11 $sectorBytes
    $boot[13] = $SectorsPerCluster
    Set-A3DUint16 $boot 14 $reserved
    $boot[16] = 2
    $boot[21] = 0xF8
    Set-A3DUint16 $boot 24 63
    Set-A3DUint16 $boot 26 255
    Set-A3DUint32 $boot 28 $partitionStart
    Set-A3DUint32 $boot 32 $partitionSectors
    Set-A3DUint32 $boot 36 $fatSectors
    Set-A3DUint32 $boot 44 2
    Set-A3DUint16 $boot 48 1
    Set-A3DUint16 $boot 50 6
    $boot[64] = 0x80
    $boot[66] = 0x29
    Set-A3DUint32 $boot 67 $Seed
    Copy-A3DBytes $boot 71 ([Text.Encoding]::ASCII.GetBytes('NO NAME    '))
    Copy-A3DBytes $boot 82 ([Text.Encoding]::ASCII.GetBytes('FAT32   '))
    Copy-A3DBytes $boot 90 ([byte[]]@(0xFA, 0xF4, 0xEB, 0xFD))
    Set-A3DUint16 $boot 510 0xAA55
    Copy-A3DBytes $image ($partitionStart * $sectorBytes) $boot
    Copy-A3DBytes $image (($partitionStart + 6) * $sectorBytes) $boot

    $allocated = 1
    $fat = [byte[]]::new($fatSectors * $sectorBytes)
    Set-A3DUint32 $fat 0 0x0FFFFFF8
    Set-A3DUint32 $fat 4 0x0FFFFFFF
    Set-A3DUint32 $fat 8 0x0FFFFFFF
    $oracle = @(foreach ($file in $clean.oracle) {
        $content = [byte[]]::new($file.lengthBytes)
        $written = 0
        foreach ($extent in $file.extents) {
            [Array]::Copy($clean.image, $extent.offsetBytes, $content, $written, $extent.lengthBytes)
            $written += $extent.lengthBytes
        }
        $chain = @($file.firstCluster)
        if ($content.Length -gt $clusterBytes) {
            if ($Fragment3Mf) { $chain += 7 }
            else { $chain += $file.firstCluster + 1 }
        }
        if ($content.Length -gt $chain.Count * $clusterBytes) { throw 'Synthetic file exceeds reserved clusters' }
        $allocated += $chain.Count
        $extents = @(for ($i = 0; $i -lt $chain.Count; $i++) {
            $cluster = $chain[$i]
            $next = if ($i + 1 -lt $chain.Count) { $chain[$i + 1] } else { 0x0FFFFFFF }
            Set-A3DUint32 $fat (4 * $cluster) $next
            $offset = $dataStart + ($cluster - 2) * $clusterBytes
            $length = [Math]::Min($clusterBytes, $content.Length - $i * $clusterBytes)
            [Array]::Copy($content, ($i * $clusterBytes), $image, $offset, $length)
            [pscustomobject]@{ cluster = $cluster; offsetBytes = $offset; lengthBytes = $length }
        })
        [pscustomobject]@{ shortName = $file.shortName; lengthBytes = $file.lengthBytes
            sha256 = $file.sha256; extents = $extents }
    })
    [Array]::Copy($clean.image, $clean.layout.rootOffsetBytes, $image, $dataStart, 512)
    Copy-A3DBytes $image $fat1 $fat
    Copy-A3DBytes $image $fat2 $fat

    $info = [byte[]]::new($sectorBytes)
    Set-A3DUint32 $info 0 0x41615252
    Set-A3DUint32 $info 484 0x61417272
    Set-A3DUint32 $info 488 ($clusterCount - $allocated)
    Set-A3DUint32 $info 492 6
    Set-A3DUint16 $info 510 0xAA55
    Copy-A3DBytes $image (($partitionStart + 1) * $sectorBytes) $info
    Copy-A3DBytes $image (($partitionStart + 7) * $sectorBytes) $info

    [pscustomobject]@{ generatorVersion = 'A3D-standard-r1'; seed = $Seed; image = $image; oracle = $oracle }
}
