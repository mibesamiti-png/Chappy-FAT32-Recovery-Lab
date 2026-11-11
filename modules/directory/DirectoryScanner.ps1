#requires -Version 5.1
# Chappy FAT32 Recovery Lab / Team B -- metadata-only, FAT-independent directory scanner.
# Dot-source this file. Never opens a physical device or writes to an input stream.

function Read-ChappyBBytes {
    param([Parameter(Mandatory=$true)][System.IO.Stream]$Stream,
          [Parameter(Mandatory=$true)][long]$Offset,
          [Parameter(Mandatory=$true)][int]$Count)
    if (-not $Stream.CanRead -or -not $Stream.CanSeek) { throw 'A readable, seekable stream is required' }
    if ($Count -lt 0 -or $Offset -lt 0 -or $Offset -gt ($Stream.Length - [long]$Count)) {
        throw 'Read outside input stream bounds'
    }
    [void]$Stream.Seek($Offset, [System.IO.SeekOrigin]::Begin)
    $buffer = New-Object byte[] $Count
    $done = 0
    while ($done -lt $Count) {
        $read = $Stream.Read($buffer, $done, $Count - $done)
        if ($read -le 0) { throw 'Input stream truncated during read' }
        $done += $read
    }
    return ,$buffer
}

function Get-ChappyFat32Geometry {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][System.IO.Stream]$Stream,
          [long]$PartitionOffsetBytes = -1L)
    if ($PartitionOffsetBytes -lt -1) { throw 'PartitionOffsetBytes must be -1 or nonnegative' }
    if ($Stream.Length -lt 512) { throw 'Image shorter than one sector' }
    $mbr = Read-ChappyBBytes $Stream 0 512
    if ($PartitionOffsetBytes -eq -1L) {
        $partitions = New-Object System.Collections.ArrayList
        if ($mbr[510] -eq 0x55 -and $mbr[511] -eq 0xAA) {
            for ($i=0; $i -lt 4; $i++) {
                $p = 446 + 16*$i
                if (($mbr[$p+4] -eq 0x0B -or $mbr[$p+4] -eq 0x0C) -and
                    [BitConverter]::ToUInt32($mbr, $p+12) -gt 0) {
                    [void]$partitions.Add(([long][BitConverter]::ToUInt32($mbr, $p+8) * 512L))
                }
            }
        }
        if ($partitions.Count -gt 1) { throw 'Ambiguous FAT32 partitions; specify PartitionOffsetBytes' }
        if ($partitions.Count -eq 1) { $PartitionOffsetBytes = [long]$partitions[0] }
        else { $PartitionOffsetBytes = 0L } # superfloppy PBR fallback; BPB must validate below.
    }
    $boot = Read-ChappyBBytes $Stream $PartitionOffsetBytes 512
    if ($boot[510] -ne 0x55 -or $boot[511] -ne 0xAA) { throw 'Boot sector signature missing' }
    $bps = [long][BitConverter]::ToUInt16($boot, 11)
    $spc = [long]$boot[13]
    $reserved = [long][BitConverter]::ToUInt16($boot, 14)
    $fats = [long]$boot[16]
    $rootEntries = [long][BitConverter]::ToUInt16($boot, 17)
    $fatSectors = [long][BitConverter]::ToUInt32($boot, 36)
    $totalSectors = [long][BitConverter]::ToUInt32($boot, 32)
    if ($totalSectors -eq 0) { $totalSectors = [long][BitConverter]::ToUInt16($boot, 19) }
    $rootCluster = [long][BitConverter]::ToUInt32($boot, 44)
    if (($bps -ne 512 -and $bps -ne 1024 -and $bps -ne 2048 -and $bps -ne 4096) -or
        $spc -lt 1 -or $spc -gt 128 -or (($spc -band ($spc-1)) -ne 0) -or
        $reserved -lt 1 -or $fats -lt 1 -or $fats -gt 2 -or $rootEntries -ne 0 -or
        $fatSectors -lt 1 -or $totalSectors -lt 1 -or
        [BitConverter]::ToUInt16($boot, 22) -ne 0) {
        throw 'Invalid FAT32-like BPB fields'
    }
    $dataSectors = $totalSectors - $reserved - ($fats * $fatSectors)
    if ($dataSectors -lt $spc) { throw 'Invalid data-region length' }
    $clusterCount = [long][Math]::Floor($dataSectors / $spc)
    if (($fatSectors * $bps) -lt (($clusterCount+2L)*4L)) {
        throw 'FAT capacity inconsistent with BPB (do not trust data offset)'
    }
    $partEnd = $PartitionOffsetBytes + $totalSectors*$bps
    if ($partEnd -gt $Stream.Length) { throw 'Image truncated relative to BPB partition size' }
    $dataStart = $PartitionOffsetBytes + ($reserved + $fats*$fatSectors)*$bps
    $clusterSize = $bps * $spc
    return [pscustomobject]@{
        partitionOffsetBytes = $PartitionOffsetBytes
        dataOffsetBytes = $dataStart
        bytesPerSector = $bps
        sectorsPerCluster = $spc
        clusterSizeBytes = $clusterSize
        clusterCount = $clusterCount
        rootCluster = $rootCluster
        maxCluster = ($clusterCount+1L)
        partitionEndBytes = $partEnd
        fatCount = $fats
        fatSizeSectors = $fatSectors
        # These are geometry only; no FAT entries are read.
    }
}

function Get-ChappyBShortChecksum {
    param([byte[]]$Entry)
    $sum = 0
    for ($k=0; $k -lt 11; $k++) {
        $sum = (((($sum -band 1) * 128) + ($sum -shr 1) + [int]$Entry[$k]) -band 255)
    }
    return [int]$sum
}

function Get-ChappyBLfnName {
    param([object[]]$Segments, [int]$Checksum)
    if ($Segments.Count -lt 1 -or $Segments.Count -gt 20) { return $null }
    $firstOrd = [int]$Segments[0][0]
    $count = $firstOrd -band 0x1F
    # Bits 0x20 and 0x80 are reserved in a live LFN ordinal.
    if (($firstOrd -band 0x40) -eq 0 -or ($firstOrd -band 0xA0) -ne 0 -or
        $count -ne $Segments.Count) { return $null }
    $units = New-Object 'System.Collections.Generic.List[byte]'
    $positions = @(1,3,5,7,9,14,16,18,20,22,24,28,30)
    for ($i=$Segments.Count-1; $i -ge 0; $i--) {
        [byte[]]$s = $Segments[$i]
        if ($null -eq $s -or $s.Length -ne 32) { return $null }
        $expectedOrd = $Segments.Count - $i
        if ((($s[0] -band 0x1F) -ne $expectedOrd) -or
            (($s[0] -band 0xA0) -ne 0) -or
            (($i -ne 0) -and (($s[0] -band 0x40) -ne 0)) -or
            $s[11] -ne 0x0F -or $s[12] -ne 0 -or $s[13] -ne $Checksum -or
            $s[26] -ne 0 -or $s[27] -ne 0) { return $null }
        foreach ($p in $positions) {
            $units.Add($s[$p]); $units.Add($s[$p+1])
        }
    }
    $textBytes = New-Object 'System.Collections.Generic.List[byte]'
    $sawNullTerminator = $false
    for ($j=0; $j -lt $units.Count; $j+=2) {
        $u = [int]$units[$j] + 256*[int]$units[$j+1]
        if ($u -eq 0) {
            if ($sawNullTerminator) { return $null }
            $sawNullTerminator = $true
            continue
        }
        if ($u -eq 65535) {
            # 0xFFFF is filler, never a substitute for the 0x0000 terminator.
            if (-not $sawNullTerminator) { return $null }
            continue
        }
        if ($sawNullTerminator) { return $null }
        $textBytes.Add($units[$j]); $textBytes.Add($units[$j+1])
    }
    try {
        $utf16 = New-Object -TypeName System.Text.UnicodeEncoding -ArgumentList @($false, $false, $true)
        $name = $utf16.GetString($textBytes.ToArray())
    } catch { return $null }
    if ($name.Length -lt 1 -or $name.Length -gt 255 -or
        $name -eq '.' -or $name -eq '..' -or
        $name -match '[\\/:*?"<>|\x00-\x1F]') { return $null }
    return $name
}

function Get-ChappyBShortName {
    param([byte[]]$Entry, [switch]$AllowDeleted)
    if ($Entry.Length -ne 32) { return $null }
    $deleted = ($Entry[0] -eq 0xE5)
    if ($deleted -and -not $AllowDeleted) { return $null }
    $baseBytes = New-Object byte[] 8
    $extBytes = New-Object byte[] 3
    [Array]::Copy($Entry, 0, $baseBytes, 0, 8)
    [Array]::Copy($Entry, 8, $extBytes, 0, 3)
    if ($baseBytes[0] -eq 0x05) { $baseBytes[0] = 0xE5 }
    elseif ($deleted) { $baseBytes[0] = 0x3F } # Unknown original first character.
    for ($i=0; $i -lt 11; $i++) {
        $b = [int]$Entry[$i]
        if ($i -eq 0 -and ($deleted -or $b -eq 0x05)) { continue }
        if ($b -lt 0x20 -or $b -eq 0x7F -or
            @(0x22,0x2A,0x2B,0x2C,0x2F,0x3A,0x3B,0x3C,0x3D,0x3E,0x3F,0x5B,0x5C,0x5D,0x7C) -contains $b) {
            return $null
        }
    }
    $oem = [Text.Encoding]::GetEncoding(437)
    $base = $oem.GetString($baseBytes).TrimEnd(' ')
    $ext = $oem.GetString($extBytes).TrimEnd(' ')
    if ($base.Length -eq 0 -or $base -match '[\\/]') { return $null }
    if ($base -eq '.' -or $base -eq '..') { return $base }
    if ($base.Contains('.')) { return $null }
    if ($ext.Length -gt 0) { return ($base + '.' + $ext) }
    return $base
}

function Read-ChappyBDirectoryCluster {
    param([byte[]]$Buffer, [long]$Cluster, [long]$OffsetBytes,
          [long]$MaxCluster, [switch]$IncludeDeleted, [switch]$IncludeNames,
          [switch]$ExperimentalFlagZeroSizeAllocatedFile, [bool]$IsRoot)
    $candidateItems = New-Object System.Collections.ArrayList
    $segments = New-Object System.Collections.ArrayList
    $validCount = 0
    $dotSeen = $false
    $dotdotSeen = $false
    $dotdotParent = $null
    $malformedDotHeader = $false
    $parentHint = $null
    $hasValidLfn = $false
    $hasEndMarker = $false
    for ($j=0; $j -le $Buffer.Length-32; $j+=32) {
        $first = [int]$Buffer[$j]
        if ($first -eq 0) { $hasEndMarker = $true; break }
        [byte[]]$e = New-Object byte[] 32
        [Array]::Copy($Buffer, $j, $e, 0, 32)
        $attr = [int]$e[11]
        if ($attr -eq 0x0F) {
            if ($first -eq 0xE5) { $segments.Clear(); continue }
            if ($segments.Count -ge 20) { $segments.Clear(); continue }
            [void]$segments.Add($e)
            continue
        }
        if (($attr -band 0xC0) -ne 0 -or (($attr -band 0x18) -eq 0x18) -or
            (($attr -band 0x08) -ne 0)) { $segments.Clear(); continue } # labels/not file or dir
        $short = Get-ChappyBShortName $e -AllowDeleted:$IncludeDeleted
        if ($null -eq $short) { $segments.Clear(); continue }
        $clusterHigh = [long][BitConverter]::ToUInt16($e, 20) -band 0x0FFFL
        $clusterLow = [long][BitConverter]::ToUInt16($e, 26)
        $start = ($clusterHigh -shl 16) + $clusterLow
        $size = [long][BitConverter]::ToUInt32($e, 28)
        $directory = (($attr -band 0x10) -ne 0)
        if ($short -eq '.' -or $short -eq '..') {
            # Dot records are structural evidence only when they form an ordered,
            # size-zero pair in the first two slots. Never trust a lone dot record.
            $validHeaderRecord = ($directory -and $size -eq 0 -and $segments.Count -eq 0 -and $first -ne 0xE5)
            if ($short -eq '.' -and $j -eq 0 -and $validHeaderRecord -and $start -eq $Cluster) {
                $dotSeen = $true
            } elseif ($short -eq '..' -and $j -eq 32 -and $validHeaderRecord -and
                      ($start -eq 0 -or ($start -ge 2 -and $start -le $MaxCluster))) {
                $dotdotSeen = $true
                $dotdotParent = $start
            } else {
                $malformedDotHeader = $true
            }
            $segments.Clear(); continue
        }
        if (($start -eq 1) -or ($start -gt $MaxCluster) -or
            ($directory -and ($start -lt 2 -or $size -ne 0)) -or
            (-not $directory -and $size -gt 0 -and $start -lt 2)) {
            $segments.Clear(); continue
        }
        $lfnName = $null
        if ($segments.Count -gt 0 -and $first -ne 0xE5) {
            $lfnName = Get-ChappyBLfnName -Segments @($segments.ToArray()) -Checksum (Get-ChappyBShortChecksum $e)
        }
        $lfnInvalid = ($segments.Count -gt 0 -and $null -eq $lfnName)
        $segments.Clear()
        $validCount++
        if ($null -ne $lfnName) { $hasValidLfn = $true }
        $isDeleted = ($first -eq 0xE5)
        $zeroSizeAllocatedFile = (-not $directory -and $size -eq 0 -and $start -ge 2)
        $oversized = (-not $directory -and $size -gt (($MaxCluster-1L)*[long]$Buffer.Length))
        $visibleName = $null
        $visibleShort = $null
        if ($IncludeNames) {
            $visibleName = if ($null -ne $lfnName) { $lfnName } else { $short }
            $visibleShort = $short
        }
        $reasons = New-Object System.Collections.ArrayList
        [void]$reasons.Add('short_entry_structure')
        if ($null -ne $lfnName) { [void]$reasons.Add('lfn_checksum_sequence_valid') }
        if ($lfnInvalid) { [void]$reasons.Add('lfn_rejected_short_fallback') }
        if ($isDeleted) { [void]$reasons.Add('deleted_first_character_unknown') }
        if ($oversized) { [void]$reasons.Add('size_exceeds_volume_capacity') }
        if ($ExperimentalFlagZeroSizeAllocatedFile -and $zeroSizeAllocatedFile) {
            [void]$reasons.Add('zero_size_with_allocated_start_cluster')
        }
        [void]$candidateItems.Add([pscustomobject]@{
            offsetBytes = ($OffsetBytes + $j)
            containerCluster = $Cluster
            startCluster = $start
            sizeBytes = $size
            isDirectory = $directory
            deleted = $isDeleted
            name = $visibleName
            shortName = $visibleShort
            nameSource = $(if ($null -ne $lfnName) { 'lfn_validated' } elseif ($isDeleted) { 'deleted_short_partial' } else { 'short_8_3' })
            confidence = $(if ($isDeleted -or $lfnInvalid -or $oversized -or
                ($ExperimentalFlagZeroSizeAllocatedFile -and $zeroSizeAllocatedFile)) { 'partial' } else { 'probable' })
            evidence = @($reasons.ToArray())
            parentClusterHint = $null
        })
    }
    # Classify the *container*, not just its individual 32-byte records.
    # A lone dot record or an isolated valid LFN can occur inside arbitrary file data.
    # This deliberately favors precision: a partially overwritten one-entry orphan
    # with no consistent header may be missed, rather than called a proven directory.
    $validDotPair = ($dotSeen -and $dotdotSeen -and -not $malformedDotHeader)
    if ($validDotPair) { $parentHint = $dotdotParent }
    $accepted = $false
    $decisionReason = 'insufficient_directory_evidence'
    if ($IsRoot -and $validCount -ge 1) {
        $accepted = $true
        $decisionReason = 'root_valid_entry'
    } elseif ($validDotPair) {
        $accepted = $true
        $decisionReason = 'ordered_dot_pair'
    } elseif ($validCount -ge 2 -and $hasEndMarker) {
        $accepted = $true
        $decisionReason = 'multiple_entries_with_end_marker'
    } elseif ($dotSeen -or $dotdotSeen -or $malformedDotHeader) {
        $decisionReason = 'unpaired_or_malformed_dot_header'
    } elseif ($validCount -eq 1 -and $hasValidLfn) {
        $decisionReason = 'isolated_lfn_without_directory_header'
    }
    # A weak multi-entry cluster may be ordinary file content that happens
    # to look like directory records. Keep it discoverable as a *candidate*,
    # but do not assign the same evidence confidence as a dot-pair or root.
    $containerConfidence = if (-not $accepted) { 'unknown' }
                           elseif ($decisionReason -eq 'multiple_entries_with_end_marker') { 'partial' }
                           else { 'probable' }
    if ($accepted) {
        foreach ($item in $candidateItems) {
            $item.parentClusterHint = $parentHint
            $item.evidence = @($item.evidence) + @('container_' + $decisionReason)
            if ($containerConfidence -eq 'partial') {
                $item.confidence = 'partial'
                $item.evidence = @($item.evidence) + @('unpaired_multi_entry_weak_container')
            }
        }
    }
    return [pscustomobject]@{
        accepted = $accepted
        decisionReason = $decisionReason
        confidence = $containerConfidence
        entries = @($candidateItems.ToArray())
        validCount = $validCount
        hasDotHeader = $dotSeen
        hasConsistentDotPair = $validDotPair
        parentClusterHint = $parentHint
        hasEndMarker = $hasEndMarker
    }
}

function Get-ChappyDirectoryCandidates {
    <#
    .SYNOPSIS
    FAT-independent directory metadata scan; does NOT read FAT chains or file contents.
    .DESCRIPTION
    Bounded cluster-aligned scan. Root cluster gets priority; subsequent clusters are
    independent candidates, not a proven directory tree. Names remain redacted by default.
    .EXAMPLE
    Get-ChappyDirectoryCandidates -Stream $readOnlyStream -MaxScanBytes 67108864 -IncludeNames
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][System.IO.Stream]$Stream,
          [object]$Geometry = $null,
          [long]$PartitionOffsetBytes = -1L,
          [long]$MaxScanBytes = 67108864L,
          [long]$StartCluster = 2L,
          [int]$MaxCandidates = 10000,
          [int]$MaxDirectories = 1000,
          [switch]$IncludeNames,
          [switch]$IncludeDeleted,
          # R4 experiment, default OFF: flag zero-size files with allocated starts.
          [switch]$ExperimentalFlagZeroSizeAllocatedFile,
          # R9 experimental, default OFF: bounded read-event provenance.
          # This reports scanner observations, not cryptographic authenticity.
          [switch]$RecordClusterCoverage,
          [int]$MaxCoverageClusters = 65536,
          [int]$MaxCoverageIntervals = 128)
    $items = New-Object System.Collections.ArrayList
    $directoryContainers = New-Object System.Collections.ArrayList
    $warnings = New-Object System.Collections.ArrayList
    $errors = New-Object System.Collections.ArrayList
    $bytesRead = 0L
    $checked = 0L
    $directoriesAccepted = 0L
    $coverageBitmap = $null
    $coverageStatus = 'not_requested'
    $coverageUnique = 0L
    $coverageDuplicates = 0L
    $coverageIntervals = New-Object System.Collections.ArrayList
    $rejectedReasons = [ordered]@{
        insufficient_directory_evidence = 0L
        unpaired_or_malformed_dot_header = 0L
        isolated_lfn_without_directory_header = 0L
    }
    $incomplete = $false
    $geo = $null
    try {
        if ($MaxScanBytes -lt 0 -or $StartCluster -lt 2 -or
            $MaxCandidates -lt 1 -or $MaxCandidates -gt 200000 -or
            $MaxDirectories -lt 1 -or $MaxDirectories -gt 100000 -or
            $MaxCoverageClusters -lt 1 -or $MaxCoverageClusters -gt 65536 -or
            $MaxCoverageIntervals -lt 1 -or $MaxCoverageIntervals -gt 128) {
            throw 'Invalid scan limits'
        }
        if ($null -eq $Geometry) {
            $geo = Get-ChappyFat32Geometry -Stream $Stream -PartitionOffsetBytes $PartitionOffsetBytes
        } else { $geo = $Geometry }
        $clusterSize = [long]$geo.clusterSizeBytes
        $dataOffset = [long]$geo.dataOffsetBytes
        $maxCluster = [long]$geo.maxCluster
        $root = [long]$geo.rootCluster
        $partitionEnd = [long]$geo.partitionEndBytes
        if ($clusterSize -lt 512 -or $clusterSize -gt 131072 -or
            ($clusterSize % 32) -ne 0 -or $dataOffset -lt 0 -or
            $maxCluster -lt 2 -or $partitionEnd -gt $Stream.Length -or
            $dataOffset -gt $partitionEnd -or
            ($dataOffset + ($maxCluster-1L)*$clusterSize) -gt $partitionEnd) {
            throw 'Unsafe or inconsistent supplied geometry'
        }
        if ($RecordClusterCoverage) {
            $declaredCount = [long]$geo.clusterCount
            if ($declaredCount -gt 0 -and $declaredCount -le $MaxCoverageClusters -and
                $maxCluster -eq ($declaredCount + 1L)) {
                $coverageBitmap = New-Object byte[] ([int]$declaredCount)
                $coverageStatus = 'recorded'
            } else {
                # Never allocate a whole-volume bitmap for a large volume.
                # Candidate scanning continues; independent coverage is unknown.
                $coverageStatus = 'cluster_limit'
            }
        }
        if ($root -lt 2 -or $root -gt $maxCluster) {
            [void]$warnings.Add('root_cluster_out_of_range')
        }
        if ($MaxScanBytes -lt $clusterSize) {
            $incomplete = $true
            [void]$warnings.Add('budget_smaller_than_cluster')
        } else {
            $rootRead = $false
            if ($root -ge 2 -and $root -le $maxCluster) {
                $rootOffset = $dataOffset + ($root-2L)*$clusterSize
                $rootBuf = Read-ChappyBBytes $Stream $rootOffset ([int]$clusterSize)
                $bytesRead += $clusterSize
                if ($null -ne $coverageBitmap) {
                    $readIndex = [int]($root - 2L)
                    if ($coverageBitmap[$readIndex] -eq 0) {
                        $coverageBitmap[$readIndex] = 1
                        $coverageUnique++
                    } else { $coverageDuplicates++ }
                }
                $rootRead = $true
                $parsed = Read-ChappyBDirectoryCluster -Buffer $rootBuf -Cluster $root -OffsetBytes $rootOffset -MaxCluster $maxCluster -IncludeDeleted:$IncludeDeleted -IncludeNames:$IncludeNames -ExperimentalFlagZeroSizeAllocatedFile:$ExperimentalFlagZeroSizeAllocatedFile -IsRoot $true
                $checked += [long]$parsed.validCount
                if ($parsed.accepted) {
                    $directoriesAccepted++
                    [void]$directoryContainers.Add([pscustomobject]@{
                        cluster = $root
                        isRoot = $true
                        decisionReason = $parsed.decisionReason
                        confidence = $parsed.confidence
                        parentClusterHint = $parsed.parentClusterHint
                        entryCount = $parsed.validCount
                    })
                    foreach ($item in $parsed.entries) {
                        if ($items.Count -ge $MaxCandidates) { $incomplete = $true; break }
                        [void]$items.Add($item)
                    }
                } else {
                    $rejectedReasons[$parsed.decisionReason] = [long]$rejectedReasons[$parsed.decisionReason] + 1L
                    [void]$warnings.Add('root_cluster_not_recognized_as_directory')
                }
            }
            $completeCoverage = ($StartCluster -le 2 -and $MaxScanBytes -ge ([long]$geo.clusterCount * $clusterSize))
            if (-not $completeCoverage) { $incomplete = $true }
            for ($c=$StartCluster; $c -le $maxCluster; $c++) {
                if ($c -eq $root -and $rootRead) { continue }
                if (($bytesRead + $clusterSize) -gt $MaxScanBytes -or
                    $items.Count -ge $MaxCandidates -or
                    $directoriesAccepted -ge $MaxDirectories) {
                    $incomplete = $true
                    break
                }
                $at = $dataOffset + ($c-2L)*$clusterSize
                $buf = Read-ChappyBBytes $Stream $at ([int]$clusterSize)
                $bytesRead += $clusterSize
                if ($null -ne $coverageBitmap) {
                    $readIndex = [int]($c - 2L)
                    if ($coverageBitmap[$readIndex] -eq 0) {
                        $coverageBitmap[$readIndex] = 1
                        $coverageUnique++
                    } else { $coverageDuplicates++ }
                }
                $parsed = Read-ChappyBDirectoryCluster -Buffer $buf -Cluster $c -OffsetBytes $at -MaxCluster $maxCluster -IncludeDeleted:$IncludeDeleted -IncludeNames:$IncludeNames -ExperimentalFlagZeroSizeAllocatedFile:$ExperimentalFlagZeroSizeAllocatedFile -IsRoot $false
                $checked += [long]$parsed.validCount
                if (-not $parsed.accepted) {
                    $rejectedReasons[$parsed.decisionReason] = [long]$rejectedReasons[$parsed.decisionReason] + 1L
                    continue
                }
                $directoriesAccepted++
                [void]$directoryContainers.Add([pscustomobject]@{
                    cluster = $c
                    isRoot = $false
                    decisionReason = $parsed.decisionReason
                    confidence = $parsed.confidence
                    parentClusterHint = $parsed.parentClusterHint
                    entryCount = $parsed.validCount
                })
                foreach ($item in $parsed.entries) {
                    if ($items.Count -ge $MaxCandidates) { $incomplete = $true; break }
                    [void]$items.Add($item)
                }
                if ($items.Count -ge $MaxCandidates) { $incomplete = $true; break }
            }
        }
    } catch {
        [void]$errors.Add('directory_scan_error: ' + $_.Exception.Message)
        $incomplete = $true
    }
    # Convert the bounded observed-cluster bitmap to disjoint ascending
    # intervals. A full scan yields one interval, irrespective of root order.
    if ($RecordClusterCoverage -and $null -ne $coverageBitmap) {
        $openAt = -1
        for ($k=0; $k -lt $coverageBitmap.Length; $k++) {
            if ($coverageBitmap[$k] -ne 0 -and $openAt -lt 0) {
                $openAt = $k
            } elseif ($coverageBitmap[$k] -eq 0 -and $openAt -ge 0) {
                if ($coverageIntervals.Count -ge $MaxCoverageIntervals) {
                    $coverageStatus = 'interval_limit'
                    break
                }
                [void]$coverageIntervals.Add([pscustomobject]@{
                    firstCluster = [long]($openAt + 2)
                    lastCluster = [long]($k + 1)
                })
                $openAt = -1
            }
        }
        if ($coverageStatus -eq 'recorded' -and $openAt -ge 0) {
            if ($coverageIntervals.Count -ge $MaxCoverageIntervals) {
                $coverageStatus = 'interval_limit'
            } else {
                [void]$coverageIntervals.Add([pscustomobject]@{
                    firstCluster = [long]($openAt + 2)
                    lastCluster = [long]($coverageBitmap.Length + 1)
                })
            }
        }
    }
    $coverageReport = $null
    if ($RecordClusterCoverage) {
        $coverageReport = [pscustomobject]@{
            source = 'scanner_read_events_v1'
            status = $coverageStatus
            uniqueClusters = $coverageUnique
            duplicateReadEvents = $coverageDuplicates
            readEvents = ($coverageUnique + $coverageDuplicates)
            intervals = @($coverageIntervals.ToArray())
        }
    }
    $status = if ($errors.Count) { 'error' } elseif ($incomplete -or $warnings.Count) { 'partial' } else { 'ok' }
    return [pscustomobject]@{
        schemaVersion = '1'
        team = 'B'
        status = $status
        scanIncomplete = [bool]$incomplete
        items = @($items.ToArray())
        directoryContainers = @($directoryContainers.ToArray())
        coverageProvenance = $coverageReport
        warnings = @($warnings.ToArray())
        errors = @($errors.ToArray())
        metrics = [pscustomobject]@{
            bytesRead = $bytesRead
            entriesChecked = $checked
            directoriesAccepted = $directoriesAccepted
            directoryRejectReasons = [pscustomobject]$rejectedReasons
            candidateCount = $items.Count
        }
        geometry = $geo
        notes = @('FAT entries never read', 'directory/container linkage not proven', 'file data not validated')
    }
}
