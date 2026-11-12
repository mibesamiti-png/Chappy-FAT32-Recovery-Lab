#Requires -Version 5.1
# A R7 synthetic-only integration: C's default-OFF data-region research reads
# share one A-issued physical source quota with actual B geometry/directory and
# D FAT evidence. NOT a production interface or original-file authentication.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Test-A3DSharedReadProvenance.ps1')
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')
. (Join-Path $root 'modules\carving\tests\R5StandardDataWindowResearch.ps1')

function Assert-A7Data([bool]$Condition,[string]$Code) {
    if(-not $Condition){throw ('A7_DATA_REGION_BRIDGE_FAIL: '+$Code)}
}
$cases=0;$found=0;$physicalTotal=0L;$uniqueTotal=0L;$quotaRefusals=0
$exactScorer=0
foreach($spc in @(1,2)){
    $fixture=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
    [byte[]]$img=$fixture.image
    $before=Get-A3DSha256 $img
    $raw=[IO.MemoryStream]::new($img,$false)
    $meter=[ChappyA7SharedSource]::new($raw,120000L)
    try {
        Assert-A7Data (-not $raw.CanWrite -and -not $meter.CanWrite -and $meter.MaximumBytes -eq 120000L) 'nonwritable_shared_meter'
        $meter.BeginConsumer('geometry')
        $geo=Get-ChappyFat32Geometry -Stream $meter
        Assert-A7Data ($geo.clusterCount -eq 65541 -and $geo.fatCount -eq 2 -and
            $geo.dataOffsetBytes -gt 65536 -and $geo.sectorsPerCluster -eq $spc) 'real_B_numeric_geometry'

        $meter.BeginConsumer('directory')
        $directory=Get-ChappyDirectoryCandidates -Stream $meter -Geometry $geo -MaxScanBytes (512*$spc) -MaxCandidates 16 -MaxDirectories 4 -RecordDirectoryReadSpans -MaxDirectoryReadSpans 8
        Assert-A7Data ($directory.team -ceq 'B' -and $directory.metrics.bytesRead -eq (512*$spc) -and
            $directory.directoryReadEvidence.status -ceq 'recorded') 'real_B_root_observation'

        $meter.BeginConsumer('carving')
        $carving=Invoke-CStandardDataTrial -Stream $meter -Geometry $geo -EnableDataWindow
        Assert-A7Data ($carving.status -ceq 'partial' -and $carving.originalIdentity -ceq 'unknown' -and
            $carving.start -eq $geo.dataOffsetBytes -and @($carving.items).Count -gt 0 -and
            $carving.metrics.sourceBytesRead -le 98304L) 'C_data_window_bounded_and_partial'
        foreach($candidate in @($carving.items)){
            Assert-A7Data ($candidate.integrityScope -cne 'original_file_integrity' -and
                $null -eq $candidate.PSObject.Properties['sourceToken']) 'no_fake_A_receipts_or_original_claim'
        }

        # A independent negative: a caller-fabricated in-source-looking but
        # out-of-bounds data start cannot use the C helper to read source bytes.
        $bad=[pscustomobject]@{
            dataOffsetBytes=([long]$img.Length-17L);partitionOffsetBytes=$geo.partitionOffsetBytes
            partitionEndBytes=$geo.partitionEndBytes;bytesPerSector=$geo.bytesPerSector
            sectorsPerCluster=$geo.sectorsPerCluster;clusterSizeBytes=$geo.clusterSizeBytes
            clusterCount=$geo.clusterCount;fatCount=$geo.fatCount;fatSizeSectors=$geo.fatSizeSectors
        }
        $prior=$meter.TotalBytes
        $badTrial=Invoke-CStandardDataTrial -Stream $meter -Geometry $bad -EnableDataWindow
        Assert-A7Data ($badTrial.status -ceq 'unknown' -and $meter.TotalBytes -eq $prior) 'forged_data_start_no_physical_read'
        $smallTrial=Invoke-CStandardDataTrial -Stream $meter -Geometry $geo -EnableDataWindow -MaxSourceBytes 1024
        Assert-A7Data ($smallTrial.status -ceq 'unknown' -and $meter.TotalBytes -eq $prior) 'C_undersized_budget_no_read'

        $meter.BeginConsumer('fat')
        $fat=Get-ChappyFatObservedIoEvidence -Stream $meter -Mode MirrorAndChain -MaxReadBytes 2048
        Assert-A7Data ($fat.team -ceq 'D' -and $fat.experimentalDefaultOff -and
            -not $fat.writePermitted -and $fat.sourceDecision -ceq 'not_selected') 'D_no_FAT_winner'

        $events=@($meter.GetEvents())
        $physical=0L
        $unique=New-Object 'System.Collections.Generic.HashSet[long]'
        $bBytes=0L;$cBytes=0L;$dBytes=0L;$geoReads=0
        foreach($ev in $events){
            $at=[long]$ev.OffsetBytes;$n=[long]$ev.ReturnedBytes
            Assert-A7Data ($n -gt 0 -and $at -ge 0 -and $at -le $raw.Length-$n) 'real_returned_extents_in_bounds'
            $physical+=$n
            for($i=0L;$i -lt $n;$i++){[void]$unique.Add($at+$i)}
            switch($ev.Consumer){
                'geometry' {$geoReads++}
                'directory' {$bBytes+=$n}
                'carving' {$cBytes+=$n}
                'fat' {$dBytes+=$n}
                default {throw 'Unexpected A physical consumer'}
            }
        }
        Assert-A7Data ($physical -eq $meter.TotalBytes -and $unique.Count -eq $meter.UniqueBytes -and
            $meter.DuplicateBytes -eq ($physical-$unique.Count) -and
            $meter.ReadRequests -ge $events.Count -and $physical -le 120000L) 'A_independent_physical_union_and_global_quota'
        Assert-A7Data ($geoReads -gt 0 -and $bBytes -eq [long]$directory.metrics.bytesRead -and
            $cBytes -eq [long]$carving.metrics.sourceBytesRead -and
            $dBytes -eq [long]$fat.metrics.bytesRead -and $dBytes -le 2048L) 'B_C_D_actual_returned_bytes_reconcile'

        # Artificial scorer checks candidate bytes AFTER discovery. The clean
        # original SHA and true extent locations were never passed to B/C/D.
        $truth=@($fixture.oracle|Where-Object {$_.shortName -ceq 'MODEL   3MF'})[0]
        $localExact=0
        foreach($candidate in @($carving.items|Where-Object {$_.format -ceq '3mf'})){
            if($candidate.lengthBytes -eq $truth.lengthBytes -and
                $candidate.offsetBytes -eq $truth.extents[0].offsetBytes){
                [byte[]]$bytes=[byte[]]::new([int]$candidate.lengthBytes)
                [Array]::Copy($img,[int]$candidate.offsetBytes,$bytes,0,$bytes.Length)
                if((Get-A3DSha256 $bytes) -ceq $truth.sha256){$localExact++}
            }
        }
        $exactScorer+=$localExact

        # Exceed the remaining A source quota by exactly one byte. This MUST
        # throw, never become a fake 0-byte EOF or an A physical event.
        $used=$meter.TotalBytes;$eventCount=$events.Count
        [byte[]]$tooMuch=[byte[]]::new([int](120001L-$used))
        $denied=$false
        $meter.BeginConsumer('carving')
        try{[void]$meter.Read($tooMuch,0,$tooMuch.Length)}
        catch{
            $fault=$_.Exception
            for($depth=0;$depth -lt 5 -and $null -ne $fault;$depth++){
                if($fault.Message -match 'A7[.]shared_source_budget_exhausted'){$denied=$true;break}
                $fault=$fault.InnerException
            }
        }
        Assert-A7Data ($denied -and $meter.TotalBytes -eq $used -and
            @($meter.GetEvents()).Count -eq $eventCount) 'physical_quota_denied_without_fake_EOF_or_event'
        Assert-A7Data ((Get-A3DSha256 $img) -ceq $before) 'artificial_source_SHA_unchanged'
        $quotaRefusals++;$cases++;$found+=@($carving.items).Count
        $physicalTotal+=$physical;$uniqueTotal+=[long]$unique.Count
        Write-Host ('A7 DATA WINDOW spc={0} candidates={1} scorerExact3mf={2} physical={3} unique={4} Csource={5} Dsource={6} status=partial original=unknown' -f
            $spc,@($carving.items).Count,$localExact,$physical,$unique.Count,$cBytes,$dBytes)
    } finally {
        $raw.Dispose()
        $fixture=$null;$img=$null
        [GC]::Collect()
    }
}
Assert-A7Data ($cases -eq 2 -and $quotaRefusals -eq 2 -and $found -gt 0 -and
    $exactScorer -ge 1 -and $physicalTotal -ge $uniqueTotal) 'two_standard_artificial_volumes'
Write-Host ('PASS: A7 C data-window / B geometry and root / D FAT on shared source, cases={0}, C candidates={1}, external exact3MF={2}, returnedB={3}, uniquePerSourceB={4}, refusals={5}; R7 PARTIAL, originalIdentity=unknown' -f
    $cases,$found,$exactScorer,$physicalTotal,$uniqueTotal,$quotaRefusals)
