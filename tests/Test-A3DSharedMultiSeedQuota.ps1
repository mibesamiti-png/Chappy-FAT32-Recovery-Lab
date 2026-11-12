#Requires -Version 5.1
# A R7 synthetic ONLY: B/C/D share ONE outer physical source meter per run.
# No path/device inputs, source writes, file output, or original IMG access.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
# Also reruns previously accepted A shared-meter negatives as independent guard.
. (Join-Path $PSScriptRoot 'Test-A3DSharedReadProvenance.ps1')

function Assert-A7Seed([bool]$Okay,[string]$Why) {
    if(-not $Okay){throw ('A7_MULTI_SEED_FAIL: '+$Why)}
}
$seeds=@(202611,202612,202613)
$cases=@('M00','M01','M02','P02')
$tested=0;$sourceBytes=0L;$uniqueBytes=0L;$duplicateBytes=0L
$requests=0L;$budgetRejects=0;$structureClaims=0
foreach($seed in $seeds){
    foreach($case in $cases){
        $fixture=New-ChappyA3DDamagedFixture -Seed $seed -Case $case
        [byte[]]$bytes=$fixture.image
        $sha=Get-A3DSha256 $bytes
        Assert-A7Seed ($sha -ceq $fixture.manifest.imageSha256) 'independent_generated_source_hash'
        $memory=[IO.MemoryStream]::new($bytes,$false)
        $meter=[ChappyA7SharedSource]::new($memory,120000L)
        try{
            Assert-A7Seed ($meter.CanRead -and $meter.CanSeek -and -not $meter.CanWrite) 'outer_nonwritable_source'

            $meter.BeginConsumer('geometry')
            $geo=Get-ChappyFat32Geometry -Stream $meter
            Assert-A7Seed ($geo.fatCount -eq 2) 'generated_geometry'

            $meter.BeginConsumer('directory')
            $dir=Get-ChappyDirectoryCandidates -Stream $meter -Geometry $geo -MaxScanBytes 512 -MaxCandidates 16 -MaxDirectories 4 -RecordDirectoryReadSpans -MaxDirectoryReadSpans 8
            Assert-A7Seed ($dir.team -ceq 'B' -and $dir.metrics.bytesRead -eq 512) 'actual_B_read'
            $meter.BeginConsumer('carving')
            $carve=Get-ChappyCarvingCandidates -Stream $meter -MaxScanBytes 65536 -ExtraValidationReadBytes 32768 -MaxFileBytes 4096 -MaxCandidates 16 -MaxProbes 16 -MaxProbeBytes 8192
            Assert-A7Seed ($carve.team -ceq 'C' -and $carve.status -ne 'error') 'actual_C_readonly_scanner'
            $meter.BeginConsumer('fat')
            $fat=Get-ChappyFatObservedIoEvidence -Stream $meter -Mode MirrorAndChain -MaxReadBytes 2048
            Assert-A7Seed ($fat.team -ceq 'D' -and $fat.experimentalDefaultOff -and
                -not $fat.writePermitted -and $fat.sourceDecision -ceq 'not_selected') 'actual_D_no_FAT_winner'
            $events=@($meter.GetEvents())
            $names=@('geometry','directory','carving','fat')
            foreach($name in $names) {
                Assert-A7Seed (@($events | Where-Object {$_.Consumer -ceq $name}).Count -gt 0) ('actual_source_reads_'+$name)
            }

            # Independently reconstruct an exact byte-coordinate union from
            # OUTER Stream.Read return events, not from module-reported counters.
            $observed=New-Object 'System.Collections.Generic.HashSet[long]'
            $actual=0L
            foreach($event in $events) {
                $offset=[long]$event.OffsetBytes
                $length=[long]$event.ReturnedBytes
                Assert-A7Seed ($offset -ge 0 -and $length -gt 0 -and
                    $offset -le $memory.Length-$length) 'source_event_inside_input'
                $actual+=$length
                for($i=0L;$i -lt $length;$i++) {
                    [void]$observed.Add($offset+$i)
                }
            }
            $distinct=[long]$observed.Count
            Assert-A7Seed ($actual -eq $meter.TotalBytes -and
                $distinct -eq $meter.UniqueBytes -and
                ($actual-$distinct) -eq $meter.DuplicateBytes -and
                $meter.ReadRequests -ge $events.Count -and
                $actual -gt 0 -and $actual -le 120000L) 'global_meter_matches_independent_union'
            $dirSeen=@($events|Where-Object {$_.Consumer -ceq 'directory'})
            Assert-A7Seed ($dirSeen.Count -eq 1 -and
                $dirSeen[0].OffsetBytes -eq [long]$dir.directoryReadEvidence.spans[0].offsetBytes -and
                $dirSeen[0].ReturnedBytes -eq [long]$dir.directoryReadEvidence.spans[0].lengthBytes) 'B_directory_span_matches_actual'
            $fatSeen=@($events|Where-Object {$_.Consumer -ceq 'fat'})
            $fatActual=0L
            foreach($ev in $fatSeen){$fatActual += [long]$ev.ReturnedBytes}
            Assert-A7Seed ($fatActual -eq [long]$fat.metrics.bytesRead) 'D_reported_bytes_reconcile_outer_source'
            $plausible=@($carve.items|Where-Object {$_.format -ceq '3mf' -and $_.confidence -ceq 'verified'})
            foreach($item in $plausible) {
                Assert-A7Seed ($item.integrityScope -ceq 'structural_only_not_original_file_integrity') 'C_verified_is_only_structural'
            }
            $structureClaims += $plausible.Count
            Assert-A7Seed ((Get-A3DSha256 $bytes) -ceq $sha) 'original_synthetic_input_unmodified'

            # A deliberately tries to exceed the PHYSICAL source byte cap
            # *after* B, C and D have used the same meter. This must throw,
            # never pretend to be EOF, and MUST leave every physical counter
            # and all received events unchanged.
            $atCap=$meter.TotalBytes
            $beforeEvents=$events.Count
            $meter.BeginConsumer('carving')
            [byte[]]$over=[byte[]]::new([int](120001L-$atCap))
            $blocked=$false
            try{[void]$meter.Read($over,0,$over.Length)}
            catch{
                $inner=$_.Exception
                for($j=0;$j -lt 5 -and $null -ne $inner;$j++){
                    if($inner.Message -match 'A7[.]shared_source_budget_exhausted'){$blocked=$true;break}
                    $inner=$inner.InnerException
                }
            }
            Assert-A7Seed ($blocked -and $meter.TotalBytes -eq $atCap -and
                @($meter.GetEvents()).Count -eq $beforeEvents) 'global_BCD_quota_refuses_extra_read_without_false_EOF'
            Assert-A7Seed ((Get-A3DSha256 $bytes) -ceq $sha) 'global_quota_does_not_mutate_source'

            $sourceBytes+=$actual
            $uniqueBytes+=$distinct
            $duplicateBytes+=($actual-$distinct)
            $requests+=$meter.ReadRequests
            $budgetRejects++
            $tested++
            Write-Host ('A7 MULTISEED seed={0} case={1} actual={2} unique={3} duplicate={4} events={5} limit=120000 unknownOriginal=TRUE' -f
                $seed,$case,$actual,$distinct,($actual-$distinct),$events.Count)
        }finally{$memory.Dispose()}
    }
}
Assert-A7Seed ($tested -eq $seeds.Count*$cases.Count -and
    $budgetRejects -eq $tested -and
    $sourceBytes -eq $uniqueBytes+$duplicateBytes -and
    $structureClaims -ge 1) 'fixed_multiseed_corpus_and_independent_accounting'
Write-Host ('A7 MULTISEED SUMMARY cases={0}, sourceActual={1}, uniquePerCaseSum={2}, repeatPerCaseSum={3}, requests={4}, rejectedQuotaOvershoots={5}, structuralClaims={6}; NOT original recovery' -f
    $tested,$sourceBytes,$uniqueBytes,$duplicateBytes,$requests,$budgetRejects,$structureClaims)
Write-Host 'PASS: A R7 3-seed/4-case shared B/C/D physical read quota and source-origin union; no real media.'
