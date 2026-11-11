#requires -Version 5.1
<#
Quick, bounded, read-only FAT32 IMG triage. No recursive traversal, writes, or repair.
Usage:
  & ".\Chappy_FAT32_QuickProbe_v0.5.1.ps1" -ImagePath "C:\SD_Backups\microSD_disk1.img"
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ImagePath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$stream = $null
function Read-Bytes([System.IO.Stream]$s, [long]$offset, [int]$length) {
    if ($offset -lt 0 -or $length -lt 0 -or $offset -gt ($s.Length - $length)) {
        throw "Out of IMG bounds: offset=$offset, length=$length"
    }
    [void]$s.Seek($offset, [System.IO.SeekOrigin]::Begin)
    $buf = New-Object byte[] $length
    $got = 0
    while ($got -lt $length) {
        $n = $s.Read($buf, $got, $length - $got)
        if ($n -le 0) { throw "Unexpected end of IMG at $offset" }
        $got += $n
    }
    return ,$buf
}
function U16([byte[]]$b, [int]$offset) { return [BitConverter]::ToUInt16($b, $offset) }
function U32([byte[]]$b, [int]$offset) { return [BitConverter]::ToUInt32($b, $offset) }
function IsAllZero([byte[]]$b) {
    foreach ($x in $b) { if ($x -ne 0) { return $false } }
    return $true
}
try {
    $resolved = (Resolve-Path -LiteralPath $ImagePath).ProviderPath
    if (-not [IO.File]::Exists($resolved)) { throw 'Image path is not a file' }
    $stream = [IO.File]::Open($resolved, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    Write-Host '=== Chappy FAT32 Quick Probe v0.5.1 (READ ONLY) ==='
    Write-Host "IMG: $resolved"
    Write-Host "IMG bytes: $($stream.Length)"
    $mbr = Read-Bytes $stream 0 512
    if ($mbr[510] -ne 0x55 -or $mbr[511] -ne 0xAA) { throw 'MBR signature missing' }
    $part = $null
    for ($i = 0; $i -lt 4; $i++) {
        $off = 446 + 16 * $i
        $type = [int]$mbr[$off + 4]
        $lba = [long](U32 $mbr ($off + 8))
        $count = [long](U32 $mbr ($off + 12))
        if (($type -eq 11 -or $type -eq 12) -and $count -gt 0) {
            if ($null -ne $part) { throw 'Multiple FAT32 partitions; refusing ambiguous layout' }
            $part = @{type=$type; lba=$lba; count=$count}
        }
    }
    if ($null -eq $part) { throw 'No FAT32-type MBR partition found' }
    $partStart = [long]$part.lba * 512L
    $boot = Read-Bytes $stream $partStart 512
    if ($boot[510] -ne 0x55 -or $boot[511] -ne 0xAA) { throw 'FAT32 boot sector signature missing' }
    $bps = [long](U16 $boot 11)
    $spc = [long]$boot[13]
    $reserved = [long](U16 $boot 14)
    $nfats = [long]$boot[16]
    $fatSectors = [long](U32 $boot 36)
    $totalSectors = [long](U32 $boot 32)
    $rootCluster = [long](U32 $boot 44)
    if ($bps -ne 512 -or $spc -lt 1 -or $spc -gt 128 -or (($spc -band ($spc - 1)) -ne 0) -or
        $reserved -lt 1 -or $nfats -ne 2 -or $fatSectors -lt 1 -or $totalSectors -lt 1) {
        throw 'Implausible FAT32 geometry: stopping before FAT reads'
    }
    $dataSectors = $totalSectors - $reserved - $nfats * $fatSectors
    if ($dataSectors -lt 1) { throw 'Invalid data-region size' }
    $clusterCount = [long][math]::Floor($dataSectors / $spc)
    $maxCluster = $clusterCount + 1L
    if ($rootCluster -lt 2 -or $rootCluster -gt $maxCluster) { throw 'Root cluster out of valid range' }
    $fatBytes = $fatSectors * $bps
    if ($fatBytes -lt ($clusterCount + 2) * 4L) { throw 'FAT too short for cluster count' }
    $fat1Start = $partStart + $reserved * $bps
    $fat2Start = $fat1Start + $fatBytes
    $dataStart = $fat2Start + $fatBytes
    $rootOffset = $dataStart + ($rootCluster - 2) * $spc * $bps
    if ($partStart + $totalSectors * $bps -gt $stream.Length) { throw 'Partition exceeds IMG' }
    Write-Host "Partition offset: $partStart"
    Write-Host "Cluster size: $($spc * $bps) bytes; clusters: $clusterCount; root cluster: $rootCluster"
    Write-Host "FAT1 offset: $fat1Start; FAT2 offset: $fat2Start; root data offset: $rootOffset"
    $fatSamples = @()
    foreach ($f in @(@{name='FAT1';at=$fat1Start}, @{name='FAT2';at=$fat2Start})) {
        $sample = Read-Bytes $stream ([long]$f.at) 32
        $e0 = ([long](U32 $sample 0) -band 0x0FFFFFFFL)
        $e1 = ([long](U32 $sample 4) -band 0x0FFFFFFFL)
        $e2 = ([long](U32 $sample 8) -band 0x0FFFFFFFL)
        $valid = (($e0 -band 0x0FFFFFF8L) -eq 0x0FFFFFF8L -and $e1 -ge 0x0FFFFFF8L)
        Write-Host "--- $($f.name) ---"
        Write-Host "First 32 bytes: $([BitConverter]::ToString($sample))"
        Write-Host ('Entry0: 0x{0:X8}; Entry1: 0x{1:X8}; Root-chain entry: 0x{2:X8}; reserved entries plausible: {3}' -f $e0,$e1,$e2,$valid)
        Write-Host "All first 32 bytes zero: $(IsAllZero $sample)"
        $fatSamples += ,$sample
    }
    $matching = ([BitConverter]::ToString($fatSamples[0]) -eq [BitConverter]::ToString($fatSamples[1]))
    Write-Host "FAT1/FAT2 first 32 bytes identical: $matching"
    $root = Read-Bytes $stream $rootOffset 512
    Write-Host "Root directory first 32 bytes: $([BitConverter]::ToString($root,0,32))"
    Write-Host "Root directory first 512 bytes all zero: $(IsAllZero $root)"
    Write-Host 'DONE. No image writes, source device access, or JSON output.'
} catch {
    Write-Host "STOPPED: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    if ($null -ne $stream) { $stream.Dispose() }
}