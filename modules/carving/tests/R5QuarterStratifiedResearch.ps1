#Requires -Version 5.1
# C R5 held-out equal-quarter windows; test-only and default OFF.
# Uses geometry only for fixed offsets. Oracle is passed only to scorer.
function Invoke-CQuarterStratifiedTrial {
    [CmdletBinding()]
    param([Parameter(Mandatory)][IO.Stream]$Stream,[Parameter(Mandatory)]$Geometry)
    $unknown=[pscustomobject]@{status='unknown';reason='quarter.scan_incomplete';originalIdentity='unknown';starts=@();items=@();metrics=[pscustomobject]@{sourceBytesRead=0L;readCalls=0;probes=0;candidateCount=0;elapsedMilliseconds=0;windowBytes=0L;scannedBytes=0L}}
    if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite){$unknown.reason='quarter.not_readonly';return $unknown}
    $width=16384L
    $maxSource=98304L
    $start=[long]$Geometry.dataOffsetBytes
    $clusterBytes=[long]$Geometry.clusterSizeBytes
    $clusters=[long]$Geometry.clusterCount
    $end=[long]$Geometry.partitionEndBytes
    $first=[long]$Geometry.partitionOffsetBytes
    $bps=[long]$Geometry.bytesPerSector
    $spc=[long]$Geometry.sectorsPerCluster
    $fats=[long]$Geometry.fatCount
    $fatSectors=[long]$Geometry.fatSizeSectors
    $valid=($bps -in @(512L,1024L,2048L,4096L) -and $spc -ge 1L -and $spc -le 128L -and
        (($spc -band ($spc-1L)) -eq 0) -and $clusterBytes -eq $bps*$spc -and
        $clusters -ge 65525L -and $clusters -le 1000000L -and $fats -ge 1L -and $fats -le 2L -and
        $fatSectors -gt 0L -and $first -ge 0L -and $end -le $Stream.Length -and $end -gt $first -and
        $start -gt ($first+$fats*$fatSectors*$bps) -and $start -le ($end-65536L) -and
        (($start-$first)%$bps) -eq 0 -and ($end-$start) -ge ($clusters*$clusterBytes) -and
        ($end-$start) -lt (($clusters+1L)*$clusterBytes))
    if(-not $valid){$unknown.reason='quarter.geometry_invalid';return $unknown}
    $starts=@(
        [long]$start,
        [long]($start+[long][Math]::Floor($clusters/4.0)*$clusterBytes),
        [long]($start+[long][Math]::Floor($clusters/2.0)*$clusterBytes),
        [long]($start+[long][Math]::Floor($clusters*3.0/4.0)*$clusterBytes)
    )
    foreach($at in $starts){if($at -lt $start -or $at -gt ($end-$width)){$unknown.reason='quarter.schedule_invalid';return $unknown}}
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $items=New-Object 'System.Collections.Generic.List[object]'
    $read=0L;$calls=0;$probes=0;$scanned=0L;$failure=$null
    foreach($at in $starts){
        $remaining=30000-[int]$clock.ElapsedMilliseconds
        if($remaining -lt 100){$failure='quarter.time_exhausted';break}
        if($items.Count -ge 16 -or $probes -ge 16){$failure='quarter.probe_or_candidate_exhausted';break}
        $scan=Get-ChappyCarvingCandidates -Stream $Stream -StartOffset $at -MaxScanBytes $width -ExtraValidationReadBytes 8192 -MaxFileBytes 4096 -MaxCandidates (16-$items.Count) -MaxProbes (16-$probes) -MaxProbeBytes 8192 -MaxWorkMilliseconds $remaining
        $read += [long]$scan.metrics.bytesRead
        $calls += [int]$scan.metrics.readRequests
        $probes += [int]$scan.metrics.entriesChecked
        $scanned += [long]$scan.metrics.scannedBytes
        if($scan.status -eq 'error' -or $scan.metrics.scannedBytes -lt $width -or @($scan.warnings|Where-Object {$_ -in @('scan.read_budget_exhausted','scan.probe_budget_exhausted','scan.time_budget_exhausted')}).Count -gt 0){$failure='quarter.scan_truncated_or_exhausted';break}
        foreach($candidate in @($scan.items)){
            if($null -eq $candidate.PSObject.Properties['integrityScope'] -or $candidate.integrityScope -ceq 'original_file_integrity'){$failure='quarter.untrusted_original_claim';break}
            $items.Add($candidate)
        }
        if($null -ne $failure){break}
    }
    $clock.Stop()
    if($read -gt $maxSource -or $probes -gt 16 -or $items.Count -gt 16 -or $scanned -gt 65536L -or $clock.ElapsedMilliseconds -gt 30000){throw 'C quarter-stratified cap violated'}
    if($null -ne $failure){$items.Clear()}
    return [pscustomobject]@{
        status=$(if($null -ne $failure){'unknown'}else{'partial'})
        reason=$(if($null -ne $failure){$failure}else{'quarter.unscanned_regions_unknown'})
        originalIdentity='unknown';starts=$starts;items=@($items.ToArray())
        metrics=[pscustomobject]@{sourceBytesRead=$read;readCalls=$calls;probes=$probes;candidateCount=$items.Count;elapsedMilliseconds=[int]$clock.ElapsedMilliseconds;windowBytes=($width*$starts.Count);scannedBytes=$scanned}
    }
}

# Independent synthetic scorer fixture. The C scanner never receives truth,
# seed, labels, original SHA, destination cluster, or decoy offsets.
function New-CQuarterHeldoutFixture {
    param([ValidateSet(202614,202615,202616,202617,202618,202619)][int]$Seed,[ValidateSet(1,2)][int]$Spc)
    $fixture=New-ChappyA3DStandardFixture -Seed $Seed -SectorsPerCluster $Spc
    [byte[]]$image=$fixture.image
    $view=[IO.MemoryStream]::new($image,$false)
    try{$geo=Get-ChappyFat32Geometry -Stream $view}finally{$view.Dispose()}
    $clusterBytes=[long]$geo.clusterSizeBytes
    $fatBytes=[long]$geo.fatSizeSectors*[long]$geo.bytesPerSector
    $fat1=[long]$geo.dataOffsetBytes-2L*$fatBytes
    $fat2=$fat1+$fatBytes
    $model=@($fixture.oracle|Where-Object {$_.shortName -ceq 'MODEL   3MF'})[0]
    if($null -eq $model){throw 'Held-out synthetic 3MF oracle missing'}
    [byte[]]$payload=New-Object byte[] ([int]$model.lengthBytes)
    $copied=0
    foreach($extent in @($model.extents)){[Array]::Copy($image,[int]$extent.offsetBytes,$payload,$copied,[int]$extent.lengthBytes);$copied += [int]$extent.lengthBytes}
    if($copied -ne $payload.Length -or (Get-A3DSha256 $payload) -cne $model.sha256){throw 'Held-out scorer source mismatch'}
    foreach($extent in @($model.extents)){
        [Array]::Clear($image,[int]$extent.offsetBytes,[int]$clusterBytes)
        Set-A3DUint32 $image ([int]($fat1+4L*[long]$extent.cluster)) 0
        Set-A3DUint32 $image ([int]($fat2+4L*[long]$extent.cluster)) 0
    }
    $placementNumerator=switch($Seed){202614 {2} 202615 {4} 202616 {6} 202617 {1} 202618 {3} default {7}}
    $isAligned=($placementNumerator -eq 2 -or $placementNumerator -eq 4 -or $placementNumerator -eq 6)
    $destination=[long]2+[long][Math]::Floor($geo.clusterCount*$placementNumerator/8.0)
    $needed=[int][Math]::Ceiling($payload.Length/[double]$clusterBytes)
    if($destination -lt 10 -or $destination+$needed -gt ([long]$geo.clusterCount+1L)){throw 'Held-out destination outside synthetic volume'}
    $newExtents=New-Object 'System.Collections.Generic.List[object]'
    for($i=0;$i -lt $needed;$i++){
        $cluster=$destination+$i
        $next=if($i+1 -lt $needed){[uint32]($cluster+1L)}else{[uint32]0x0FFFFFFF}
        Set-A3DUint32 $image ([int]($fat1+4L*$cluster)) $next
        Set-A3DUint32 $image ([int]($fat2+4L*$cluster)) $next
        $offset=[long]$geo.dataOffsetBytes+($cluster-2L)*$clusterBytes
        $length=[int][Math]::Min($clusterBytes,$payload.Length-$i*$clusterBytes)
        [Array]::Copy($payload,($i*[int]$clusterBytes),$image,[int]$offset,$length)
        $newExtents.Add([pscustomobject]@{cluster=$cluster;offsetBytes=$offset;lengthBytes=$length})
    }
    $rootOffset=[long]$geo.dataOffsetBytes+([long]$geo.rootCluster-2L)*$clusterBytes
    $entryIndex=1
    Set-A3DUint16 $image ([int]($rootOffset+32L*$entryIndex+26L)) ([uint16]$destination)
    $truth=@(foreach($file in $fixture.oracle){
        if($file.shortName -ceq 'MODEL   3MF'){
            [pscustomobject]@{shortName=$file.shortName;lengthBytes=$file.lengthBytes;sha256=$file.sha256;extents=@($newExtents.ToArray())}
        }else{$file}
    })
    $decoyAt=[long]$geo.dataOffsetBytes+[long][Math]::Floor($geo.clusterCount/16.0)*$clusterBytes+64L
    [Array]::Copy([byte[]]@(0x50,0x4B,0x03,0x04),0,$image,[int]$decoyAt,4)
    return [pscustomobject]@{image=$image;geometry=$geo;truth=$truth;decoyAt=$decoyAt;destination=$destination;placementNumerator=$placementNumerator;isAligned=$isAligned}
}

function Assert-CQuarterArm($Result,$Meter,[string]$Name) {
    if($Result.status -ne 'partial' -or $Result.originalIdentity -ne 'unknown' -or
        $Meter.BytesRead -ne $Result.metrics.sourceBytesRead -or $Meter.BytesRead -gt 98304 -or
        $Result.metrics.probes -gt 16 -or @($Result.items).Count -gt 16 -or $Meter.CanWrite) {
        throw ('C quarter arm violates shared safety/work bounds: '+$Name)
    }
}
function Invoke-CQuarterStratifiedWindowRegression {
    $repoRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $repoRoot 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
    . (Join-Path $repoRoot 'modules\directory\DirectoryScanner.ps1')
    $cases=0;$baseHits=0;$midHits=0;$quarterHits=0;$baseExact=0;$midExact=0;$quarterExact=0
    $falseBase=0;$falseMid=0;$falseQuarter=0;$quarterBytes=0L;$midBytes=0L;$baseBytes=0L;$quarterCalls=0L;$midCalls=0L;$baseCalls=0L
    $quarterUnique=0L;$midUnique=0L;$baseUnique=0L;$quarterMs=0L;$midMs=0L;$baseMs=0L
    $alignedCases=0;$offgridCases=0;$offgridBaseUnknown=0;$offgridMidUnknown=0;$offgridQuarterUnknown=0
    $baseDecoySeen=0;$midDecoySeen=0;$quarterDecoySeen=0
    foreach($seed in @(202614,202615,202616,202617,202618,202619)){foreach($spc in @(1,2)){
        $case=New-CQuarterHeldoutFixture -Seed $seed -Spc $spc
        [byte[]]$img=$case.image
        $before=Get-A3DSha256 $img
        $baselineMeter=[ChappyCSparseReadMeter]::new([IO.MemoryStream]::new($img,$false))
        $midpointMeter=[ChappyCSparseReadMeter]::new([IO.MemoryStream]::new($img,$false))
        $quarterMeter=[ChappyCSparseReadMeter]::new([IO.MemoryStream]::new($img,$false))
        try{
            $base=Invoke-CSparseDataWindowTrial -Stream $baselineMeter -Geometry $case.geometry
            $midpoint=Invoke-CSparseDataWindowTrial -Stream $midpointMeter -Geometry $case.geometry -EnableSparseWindows
            $quarter=Invoke-CQuarterStratifiedTrial -Stream $quarterMeter -Geometry $case.geometry
            Assert-CQuarterArm $base $baselineMeter 'contiguous'
            Assert-CQuarterArm $midpoint $midpointMeter 'start-midpoint'
            Assert-CQuarterArm $quarter $quarterMeter 'four-quarter'
            if($base.metrics.scannedBytes -ne 65536 -or $midpoint.metrics.scannedBytes -ne 65536 -or
                $quarter.metrics.scannedBytes -ne 65536){throw 'C quarter arms scanned unequal/overbudget logical bytes'}
            $scBase=Get-CSparseSyntheticScore -Image $img -Truth $case.truth -Items @($base.items) -FatDecoyAt -1 -RootDecoyAt $case.decoyAt
            $scMid=Get-CSparseSyntheticScore -Image $img -Truth $case.truth -Items @($midpoint.items) -FatDecoyAt -1 -RootDecoyAt $case.decoyAt
            $scQuarter=Get-CSparseSyntheticScore -Image $img -Truth $case.truth -Items @($quarter.items) -FatDecoyAt -1 -RootDecoyAt $case.decoyAt
            if($scBase.wrongOriginalClaims+$scMid.wrongOriginalClaims+$scQuarter.wrongOriginalClaims -gt 0){throw 'C quarter arm made original identity claim'}
            if($scBase.rootDecoySeen+$scMid.rootDecoySeen+$scQuarter.rootDecoySeen -ne 0){throw 'C quarter arm promoted off-grid PK decoy'}
            $targetTruth=@($case.truth|Where-Object {$_.shortName -ceq 'MODEL   3MF'})[0]
            $targetOffset=[long]$targetTruth.extents[0].offsetBytes
            if($case.isAligned){$alignedCases++}
            else {
                $offgridCases++
                $allItems=@($base.items)+@($midpoint.items)+@($quarter.items)
                if(@($allItems|Where-Object {$_.offsetBytes -eq $targetOffset}).Count -ne 0){throw 'Off-grid original 3MF unexpectedly observed'}
                if($base.reason -cne 'sparse.unscanned_regions_unknown' -or $midpoint.reason -cne 'sparse.unscanned_regions_unknown' -or
                    $quarter.reason -cne 'quarter.unscanned_regions_unknown' -or
                    $base.originalIdentity -cne 'unknown' -or $midpoint.originalIdentity -cne 'unknown' -or $quarter.originalIdentity -cne 'unknown') {
                    throw 'Off-grid true file must stay explicitly unknown'
                }
                $offgridBaseUnknown++;$offgridMidUnknown++;$offgridQuarterUnknown++
            }
            if($scBase.fatDecoyAccepted+$scMid.fatDecoyAccepted+$scQuarter.fatDecoyAccepted -gt 0){throw 'C quarter schedule promoted off-grid PK decoy'}
            $baseDecoySeen+=$scBase.rootDecoySeen;$midDecoySeen+=$scMid.rootDecoySeen;$quarterDecoySeen+=$scQuarter.rootDecoySeen
            if($scBase.rootDecoySeen+$scMid.rootDecoySeen+$scQuarter.rootDecoySeen -ne 0){throw 'C quarter scanner observed off-grid PK decoy'}
            $baseHits+=$scBase.trueHeader;$midHits+=$scMid.trueHeader;$quarterHits+=$scQuarter.trueHeader
            $baseExact+=$scBase.exact;$midExact+=$scMid.exact;$quarterExact+=$scQuarter.exact
            $falseBase+=$scBase.falseObservations;$falseMid+=$scMid.falseObservations;$falseQuarter+=$scQuarter.falseObservations
            $baseBytes+=$baselineMeter.BytesRead;$midBytes+=$midpointMeter.BytesRead;$quarterBytes+=$quarterMeter.BytesRead
            $baseCalls+=$baselineMeter.ReadCalls;$midCalls+=$midpointMeter.ReadCalls;$quarterCalls+=$quarterMeter.ReadCalls
            $baseUnique+=$baselineMeter.UniqueBytes;$midUnique+=$midpointMeter.UniqueBytes;$quarterUnique+=$quarterMeter.UniqueBytes
            $baseMs+=$base.metrics.elapsedMilliseconds;$midMs+=$midpoint.metrics.elapsedMilliseconds;$quarterMs+=$quarter.metrics.elapsedMilliseconds
            $cases++
            Write-Host ('C QUARTER CASE seed={0} spc={1} placement={2}/8 aligned={3} true={4}/{5}/{6} exact={7}/{8}/{9} false={10} bytes={11}/{12}/{13} calls={14}/{15}/{16} scan_unknown_status={17}/{18}/{19}' -f
                $seed,$spc,$case.placementNumerator,$case.isAligned,$scBase.trueHeader,$scMid.trueHeader,$scQuarter.trueHeader,$scBase.exact,$scMid.exact,$scQuarter.exact,$scQuarter.falseObservations,
                $baselineMeter.BytesRead,$midpointMeter.BytesRead,$quarterMeter.BytesRead,$baselineMeter.ReadCalls,$midpointMeter.ReadCalls,$quarterMeter.ReadCalls,
                ($base.status -eq 'unknown'),($midpoint.status -eq 'unknown'),($quarter.status -eq 'unknown'))
        }finally{$baselineMeter.Dispose();$midpointMeter.Dispose();$quarterMeter.Dispose()}
        if((Get-A3DSha256 $img) -cne $before){throw 'C quarter input bytes changed'}
        $img=$null;$case=$null;[GC]::Collect()
    }}
    if($cases -ne 12 -or $quarterBytes -le 0 -or $quarterCalls -le 0){throw 'C quarter held-out suite incomplete'}
    if($alignedCases -ne 6 -or $offgridCases -ne 6 -or $offgridBaseUnknown -ne 6 -or $offgridMidUnknown -ne 6 -or $offgridQuarterUnknown -ne 6 -or
       $baseDecoySeen -ne 0 -or $midDecoySeen -ne 0 -or $quarterDecoySeen -ne 0 -or
       $baseHits -ne 0 -or $midHits -ne 2 -or $quarterHits -ne 6 -or
       $baseExact -ne 0 -or $midExact -ne 2 -or $quarterExact -ne 6 -or $falseBase -ne 0 -or $falseMid -ne 0 -or $falseQuarter -ne 0) {
        throw 'C quarter held-out registered detection/identity outcomes changed'
    }
    if($quarterUnique -gt $quarterBytes -or $midUnique -gt $midBytes -or $baseUnique -gt $baseBytes) {throw 'C quarter unique bytes exceed returned bytes'}
    Write-Host ('C QUARTER SUMMARY images={0} aligned={1} offgrid_file_unknown={2}/{3}/{4} true_headers={5}/{6}/{7} false_negative_labels={8}/{9}/{10} exact_sha={11}/{12}/{13} false_candidates={14}/{15}/{16} offgrid_decoy_observations={17}/{18}/{19} physical_bytes={20}/{21}/{22} unique_bytes={23}/{24}/{25} Stream.Read_calls={26}/{27}/{28} summed_elapsed_ms={29}/{30}/{31} overall_original_claims=0' -f
        $cases,$alignedCases,$offgridBaseUnknown,$offgridMidUnknown,$offgridQuarterUnknown,$baseHits,$midHits,$quarterHits,(12-$baseHits),(12-$midHits),(12-$quarterHits),$baseExact,$midExact,$quarterExact,$falseBase,$falseMid,$falseQuarter,$baseDecoySeen,$midDecoySeen,$quarterDecoySeen,$baseBytes,$midBytes,$quarterBytes,$baseUnique,$midUnique,$quarterUnique,$baseCalls,$midCalls,$quarterCalls,$baseMs,$midMs,$quarterMs)
    Write-Host 'PASS: C equal-quarter 4x16KiB held-out schedule vs contiguous and prior midpoint, synthetic-only'
}
