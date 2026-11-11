#Requires -Version 5.1
# Team D R3-P4: bounded, numeric-only directory/FAT consistency observations.
# No file paths, disk opening, writes, extraction, names or raw data in outputs.
Set-StrictMode -Version 2.0

function Read-DConsistencyBytes {
    param([System.IO.Stream]$Stream,[long]$Offset,[int]$Count)
    if($Offset -lt 0 -or $Count -lt 0 -or $Count -gt 32) {throw 'Invalid bounded read'}
    $available=[long]0
    if($Offset -le $Stream.Length) {
        $available=[Math]::Min([long]$Count, ($Stream.Length - $Offset))
    }
    $bytes=New-Object 'byte[]' ([int]$available)
    if($available -eq 0){return ,$bytes}
    [void]$Stream.Seek($Offset,[IO.SeekOrigin]::Begin)
    $pos=0
    while($pos -lt $bytes.Length) {
        $n=$Stream.Read($bytes,$pos,$bytes.Length-$pos)
        if($n -le 0){break}
        $pos+=$n
    }
    if($pos -eq $bytes.Length){return ,$bytes}
    $short=New-Object 'byte[]' $pos
    if($pos -gt 0){[Array]::Copy($bytes,0,$short,0,$pos)}
    return ,$short
}

function Get-ChappyFatDirectoryConsistency {
    <#
    .SYNOPSIS
    Independently probes a small bounded FAT32 8.3 directory window and compares
    candidate cluster chains in both FAT copies; no names or data are exported.
    .DESCRIPTION
    Caller-provided geometry, directory location, and entry candidates remain
    unverified. A compatible chain does not prove any file contents are correct.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [Parameter(Mandatory=$true)][long]$DirectoryOffsetBytes,
        [Parameter(Mandatory=$true)][long]$Fat1OffsetBytes,
        [Parameter(Mandatory=$true)][long]$Fat2OffsetBytes,
        [Parameter(Mandatory=$true)][long]$FatLengthBytes,
        [Parameter(Mandatory=$true)][long]$MaxDataCluster,
        [int]$DirectorySlots=8,
        [int]$BytesPerCluster=4096,
        [int]$MaxStepsPerTrace=16,
        [int]$MaxReadBytes=2048
    )
    if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite) {
        throw 'Read-only seekable stream required'
    }
    if($DirectorySlots -lt 1 -or $DirectorySlots -gt 16 -or
        $BytesPerCluster -lt 512 -or $BytesPerCluster -gt 32768 -or
        ($BytesPerCluster%512) -ne 0 -or
        ($BytesPerCluster -band ($BytesPerCluster-1)) -ne 0 -or
        $MaxStepsPerTrace -lt 1 -or $MaxStepsPerTrace -gt 32 -or
        $MaxReadBytes -lt 40 -or $MaxReadBytes -gt 4096) {
        throw 'Window, cluster-size or read budget exceeds caps'
    }
    if($DirectoryOffsetBytes -lt 0 -or $Fat1OffsetBytes -lt 0 -or
        $Fat2OffsetBytes -lt 0 -or
        ($DirectoryOffsetBytes % 32) -ne 0 -or
        ($Fat1OffsetBytes % 4) -ne 0 -or ($Fat2OffsetBytes % 4) -ne 0 -or
        $FatLengthBytes -lt 12 -or ($FatLengthBytes % 4) -ne 0 -or
        $MaxDataCluster -lt 2 -or $MaxDataCluster -gt 268435439 -or
        ($MaxDataCluster+1) -gt [long]($FatLengthBytes/4)) {
        throw 'Invalid caller supplied directory/FAT geometry'
    }
    $dirLength=[long]$DirectorySlots*32
    if($DirectoryOffsetBytes -gt ([long]::MaxValue-$dirLength) -or
        $Fat1OffsetBytes -gt ([long]::MaxValue-$FatLengthBytes) -or
        $Fat2OffsetBytes -gt ([long]::MaxValue-$FatLengthBytes)) {
        throw 'Declared offset arithmetic overflow'
    }
    $dirEnd=$DirectoryOffsetBytes+$dirLength
    $end1=$Fat1OffsetBytes+$FatLengthBytes
    $end2=$Fat2OffsetBytes+$FatLengthBytes
    if(($Fat1OffsetBytes -lt $end2 -and $Fat2OffsetBytes -lt $end1) -or
        ($DirectoryOffsetBytes -lt $end1 -and $Fat1OffsetBytes -lt $dirEnd) -or
        ($DirectoryOffsetBytes -lt $end2 -and $Fat2OffsetBytes -lt $dirEnd)) {
        throw 'Caller supplied FAT/directory regions overlap'
    }

    $records=New-Object System.Collections.ArrayList
    $skipped=0;$dirBytes=0;$slotCount=0;$endMarker=$false
    $truncated=$false;$budgetHit=$false
    for($slot=0;$slot -lt $DirectorySlots;$slot++) {
        if(($dirBytes+32) -gt $MaxReadBytes){$budgetHit=$true;break}
        $raw=Read-DConsistencyBytes $Stream ($DirectoryOffsetBytes+[long]$slot*32) 32
        $dirBytes+=$raw.Length
        if($raw.Length -lt 32){$truncated=$true;break}
        $slotCount++
        if($raw[0] -eq 0){$endMarker=$true;break}
        $attr=[int]$raw[11]
        if($raw[0] -eq 0xE5 -or $raw[0] -eq 0x2E -or
            ($attr -band 0x0F) -eq 0x0F -or ($attr -band 0x08) -ne 0 -or
            ($attr -band 0xC0) -ne 0) {
            $skipped++;continue
        }
        $start=([long][BitConverter]::ToUInt16($raw,20)*65536)+
            [long][BitConverter]::ToUInt16($raw,26)
        $fileSize=[long][BitConverter]::ToUInt32($raw,28)
        $isDirectory=(($attr -band 0x10) -ne 0)
        [void]$records.Add([pscustomobject]@{
            slotIndex=$slot
            isDirectory=$isDirectory
            startCluster=$start
            declaredSizeBytes=$fileSize
            # For files only, size may be zero. For directories, size is not a
            # reliable capacity metric; never infer byte coverage from it.
            requiredFileClusters=$(if($isDirectory){$null}else{
                [long][Math]::Ceiling([double]$fileSize/$BytesPerCluster)})
        })
    }

    # Reserve a fixed per-copy quota from the bytes not spent scanning directory
    # slots. No copy can consume the other's read budget.
    $remaining=[int]($MaxReadBytes-$dirBytes)
    $quotaEntries=[int][Math]::Floor($remaining/8.0)
    $offsets=@([long]$Fat1OffsetBytes,[long]$Fat2OffsetBytes)
    $results=New-Object System.Collections.ArrayList
    $mirrorSummaries=New-Object System.Collections.ArrayList
    $readBytes=[long]$dirBytes
    $incomplete=($truncated -or $budgetHit)
    $conflicts=0;$compatible=0;$unknown=0
    for($fat=0;$fat -lt 2;$fat++) {
        $checked=0;$conflictCount=0;$compatibleCount=0;$unknownCount=0
        foreach($record in $records) {
            $status='unknown';$reason='candidate.unproven';$steps=0
            $start=[long]$record.startCluster
            if($record.isDirectory -and $start -eq 0) {
                $status='conflict';$reason='directory.zero_cluster'
            }elseif(-not $record.isDirectory -and $record.declaredSizeBytes -gt 0 -and $start -eq 0) {
                $status='conflict';$reason='file.nonempty_zero_cluster'
            }elseif(-not $record.isDirectory -and $record.declaredSizeBytes -eq 0 -and $start -eq 0) {
                $status='compatible';$reason='file.empty_zero_cluster'
            }elseif($start -lt 2 -or $start -gt $MaxDataCluster) {
                $status='conflict';$reason='entry.cluster_out_of_range'
            }else {
                $current=$start
                $seen=New-Object 'System.Collections.Generic.HashSet[long]'
                while($true) {
                    if($steps -ge $MaxStepsPerTrace){
                        $status='unknown';$reason='budget.chain_steps';break
                    }
                    if($checked -ge $quotaEntries){
                        $status='unknown';$reason='budget.fat_copy_quota';break
                    }
                    if(-not $seen.Add($current)){
                        $status='conflict';$reason='fat.chain_cycle';break
                    }
                    $at=$offsets[$fat]+$current*4
                    if($at -gt $Stream.Length -or ($Stream.Length-$at) -lt 4) {
                        $status='unknown';$reason='io.fat_entry_truncated';break
                    }
                    $entry=Read-DConsistencyBytes $Stream $at 4
                    $readBytes+=$entry.Length
                    if($entry.Length -lt 4){
                        $status='unknown';$reason='io.short_fat_read';break
                    }
                    $checked++;$steps++
                    $next=[long]([BitConverter]::ToUInt32($entry,0) -band 0x0FFFFFFF)
                    if($next -ge 268435448) {
                        if(-not $record.isDirectory -and
                            $steps -lt $record.requiredFileClusters) {
                            $status='conflict';$reason='file.chain_shorter_than_size'
                        }else{
                            $status='compatible';$reason='fat.chain_eoc_compatible'
                        }
                        break
                    }
                    if($next -eq 0) {
                        $status='conflict';$reason='fat.chain_free_link';break
                    }
                    if($next -eq 1 -or ($next -ge 268435440 -and $next -le 268435446)){
                        $status='conflict';$reason='fat.chain_reserved_link';break
                    }
                    if($next -eq 268435447){
                        $status='conflict';$reason='fat.chain_bad_marker';break
                    }
                    if($next -lt 2 -or $next -gt $MaxDataCluster){
                        $status='conflict';$reason='fat.chain_out_of_range';break
                    }
                    if($seen.Contains($next)){
                        $status='conflict';$reason='fat.chain_cycle';break
                    }
                    $current=$next
                }
            }
            switch($status) {
                'conflict' {$conflicts++;$conflictCount++}
                'compatible' {$compatible++;$compatibleCount++}
                default {$unknown++;$unknownCount++;$incomplete=$true}
            }
            [void]$results.Add([pscustomobject]@{
                fatIndex=$fat
                slotIndex=$record.slotIndex
                isDirectory=$record.isDirectory
                startCluster=$start
                declaredSizeBytes=$record.declaredSizeBytes
                requiredFileClusters=$record.requiredFileClusters
                observedChainEntries=$steps
                consistency=$status
                evidence=$reason
                scanIncomplete=$($status -eq 'unknown')
                confidence=$(if($status -eq 'unknown'){'unknown'}else{'partial'})
            })
        }
        [void]$mirrorSummaries.Add([pscustomobject]@{
            fatIndex=$fat
            fatEntriesRead=$checked
            readBytes=$($checked*4)
            conflicts=$conflictCount
            compatibleObservations=$compatibleCount
            unresolved=$unknownCount
        })
    }
    $warnings=New-Object System.Collections.ArrayList
    [void]$warnings.Add('geometry.caller_supplied_unverified')
    [void]$warnings.Add('directory.slot_candidates_not_authenticated')
    [void]$warnings.Add('coverage.directory_window_only')
    [void]$warnings.Add('fat.mirror_agreement_not_integrity_proof')
    [void]$warnings.Add('file.compatibility_not_content_validation')
    if($incomplete){[void]$warnings.Add('coverage.incomplete')}
    if($truncated){[void]$warnings.Add('io.directory_truncated')}
    if($budgetHit){[void]$warnings.Add('budget.directory_read_limit')}
    return [pscustomobject]@{
        schemaVersion='1'
        team='D'
        mode='read_only_directory_fat_consistency'
        status=$(if($incomplete){'partial'}else{'ok'})
        scanIncomplete=$incomplete
        writePermitted=$false
        geometryProvenance='caller_supplied_unverified'
        items=@($results.ToArray())
        copies=@($mirrorSummaries.ToArray())
        warnings=@($warnings.ToArray())
        errors=@()
        metrics=[pscustomobject]@{
            bytesRead=$readBytes
            directoryBytesRead=$dirBytes
            fatBytesRead=$($readBytes-$dirBytes)
            slotsExamined=$slotCount
            candidateRecords=$records.Count
            skippedEntries=$skipped
            directoryEndMarkerObserved=$endMarker
            requestedSlots=$DirectorySlots
            maxReadBytes=$MaxReadBytes
            maxStepsPerTrace=$MaxStepsPerTrace
            perFatEntryQuota=$quotaEntries
            observations=$results.Count
            conflicts=$conflicts
            compatibleObservations=$compatible
            unresolved=$unknown
        }
    }
}
Export-ModuleMember -Function Get-ChappyFatDirectoryConsistency
