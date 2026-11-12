#Requires -Version 5.1
# Team A R7: B/C/D real parser calls on generated standards-shaped FAT32,
# with ONE source-wide physical read meter per disposable synthetic image.
# No source path, disk/device access, file output, or production adoption.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
# Load the already-reviewed A physical meter; this also reruns its bounded
# synthetic negative regression in the same isolated child process.
. (Join-Path $PSScriptRoot 'Test-A3DSharedReadProvenance.ps1')
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')

function Assert-A7Standard([bool]$Okay,[string]$Why) {
    if(-not $Okay) {throw ('A7_STANDARD_SHARED_FAIL: '+$Why)}
}
$plans=@(
    [pscustomobject]@{seed=202611;spc=1;fault='clean'},
    [pscustomobject]@{seed=202611;spc=2;fault='clean'},
    [pscustomobject]@{seed=202612;spc=1;fault='clean'},
    [pscustomobject]@{seed=202612;spc=2;fault='clean'},
    [pscustomobject]@{seed=202613;spc=1;fault='fat2_link4'}
)
$cases=0;$bytesActual=0L;$bytesUnique=0L;$bytesRepeated=0L;$physicalRequests=0L;$quotaRefusals=0
$cCandidates=0;$unknownOriginal=0
foreach($plan in $plans) {
    $fixture=New-ChappyA3DStandardFixture -Seed $plan.seed -SectorsPerCluster $plan.spc -Fragment3Mf:($plan.spc -eq 1)
    [byte[]]$img=$fixture.image
    Assert-A7Standard ($img.Length -ge 30MB -and $img.Length -le 80MB -and
        @($fixture.oracle).Count -eq 3) 'standards_shaped_30_to_80_MiB_only'
    $fatSectors=[int][Math]::Ceiling(4 * (65541 + 2) / 512.0)
    $fat2=(1+32+$fatSectors)*512
    if($plan.fault -ceq 'fat2_link4') {
        # Artificial-only FAT2 chain byte corruption, no original file writes.
        [byte[]]$copy=[byte[]]$img.Clone()
        $beforeCopy=Get-A3DSha256 $img
        $copy[$fat2+16]=[byte]($copy[$fat2+16] -bxor 1)
        Assert-A7Standard ((Get-A3DSha256 $copy) -cne $beforeCopy) 'synthetic_FAT2_mutation_changes_hash'
        $img=$copy
        $copy=$null
    }
    $before=Get-A3DSha256 $img
    $raw=[IO.MemoryStream]::new($img,$false)
    $meter=[ChappyA7SharedSource]::new($raw,120000L)
    try {
        Assert-A7Standard ($raw.CanRead -and $raw.CanSeek -and -not $raw.CanWrite -and
            -not $meter.CanWrite -and $meter.MaximumBytes -eq 120000L) 'strictly_nonwritable_stream'

        $meter.BeginConsumer('geometry')
        $geo=Get-ChappyFat32Geometry -Stream $meter
        Assert-A7Standard ($geo.fatCount -eq 2 -and
            $geo.bytesPerSector -eq 512 -and
            $geo.sectorsPerCluster -eq $plan.spc -and
            $geo.clusterCount -eq 65541 -and
            $geo.rootCluster -eq 2 -and
            $geo.dataOffsetBytes -gt 65536L -and
            $geo.partitionEndBytes -eq [long]$img.Length) 'A_B_geometry_true_FAT32_cluster_threshold'

        $meter.BeginConsumer('directory')
        $directory=Get-ChappyDirectoryCandidates -Stream $meter -Geometry $geo -MaxScanBytes (512*$plan.spc) -MaxCandidates 16 -MaxDirectories 4 -RecordDirectoryReadSpans -MaxDirectoryReadSpans 8
        Assert-A7Standard ($directory.team -ceq 'B' -and
            $directory.directoryReadEvidence.status -ceq 'recorded' -and
            $directory.metrics.bytesRead -eq $geo.clusterSizeBytes) 'B_read_standards_shaped_root'

        # C currently scans a bounded IMAGE-prefix search window, not an
        # independently FAT-aware data-region scan. Keep this limitation visible:
        # C may return zero candidates even when the external oracle has files.
        $meter.BeginConsumer('carving')
        $carving=Get-ChappyCarvingCandidates -Stream $meter -MaxScanBytes 65536 -ExtraValidationReadBytes 32768 -MaxFileBytes 4096 -MaxCandidates 16 -MaxProbes 16 -MaxProbeBytes 8192
        Assert-A7Standard ($carving.team -ceq 'C' -and $carving.status -ne 'error') 'C_bounded_scan_never_extrapolates_to_unread_data'
        foreach($candidate in @($carving.items)) {
            Assert-A7Standard ($candidate.integrityScope -cne 'original_file_integrity') 'C_never_promotes_original_identity'
        }
        $cCandidates += @($carving.items).Count

        $meter.BeginConsumer('fat')
        $fat=Get-ChappyFatObservedIoEvidence -Stream $meter -Mode MirrorAndChain -MaxReadBytes 2048
        Assert-A7Standard ($fat.team -ceq 'D' -and $fat.experimentalDefaultOff -eq $true -and
            -not $fat.writePermitted -and $fat.sourceDecision -ceq 'not_selected') 'D_no_FAT_winner_or_repair'

        $events=@($meter.GetEvents())
        $union=New-Object 'System.Collections.Generic.HashSet[long]'
        $physical=0L
        foreach($evt in $events) {
            $at=[long]$evt.OffsetBytes;$len=[long]$evt.ReturnedBytes
            Assert-A7Standard ($at -ge 0 -and $len -gt 0 -and
                $at -le $raw.Length-$len) 'A_source_meter_event_in_bounds'
            $physical += $len
            for($i=0L;$i -lt $len;$i++) { [void]$union.Add($at+$i) }
        }
        $unique=[long]$union.Count
        Assert-A7Standard ($physical -eq $meter.TotalBytes -and
            $unique -eq $meter.UniqueBytes -and
            $meter.DuplicateBytes -eq $physical-$unique -and
            $meter.ReadRequests -ge $events.Count -and
            $physical -gt 0 -and $physical -le 120000L) 'A_independent_global_physical_union'

        $bRead=@($events|Where-Object {$_.Consumer -ceq 'directory'})
        $bSpan=$directory.directoryReadEvidence.spans[0]
        Assert-A7Standard ($bRead.Count -eq 1 -and
            $bRead[0].OffsetBytes -eq [long]$bSpan.offsetBytes -and
            $bRead[0].ReturnedBytes -eq [long]$bSpan.lengthBytes) 'B_observed_root_bytes_equal_outer_meter'
        $dRead=@($events|Where-Object {$_.Consumer -ceq 'fat'})
        $dReturned=0L
        foreach($evt in $dRead) {$dReturned += [long]$evt.ReturnedBytes}
        Assert-A7Standard ($dRead.Count -gt 0 -and
            $dReturned -eq [long]$fat.metrics.bytesRead -and
            $dReturned -le 2048L) 'D_sampled_FAT_returns_match_outer_meter'

        # The artificial oracle is consulted only by this independent scorer,
        # never supplied to B/C/D. No need to copy or export any source file.
        $matches=0
        foreach($file in @($fixture.oracle)) {
            [byte[]]$content=[byte[]]::new([int]$file.lengthBytes)
            $written=0
            foreach($extent in @($file.extents)) {
                [Array]::Copy($img,[int]$extent.offsetBytes,$content,$written,[int]$extent.lengthBytes)
                $written += [int]$extent.lengthBytes
            }
            if($written -eq $content.Length -and (Get-A3DSha256 $content) -ceq $file.sha256) {$matches++}
        }
        Assert-A7Standard ($matches -eq 3 -and
            (Get-A3DSha256 $img) -ceq $before) 'synthetic_oracle_3_of_3_independent_of_modules'
        $unknownOriginal+=3

        # Deliberately consume more than the remaining *global* source quota,
        # after all four module phases; no returned bytes, read events or fake EOF.
        $totalBefore=$meter.TotalBytes;$eventsBefore=$events.Count
        $meter.BeginConsumer('carving')
        [byte[]]$excess=[byte[]]::new([int](120001L-$totalBefore))
        $rejected=$false
        try{[void]$meter.Read($excess,0,$excess.Length)}
        catch{
            $exception=$_.Exception
            for($d=0;$d -lt 5 -and $null -ne $exception;$d++) {
                if($exception.Message -match 'A7[.]shared_source_budget_exhausted') {$rejected=$true;break}
                $exception=$exception.InnerException
            }
        }
        Assert-A7Standard ($rejected -and $meter.TotalBytes -eq $totalBefore -and
            @($meter.GetEvents()).Count -eq $eventsBefore -and
            (Get-A3DSha256 $img) -ceq $before) 'global_quota_failure_no_source_read_or_mutation'
        $quotaRefusals++
        $bytesActual+=$physical;$bytesUnique+=$unique
        $bytesRepeated+=($physical-$unique)
        $physicalRequests+=$meter.ReadRequests;$cases++
        Write-Host ('A7 STANDARD seed={0} spc={1} fault={2} imageMiB={3:N1} actual={4} unique={5} repeated={6} C_candidates={7} scorer_sha=3_of_3 original_claim=unknown' -f
            $plan.seed,$plan.spc,$plan.fault,($img.Length/1MB),$physical,$unique,($physical-$unique),@($carving.items).Count)
    } finally {
        $raw.Dispose()
        $meter=$null;$fixture=$null;$img=$null
        [GC]::Collect()
    }
}
Assert-A7Standard ($cases -eq 5 -and $quotaRefusals -eq 5 -and
    $bytesActual -eq ($bytesUnique+$bytesRepeated) -and
    $unknownOriginal -eq 15) 'predeclared_standards_shaped_suite'
Write-Host ('A7 STANDARD SUMMARY cases={0} actual={1} unique_per_source_sum={2} duplicates={3} read_requests={4} quota_rejections={5} scorer_sha_exact={6} C_observed_candidates={7}' -f
    $cases,$bytesActual,$bytesUnique,$bytesRepeated,$physicalRequests,$quotaRefusals,$unknownOriginal,$cCandidates)
Write-Host 'PASS: A R7 larger standards-shaped 5-case shared B/C/D physical source meter; no real images or original identity claims.'
