#requires -Version 5.1
# Team B R5: fixed artificial ground truth only; no real image, user names,
# source writes, FAT chain walking, file extraction, or path reconstruction.
# Dot-sourced by tests/Test-DirectoryScanner.ps1 after fixture helpers exist.

function New-R5Records { return ,(New-Object System.Collections.ArrayList) }
function Add-R5Fixture {
    param([string]$Id,[bool]$DirectoryTruth,[System.Collections.IList]$Records,
          [bool]$IsRoot=$false,[bool]$IncludeDeleted=$false,[bool]$NoEndMarker=$false,
          [string]$ExpectedReason=$null)
    [byte[]]$buf=New-Object byte[] 1024
    if ($NoEndMarker) {
        for($i=0;$i -lt $buf.Length;$i++) { $buf[$i]=0xE5 }
    }
    $offset=0
    foreach($entry in $Records) {
        [byte[]]$e=[byte[]]$entry
        if($e.Length -ne 32 -or $offset -gt 992) { throw 'R5 synthetic record overflow' }
        [Array]::Copy($e,0,$buf,$offset,32);$offset+=32
    }
    [void]$r5Fixtures.Add([pscustomobject]@{
        id=$Id; truth=$DirectoryTruth; root=$IsRoot; deleted=$IncludeDeleted
        expectedReason=$ExpectedReason; bytes=$buf
    })
}
$r5Fixtures=New-Object System.Collections.ArrayList
$one=New-ShortB 'ONE     TXT' 0x20 90 8
$two=New-ShortB 'TWO     TXT' 0x20 91 12
$three=New-ShortB 'THREE   TXT' 0x20 92 22
$sub1=New-ShortB 'SUBONE     ' 0x10 80 0
$sub2=New-ShortB 'SUBTWO     ' 0x10 81 0
$dot=New-ShortB '.          ' 0x10 60 0
$dotdot=New-ShortB '..         ' 0x10 2 0
$short=New-ShortB 'LFNQA   TXT' 0x20 70 15
$lfn=(New-LfnB 'InventedLong.txt' $short)
[byte[]]$deletedOne=[byte[]]$one.Clone();$deletedOne[0]=0xE5
[byte[]]$deletedTwo=[byte[]]$two.Clone();$deletedTwo[0]=0xE5

# Eight positives anchored by the known root position or a complete dot pair.
$x=New-R5Records;[void]$x.Add($one)
Add-R5Fixture 'root_one' $true $x -IsRoot $true -ExpectedReason 'root_valid_entry'
$x=New-R5Records;[void]$x.Add($one);[void]$x.Add($two)
Add-R5Fixture 'root_two' $true $x -IsRoot $true -ExpectedReason 'root_valid_entry'
$x=New-R5Records;foreach($entry in $lfn){[void]$x.Add($entry)};[void]$x.Add($short)
Add-R5Fixture 'root_lfn' $true $x -IsRoot $true -ExpectedReason 'root_valid_entry'
$x=New-R5Records;[void]$x.Add($dot);[void]$x.Add($dotdot)
Add-R5Fixture 'dot_empty' $true $x -ExpectedReason 'ordered_dot_pair'
$x=New-R5Records;[void]$x.Add($dot);[void]$x.Add($dotdot);[void]$x.Add($one)
Add-R5Fixture 'dot_one' $true $x -ExpectedReason 'ordered_dot_pair'
$x=New-R5Records;[void]$x.Add($dot);[void]$x.Add($dotdot);[void]$x.Add($one);[void]$x.Add($two)
Add-R5Fixture 'dot_two' $true $x -ExpectedReason 'ordered_dot_pair'
$x=New-R5Records;[void]$x.Add($dot);[void]$x.Add($dotdot);[void]$x.Add($deletedOne)
Add-R5Fixture 'dot_deleted' $true $x -IncludeDeleted $true -ExpectedReason 'ordered_dot_pair'
$x=New-R5Records;[void]$x.Add($dot);[void]$x.Add($dotdot)
Add-R5Fixture 'dot_no_end' $true $x -NoEndMarker $true -ExpectedReason 'ordered_dot_pair'

# Five intentionally real-in-fixture orphan directories without dot headers.
# Preserving these is why a strict dot-only hard rejection is inappropriate.
$x=New-R5Records;[void]$x.Add($one);[void]$x.Add($two)
Add-R5Fixture 'orphan_two_files' $true $x -ExpectedReason 'multiple_entries_with_end_marker'
$x=New-R5Records;[void]$x.Add($one);[void]$x.Add($two);[void]$x.Add($three)
Add-R5Fixture 'orphan_three_files' $true $x -ExpectedReason 'multiple_entries_with_end_marker'
$x=New-R5Records;[void]$x.Add($sub1);[void]$x.Add($sub2)
Add-R5Fixture 'orphan_two_subdirs' $true $x -ExpectedReason 'multiple_entries_with_end_marker'
$x=New-R5Records;[void]$x.Add($deletedOne);[void]$x.Add($two)
Add-R5Fixture 'orphan_deleted_and_file' $true $x -IncludeDeleted $true -ExpectedReason 'multiple_entries_with_end_marker'
$x=New-R5Records;foreach($entry in $lfn){[void]$x.Add($entry)};[void]$x.Add($short);[void]$x.Add($three)
Add-R5Fixture 'orphan_lfn_and_file' $true $x -ExpectedReason 'multiple_entries_with_end_marker'

# Eight deliberate file-data masquerades: identical directory-record shapes
# but *known synthetic negative* ground truth. This is not real-data sampling.
$x=New-R5Records;[void]$x.Add($one);[void]$x.Add($two)
Add-R5Fixture 'decoy_two_files' $false $x -ExpectedReason 'multiple_entries_with_end_marker'
$x=New-R5Records;[void]$x.Add($one);[void]$x.Add($two);[void]$x.Add($three)
Add-R5Fixture 'decoy_three_files' $false $x -ExpectedReason 'multiple_entries_with_end_marker'
$x=New-R5Records;[void]$x.Add($sub1);[void]$x.Add($sub2)
Add-R5Fixture 'decoy_two_subdirs' $false $x -ExpectedReason 'multiple_entries_with_end_marker'
$x=New-R5Records;[void]$x.Add($deletedOne);[void]$x.Add($deletedTwo)
Add-R5Fixture 'decoy_two_deleted' $false $x -IncludeDeleted $true -ExpectedReason 'multiple_entries_with_end_marker'
$x=New-R5Records;foreach($entry in $lfn){[void]$x.Add($entry)};[void]$x.Add($short);[void]$x.Add($two)
Add-R5Fixture 'decoy_lfn_plus_file' $false $x -ExpectedReason 'multiple_entries_with_end_marker'
$x=New-R5Records;[void]$x.Add($sub1);[void]$x.Add($one)
Add-R5Fixture 'decoy_subdir_plus_file' $false $x -ExpectedReason 'multiple_entries_with_end_marker'
$x=New-R5Records;[void]$x.Add($deletedOne);[void]$x.Add($one)
Add-R5Fixture 'decoy_deleted_plus_file' $false $x -IncludeDeleted $true -ExpectedReason 'multiple_entries_with_end_marker'
$x=New-R5Records;foreach($entry in $lfn){[void]$x.Add($entry)};[void]$x.Add($short);[void]$x.Add($sub1)
Add-R5Fixture 'decoy_lfn_plus_subdir' $false $x -ExpectedReason 'multiple_entries_with_end_marker'

# Eleven negatives with insufficient/inconsistent evidence.
$x=New-R5Records;[void]$x.Add($one)
Add-R5Fixture 'reject_lone_file' $false $x
$x=New-R5Records;foreach($entry in $lfn){[void]$x.Add($entry)};[void]$x.Add($short)
Add-R5Fixture 'reject_lone_lfn' $false $x
$x=New-R5Records;[void]$x.Add($dot);[void]$x.Add((New-ShortB '..         ' 0x10 9999 0));[void]$x.Add($one)
Add-R5Fixture 'reject_invalid_dotdot' $false $x
$x=New-R5Records;[void]$x.Add($one);[void]$x.Add($two)
Add-R5Fixture 'reject_two_without_end' $false $x -NoEndMarker $true
$x=New-R5Records;[void]$x.Add((New-ShortB 'VOLUME     ' 0x08 0 0))
Add-R5Fixture 'reject_volume_label' $false $x
$x=New-R5Records
Add-R5Fixture 'reject_zeros' $false $x
$x=New-R5Records;[void]$x.Add($deletedOne)
Add-R5Fixture 'reject_deleted_disabled' $false $x
$x=New-R5Records;[void]$x.Add((New-ShortB 'TOOHIGH TXT' 0x20 9999 12))
Add-R5Fixture 'reject_bad_cluster' $false $x
$x=New-R5Records;foreach($entry in $lfn){[void]$x.Add($entry)}
Add-R5Fixture 'reject_orphan_lfn_segment' $false $x -IsRoot $true
$x=New-R5Records;[void]$x.Add($dot)
Add-R5Fixture 'reject_single_dot' $false $x
$x=New-R5Records;[void]$x.Add((New-ShortB 'BADDIR     ' 0x10 70 44))
Add-R5Fixture 'reject_bad_directory_size' $false $x

$seen=@{}
$oldTP=0;$oldFP=0;$oldFN=0;$oldTN=0
$newTP=0;$newFP=0;$newFN=0;$newTN=0
$probableTP=0;$probableFP=0;$weakTrue=0;$weakDecoy=0
$reasonCounts=@{}
foreach($case in $r5Fixtures) {
    if($seen.ContainsKey($case.id)) { throw 'Duplicate synthetic case ID' }
    $seen[$case.id]=$true
    $result=Read-ChappyBDirectoryCluster -Buffer $case.bytes -Cluster 60 -OffsetBytes 0 -MaxCluster 1000 -IsRoot $case.root -IncludeDeleted:$case.deleted
    if(-not [string]::IsNullOrEmpty($case.expectedReason) -and $result.decisionReason -ne $case.expectedReason) {
        throw ('Unexpected synthetic container reason for ' + $case.id)
    }
    $legacyAccept=[bool]$result.accepted # unchanged acceptance predicate
    $newAccept=[bool]$result.accepted
    $reasonCounts[$result.decisionReason]=1+[int]$reasonCounts[$result.decisionReason]
    if($case.truth) {
        if($legacyAccept){$oldTP++}else{$oldFN++}
        if($newAccept){$newTP++}else{$newFN++}
    } else {
        if($legacyAccept){$oldFP++}else{$oldTN++}
        if($newAccept){$newFP++}else{$newTN++}
    }
    $weak=($result.decisionReason -eq 'multiple_entries_with_end_marker')
    if($weak -and $case.truth){$weakTrue++}
    if($weak -and -not $case.truth){$weakDecoy++}
    if($newAccept -and $result.confidence -eq 'probable') {
        if($case.truth){$probableTP++}else{$probableFP++}
    }
    if($newAccept) {
        $wantedConfidence=if($weak){'partial'}else{'probable'}
        if($result.confidence -ne $wantedConfidence){ throw ('Wrong synthetic confidence: ' + $case.id) }
        foreach($item in @($result.entries)) {
            if($null -ne $item.name -or $null -ne $item.shortName) {
                throw 'Default output leaked synthetic test name'
            }
            if($weak -and ($item.confidence -ne 'partial' -or
                $item.evidence -notcontains 'unpaired_multi_entry_weak_container')) {
                throw ('Weak fixture lost evidence: ' + $case.id)
            }
        }
    } elseif($result.confidence -ne 'unknown') {
        throw ('Rejected synthetic container has non-unknown confidence: ' + $case.id)
    }
}
Assert-B ($r5Fixtures.Count -eq 32 -and $seen.Count -eq 32) 'R5 deterministic 32-case synthetic matrix bounded and unique'
Assert-B ($oldTP -eq 13 -and $oldFP -eq 8 -and $oldFN -eq 0 -and $oldTN -eq 11) 'R5 historical acceptance model retains TP13 FP8 FN0 TN11'
Assert-B ($newTP -eq 13 -and $newFP -eq 8 -and $newFN -eq 0 -and $newTN -eq 11) 'R5 candidate discovery recall unchanged; decoys remain candidates'
Assert-B ($probableTP -eq 8 -and $probableFP -eq 0 -and $weakTrue -eq 5 -and $weakDecoy -eq 8) 'R5 probable-only synthetic precision: TP8 FP0, weak positives and decoys retained as partial'
Assert-B ($reasonCounts['multiple_entries_with_end_marker'] -eq 13 -and
    $reasonCounts['ordered_dot_pair'] -eq 5 -and $reasonCounts['root_valid_entry'] -eq 3) 'R5 fixed-code evidence histogram matches fixture categories'
Write-Host ("SYNTHETIC R5 ONLY: cases={0} candidate TP={1} FP={2} FN={3} TN={4}; probable TP={5} FP={6}; partial true={7} decoy={8}" -f
    $r5Fixtures.Count,$newTP,$newFP,$newFN,$newTN,$probableTP,$probableFP,$weakTrue,$weakDecoy)

# Exercise scanner-level backward compatibility against an existing synthetic
# read-only fixture: all candidates remain available, but weak container
# confidence must be propagated. Bound root and scan bytes explicitly.
Assert-B (-not $read.CanWrite -and $read.CanRead) 'R5 synthetic file stream remains strictly read-only'
$shaBefore = Hash-B $imagePath
$bounded=Get-ChappyDirectoryCandidates -Stream $read -Geometry $geo -MaxScanBytes 1024 -MaxCandidates 2
Assert-B ($bounded.scanIncomplete -and $bounded.metrics.bytesRead -eq 1024 -and
    $bounded.items.Count -le 2) 'R5 candidate and byte caps still enforced'
Assert-B (@($bounded.items|Where-Object {$null -ne $_.name -or $null -ne $_.shortName}).Count -eq 0) 'R5 scanner default name redaction preserved'
Assert-B ((Hash-B $imagePath) -eq $shaBefore) 'R5 synthetic source SHA-256 unchanged'
