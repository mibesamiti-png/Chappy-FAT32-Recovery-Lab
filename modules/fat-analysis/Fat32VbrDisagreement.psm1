#Requires -Version 5.1
# Team D R5: synthetic-only bounded primary/backup FAT32 candidate evidence.
# Never opens a path, writes bytes, repairs, chooses a geometry or approves a real IMG.
Set-StrictMode -Version 2.0

function Read-D5Sector {
    param([IO.Stream]$Stream,[long]$Offset,[ref]$Used,[int]$Budget)
    if($Offset -lt 0){throw 'Negative offset'}
    if(([long]$Used.Value+512) -gt $Budget){return $null}
    if($Offset -gt $Stream.Length){return ,([byte[]]@())}
    $size=[int][Math]::Min(512,($Stream.Length-$Offset))
    $b=New-Object 'byte[]' $size
    if($size -eq 0){return ,$b}
    [void]$Stream.Seek($Offset,[IO.SeekOrigin]::Begin)
    $at=0
    while($at -lt $size){
        $n=$Stream.Read($b,$at,($size-$at))
        if($n -le 0){break}
        $at+=$n
    }
    $Used.Value=[long]$Used.Value+$at
    if($at -eq $size){return ,$b}
    $short=New-Object 'byte[]' $at
    if($at -gt 0){[Array]::Copy($b,0,$short,0,$at)}
    return ,$short
}
function Get-D5Bpb {
    param([byte[]]$B)
    if($null -eq $B -or $B.Length -ne 512){return $null}
    return [pscustomobject]@{
        bootJump=($B[0] -eq 0xE9 -or ($B[0] -eq 0xEB -and $B[2] -eq 0x90))
        signature=($B[510] -eq 0x55 -and $B[511] -eq 0xAA)
        bytesPerSector=[long][BitConverter]::ToUInt16($B,11)
        sectorsPerCluster=[long]$B[13]
        reservedSectors=[long][BitConverter]::ToUInt16($B,14)
        fatCopies=[long]$B[16]
        rootEntryCount=[long][BitConverter]::ToUInt16($B,17)
        total16=[long][BitConverter]::ToUInt16($B,19)
        fat16=[long][BitConverter]::ToUInt16($B,22)
        hiddenSectors=[long][BitConverter]::ToUInt32($B,28)
        totalSectors=[long][BitConverter]::ToUInt32($B,32)
        fatSectors=[long][BitConverter]::ToUInt32($B,36)
        extendedFlags=[long][BitConverter]::ToUInt16($B,40)
        version=[long][BitConverter]::ToUInt16($B,42)
        rootCluster=[long][BitConverter]::ToUInt32($B,44)
        fsInfoSector=[long][BitConverter]::ToUInt16($B,48)
        backupBootSector=[long][BitConverter]::ToUInt16($B,50)
    }
}
function Get-D5Candidate {
    param([string]$Role,$ProbeOffset,$Bpb,[string]$ReadProblem,[long]$Start,[long]$Length,
        [long]$StreamLength,$Fs,[long]$FsLocation,[bool]$BadMbr)
    $issues=New-Object System.Collections.ArrayList
    $unknown=New-Object System.Collections.ArrayList
    $fat1=$null;$fat2=$null;$fatBytes=$null;$end=$null;$clusters=$null
    if($ReadProblem){[void]$unknown.Add($ReadProblem)}
    elseif($null -eq $Bpb){[void]$unknown.Add('vbr.not_observed')}
    else {
        if(-not $Bpb.bootJump){[void]$issues.Add('vbr.jump_invalid')}
        if(-not $Bpb.signature){[void]$issues.Add('vbr.signature_invalid')}
        if($Bpb.bytesPerSector -ne 512){[void]$issues.Add('bpb.sector_size_unsupported')}
        $spc=$Bpb.sectorsPerCluster
        $spcValid=($spc -ge 1 -and $spc -le 128 -and ($spc -band ($spc-1)) -eq 0)
        if(-not $spcValid){[void]$issues.Add('bpb.cluster_sectors_invalid')}
        elseif($Bpb.bytesPerSector*$spc -gt 32768){[void]$issues.Add('bpb.cluster_bytes_too_large')}
        if($Bpb.reservedSectors -lt 2){[void]$issues.Add('bpb.reserved_too_small')}
        if($Bpb.fatCopies -ne 2){[void]$issues.Add('bpb.fat_copy_count_invalid')}
        if($Bpb.totalSectors -le 0 -or $Bpb.fatSectors -le 0){
            [void]$issues.Add('bpb.total_or_fat_zero')
        }
        if($Bpb.rootEntryCount -ne 0 -or $Bpb.total16 -ne 0 -or $Bpb.fat16 -ne 0){
            [void]$issues.Add('bpb.legacy_fields_nonzero')
        }
        if($Bpb.version -ne 0){[void]$issues.Add('bpb.version_unsupported')}
        # The fixed two-copy mirror observer cannot interpret a BPB that
        # disables mirroring/selects one active FAT, or sets reserved flag bits.
        # Reject even if BOTH boot sectors match this unsafe configuration.
        if($Bpb.extendedFlags -ne 0){
            [void]$issues.Add('bpb.extended_flags_not_mirrored_fixed_compatible')
        }
        # BPB_HiddSec is the containing partition start in sectors. A
        # numerical agreement between two VBRs does not override the MBR.
        if($null -ne $Start -and $Bpb.hiddenSectors -ne [long]($Start/512)){
            [void]$issues.Add('bpb.hidden_sectors_disagrees_with_mbr')
        }
        if($Bpb.bytesPerSector -eq 512 -and $spcValid -and
            $Bpb.fatCopies -gt 0 -and $Bpb.reservedSectors -ge 2 -and
            $Bpb.totalSectors -gt 0 -and $Bpb.fatSectors -gt 0) {
            $fatBytes=[long]($Bpb.fatSectors*512)
            $fat1=[long]($Start+$Bpb.reservedSectors*512)
            $fat2=[long]($fat1+$fatBytes)
            $end=[long]($Start+$Bpb.totalSectors*512)
            $dataStart=[long]($fat1+$Bpb.fatCopies*$fatBytes)
            if($end -gt ($Start+$Length) -or $end -gt $StreamLength){
                [void]$issues.Add('geometry.exceeds_partition_or_stream')
            }
            if($dataStart -ge $end -or ($fat2+$fatBytes) -gt $end){
                [void]$issues.Add('geometry.fat_overruns_volume')
            }else{
                $dataSectors=[long]($Bpb.totalSectors-$Bpb.reservedSectors-$Bpb.fatCopies*$Bpb.fatSectors)
                $clusters=[long][Math]::Floor($dataSectors/$spc)
                # FAT32 classification requires >=65525 data clusters.
                # An in-range tiny FAT16-size layout with a FAT32-like BPB
                # cannot be promoted to a FAT32 fixed-sampler candidate.
                if($clusters -lt 65525){
                    [void]$issues.Add('geometry.below_fat32_cluster_threshold')
                }
                if($clusters -lt 1 -or $clusters -gt 268435438 -or $fatBytes/4 -lt ($clusters+2)){
                    [void]$issues.Add('geometry.fat_entry_capacity_insufficient')
                }
                if($Bpb.rootCluster -lt 2 -or $Bpb.rootCluster -gt ($clusters+1)){
                    [void]$issues.Add('geometry.root_cluster_out_of_range')
                }
            }
        }
        if($Bpb.backupBootSector -lt 1 -or $Bpb.backupBootSector -ge $Bpb.reservedSectors){
            [void]$issues.Add('bpb.backup_locator_invalid')
        }
        if($Bpb.fsInfoSector -lt 1 -or $Bpb.fsInfoSector -ge $Bpb.reservedSectors -or
            $Bpb.fsInfoSector -eq $Bpb.backupBootSector){
            [void]$issues.Add('bpb.fsinfo_locator_invalid')
        }
        if($null -eq $Fs -or $Bpb.fsInfoSector -ne $FsLocation){
            [void]$unknown.Add('fsinfo.for_candidate_not_observed')
        }else{
            if(-not $Fs.signaturesValid){[void]$issues.Add('fsinfo.signatures_invalid')}
            if($null -eq $clusters){
                [void]$unknown.Add('fsinfo.capacity_unavailable')
            }elseif(($Fs.free -ne 4294967295 -and $Fs.free -gt $clusters) -or
                ($Fs.next -ne 4294967295 -and ($Fs.next -lt 2 -or $Fs.next -gt ($clusters+1)))){
                [void]$issues.Add('fsinfo.hints_outside_candidate')
            }
        }
    }
    if($BadMbr){[void]$issues.Add('mbr.anchor_unreliable')}
    $grade=$(if($issues.Count -gt 0){'contradicted'}elseif($unknown.Count -gt 0){'insufficient_evidence'}else{'plausible_unverified'})
    return [pscustomobject]@{
        sourceRole=$Role
        probeOffsetBytes=$ProbeOffset
        plausibility=$grade
        confidence=$(if($grade -eq 'insufficient_evidence'){'unknown'}else{'partial'})
        reasonCodes=@($issues.ToArray())
        unknownCodes=@($unknown.ToArray())
        geometry=[pscustomobject]@{
            bytesPerSector=$(if($Bpb){$Bpb.bytesPerSector}else{$null})
            sectorsPerCluster=$(if($Bpb){$Bpb.sectorsPerCluster}else{$null})
            reservedSectors=$(if($Bpb){$Bpb.reservedSectors}else{$null})
            fatCopies=$(if($Bpb){$Bpb.fatCopies}else{$null})
            totalSectors=$(if($Bpb){$Bpb.totalSectors}else{$null})
            hiddenSectors=$(if($Bpb){$Bpb.hiddenSectors}else{$null})
            extendedFlags=$(if($Bpb){$Bpb.extendedFlags}else{$null})
            fatSectors=$(if($Bpb){$Bpb.fatSectors}else{$null})
            rootCluster=$(if($Bpb){$Bpb.rootCluster}else{$null})
            fsInfoSector=$(if($Bpb){$Bpb.fsInfoSector}else{$null})
            backupBootSector=$(if($Bpb){$Bpb.backupBootSector}else{$null})
            fat1OffsetBytes=$fat1
            fat2OffsetBytes=$fat2
            fatLengthBytes=$fatBytes
            volumeEndExclusiveBytes=$end
            dataClusterCount=$clusters
        }
    }
}
function Get-ChappyFatVbrDisagreement {
    <#
    .SYNOPSIS
    Compares primary and primary-declared backup VBR candidates independently,
    without choosing which is correct or authorizing a real-image operation.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [ValidateRange(0,3)][int]$PartitionIndex=0,
        [ValidateRange(512,2048)][int]$MaxReadBytes=2048)
    if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite){
        throw 'Readable seekable non-writable stream required'
    }
    $used=[long]0;$incomplete=$false
    $mbrErrors=New-Object System.Collections.ArrayList
    $observations=New-Object System.Collections.ArrayList
    $warnings=New-Object System.Collections.ArrayList
    $start=$null;$length=$null;$kind=$null
    $primary=$null;$backup=$null;$fs=$null
    $pProblem='';$bProblem=''
    $primaryOffset=$null;$backupOffset=$null;$fsLocation=-1
    $mbr=Read-D5Sector $Stream 0 ([ref]$used) $MaxReadBytes
    if($null -eq $mbr -or $mbr.Length -ne 512) {
        [void]$mbrErrors.Add('io.mbr_truncated')
        $incomplete=$true
    }else{
        [void]$observations.Add('mbr.partition_entry_observed')
        if($mbr[510] -ne 0x55 -or $mbr[511] -ne 0xAA){
            [void]$mbrErrors.Add('mbr.signature_invalid')
        }
        $slot=446+16*$PartitionIndex
        $kind=[int]$mbr[$slot+4]
        $flag=[int]$mbr[$slot]
        $start=[long][BitConverter]::ToUInt32($mbr,$slot+8)*512
        $length=[long][BitConverter]::ToUInt32($mbr,$slot+12)*512
        if($flag -ne 0 -and $flag -ne 128){[void]$mbrErrors.Add('mbr.boot_flag_invalid')}
        if(@(11,12,27,28) -notcontains $kind){[void]$mbrErrors.Add('mbr.type_not_fat32')}
        if($start -eq 0 -or $length -eq 0){[void]$mbrErrors.Add('mbr.partition_empty')}
        if(($start+$length) -gt $Stream.Length){
            [void]$mbrErrors.Add('mbr.partition_exceeds_stream')
            $incomplete=$true
        }
        # Never perform an offset-scanning fallback when the MBR anchor is bad.
        if($mbrErrors.Count -eq 0){
            $primaryOffset=$start
            $pRaw=Read-D5Sector $Stream $start ([ref]$used) $MaxReadBytes
            if($null -eq $pRaw){$pProblem='budget.primary_unread';$incomplete=$true}
            elseif($pRaw.Length -ne 512){$pProblem='io.primary_truncated';$incomplete=$true}
            else{
                $primary=Get-D5Bpb $pRaw
                [void]$observations.Add('vbr.primary_observed')
                $bs=[long]$primary.backupBootSector
                $fsPos=[long]$primary.fsInfoSector
                $bps=[long]$primary.bytesPerSector
                if($bps -ne 512 -or $bs -lt 1 -or $bs -ge $primary.reservedSectors -or
                    (($bs+1)*512) -gt $length){
                    $bProblem='backup.primary_declared_locator_invalid'
                    $incomplete=$true
                }else{
                    $backupOffset=$start+$bs*512
                    $bRaw=Read-D5Sector $Stream $backupOffset ([ref]$used) $MaxReadBytes
                    if($null -eq $bRaw){$bProblem='budget.backup_unread';$incomplete=$true}
                    elseif($bRaw.Length -ne 512){$bProblem='io.backup_truncated';$incomplete=$true}
                    else{
                        $backup=Get-D5Bpb $bRaw
                        [void]$observations.Add('vbr.backup_at_primary_declared_offset')
                    }
                }
                if($bps -eq 512 -and $fsPos -ge 1 -and $fsPos -lt $primary.reservedSectors -and
                    $fsPos -ne $bs -and (($fsPos+1)*512) -le $length) {
                    $fsRaw=Read-D5Sector $Stream ($start+$fsPos*512) ([ref]$used) $MaxReadBytes
                    if($null -eq $fsRaw){$incomplete=$true;[void]$observations.Add('budget.fsinfo_unread')}
                    elseif($fsRaw.Length -ne 512){$incomplete=$true;[void]$observations.Add('io.fsinfo_truncated')}
                    else{
                        $fsLocation=$fsPos
                        $fs=[pscustomobject]@{
                            signaturesValid=(
                                [BitConverter]::ToUInt32($fsRaw,0) -eq ([Convert]::ToUInt32('41615252',16)) -and
                                [BitConverter]::ToUInt32($fsRaw,484) -eq ([Convert]::ToUInt32('61417272',16)) -and
                                [BitConverter]::ToUInt32($fsRaw,508) -eq ([Convert]::ToUInt32('AA550000',16))
                            )
                            free=[long][BitConverter]::ToUInt32($fsRaw,488)
                            next=[long][BitConverter]::ToUInt32($fsRaw,492)
                        }
                        [void]$observations.Add('fsinfo.at_primary_declared_offset')
                    }
                }else{[void]$observations.Add('fsinfo.primary_locator_invalid')}
            }
        }
    }
    $anchorBad=$mbrErrors.Count -gt 0
    # An invalid MBR prevents both VBR probes. Even if its contradiction is
    # observed, the comparison itself is incomplete and must say so.
    if($anchorBad){$incomplete=$true}
    $pa=Get-D5Candidate -Role 'primary' -ProbeOffset $primaryOffset -Bpb $primary -ReadProblem $pProblem -Start $start -Length $length -StreamLength $Stream.Length -Fs $fs -FsLocation $fsLocation -BadMbr $anchorBad
    $ba=Get-D5Candidate -Role 'backup' -ProbeOffset $backupOffset -Bpb $backup -ReadProblem $bProblem -Start $start -Length $length -StreamLength $Stream.Length -Fs $fs -FsLocation $fsLocation -BadMbr $anchorBad
    $diff=New-Object System.Collections.ArrayList
    if($null -ne $primary -and $null -ne $backup){
        foreach($key in @('bootJump','signature','bytesPerSector','sectorsPerCluster','reservedSectors','fatCopies','rootEntryCount','total16','fat16','hiddenSectors','totalSectors','fatSectors','extendedFlags','version','rootCluster','fsInfoSector','backupBootSector')){
            if($primary.$key -ne $backup.$key){[void]$diff.Add(('bpb.'+$key))}
        }
    }
    $agreement=$(if($null -eq $primary -or $null -eq $backup){'insufficient_evidence'}elseif($diff.Count -gt 0){'disagree'}else{'agree'})
    if($agreement -eq 'disagree'){[void]$warnings.Add('vbr.disagree_no_winner')}
    if($pa.plausibility -eq 'plausible_unverified' -and
       $ba.plausibility -eq 'plausible_unverified' -and $agreement -eq 'disagree'){
        [void]$warnings.Add('vbr.both_plausible_but_incompatible')
    }
    [void]$warnings.Add('backup.locator_from_primary_unverified')
    [void]$warnings.Add('candidate.authenticity_not_established')
    [void]$warnings.Add('real_master_img_trial_not_authorized')
    if($pa.plausibility -eq 'insufficient_evidence' -or $ba.plausibility -eq 'insufficient_evidence'){
        $incomplete=$true
    }
    if($incomplete){[void]$warnings.Add('coverage.incomplete')}
    return [pscustomobject]@{
        schemaVersion='1'
        team='D'
        mode='read_only_vbr_disagreement'
        status=$(if($incomplete){'partial'}else{'ok'})
        scanIncomplete=$incomplete
        agreement=$agreement
        selectedCandidate=$null
        sourceDecision='not_selected'
        writePermitted=$false
        mbr=[pscustomobject]@{
            partitionIndex=$PartitionIndex
            partitionType=$kind
            startOffsetBytes=$start
            lengthBytes=$length
            reasonCodes=@($mbrErrors.ToArray())
        }
        candidates=@($pa,$ba)
        differingFields=@($diff.ToArray())
        warnings=@($warnings.ToArray())
        observations=@($observations.ToArray())
        errors=@()
        metrics=[pscustomobject]@{
            bytesRead=$used
            maxReadBytes=$MaxReadBytes
            differencesCount=$diff.Count
            sourceLengthBytes=$Stream.Length
        }
    }
}
Export-ModuleMember -Function Get-ChappyFatVbrDisagreement
