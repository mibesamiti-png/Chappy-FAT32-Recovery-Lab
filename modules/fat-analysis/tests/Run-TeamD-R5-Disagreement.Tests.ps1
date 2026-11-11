#Requires -Version 5.1
# R5 Team D: only artificial in-memory FAT32-like data. No filesystem/device I/O.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\Fat32VbrDisagreement.psm1') -Force
$script:Pass=0;$script:Fail=0
function Check-D5 {
    param([bool]$Condition,[string]$Label)
    if($Condition){Write-Host "PASS $Label";$script:Pass++}
    else{Write-Host "FAIL $Label";$script:Fail++}
}
function Throws-D5 {
    param([scriptblock]$Action)
    try{$null=& $Action;return $false}catch{return $true}
}
function U16-D5 {
    param([byte[]]$B,[int]$At,[uint16]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$B,$At,2)
}
function U32-D5 {
    param([byte[]]$B,[int]$At,[uint32]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$B,$At,4)
}
function New-D5Image {
    $b=New-Object 'byte[]' 2097152
    $v=4096
    $b[510]=0x55;$b[511]=0xAA
    $b[450]=0x0C
    U32-D5 $b 454 8
    U32-D5 $b 458 4088
    $b[$v]=0xEB;$b[$v+1]=0x58;$b[$v+2]=0x90
    U16-D5 $b ($v+11) 512
    $b[$v+13]=8
    U16-D5 $b ($v+14) 32
    $b[$v+16]=2
    U32-D5 $b ($v+32) 4088
    U32-D5 $b ($v+36) 16
    U32-D5 $b ($v+44) 2
    U16-D5 $b ($v+48) 1
    U16-D5 $b ($v+50) 6
    $b[$v+510]=0x55;$b[$v+511]=0xAA
    [Array]::Copy($b,$v,$b,($v+3072),512)
    $fs=$v+512
    U32-D5 $b $fs ([Convert]::ToUInt32('41615252',16))
    U32-D5 $b ($fs+484) ([Convert]::ToUInt32('61417272',16))
    U32-D5 $b ($fs+488) ([uint32]::MaxValue)
    U32-D5 $b ($fs+492) ([uint32]::MaxValue)
    U32-D5 $b ($fs+508) ([Convert]::ToUInt32('AA550000',16))
    [Text.Encoding]::ASCII.GetBytes('PRIVATE-NAME-CANARY-NO-EXPORT').CopyTo($b,500000)
    return ,$b
}
function Open-D5 {
    param([byte[]]$B)
    return [IO.MemoryStream]::new($B,$false)
}
function Run-D5 {
    param([byte[]]$B,[int]$Budget=2048)
    $s=Open-D5 $B
    try {return Get-ChappyFatVbrDisagreement -Stream $s -MaxReadBytes $Budget}
    finally {$s.Dispose()}
}
function Hash-D5 {
    param([byte[]]$B)
    $h=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($h.ComputeHash($B)).Replace('-','')}
    finally{$h.Dispose()}
}
$good=New-D5Image;$hash=Hash-D5 $good
$r=Run-D5 $good
Check-D5 ($r.schemaVersion -eq '1' -and $r.team -eq 'D' -and $r.mode -eq 'read_only_vbr_disagreement') 'V1 schema and separate D research mode'
Check-D5 ($r.status -eq 'ok' -and -not $r.scanIncomplete) 'Full synthetic four-probe evidence collected'
Check-D5 ($r.agreement -eq 'agree' -and $r.differingFields.Count -eq 0) 'Matching VBR geometry reported only as agreement'
Check-D5 ($r.candidates[0].plausibility -eq 'plausible_unverified' -and $r.candidates[1].plausibility -eq 'plausible_unverified') 'Both independently plausible and explicitly unverified'
Check-D5 ($null -eq $r.selectedCandidate -and $r.sourceDecision -eq 'not_selected') 'No selected source or repair candidate'
Check-D5 (-not $r.writePermitted -and $r.warnings -contains 'real_master_img_trial_not_authorized') 'Read-only mode never permits real IMG trial'
Check-D5 ($r.metrics.bytesRead -eq 2048 -and $r.metrics.maxReadBytes -eq 2048) 'Four 512-byte reads precisely accounted'
Check-D5 ($r.mbr.startOffsetBytes -eq 4096 -and $r.mbr.lengthBytes -eq 2093056) 'MBR bounds derived from LBA 8, 4088 sectors'
Check-D5 ($r.candidates[0].geometry.fat1OffsetBytes -eq 20480 -and $r.candidates[1].geometry.fat2OffsetBytes -eq 28672) 'Independent candidate FAT offsets calculated'
Check-D5 ($r.candidates[0].geometry.dataClusterCount -eq 503) 'Independent cluster count derived'
Check-D5 ($r.warnings -contains 'backup.locator_from_primary_unverified' -and $r.warnings -contains 'candidate.authenticity_not_established') 'Untrusted locator and authenticity uncertainty always declared'
$json=$r|ConvertTo-Json -Depth 12
Check-D5 ($json -notmatch 'PRIVATE-NAME|CANARY|rawBytes|sourcePath|sourceSha|recoveredFile') 'No sample bytes, private filename, paths or fingerprints in result JSON'
Check-D5 ((Hash-D5 $good) -eq $hash) 'Synthetic memory image byte-identical after scanning'

$changed=New-D5Image
U32-D5 $changed (4096+3072+44) 3
$r=Run-D5 $changed
Check-D5 ($r.agreement -eq 'disagree' -and $r.differingFields -contains 'bpb.rootCluster') 'Root cluster mismatch flagged as a fixed field code'
Check-D5 ($r.candidates[0].plausibility -eq 'plausible_unverified' -and $r.candidates[1].plausibility -eq 'plausible_unverified') 'Both different root clusters independently plausible'
Check-D5 ($r.warnings -contains 'vbr.both_plausible_but_incompatible') 'Both-plausible disagreement explicit'
Check-D5 ($r.sourceDecision -eq 'not_selected' -and $null -eq $r.selectedCandidate) 'No preference despite two plausible candidates'
Check-D5 (-not $r.scanIncomplete -and $r.status -eq 'ok') 'Disagreement is observed, not omitted evidence'

$changed=New-D5Image
U32-D5 $changed (4096+3072+32) 4000
$r=Run-D5 $changed
Check-D5 ($r.agreement -eq 'disagree' -and $r.differingFields -contains 'bpb.totalSectors') 'Two BPBs with different bounded partition length compared'
Check-D5 ($r.candidates[1].plausibility -eq 'plausible_unverified') 'Backup total-sector alternative separately plausible'
Check-D5 ($r.candidates[1].geometry.dataClusterCount -eq 492) 'Backup FAT/data capacity independently recomputed'

$changed=New-D5Image
U32-D5 $changed (4096+3072+32) ([uint32]::MaxValue)
$r=Run-D5 $changed
Check-D5 ($r.candidates[1].plausibility -eq 'contradicted' -and $r.candidates[1].reasonCodes -contains 'geometry.exceeds_partition_or_stream') 'Hostile huge backup BPB total sectors rejected'
Check-D5 ($r.candidates[0].plausibility -eq 'plausible_unverified' -and $r.agreement -eq 'disagree') 'Primary separately analyzed; no automatic promotion'
Check-D5 ($r.metrics.bytesRead -eq 2048) 'Huge BPB never enlarges read budget'

$changed=New-D5Image
U32-D5 $changed (4096+32) ([uint32]::MaxValue)
$r=Run-D5 $changed
Check-D5 ($r.candidates[0].plausibility -eq 'contradicted' -and $r.candidates[1].plausibility -eq 'plausible_unverified') 'Primary huge BPB does not block backup evidence'
Check-D5 ($null -eq $r.selectedCandidate -and $r.agreement -eq 'disagree') 'Backup never silently selected as replacement'

$changed=New-D5Image
$changed[4096+3072+510]=0
$r=Run-D5 $changed
Check-D5 ($r.candidates[1].reasonCodes -contains 'vbr.signature_invalid') 'Malformed backup sector signature detected'
Check-D5 ($r.candidates[0].plausibility -eq 'plausible_unverified' -and $r.agreement -eq 'disagree') 'Bad backup does not change primary geometry observation'
$changed=New-D5Image
$changed[4096+3072]=0xEB
$changed[4096+3072+2]=0
$r=Run-D5 $changed
Check-D5 ($r.candidates[1].reasonCodes -contains 'vbr.jump_invalid') 'Fake EB58 missing boot-jump suffix rejected'
Check-D5 ($r.agreement -eq 'disagree') 'Jump-pattern disagreement captured'
$changed=New-D5Image
U32-D5 $changed (4096+3072+36) 1
$r=Run-D5 $changed
Check-D5 ($r.candidates[1].reasonCodes -contains 'geometry.fat_entry_capacity_insufficient') 'Undersized backup FAT capacity detected'

$changed=New-D5Image
U16-D5 $changed (4096+3072+48) 2
$r=Run-D5 $changed
Check-D5 ($r.agreement -eq 'disagree' -and $r.differingFields -contains 'bpb.fsInfoSector') 'Backup declares different FSInfo locator'
Check-D5 ($r.candidates[1].plausibility -eq 'insufficient_evidence' -and $r.candidates[1].unknownCodes -contains 'fsinfo.for_candidate_not_observed') 'Never borrow FSInfo evidence from primary for different backup offset'
Check-D5 ($r.scanIncomplete -and $r.status -eq 'partial') 'Unprobed backup FSInfo reported partial'

$shift=New-D5Image
U16-D5 $shift (4096+50) 7
$r=Run-D5 $shift
Check-D5 ($r.candidates[1].probeOffsetBytes -eq (4096+7*512)) 'Only primary-declared shifted backup sector probed'
Check-D5 ($r.candidates[1].plausibility -eq 'contradicted' -and $r.candidates[1].reasonCodes -contains 'vbr.signature_invalid') 'Shifted locator cannot make all-zero sector valid'
Check-D5 ($r.candidates[0].plausibility -eq 'plausible_unverified') 'Shifted backup pointer does not rewrite independent primary structure'
Check-D5 ($r.agreement -eq 'disagree' -and $null -eq $r.selectedCandidate) 'Never find or promote undisclosed secondary boot copies'
Check-D5 ($r.metrics.bytesRead -eq 2048) 'Shifted locator uses same hard 4-sector budget'

$fake=New-D5Image
$fat=20480
$fake[$fat]=0xEB;$fake[$fat+1]=0x58;$fake[$fat+2]=0x90
$fake[$fat+510]=0x55;$fake[$fat+511]=0xAA
$r=Run-D5 $fake
Check-D5 ($r.agreement -eq 'agree' -and $r.candidates[1].probeOffsetBytes -ne $fat) 'Misleading EB58 at FAT start never repointed as backup VBR'
Check-D5 ($r.metrics.bytesRead -eq 2048) 'Fake FAT signature causes zero additional read probes'

$fsBad=New-D5Image
U32-D5 $fsBad (4096+512+488) 50000
$r=Run-D5 $fsBad
Check-D5 ($r.agreement -eq 'agree' -and $r.candidates[0].reasonCodes -contains 'fsinfo.hints_outside_candidate') 'Matching BPB copies can both contradict shared FSInfo hint'
Check-D5 ($r.candidates[1].plausibility -eq 'contradicted' -and $r.sourceDecision -eq 'not_selected') 'Agreement does not establish integrity'

$changed=New-D5Image
$changed[510]=0
$r=Run-D5 $changed
Check-D5 ($r.mbr.reasonCodes -contains 'mbr.signature_invalid' -and $r.metrics.bytesRead -eq 512) 'Bad MBR anchor triggers no VBR fallback search'
Check-D5 ($r.candidates[0].plausibility -eq 'contradicted' -and $r.candidates[1].plausibility -eq 'contradicted') 'Neither candidate can be trusted under bad MBR anchor'
Check-D5 ($r.agreement -eq 'insufficient_evidence' -and $r.scanIncomplete) 'Unknown copy agreement not mislabeled as matching'

$changed=New-D5Image
U16-D5 $changed (4096+50) 40
$r=Run-D5 $changed
Check-D5 ($r.candidates[0].reasonCodes -contains 'bpb.backup_locator_invalid') 'Backup locator outside reserved region is contradiction'
Check-D5 ($r.candidates[1].unknownCodes -contains 'backup.primary_declared_locator_invalid') 'Never seek outside primary declared reserved area'
Check-D5 ($r.metrics.bytesRead -le 1536 -and $r.agreement -eq 'insufficient_evidence') 'Invalid locator cannot silently recover alternate candidate'

$r=Run-D5 $good -Budget 512
Check-D5 ($r.metrics.bytesRead -eq 512 -and $r.scanIncomplete -and $r.agreement -eq 'insufficient_evidence') '512-byte budget allows MBR only'
$r=Run-D5 $good -Budget 1024
Check-D5 ($r.metrics.bytesRead -eq 1024 -and $r.candidates[1].unknownCodes -contains 'budget.backup_unread') '1024-byte budget cannot read backup'
$r=Run-D5 $good -Budget 1536
Check-D5 ($r.metrics.bytesRead -eq 1536 -and $r.candidates[0].plausibility -eq 'insufficient_evidence') 'Missing FSInfo remains explicit'
Check-D5 ($r.status -eq 'partial' -and $null -eq $r.selectedCandidate) 'Limited budget cannot certify geometry'

$short=New-Object 'byte[]' 200
$s=Open-D5 $short
try{
    $r=Get-ChappyFatVbrDisagreement -Stream $s
    Check-D5 ($r.metrics.bytesRead -eq 200 -and $r.scanIncomplete) 'Truncated MBR actual bytes counted'
    Check-D5 ($r.mbr.reasonCodes -contains 'io.mbr_truncated' -and $r.agreement -eq 'insufficient_evidence') 'Truncated MBR lacks evidence'
}finally{$s.Dispose()}
$tooShort=New-Object 'byte[]' 4600
[Array]::Copy($good,0,$tooShort,0,$tooShort.Length)
$s=Open-D5 $tooShort
try{
    $r=Get-ChappyFatVbrDisagreement -Stream $s
    Check-D5 ($r.mbr.reasonCodes -contains 'mbr.partition_exceeds_stream') 'Declared MBR partition beyond stream rejected before VBR read'
    Check-D5 ($r.metrics.bytesRead -eq 512 -and $r.scanIncomplete) 'Truncated stream causes bounded MBR-only observation'
}finally{$s.Dispose()}
$s=Open-D5 $good
try{
    Check-D5 (Throws-D5 {Get-ChappyFatVbrDisagreement -Stream $s -MaxReadBytes 2049}) 'Over budget rejected'
    Check-D5 (Throws-D5 {Get-ChappyFatVbrDisagreement -Stream $s -MaxReadBytes 511}) 'Subsector budget rejected'
    Check-D5 (Throws-D5 {Get-ChappyFatVbrDisagreement -Stream $s -PartitionIndex 4}) 'Invalid MBR entry index rejected'
}finally{$s.Dispose()}
$w=[IO.MemoryStream]::new($good,$true)
try{Check-D5 (Throws-D5 {Get-ChappyFatVbrDisagreement -Stream $w}) 'Writable source stream refused'}
finally{$w.Dispose()}

# An artificial stream that splits every Read into 7-byte chunks; module must loop
# and still account for bytes actually returned, not the count requested.
Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class D5ShortReadStream : Stream {
    private readonly MemoryStream inner;
    public D5ShortReadStream(byte[] bytes) { inner = new MemoryStream(bytes, false); }
    public override bool CanRead { get { return true; } }
    public override bool CanWrite { get { return false; } }
    public override bool CanSeek { get { return true; } }
    public override long Length { get { return inner.Length; } }
    public override long Position { get { return inner.Position; } set { inner.Position=value; } }
    public override void Flush() { }
    public override long Seek(long offset, SeekOrigin origin) { return inner.Seek(offset, origin); }
    public override int Read(byte[] buffer, int offset, int count) { return inner.Read(buffer,offset,Math.Min(count,7)); }
    public override void SetLength(long length) { throw new NotSupportedException(); }
    public override void Write(byte[] buffer,int offset,int count) { throw new NotSupportedException(); }
}
'@
$split=New-Object D5ShortReadStream (,$good)
try{
    $r=Get-ChappyFatVbrDisagreement -Stream $split
    Check-D5 ($r.agreement -eq 'agree' -and $r.metrics.bytesRead -eq 2048) '7-byte fragmented reads preserve all observations'
    Check-D5 ($r.candidates[0].plausibility -eq 'plausible_unverified') 'Fragmented short-return reads do not corrupt candidate parsing'
}finally{$split.Dispose()}
Check-D5 ((Hash-D5 $good) -eq $hash) 'Source hash remains identical after all tests'
Write-Host "Team D R5-P1 result: $script:Pass passed; $script:Fail failed."
if($script:Fail -gt 0){exit 1}
