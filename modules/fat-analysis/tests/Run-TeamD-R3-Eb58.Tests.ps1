#Requires -Version 5.1
# Team D R3-P2 artificial fixtures only. No disk image, private data or file operations.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\Fat32Eb58Map.psm1') -Force
$script:Pass=0;$script:Fail=0
function Check-D58 {
    param([bool]$Condition,[string]$Label)
    if($Condition){Write-Host "PASS $Label";$script:Pass++}
    else{Write-Host "FAIL $Label";$script:Fail++}
}
function Throws-D58 {
    param([scriptblock]$Action)
    try{$null=& $Action;return $false}catch{return $true}
}
function Put16-D58 {
    param([byte[]]$Bytes,[int]$Pos,[uint16]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$Bytes,$Pos,2)
}
function Put32-D58 {
    param([byte[]]$Bytes,[int]$Pos,[uint32]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$Bytes,$Pos,4)
}
function New-ImageD58 {
    $b=New-Object 'byte[]' 40000
    $b[0]=0xEB;$b[1]=0x58;$b[2]=0x90
    Put16-D58 $b 11 512
    $b[13]=1
    Put16-D58 $b 14 32
    $b[16]=2
    Put32-D58 $b 36 16
    Put32-D58 $b 44 2
    $b[510]=0x55;$b[511]=0xAA
    [Text.Encoding]::ASCII.GetBytes('SYNTHETIC-NAME-PRIVATE-NO').CopyTo($b,36000)
    return ,$b
}
function PutRun-D58 {
    param([byte[]]$Bytes,[int]$Position,[int]$Pairs)
    for($i=0;$i -lt $Pairs;$i++){$Bytes[$Position+$i*2]=0xEB;$Bytes[$Position+$i*2+1]=0x58}
}
function Open-D58 {
    param([byte[]]$B)
    return [IO.MemoryStream]::new($B,$false)
}
function Hash-D58 {
    param([byte[]]$B)
    $hash=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($hash.ComputeHash($B)).Replace('-','')}
    finally{$hash.Dispose()}
}
$fat1=16384;$fat2=24576;$size=8192
$img=New-ImageD58
PutRun-D58 $img $fat1 20
PutRun-D58 $img $fat2 20
PutRun-D58 $img ($fat1+512) 5
PutRun-D58 $img ($fat2+513) 6
$h=Hash-D58 $img
$s=Open-D58 $img
try {
    $r=Get-ChappyFatEb58Map -Stream $s -VolumeOffsetBytes 0 -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $size -ProbeBytesPerFat 1024 -MaxReadBytes 2560
    Check-D58 ($r.schemaVersion -eq '1' -and $r.team -eq 'D' -and $r.mode -eq 'read_only_eb58_mapping') 'Shared interface v1 with separate EB58 mode'
    Check-D58 ($r.bootObservation.plausibleFat32Bpb -and $r.bootObservation.eb5890JumpObserved -and $r.bootObservation.bootSignatureObserved) 'Valid synthetic BPB recognized'
    Check-D58 ($r.bootObservation.bpbDerivedFat1OffsetBytes -eq $fat1 -and $r.bootObservation.bpbDerivedFat2OffsetBytes -eq $fat2) 'BPB-derived FAT offsets match independent caller positions'
    Check-D58 (-not $r.geometryComparison.suppliedOffsetsDisagreeWithBpb -and $r.geometryComparison.bpbCompared) 'Geometry agreement only, not authenticity'
    Check-D58 ($r.items[0].totalRuns -eq 2 -and $r.items[1].totalRuns -eq 2 -and $r.metrics.totalPatternRuns -eq 4) 'Both mirror copies contain two independently counted runs'
    Check-D58 ($r.items[0].observedPairs -eq 25 -and $r.items[1].observedPairs -eq 26 -and $r.metrics.totalObservedPatternPairs -eq 51) 'Total pair counts are exact'
    Check-D58 ($r.items[0].runs[0].observedPairs -eq 20 -and $r.items[0].runs[0].startsAtFatProbe) 'Repeated EB58 at actual supplied FAT start'
    Check-D58 ($r.items[0].runs[1].startOffsetBytes -eq ($fat1+512) -and $r.items[0].runs[1].alignmentModulo512 -eq 0) 'Aligned mid-FAT run located'
    Check-D58 ($r.items[1].runs[1].startOffsetBytes -eq ($fat2+513) -and $r.items[1].runs[1].alignmentModulo4 -eq 1) 'Odd byte shift captured, not mistaken for entry alignment'
    Check-D58 ($r.items[0].bootLikePrefixObserved -eq $false -and $r.items[0].runsAtProbeStart) 'Repeated EB58 is not mislabeled as EB 58 90 boot jump'
    Check-D58 ($r.status -eq 'partial' -and $r.scanIncomplete -and $r.metrics.sampledOnly) 'First 1 KiB cannot claim whole FAT verified'
    Check-D58 ($r.metrics.bytesRead -eq 2560 -and $r.metrics.fatBytesObserved -eq 2048 -and $r.metrics.maxReadBytes -eq 2560) 'Combined FAT/VBR bytes exactly accounted'
    Check-D58 ($r.warnings -contains 'pattern.observation_not_causation' -and $r.warnings -contains 'fat.mirror_agreement_not_proof_of_health') 'Corruption cause and FAT health remain undetermined'
    Check-D58 ((Hash-D58 $img) -eq $h -and $r.writePermitted -eq $false) 'Source untouched and writes never permitted'
    $json=$r|ConvertTo-Json -Depth 12
    Check-D58 ($json -notmatch 'SYNTHETIC-NAME' -and $json -notmatch 'PRIVATE-NO' -and $json -notmatch 'Sha256' -and $json -notmatch 'rawBytes') 'No raw image content or fingerprints in JSON'
}
finally{$s.Dispose()}

$clean=New-ImageD58
$s=Open-D58 $clean
try {
    $r=Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $size -ProbeBytesPerFat 512 -MaxReadBytes 1536
    Check-D58 ($r.items[0].totalRuns -eq 0 -and $r.items[1].totalRuns -eq 0) 'VBR EB 58 90 alone causes zero FAT EB58 runs'
    Check-D58 ($r.bootObservation.eb5890JumpObserved -and -not $r.items[0].bootLikePrefixObserved) 'Separate boot versus FAT observations'
}
finally{$s.Dispose()}

$bootcopy=New-ImageD58
[Array]::Copy($bootcopy,0,$bootcopy,$fat2,512)
$s=Open-D58 $bootcopy
try {
    $r=Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $size -ProbeBytesPerFat 512 -MaxReadBytes 1536
    Check-D58 ($r.items[1].bootLikePrefixObserved -and $r.items[1].bootSignatureAt510Observed) 'Boot-like signature at FAT boundary detected'
    Check-D58 ($r.items[1].bootLikeSignatureCombination -and $r.items[1].totalRuns -eq 0) 'Boot-like bytes not counted as repeated EB58 corruption'
    Check-D58 ($r.warnings -contains 'hypothesis.boot_copy_or_wrong_offset_requires_independent_check') 'Boot-copy hypothesis requires independent confirmation'
}
finally{$s.Dispose()}

$shift=New-ImageD58
PutRun-D58 $shift $fat1 32
$s=Open-D58 $shift
try {
    $r=Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes ($fat1+512) -Fat2OffsetBytes ($fat2+512) -FatLengthBytes $size -ProbeBytesPerFat 512 -MaxReadBytes 1536
    Check-D58 ($r.geometryComparison.suppliedOffsetsDisagreeWithBpb -and $r.warnings -contains 'geometry.supplied_offsets_disagree_with_bpb') 'Wrong FAT offset flagged against plausible synthetic BPB'
    Check-D58 ($r.items[0].totalRuns -eq 0 -and $r.geometryProvenance -eq 'caller_supplied_unverified') 'A wrong offset can hide a real nearby EB58 run'
}
finally{$s.Dispose()}

$small=New-ImageD58
PutRun-D58 $small $fat1 12
PutRun-D58 $small $fat2 12
$s=Open-D58 $small
try {
    $r=Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $size -ProbeBytesPerFat 1024 -MaxReadBytes 544
    Check-D58 ($r.metrics.bytesRead -eq 544 -and $r.items[0].observedBytes -eq 16 -and $r.items[1].observedBytes -eq 16) 'Small global budget divided safely between mirrors'
    Check-D58 ($r.items[0].runs[0].observedPairs -eq 8 -and $r.items[0].runs[0].reachesObservedEnd) 'Run at probe boundary marked as observed-prefix only'
}
finally{$s.Dispose()}

$cross=New-ImageD58
PutRun-D58 $cross ($fat1+4094) 10
$s=Open-D58 $cross
try{
    $r=Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $size -ProbeBytesPerFat 8192 -MaxReadBytes 16896
    Check-D58 ($r.items[0].totalRuns -eq 1 -and $r.items[0].runs[0].observedPairs -eq 10) 'Run crossing internal 4096-byte I/O boundary preserved'
    Check-D58 ($r.metrics.bytesRead -eq 16896 -and -not $r.scanIncomplete) 'Full synthetic FAT coverage correctly distinguished'
}
finally{$s.Dispose()}

$capped=New-ImageD58
for($i=0;$i -lt 10;$i++){PutRun-D58 $capped ($fat1+$i*16) 4}
$s=Open-D58 $capped
try {
    $r=Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $size -ProbeBytesPerFat 512 -MaxReadBytes 1536 -MaxReportedRunsPerFat 2
    Check-D58 ($r.items[0].totalRuns -eq 10 -and $r.items[0].omittedRuns -eq 8 -and $r.items[0].runs.Count -eq 2) 'Per-FAT run list cap and omitted count exact'
    Check-D58 ($r.items[0].evidence -contains 'report.run_list_capped' -and $r.scanIncomplete) 'Capped report never appears exhaustive'
}
finally{$s.Dispose()}

$cut=New-Object 'byte[]' ($fat2+7)
$originalCut=New-ImageD58
[Array]::Copy($originalCut,0,$cut,0,$cut.Length)
PutRun-D58 $cut $fat1 8
$s=Open-D58 $cut
try {
    $r=Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $size -ProbeBytesPerFat 512 -MaxReadBytes 1536
    Check-D58 ($r.items[1].observedBytes -eq 7 -and $r.items[1].evidence -contains 'io.truncated') 'Truncated FAT mirror reports only actual observed bytes'
    Check-D58 ($r.metrics.bytesRead -eq 1031 -and $r.scanIncomplete) 'Truncated source respects cumulative budget and partial coverage'
}
finally{$s.Dispose()}

$short=New-Object 'byte[]' 100
$s=Open-D58 $short
try{
    $r=Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $size -MaxReadBytes 512
    Check-D58 (-not $r.bootObservation.plausibleFat32Bpb -and $r.metrics.bytesRead -eq 100) 'Truncated boot has no inferred FAT32 geometry'
    Check-D58 ($r.items[0].observedBytes -eq 0 -and $r.items[1].observedBytes -eq 0 -and $r.scanIncomplete) 'Entirely missing FATs stop safely'
}
finally{$s.Dispose()}

$invalid=New-ImageD58
$writable=[IO.MemoryStream]::new($invalid,$true)
try {
    Check-D58 (Throws-D58 { Get-ChappyFatEb58Map -Stream $writable -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $size }) 'Writable input rejected'
}finally{$writable.Dispose()}
$s=Open-D58 $invalid
try{
    Check-D58 (Throws-D58 {Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes ($fat1+1) -Fat2OffsetBytes $fat2 -FatLengthBytes $size}) 'Misaligned FAT address rejected'
    Check-D58 (Throws-D58 {Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes $fat1 -Fat2OffsetBytes ($fat1+512) -FatLengthBytes $size}) 'Overlapping FAT regions rejected'
    Check-D58 (Throws-D58 {Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes $fat1 -Fat2OffsetBytes ([long]::MaxValue-3) -FatLengthBytes $size}) 'Int64 FAT offset overflow rejected'
    Check-D58 (Throws-D58 {Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $size -ProbeBytesPerFat 65537}) 'Maximum per-FAT probe budget enforced'
    Check-D58 (Throws-D58 {Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $size -MaxReadBytes 131585}) 'Maximum total read budget enforced'
    Check-D58 (Throws-D58 {Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 -FatLengthBytes $size -MaxReportedRunsPerFat 65}) 'Maximum reported run cap enforced'
    $huge=Get-ChappyFatEb58Map -Stream $s -Fat1OffsetBytes 16384 -Fat2OffsetBytes 2199023255552 -FatLengthBytes 1099511627776 -ProbeBytesPerFat 512 -MaxReadBytes 1536
    Check-D58 ($huge.metrics.bytesRead -le 1536 -and $huge.items[1].observedBytes -eq 0 -and $huge.scanIncomplete) 'Hostile huge declared geometry cannot trigger unbounded reads'
}
finally{$s.Dispose()}
Write-Host "Team D R3-P2 result: $script:Pass passed; $script:Fail failed."
if($script:Fail -gt 0){exit 1}
