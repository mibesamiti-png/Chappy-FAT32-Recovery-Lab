#Requires -Version 5.1
# Team D: read-only FAT32 structural forensics. No image write APIs in this module.
Set-StrictMode -Version 2.0

function Read-DBytes {
    param([System.IO.FileStream]$Stream, [long]$Offset, [int]$Count)
    if ($Offset -lt 0 -or $Count -lt 0 -or $Count -gt 1048576 -or $Offset -gt ($Stream.Length - [long]$Count)) {
        throw "Read outside image or above 1 MiB cap: offset=$Offset count=$Count length=$($Stream.Length)"
    }
    [void]$Stream.Seek($Offset, [System.IO.SeekOrigin]::Begin)
    $buffer = New-Object 'byte[]' $Count
    $read = 0
    while ($read -lt $Count) {
        $n = $Stream.Read($buffer, $read, $Count - $read)
        if ($n -eq 0) { throw 'Unexpected EOF' }
        $read += $n
    }
    $script:DBytesRead += $Count
    return ,$buffer
}
function Get-U16 { param([byte[]]$Bytes, [int]$At) return [BitConverter]::ToUInt16($Bytes,$At) }
function Get-U32 { param([byte[]]$Bytes, [int]$At) return [BitConverter]::ToUInt32($Bytes,$At) }
function Get-Hex { param([byte[]]$Bytes) return [BitConverter]::ToString($Bytes).Replace('-',' ') }
function Get-SampleSha256 {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant()) }
    finally { $sha.Dispose() }
}
function Test-IsPowerOfTwo { param([int]$Value) return ($Value -gt 0 -and (($Value -band ($Value - 1)) -eq 0)) }
function Add-Finding { param($Issues,[string]$Code,[string]$Severity,[string]$Detail) [void]$Issues.Add([pscustomobject]@{Code=$Code;Severity=$Severity;Detail=$Detail}) }

function Get-BpbProbe {
    param([System.IO.FileStream]$Stream, [long]$VolumeOffset)
    if ($VolumeOffset -lt 0 -or $VolumeOffset -gt ($Stream.Length-512)) { return $null }
    $b=Read-DBytes $Stream $VolumeOffset 512
    $bytesPerSector=[int](Get-U16 $b 11); $spc=[int]$b[13]
    $reserved=[int](Get-U16 $b 14); $fats=[int]$b[16]
    $total16=[uint32](Get-U16 $b 19); $total32=[uint32](Get-U32 $b 32)
    $total=[long]$total32; if ($total16 -ne 0) { $total=[long]$total16 }
    $fatSectors=[long](Get-U32 $b 36)
    $fatBytes=([long]$fatSectors)*$bytesPerSector
    $dataSectors=$total-[long]$reserved-[long]$fats*$fatSectors
    $clusters=[long]0; if ($spc -gt 0) { $clusters=[math]::Floor($dataSectors/$spc) }
    $issues=New-Object System.Collections.ArrayList
    if ($b[510] -ne 0x55 -or $b[511] -ne 0xAA) { Add-Finding $issues 'BPB_SIGNATURE' 'error' 'Missing 55 AA at offset 510' }
    if (-not (($b[0] -eq 0xEB -and $b[2] -eq 0x90) -or $b[0] -eq 0xE9)) { Add-Finding $issues 'BPB_JUMP' 'warning' 'Unexpected jump opcode' }
    if (@(512,1024,2048,4096) -notcontains $bytesPerSector) { Add-Finding $issues 'BPB_SECTOR_SIZE' 'error' "Unsupported bytes/sector=$bytesPerSector" }
    if ($spc -gt 128 -or -not (Test-IsPowerOfTwo $spc)) { Add-Finding $issues 'BPB_CLUSTER_SIZE' 'error' "Invalid sectors/cluster=$spc" }
    if ($reserved -lt 1) { Add-Finding $issues 'BPB_RESERVED' 'error' 'Reserved sector count zero' }
    if ($fats -lt 1 -or $fats -gt 4) { Add-Finding $issues 'BPB_FAT_COPIES' 'error' "Suspicious FAT count=$fats" }
    if ((Get-U16 $b 17) -ne 0 -or (Get-U16 $b 22) -ne 0 -or $total16 -ne 0) { Add-Finding $issues 'BPB_FAT32_FIELDS' 'error' 'FAT32-specific legacy BPB fields are nonzero' }
    if ($fatSectors -le 0 -or $total -le 0 -or $dataSectors -le 0) { Add-Finding $issues 'BPB_GEOMETRY' 'error' 'Empty or impossible FAT/data geometry' }
    if ($bytesPerSector -gt 0 -and $total -gt 0 -and $VolumeOffset + $total*$bytesPerSector -gt $Stream.Length) { Add-Finding $issues 'BPB_IMAGE_BOUNDS' 'error' 'Declared volume extends beyond IMG' }
    if ($clusters -lt 65525) { Add-Finding $issues 'BPB_FAT32_CLUSTER_COUNT' 'warning' 'Cluster count below FAT32 identification threshold' }
    if ($fatBytes -gt 0 -and $clusters + 2 -gt [math]::Floor($fatBytes/4)) { Add-Finding $issues 'BPB_FAT_TOO_SHORT' 'error' 'FAT cannot hold all data cluster entries' }
    if ((Get-U16 $b 42) -ne 0) { Add-Finding $issues 'BPB_FS_VERSION' 'warning' 'Unusual FAT32 FSVersion' }
    if (((Get-U16 $b 40) -band 0x7F70) -ne 0) { Add-Finding $issues 'BPB_EXT_FLAGS' 'warning' 'Unexpected ExtFlags reserved bits' }
    $mirrorDisabled=(((Get-U16 $b 40) -band 0x80) -ne 0)
    $active=[int]((Get-U16 $b 40) -band 0x0F)
    if ($mirrorDisabled -and $active -ge $fats) { Add-Finding $issues 'BPB_ACTIVE_FAT' 'error' 'Active FAT index exceeds FAT count' }
    $root=[uint32](Get-U32 $b 44)
    if ($root -lt 2 -or [long]$root -gt $clusters+1) { Add-Finding $issues 'BPB_ROOT_CLUSTER' 'error' 'Root cluster outside data region' }
    $fsInfo=[int](Get-U16 $b 48); $backup=[int](Get-U16 $b 50)
    if ($fsInfo -ge $reserved) { Add-Finding $issues 'BPB_FSINFO_RANGE' 'warning' 'FSInfo sector outside reserved region' }
    if ($backup -gt 0 -and $backup -ge $reserved) { Add-Finding $issues 'BPB_BACKUP_RANGE' 'warning' 'Backup boot sector outside reserved region' }
    if (@($b[52..63] | Where-Object {$_ -ne 0}).Count -gt 0) { Add-Finding $issues 'BPB_RESERVED_BYTES' 'warning' 'FAT32 reserved BPB bytes are nonzero' }
    $geometrySafe=($bytesPerSector -in @(512,1024,2048,4096) -and $spc -ge 1 -and $spc -le 128 -and (Test-IsPowerOfTwo $spc) -and $reserved -gt 0 -and $fats -ge 1 -and $fats -le 4 -and $fatSectors -gt 0 -and $total -gt 0 -and $dataSectors -gt 0 -and $VolumeOffset+$total*$bytesPerSector -le $Stream.Length -and $clusters+2 -le [math]::Floor($fatBytes/4))
    return [pscustomobject]@{
        VolumeOffset=$VolumeOffset; BootPrefix=(Get-Hex $b[0..2]); BootSignature=((Get-Hex $b[510..511])); OEMName=[Text.Encoding]::ASCII.GetString($b,3,8)
        BytesPerSector=$bytesPerSector; SectorsPerCluster=$spc; ReservedSectors=$reserved; FatCount=$fats
        RootEntryCount=[int](Get-U16 $b 17); TotalSectors16=$total16; TotalSectors32=$total32; TotalSectors=$total
        Media=[int]$b[21]; FatSectors16=[int](Get-U16 $b 22); FatSectors32=$fatSectors
        SectorsPerTrack=[int](Get-U16 $b 24); HeadCount=[int](Get-U16 $b 26); HiddenSectors=[uint32](Get-U32 $b 28)
        ExtendedFlags=[int](Get-U16 $b 40); MirrorDisabled=$mirrorDisabled; ActiveFat=$active; FileSystemVersion=[int](Get-U16 $b 42)
        RootCluster=$root; FsInfoSector=$fsInfo; BackupBootSector=$backup; DriveNumber=[int]$b[64]
        BootSignatureExtended=[int]$b[66]; VolumeId=[uint32](Get-U32 $b 67)
        VolumeLabel=[Text.Encoding]::ASCII.GetString($b,71,11); FileSystemTypeHint=[Text.Encoding]::ASCII.GetString($b,82,8)
        DataSectorCount=$dataSectors; ClusterCount=$clusters; FatBytes=$fatBytes; ClusterBytes=([long]$spc*$bytesPerSector)
        FatOffset=($VolumeOffset+[long]$reserved*$bytesPerSector)
        DataOffset=($VolumeOffset+([long]$reserved+[long]$fats*$fatSectors)*$bytesPerSector)
        GeometrySafe=[bool]$geometrySafe; Findings=@($issues)
    }
}

function Get-MbrPartitions {
    param([System.IO.FileStream]$Stream)
    $sector=Read-DBytes $Stream 0 512
    $result=New-Object System.Collections.ArrayList
    if ($sector[510] -ne 0x55 -or $sector[511] -ne 0xAA) { return @() }
    for ($i=0;$i -lt 4;$i++) {
        $p=446+16*$i
        $type=[int]$sector[$p+4]; $start=[uint32](Get-U32 $sector ($p+8)); $count=[uint32](Get-U32 $sector ($p+12))
        if ($type -ne 0 -and $count -gt 0) {
            [void]$result.Add([pscustomobject]@{Index=$i;Type=('0x{0:X2}' -f $type);StartLba=$start;SectorCount=$count;ByteOffset=([long]$start*512)})
        }
    }
    return @($result)
}
function Get-FatEntry {
    param([System.IO.FileStream]$Stream,$Bpb,[int]$FatIndex,[uint32]$Cluster)
    if (-not $Bpb.GeometrySafe -or $FatIndex -ge $Bpb.FatCount -or $FatIndex -lt 0 -or [long]$Cluster -ge [math]::Floor($Bpb.FatBytes/4)) { return $null }
    $pos=[long]$Bpb.FatOffset+[long]$FatIndex*$Bpb.FatBytes+[long]$Cluster*4
    $entry=Read-DBytes $Stream $pos 4
    return ([uint32]((Get-U32 $entry 0) -band 0x0FFFFFFF))
}
function Get-FatHeader {
    param([System.IO.FileStream]$Stream,$Bpb,[int]$FatIndex,[long]$OverrideOffset=-1)
    $pos=[long]$Bpb.FatOffset+[long]$FatIndex*$Bpb.FatBytes
    if ($OverrideOffset -ge 0) { $pos=$OverrideOffset }
    if ($pos -lt 0 -or $pos -gt $Stream.Length-32) { return $null }
    $b=Read-DBytes $Stream $pos 32
    $a=[uint32]((Get-U32 $b 0) -band 0x0FFFFFFF)
    $c=[uint32]((Get-U32 $b 4) -band 0x0FFFFFFF)
    $expected=([uint32](0x0FFFFF00 -bor $Bpb.Media))
    # FAT[1] has dirty/error bits: any EOC (0x0FFFFFF8..0x0FFFFFFF) is accepted.
    $valid=($a -eq $expected -and (($c -band 0x03FFFFFF) -eq 0x03FFFFFF))
    $twoByteRepeat=$true; for($k=0;$k -lt 32;$k+=2) { if ($b[$k] -ne 0xEB -or $b[$k+1] -ne 0x58) {$twoByteRepeat=$false;break} }
    $jumpPrefix=($b[0] -eq 0xEB -and $b[1] -eq 0x58 -and $b[2] -eq 0x90)
    $bootLike=$false
    if ($jumpPrefix -and $pos -le $Stream.Length-512) {
        $boot=Read-DBytes $Stream $pos 512
        $bootLike=($boot[510] -eq 0x55 -and $boot[511] -eq 0xAA -and (Get-U16 $boot 11) -in @(512,1024,2048,4096))
    }
    return [pscustomobject]@{FatIndex=$FatIndex;Offset=$pos;First32Hex=(Get-Hex $b);First32Sha256=(Get-SampleSha256 $b);Entry0=$a;Entry1=$c;ExpectedEntry0=$expected;ReservedEntriesValid=[bool]$valid;EB58PairRepeated16Times=$twoByteRepeat;StartsEB5890=$jumpPrefix;LooksLikeBootSector=$bootLike}
}
function Get-NearbyFatHeaders {
    param([System.IO.FileStream]$Stream,$Bpb,[int]$FatIndex)
    $expected=[long]$Bpb.FatOffset+[long]$FatIndex*$Bpb.FatBytes
    $hits=New-Object System.Collections.ArrayList
    # Deliberately bounded: +/- 8 sectors, plus byte shifts of +/- 1..16.
    foreach($delta in @(-4096,-3584,-3072,-2560,-2048,-1536,-1024,-512,-16,-8,-4,-2,-1,0,1,2,4,8,16,512,1024,1536,2048,2560,3072,3584,4096)) {
        $p=$expected+$delta
        if ($p -lt 0 -or $p -gt $Stream.Length-32) { continue }
        $q=Get-FatHeader $Stream $Bpb $FatIndex $p
        if ($q.ReservedEntriesValid -or $q.LooksLikeBootSector) {
            [void]$hits.Add([pscustomobject]@{Offset=$p;DeltaBytes=$delta;ReservedEntriesValid=$q.ReservedEntriesValid;LooksLikeBootSector=$q.LooksLikeBootSector;First32Hex=$q.First32Hex})
        }
    }
    return @($hits)
}
function Compare-FatCopies {
    param([System.IO.FileStream]$Stream,$Bpb,[long]$MaxBytes=67108864)
    if ($Bpb.FatCount -lt 2) { return [pscustomobject]@{Available=$false;Reason='Only one FAT'} }
    $limit=[long][math]::Min($Bpb.FatBytes,[math]::Max(0,$MaxBytes))
    $totalDiff=[long]0; $samples=New-Object System.Collections.ArrayList
    for($p=[long]0;$p -lt $limit;$p+=[long]65536) {
        $n=[int][math]::Min(65536, $limit-$p)
        $a=Read-DBytes $Stream ([long]$Bpb.FatOffset+$p) $n
        $b=Read-DBytes $Stream ([long]$Bpb.FatOffset+$Bpb.FatBytes+$p) $n
        for($i=0;$i -lt $n;$i++) {
            if ($a[$i] -ne $b[$i]) {
                $totalDiff++
                if ($samples.Count -lt 20) { [void]$samples.Add([pscustomobject]@{RelativeByteOffset=$p+$i;Fat1Byte=[int]$a[$i];Fat2Byte=[int]$b[$i]}) }
            }
        }
    }
    return [pscustomobject]@{Available=$true;ComparedBytes=$limit;FatBytes=$Bpb.FatBytes;Complete=($limit -eq $Bpb.FatBytes);DifferentBytes=$totalDiff;EqualWithinComparedRange=($totalDiff -eq 0);FirstDifferences=@($samples);MirroringDisabled=$Bpb.MirrorDisabled;ActiveFat=$Bpb.ActiveFat}
}
function Trace-FatChain {
    param([System.IO.FileStream]$Stream,$Bpb,[int]$FatIndex,[uint32]$Start,[int]$MaxSteps=4096)
    $visited=New-Object 'System.Collections.Generic.HashSet[uint32]'
    $chain=New-Object System.Collections.ArrayList
    $cur=[uint32]$Start; $reason='Limit';$bad=$false
    for ($step=0;$step -lt $MaxSteps;$step++) {
        if ($cur -lt 2 -or [long]$cur -gt $Bpb.ClusterCount+1) { $reason='ClusterOutOfRange';$bad=$true;break }
        if (-not $visited.Add($cur)) { $reason='Loop';$bad=$true;break }
        if ($chain.Count -lt 64) { [void]$chain.Add($cur) }
        $next=Get-FatEntry $Stream $Bpb $FatIndex $cur
        if ($null -eq $next) { $reason='EntryOutOfRange';$bad=$true;break }
        if ($next -ge 0x0FFFFFF8) { $reason='EndOfChain';break }
        if ($next -eq 0) { $reason='UnexpectedFree';$bad=$true;break }
        if ($next -eq 0x0FFFFFF7) { $reason='BadCluster';$bad=$true;break }
        if ($next -eq 1 -or ($next -ge 0x0FFFFFF0 -and $next -le 0x0FFFFFF6)) { $reason='ReservedValue';$bad=$true;break }
        if ($next -lt 2 -or [long]$next -gt $Bpb.ClusterCount+1) { $reason='NextOutOfRange';$bad=$true;break }
        $cur=[uint32]$next
    }
    return [pscustomobject]@{Start=$Start;FatIndex=$FatIndex;StopReason=$reason;Anomalous=$bad;Visited=$visited.Count;ClusterSample=@($chain);SampleTruncated=($visited.Count -gt $chain.Count);StepCap=$MaxSteps}
}
function Get-DirectoryProbe {
    param([System.IO.FileStream]$Stream,$Bpb,[int]$FatIndex=0,[int]$MaxEntries=32)
    $start=[uint32]$Bpb.RootCluster
    $pos=[long]$Bpb.DataOffset+([long]$start-2)*$Bpb.ClusterBytes
    if ($pos -lt 0 -or $pos -gt $Stream.Length-32) { return [pscustomobject]@{Status='OutsideImage';Entries=@()} }
    $readBytes=[int][math]::Min([long]$MaxEntries*32,[long]$Bpb.ClusterBytes)
    if ($readBytes -lt 32) {return [pscustomobject]@{Status='ClusterTooSmall';Entries=@()} }
    $raw=Read-DBytes $Stream $pos $readBytes
    $entries=New-Object System.Collections.ArrayList
    for($i=0;$i -lt $readBytes;$i+=32) {
        if ($raw[$i] -eq 0) { break }
        if ($raw[$i] -eq 0xE5) {continue}
        $attr=[int]$raw[$i+11]
        if ($attr -eq 0x0F) { [void]$entries.Add([pscustomobject]@{Index=$i/32;Kind='LFN';Name=$null;Cluster=$null;Size=$null;FatState='NotApplicable'});continue }
        $name=[Text.Encoding]::ASCII.GetString($raw,$i,11).Trim()
        $clus=[uint32](([uint32](Get-U16 $raw ($i+20)) -shl 16) -bor [uint32](Get-U16 $raw ($i+26)))
        $size=[uint32](Get-U32 $raw ($i+28))
        $state='NoCluster'; if ($clus -gt 0) {
            if ([long]$clus -gt $Bpb.ClusterCount+1 -or $clus -lt 2) { $state='OutOfRange' }
            else {
                $value=Get-FatEntry $Stream $Bpb $FatIndex $clus
                if ($value -eq 0) { $state='FATClaimsFree' } elseif ($value -eq 0x0FFFFFF7) {$state='Bad'} else {$state='AllocatedOrChained'}
            }
        }
        [void]$entries.Add([pscustomobject]@{Index=$i/32;Kind='Short';Name=$name;Attr=$attr;Cluster=$clus;Size=$size;FatState=$state})
    }
    return [pscustomobject]@{Status='Read';Cluster=$start;ByteOffset=$pos;Entries=@($entries)}
}
function Get-FsInfoProbe {
    param([System.IO.FileStream]$Stream,$Bpb)
    $sec=[int]$Bpb.FsInfoSector
    if ($sec -le 0 -or $sec -ge $Bpb.ReservedSectors) {return [pscustomobject]@{Available=$false;Reason='Sector out of reserved range'} }
    $p=[long]$Bpb.VolumeOffset+[long]$sec*$Bpb.BytesPerSector
    $b=Read-DBytes $Stream $p 512
    $valid=((Get-U32 $b 0) -eq 0x41615252 -and (Get-U32 $b 484) -eq 0x61417272 -and (Get-U32 $b 508) -eq [Convert]::ToUInt32('AA550000',16))
    return [pscustomobject]@{Available=$true;Offset=$p;SignaturesValid=$valid;FreeClusterCount=(Get-U32 $b 488);NextFreeHint=(Get-U32 $b 492)}
}
function Get-BackupProbe {
    param([System.IO.FileStream]$Stream,$Bpb)
    $sec=[int]$Bpb.BackupBootSector
    if ($sec -le 0 -or $sec -ge $Bpb.ReservedSectors) { return [pscustomobject]@{Available=$false;Reason='No valid backup BPB pointer'} }
    $p=[long]$Bpb.VolumeOffset+[long]$sec*$Bpb.BytesPerSector
    $a=Read-DBytes $Stream $Bpb.VolumeOffset 512
    $b=Read-DBytes $Stream $p 512
    $diff=0;for($i=0;$i -lt 512;$i++){if($a[$i] -ne $b[$i]){$diff++}}
    return [pscustomobject]@{Available=$true;Offset=$p;DifferentBytes=$diff;BPBFieldsIdentical=([BitConverter]::ToString($a,11,79) -eq [BitConverter]::ToString($b,11,79));BootSignatureValid=($b[510] -eq 0x55 -and $b[511] -eq 0xAA)}
}
function Get-TeamDFat32Diagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ImagePath,
        [long]$VolumeOffset=-1,
        [long]$MaxFatCompareBytes=67108864,
        [int]$MaxRootChainSteps=4096,
        [switch]$IncludePrivateMetadata
    )
    if ($ImagePath -match '^(\\\\\.\\|\\\\\?\\|[\\/]dev[\\/])') { throw 'Raw device paths are prohibited. Use an ordinary IMG file.' }
    $resolved=(Resolve-Path -LiteralPath $ImagePath -ErrorAction Stop).ProviderPath
    $file=[IO.FileInfo]$resolved
    if (-not $file.Exists -or $file.Length -lt 512) {throw 'IMG file not found or shorter than one sector'}
    # Enforce read-only FileAccess and FileShare.Read, never write to source.
    $script:DBytesRead=[long]0
    $s=[System.IO.File]::Open($resolved,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $mbr=@(Get-MbrPartitions $s)
        $candidates=New-Object System.Collections.ArrayList
        if ($VolumeOffset -ge 0) { [void]$candidates.Add([long]$VolumeOffset) }
        else {
            [void]$candidates.Add([long]0)
            foreach($p in $mbr) { if ($p.ByteOffset -lt $s.Length) { [void]$candidates.Add([long]$p.ByteOffset) } }
            foreach($v in @(512,32256,1048576,2097152,4194304)) { if ($v -lt $s.Length) { [void]$candidates.Add([long]$v) } }
        }
        $probes=New-Object System.Collections.ArrayList
        foreach($off in ($candidates | Select-Object -Unique)) {
            $q=Get-BpbProbe $s ([long]$off)
            if ($null -ne $q) { [void]$probes.Add($q) }
        }
        $selected=$null
        if ($VolumeOffset -ge 0) { $selected=@($probes | Where-Object {$_.VolumeOffset -eq $VolumeOffset}) | Select-Object -First 1 }
        else { $selected=$probes | Where-Object {$_.GeometrySafe -and $_.BootSignature -eq '55 AA'} | Sort-Object @{Expression={$_.Findings.Count};Ascending=$true} | Select-Object -First 1 }
        $findings=New-Object System.Collections.ArrayList
        $headers=New-Object System.Collections.ArrayList; $nearby=New-Object System.Collections.ArrayList
        $compare=$null;$chain=$null;$chains=New-Object System.Collections.ArrayList;$dir=$null;$fsinfo=$null;$backup=$null
        $repairCandidates=New-Object System.Collections.ArrayList
        if ($null -eq $selected -or -not $selected.GeometrySafe) {
            Add-Finding $findings 'NO_TRUSTED_GEOMETRY' 'error' 'No plausible FAT32 geometry; FAT offsets are not trusted'
        } else {
            foreach($f in $selected.Findings) { [void]$findings.Add($f) }
            for($i=0;$i -lt [math]::Min($selected.FatCount,2);$i++) {
                $h=Get-FatHeader $s $selected $i; [void]$headers.Add($h)
                if (-not $h.ReservedEntriesValid) {
                    Add-Finding $findings 'FAT_RESERVED_INVALID' 'error' "FAT$($i+1): reserved entries not valid at predicted offset $($h.Offset)"
                    foreach($hit in @(Get-NearbyFatHeaders $s $selected $i)) { [void]$nearby.Add([pscustomobject]@{FatIndex=$i;Hit=$hit}) }
                }
                if ($h.EB58PairRepeated16Times) { Add-Finding $findings 'EB58_REPEATED' 'warning' "FAT$($i+1): EB 58 repeats in first 32 bytes (not a valid FAT header)" }
                if ($h.LooksLikeBootSector) { Add-Finding $findings 'BOOT_AT_FAT_OFFSET' 'warning' "FAT$($i+1): valid-looking boot sector at predicted FAT offset; inspect IMG creation and partition offset" }
            }
            if ($selected.FatCount -gt 1) {
                $compare=Compare-FatCopies $s $selected $MaxFatCompareBytes
                if ($compare.DifferentBytes -gt 0) {Add-Finding $findings 'FATS_DIFFER' 'warning' "FAT copies differ in $($compare.DifferentBytes) compared byte positions"}
                elseif ($headers.Count -eq 2 -and -not $headers[0].ReservedEntriesValid -and -not $headers[1].ReservedEntriesValid) {Add-Finding $findings 'IDENTICAL_CORRUPTION_POSSIBLE' 'warning' 'Both FAT copies match but have invalid reserved entries; matching does not mean healthy'}
            }
            $fatIndex=0;if ($selected.MirrorDisabled) {$fatIndex=$selected.ActiveFat}
            for($i=0;$i -lt [math]::Min($selected.FatCount,2);$i++) { [void]$chains.Add((Trace-FatChain $s $selected $i $selected.RootCluster $MaxRootChainSteps)) }
            $chain=@($chains | Where-Object {$_.FatIndex -eq $fatIndex} | Select-Object -First 1)[0]
            if ($chain.Anomalous) {Add-Finding $findings 'ROOT_CHAIN_ANOMALY' 'error' "Root chain: $($chain.StopReason)"}
            $dir=Get-DirectoryProbe $s $selected $fatIndex
            foreach($e in @($dir.Entries)) {if ($e.FatState -eq 'FATClaimsFree' -or $e.FatState -eq 'OutOfRange') { Add-Finding $findings 'DIR_FAT_CONFLICT' 'warning' "Directory entry index $($e.Index) at cluster $($e.Cluster): $($e.FatState)" }}
            $fsinfo=Get-FsInfoProbe $s $selected
            $backup=Get-BackupProbe $s $selected
            if ($fsinfo.Available -and -not $fsinfo.SignaturesValid) {Add-Finding $findings 'FSINFO_INVALID' 'warning' 'Invalid FSInfo signature(s)'}
            if ($backup.Available -and -not $backup.BPBFieldsIdentical) {Add-Finding $findings 'BACKUP_BPB_DIFF' 'warning' 'Backup and primary BPB fields differ'}
            if ($nearby.Count -gt 0) { [void]$repairCandidates.Add([pscustomobject]@{Id='D-OFFSET-01';Action='Re-evaluateVolumeGeometry';Confidence='low';RequiresManualEvidence=$true;WritePermitted=$false;Reason='Plausible FAT/boot patterns also exist near predicted offsets; possible wrong offset'}) }
            if ($headers.Count -eq 2 -and $headers[0].ReservedEntriesValid -ne $headers[1].ReservedEntriesValid) {
                [void]$repairCandidates.Add([pscustomobject]@{Id='D-FAT-RESERVED-01';Action='CompareValidFatCopyWithInvalidCopy';Confidence='low';RequiresManualEvidence=$true;WritePermitted=$false;Reason='One FAT has a valid header; never assume other FAT can safely be replaced'})
            }
            if ($headers.Count -gt 0 -and @($headers | Where-Object {-not $_.ReservedEntriesValid}).Count -gt 0) {
                [void]$repairCandidates.Add([pscustomobject]@{Id='D-READ-01';Action='ReimageAndVerifyReadOffsets';Confidence='medium';RequiresManualEvidence=$true;WritePermitted=$false;Reason='Confirm source sector mapping, imaging command, and raw hexdumps before treating bytes as corruption'})
            }
        }
        $first=Read-DBytes $s 0 ([int][math]::Min(4096,$s.Length))
        $last=Read-DBytes $s ([long][math]::Max(0,$s.Length-4096)) ([int][math]::Min(4096,$s.Length))
        if (-not $IncludePrivateMetadata) {
            foreach($bpb in @($probes)) { $bpb.OEMName='<redacted>'; $bpb.VolumeLabel='<redacted>' }
            foreach($h in @($headers)) { $h.First32Hex='<redacted>' }
            foreach($n in @($nearby)) { $n.Hit.First32Hex='<redacted>' }
            if ($null -ne $dir) { foreach($e in @($dir.Entries)) { $e.Name=$null } }
            if ($null -ne $compare -and $compare.Available) {
                foreach($d in @($compare.FirstDifferences)) {$d.Fat1Byte=$null;$d.Fat2Byte=$null}
            }
        }
        $reportInput='<redacted>'; if ($IncludePrivateMetadata) { $reportInput=$resolved }
        return [pscustomobject]@{
            Schema='chappy.teamD.readonly.v1'; CreatedUtc=[DateTime]::UtcNow.ToString('o'); Mode='READ_ONLY'; WritePermitted=$false
            Image=[pscustomobject]@{Path=$reportInput;SizeBytes=$s.Length;FirstSampleSha256=(Get-SampleSha256 $first);LastSampleSha256=(Get-SampleSha256 $last);SamplingOnly=$true}
            PartitionCandidates=$mbr; BootProbes=@($probes); SelectedBoot=$selected; FatHeaders=@($headers); NearbyOffsets=@($nearby)
            FatComparison=$compare; RootChain=$chain; RootChains=@($chains); RootDirectory=$dir; FsInfo=$fsinfo; BackupBoot=$backup
            Findings=@($findings); RepairCandidates=@($repairCandidates)
            Metrics=[pscustomobject]@{BytesRead=$script:DBytesRead;RootEntriesChecked=$(if ($null -eq $dir) {0} else {$dir.Entries.Count})}
            Conclusions='Diagnostic evidence only. Repeated EB58 is not proof of physical corruption. No repair or write performed.'
        }
    } finally { $s.Dispose() }
}
function Export-TeamDFat32Diagnostic {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ImagePath,[Parameter(Mandatory=$true)][string]$ReportPath,[long]$VolumeOffset=-1,[switch]$IncludePrivateMetadata)
    $source=(Resolve-Path -LiteralPath $ImagePath -ErrorAction Stop).ProviderPath
    $fullReport=[IO.Path]::GetFullPath($ReportPath)
    if ([string]::Equals($source,$fullReport,[StringComparison]::OrdinalIgnoreCase)) {throw 'Report destination may not overwrite image'}
    $report=Get-TeamDFat32Diagnostic -ImagePath $ImagePath -VolumeOffset $VolumeOffset -IncludePrivateMetadata:$IncludePrivateMetadata
    $json=$report | ConvertTo-Json -Depth 15
    [IO.File]::WriteAllText($fullReport,$json,(New-Object Text.UTF8Encoding($false)))
    return $report
}
function Get-ChappyFatDiagnostics {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ImagePath,[long]$VolumeOffset=-1,[long]$MaxFatCompareBytes=67108864)
    $r=Get-TeamDFat32Diagnostic -ImagePath $ImagePath -VolumeOffset $VolumeOffset -MaxFatCompareBytes $MaxFatCompareBytes
    $errors=@($r.Findings | Where-Object {$_.Severity -eq 'error'} | ForEach-Object {$_.Code})
    $warnings=@($r.Findings | Where-Object {$_.Severity -ne 'error'} | ForEach-Object {$_.Code})
    $incomplete=($null -eq $r.SelectedBoot -or ($null -ne $r.FatComparison -and -not $r.FatComparison.Complete) -or ($null -ne $r.RootChain -and $r.RootChain.StopReason -eq 'Limit'))
    $status='ok'; if ($errors.Count -gt 0 -or $incomplete) {$status='partial'}
    return [pscustomobject]@{
        schemaVersion='1';team='D';status=$status;scanIncomplete=[bool]$incomplete
        items=@($r.RepairCandidates);warnings=$warnings;errors=$errors
        metrics=[pscustomobject]@{bytesRead=$r.Metrics.BytesRead;entriesChecked=$r.Metrics.RootEntriesChecked}
        diagnostic=$r
    }
}
Export-ModuleMember -Function Get-TeamDFat32Diagnostic,Export-TeamDFat32Diagnostic,Get-ChappyFatDiagnostics