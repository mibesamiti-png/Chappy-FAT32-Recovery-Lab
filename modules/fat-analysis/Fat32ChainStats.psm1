#Requires -Version 5.1
# Team D R3-P3: bounded FAT32 chain observations. No file I/O, repairs, or raw-data output.
Set-StrictMode -Version 2.0

function Get-ChappyFatChainAnomalyStats {
    <#
    .SYNOPSIS
    Bounded, read-only tracing of caller-selected FAT32 cluster chains in two FAT copies.
    .DESCRIPTION
    Requires a seekable non-writable stream. Caller-supplied FAT locations and
    maximum valid data cluster are NOT authenticated BPB geometry. The reported
    ratios describe sampled start chains, not the health of a full FAT.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.IO.Stream]$Stream,
        [Parameter(Mandatory=$true)][long]$Fat1OffsetBytes,
        [Parameter(Mandatory=$true)][long]$Fat2OffsetBytes,
        [Parameter(Mandatory=$true)][long]$FatLengthBytes,
        [Parameter(Mandatory=$true)][long]$MaxDataCluster,
        [long[]]$StartClusters=@(2),
        [int]$MaxStepsPerChain=128,
        [int]$MaxTotalEntries=512,
        [int]$MaxReadBytes=2048
    )
    if (-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite) {
        throw 'Requires readable, seekable, non-writable stream'
    }
    if ($Fat1OffsetBytes -lt 0 -or $Fat2OffsetBytes -lt 0 -or
        ($Fat1OffsetBytes % 4) -ne 0 -or ($Fat2OffsetBytes % 4) -ne 0 -or
        $FatLengthBytes -lt 12 -or ($FatLengthBytes % 4) -ne 0 -or
        $Fat1OffsetBytes -gt ([long]::MaxValue-$FatLengthBytes) -or
        $Fat2OffsetBytes -gt ([long]::MaxValue-$FatLengthBytes)) {
        throw 'Invalid or overflowing FAT geometry'
    }
    if ($MaxDataCluster -lt 2 -or $MaxDataCluster -gt 268435439 -or
        ($MaxDataCluster + 1) -gt [long]($FatLengthBytes/4)) {
        throw 'Maximum data cluster inconsistent with supplied FAT length'
    }
    if ($Fat1OffsetBytes -lt ($Fat2OffsetBytes+$FatLengthBytes) -and
        $Fat2OffsetBytes -lt ($Fat1OffsetBytes+$FatLengthBytes)) {
        throw 'Overlapping FAT locations'
    }
    if ($null -eq $StartClusters -or $StartClusters.Count -lt 1 -or
        $StartClusters.Count -gt 16 -or $MaxStepsPerChain -lt 1 -or
        $MaxStepsPerChain -gt 512 -or $MaxTotalEntries -lt 2 -or
        $MaxTotalEntries -gt 4096 -or $MaxReadBytes -lt 8 -or
        $MaxReadBytes -gt 16384) {
        throw 'Chain count, steps, entry cap, or byte budget outside limits'
    }
    $uniqueStarts=New-Object 'System.Collections.Generic.HashSet[long]'
    foreach($start in $StartClusters) {
        if (-not $uniqueStarts.Add([long]$start)) {throw 'Duplicate start cluster would bias statistics'}
    }
    # Each mirror gets its own fixed quota; FAT1 cannot starve FAT2.
    $perFatEntryQuota=[int][Math]::Floor($MaxTotalEntries/2.0)
    $perFatByteQuota=[int]([Math]::Floor($MaxReadBytes/8.0)*4)
    $fatOffsets=@([long]$Fat1OffsetBytes,[long]$Fat2OffsetBytes)
    $copies=New-Object System.Collections.ArrayList
    $allChains=New-Object System.Collections.ArrayList
    $bytesRead=[long]0;$entriesChecked=[long]0;$allIncomplete=$false
    $resolvedChains=0;$anomalyChains=0

    for($fat=0;$fat -lt 2;$fat++) {
        $copyBytes=0;$copyEntries=0;$copyComplete=0;$copyIncomplete=0
        $counts=@{
            eoc=0;free=0;reserved=0;bad_cluster=0;out_of_range=0
            cycle=0;invalid_start=0;truncated=0;step_limit=0;read_budget=0
        }
        foreach($start in $StartClusters) {
            $current=[long]$start
            $visited=New-Object 'System.Collections.Generic.HashSet[long]'
            $steps=0;$terminal='';$reason='';$lastCluster=$null
            if($current -lt 2 -or $current -gt $MaxDataCluster) {
                $terminal='invalid_start'
                $reason='fat.chain.invalid_start'
            } else {
                while($true) {
                    if($steps -ge $MaxStepsPerChain) {
                        $terminal='step_limit';$reason='budget.chain_steps';break
                    }
                    if($copyEntries -ge $perFatEntryQuota -or
                        ($copyBytes+4) -gt $perFatByteQuota) {
                        $terminal='read_budget';$reason='budget.fat_copy_quota';break
                    }
                    if(-not $visited.Add($current)) {
                        $terminal='cycle';$reason='fat.chain.cycle_observed';break
                    }
                    $offset=[long]($fatOffsets[$fat]+$current*4)
                    if($offset -gt $Stream.Length -or ($Stream.Length-$offset) -lt 4) {
                        $terminal='truncated';$reason='io.fat_entry_truncated';break
                    }
                    [void]$Stream.Seek($offset,[System.IO.SeekOrigin]::Begin)
                    $buffer=New-Object 'byte[]' 4
                    $got=0
                    while($got -lt 4) {
                        $n=$Stream.Read($buffer,$got,(4-$got))
                        if($n -le 0){break}
                        $got+=$n
                    }
                    $copyBytes+=$got;$bytesRead+=$got
                    if($got -lt 4) {
                        $terminal='truncated';$reason='io.short_read';break
                    }
                    $copyEntries++;$entriesChecked++;$steps++
                    $lastCluster=$current
                    # FAT32 high four bits are reserved; only low 28 bits are links.
                    $next=[long]([BitConverter]::ToUInt32($buffer,0) -band 0x0FFFFFFF)
                    if($next -eq 0) {
                        $terminal='free';$reason='fat.chain.free_link';break
                    }
                    if($next -eq 1 -or ($next -ge 268435440 -and $next -le 268435446)) {
                        $terminal='reserved';$reason='fat.chain.reserved_link';break
                    }
                    if($next -eq 268435447) {
                        $terminal='bad_cluster';$reason='fat.chain.bad_cluster_marker';break
                    }
                    if($next -ge 268435448) {
                        $terminal='eoc';$reason='fat.chain.eoc_observed';break
                    }
                    if($next -lt 2 -or $next -gt $MaxDataCluster) {
                        $terminal='out_of_range';$reason='fat.chain.out_of_range_link';break
                    }
                    if($visited.Contains($next)) {
                        $terminal='cycle';$reason='fat.chain.cycle_observed';break
                    }
                    $current=$next
                }
            }
            $complete=($terminal -ne 'truncated' -and $terminal -ne 'step_limit' -and
                $terminal -ne 'read_budget')
            $anomaly=($complete -and $terminal -ne 'eoc')
            if($complete) {
                $copyComplete++;$resolvedChains++
                if($anomaly){$anomalyChains++}
            } else {
                $copyIncomplete++;$allIncomplete=$true
            }
            $counts[$terminal]=[int]$counts[$terminal]+1
            [void]$allChains.Add([pscustomobject]@{
                fatIndex=$fat
                startCluster=[long]$start
                terminal=$terminal
                terminalReason=$reason
                entriesRead=$steps
                lastObservedCluster=$lastCluster
                scanIncomplete=(-not $complete)
                anomalyObserved=$anomaly
                confidence=$(if($complete){'verified'}else{'partial'})
            })
        }
        [void]$copies.Add([pscustomobject]@{
            fatIndex=$fat
            entriesRead=$copyEntries
            bytesRead=$copyBytes
            completedTraces=$copyComplete
            incompleteTraces=$copyIncomplete
            terminalCounts=[pscustomobject]$counts
        })
    }
    $comparable=0;$different=0
    for($i=0;$i -lt $StartClusters.Count;$i++) {
        $first=$allChains[$i]
        $second=$allChains[$i+$StartClusters.Count]
        if(-not $first.scanIncomplete -and -not $second.scanIncomplete) {
            $comparable++
            if($first.terminal -cne $second.terminal) {$different++}
        }
    }
    $warnings=New-Object System.Collections.ArrayList
    [void]$warnings.Add('geometry.caller_supplied_unverified')
    [void]$warnings.Add('coverage.sampled_chains_not_whole_fat')
    [void]$warnings.Add('fat.mirror_agreement_not_integrity_proof')
    [void]$warnings.Add('confidence.verified_only_means_observed_termination')
    if($allIncomplete){[void]$warnings.Add('coverage.chain_traversal_incomplete')}
    if($different -gt 0){[void]$warnings.Add('fat.mirror_terminal_disagreement_no_winner')}
    return [pscustomobject]@{
        schemaVersion='1'
        team='D'
        status=$(if($allIncomplete){'partial'}else{'ok'})
        scanIncomplete=$allIncomplete
        mode='read_only_chain_anomaly_statistics'
        writePermitted=$false
        geometryProvenance='caller_supplied_unverified'
        items=@($allChains.ToArray())
        copies=@($copies.ToArray())
        warnings=@($warnings.ToArray())
        errors=@()
        metrics=[pscustomobject]@{
            bytesRead=$bytesRead
            entriesChecked=$entriesChecked
            startClustersChecked=$StartClusters.Count
            requestedTraces=$($StartClusters.Count*2)
            resolvedTraces=$resolvedChains
            incompleteTraces=$($StartClusters.Count*2-$resolvedChains)
            anomalousResolvedTraces=$anomalyChains
            anomalyRateAmongResolvedTracesPercent=$(if($resolvedChains -gt 0){
                [Math]::Round(100.0*$anomalyChains/$resolvedChains,2)
            }else{$null})
            comparableMirrorTerminals=$comparable
            differentMirrorTerminals=$different
            maxReadBytes=$MaxReadBytes
            maxTotalEntries=$MaxTotalEntries
            maxStepsPerChain=$MaxStepsPerChain
            perFatByteQuota=$perFatByteQuota
            perFatEntryQuota=$perFatEntryQuota
        }
    }
}
Export-ModuleMember -Function Get-ChappyFatChainAnomalyStats
