#Requires -Version 5.1
# Team D R3-P2: read-only, bounded EB-58 range observations; NO repair or file writes.
Set-StrictMode -Version 2.0

function Read-D58Bytes {
    param([System.IO.Stream]$Stream,[long]$Offset,[int]$Length)
    if ($Offset -lt 0 -or $Length -lt 0 -or $Length -gt 65536) { throw 'Invalid read range' }
    if ($Offset -gt $Stream.Length) { return ,([byte[]]@()) }
    $count=[int][Math]::Min([long]$Length,($Stream.Length-$Offset))
    $b=New-Object 'byte[]' $count
    [void]$Stream.Seek($Offset,[System.IO.SeekOrigin]::Begin)
    $at=0
    while ($at -lt $count) {
        $chunk=[int][Math]::Min(4096,($count-$at))
        $n=$Stream.Read($b,$at,$chunk)
        if ($n -le 0) { break }
        $at+=$n
    }
    if ($at -eq $count) { return ,$b }
    $short=New-Object 'byte[]' $at
    if($at -gt 0){[Array]::Copy($b,0,$short,0,$at)}
    return ,$short
}

function Get-D58BootObservation {
    param([byte[]]$Bytes,[long]$VolumeOffsetBytes)
    $valid=$false
    $fat1=$null;$fat2=$null;$fatSize=$null
    $hasJump=($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEB -and $Bytes[1] -eq 0x58 -and $Bytes[2] -eq 0x90)
    $hasSig=($Bytes.Length -ge 512 -and $Bytes[510] -eq 0x55 -and $Bytes[511] -eq 0xAA)
    if ($Bytes.Length -ge 512 -and $hasSig) {
        $bps=[BitConverter]::ToUInt16($Bytes,11)
        $spc=[int]$Bytes[13]
        $reserved=[BitConverter]::ToUInt16($Bytes,14)
        $copies=[int]$Bytes[16]
        $fatSectors=[BitConverter]::ToUInt32($Bytes,36)
        $root=[BitConverter]::ToUInt32($Bytes,44)
        if (($bps -eq 512 -or $bps -eq 1024 -or $bps -eq 2048 -or $bps -eq 4096) -and
            $spc -gt 0 -and $spc -le 128 -and ($spc -band ($spc-1)) -eq 0 -and
            $reserved -ge 1 -and $copies -ge 2 -and $copies -le 4 -and
            $fatSectors -gt 0 -and $root -ge 2 -and $root -le 268435446) {
            $reservedBytes=[long]$reserved*[long]$bps
            $fatSize=[long]$fatSectors*[long]$bps
            if ($VolumeOffsetBytes -le ([long]::MaxValue-$reservedBytes-$fatSize)) {
                $fat1=$VolumeOffsetBytes+$reservedBytes
                $fat2=$fat1+$fatSize
                $valid=$true
            }
        }
    }
    return [pscustomobject]@{
        bootBytesObserved=$Bytes.Length
        eb5890JumpObserved=$hasJump
        bootSignatureObserved=$hasSig
        plausibleFat32Bpb=$valid
        bpbDerivedFat1OffsetBytes=$fat1
        bpbDerivedFat2OffsetBytes=$fat2
        bpbDerivedFatLengthBytes=$fatSize
        geometryConfidence='partial'
    }
}

function Get-D58Ranges {
    param([byte[]]$Bytes,[long]$FatOffset,[int]$MinRunPairs,[int]$MaxReportedRuns)
    $runs=New-Object System.Collections.ArrayList
    $i=0;$count=0;$pairs=0;$longest=0;$omitted=0;$atStart=$false
    while($i -lt ($Bytes.Length-1)) {
        if($Bytes[$i] -eq 0xEB -and $Bytes[$i+1] -eq 0x58) {
            $begin=$i
            do {$i+=2} while($i -lt ($Bytes.Length-1) -and $Bytes[$i] -eq 0xEB -and $Bytes[$i+1] -eq 0x58)
            $length=[int](($i-$begin)/2)
            if($length -ge $MinRunPairs) {
                $count++;$pairs+=$length
                if($length -gt $longest){$longest=$length}
                if($begin -eq 0){$atStart=$true}
                if($runs.Count -lt $MaxReportedRuns) {
                    $absolute=$FatOffset+[long]$begin
                    [void]$runs.Add([pscustomobject]@{
                        startOffsetBytes=$absolute
                        endOffsetExclusive=$FatOffset+[long]$i
                        observedPairs=$length
                        alignmentModulo4=[int]($absolute%4)
                        alignmentModulo512=[int]($absolute%512)
                        startsAtFatProbe=$($begin -eq 0)
                        reachesObservedEnd=$($i -ge $Bytes.Length-1)
                        confidence='verified'
                        evidence=@('eb58.contiguous_pairs_observed')
                    })
                }else{$omitted++}
            }
        }else{$i++}
    }
    $vbrPrefix=($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEB -and $Bytes[1] -eq 0x58 -and $Bytes[2] -eq 0x90)
    $vbrSig=($Bytes.Length -ge 512 -and $Bytes[510] -eq 0x55 -and $Bytes[511] -eq 0xAA)
    return [pscustomobject]@{
        runs=@($runs.ToArray())
        totalRuns=$count
        omittedRuns=$omitted
        observedPatternPairs=$pairs
        longestObservedRunPairs=$longest
        runsAtProbeStart=$atStart
        bootLikePrefixObserved=$vbrPrefix
        bootSignatureAt510Observed=$vbrSig
        bootLikeSignatureCombination=$($vbrPrefix -and $vbrSig)
    }
}

function Get-ChappyFatEb58Map {
    <#
    .SYNOPSIS
    Reports observed EB-58 pair runs near supplied FAT boundaries, without asserting the cause.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.IO.Stream]$Stream,
        [Parameter(Mandatory=$true)][long]$Fat1OffsetBytes,
        [Parameter(Mandatory=$true)][long]$Fat2OffsetBytes,
        [Parameter(Mandatory=$true)][long]$FatLengthBytes,
        [long]$VolumeOffsetBytes=0,
        [ValidateRange(32,65536)][int]$ProbeBytesPerFat=4096,
        [ValidateRange(512,131584)][int]$MaxReadBytes=8704,
        [ValidateRange(2,128)][int]$MinRunPairs=4,
        [ValidateRange(1,64)][int]$MaxReportedRunsPerFat=32
    )
    if (-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite) {
        throw 'Require readable, seekable, nonwritable stream; writes are forbidden'
    }
    if($VolumeOffsetBytes -lt 0 -or $Fat1OffsetBytes -lt 0 -or $Fat2OffsetBytes -lt 0 -or
        ($VolumeOffsetBytes%512) -ne 0 -or ($Fat1OffsetBytes%4) -ne 0 -or
        ($Fat2OffsetBytes%4) -ne 0 -or $FatLengthBytes -lt 32 -or
        ($FatLengthBytes%4) -ne 0) {throw 'Invalid caller-supplied aligned offsets/length'}
    if($Fat1OffsetBytes -gt ([long]::MaxValue-$FatLengthBytes) -or
        $Fat2OffsetBytes -gt ([long]::MaxValue-$FatLengthBytes)) {throw 'FAT range overflows Int64'}
    $end1=$Fat1OffsetBytes+$FatLengthBytes
    $end2=$Fat2OffsetBytes+$FatLengthBytes
    if($Fat1OffsetBytes -lt $end2 -and $Fat2OffsetBytes -lt $end1) {
        throw 'Caller FAT regions overlap'
    }
    $boot=Read-D58Bytes $Stream $VolumeOffsetBytes 512
    $parsed=Get-D58BootObservation $boot $VolumeOffsetBytes
    $observedRead=[long]$boot.Length
    $quota=[int][Math]::Min([long]$ProbeBytesPerFat, [Math]::Min(
        $FatLengthBytes, [long][Math]::Floor(($MaxReadBytes-$observedRead)/2.0)))
    if($quota -lt 0){$quota=0}
    $positions=@([long]$Fat1OffsetBytes,[long]$Fat2OffsetBytes)
    $ranges=New-Object System.Collections.ArrayList
    $totalPairs=0;$totalRuns=0;$reported=0;$incomplete=$false
    for($f=0;$f -lt 2;$f++){
        $position=$positions[$f]
        $bytes=Read-D58Bytes $Stream $position $quota
        $observedRead += [long]$bytes.Length
        $runs=Get-D58Ranges $bytes $position $MinRunPairs $MaxReportedRunsPerFat
        $totalPairs += $runs.observedPatternPairs;$totalRuns += $runs.totalRuns
        $reported += $runs.runs.Count
        $partial=($bytes.Length -lt $FatLengthBytes -or $runs.omittedRuns -gt 0)
        if($partial){$incomplete=$true}
        $reasons=New-Object System.Collections.ArrayList
        if($runs.totalRuns -gt 0){[void]$reasons.Add('fat.eb58_repeated_region_observed')}
        if($runs.runsAtProbeStart){[void]$reasons.Add('fat.eb58_at_supplied_start')}
        if($runs.bootLikePrefixObserved){[void]$reasons.Add('fat.boot_jump_like_prefix_observed')}
        if($runs.bootLikeSignatureCombination){[void]$reasons.Add('fat.vbr_like_combination_observed')}
        if($bytes.Length -lt $quota){[void]$reasons.Add('io.truncated')}
        if($bytes.Length -lt $FatLengthBytes){[void]$reasons.Add('coverage.partial')}
        if($runs.omittedRuns -gt 0){[void]$reasons.Add('report.run_list_capped')}
        [void]$ranges.Add([pscustomobject]@{
            fatIndex=$f
            suppliedStartOffsetBytes=$position
            declaredFatLengthBytes=$FatLengthBytes
            requestedProbeBytes=$quota
            observedBytes=$bytes.Length
            totalRuns=$runs.totalRuns
            omittedRuns=$runs.omittedRuns
            observedPairs=$runs.observedPatternPairs
            longestObservedRunPairs=$runs.longestObservedRunPairs
            runsAtProbeStart=$runs.runsAtProbeStart
            bootLikePrefixObserved=$runs.bootLikePrefixObserved
            bootSignatureAt510Observed=$runs.bootSignatureAt510Observed
            bootLikeSignatureCombination=$runs.bootLikeSignatureCombination
            runs=@($runs.runs)
            scanIncomplete=$partial
            confidence=$(if($partial){'partial'}else{'verified'})
            evidence=@($reasons.ToArray())
        })
    }
    $geometryMismatch=$false
    $geometryCompared=$parsed.plausibleFat32Bpb
    if($geometryCompared){
        $geometryMismatch=($Fat1OffsetBytes -ne $parsed.bpbDerivedFat1OffsetBytes -or
            $Fat2OffsetBytes -ne $parsed.bpbDerivedFat2OffsetBytes -or
            $FatLengthBytes -ne $parsed.bpbDerivedFatLengthBytes)
    }
    $warnings=New-Object System.Collections.ArrayList
    [void]$warnings.Add('geometry.caller_supplied_unverified')
    [void]$warnings.Add('pattern.observation_not_causation')
    [void]$warnings.Add('fat.mirror_agreement_not_proof_of_health')
    if(-not $parsed.plausibleFat32Bpb){[void]$warnings.Add('boot.bpb_not_independently_validated')}
    if($geometryMismatch){[void]$warnings.Add('geometry.supplied_offsets_disagree_with_bpb')}
    if($incomplete){[void]$warnings.Add('coverage.partial')}
    if($observedRead -ge $MaxReadBytes){[void]$warnings.Add('budget.max_read_bytes_reached')}
    $sharedAtStart=($ranges[0].runsAtProbeStart -and $ranges[1].runsAtProbeStart)
    if($sharedAtStart){[void]$warnings.Add('pattern.both_mirrors_have_start_pattern')}
    if($ranges[0].bootLikeSignatureCombination -or $ranges[1].bootLikeSignatureCombination){
        [void]$warnings.Add('hypothesis.boot_copy_or_wrong_offset_requires_independent_check')
    }
    $observedFatBytes=[long]$ranges[0].observedBytes+[long]$ranges[1].observedBytes
    return [pscustomobject]@{
        schemaVersion='1'
        team='D'
        status=$(if($incomplete){'partial'}else{'ok'})
        scanIncomplete=$incomplete
        mode='read_only_eb58_mapping'
        writePermitted=$false
        geometryProvenance='caller_supplied_unverified'
        bootObservation=$parsed
        geometryComparison=[pscustomobject]@{
            bpbCompared=$geometryCompared
            suppliedOffsetsDisagreeWithBpb=$geometryMismatch
            inference='offset_consistency_only_not_authenticity'
        }
        items=@($ranges.ToArray())
        warnings=@($warnings.ToArray())
        errors=@()
        metrics=[pscustomobject]@{
            bytesRead=$observedRead
            maxReadBytes=$MaxReadBytes
            fatBytesObserved=$observedFatBytes
            fatBytesDeclaredTotal=[long]($FatLengthBytes*2)
            totalPatternRuns=$totalRuns
            reportedRuns=$reported
            totalObservedPatternPairs=$totalPairs
            probeQuotaPerFatBytes=$quota
            sampledOnly=$($observedFatBytes -lt ([long]$FatLengthBytes*2))
        }
    }
}
Export-ModuleMember -Function Get-ChappyFatEb58Map
