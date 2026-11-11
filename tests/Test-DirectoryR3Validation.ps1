#requires -Version 5.1
# Team B R3: artificial records and synthetic local IMG only. Imported by
# tests/Test-DirectoryScanner.ps1 after helpers and $read/$geo are available.
# Labels, metrics and reason codes contain no actual user data.

function Add-ChappyR3SyntheticCase {
    param([string]$CaseId, [bool]$Truth, [System.Collections.IList]$Records,
          [bool]$Root=$false, [bool]$Deleted=$false, [bool]$NoEnd=$false,
          [long]$MaxCluster=1000)
    [byte[]]$buf = New-Object byte[] 1024
    if ($NoEnd) {
        for ($q=0; $q -lt $buf.Length; $q++) { $buf[$q]=0xE5 }
    }
    $at=0
    foreach ($record in $Records) {
        [byte[]]$e = [byte[]]$record
        if ($e.Length -ne 32 -or $at -gt 992) { throw 'Synthetic record exceeds fixed 1KiB cluster' }
        [Array]::Copy($e,0,$buf,$at,32)
        $at+=32
    }
    [void]$r3Cases.Add([pscustomobject]@{
        id=$CaseId; truth=$Truth; root=$Root; deleted=$Deleted
        maxCluster=$MaxCluster; buffer=$buf
    })
}
function New-ChappyR3Records {
    return ,(New-Object System.Collections.ArrayList)
}

$r3Cases = New-Object System.Collections.ArrayList
$one = New-ShortB 'ONE     TXT' 0x20 90 12
$two = New-ShortB 'TWO     TXT' 0x20 91 17
$dot = New-ShortB '.          ' 0x10 60 0
$dotdot = New-ShortB '..         ' 0x10 2 0
$directory = New-ShortB 'SUBDIR     ' 0x10 77 0
$lfnShort = New-ShortB 'LFNQA   TXT' 0x20 70 18

$rec=New-ChappyR3Records; [void]$rec.Add($one)
Add-ChappyR3SyntheticCase 'root_one' $true $rec -Root $true
$rec=New-ChappyR3Records; foreach ($x in (New-LfnB 'Synthetic Japanese 日本語🌟.txt' $lfnShort)) {[void]$rec.Add($x)};[void]$rec.Add($lfnShort)
Add-ChappyR3SyntheticCase 'root_unicode_lfn' $true $rec -Root $true
$rec=New-ChappyR3Records; [void]$rec.Add($dot);[void]$rec.Add($dotdot);[void]$rec.Add($one)
Add-ChappyR3SyntheticCase 'paired_one' $true $rec
$rec=New-ChappyR3Records; [void]$rec.Add($dot);[void]$rec.Add($dotdot)
Add-ChappyR3SyntheticCase 'paired_empty' $true $rec
$rec=New-ChappyR3Records; [void]$rec.Add($one);[void]$rec.Add($two)
Add-ChappyR3SyntheticCase 'orphan_two_end' $true $rec
$rec=New-ChappyR3Records; [void]$rec.Add($directory);[void]$rec.Add($one)
Add-ChappyR3SyntheticCase 'orphan_subdir_file' $true $rec
$rec=New-ChappyR3Records;[void]$rec.Add($dot);[void]$rec.Add($dotdot)
Add-ChappyR3SyntheticCase 'paired_no_end' $true $rec -NoEnd $true
$rec=New-ChappyR3Records; [void]$rec.Add((New-ShortB 'HIADDR  BIN' 0x20 70000 16));[void]$rec.Add($one)
Add-ChappyR3SyntheticCase 'high_cluster_number' $true $rec -MaxCluster 80000
$rec=New-ChappyR3Records; [byte[]]$deletedA=(New-ShortB 'DELETED TXT' 0x20 90 3);$deletedA[0]=0xE5
[void]$rec.Add($deletedA);[void]$rec.Add($one)
Add-ChappyR3SyntheticCase 'deleted_opt_in' $true $rec -Deleted $true
$rec=New-ChappyR3Records; [void]$rec.Add($one);[void]$rec.Add($lfnShort)
Add-ChappyR3SyntheticCase 'short_pair' $true $rec

$rec=New-ChappyR3Records
Add-ChappyR3SyntheticCase 'all_zeros' $false $rec
$rec=New-ChappyR3Records;[void]$rec.Add($one)
Add-ChappyR3SyntheticCase 'single_noise_entry' $false $rec
$rec=New-ChappyR3Records;foreach ($x in (New-LfnB 'SyntheticName.txt' $lfnShort)) {[void]$rec.Add($x)};[void]$rec.Add($lfnShort)
Add-ChappyR3SyntheticCase 'single_lfn_noise' $false $rec
$rec=New-ChappyR3Records;[void]$rec.Add($dot);[void]$rec.Add((New-ShortB '..         ' 0x10 99999 0));[void]$rec.Add($one)
Add-ChappyR3SyntheticCase 'bad_dotdot' $false $rec
$rec=New-ChappyR3Records;[void]$rec.Add($dot)
Add-ChappyR3SyntheticCase 'dot_only' $false $rec
$rec=New-ChappyR3Records;[void]$rec.Add($dotdot);[void]$rec.Add($dot)
Add-ChappyR3SyntheticCase 'reversed_dot_pair' $false $rec
$rec=New-ChappyR3Records;[void]$rec.Add($one);[void]$rec.Add($two)
Add-ChappyR3SyntheticCase 'two_fake_records_no_end' $false $rec -NoEnd $true
$rec=New-ChappyR3Records;[void]$rec.Add($deletedA)
Add-ChappyR3SyntheticCase 'deleted_not_opted_in' $false $rec
$rec=New-ChappyR3Records;foreach ($x in (New-LfnB 'OnlyLFN.txt' $lfnShort)) {[void]$rec.Add($x)}
Add-ChappyR3SyntheticCase 'lfn_without_short_entry' $false $rec
$rec=New-ChappyR3Records;[void]$rec.Add((New-ShortB 'VOLUME     ' 0x08 0 0))
Add-ChappyR3SyntheticCase 'volume_label_not_file' $false $rec
$rec=New-ChappyR3Records;[void]$rec.Add((New-ShortB 'BADDIR     ' 0x10 0 0))
Add-ChappyR3SyntheticCase 'zero_directory_cluster' $false $rec
$rec=New-ChappyR3Records;[void]$rec.Add((New-ShortB 'BADDIR     ' 0x10 64 32))
Add-ChappyR3SyntheticCase 'directory_has_file_size' $false $rec
$rec=New-ChappyR3Records;[void]$rec.Add($dot);[void]$rec.Add((New-ShortB '..         ' 0x10 2 1))
Add-ChappyR3SyntheticCase 'dotdot_nonzero_size' $false $rec

$tp=0;$fp=0;$fn=0;$tn=0
$reasons = @{}
$seenIds = @{}
foreach ($case in $r3Cases) {
    if ($seenIds.ContainsKey($case.id)) { throw 'Duplicate artificial case ID' }
    $seenIds[$case.id] = $true
    $result = Read-ChappyBDirectoryCluster -Buffer $case.buffer -Cluster 60 -OffsetBytes 0 -MaxCluster $case.maxCluster -IsRoot $case.root -IncludeDeleted:$case.deleted
    if ($null -eq $result -or $null -eq $result.decisionReason) { throw 'Missing container classification' }
    if ($result.decisionReason -notin @('root_valid_entry','ordered_dot_pair','multiple_entries_with_end_marker',
        'insufficient_directory_evidence','unpaired_or_malformed_dot_header','isolated_lfn_without_directory_header')) {
        throw 'Unexpected free-text reason from synthetic container'
    }
    $reasons[$result.decisionReason] = 1 + [int]$reasons[$result.decisionReason]
    if (@($result.entries|Where-Object {$null -ne $_.name -or $null -ne $_.shortName}).Count -ne 0) {
        throw 'Default name redaction regression'
    }
    if ($case.truth -and $result.accepted) { $tp++ }
    elseif ($case.truth) { $fn++ }
    elseif ($result.accepted) { $fp++ }
    else { $tn++ }
}
Assert-B ($r3Cases.Count -eq 23 -and $tp -eq 10 -and $tn -eq 13 -and $fp -eq 0 -and $fn -eq 0) 'R3 fixed synthetic confidence matrix TP10 TN13 FP0 FN0'
Assert-B (($reasons['root_valid_entry'] -ge 1) -and ($reasons['ordered_dot_pair'] -ge 1) -and
    ($reasons['isolated_lfn_without_directory_header'] -ge 1) -and
    ($reasons['unpaired_or_malformed_dot_header'] -ge 1)) 'R3 fixed-code acceptance/rejection evidence frequencies'
Assert-B ($seenIds.Count -eq $r3Cases.Count) 'R3 synthetic case IDs unique and finite'
Write-Host ("SYNTHETIC R3 CALIBRATION ONLY: cases={0} TP={1} TN={2} FP={3} FN={4}; artificial precision/recall={5}/{6}" -f
    $r3Cases.Count,$tp,$tn,$fp,$fn, $(if($tp+$fp -gt 0){[Math]::Round($tp/($tp+$fp),3)}else{'n/a'}),
    $(if($tp+$fn -gt 0){[Math]::Round($tp/($tp+$fn),3)}else{'n/a'}))
foreach ($key in @($reasons.Keys | Sort-Object)) {
    Write-Host ("SYNTHETIC REASON CODE: {0}={1}" -f $key,$reasons[$key])
}

# Source read-only checks exercise the actual scanner, not just the parser.
Assert-B ($read.CanRead -and $read.CanSeek -and -not $read.CanWrite) 'R3 artificial IMG source stream has no write capability'
$pos=$read.Position
$zeroScan=Get-ChappyDirectoryCandidates -Stream $read -Geometry $geo -MaxScanBytes 0
Assert-B ($zeroScan.scanIncomplete -and $zeroScan.metrics.bytesRead -eq 0 -and
    $zeroScan.items.Count -eq 0 -and $read.Position -eq $pos) 'R3 zero-byte scan budget does not read source'
$smallScan=Get-ChappyDirectoryCandidates -Stream $read -Geometry $geo -MaxScanBytes 3072
Assert-B ($smallScan.scanIncomplete -and $smallScan.metrics.bytesRead -eq 3072 -and
    $smallScan.metrics.candidateCount -le 10000) 'R3 partial scan obeys exact three-cluster read budget'
$oneItem=Get-ChappyDirectoryCandidates -Stream $read -Geometry $geo -MaxScanBytes 8192 -MaxCandidates 1
Assert-B ($oneItem.scanIncomplete -and $oneItem.items.Count -eq 1 -and
    $oneItem.metrics.bytesRead -le 8192) 'R3 MaxCandidates hard stop'
$oneDir=Get-ChappyDirectoryCandidates -Stream $read -Geometry $geo -MaxScanBytes 8192 -MaxDirectories 1
Assert-B ($oneDir.scanIncomplete -and $oneDir.metrics.directoriesAccepted -eq 1 -and
    $oneDir.metrics.bytesRead -le 8192) 'R3 MaxDirectories hard stop'
$redact=Get-ChappyDirectoryCandidates -Stream $read -Geometry $geo -MaxScanBytes 1024
Assert-B (@($redact.items|Where-Object {$null -ne $_.name -or $null -ne $_.shortName}).Count -eq 0) 'R3 scanner default redacts all names'
$budgetReject=Get-ChappyDirectoryCandidates -Stream $read -Geometry $geo -MaxScanBytes -1
Assert-B ($budgetReject.status -eq 'error' -and $budgetReject.scanIncomplete) 'R3 rejects negative scan budget'
$invalidGeo=[pscustomobject]@{
    clusterSizeBytes = 1024L
    dataOffsetBytes = ($read.Length - 1024L)
    maxCluster = 100L
    rootCluster = 2L
    partitionEndBytes = $read.Length
}
$geoReject=Get-ChappyDirectoryCandidates -Stream $read -Geometry $invalidGeo -MaxScanBytes 1024
Assert-B ($geoReject.status -eq 'error' -and $geoReject.metrics.bytesRead -eq 0) 'R3 refuses supplied geometry outside partition bounds'

# Bogus boot sector does not become a trusted FAT32 volume. Memory only.
[byte[]]$fake=New-Object byte[] 4096
$fake[510]=0x55;$fake[511]=0xAA
$fakeStream=New-Object System.IO.MemoryStream(,$fake)
try {
    $badBpb=Get-ChappyDirectoryCandidates -Stream $fakeStream -MaxScanBytes 1024
    Assert-B ($badBpb.status -eq 'error' -and $badBpb.scanIncomplete -and
        $badBpb.metrics.bytesRead -eq 0) 'R3 bogus signed BPB cannot bypass geometry validation'
} finally { $fakeStream.Dispose() }

[byte[]]$incomplete=New-Object byte[] 31
$cutRecord=Read-ChappyBDirectoryCluster -Buffer $incomplete -Cluster 60 -OffsetBytes 0 -MaxCluster 1000 -IsRoot $true
Assert-B (-not $cutRecord.accepted -and $cutRecord.validCount -eq 0) 'R3 truncated 31-byte directory record is rejected'
