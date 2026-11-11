#Requires -Version 5.1
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')

function Assert-StandardFixture([bool]$Ok, [string]$Reason) {
    if (-not $Ok) { throw "A3D_STANDARD_FAIL: $Reason" }
}

function Read-StandardFixtureBytes([IO.Stream]$Source, [long]$Offset, [int]$Count) {
    Assert-StandardFixture ($Source.CanRead -and $Source.CanSeek -and -not $Source.CanWrite) 'source_not_read_only'
    Assert-StandardFixture ($Offset -ge 0 -and $Count -gt 0 -and $Count -le 512KB -and
        $Offset -le $Source.Length - $Count) 'range_outside_source'
    $Source.Position = $Offset
    $bytes = [byte[]]::new($Count)
    $read = 0
    while ($read -lt $Count) {
        $n = $Source.Read($bytes, $read, $Count - $read)
        Assert-StandardFixture ($n -gt 0) 'short_read'
        $read += $n
    }
    return ,$bytes
}

function Read-StandardFixtureVolume([IO.Stream]$Source) {
    $mbr = Read-StandardFixtureBytes $Source 0 512
    Assert-StandardFixture ([BitConverter]::ToUInt16($mbr, 510) -eq 0xAA55 -and $mbr[450] -eq 0x0C) 'partition_signature'
    $start = [long][BitConverter]::ToUInt32($mbr, 454) * 512
    $count = [long][BitConverter]::ToUInt32($mbr, 458)
    Assert-StandardFixture ($start -ge 512 -and $start + $count * 512 -eq $Source.Length) 'partition_extent'
    $vbr = Read-StandardFixtureBytes $Source $start 512
    $bytesPerSector = [BitConverter]::ToUInt16($vbr, 11)
    $spc = $vbr[13]
    $reserved = [BitConverter]::ToUInt16($vbr, 14)
    $fatCount = $vbr[16]
    $fatSectors = [long][BitConverter]::ToUInt32($vbr, 36)
    $total = [BitConverter]::ToUInt32($vbr, 32)
    Assert-StandardFixture ([BitConverter]::ToUInt16($vbr, 510) -eq 0xAA55 -and $bytesPerSector -eq 512 -and
        $spc -in @(1, 2) -and $reserved -eq 32 -and $fatCount -eq 2 -and $total -eq $count -and
        [BitConverter]::ToUInt16($vbr, 17) -eq 0 -and [BitConverter]::ToUInt16($vbr, 22) -eq 0 -and
        [BitConverter]::ToUInt16($vbr, 19) -eq 0 -and [BitConverter]::ToUInt32($vbr, 28) * 512L -eq $start) 'BPB'
    $firstDataSector = $reserved + $fatCount * $fatSectors
    $clusters = [long][Math]::Floor(($total - $firstDataSector) / [double]$spc)
    Assert-StandardFixture ($clusters -ge 65525 -and $fatSectors * 128 -ge $clusters + 2) 'FAT32_classification'
    $backup = [BitConverter]::ToUInt16($vbr, 50)
    $fsInfo = [BitConverter]::ToUInt16($vbr, 48)
    Assert-StandardFixture ($backup -eq 6 -and $fsInfo -eq 1) 'reserved_metadata_offsets'
    $secondary = Read-StandardFixtureBytes $Source ($start + 512 * $backup) 512
    Assert-StandardFixture ((Get-A3DSha256 $vbr) -ceq (Get-A3DSha256 $secondary)) 'backup_boot_mismatch'
    $info = Read-StandardFixtureBytes $Source ($start + 512 * $fsInfo) 512
    $infoBackup = Read-StandardFixtureBytes $Source ($start + 512 * ($backup + $fsInfo)) 512
    Assert-StandardFixture ((Get-A3DSha256 $info) -ceq (Get-A3DSha256 $infoBackup) -and
        [BitConverter]::ToUInt32($info, 0) -eq 0x41615252 -and [BitConverter]::ToUInt32($info, 484) -eq 0x61417272 -and
        [BitConverter]::ToUInt16($info, 510) -eq 0xAA55) 'FSInfo_signatures'
    $fatOffset = $start + 512 * $reserved
    $fatBytes = [int]($fatSectors * 512)
    $fat = Read-StandardFixtureBytes $Source $fatOffset $fatBytes
    $mirror = Read-StandardFixtureBytes $Source ($fatOffset + $fatBytes) $fatBytes
    Assert-StandardFixture ((Get-A3DSha256 $fat) -ceq (Get-A3DSha256 $mirror)) 'FAT_mirror_mismatch'
    $root = [BitConverter]::ToUInt32($vbr, 44)
    Assert-StandardFixture ($root -eq 2 -and [BitConverter]::ToUInt32($fat, 8) -ge 0x0FFFFFF8) 'root_chain'
    $dataOffset = $start + $firstDataSector * 512
    $clusterBytes = $spc * 512
    $directory = Read-StandardFixtureBytes $Source $dataOffset $clusterBytes
    Assert-StandardFixture ($directory[96] -eq 0) 'directory_end'

    $occupied = [System.Collections.Generic.HashSet[int]]::new()
    [void]$occupied.Add([int]$root)
    $results = @(for ($entry = 0; $entry -lt 3; $entry++) {
        $record = $entry * 32
        $name = [Text.Encoding]::ASCII.GetString($directory, $record, 11)
        $cluster = [int][BitConverter]::ToUInt16($directory, $record + 26)
        $length = [int][BitConverter]::ToUInt32($directory, $record + 28)
        Assert-StandardFixture ($length -gt 0 -and $length -le 2048) 'file_length_budget'
        $content = [byte[]]::new($length)
        $chain = @(for ($done = 0; $done -lt $length; $done += $n) {
            Assert-StandardFixture ($cluster -ge 2 -and $cluster -le $clusters + 1 -and $occupied.Add($cluster)) 'invalid_or_shared_cluster'
            $n = [Math]::Min($clusterBytes, $length - $done)
            $chunk = Read-StandardFixtureBytes $Source ($dataOffset + ($cluster - 2) * $clusterBytes) $n
            [Array]::Copy($chunk, 0, $content, $done, $n)
            $cluster
            $cluster = [int]([BitConverter]::ToUInt32($fat, 4 * $cluster) -band 0x0FFFFFFF)
        })
        Assert-StandardFixture ($cluster -ge 0x0FFFFFF8) 'missing_chain_end'
        [pscustomobject]@{ name = $name; sha256 = Get-A3DSha256 $content; chain = $chain }
    })
    $nextFree = [BitConverter]::ToUInt32($info, 492)
    Assert-StandardFixture ([BitConverter]::ToUInt32($info, 488) -eq $clusters - $occupied.Count -and
        $nextFree -ge 2 -and $nextFree -le $clusters + 1 -and
        [BitConverter]::ToUInt32($fat, 4 * [int]$nextFree) -eq 0) 'FSInfo_allocation'
    [pscustomobject]@{ clusterBytes = $clusterBytes; clusters = $clusters; fatOffset = $fatOffset; files = $results }
}

function Assert-StandardVolumeRejected([IO.Stream]$Source, [string]$Reason) {
    try { $null = Read-StandardFixtureVolume $Source }
    catch {
        if ($_.Exception.Message -ceq "A3D_STANDARD_FAIL: $Reason") { return }
        throw
    } finally { $Source.Dispose() }
    throw "A3D_STANDARD_FAIL: expected rejection for $Reason"
}

foreach ($spc in @(1, 2)) {
    $fixture = New-ChappyA3DStandardFixture -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
    $before = Get-A3DSha256 $fixture.image
    $source = [IO.MemoryStream]::new($fixture.image, $false)
    try { $observed = Read-StandardFixtureVolume $source }
    finally { $source.Dispose() }
    Assert-StandardFixture ($observed.clusterBytes -eq 512 * $spc -and $observed.clusters -eq 65541) 'geometry'
    for ($i = 0; $i -lt 3; $i++) {
        Assert-StandardFixture ($observed.files[$i].name -ceq $fixture.oracle[$i].shortName -and
            $observed.files[$i].sha256 -ceq $fixture.oracle[$i].sha256) 'independent_full_file_sha'
    }
    $expectedChain = if ($spc -eq 1) { '4,7' } else { '4' }
    Assert-StandardFixture (($observed.files[1].chain -join ',') -ceq $expectedChain) '3MF_cluster_chain'
    if ($spc -eq 1) {
        [byte[]]$copy = $fixture.image.Clone()
        $copy[$observed.fatOffset + 16] = 0
        Assert-StandardVolumeRejected ([IO.MemoryStream]::new($copy, $false)) 'FAT_mirror_mismatch'
        $copy[512 + 13] = 0
        Assert-StandardVolumeRejected ([IO.MemoryStream]::new($copy, $false)) 'BPB'
        $copy = $null
        $shortSource = [IO.MemoryStream]::new($fixture.image, 0, ($fixture.image.Length - 1), $false)
        Assert-StandardVolumeRejected $shortSource 'partition_extent'
        Write-Host 'PASS: standards-shaped FAT32 rejects damaged FAT mirror, malformed BPB and truncated image.'
    }
    Assert-StandardFixture ((Get-A3DSha256 $fixture.image) -ceq $before) 'source_SHA'
    Write-Host ('PASS: standard synthetic FAT32 image {0} bytes, {1} clusters of {2} bytes, 3MF chain {3}, SHA 3/3.' -f
        $fixture.image.Length, $observed.clusters, $observed.clusterBytes, $expectedChain)
    $fixture = $null
}
