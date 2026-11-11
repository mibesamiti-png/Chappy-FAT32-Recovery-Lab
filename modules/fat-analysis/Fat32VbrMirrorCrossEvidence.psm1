#Requires -Version 5.1
# Team D R6-P1: bounded, read-only cross-evidence for two unverified VBR geometries.
# Synthetic-only. No paths, device access, writes, extraction, repair or winner selection.
Set-StrictMode -Version 2.0

function Read-D6Entry {
    param([IO.Stream]$Stream,[long]$Offset,[ref]$TotalBytes,[int]$Budget)
    if($Offset -lt 0){throw 'Negative FAT entry offset'}
    if(([long]$TotalBytes.Value+4) -gt $Budget){return $null}
    if($Offset -gt $Stream.Length){return ,([byte[]]@())}
    $available=[int][Math]::Min(4,($Stream.Length-$Offset))
    $bytes=New-Object 'byte[]' $available
    if($available -eq 0){return ,$bytes}
    [void]$Stream.Seek($Offset,[IO.SeekOrigin]::Begin)
    $read=0
    while($read -lt $available){
        $n=$Stream.Read($bytes,$read,($available-$read))
        if($n -le 0){break}
        $read+=$n
    }
    $TotalBytes.Value=[long]$TotalBytes.Value+$read
    if($read -eq $available){return ,$bytes}
    $short=New-Object 'byte[]' $read
    if($read -gt 0){[Array]::Copy($bytes,0,$short,0,$read)}
    return ,$short
}

function Get-D6RootEvidence {
    param([System.Collections.Generic.Dictionary[long,long]]$Values,
        [long]$Root,[long]$MaxDataCluster,[int]$MaxSteps)
    $seen=New-Object 'System.Collections.Generic.HashSet[long]'
    $cur=$Root
    for($step=0;$step -lt $MaxSteps;$step++){
        if(-not $seen.Add($cur)){return 'cycle_observed'}
        if(-not $Values.ContainsKey($cur)){return 'chain_outside_sample'}
        $value=[long]$Values[$cur]
        if($value -ge 268435448){return 'eoc_observed'}
        if($value -eq 0){return 'free_link_observed'}
        if($value -eq 1 -or ($value -ge 268435440 -and $value -le 268435446)){
            return 'reserved_link_observed'
        }
        if($value -eq 268435447){return 'bad_link_observed'}
        if($value -lt 2 -or $value -gt ($MaxDataCluster+1)){
            return 'out_of_range_link_observed'
        }
        $cur=$value
    }
    return 'chain_outside_sample'
}

function Get-ChappyFatVbrMirrorCrossEvidence {
    <#
    .SYNOPSIS
    Compare tiny FAT1/FAT2 samples under both unverified VBR candidates.
    .DESCRIPTION
    Accepts exactly the primary and backup candidate records returned by R5.
    Does not import R5, authenticate their geometry or choose any valid copy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [Parameter(Mandatory=$true)][object[]]$Candidates,
        [ValidateRange(2,8)][int]$RootWindowEntries=4,
        [ValidateRange(16,256)][int]$MaxReadBytes=128,
        [ValidateRange(4,40)][int]$MaxEntries=32
    )
    if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite){
        throw 'Readable seekable strictly non-writable stream required'
    }
    if($Candidates.Count -ne 2 -or $null -eq $Candidates[0] -or $null -eq $Candidates[1]){
        throw 'Exactly two primary/backup candidate summaries required'
    }
    # Fixed fair quotas across the four (candidate, FAT copy) streams.
    # Quotas are never transferred, and each candidate has exactly two windows.
    $quota=[int][Math]::Min([Math]::Floor($MaxReadBytes/16.0),
                            [Math]::Floor($MaxEntries/4.0))
    $used=[long]0
    $totalEntries=0
    $reports=New-Object System.Collections.ArrayList
    $incomplete=$false
    $totalAnomalies=0
    $geometryDifferences=New-Object System.Collections.ArrayList
    $firstGeometry=$null
    $secondGeometry=$null
    for($c=0;$c -lt 2;$c++){
        $role=$(if($c -eq 0){'primary'}else{'backup'})
        $codes=New-Object System.Collections.ArrayList
        $copies=New-Object System.Collections.ArrayList
        $maps=@()
        $valid=$true
        $fat1=0L;$fat2=0L;$fatSize=0L;$root=0L;$clusterCount=0L;$end=0L
        $summary=$Candidates[$c]
        try {
            if($summary.plausibility -ne 'plausible_unverified'){
                [void]$codes.Add('candidate.upstream_not_plausible')
                $valid=$false
            }
            if($null -eq $summary.geometry){throw 'missing'}
            $g=$summary.geometry
            foreach($k in @('fat1OffsetBytes','fat2OffsetBytes','fatLengthBytes',
                'rootCluster','dataClusterCount','volumeEndExclusiveBytes')){
                if($null -eq $g.$k){throw 'missing'}
            }
            $fat1=[long]$g.fat1OffsetBytes
            $fat2=[long]$g.fat2OffsetBytes
            $fatSize=[long]$g.fatLengthBytes
            $root=[long]$g.rootCluster
            $clusterCount=[long]$g.dataClusterCount
            $end=[long]$g.volumeEndExclusiveBytes
            if($fat1 -lt 0 -or $fat2 -lt 0 -or $fatSize -lt 12 -or
                ($fat1%4) -ne 0 -or ($fat2%4) -ne 0 -or ($fatSize%4) -ne 0 -or
                $fat1 -gt ([long]::MaxValue-$fatSize) -or
                $fat2 -gt ([long]::MaxValue-$fatSize)){
                [void]$codes.Add('geometry.invalid_or_overflow')
                $valid=$false
            }else{
                $fatEnd=$fat2+$fatSize
                if($fat1+$fatSize -ne $fat2 -or $end -le $fatEnd -or
                    $end -gt $Stream.Length -or $fatEnd -gt $Stream.Length){
                    [void]$codes.Add('geometry.fat_regions_outside_volume')
                    $valid=$false
                }
            }
            if($clusterCount -lt 1 -or $clusterCount -gt 268435438 -or
                $root -lt 2 -or $root -gt ($clusterCount+1) -or
                [Math]::Floor($fatSize/4.0) -lt ($clusterCount+2) -or
                $root -gt ([Math]::Floor($fatSize/4.0)-1)){
                [void]$codes.Add('geometry.cluster_capacity_invalid')
                $valid=$false
            }
        }catch{
            [void]$codes.Add('geometry.missing_or_non_numeric')
            $valid=$false
        }
        $candidateGeometry=[pscustomobject]@{
            fat1OffsetBytes=$(if($valid){$fat1}else{$null})
            fat2OffsetBytes=$(if($valid){$fat2}else{$null})
            fatLengthBytes=$(if($valid){$fatSize}else{$null})
            rootCluster=$(if($valid){$root}else{$null})
            dataClusterCount=$(if($valid){$clusterCount}else{$null})
        }
        if($c -eq 0){$firstGeometry=$candidateGeometry}else{$secondGeometry=$candidateGeometry}
        if($valid){
            for($mirror=0;$mirror -lt 2;$mirror++){
                $offset=$(if($mirror -eq 0){$fat1}else{$fat2})
                $values=New-Object 'System.Collections.Generic.Dictionary[long,long]'
                $entryReads=0;$readBytes=0;$partial=$false;$prefixBad=0
                $reason=New-Object System.Collections.ArrayList
                foreach($window in @(0,1)){
                    $begin=$(if($window -eq 0){0L}else{$root})
                    $wanted=$(if($window -eq 0){2}else{$RootWindowEntries})
                    for($i=0;$i -lt $wanted;$i++){
                        $idx=[long]($begin+$i)
                        if($entryReads -ge $quota){
                            $partial=$true
                            if($reason -notcontains 'budget.copy_quota_exhausted'){
                                [void]$reason.Add('budget.copy_quota_exhausted')
                            }
                            break
                        }
                        if($idx -ge [Math]::Floor($fatSize/4.0) -or
                           $idx -gt ($clusterCount+1) -and $window -eq 1){
                            $partial=$true
                            [void]$reason.Add('coverage.window_exceeds_declared_fat')
                            break
                        }
                        if($values.ContainsKey($idx)){continue}
                        $entryOffset=[long]($offset+$idx*4)
                        $b=Read-D6Entry $Stream $entryOffset ([ref]$used) $MaxReadBytes
                        if($null -eq $b){
                            $partial=$true;[void]$reason.Add('budget.global_bytes_exhausted')
                            break
                        }
                        $readBytes+=$b.Length
                        if($b.Length -ne 4){
                            $partial=$true;[void]$reason.Add('io.fat_entry_truncated')
                            break
                        }
                        $value=[long]([BitConverter]::ToUInt32($b,0) -band 0x0FFFFFFF)
                        $values.Add($idx,$value)
                        $entryReads++;$totalEntries++
                        if($window -eq 0){
                            if($idx -eq 0 -and ($value -band 0x0FFFFF00) -ne 0x0FFFFF00){
                                $prefixBad++
                            }
                            if($idx -eq 1 -and $value -lt 268435448){
                                $prefixBad++
                            }
                        }
                    }
                }
                $rootEvidence=Get-D6RootEvidence $values $root $clusterCount ($RootWindowEntries+1)
                if($rootEvidence -ne 'eoc_observed'){
                    if($rootEvidence -eq 'chain_outside_sample'){
                        $partial=$true
                        [void]$reason.Add('coverage.root_chain_unresolved')
                    }else{[void]$reason.Add(('fat.'+$rootEvidence))}
                }
                if($prefixBad -gt 0){[void]$reason.Add('fat.reserved_prefix_suspicious')}
                $anomalies=$prefixBad
                if(@('free_link_observed','reserved_link_observed','bad_link_observed',
                    'out_of_range_link_observed','cycle_observed') -contains $rootEvidence){
                    $anomalies++
                }
                $totalAnomalies+=$anomalies
                if($partial){$incomplete=$true}
                [void]$copies.Add([pscustomobject]@{
                    fatIndex=$mirror
                    entriesRead=$entryReads
                    bytesRead=$readBytes
                    requestedEntries=(2+$RootWindowEntries)
                    rootChainEvidence=$rootEvidence
                    prefixAnomalies=$prefixBad
                    anomalyCount=$anomalies
                    scanIncomplete=$partial
                    reasonCodes=@($reason.ToArray())
                })
                $maps+=,$values
            }
        }else{$incomplete=$true}
        $common=0;$same=0;$different=0
        if($valid){
            foreach($key in $maps[0].Keys){
                if($maps[1].ContainsKey($key)){
                    $common++
                    if($maps[0][$key] -eq $maps[1][$key]){$same++}else{$different++}
                }
            }
        }
        $comparisonStatus=$(if(-not $valid){'insufficient_evidence'}
          elseif($common -eq 0){'insufficient_evidence'}
          elseif($copies[0].scanIncomplete -or $copies[1].scanIncomplete){'partial'}
          else{'observed'})
        [void]$reports.Add([pscustomobject]@{
            sourceRole=$role
            inputProvenance='unverified_r5_candidate'
            status=$comparisonStatus
            geometry=$candidateGeometry
            fatCopies=@($copies.ToArray())
            mirrors=[pscustomobject]@{
                commonEntries=$common
                matchingEntries=$same
                differentEntries=$different
                bothCopiesAgree=($common -gt 0 -and $different -eq 0)
                comparisonDoesNotProveHealth=$true
            }
            reasonCodes=@($codes.ToArray())
        })
    }
    if($null -ne $firstGeometry.fat1OffsetBytes -and
       $null -ne $secondGeometry.fat1OffsetBytes){
        foreach($key in @('fat1OffsetBytes','fat2OffsetBytes','fatLengthBytes',
            'rootCluster','dataClusterCount')){
            if($firstGeometry.$key -ne $secondGeometry.$key){
                [void]$geometryDifferences.Add(('geometry.'+$key))
            }
        }
    }
    $crossStatus='insufficient_evidence'
    if(-not $incomplete -and $reports[0].status -eq 'observed' -and
        $reports[1].status -eq 'observed'){
        $crossStatus=$(if($totalAnomalies -gt 0 -or
            $reports[0].mirrors.differentEntries -gt 0 -or
            $reports[1].mirrors.differentEntries -gt 0){
            'observed_conflicts_no_selection'
        }else{'ambiguous_equal_plausibility'})
    }
    $warnings=@('candidate.geometry_unverified','fat.mirror_agreement_not_integrity',
        'evidence.tiny_windows_not_full_fat','source.no_winner_or_repair',
        'real_master_img_trial_not_authorized')
    if($incomplete){$warnings+=,'coverage.incomplete'}
    return [pscustomobject]@{
        schemaVersion='1'
        team='D'
        mode='read_only_vbr_fat_mirror_cross_evidence'
        status=$(if($incomplete){'partial'}else{'ok'})
        scanIncomplete=$incomplete
        writePermitted=$false
        sourceDecision='not_selected'
        selectedCandidate=$null
        crossEvidence=$crossStatus
        differingCandidateGeometry=@($geometryDifferences.ToArray())
        items=@($reports.ToArray())
        warnings=@($warnings)
        errors=@()
        metrics=[pscustomobject]@{
            bytesRead=$used
            entriesRead=$totalEntries
            maxReadBytes=$MaxReadBytes
            maxEntries=$MaxEntries
            perCopyEntryQuota=$quota
            maxWindowsPerCopy=2
            requestedRootWindowEntries=$RootWindowEntries
            totalAnomalyObservations=$totalAnomalies
        }
    }
}
Export-ModuleMember -Function Get-ChappyFatVbrMirrorCrossEvidence
