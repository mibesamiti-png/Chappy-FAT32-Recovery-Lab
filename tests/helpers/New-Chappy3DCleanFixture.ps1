#Requires -Version 5.1
# Team A only: deterministic artificial 3D-print fixture generator.
# This helper never reads a path/device, opens a real file, or repairs anything.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression

function Get-A3DSha256([byte[]]$Bytes) {
    $h = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($h.ComputeHash($Bytes)).Replace('-', '') }
    finally { $h.Dispose() }
}
function Set-A3DUint16([byte[]]$Buffer, [int]$Offset, [uint16]$Value) {
    [Array]::Copy([BitConverter]::GetBytes($Value), 0, $Buffer, $Offset, 2)
}
function Set-A3DUint32([byte[]]$Buffer, [int]$Offset, [uint32]$Value) {
    [Array]::Copy([BitConverter]::GetBytes($Value), 0, $Buffer, $Offset, 4)
}
function Copy-A3DBytes([byte[]]$Target, [int]$Offset, [byte[]]$Bytes) {
    if ($Offset -lt 0 -or [long]$Offset + $Bytes.Length -gt $Target.Length) {
        throw 'Synthetic fixture exceeds fixed image capacity'
    }
    [Array]::Copy($Bytes, 0, $Target, $Offset, $Bytes.Length)
}
function New-A3D3MfBytes {
    $contentTypes = '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/></Types>'
    $relationships = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="r0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="/3D/3dmodel.model"/></Relationships>'
    $model = '<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02"><resources><object id="1" type="model"><mesh><vertices><vertex x="0" y="0" z="0"/><vertex x="1" y="0" z="0"/><vertex x="0" y="1" z="0"/><vertex x="0" y="0" z="1"/></vertices><triangles><triangle v1="0" v2="2" v3="1"/><triangle v1="0" v2="1" v3="3"/><triangle v1="0" v2="3" v3="2"/><triangle v1="1" v2="2" v3="3"/></triangles></mesh></object></resources><build><item objectid="1"/></build></model>'
    $parts = @(
        [pscustomobject]@{ name = '[Content_Types].xml'; data = $contentTypes },
        [pscustomobject]@{ name = '_rels/.rels'; data = $relationships },
        [pscustomobject]@{ name = '3D/3dmodel.model'; data = $model }
    )
    $ms = New-Object IO.MemoryStream
    $zip = [IO.Compression.ZipArchive]::new($ms, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($part in $parts) {
            $entry = $zip.CreateEntry($part.name, [IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = [DateTimeOffset]::new(2020, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
            $es = $entry.Open()
            try {
                [byte[]]$raw = [Text.Encoding]::UTF8.GetBytes($part.data)
                $es.Write($raw, 0, $raw.Length)
            } finally { $es.Dispose() }
        }
    } finally { $zip.Dispose() }
    try { return ,$ms.ToArray() }
    finally { $ms.Dispose() }
}
function New-A3DBinaryStlBytes {
    # Four oriented faces of an artificial tetrahedron, not private model data.
    $k = [single](1.0 / [Math]::Sqrt(3.0))
    $tris = @(
        [pscustomobject]@{ n = @(0,0,-1); v = @(0,0,0, 0,1,0, 1,0,0) },
        [pscustomobject]@{ n = @(0,-1,0); v = @(0,0,0, 1,0,0, 0,0,1) },
        [pscustomobject]@{ n = @(-1,0,0); v = @(0,0,0, 0,0,1, 0,1,0) },
        [pscustomobject]@{ n = @($k,$k,$k); v = @(1,0,0, 0,1,0, 0,0,1) }
    )
    $ms = New-Object IO.MemoryStream
    $writer = [IO.BinaryWriter]::new($ms)
    try {
        [byte[]]$header = New-Object 'byte[]' 80
        [byte[]]$tag = [Text.Encoding]::ASCII.GetBytes('CHAPPY ARTIFICIAL TETRAHEDRON STL')
        [Array]::Copy($tag, 0, $header, 0, $tag.Length)
        $writer.Write($header)
        $writer.Write([uint32]$tris.Count)
        foreach ($t in $tris) {
            foreach ($f in $t.n) { $writer.Write([single]$f) }
            foreach ($f in $t.v) { $writer.Write([single]$f) }
            $writer.Write([uint16]0)
        }
        $writer.Flush()
        return ,$ms.ToArray()
    } finally { $writer.Dispose(); $ms.Dispose() }
}
function Set-A3DRootEntry([byte[]]$Image, [int]$Index, [string]$ShortName,
                           [uint16]$FirstCluster, [uint32]$Size) {
    if ($ShortName.Length -ne 11 -or $Index -lt 0 -or $Index -gt 2) {
        throw 'Invalid bounded synthetic directory entry'
    }
    $off = 57856 + (32 * $Index)
    Copy-A3DBytes $Image $off ([Text.Encoding]::ASCII.GetBytes($ShortName))
    $Image[$off + 11] = 0x20
    Set-A3DUint16 $Image ($off + 26) $FirstCluster
    Set-A3DUint32 $Image ($off + 28) $Size
}
function New-A3DOracle([string]$Id, [string]$Format, [string]$ShortName,
                       [byte[]]$Content, [int]$StartCluster) {
    $parts = New-Object 'System.Collections.Generic.List[object]'
    $left = $Content.Length
    $cluster = $StartCluster
    while ($left -gt 0) {
        if ($parts.Count -ge 4) { throw 'Artificial file exceeds reserved clusters' }
        $n = [int][Math]::Min(512, $left)
        $parts.Add([pscustomobject]@{
            cluster = $cluster
            offsetBytes = [int](57856 + (($cluster - 2) * 512))
            lengthBytes = $n
        })
        $left -= $n
        $cluster++
    }
    return [pscustomobject]@{
        artificialId = $Id
        format = $Format
        shortName = $ShortName
        firstCluster = $StartCluster
        lengthBytes = $Content.Length
        sha256 = Get-A3DSha256 $Content
        extents = @($parts.ToArray())
    }
}
function New-ChappyA3DCleanFixture {
    [CmdletBinding()]param([ValidateRange(1, 999999)][int]$Seed = 202611)
    if (-not [BitConverter]::IsLittleEndian) { throw 'Fixture writer requires little-endian Windows' }
    $gcodeLines = @(
        ';CHAPPY-ARTIFICIAL-GCODE'
        'G28'
        ('G1 X{0} Y10 F1000' -f (10 + ($Seed % 7)))
        'G1 X20 Y20'
        'M84'
    )
    [byte[]]$gcode = [Text.Encoding]::ASCII.GetBytes(([string]::Join([char]10, $gcodeLines) + [char]10))
    [byte[]]$mf = New-A3D3MfBytes
    [byte[]]$stl = New-A3DBinaryStlBytes
    if ($gcode.Length -gt 512 -or $mf.Length -gt 2048 -or $stl.Length -gt 512) {
        throw 'Generated artificial file exceeds reserved capacity'
    }

    # Fast test image: 2 MiB FAT32-LIKE only, NOT a standards-sized FAT32 volume.
    [byte[]]$image = New-Object 'byte[]' 2097152
    $image[450] = 0x0C
    Set-A3DUint32 $image 454 ([uint32]1)
    Set-A3DUint32 $image 458 ([uint32]4095)
    $image[510] = 0x55; $image[511] = 0xAA
    [byte[]]$boot = New-Object 'byte[]' 512
    $boot[0] = 0xEB; $boot[1] = 0x58; $boot[2] = 0x90
    Set-A3DUint16 $boot 11 ([uint16]512)
    $boot[13] = 1
    Set-A3DUint16 $boot 14 ([uint16]32)
    $boot[16] = 2; $boot[21] = 0xF8
    Set-A3DUint32 $boot 32 ([uint32]4095)
    Set-A3DUint32 $boot 36 ([uint32]40)
    Set-A3DUint32 $boot 44 ([uint32]2)
    $boot[510] = 0x55; $boot[511] = 0xAA
    Copy-A3DBytes $image 512 $boot

    [byte[]]$fat = New-Object 'byte[]' 20480
    Set-A3DUint32 $fat 0 ([uint32]0x0FFFFFF8)
    Set-A3DUint32 $fat 4 ([uint32]0x0FFFFFFF)
    Set-A3DUint32 $fat 8 ([uint32]0x0FFFFFFF)
    Set-A3DUint32 $fat 12 ([uint32]0x0FFFFFFF)
    $mfClusters = [int][Math]::Ceiling($mf.Length / 512.0)
    for ($i = 0; $i -lt $mfClusters; $i++) {
        $next = if ($i -eq ($mfClusters - 1)) { [uint32]0x0FFFFFFF } else { [uint32](5 + $i) }
        Set-A3DUint32 $fat (4 * (4 + $i)) $next
    }
    Set-A3DUint32 $fat 32 ([uint32]0x0FFFFFFF)
    Copy-A3DBytes $image 16896 $fat
    Copy-A3DBytes $image 37376 $fat

    Set-A3DRootEntry $image 0 'PRINT   GCO' ([uint16]3) ([uint32]$gcode.Length)
    Set-A3DRootEntry $image 1 'MODEL   3MF' ([uint16]4) ([uint32]$mf.Length)
    Set-A3DRootEntry $image 2 'MESH    STL' ([uint16]8) ([uint32]$stl.Length)
    Copy-A3DBytes $image 58368 $gcode
    Copy-A3DBytes $image 58880 $mf
    Copy-A3DBytes $image 60928 $stl
    $oracle = @(
        (New-A3DOracle 'artificial_gcode' 'gcode' 'PRINT   GCO' $gcode 3),
        (New-A3DOracle 'artificial_3mf' '3mf' 'MODEL   3MF' $mf 4),
        (New-A3DOracle 'artificial_binary_stl' 'stl_binary' 'MESH    STL' $stl 8)
    )
    return [pscustomobject]@{
        generatorVersion = 'A3D-clean-r1'
        seed = $Seed
        image = $image
        oracle = $oracle
        layout = [pscustomobject]@{
            kind = 'synthetic_FAT32_like_not_standards_volume'
            imageBytes = $image.Length
            clusterBytes = 512
            rootOffsetBytes = 57856
            fat1OffsetBytes = 16896
            fat2OffsetBytes = 37376
        }
    }
}