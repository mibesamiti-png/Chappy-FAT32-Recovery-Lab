#Requires -Version 5.1
# Team D R9: independent, research-only/default-OFF tiny-window FAT evidence.
# No disk/path/device handles, no repair/output, no real IMG authorization.
Set-StrictMode -Version 2.0

function Read-D9Entry {
    param([IO.Stream]$Stream,[long]$Offset,[ref]$Used,[int]$MaxBytes)
    if($Offset -lt 0 -or $Offset -gt ([long]::MaxValue-4)){throw 'invalid numeric offset'}
    if(([long]$Used.Value+4) -gt $MaxBytes){return $null}
    if($Offset -gt $Stream.Length){return ,([byte[]]@())}
    $count=[int][Math]::Min(4L,($Stream.Length-$Offset))
    $b=New-Object 'byte[]' $count
    if($count -eq 0){return ,$b}
    [void]$Stream.Seek($Offset,[IO.SeekOrigin]::Begin)
    $read=0
    while($read -lt $count){
        $n=$Stream.Read($b,$read,($count-$read))
        if($n -le 0){break}
        $read+=$n
    }
    $Used.Value=[long]$Used.Value+$read
    if($read -eq $count){return ,$b}
    $partial=New-Object 'byte[]' $read
    if($read -gt 0){[Array]::Copy($b,0,$partial,0,$read)}
    return ,$partial
}
function Test-D9Candidate {
    param($Candidate,[long]$SourceLength)
    $ok=$true;$reason=''
    $a=0L;$b=0L;$size=0L;$root=0L;$clusters=0L;$end=0L
    try{
        if($Candidate.plausibility -ne 'plausible_unverified'){
            $reason='candidate.not_plausible';$ok=$false
        }
        if($null -eq $Candidate.geometry){throw 'missing'}
        $g=$Candidate.geometry
        foreach($key in @('fat1OffsetBytes','fat2OffsetBytes','fatLengthBytes','rootCluster','dataClusterCount','volumeEndExclusiveBytes')){
            if($null -eq $g.$key){throw 'missing'}
        }
        $a=[long]$g.fat1OffsetBytes;$b=[long]$g.fat2OffsetBytes
        $size=[long]$g.fatLengthBytes;$root=[long]$g.rootCluster
        $clusters=[long]$g.dataClusterCount;$end=[long]$g.volumeEndExclusiveBytes
        if($a -lt 0 -or $b -lt 0 -or ($a%4) -ne 0 -or ($b%4) -ne 0 -or
            $size -lt 12 -or ($size%4) -ne 0 -or
            $a -gt ([long]::MaxValue-$size) -or $b -gt ([long]::MaxValue-$size)){
            $reason='geometry.invalid_or_overflow';$ok=$false
        }elseif($a+$size -ne $b -or $b+$size -ge $end -or $end -gt $SourceLength){
            $reason='geometry.fat_outside_volume';$ok=$false
        }elseif($clusters -lt 2 -or $clusters -gt 268435438 -or
            $root -lt 2 -or $root -gt ($clusters+1) -or
            $size/4 -lt ($clusters+2)){
            $reason='geometry.cluster_capacity_invalid';$ok=$false
        }
    }catch{
        $reason='geometry.non_numeric_or_missing';$ok=$false
    }
    return [pscustomobject]@{valid=$ok;reason=$reason
        fat1=$a;fat2=$b;fatSize=$size;root=$root;clusters=$clusters}
}
function Get-D9RootChain {
    param([System.Collections.Generic.Dictionary[long,long]]$Values,[long]$Root,[long]$Clusters)
    $visited=New-Object 'System.Collections.Generic.HashSet[long]'
    $next=$Root
    for($step=0;$step -le 4;$step++){
        if(-not $visited.Add($next)){return 'cycle_observed'}
        if(-not $Values.ContainsKey($next)){return 'chain_outside_sample'}
        $v=[long]$Values[$next]
        if($v -ge 268435448){return 'eoc_observed'}
        if($v -eq 0){return 'free_link_observed'}
        if($v -eq 1 -or ($v -ge 268435440 -and $v -le 268435446)){
            return 'reserved_link_observed'
        }
        if($v -eq 268435447){return 'bad_link_observed'}
        if($v -lt 2 -or $v -gt ($Clusters+1)){return 'out_of_range_link_observed'}
        $next=$v
    }
    return 'chain_outside_sample'
}
function Get-ChappyFatLongCycleRemoteEvidence {
    <#
    .SYNOPSIS
    Experimental root-four, midpoint-two and far-two FAT sample under 40 entries.
    .DESCRIPTION
    Numeric-only, strictly read-only, never selects authentic geometry or FAT.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [Parameter(Mandatory=$true)][object[]]$Candidates,
        [ValidateRange(16,256)][int]$MaxReadBytes=160,
        [ValidateRange(4,40)][int]$MaxEntries=40
    )
    if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite){
        throw 'Requires strictly non-writable readable seekable stream'
    }
    if($Candidates.Count -ne 2 -or $null -eq $Candidates[0] -or $null -eq $Candidates[1]){
        throw 'Two unverified geometry candidates required'
    }
    $perCopy=[int][Math]::Min(10,[Math]::Floor([Math]::Min($MaxEntries,[Math]::Floor($MaxReadBytes/4.0))/4.0))
    $used=[long]0;$reads=0;$suspects=0;$cycles=0;$incomplete=$false
    $physical=New-Object 'System.Collections.Generic.HashSet[long]'
    $reports=New-Object System.Collections.ArrayList
    for($ci=0;$ci -lt 2;$ci++){
        $geo=Test-D9Candidate $Candidates[$ci] $Stream.Length
        $copies=New-Object System.Collections.ArrayList
        $maps=@()
        if(-not $geo.valid){
            $incomplete=$true
        }else{
            $middle=1L+[long][Math]::Floor($geo.clusters/2.0)
            $far=1L+[long][Math]::Floor((3.0*$geo.clusters)/4.0)
            $windows=@(
                [pscustomobject]@{name='prefix';at=0L;length=2},
                [pscustomobject]@{name='root';at=$geo.root;length=4},
                [pscustomobject]@{name='midpoint';at=$middle;length=2},
                [pscustomobject]@{name='far';at=$far;length=2}
            )
            for($fat=0;$fat -lt 2;$fat++){
                $origin=$(if($fat -eq 0){$geo.fat1}else{$geo.fat2})
                $map=New-Object 'System.Collections.Generic.Dictionary[long,long]'
                $codes=New-Object System.Collections.ArrayList
                $byWindow=New-Object System.Collections.ArrayList
                $copyReads=0;$copyBytes=0;$copySuspicious=0;$copyIncomplete=$false
                foreach($win in $windows){
                    $observed=0;$fresh=0;$suspiciousWindow=0
                    for($wi=0;$wi -lt $win.length;$wi++){
                        $idx=[long]($win.at+$wi)
                        if($idx -ge ($geo.fatSize/4) -or ($idx -gt ($geo.clusters+1) -and $win.name -ne 'prefix')){
                            $copyIncomplete=$true
                            if($codes -notcontains 'coverage.window_out_of_range'){[void]$codes.Add('coverage.window_out_of_range')}
                            break
                        }
                        if($map.ContainsKey($idx)){
                            $observed++
                            continue
                        }
                        if($copyReads -ge $perCopy){
                            $copyIncomplete=$true
                            if($codes -notcontains 'budget.copy_entry_quota'){[void]$codes.Add('budget.copy_entry_quota')}
                            break
                        }
                        $offset=[long]($origin+$idx*4)
                        $bytes=Read-D9Entry $Stream $offset ([ref]$used) $MaxReadBytes
                        if($null -eq $bytes){
                            $copyIncomplete=$true
                            if($codes -notcontains 'budget.global_bytes'){[void]$codes.Add('budget.global_bytes')}
                            break
                        }
                        $copyBytes+=$bytes.Length
                        if($bytes.Length -ne 4){
                            $copyIncomplete=$true
                            if($codes -notcontains 'io.entry_truncated'){[void]$codes.Add('io.entry_truncated')}
                            break
                        }
                        [void]$physical.Add($offset)
                        $raw=[BitConverter]::ToUInt32($bytes,0)
                        $value=[long]($raw -band 268435455)
                        $map.Add($idx,$value)
                        $copyReads++;$reads++;$fresh++;$observed++
                        $bad=$false
                        if($value -eq 1 -or ($value -ge 268435440 -and $value -le 268435447)){
                            $bad=$true
                        }elseif($value -ge 2 -and $value -lt 268435448 -and $value -gt ($geo.clusters+1)){
                            $bad=$true
                        }elseif(($raw -band 65535) -eq 22763){
                            $bad=$true
                        }elseif($idx -eq 0 -and ($value -band 268435200) -ne 268435200){
                            $bad=$true
                        }elseif($idx -eq 1 -and $value -lt 268435448){
                            $bad=$true
                        }elseif($idx -eq $geo.root -and $value -eq 0){
                            $bad=$true
                        }
                        if($bad){$copySuspicious++;$suspiciousWindow++}
                    }
                    [void]$byWindow.Add([pscustomobject]@{
                        region=$win.name;requestedEntries=$win.length
                        observedEntries=$observed;newlyReadEntries=$fresh
                        suspiciousNewEntries=$suspiciousWindow
                        scanIncomplete=($observed -ne $win.length)
                    })
                }
                $rootEvidence=Get-D9RootChain $map $geo.root $geo.clusters
                if($rootEvidence -eq 'cycle_observed'){$cycles++}
                if($rootEvidence -eq 'chain_outside_sample'){
                    $copyIncomplete=$true
                    if($codes -notcontains 'coverage.root_chain_outside_sample'){[void]$codes.Add('coverage.root_chain_outside_sample')}
                }
                if($rootEvidence -in @('cycle_observed','free_link_observed','bad_link_observed','reserved_link_observed','out_of_range_link_observed')){
                    $copySuspicious++
                }
                if($copyIncomplete){$incomplete=$true}
                $suspects+=$copySuspicious
                [void]$copies.Add([pscustomobject]@{
                    fatIndex=$fat
                    bytesRead=$copyBytes
                    observedUniqueEntries=$map.Count
                    unknownDeclaredEntries=([long]($geo.fatSize/4)-$map.Count)
                    rootChainEvidence=$rootEvidence
                    anomalyIndicators=$copySuspicious
                    sampleWindows=@($byWindow.ToArray())
                    scanIncomplete=$copyIncomplete
                    reasonCodes=@($codes.ToArray())
                })
                $maps+=,$map
            }
        }
        $common=0;$matching=0;$different=0
        if($geo.valid){
            foreach($key in $maps[0].Keys){
                if($maps[1].ContainsKey($key)){
                    $common++
                    if($maps[0][$key] -eq $maps[1][$key]){$matching++}else{$different++}
                }
            }
        }
        [void]$reports.Add([pscustomobject]@{
            sourceRole=$(if($ci -eq 0){'primary'}else{'backup'})
            geometryUnverified=$true
            status=$(if(-not $geo.valid){'insufficient_evidence'}
                elseif($copies[0].scanIncomplete -or $copies[1].scanIncomplete){'partial'}
                else{'sample_observed'})
            reasonCodes=$(if(-not $geo.valid){@($geo.reason)}else{@()})
            fatCopies=@($copies.ToArray())
            mirrors=[pscustomobject]@{
                commonEntries=$common;matchingEntries=$matching;differingEntries=$different
                comparisonDoesNotProveHealth=$true
            }
        })
    }
    if($used -gt $MaxReadBytes -or $reads -gt $MaxEntries -or $reads -gt 40){
        throw 'Internal budget violation'
    }
    $differentTotal=0
    foreach($item in $reports){$differentTotal+=$item.mirrors.differingEntries}
    $status=$(if($suspects -gt 0 -or $differentTotal -gt 0){'suspicious_samples_no_selection'}
        elseif($incomplete){'insufficient_evidence'}
        else{'ambiguous_samples_no_selection'})
    $warn=@('candidate.geometry_unverified','fat.matching_mirrors_not_health',
        'coverage.unsampled_entries_unknown','sample.suspicion_not_proof',
        'source.no_winner_or_repair','real_master_img_trial_not_authorized')
    if($incomplete){$warn+=,'coverage.incomplete'}
    return [pscustomobject]@{
        schemaVersion='1';team='D'
        mode='experimental_long_root_far_fat_evidence'
        status=$(if($incomplete){'partial'}else{'ok'})
        scanIncomplete=$incomplete;crossEvidence=$status
        experimentalDefaultOff=$true
        sourceDecision='not_selected';selectedCandidate=$null;writePermitted=$false
        items=@($reports.ToArray())
        warnings=@($warn);errors=@()
        metrics=[pscustomobject]@{
            bytesRead=$used
            entriesRead=$reads
            uniquePhysicalEntries=$physical.Count
            duplicatePhysicalEntryReads=($reads-$physical.Count)
            maxReadBytes=$MaxReadBytes;maxEntries=$MaxEntries
            perCopyEntryQuota=$perCopy
            maxWindowsPerCopy=4
            detectedRootCycles=$cycles
            anomalyIndicators=$suspects
        }
    }
}
Export-ModuleMember -Function Get-ChappyFatLongCycleRemoteEvidence
