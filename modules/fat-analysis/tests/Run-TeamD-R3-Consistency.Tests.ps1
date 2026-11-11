#Requires -Version 5.1
# Team D R3-P4: artificial FAT32 directory slots and FAT copies, strictly memory-only.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\Fat32DirectoryConsistency.psm1') -Force
$script:Passed=0;$script:Failed=0
function Check-DConsistency {
    param([bool]$Condition,[string]$Label)
    if($Condition){Write-Host "PASS $Label";$script:Passed++}
    else{Write-Host "FAIL $Label";$script:Failed++}
}
function Throws-DConsistency {
    param([scriptblock]$Action)
    try {$null=& $Action;return $false} catch{return $true}
}
function Set-EntryDConsistency {
    param([byte[]]$Buffer,[int]$Offset,[int]$Cluster,[uint32]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$Buffer,($Offset+$Cluster*4),4)
}
function Set-SlotDConsistency {
    param([byte[]]$Buffer,[int]$Slot,[string]$Name,[int]$Attr,[int]$Start,[uint32]$Size,[int]$Base=8192)
    $pos=$Base+32*$Slot
    $nameBytes=[Text.Encoding]::ASCII.GetBytes($Name.PadRight(11).Substring(0,11))
    [Array]::Copy($nameBytes,0,$Buffer,$pos,11)
    $Buffer[$pos+11]=[byte]$Attr
    [Array]::Copy([BitConverter]::GetBytes([uint16]($Start -shr 16)),0,$Buffer,($pos+20),2)
    [Array]::Copy([BitConverter]::GetBytes([uint16]($Start -band 65535)),0,$Buffer,($pos+26),2)
    [Array]::Copy([BitConverter]::GetBytes($Size),0,$Buffer,($pos+28),4)
}
function New-DConsistencyFixture {
    $b=New-Object 'byte[]' 32768
    foreach($fat in @(512,4096)) {
        Set-EntryDConsistency $b $fat 2 3
        Set-EntryDConsistency $b $fat 3 ([Convert]::ToUInt32('0FFFFFFF',16))
        Set-EntryDConsistency $b $fat 10 ([Convert]::ToUInt32('0FFFFFFF',16))
        Set-EntryDConsistency $b $fat 20 0
        Set-EntryDConsistency $b $fat 30 ([Convert]::ToUInt32('0FFFFFFF',16))
    }
    Set-EntryDConsistency $b 4096 10 11
    Set-EntryDConsistency $b 4096 11 ([Convert]::ToUInt32('0FFFFFFF',16))
    Set-EntryDConsistency $b 4096 20 ([Convert]::ToUInt32('0FFFFFF7',16))
    Set-EntryDConsistency $b 4096 30 31
    Set-EntryDConsistency $b 4096 31 30
    Set-SlotDConsistency $b 0 'SECRETATXT' 0x20 2 6000
    Set-SlotDConsistency $b 1 'HIDDENBBIN' 0x20 10 8192
    Set-SlotDConsistency $b 2 'SENSITIVE01' 0x20 20 128
    Set-SlotDConsistency $b 3 'ZEROFILE00' 0x20 0 100
    Set-SlotDConsistency $b 4 'EMPTYFILE0' 0x20 0 0
    Set-SlotDConsistency $b 5 'DIRSECRET00' 0x10 30 0
    Set-SlotDConsistency $b 6 'LONGNAME001' 0x0F 2 9999
    # Slot 7 remains a zero terminator, and everything beyond stays artificial.
    return ,$b
}
function Open-DConsistency {
    param([byte[]]$Buffer)
    return [IO.MemoryStream]::new($Buffer,$false)
}
function Hash-DConsistency {
    param([byte[]]$Buffer)
    $hash=[Security.Cryptography.SHA256]::Create()
    try {return [BitConverter]::ToString($hash.ComputeHash($Buffer)).Replace('-','')}
    finally {$hash.Dispose()}
}
function Scan-DConsistency {
    param([IO.Stream]$Stream,[int]$Budget=2048,[int]$Steps=16,[int]$Slots=8,
        [long]$DirectoryOffset=8192,[long]$Fat2Offset=4096,[long]$FatSize=1024,
        [long]$MaxCluster=100)
    return Get-ChappyFatDirectoryConsistency -Stream $Stream -DirectoryOffsetBytes $DirectoryOffset -Fat1OffsetBytes 512 -Fat2OffsetBytes $Fat2Offset -FatLengthBytes $FatSize -MaxDataCluster $MaxCluster -DirectorySlots $Slots -BytesPerCluster 4096 -MaxStepsPerTrace $Steps -MaxReadBytes $Budget
}
function Get-DConsistencyObservation {
    param($Report,[int]$Fat,[int]$Slot)
    return @($Report.items|Where-Object {$_.fatIndex -eq $Fat -and $_.slotIndex -eq $Slot})[0]
}

$original=New-DConsistencyFixture;$before=Hash-DConsistency $original
$s=Open-DConsistency $original
try {
    $r=Scan-DConsistency $s
    Check-DConsistency ($r.schemaVersion -eq '1' -and $r.team -eq 'D' -and $r.status -eq 'ok') 'Interface v1 and fully resolved requested window'
    Check-DConsistency ($r.mode -eq 'read_only_directory_fat_consistency' -and -not $r.writePermitted) 'Strictly read-only evidence mode'
    Check-DConsistency ($r.metrics.bytesRead -eq 304 -and $r.metrics.directoryBytesRead -eq 256 -and $r.metrics.fatBytesRead -eq 48) 'Actual global read bytes counted: 256 + 48'
    Check-DConsistency ($r.metrics.candidateRecords -eq 6 -and $r.metrics.skippedEntries -eq 1 -and $r.metrics.slotsExamined -eq 8) 'Six candidates, LFN skipped, end marker observed'
    Check-DConsistency ($r.metrics.directoryEndMarkerObserved -and -not $r.scanIncomplete) 'Zero directory terminator ends requested window'
    Check-DConsistency ($r.metrics.observations -eq 12 -and $r.metrics.conflicts -eq 6 -and $r.metrics.compatibleObservations -eq 6) 'Per-copy numeric conflict totals exact'
    Check-DConsistency ($r.copies[0].fatEntriesRead -eq 5 -and $r.copies[1].fatEntriesRead -eq 7) 'Different chain lengths independently observed'
    Check-DConsistency ((Get-DConsistencyObservation $r 0 0).consistency -eq 'compatible' -and (Get-DConsistencyObservation $r 1 0).consistency -eq 'compatible') 'Two-cluster file size compatible with both FATs'
    Check-DConsistency ((Get-DConsistencyObservation $r 0 1).evidence -eq 'file.chain_shorter_than_size') 'File size exceeds FAT1 chain capacity'
    Check-DConsistency ((Get-DConsistencyObservation $r 1 1).evidence -eq 'fat.chain_eoc_compatible') 'FAT2 two-cluster chain supports file size'
    Check-DConsistency ((Get-DConsistencyObservation $r 0 2).evidence -eq 'fat.chain_free_link') 'Free FAT link conflicts with candidate'
    Check-DConsistency ((Get-DConsistencyObservation $r 1 2).evidence -eq 'fat.chain_bad_marker') 'Bad marker is distinct from free link'
    Check-DConsistency ((Get-DConsistencyObservation $r 0 3).evidence -eq 'file.nonempty_zero_cluster') 'Nonempty file cannot start at cluster zero'
    Check-DConsistency ((Get-DConsistencyObservation $r 1 4).evidence -eq 'file.empty_zero_cluster') 'Empty file and zero start are compatible'
    Check-DConsistency ((Get-DConsistencyObservation $r 0 5).consistency -eq 'compatible' -and (Get-DConsistencyObservation $r 1 5).evidence -eq 'fat.chain_cycle') 'Directory EOC versus cycle detected, not guessed'
    Check-DConsistency ($r.warnings -contains 'geometry.caller_supplied_unverified' -and $r.warnings -contains 'file.compatibility_not_content_validation') 'No authenticity or content correctness claim'
    $json=$r|ConvertTo-Json -Depth 12
    Check-DConsistency ($json -notmatch 'SECRETATXT|HIDDENBBIN|SENSITIVE01|LONGNAME001|DIRSECRET00' -and $json -notmatch 'rawBytes|Sha256|sourcePath') 'JSON excludes artificial private filename canaries and raw data'
    Check-DConsistency ((Hash-DConsistency $original) -eq $before) 'Input artificial IMG remains byte-identical'
}
finally {$s.Dispose()}

$limited=New-DConsistencyFixture
$s=Open-DConsistency $limited
try {
    $r=Scan-DConsistency $s -Budget 264
    Check-DConsistency ($r.metrics.bytesRead -eq 264 -and $r.metrics.fatBytesRead -eq 8) 'Exact cumulative budget enforcement across directory and both FATs'
    Check-DConsistency ($r.copies[0].fatEntriesRead -eq 1 -and $r.copies[1].fatEntriesRead -eq 1) 'Fair per-copy FAT entry quota enforced'
    Check-DConsistency ($r.scanIncomplete -and $r.status -eq 'partial' -and $r.metrics.unresolved -gt 0) 'Budget exhaustion cannot be misreported as clean'
    Check-DConsistency ((Get-DConsistencyObservation $r 0 0).evidence -eq 'budget.fat_copy_quota') 'Insufficient chain evidence is explicitly unknown'
    Check-DConsistency ((Get-DConsistencyObservation $r 0 4).consistency -eq 'compatible') 'Zero-byte file compatible without any FAT reads'
    $r2=Scan-DConsistency $s -Budget 96
    Check-DConsistency ($r2.metrics.bytesRead -eq 96 -and $r2.scanIncomplete) 'Directory metadata scan itself respects byte budget'
    Check-DConsistency ($r2.metrics.candidateRecords -eq 3 -and $r2.metrics.slotsExamined -eq 3) 'Directory limited to observed slots only'
}
finally {$s.Dispose()}

$truncated=New-Object 'byte[]' 8335
$whole=New-DConsistencyFixture
[Array]::Copy($whole,0,$truncated,0,$truncated.Length)
$s=Open-DConsistency $truncated
try {
    $r=Scan-DConsistency $s
    Check-DConsistency ($r.scanIncomplete -and $r.status -eq 'partial' -and $r.warnings -contains 'io.directory_truncated') 'Partial directory slot detected'
    Check-DConsistency ($r.metrics.directoryBytesRead -eq 143 -and $r.metrics.candidateRecords -eq 4) 'Truncated 32-byte slot is not parsed into fake record'
}
finally {$s.Dispose()}

$swapped=New-DConsistencyFixture
$swapped[8192+11]=0x0F
$swapped[8192+32+11]=0x08
$swapped[8192+64]=0xE5
$swapped[8192+96]=0x2E
$swapped[8192+128+11]=0xC0
$s=Open-DConsistency $swapped
try {
    $r=Scan-DConsistency $s
    Check-DConsistency ($r.metrics.candidateRecords -eq 1 -and $r.metrics.skippedEntries -eq 6) 'LFN, volume, deleted, dot and unsupported attribute slots excluded'
    Check-DConsistency ($r.items.Count -eq 2 -and $r.items[0].slotIndex -eq 5) 'Only real short-entry candidates considered, numeric result only'
}
finally {$s.Dispose()}

$invalid=New-DConsistencyFixture
Set-SlotDConsistency $invalid 0 'RANGEFILE01' 0x20 101 1
Set-SlotDConsistency $invalid 1 'DIRZERO0000' 0x10 0 0
$s=Open-DConsistency $invalid
try {
    $r=Scan-DConsistency $s
    Check-DConsistency ((Get-DConsistencyObservation $r 0 0).evidence -eq 'entry.cluster_out_of_range') 'Out-of-data-range start flagged without FAT I/O'
    Check-DConsistency ((Get-DConsistencyObservation $r 1 1).evidence -eq 'directory.zero_cluster') 'Zero start directory flagged'
}
finally {$s.Dispose()}

$huge=New-DConsistencyFixture
Set-SlotDConsistency $huge 0 'HUGEFILE001' 0x20 2 ([uint32]::MaxValue)
$s=Open-DConsistency $huge
try {
    $r=Scan-DConsistency $s -Steps 1
    Check-DConsistency ((Get-DConsistencyObservation $r 0 0).evidence -eq 'budget.chain_steps') 'Huge declared file cannot cause unbounded chain traversal'
    Check-DConsistency ($r.metrics.bytesRead -le $r.metrics.maxReadBytes) 'Huge file size constrained by read budget'
}
finally {$s.Dispose()}

$device=[IO.MemoryStream]::new((New-DConsistencyFixture),$true)
try {
    Check-DConsistency (Throws-DConsistency {Scan-DConsistency $device}) 'Writable stream rejected before use'
}
finally {$device.Dispose()}
$s=Open-DConsistency (New-DConsistencyFixture)
try {
    Check-DConsistency (Throws-DConsistency {Get-ChappyFatDirectoryConsistency -Stream $s -DirectoryOffsetBytes 8193 -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100}) 'Unaligned directory start rejected'
    Check-DConsistency (Throws-DConsistency {Get-ChappyFatDirectoryConsistency -Stream $s -DirectoryOffsetBytes 8192 -Fat1OffsetBytes 512 -Fat2OffsetBytes 1024 -FatLengthBytes 1024 -MaxDataCluster 100}) 'Overlapping mirrors rejected'
    Check-DConsistency (Throws-DConsistency {Get-ChappyFatDirectoryConsistency -Stream $s -DirectoryOffsetBytes 512 -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100}) 'Directory and FAT overlapping regions rejected'
    Check-DConsistency (Throws-DConsistency {Get-ChappyFatDirectoryConsistency -Stream $s -DirectoryOffsetBytes 8192 -Fat1OffsetBytes 512 -Fat2OffsetBytes ([long]::MaxValue-3) -FatLengthBytes 1024 -MaxDataCluster 100}) 'Int64 FAT offset overflow rejected'
    Check-DConsistency (Throws-DConsistency {Get-ChappyFatDirectoryConsistency -Stream $s -DirectoryOffsetBytes ([long]::MaxValue-31) -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100}) 'Int64 directory length overflow rejected'
    Check-DConsistency (Throws-DConsistency {Get-ChappyFatDirectoryConsistency -Stream $s -DirectoryOffsetBytes 8192 -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 12 -MaxDataCluster 100}) 'Impossible declared FAT size fails safely'
    Check-DConsistency (Throws-DConsistency {Get-ChappyFatDirectoryConsistency -Stream $s -DirectoryOffsetBytes 8192 -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -DirectorySlots 17}) 'Directory slot count capped'
    Check-DConsistency (Throws-DConsistency {Get-ChappyFatDirectoryConsistency -Stream $s -DirectoryOffsetBytes 8192 -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -MaxStepsPerTrace 33}) 'Chain trace step count capped'
    Check-DConsistency (Throws-DConsistency {Get-ChappyFatDirectoryConsistency -Stream $s -DirectoryOffsetBytes 8192 -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -MaxReadBytes 4097}) 'Global 4096-byte budget capped'
    Check-DConsistency (Throws-DConsistency {Get-ChappyFatDirectoryConsistency -Stream $s -DirectoryOffsetBytes 8192 -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -BytesPerCluster 768}) 'Non-power-of-two cluster byte count rejected'
    $x=Get-ChappyFatDirectoryConsistency -Stream $s -DirectoryOffsetBytes 8192 -Fat1OffsetBytes 512 -Fat2OffsetBytes 2199023255552 -FatLengthBytes 1099511627776 -MaxDataCluster 100 -MaxReadBytes 1024
    Check-DConsistency ($x.scanIncomplete -and $x.metrics.bytesRead -le 1024) 'Huge declared but absent FAT2 is bounded and incomplete'
}
finally {$s.Dispose()}
Write-Host "Team D R3-P4 result: $script:Passed passed; $script:Failed failed."
if($script:Failed -gt 0) {exit 1}
