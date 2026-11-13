#Requires -Version 5.1
# Team D / Issue #73 / gate D6-02: bounded, numeric-only shared FAT-chain observation.
# This is a caller-hint observation, not a file ownership, FAT winner, or repair API.
Set-StrictMode -Version 2.0

function Get-ChappyFatSharedChainEvidence {
    <#
    .SYNOPSIS
    Report whether two distinct caller-hinted FAT chains physically converge.
    .DESCRIPTION
    Observes two FAT copies separately on one nonwritable Stream. Shared
    cluster numbers are evidence of convergence among the *sampled* traces,
    not proof that two files exist, own those clusters, or are corrupt.
    All geometry and chain starts are caller supplied and unverified.
    Never opens files, emits names/content, chooses a FAT copy, or writes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.IO.Stream]$Stream,
        [Parameter(Mandatory=$true)][long]$Fat1OffsetBytes,
        [Parameter(Mandatory=$true)][long]$Fat2OffsetBytes,
        [Parameter(Mandatory=$true)][long]$FatLengthBytes,
        [Parameter(Mandatory=$true)][long]$MaxDataCluster,
        [Parameter(Mandatory=$true)][long[]]$StartClusters,
        [ValidateRange(16,1024)][int]$MaxReadBytes=256,
        [ValidateRange(1,16)][int]$MaxStepsPerChain=8,
        [ValidateRange(4,256)][int]$MaxReadCalls=128
    )
    if($null -eq $Stream -or -not $Stream.CanRead -or
       -not $Stream.CanSeek -or $Stream.CanWrite) {
        throw 'Requires a readable seekable strictly nonwritable source Stream'
    }
    if($null -eq $StartClusters -or $StartClusters.Count -ne 2 -or
       $StartClusters[0] -eq $StartClusters[1]) {
        throw 'Two different numeric chain start hints required'
    }
    if($Fat1OffsetBytes -lt 0 -or $Fat2OffsetBytes -lt 0 -or
       ($Fat1OffsetBytes % 4) -ne 0 -or ($Fat2OffsetBytes % 4) -ne 0 -or
       $FatLengthBytes -lt 12 -or ($FatLengthBytes % 4) -ne 0 -or
       $Fat1OffsetBytes -gt ([long]::MaxValue-$FatLengthBytes) -or
       $Fat2OffsetBytes -gt ([long]::MaxValue-$FatLengthBytes)) {
        throw 'Invalid or overflowing caller FAT geometry'
    }
    $end1=$Fat1OffsetBytes+$FatLengthBytes
    $end2=$Fat2OffsetBytes+$FatLengthBytes
    if(($Fat1OffsetBytes -lt $end2 -and $Fat2OffsetBytes -lt $end1) -or
       $end1 -gt $Stream.Length -or $end2 -gt $Stream.Length) {
        throw 'Overlapping FATs or declared FAT beyond source length'
    }
    if($MaxDataCluster -lt 2 -or $MaxDataCluster -gt 268435439 -or
       ($MaxDataCluster+1) -gt [long]($FatLengthBytes/4)) {
        throw 'Invalid caller-provided data cluster upper bound'
    }

    # Divide one physical returned-byte budget between mirrors. The second
    # copy cannot be starved by the first; no mid-invocation reset occurs.
    $perFatCap=[long]([Math]::Floor($MaxReadBytes/8.0)*4)
    $offsets=[long[]]@($Fat1OffsetBytes,$Fat2OffsetBytes)
    $all=New-Object System.Collections.ArrayList
    $copies=New-Object System.Collections.ArrayList
    $uniqueBytes=New-Object 'System.Collections.Generic.HashSet[long]'
    $actual=0L;$calls=0L;$shortReturns=0L;$zeroEarly=0L
    $incompleteTraces=0L;$sharedCopies=0L

    for($fat=0;$fat -lt 2;$fat++) {
        $copyBytes=0L
        $observedSets=@(
            (New-Object 'System.Collections.Generic.HashSet[long]'),
            (New-Object 'System.Collections.Generic.HashSet[long]')
        )
        for($i=0;$i -lt 2;$i++) {
            $start=[long]$StartClusters[$i]
            $current=$start;$steps=0
            $visited=New-Object 'System.Collections.Generic.HashSet[long]'
            $terminal='';$reason='';$partial=$false
            if($current -lt 2 -or $current -gt $MaxDataCluster) {
                $terminal='invalid_start';$reason='fat.chain.invalid_start'
            } else {
                while($true) {
                    if($steps -ge $MaxStepsPerChain) {
                        $terminal='step_cap';$reason='budget.chain_steps';$partial=$true;break
                    }
                    if(($copyBytes+4) -gt $perFatCap) {
                        $terminal='byte_cap';$reason='budget.fat_copy_quota';$partial=$true;break
                    }
                    if(-not $visited.Add($current)) {
                        $terminal='cycle';$reason='fat.chain.cycle_observed';break
                    }
                    # Numeric offsets were checked for overflow and source extent
                    # above, and current is <= MaxDataCluster <= FAT entries-2.
                    $at=[long]($offsets[$fat]+$current*4)
                    if($at -gt $Stream.Length-4) {
                        $terminal='truncated';$reason='io.fat_entry_truncated';$partial=$true;break
                    }
                    [void]$Stream.Seek($at,[System.IO.SeekOrigin]::Begin)
                    $raw=New-Object 'byte[]' 4
                    $got=0
                    $readError=$false
                    while($got -lt 4) {
                        if($calls -ge $MaxReadCalls) {
                            $terminal='read_call_cap';$reason='budget.physical_read_calls'
                            $partial=$true;break
                        }
                        $request=4-$got
                        $readAt=[long]($at+$got)
                        try {
                            $n=$Stream.Read($raw,$got,$request)
                        } catch {
                            $terminal='read_error';$reason='io.source_read_exception'
                            $partial=$true;$readError=$true;break
                        }
                        $calls++
                        if($n -lt 0 -or $n -gt $request) {
                            throw 'Source violated Stream.Read returned-byte contract'
                        }
                        if($n -eq 0) {
                            $terminal='truncated';$reason='io.short_read'
                            $partial=$true
                            if($readAt -lt $Stream.Length){$zeroEarly++}
                            break
                        }
                        if($n -lt $request){$shortReturns++}
                        for($j=0;$j -lt $n;$j++) {
                            [void]$uniqueBytes.Add([long]($readAt+$j))
                        }
                        $got+=$n
                        $actual+=[long]$n
                        $copyBytes+=[long]$n
                    }
                    if($got -ne 4 -or $readError){break}
                    [void]$observedSets[$i].Add($current)
                    $steps++
                    # Only FAT32's low 28 bits can encode chain links.
                    $next=[long]([BitConverter]::ToUInt32($raw,0) -band 0x0FFFFFFF)
                    if($next -eq 0) {
                        $terminal='free';$reason='fat.chain.free_link_observed';break
                    }
                    if($next -eq 1 -or ($next -ge 268435440 -and $next -le 268435446)) {
                        $terminal='reserved';$reason='fat.chain.reserved_link_observed';break
                    }
                    if($next -eq 268435447) {
                        $terminal='bad_cluster';$reason='fat.chain.bad_cluster_observed';break
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
            if($partial){$incompleteTraces++}
            [void]$all.Add([pscustomobject]@{
                fatCopyIndex=$fat;startHintIndex=$i;startCluster=$start
                terminal=$terminal;reason=$reason;observedCompleteEntries=$steps
                scanIncomplete=$partial
            })
        }
        $common=New-Object System.Collections.ArrayList
        foreach($cluster in $observedSets[0]) {
            if($observedSets[1].Contains($cluster)) {
                [void]$common.Add([long]$cluster)
            }
        }
        $commonSorted=@($common.ToArray() | Sort-Object)
        if($commonSorted.Count -gt 0){$sharedCopies++}
        [void]$copies.Add([pscustomobject]@{
            fatCopyIndex=$fat;returnedBytes=$copyBytes
            start1ObservedEntries=$observedSets[0].Count
            start2ObservedEntries=$observedSets[1].Count
            sharedObservedClusterCount=$commonSorted.Count
            sharedObservedClusters=@($commonSorted)
            sharedEvidence=$(if($commonSorted.Count -gt 0){
                'fat.chain.shared_cluster_observed'
            }else{'fat.chain.no_shared_cluster_in_observed_trace'})
            # Absence of an observed shared cluster cannot prove global absence.
            missingSharedEvidenceIsProof=$false
        })
    }
    $warnings=@(
        'geometry.caller_supplied_unverified',
        'source.internal_stream_reads_not_A_receipts',
        'fat.shared_cluster_not_file_ownership',
        'fat.mirror_agreement_not_integrity',
        'coverage.sampled_chains_not_whole_fat'
    )
    if($incompleteTraces -gt 0) {
        $warnings+= 'coverage.chain_traversal_incomplete'
    }
    return [pscustomobject]@{
        schemaVersion='1';team='D';mode='read_only_shared_chain_observation'
        status=$(if($incompleteTraces -gt 0){'partial'}else{'ok'})
        scanIncomplete=$true
        tracesIncomplete=($incompleteTraces -gt 0)
        geometryProvenance='caller_supplied_unverified'
        sourceObservationProvenance='internal_read_not_A_attested'
        originalIdentity='unknown';fileOwner='unknown'
        fatCopyWinner='not_selected';writePermitted=$false
        sharedObservedInCopies=$sharedCopies
        items=@($all.ToArray());copies=@($copies.ToArray())
        warnings=@($warnings);errors=@()
        metrics=[pscustomobject]@{
            actualReturnedBytes=$actual
            uniqueReturnedBytes=[long]$uniqueBytes.Count
            repeatedReturnedBytes=($actual-[long]$uniqueBytes.Count)
            physicalReadCalls=$calls
            shortPhysicalReadReturns=$shortReturns
            prematureZeroBeforeStreamEnd=$zeroEarly
            maxReadBytes=$MaxReadBytes;maxReadCalls=$MaxReadCalls
            perFatReturnedByteCap=$perFatCap
            requestedStartTraces=4;incompleteTraces=$incompleteTraces
            wholeFatEntriesCovered=$false
        }
    }
}

Export-ModuleMember -Function Get-ChappyFatSharedChainEvidence
