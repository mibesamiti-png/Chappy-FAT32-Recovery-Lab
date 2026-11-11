#requires -Version 5.1
# Team B R2 LFN adversarial checks: artificial 32-byte records only.
# Dot-sourced by tests/Test-DirectoryScanner.ps1 after fixture helpers are loaded.

$lfnShort = New-ShortB 'LFNQA   TXT' 0x20 50 12
$lfnHash = Get-ChappyBShortChecksum $lfnShort
$positions = @(1,3,5,7,9,14,16,18,20,22,24,28,30)
$longName = '日本語の長い名前🌟.gcode'
$cleanLfn = (New-LfnB $longName $lfnShort)
Assert-B ($cleanLfn.Count -ge 2 -and
    (Get-ChappyBLfnName -Segments $cleanLfn -Checksum $lfnHash) -eq $longName) 'LFN adversarial fixture valid multi-segment Unicode'

$mutatedOrder = (New-LfnB $longName $lfnShort)
$mutatedOrder[0][0] = [byte]($mutatedOrder[0][0] -bor 0x20)
Assert-B ($null -eq (Get-ChappyBLfnName -Segments $mutatedOrder -Checksum $lfnHash)) 'LFN reserved ordinal 0x20 rejected'

$mutatedInner = (New-LfnB $longName $lfnShort)
$mutatedInner[1][0] = [byte]($mutatedInner[1][0] -bor 0x20)
Assert-B ($null -eq (Get-ChappyBLfnName -Segments $mutatedInner -Checksum $lfnHash)) 'LFN reserved ordinal in nonterminal segment rejected'

$swapped = @($cleanLfn[1], $cleanLfn[0])
Assert-B ($null -eq (Get-ChappyBLfnName -Segments $swapped -Checksum $lfnHash)) 'LFN reversed ordinal sequence rejected'

$checksumBad = (New-LfnB $longName $lfnShort)
$checksumBad[0][13] = [byte](($checksumBad[0][13] + 1) -band 255)
Assert-B ($null -eq (Get-ChappyBLfnName -Segments $checksumBad -Checksum $lfnHash)) 'LFN corrupted short checksum rejected'

$shortName = 'TEST.txt'
$shortLfn = (New-LfnB $shortName $lfnShort)
Assert-B ($shortLfn.Count -eq 1 -and
    (Get-ChappyBLfnName -Segments $shortLfn -Checksum $lfnHash) -eq $shortName) 'LFN single-segment positive control'

$invalidNull = (New-LfnB $shortName $lfnShort)
Set-U16 $invalidNull[0] $positions[$shortName.Length] 65535
Assert-B ($null -eq (Get-ChappyBLfnName -Segments $invalidNull -Checksum $lfnHash)) 'LFN 0xFFFF is not a substitute for null terminator'

$invalidTail = (New-LfnB $shortName $lfnShort)
Set-U16 $invalidTail[0] $positions[($shortName.Length+1)] 0x0041
Assert-B ($null -eq (Get-ChappyBLfnName -Segments $invalidTail -Checksum $lfnHash)) 'LFN non-padding after terminator rejected'

$surrogateBad = (New-LfnB 'AB🌟.txt' $lfnShort)
Set-U16 $surrogateBad[0] $positions[2] 0xDC00
Assert-B ($null -eq (Get-ChappyBLfnName -Segments $surrogateBad -Checksum $lfnHash)) 'LFN unpaired UTF-16 surrogate rejected'

$withoutTerminator = (New-LfnB ('A'*12) $lfnShort)
Set-U16 $withoutTerminator[0] $positions[12] 0x0042
Assert-B ((Get-ChappyBLfnName -Segments $withoutTerminator -Checksum $lfnHash) -eq (('A'*12)+'B')) 'LFN exact 13-unit segment without terminator allowed'

$maxLfn = (New-LfnB ('Z'*255) $lfnShort)
$tooLongLfn = (New-LfnB ('Z'*256) $lfnShort)
Assert-B ((Get-ChappyBLfnName -Segments $maxLfn -Checksum $lfnHash).Length -eq 255 -and
    $null -eq (Get-ChappyBLfnName -Segments $tooLongLfn -Checksum $lfnHash)) 'LFN 255 UTF-16 units accepted; 256 rejected'

# Fixed-seed corruptions that are guaranteed invalid, without printing any name.
$rng = New-Object System.Random 20261111
$mutationAccepted = 0
for ($k=0; $k -lt 160; $k++) {
    $parts = (New-LfnB $longName $lfnShort)
    $n = $rng.Next(0, $parts.Count)
    switch ($k % 5) {
        0 { $parts[$n][0] = [byte]($parts[$n][0] -bor 0x20) }
        1 { $parts[$n][13] = [byte](($parts[$n][13] + 1) -band 255) }
        2 { $parts[$n][11] = 0x0E }
        3 { $parts[$n][12] = 1 }
        4 { $parts[$n][26] = 1 }
    }
    if ($null -ne (Get-ChappyBLfnName -Segments $parts -Checksum $lfnHash)) {
        $mutationAccepted++
    }
}
Assert-B ($mutationAccepted -eq 0) 'LFN 160 reproducible malformed mutations all rejected'

# Corruption may invalidate the long name while the short alias remains useful.
[byte[]]$badRecord = [byte[]]$invalidNull[0].Clone()
[byte[]]$fallbackBuffer = New-Object byte[] 1024
[Array]::Copy($badRecord, 0, $fallbackBuffer, 0, 32)
[Array]::Copy($lfnShort, 0, $fallbackBuffer, 32, 32)
$fallback = Read-ChappyBDirectoryCluster -Buffer $fallbackBuffer -Cluster 2 -OffsetBytes 0 -MaxCluster 1000 -IsRoot $true -IncludeNames
Assert-B ($fallback.accepted -and $fallback.entries.Count -eq 1 -and
    $fallback.entries[0].name -eq 'LFNQA.TXT' -and
    $fallback.entries[0].confidence -eq 'partial' -and
    $fallback.entries[0].evidence -contains 'lfn_rejected_short_fallback') 'Malformed LFN falls back to partial short-name candidate'

# Without trusted FAT links, fragments on adjacent clusters cannot be spliced.
[byte[]]$leftCluster = New-Object byte[] 1024
for ($i=0; $i -lt $leftCluster.Length; $i++) { $leftCluster[$i] = 0xE5 }
[Array]::Copy($shortLfn[0], 0, $leftCluster, 992, 32)
[byte[]]$rightCluster = New-Object byte[] 1024
[Array]::Copy($lfnShort, 0, $rightCluster, 0, 32)
$leftParsed = Read-ChappyBDirectoryCluster -Buffer $leftCluster -Cluster 40 -OffsetBytes 0 -MaxCluster 1000 -IsRoot $false -IncludeNames
$rightParsed = Read-ChappyBDirectoryCluster -Buffer $rightCluster -Cluster 41 -OffsetBytes 1024 -MaxCluster 1000 -IsRoot $true -IncludeNames
Assert-B ($leftParsed.entries.Count -eq 0 -and $rightParsed.entries.Count -eq 1 -and
    $rightParsed.entries[0].nameSource -eq 'short_8_3') 'Truncated LFN at cluster boundary never joins adjacent cluster'

# R1-style *acceptance-predicate model* vs actual R2 scanner, same known
# synthetic ground truth. This is NOT a second execution of historical R1 code.
function New-SyntheticBenchmarkBufferB {
    param([System.Collections.IList]$Records, [bool]$NoEndMarker)
    [byte[]]$b = New-Object byte[] 1024
    if ($NoEndMarker) {
        for ($i=0; $i -lt $b.Length; $i++) { $b[$i] = 0xE5 }
    }
    $index = 0
    foreach ($entry in $Records) {
        if ($index -gt 992) { throw 'Synthetic benchmark entry limit' }
        [byte[]]$record = [byte[]]$entry
        if ($record.Length -ne 32) { throw 'Synthetic benchmark entry size invalid' }
        [Array]::Copy($record, 0, $b, $index, 32)
        $index += 32
    }
    return ,$b
}
function Add-SyntheticBenchmarkB {
    param([System.Collections.ArrayList]$Records, [bool]$Truth, [bool]$IsRoot, [bool]$NoEndMarker)
    $buffer = New-SyntheticBenchmarkBufferB -Records $Records -NoEndMarker $NoEndMarker
    [void]$bench.Add([pscustomobject]@{
        buffer = $buffer
        expectedDirectory = $Truth
        isRoot = $IsRoot
    })
}
function New-BRecords { return ,(New-Object System.Collections.ArrayList) }

$bench = New-Object System.Collections.ArrayList
$one = New-ShortB 'ONE     TXT' 0x20 90 9
$two = New-ShortB 'TWO     TXT' 0x20 91 10
$dot = New-ShortB '.          ' 0x10 60 0
$dotdot = New-ShortB '..         ' 0x10 2 0

$records = New-BRecords; [void]$records.Add($one)
Add-SyntheticBenchmarkB -Records $records -Truth $true -IsRoot $true -NoEndMarker $false
$records = New-BRecords; [void]$records.Add($dot); [void]$records.Add($dotdot); [void]$records.Add($one)
Add-SyntheticBenchmarkB -Records $records -Truth $true -IsRoot $false -NoEndMarker $false
$records = New-BRecords; [void]$records.Add($one); [void]$records.Add($two)
Add-SyntheticBenchmarkB -Records $records -Truth $true -IsRoot $false -NoEndMarker $false
$records = New-BRecords; [void]$records.Add($dot); [void]$records.Add($dotdot)
Add-SyntheticBenchmarkB -Records $records -Truth $true -IsRoot $false -NoEndMarker $false
$records = New-BRecords; [void]$records.Add($one)
Add-SyntheticBenchmarkB -Records $records -Truth $false -IsRoot $false -NoEndMarker $false
$records = New-BRecords; foreach($piece in $shortLfn){[void]$records.Add($piece)}; [void]$records.Add($lfnShort)
Add-SyntheticBenchmarkB -Records $records -Truth $false -IsRoot $false -NoEndMarker $false
$records = New-BRecords; [void]$records.Add($dot); [void]$records.Add($one)
Add-SyntheticBenchmarkB -Records $records -Truth $false -IsRoot $false -NoEndMarker $false
$records = New-BRecords; [void]$records.Add($dot)
$wrongDot = New-ShortB '..         ' 0x10 99999 0
[void]$records.Add($wrongDot); [void]$records.Add($one)
Add-SyntheticBenchmarkB -Records $records -Truth $false -IsRoot $false -NoEndMarker $false
$records = New-BRecords; [void]$records.Add($one); [void]$records.Add($two)
Add-SyntheticBenchmarkB -Records $records -Truth $false -IsRoot $false -NoEndMarker $true
$records = New-BRecords
Add-SyntheticBenchmarkB -Records $records -Truth $false -IsRoot $false -NoEndMarker $false

$r1TP = 0; $r1FP = 0; $r1FN = 0; $r2TP = 0; $r2FP = 0; $r2FN = 0
foreach ($fixture in $bench) {
    $parsed = Read-ChappyBDirectoryCluster -Buffer $fixture.buffer -Cluster 60 -OffsetBytes 0 -MaxCluster 1000 -IsRoot $fixture.isRoot
    $lfnPresent = @($parsed.entries | Where-Object {$_.nameSource -eq 'lfn_validated'}).Count -gt 0
    # Equivalent to R1's directory-acceptance OR predicate for these aligned fixtures.
    $modeledR1 = ($parsed.validCount -ge 2 -or $parsed.hasDotHeader -or
                  ($fixture.isRoot -and $parsed.validCount -ge 1) -or $lfnPresent)
    $currentR2 = [bool]$parsed.accepted
    if ($fixture.expectedDirectory) {
        if ($modeledR1) { $r1TP++ } else { $r1FN++ }
        if ($currentR2) { $r2TP++ } else { $r2FN++ }
    } else {
        if ($modeledR1) { $r1FP++ }
        if ($currentR2) { $r2FP++ }
    }
}
Assert-B ($bench.Count -eq 10 -and $r1TP -eq 4 -and $r1FP -eq 4 -and $r1FN -eq 0 -and
    $r2TP -eq 4 -and $r2FP -eq 0 -and $r2FN -eq 0) 'Fixed synthetic R1-style policy versus R2: TP=4 each, FP=4 versus 0'
Write-Host ("SYNTHETIC AB MODEL ONLY: fixtures={0}; R1-style TP={1} FP={2} FN={3}; R2 TP={4} FP={5} FN={6}" -f $bench.Count,$r1TP,$r1FP,$r1FN,$r2TP,$r2FP,$r2FN)
