#Requires -Version 5.1
# Synthetic-only Team D R4-P1. No file system I/O or real 31GB master IMG.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\Fat32GeometryTrust.psm1') -Force
$script:Pass=0;$script:Fail=0
function Check-D4 {
    param([bool]$Condition,[string]$Name)
    if($Condition){Write-Host "PASS $Name";$script:Pass++}
    else{Write-Host "FAIL $Name";$script:Fail++}
}
function Throws-D4 {
    param([scriptblock]$Action)
    try {$null=& $Action;return $false}catch{return $true}
}
function Put16-D4 {
    param([byte[]]$B,[int]$Offset,[uint16]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$B,$Offset,2)
}
function Put32-D4 {
    param([byte[]]$B,[int]$Offset,[uint32]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$B,$Offset,4)
}
function Make-D4 {
    $b=New-Object 'byte[]' 2097152
    $vbr=4096
    $b[510]=0x55;$b[511]=0xAA
    $b[446+4]=0x0C
    Put32-D4 $b (446+8) 8
    Put32-D4 $b (446+12) 4088
    $b[$vbr]=0xEB;$b[$vbr+1]=0x58;$b[$vbr+2]=0x90
    Put16-D4 $b ($vbr+11) 512
    $b[$vbr+13]=8
    Put16-D4 $b ($vbr+14) 32
    $b[$vbr+16]=2
    Put32-D4 $b ($vbr+32) 4088
    Put32-D4 $b ($vbr+36) 16
    Put32-D4 $b ($vbr+44) 2
    Put16-D4 $b ($vbr+48) 1
    Put16-D4 $b ($vbr+50) 6
    $b[$vbr+510]=0x55;$b[$vbr+511]=0xAA
    [Array]::Copy($b,$vbr,$b,($vbr+6*512),512)
    $fs=$vbr+512
    Put32-D4 $b $fs ([Convert]::ToUInt32('41615252',16))
    Put32-D4 $b ($fs+484) ([Convert]::ToUInt32('61417272',16))
    Put32-D4 $b ($fs+488) ([uint32]::MaxValue)
    Put32-D4 $b ($fs+492) ([uint32]::MaxValue)
    Put32-D4 $b ($fs+508) ([Convert]::ToUInt32('AA550000',16))
    [Text.Encoding]::ASCII.GetBytes('PRIVATE-CANARY-NOT-IN-JSON').CopyTo($b,500000)
    return ,$b
}
function Open-D4 {
    param([byte[]]$Bytes)
    return [IO.MemoryStream]::new($Bytes,$false)
}
function Check-D4Fixture {
    param([byte[]]$Bytes,[string]$Name,[string]$Reason)
    $s=Open-D4 $Bytes
    try{
        $r=Get-ChappyFatGeometryTrust -Stream $s
        Check-D4 ($r.trustDecision -eq 'reject' -and $r.reasons -contains $Reason) $Name
        Check-D4 ($r.metrics.bytesRead -le 2048 -and -not $r.writePermitted) "$Name bounded non-writable"
    }finally{$s.Dispose()}
}
function Hash-D4 {
    param([byte[]]$B)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($B)).Replace('-','')}
    finally{$sha.Dispose()}
}
$good=Make-D4
$startHash=Hash-D4 $good
$s=Open-D4 $good
try {
    $r=Get-ChappyFatGeometryTrust -Stream $s
    Check-D4 ($r.schemaVersion -eq '1' -and $r.team -eq 'D' -and $r.mode -eq 'read_only_geometry_trust_guard') 'V1 envelope and independent Team D scope'
    Check-D4 ($r.trustDecision -eq 'plausible_unverified' -and $r.reasons.Count -eq 0) 'Synthetic control geometry plausible, never certified trustworthy'
    Check-D4 ($r.status -eq 'ok' -and -not $r.scanIncomplete -and $r.metrics.bytesRead -eq 2048) 'Four 512-byte observations counted exactly'
    Check-D4 ($r.backupVbrRead -and $r.fsInfoRead -and $r.metrics.probesObserved -eq 4) 'MBR primary backup FSInfo all sampled'
    Check-D4 ($r.mbr.partitionOffsetBytes -eq 4096 -and $r.mbr.partitionLengthBytes -eq 2093056) 'MBR partition boundaries derived from 512-byte LBAs'
    Check-D4 ($r.geometry.fat1OffsetBytes -eq 20480 -and $r.geometry.fat2OffsetBytes -eq 28672 -and $r.geometry.fatLengthBytes -eq 8192) 'FAT geometry offsets derived within partition'
    Check-D4 ($r.geometry.dataClusterCount -eq 503) 'FAT data capacity checked against cluster count'
    Check-D4 ($r.warnings -contains 'real_master_img_trial_not_authorized' -and $r.warnings -contains 'signature.match_not_proof_of_health') 'Never authorize original data inspection'
    $json=$r | ConvertTo-Json -Depth 12
    Check-D4 ($json -notmatch 'PRIVATE-CANARY|rawBytes|sourcePath|Sha256|diskPath') 'JSON has no raw bytes, local paths or private fingerprints'
    Check-D4 ((Hash-D4 $good) -eq $startHash) 'Full synthetic source SHA unchanged'
}
finally{$s.Dispose()}

$fake=Make-D4
$wrong=20480
$fake[$wrong]=0xEB;$fake[$wrong+1]=0x58;$fake[$wrong+2]=0x90
$fake[$wrong+510]=0x55;$fake[$wrong+511]=0xAA
$s=Open-D4 $fake
try{
    $r=Get-ChappyFatGeometryTrust -Stream $s
    Check-D4 ($r.trustDecision -eq 'plausible_unverified' -and $r.geometry.fat1OffsetBytes -eq $wrong) 'Fake EB5890 at FAT start does not override MBR-derived VBR'
    Check-D4 ($r.metrics.bytesRead -eq 2048) 'Fake FAT VBR never scanned as extra probe'
}finally{$s.Dispose()}

$bad=Make-D4
$bad[510]=0
Check-D4Fixture $bad 'Bad MBR signature rejects geometry' 'mbr.signature_missing'
$bad=Make-D4
$bad[446+4]=0x07
Check-D4Fixture $bad 'Non FAT32 partition type refused' 'mbr.partition_type_not_fat32'
$bad=Make-D4
$bad[446]=0x66
Check-D4Fixture $bad 'Invalid active partition flag refused' 'mbr.boot_flag_invalid'
$bad=Make-D4
Put32-D4 $bad (446+8) 0
Check-D4Fixture $bad 'Zero MBR LBA start refused' 'mbr.empty_or_zero_start'
$bad=Make-D4
Put32-D4 $bad (446+12) 4294967295
Check-D4Fixture $bad 'Oversized MBR partition count refused' 'geometry.partition_exceeds_stream'
$bad=Make-D4
$bad[4096+510]=0
Check-D4Fixture $bad 'Bad primary signature refused' 'bpb.signature_missing'
$bad=Make-D4
$bad[4096]=0xEB;$bad[4096+2]=0
Check-D4Fixture $bad 'Fake EB58 signature missing valid jump suffix refused' 'bpb.boot_jump_invalid'
$bad=Make-D4
Put16-D4 $bad (4096+11) 0
Check-D4Fixture $bad 'Zero BPB sector size refused' 'bpb.bytes_per_sector_invalid'
$bad=Make-D4
$bad[4096+13]=0
Check-D4Fixture $bad 'Zero sectors per cluster refused without dividing by zero' 'bpb.sectors_per_cluster_invalid'
$bad=Make-D4
$bad[4096+13]=3
Check-D4Fixture $bad 'Non-power-of-two sectors per cluster refused' 'bpb.sectors_per_cluster_invalid'
$bad=Make-D4
$bad[4096+16]=1
Check-D4Fixture $bad 'Wrong FAT copy count refused' 'bpb.fat_copy_count_not_two'
$bad=Make-D4
Put16-D4 $bad (4096+14) 1
Check-D4Fixture $bad 'Too few reserved sectors refused' 'bpb.reserved_sectors_invalid'
$bad=Make-D4
Put32-D4 $bad (4096+36) 3000
Check-D4Fixture $bad 'FAT copies cannot overrun volume' 'geometry.fat_regions_exceed_volume'
$bad=Make-D4
Put32-D4 $bad (4096+32) 4294967295
Check-D4Fixture $bad 'Oversized BPB total sectors refused' 'geometry.bpb_exceeds_mbr_partition'
$bad=Make-D4
Put32-D4 $bad (4096+36) 1
Check-D4Fixture $bad 'Undersized FAT entry capacity refused' 'geometry.fat_entries_insufficient'
$bad=Make-D4
Put32-D4 $bad (4096+44) 10000
Check-D4Fixture $bad 'Out-of-data-range root cluster refused' 'geometry.root_cluster_out_of_range'
$bad=Make-D4
Put16-D4 $bad (4096+17) 512
Check-D4Fixture $bad 'Legacy FAT root-entry count refused' 'bpb.fat32_legacy_fields_nonzero'
$bad=Make-D4
Put16-D4 $bad (4096+48) 0
Check-D4Fixture $bad 'Missing FSInfo sector refused' 'bpb.fsinfo_location_invalid'
$bad=Make-D4
Put16-D4 $bad (4096+50) 40
Check-D4Fixture $bad 'Backup sector outside reserved range refused' 'bpb.backup_vbr_location_invalid'
$bad=Make-D4
$bad[4096+6*512+13]=4
Check-D4Fixture $bad 'Backup VBR mismatched FAT geometry refused' 'vbr.backup_geometry_or_signature_mismatch'
$bad=Make-D4
$bad[4096+6*512+510]=0
Check-D4Fixture $bad 'Backup VBR signature tampering refused' 'vbr.backup_geometry_or_signature_mismatch'
$bad=Make-D4
$bad[4096+512+484]=0
Check-D4Fixture $bad 'FSInfo structure signature mismatch refused' 'fsinfo.signatures_invalid'
$bad=Make-D4
Put32-D4 $bad (4096+512+488) 10000
Check-D4Fixture $bad 'FSInfo free count exceeds data clusters' 'fsinfo.count_or_hint_out_of_range'
$bad=Make-D4
Put32-D4 $bad (4096+512+492) 1
Check-D4Fixture $bad 'FSInfo next-free hint invalid' 'fsinfo.count_or_hint_out_of_range'
$bad=Make-D4
Put16-D4 $bad (4096+11) 4096
Check-D4Fixture $bad 'MBR 512-byte LBA and BPB sector-size mismatch is rejected' 'geometry.mbr_512_bpb_sector_size_differs'
$bad=Make-D4
Put16-D4 $bad (4096+48) 6
Check-D4Fixture $bad 'FSInfo sector overlapping backup refused' 'bpb.fsinfo_location_invalid'

$s=Open-D4 $good
try{
    $r=Get-ChappyFatGeometryTrust -Stream $s -MaxReadBytes 512
    Check-D4 ($r.status -eq 'partial' -and $r.scanIncomplete -and $r.trustDecision -eq 'insufficient_evidence') 'Only MBR read cannot certify BPB'
    Check-D4 ($r.metrics.bytesRead -eq 512 -and $r.reasons -contains 'budget.primary_vbr_unread') 'Hard 512-byte budget stops before VBR'
    $r=Get-ChappyFatGeometryTrust -Stream $s -MaxReadBytes 1024
    Check-D4 ($r.trustDecision -eq 'insufficient_evidence' -and $r.metrics.bytesRead -eq 1024) 'MBR + primary VBR alone insufficient'
    Check-D4 ($r.reasons -contains 'budget.backup_vbr_unread' -and $r.reasons -contains 'budget.fsinfo_unread') 'Omitted backup/FSInfo individually recorded'
    $r=Get-ChappyFatGeometryTrust -Stream $s -MaxReadBytes 1536
    Check-D4 ($r.trustDecision -eq 'insufficient_evidence' -and $r.backupVbrRead -and -not $r.fsInfoRead) 'Three observations cannot claim full four-probe confidence'
    Check-D4 ($r.metrics.bytesRead -eq 1536) 'Exact 1536-byte budget'
}finally{$s.Dispose()}

$short=New-Object 'byte[]' 400
$s=Open-D4 $short
try{
    $r=Get-ChappyFatGeometryTrust -Stream $s
    Check-D4 ($r.status -eq 'partial' -and $r.trustDecision -eq 'insufficient_evidence') 'Truncated MBR remains unknown'
    Check-D4 ($r.metrics.bytesRead -eq 400 -and $r.reasons -contains 'io.mbr_truncated') 'True partial MBR bytes recorded'
}finally{$s.Dispose()}
$short=New-Object 'byte[]' 4600
[Array]::Copy($good,0,$short,0,$short.Length)
$s=Open-D4 $short
try{
    $r=Get-ChappyFatGeometryTrust -Stream $s
    Check-D4 ($r.scanIncomplete -and $r.reasons -contains 'io.primary_vbr_truncated') 'Truncated primary VBR detected'
    Check-D4 ($r.metrics.bytesRead -eq 1016) 'Actually read bytes counted on cut VBR'
}finally{$s.Dispose()}
$short=New-Object 'byte[]' 7650
[Array]::Copy($good,0,$short,0,$short.Length)
$s=Open-D4 $short
try{
    $r=Get-ChappyFatGeometryTrust -Stream $s
    Check-D4 ($r.scanIncomplete -and $r.reasons -contains 'io.backup_vbr_truncated') 'Truncated backup VBR detected'
    Check-D4 ($r.metrics.bytesRead -le 2048) 'Truncated backup cannot exceed total read budget'
}finally{$s.Dispose()}

$w=[IO.MemoryStream]::new($good,$true)
try{
    Check-D4 (Throws-D4 {Get-ChappyFatGeometryTrust -Stream $w}) 'Writable stream rejected'
}finally{$w.Dispose()}
$s=Open-D4 $good
try{
    Check-D4 (Throws-D4 {Get-ChappyFatGeometryTrust -Stream $s -PartitionIndex 4}) 'Partition index bounded'
    Check-D4 (Throws-D4 {Get-ChappyFatGeometryTrust -Stream $s -MaxReadBytes 2049}) 'Global read budget capped'
    Check-D4 (Throws-D4 {Get-ChappyFatGeometryTrust -Stream $s -MaxReadBytes 511}) 'Cannot read partial MBR under minimum budget'
    $r=Get-ChappyFatGeometryTrust -Stream $s -PartitionIndex 1
    Check-D4 ($r.trustDecision -eq 'reject' -and $r.reasons -contains 'mbr.empty_or_zero_start') 'Empty partition slot cannot masquerade as FAT32'
}finally{$s.Dispose()}
Write-Host "Team D R4-P1 result: $script:Pass passed; $script:Fail failed."
if($script:Fail -gt 0){exit 1}
