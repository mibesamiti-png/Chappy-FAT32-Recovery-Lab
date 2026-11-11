#Requires -Version 5.1
# Team D R3-P1: read-only, budgeted FAT32 mirror comparison. Never repairs or writes any media.
Set-StrictMode -Version 2.0

function Read-D3Window {
    param(
        [Parameter(Mandatory=$true)][System.IO.Stream]$Stream,
        [Parameter(Mandatory=$true)][long]$Offset,
        [Parameter(Mandatory=$true)][int]$Count
    )
    if ($Count -lt 0 -or $Count -gt 4096 -or $Offset -lt 0) {throw 'Invalid bounded read'}
    if ($Offset -gt $Stream.Length) {return ,([byte[]]@())}
    $allowed=[int][Math]::Min([long]$Count, ($Stream.Length - $Offset))
    if ($allowed -eq 0) {return ,([byte[]]@())}
    $buffer=New-Object 'byte[]' $allowed
    [void]$Stream.Seek($Offset,[System.IO.SeekOrigin]::Begin)
    $read=0
    while($read -lt $allowed) {
        $n=$Stream.Read($buffer,$read,$allowed-$read)
        if ($n -le 0) {break}
        $read += $n
    }
    if ($read -eq $allowed) {return ,$buffer}
    $short=New-Object 'byte[]' $read
    if ($read -gt 0) {[Array]::Copy($buffer,0,$short,0,$read)}
    return ,$short
}

function Get-ChappyFatMirrorWindows {
    <#
    .SYNOPSIS
    Compares two caller-located FAT32 regions using explicit cumulative read and window budgets.
    .DESCRIPTION
    Does not discover or verify partition geometry. Caller-provided offsets remain unverified.
    Accepts ONLY a readable, seekable, non-writable stream. Never emits raw content, hashes or paths.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.IO.Stream]$Stream,
        [Parameter(Mandatory=$true)][long]$Fat1OffsetBytes,
        [Parameter(Mandatory=$true)][long]$Fat2OffsetBytes,
        [Parameter(Mandatory=$true)][long]$FatLengthBytes,
        [long]$StartEntry=0,
        [int]$WindowEntries=128,
        [int]$MaxWindows=8,
        [long]$StrideEntries=0,
        [int]$MaxReadBytes=65536
    )
    if (-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite) {
        throw 'FAT mirror scan requires a seekable, strictly read-only stream'
    }
    if ($WindowEntries -lt 1 -or $WindowEntries -gt 1024 -or $MaxWindows -lt 1 -or
        $MaxWindows -gt 64 -or $MaxReadBytes -lt 8 -or $MaxReadBytes -gt 1048576) {
        throw 'Window/read budget exceeds safety caps'
    }
    if ($StrideEntries -eq 0) {$StrideEntries=[long]$WindowEntries}
    if ($StrideEntries -lt $WindowEntries) {throw 'Overlapping or backwards sample windows are not permitted'}
    if ($Fat1OffsetBytes -lt 0 -or $Fat2OffsetBytes -lt 0 -or
        ($Fat1OffsetBytes % 4) -ne 0 -or ($Fat2OffsetBytes % 4) -ne 0 -or
        $FatLengthBytes -lt 12 -or ($FatLengthBytes % 4) -ne 0 -or
        $StartEntry -lt 0) {throw 'Invalid FAT32-aligned geometry'}
    if ($Fat1OffsetBytes -gt ([long]::MaxValue - $FatLengthBytes) -or
        $Fat2OffsetBytes -gt ([long]::MaxValue - $FatLengthBytes)) {
        throw 'Declared FAT offsets overflow Int64'
    }
    $fat1End=$Fat1OffsetBytes+$FatLengthBytes
    $fat2End=$Fat2OffsetBytes+$FatLengthBytes
    if ($Fat1OffsetBytes -lt $fat2End -and $Fat2OffsetBytes -lt $fat1End) {
        throw 'FAT mirror regions overlap under caller-provided geometry'
    }
    $declaredEntries=[long]($FatLengthBytes -shr 2)
    if ($StartEntry -ge $declaredEntries) {throw 'StartEntry lies beyond declared FAT'}
    $streamLength=$Stream.Length
    if ($streamLength -lt 0) {throw 'Invalid stream length'}

    $windows=New-Object System.Collections.ArrayList
    $warnings=New-Object System.Collections.ArrayList
    [void]$warnings.Add('geometry.caller_supplied_unverified')
    [void]$warnings.Add('mirror_agreement_does_not_establish_health')
    $used=[long]0; $read1=[long]0; $read2=[long]0
    $compared=[long]0; $matches=[long]0; $mismatches=[long]0; $byteDiff=[long]0
    $start=[long]$StartEntry
    $truncated=$false;$budgetReached=$false
    for ($w=0;$w -lt $MaxWindows -and $start -lt $declaredEntries;$w++) {
        $remaining=[long]($declaredEntries-$start)
        $requestedEntries=[int][Math]::Min([long]$WindowEntries,$remaining)
        $remainingBudget=[long]($MaxReadBytes-$used)
        $budgetEntries=[long]($remainingBudget -shr 3)
        if ($budgetEntries -le 0) {$budgetReached=$true;break}
        $scheduledEntries=[int][Math]::Min([long]$requestedEntries,$budgetEntries)
        $wantedBytes=[int]($scheduledEntries*4)
        $firstOffset=[long]($Fat1OffsetBytes+$start*4)
        $secondOffset=[long]($Fat2OffsetBytes+$start*4)
        $first=Read-D3Window -Stream $Stream -Offset $firstOffset -Count $wantedBytes
        $second=Read-D3Window -Stream $Stream -Offset $secondOffset -Count $wantedBytes
        $used += [long]$first.Length+[long]$second.Length
        $read1 += [long]$first.Length
        $read2 += [long]$second.Length
        $entries=[int]([Math]::Min($first.Length,$second.Length) -shr 2)
        $equal=0;$unequal=0;$differentBytes=0
        for($e=0;$e -lt $entries;$e++) {
            $same=$true
            for($j=0;$j -lt 4;$j++) {
                $ix=$e*4+$j
                if($first[$ix] -ne $second[$ix]){$differentBytes++;$same=$false}
            }
            if($same){$equal++} else {$unequal++}
        }
        $compared += $entries;$matches += $equal;$mismatches += $unequal;$byteDiff += $differentBytes
        $partialWindow=($scheduledEntries -ne $requestedEntries -or $entries -ne $requestedEntries)
        $codes=New-Object System.Collections.ArrayList
        if ($unequal -gt 0) {[void]$codes.Add('fat.mirror_mismatch_observed')}
        else {[void]$codes.Add('fat.mirror_equal_in_observed_window')}
        if ($first.Length -lt $wantedBytes -or $second.Length -lt $wantedBytes) {
            [void]$codes.Add('io.range_truncated')
            $truncated=$true
        }
        if ($scheduledEntries -lt $requestedEntries) {
            [void]$codes.Add('budget.byte_limit')
            $budgetReached=$true
        }
        [void]$windows.Add([pscustomobject]@{
            startEntry=[long]$start
            endEntryExclusive=[long]($start+$entries)
            requestedEntries=$requestedEntries
            comparedEntries=$entries
            equalEntries=$equal
            differentEntries=$unequal
            differingBytes=$differentBytes
            fat1BytesRead=$first.Length
            fat2BytesRead=$second.Length
            scanIncomplete=$partialWindow
            confidence=$(if($partialWindow){'partial'}else{'verified'})
            evidence=@($codes.ToArray())
        })
        # Do not silently skip truncated bytes or continue after a partially observed window.
        if ($partialWindow) {break}
        if ($start -gt ($declaredEntries-$StrideEntries)) {break}
        $start += $StrideEntries
    }
    $fullyCompared=($StartEntry -eq 0 -and $StrideEntries -eq $WindowEntries -and
        $compared -eq $declaredEntries -and -not $truncated)
    $incomplete=(-not $fullyCompared)
    if($truncated){[void]$warnings.Add('io.truncated_fat_window')}
    if($budgetReached){[void]$warnings.Add('budget.max_read_bytes_reached')}
    if($incomplete){[void]$warnings.Add('coverage.partial_not_whole_fat')}
    if($mismatches -gt 0){[void]$warnings.Add('fat.mirror_disagreement_no_winner_inferred')}
    $pct=[Math]::Round(([double]$compared/[double]$declaredEntries)*100,6)
    return [pscustomobject]@{
        schemaVersion='1'
        team='D'
        status=$(if($incomplete){'partial'}else{'ok'})
        scanIncomplete=$incomplete
        mode='read_only_mirror_comparison'
        writePermitted=$false
        geometryProvenance='caller_supplied_unverified'
        items=@($windows.ToArray())
        warnings=@($warnings.ToArray())
        errors=@()
        metrics=[pscustomobject]@{
            bytesRead=$used
            fat1BytesRead=$read1
            fat2BytesRead=$read2
            entriesChecked=$compared
            fatEntriesDeclared=$declaredEntries
            equalEntries=$matches
            differentEntries=$mismatches
            differingBytes=$byteDiff
            windowsChecked=$windows.Count
            comparisonCoveragePercent=$pct
            wholeFatCompared=$fullyCompared
            sourceLengthBytes=$streamLength
            readByteBudget=$MaxReadBytes
            windowBudget=$MaxWindows
        }
    }
}
Export-ModuleMember -Function Get-ChappyFatMirrorWindows
