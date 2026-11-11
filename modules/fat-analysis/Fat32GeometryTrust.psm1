#Requires -Version 5.1
# Team D R4-P1: synthetic-only bounded MBR/BPB/backup-VBR/FSInfo observations.
# This module NEVER opens paths, writes, repairs or authorizes real-image scanning.
Set-StrictMode -Version 2.0

function Read-D4Sector {
    param([System.IO.Stream]$Stream,[long]$Offset,[ref]$Used,[int]$Maximum)
    if($Offset -lt 0) {throw 'negative probe offset'}
    if(([long]$Used.Value+512) -gt $Maximum) {return $null}
    if($Offset -gt $Stream.Length) {return ,([byte[]]@())}
    $count=[int][Math]::Min(512,($Stream.Length-$Offset))
    $bytes=New-Object 'byte[]' $count
    if($count -eq 0){return ,$bytes}
    [void]$Stream.Seek($Offset,[System.IO.SeekOrigin]::Begin)
    $at=0
    while($at -lt $count) {
        $n=$Stream.Read($bytes,$at,($count-$at))
        if($n -le 0){break}
        $at+=$n
    }
    $Used.Value=[long]$Used.Value+$at
    if($at -eq $count){return ,$bytes}
    $short=New-Object 'byte[]' $at
    if($at -gt 0){[Array]::Copy($bytes,0,$short,0,$at)}
    return ,$short
}

function Get-D4Bpb {
    param([byte[]]$Sector)
    if($Sector.Length -lt 512){return $null}
    $bytesPerSector=[long][BitConverter]::ToUInt16($Sector,11)
    $spc=[long]$Sector[13]
    $reserved=[long][BitConverter]::ToUInt16($Sector,14)
    $fats=[long]$Sector[16]
    $rootEntries=[long][BitConverter]::ToUInt16($Sector,17)
    $total16=[long][BitConverter]::ToUInt16($Sector,19)
    $fat16=[long][BitConverter]::ToUInt16($Sector,22)
    $total=[long][BitConverter]::ToUInt32($Sector,32)
    $fatSectors=[long][BitConverter]::ToUInt32($Sector,36)
    $rootCluster=[long][BitConverter]::ToUInt32($Sector,44)
    $fsSector=[long][BitConverter]::ToUInt16($Sector,48)
    $backupSector=[long][BitConverter]::ToUInt16($Sector,50)
    $jump=($Sector[0] -eq 0xE9 -or
           ($Sector[0] -eq 0xEB -and $Sector[2] -eq 0x90))
    return [pscustomobject]@{
        jumpLike=$jump
        signature=($Sector[510] -eq 0x55 -and $Sector[511] -eq 0xAA)
        bytesPerSector=$bytesPerSector
        sectorsPerCluster=$spc
        reservedSectors=$reserved
        fatCopies=$fats
        rootEntryCount=$rootEntries
        totalSectors16=$total16
        fatSectors16=$fat16
        totalSectors=$total
        fatSectors=$fatSectors
        rootCluster=$rootCluster
        fsInfoSector=$fsSector
        backupBootSector=$backupSector
    }
}

function Get-ChappyFatGeometryTrust {
    <#
    .SYNOPSIS
    Reports why an MBR-based candidate FAT32 layout should NOT yet be trusted.
    .NOTES
    Synthetic-only research. No real-image approval, no repair and no raw output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.IO.Stream]$Stream,
        [ValidateRange(0,3)][int]$PartitionIndex=0,
        [ValidateRange(512,2048)][int]$MaxReadBytes=2048
    )
    if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite){
        throw 'Only readable, seekable, non-writable streams are accepted'
    }
    $used=[long]0
    $reasons=New-Object System.Collections.ArrayList
    $warnings=New-Object System.Collections.ArrayList
    $observed=New-Object System.Collections.ArrayList
    $incomplete=$false;$reject=$false
    $primary=$null;$backup=$null;$fsInfo=$null
    $partStart=$null;$partLength=$null;$partitionType=$null
    $fat1=$null;$fat2=$null;$dataStart=$null;$bpbEnd=$null
    $fatBytes=$null;$dataClusters=$null

    $mbr=Read-D4Sector $Stream 0 ([ref]$used) $MaxReadBytes
    if($null -eq $mbr -or $mbr.Length -ne 512) {
        [void]$reasons.Add('io.mbr_truncated')
        $incomplete=$true
    }else{
        $mbrSig=($mbr[510] -eq 0x55 -and $mbr[511] -eq 0xAA)
        if(-not $mbrSig){[void]$reasons.Add('mbr.signature_missing');$reject=$true}
        $entry=446+16*$PartitionIndex
        $bootFlag=[int]$mbr[$entry]
        $partitionType=[int]$mbr[$entry+4]
        $lbaStart=[long][BitConverter]::ToUInt32($mbr,$entry+8)
        $lbaCount=[long][BitConverter]::ToUInt32($mbr,$entry+12)
        $partStart=$lbaStart*512L
        $partLength=$lbaCount*512L
        [void]$observed.Add('mbr.partition_entry_read')
        if($bootFlag -ne 0 -and $bootFlag -ne 0x80){
            [void]$reasons.Add('mbr.boot_flag_invalid');$reject=$true
        }
        if(@(0x0B,0x0C,0x1B,0x1C) -cnotcontains $partitionType){
            [void]$reasons.Add('mbr.partition_type_not_fat32');$reject=$true
        }
        if($lbaStart -eq 0 -or $lbaCount -eq 0){
            [void]$reasons.Add('mbr.empty_or_zero_start');$reject=$true
        }else{
            $partEnd=$partStart+$partLength
            if($partEnd -gt $Stream.Length){
                [void]$reasons.Add('geometry.partition_exceeds_stream')
                $incomplete=$true;$reject=$true
            }
            $vbr=Read-D4Sector $Stream $partStart ([ref]$used) $MaxReadBytes
            if($null -eq $vbr){
                [void]$reasons.Add('budget.primary_vbr_unread')
                $incomplete=$true
            }elseif($vbr.Length -lt 512){
                [void]$reasons.Add('io.primary_vbr_truncated')
                $incomplete=$true;$reject=$true
            }else{
                $primary=Get-D4Bpb $vbr
                [void]$observed.Add('vbr.primary_read')
                if(-not $primary.jumpLike){
                    [void]$reasons.Add('bpb.boot_jump_invalid');$reject=$true
                }
                if(-not $primary.signature){
                    [void]$reasons.Add('bpb.signature_missing');$reject=$true
                }
                $bps=[long]$primary.bytesPerSector
                $spc=[long]$primary.sectorsPerCluster
                $bpsValid=@(512,1024,2048,4096) -contains $bps
                if(-not $bpsValid){
                    [void]$reasons.Add('bpb.bytes_per_sector_invalid');$reject=$true
                }
                if($spc -lt 1 -or $spc -gt 128 -or ($spc -band ($spc-1)) -ne 0){
                    [void]$reasons.Add('bpb.sectors_per_cluster_invalid');$reject=$true
                }elseif($bpsValid -and ($bps*$spc) -gt 32768){
                    [void]$reasons.Add('bpb.cluster_bytes_over_policy');$reject=$true
                }
                if($primary.reservedSectors -lt 2){
                    [void]$reasons.Add('bpb.reserved_sectors_invalid');$reject=$true
                }
                if($primary.fatCopies -ne 2){
                    [void]$reasons.Add('bpb.fat_copy_count_not_two');$reject=$true
                }
                if($primary.fatSectors -lt 1 -or $primary.totalSectors -lt 1){
                    [void]$reasons.Add('bpb.zero_total_or_fat_sectors');$reject=$true
                }
                if($primary.rootEntryCount -ne 0 -or $primary.totalSectors16 -ne 0 -or $primary.fatSectors16 -ne 0){
                    [void]$reasons.Add('bpb.fat32_legacy_fields_nonzero');$reject=$true
                }
                if($bpsValid -and $spc -ge 1 -and $spc -le 128 -and ($spc -band ($spc-1)) -eq 0 -and
                    $primary.reservedSectors -ge 2 -and $primary.fatCopies -gt 0 -and
                    $primary.totalSectors -gt 0 -and $primary.fatSectors -gt 0){
                    $bpbEnd=$partStart+$primary.totalSectors*$bps
                    if($bpbEnd -gt ($partStart+$partLength)){
                        [void]$reasons.Add('geometry.bpb_exceeds_mbr_partition');$reject=$true
                    }
                    if($bpbEnd -gt $Stream.Length){
                        [void]$reasons.Add('geometry.bpb_exceeds_stream');$incomplete=$true;$reject=$true
                    }
                    if($bps -ne 512){
                        [void]$reasons.Add('geometry.mbr_512_bpb_sector_size_differs')
                        $reject=$true
                    }
                    $fatBytes=$primary.fatSectors*$bps
                    $fat1=$partStart+$primary.reservedSectors*$bps
                    $fat2=$fat1+$fatBytes
                    $dataStart=$fat1+$primary.fatCopies*$fatBytes
                    if($dataStart -ge $bpbEnd -or $fat2+$fatBytes -gt $bpbEnd){
                        [void]$reasons.Add('geometry.fat_regions_exceed_volume');$reject=$true
                    }else{
                        $dataSectors=$primary.totalSectors-$primary.reservedSectors-$primary.fatCopies*$primary.fatSectors
                        if($dataSectors -le 0){
                            [void]$reasons.Add('geometry.no_data_region');$reject=$true
                        }else{
                            $dataClusters=[long][Math]::Floor($dataSectors/$spc)
                            if($dataClusters -gt 268435438 -or ($fatBytes/4) -lt ($dataClusters+2)){
                                [void]$reasons.Add('geometry.fat_entries_insufficient');$reject=$true
                            }
                            if($primary.rootCluster -lt 2 -or $primary.rootCluster -gt ($dataClusters+1)){
                                [void]$reasons.Add('geometry.root_cluster_out_of_range');$reject=$true
                            }
                        }
                    }
                }
                $fsIndex=[long]$primary.fsInfoSector
                $backupIndex=[long]$primary.backupBootSector
                $fsAllowed=($fsIndex -gt 0 -and $fsIndex -lt $primary.reservedSectors)
                $backupAllowed=($backupIndex -gt 0 -and $backupIndex -lt $primary.reservedSectors)
                if(-not $fsAllowed -or $fsIndex -eq $backupIndex){
                    [void]$reasons.Add('bpb.fsinfo_location_invalid');$reject=$true
                }
                if(-not $backupAllowed){
                    [void]$reasons.Add('bpb.backup_vbr_location_invalid');$reject=$true
                }
                # Only probe offsets fully inside the claimed MBR partition.
                if($bpsValid -and $backupAllowed -and
                    (($backupIndex+1)*$bps) -le $partLength){
                    $backupRaw=Read-D4Sector $Stream ($partStart+$backupIndex*$bps) ([ref]$used) $MaxReadBytes
                    if($null -eq $backupRaw){
                        [void]$reasons.Add('budget.backup_vbr_unread');$incomplete=$true
                    }elseif($backupRaw.Length -ne 512){
                        [void]$reasons.Add('io.backup_vbr_truncated');$incomplete=$true;$reject=$true
                    }else{
                        $backup=Get-D4Bpb $backupRaw
                        [void]$observed.Add('vbr.backup_read')
                        $same=$true
                        foreach($key in @('bytesPerSector','sectorsPerCluster','reservedSectors','fatCopies','rootEntryCount','totalSectors16','fatSectors16','totalSectors','fatSectors','rootCluster','fsInfoSector','backupBootSector')){
                            if($primary.$key -ne $backup.$key){$same=$false;break}
                        }
                        if(-not $same -or -not $backup.signature -or -not $backup.jumpLike){
                            [void]$reasons.Add('vbr.backup_geometry_or_signature_mismatch');$reject=$true
                        }
                    }
                }
                if($bpsValid -and $fsAllowed -and ($fsIndex+1)*$bps -le $partLength){
                    $fsRaw=Read-D4Sector $Stream ($partStart+$fsIndex*$bps) ([ref]$used) $MaxReadBytes
                    if($null -eq $fsRaw){
                        [void]$reasons.Add('budget.fsinfo_unread');$incomplete=$true
                    }elseif($fsRaw.Length -ne 512){
                        [void]$reasons.Add('io.fsinfo_truncated');$incomplete=$true;$reject=$true
                    }else{
                        [void]$observed.Add('fsinfo.read')
                        $fsInfo=[pscustomobject]@{
                            leadSignatureObserved=([BitConverter]::ToUInt32($fsRaw,0) -eq 0x41615252)
                            structureSignatureObserved=([BitConverter]::ToUInt32($fsRaw,484) -eq 0x61417272)
                            trailerSignatureObserved=([BitConverter]::ToUInt32($fsRaw,508) -eq ([Convert]::ToUInt32('AA550000',16)))
                        }
                        if(-not $fsInfo.leadSignatureObserved -or
                            -not $fsInfo.structureSignatureObserved -or
                            -not $fsInfo.trailerSignatureObserved){
                            [void]$reasons.Add('fsinfo.signatures_invalid');$reject=$true
                        }
                        $free=[long][BitConverter]::ToUInt32($fsRaw,488)
                        $next=[long][BitConverter]::ToUInt32($fsRaw,492)
                        if($null -ne $dataClusters){
                            if(($free -ne 4294967295 -and $free -gt $dataClusters) -or
                               ($next -ne 4294967295 -and ($next -lt 2 -or $next -gt ($dataClusters+1)))){
                                [void]$reasons.Add('fsinfo.count_or_hint_out_of_range');$reject=$true
                            }
                        }
                    }
                }
            }
        }
    }
    # Only observed evidence is reported. Signature matches do NOT authorize use.
    [void]$warnings.Add('geometry.candidate_only_not_authenticated')
    [void]$warnings.Add('signature.match_not_proof_of_health')
    [void]$warnings.Add('real_master_img_trial_not_authorized')
    if($incomplete){[void]$warnings.Add('coverage.incomplete')}
    return [pscustomobject]@{
        schemaVersion='1'
        team='D'
        mode='read_only_geometry_trust_guard'
        status=$(if($incomplete){'partial'}else{'ok'})
        scanIncomplete=$incomplete
        trustDecision=$(if($reject){'reject'}elseif($incomplete -or $null -eq $primary -or $null -eq $backup -or $null -eq $fsInfo){'insufficient_evidence'}else{'plausible_unverified'})
        writePermitted=$false
        mbr=[pscustomobject]@{
            partitionIndex=$PartitionIndex
            partitionType=$partitionType
            partitionOffsetBytes=$partStart
            partitionLengthBytes=$partLength
        }
        geometry=[pscustomobject]@{
            fat1OffsetBytes=$fat1
            fat2OffsetBytes=$fat2
            fatLengthBytes=$fatBytes
            dataStartOffsetBytes=$dataStart
            volumeEndExclusiveBytes=$bpbEnd
            dataClusterCount=$dataClusters
        }
        backupVbrRead=($null -ne $backup)
        fsInfoRead=($null -ne $fsInfo)
        reasons=@($reasons.ToArray())
        warnings=@($warnings.ToArray())
        observations=@($observed.ToArray())
        errors=@()
        metrics=[pscustomobject]@{
            bytesRead=$used
            maxReadBytes=$MaxReadBytes
            probesObserved=$observed.Count
            sourceLengthBytes=$Stream.Length
        }
    }
}
Export-ModuleMember -Function Get-ChappyFatGeometryTrust
