#Requires -Version 5.1
# R7-P1: independent artificial-only stratified FAT evidence. No repairs or source selection.
Set-StrictMode -Version 2.0

function Read-D7Entry {
    param([IO.Stream]$Stream,[long]$Offset,[ref]$Used,[int]$MaxReadBytes)
    if($Offset -lt 0 -or $Offset -gt ([long]::MaxValue - 4)){throw 'invalid entry offset'}
    if(([long]$Used.Value+4) -gt $MaxReadBytes){return $null}
    if($Offset -gt $Stream.Length){return ,([byte[]]@())}
    $length=[int][Math]::Min(4L,($Stream.Length-$Offset))
    $bytes=New-Object 'byte[]' $length
    [void]$Stream.Seek($Offset,[IO.SeekOrigin]::Begin)
    $at=0
    while($at -lt $length){
        $got=$Stream.Read($bytes,$at,($length-$at))
        if($got -le 0){break}
        $at+=$got
    }
    $Used.Value=[long]$Used.Value+$at
    if($at -eq $length){return ,$bytes}
    $partial=New-Object 'byte[]' $at
    if($at -gt 0){[Array]::Copy($bytes,0,$partial,0,$at)}
    return ,$partial
}
function Test-D7Geometry {
    param($Candidate,[long]$SourceLength)
    $reason='';$valid=$true
    $fat1=0L;$fat2=0L;$size=0L;$root=0L;$clusters=0L;$end=0L
    try{
        if($Candidate.plausibility -ne 'plausible_unverified'){
            $reason='candidate.upstream_unverified_or_contradicted';$valid=$false
        }
        $g=$Candidate.geometry
        if($null -eq $g){throw 'missing geometry'}
        foreach($key in @('fat1OffsetBytes','fat2OffsetBytes','fatLengthBytes',
            'rootCluster','dataClusterCount','volumeEndExclusiveBytes')){
            if($null -eq $g.$key){throw 'missing geometry field'}
        }
        $fat1=[long]$g.fat1OffsetBytes
        $fat2=[long]$g.fat2OffsetBytes
        $size=[long]$g.fatLengthBytes
        $root=[long]$g.rootCluster
        $clusters=[long]$g.dataClusterCount
        $end=[long]$g.volumeEndExclusiveBytes
        if($fat1 -lt 0 -or $fat2 -lt 0 -or ($fat1%4) -ne 0 -or
            ($fat2%4) -ne 0 -or ($size%4) -ne 0 -or $size -lt 12 -or
            $size -gt ([long]::MaxValue-$fat1) -or
            $size -gt ([long]::MaxValue-$fat2)){
            $reason='geometry.invalid_or_overflow';$valid=$false
        }elseif(($fat1+$size) -ne $fat2 -or ($fat2+$size) -ge $end -or
            $end -gt $SourceLength){
            $reason='geometry.fat_exceeds_volume';$valid=$false
        }elseif($clusters -lt 2 -or $clusters -gt 268435438 -or
            $root -lt 2 -or $root -gt ($clusters+1) -or
            $size/4 -lt ($clusters+2)){
            $reason='geometry.cluster_capacity_invalid';$valid=$false
        }
    }catch{
        $reason='geometry.missing_or_non_numeric';$valid=$false
    }
    return [pscustomobject]@{
        valid=$valid
        reason=$reason
        fat1=$fat1
        fat2=$fat2
        fatLength=$size
        root=$root
        clusters=$clusters
        volumeEnd=$end
    }
}
function Get-D7SampleClass {
    param([long]$Value,[long]$ClusterIndex,[long]$Root,[long]$DataClusters,
        [uint32]$Raw)
    $suspect=$false
    $codes=New-Object System.Collections.ArrayList
    $marker='allocated_or_end'
    $maxCluster=$DataClusters+1L
    if($Value -eq 0){$marker='free'}
    elseif($Value -eq 1 -or ($Value -ge 268435440 -and $Value -le 268435446)){
        $marker='reserved';$suspect=$true;[void]$codes.Add('fat.reserved_marker')
    }elseif($Value -eq 268435447){
        $marker='bad';$suspect=$true;[void]$codes.Add('fat.bad_marker')
    }elseif($Value -ge 268435448){$marker='eoc'}
    elseif($Value -ge 2 -and $Value -le $maxCluster){$marker='link'}
    else{
        $marker='out_of_range'
        $suspect=$true
        [void]$codes.Add('fat.out_of_range_link')
    }
    if($ClusterIndex -eq 0 -and (($Value -band 268435200) -ne 268435200)){
        $suspect=$true;[void]$codes.Add('fat.prefix_media_unexpected')
    }
    if($ClusterIndex -eq 1 -and $Value -lt 268435448){
        $suspect=$true;[void]$codes.Add('fat.prefix_eoc_unexpected')
    }
    if($ClusterIndex -eq $Root -and $Value -eq 0){
        $suspect=$true;[void]$codes.Add('fat.root_start_free')
    }
    if(($Raw -band 65535) -eq 22763) {
        # Little-endian raw bytes EB 58 at the beginning of this FAT entry.
        $suspect=$true;[void]$codes.Add('fat.eb58_like_pair')
    }
    return [pscustomobject]@{
        marker=$marker
        suspect=$suspect
        evidence=@($codes.ToArray())
    }
}
function Get-ChappyFatStratifiedAnomalyEvidence {
    <#
    .SYNOPSIS
    Default-off independent R7 anomaly sampling under two untrusted VBR geometries.
    .DESCRIPTION
    Fixed three short windows per copy: FAT prefix 0..1, root..root+1,
    and deterministic midpoint..midpoint+1. Never authenticates a candidate.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [Parameter(Mandatory=$true)][object[]]$Candidates,
        [ValidateRange(16,256)][int]$MaxReadBytes=128,
        [ValidateRange(4,40)][int]$MaxEntries=32
    )
    if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite){
        throw 'Require readable, seekable, strictly non-writable stream'
    }
    if($Candidates.Count -ne 2 -or $null -eq $Candidates[0] -or $null -eq $Candidates[1]){
        throw 'Two ordered primary and backup candidates required'
    }
    $quota=[int][Math]::Min([Math]::Floor($MaxReadBytes/16.0),
        [Math]::Floor($MaxEntries/4.0))
    $used=[long]0;$totalEntries=0;$suspects=0;$incomplete=$false
    $reports=New-Object System.Collections.ArrayList
    $totalEB58=0
    for($candidateIndex=0;$candidateIndex -lt 2;$candidateIndex++){
        $candidate=$Candidates[$candidateIndex]
        $geo=Test-D7Geometry $candidate $Stream.Length
        $reason=New-Object System.Collections.ArrayList
        $copies=New-Object System.Collections.ArrayList
        $maps=@()
        if(-not $geo.valid){
            [void]$reason.Add($geo.reason)
            $incomplete=$true
        }else{
            $mid=1L+[long][Math]::Floor($geo.clusters/2.0)
            $windows=@(
                [pscustomobject]@{name='prefix';start=0L;count=2},
                [pscustomobject]@{name='root';start=$geo.root;count=2},
                [pscustomobject]@{name='midpoint';start=$mid;count=2}
            )
            for($copy=0;$copy -lt 2;$copy++){
                $origin=$(if($copy -eq 0){$geo.fat1}else{$geo.fat2})
                $values=New-Object 'System.Collections.Generic.Dictionary[long,long]'
                $mapFlags=New-Object 'System.Collections.Generic.Dictionary[long,bool]'
                $entryCount=0;$bytes=0;$copyIncomplete=$false
                $copySuspects=0;$eb58=0
                $copyReason=New-Object System.Collections.ArrayList
                $bins=New-Object System.Collections.ArrayList
                foreach($window in $windows){
                    $seen=0;$bad=0;$newCount=0
                    for($j=0;$j -lt $window.count;$j++){
                        $idx=[long]($window.start+$j)
                        if($values.ContainsKey($idx)){
                            $seen++
                            if($mapFlags[$idx]){$bad++}
                            continue
                        }
                        if($entryCount -ge $quota){
                            $copyIncomplete=$true
                            if($copyReason -notcontains 'budget.copy_entry_quota'){
                                [void]$copyReason.Add('budget.copy_entry_quota')
                            }
                            break
                        }
                        if($idx -gt ($geo.clusters+1) -or $idx -ge ($geo.fatLength/4)){
                            $copyIncomplete=$true
                            if($copyReason -notcontains 'coverage.window_exceeds_fat'){
                                [void]$copyReason.Add('coverage.window_exceeds_fat')
                            }
                            break
                        }
                        $at=[long]($origin+$idx*4)
                        $data=Read-D7Entry $Stream $at ([ref]$used) $MaxReadBytes
                        if($null -eq $data){
                            $copyIncomplete=$true
                            [void]$copyReason.Add('budget.global_byte_cap')
                            break
                        }
                        $bytes+=$data.Length
                        if($data.Length -ne 4){
                            $copyIncomplete=$true
                            [void]$copyReason.Add('io.entry_truncated')
                            break
                        }
                        $raw=[BitConverter]::ToUInt32($data,0)
                        $value=[long]($raw -band 268435455)
                        $class=Get-D7SampleClass $value $idx $geo.root $geo.clusters $raw
                        $values.Add($idx,$value)
                        $mapFlags.Add($idx,[bool]$class.suspect)
                        $entryCount++;$totalEntries++;$newCount++;$seen++
                        if($class.suspect){$bad++;$copySuspects++}
                        if($class.evidence -contains 'fat.eb58_like_pair'){$eb58++}
                    }
                    [void]$bins.Add([pscustomobject]@{
                        region=$window.name
                        requestedEntries=$window.count
                        observedEntries=$seen
                        newlyReadEntries=$newCount
                        suspiciousEntries=$bad
                        scanIncomplete=($seen -lt $window.count)
                    })
                }
                if($copyIncomplete){$incomplete=$true}
                $suspects+=$copySuspects
                $totalEB58+=$eb58
                [void]$copies.Add([pscustomobject]@{
                    fatIndex=$copy
                    sampleWindows=@($bins.ToArray())
                    observedUniqueEntries=$values.Count
                    unknownDeclaredEntries=([long]($geo.fatLength/4)-$values.Count)
                    suspiciousEntries=$copySuspects
                    eb58LikeEntries=$eb58
                    bytesRead=$bytes
                    scanIncomplete=$copyIncomplete
                    reasonCodes=@($copyReason.ToArray())
                    densityNumerator=$copySuspects
                    densityDenominator=$values.Count
                })
                $maps+=,$values
            }
        }
        $common=0;$same=0;$different=0
        if($geo.valid){
            foreach($idx in $maps[0].Keys){
                if($maps[1].ContainsKey($idx)){
                    $common++
                    if($maps[0][$idx] -eq $maps[1][$idx]){$same++}else{$different++}
                }
            }
        }
        [void]$reports.Add([pscustomobject]@{
            sourceRole=$(if($candidateIndex -eq 0){'primary'}else{'backup'})
            status=$(if(-not $geo.valid){'insufficient_evidence'}
                elseif($copies[0].scanIncomplete -or $copies[1].scanIncomplete){'partial'}
                else{'sample_observed'})
            geometryUnverified=$true
            samples=@($copies.ToArray())
            mirrors=[pscustomobject]@{
                commonEntries=$common
                matchingEntries=$same
                differingEntries=$different
                matchingDoesNotEstablishIntegrity=$true
            }
            reasonCodes=@($reason.ToArray())
        })
    }
    $statusCode=$(if($incomplete){'insufficient_evidence'}
        elseif($suspects -gt 0 -or $reports[0].mirrors.differingEntries -gt 0 -or
            $reports[1].mirrors.differingEntries -gt 0){'suspicious_samples_no_selection'}
        else{'ambiguous_samples_no_selection'})
    return [pscustomobject]@{
        schemaVersion='1'
        team='D'
        mode='experimental_stratified_fat_anomaly_samples'
        status=$(if($incomplete){'partial'}else{'ok'})
        scanIncomplete=$incomplete
        crossEvidence=$statusCode
        selectedCandidate=$null
        sourceDecision='not_selected'
        writePermitted=$false
        experimentalDefaultOff=$true
        items=@($reports.ToArray())
        warnings=@('geometry.candidates_unverified','fat.same_corruption_possible',
            'coverage.unsampled_entries_unknown','sample.suspicion_not_damage_proof',
            'source.no_selection_or_repair','real_master_img_trial_not_authorized')
        errors=@()
        metrics=[pscustomobject]@{
            bytesRead=$used
            entriesRead=$totalEntries
            maxReadBytes=$MaxReadBytes
            maxEntries=$MaxEntries
            maxWindowsPerCopy=3
            perCopyEntryQuota=$quota
            suspiciousEntries=$suspects
            eb58LikeEntries=$totalEB58
        }
    }
}
Export-ModuleMember -Function Get-ChappyFatStratifiedAnomalyEvidence
