#Requires -Version 5.1
# Team D R3-P3: synthetic memory-only FAT chain classification tests.
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\Fat32ChainStats.psm1') -Force
$script:Passed=0
$script:Failed=0
function Check-DChain {
    param([bool]$Condition,[string]$Name)
    if($Condition){Write-Host "PASS $Name";$script:Passed++}
    else{Write-Host "FAIL $Name";$script:Failed++}
}
function Throws-DChain {
    param([scriptblock]$Code)
    try {$null=& $Code;return $false} catch{return $true}
}
function Set-DChainEntry {
    param([byte[]]$Bytes,[int]$FatOffset,[int]$Cluster,[uint32]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$Bytes,($FatOffset+4*$Cluster),4)
}
function New-DChainImage {
    $bytes=New-Object 'byte[]' 32768
    foreach($fatOffset in @(512,4096)){
        Set-DChainEntry $bytes $fatOffset 2 3
        Set-DChainEntry $bytes $fatOffset 3 ([uint32]0xFFFFFFFF)
        Set-DChainEntry $bytes $fatOffset 10 0
        Set-DChainEntry $bytes $fatOffset 20 ([uint32]0x0FFFFFF0)
        Set-DChainEntry $bytes $fatOffset 30 ([uint32]0x0FFFFFF7)
        Set-DChainEntry $bytes $fatOffset 40 101
        Set-DChainEntry $bytes $fatOffset 50 51
        Set-DChainEntry $bytes $fatOffset 51 50
    }
    # One mirror diverges, without establishing which mirror was correct.
    Set-DChainEntry $bytes 4096 10 ([uint32]0x0FFFFFF8)
    # Canary must never appear in result or CI output.
    [Text.Encoding]::ASCII.GetBytes('SYNTHETIC-PRIVATE-CANARY').CopyTo($bytes,24576)
    return ,$bytes
}
function ReadOnly-DChain {
    param([byte[]]$Bytes)
    return New-Object System.IO.MemoryStream(,$Bytes)
}
function Hash-DChain {
    param([byte[]]$Bytes)
    $hash=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($hash.ComputeHash($Bytes)).Replace('-','')}
    finally {$hash.Dispose()}
}
# Use explicit readonly MemoryStream overload; default MemoryStream(byte[]) is writable.
function Open-DChainRO {
    param([byte[]]$Bytes)
    return [System.IO.MemoryStream]::new($Bytes,$false)
}
$starts=[long[]]@(2,10,20,30,40,50,0)
$img=New-DChainImage
$sha=Hash-DChain $img
$s=Open-DChainRO $img
try {
    $r=Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -StartClusters $starts -MaxStepsPerChain 8 -MaxTotalEntries 100 -MaxReadBytes 400
    Check-DChain ($r.schemaVersion -eq '1' -and $r.team -eq 'D' -and $r.status -eq 'ok' -and -not $r.scanIncomplete) 'Interface v1 complete sampled trace output'
    Check-DChain ($r.mode -eq 'read_only_chain_anomaly_statistics' -and -not $r.writePermitted) 'Read-only analysis explicitly prohibits writes'
    Check-DChain ($r.geometryProvenance -eq 'caller_supplied_unverified' -and $r.warnings -contains 'coverage.sampled_chains_not_whole_fat') 'Geometry and scope uncertainty always disclosed'
    Check-DChain ($r.metrics.entriesChecked -eq 16 -and $r.metrics.bytesRead -eq 64) 'Each FAT entry read is four bytes with exact total'
    Check-DChain ($r.metrics.resolvedTraces -eq 14 -and $r.metrics.incompleteTraces -eq 0) 'Two mirrors complete all seven requested start traces'
    Check-DChain ($r.copies[0].terminalCounts.eoc -eq 1 -and $r.copies[1].terminalCounts.eoc -eq 2) 'EOC classification correct, including masked high nibble'
    Check-DChain ($r.copies[0].terminalCounts.free -eq 1 -and $r.copies[1].terminalCounts.free -eq 0) 'Free link classification and mirror disagreement'
    Check-DChain ($r.copies[0].terminalCounts.reserved -eq 1 -and $r.copies[1].terminalCounts.reserved -eq 1) 'Reserved FAT32 link classification'
    Check-DChain ($r.copies[0].terminalCounts.bad_cluster -eq 1 -and $r.copies[1].terminalCounts.bad_cluster -eq 1) 'Bad cluster marker distinguished from reserved range'
    Check-DChain ($r.copies[0].terminalCounts.out_of_range -eq 1 -and $r.copies[1].terminalCounts.out_of_range -eq 1) 'Data-region out-of-range link'
    Check-DChain ($r.copies[0].terminalCounts.cycle -eq 1 -and $r.copies[1].terminalCounts.cycle -eq 1) 'Two-link cycle detected with no infinite walk'
    Check-DChain ($r.copies[0].terminalCounts.invalid_start -eq 1 -and $r.copies[1].terminalCounts.invalid_start -eq 1) 'Invalid start rejected without reading FAT'
    Check-DChain ($r.metrics.anomalousResolvedTraces -eq 11 -and $r.metrics.anomalyRateAmongResolvedTracesPercent -eq 78.57) 'Anomaly ratio is explicitly over traced starts only'
    Check-DChain ($r.metrics.comparableMirrorTerminals -eq 7 -and $r.metrics.differentMirrorTerminals -eq 1) 'Both mirror terminal categories compared without choosing correct one'
    Check-DChain ($r.copies[0].bytesRead -eq 32 -and $r.copies[1].bytesRead -eq 32) 'Read budget accounted separately for each mirror'
    Check-DChain ((Hash-DChain $img) -eq $sha) 'Entire artificial input SHA256 unchanged after analysis'
    $json=$r|ConvertTo-Json -Depth 12
    Check-DChain ($json -notmatch 'SYNTHETIC-PRIVATE-CANARY' -and $json -notmatch 'rawBytes' -and $json -notmatch 'Sha256' -and $json -notmatch 'localPath') 'JSON contains no raw sample, input fingerprint or private text'
}
finally {$s.Dispose()}

$small=New-DChainImage
$s=Open-DChainRO $small
try {
    $r=Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -StartClusters ([long[]]@(2,50)) -MaxStepsPerChain 1
    Check-DChain ($r.scanIncomplete -and $r.status -eq 'partial' -and $r.metrics.incompleteTraces -eq 4) 'Step cap marks traversals incomplete'
    Check-DChain ($r.copies[0].terminalCounts.step_limit -eq 2 -and $r.copies[1].terminalCounts.step_limit -eq 2) 'Step budget enforced independently on both FATs'
    Check-DChain ($r.metrics.entriesChecked -eq 4 -and $r.metrics.bytesRead -eq 16) 'Step-limited reads counted exactly'
}
finally {$s.Dispose()}

$s=Open-DChainRO (New-DChainImage)
try {
    $r=Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -StartClusters ([long[]]@(2,10)) -MaxTotalEntries 2 -MaxReadBytes 8
    Check-DChain ($r.metrics.entriesChecked -eq 2 -and $r.metrics.bytesRead -eq 8 -and $r.scanIncomplete) 'Global entry and byte budgets never exceeded'
    Check-DChain ($r.copies[0].entriesRead -eq 1 -and $r.copies[1].entriesRead -eq 1) 'Mirrors get fair hard quotas; FAT1 cannot starve FAT2'
    Check-DChain ($r.copies[0].terminalCounts.read_budget -eq 2 -and $r.copies[1].terminalCounts.read_budget -eq 2) 'Incomplete outcomes expose budget exhaustion reason'
    Check-DChain ($r.metrics.comparableMirrorTerminals -eq 0 -and $r.metrics.differentMirrorTerminals -eq 0) 'Unresolved traces not falsely compared'
}
finally {$s.Dispose()}

$trunc=New-Object 'byte[]' 4300
$full=New-DChainImage
[Array]::Copy($full,0,$trunc,0,$trunc.Length)
$s=Open-DChainRO $trunc
try {
    $r=Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -StartClusters ([long[]]@(2,50,70)) -MaxStepsPerChain 8 -MaxTotalEntries 50 -MaxReadBytes 200
    Check-DChain ($r.scanIncomplete -and $r.status -eq 'partial' -and $r.copies[1].terminalCounts.truncated -eq 1) 'Truncation at high index of second FAT is incomplete'
    Check-DChain ($r.metrics.bytesRead -le 200 -and $r.copies[0].entriesRead -gt 0) 'Truncation keeps other mirror samples and never exceeds budget'
}
finally {$s.Dispose()}

$s=Open-DChainRO (New-DChainImage)
try {
    $r=Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1099511627776 -FatLengthBytes 1099511627776 -MaxDataCluster 100 -StartClusters ([long[]]@(2)) -MaxTotalEntries 2 -MaxReadBytes 8
    Check-DChain ($r.scanIncomplete -and $r.copies[1].terminalCounts.truncated -eq 1 -and $r.metrics.bytesRead -le 8) 'Huge declared FAT geometry stops safely on absent mirror'
}
finally {$s.Dispose()}

$s=Open-DChainRO (New-DChainImage)
try {
    # Reserved value 1, 0x0FFFFFF6, and upper nibble masked 0xF0000000.
    $v=New-DChainImage
    Set-DChainEntry $v 512 10 1
    Set-DChainEntry $v 4096 10 ([uint32]0x0FFFFFF6)
    $s.Dispose();$s=Open-DChainRO $v
    $r=Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -StartClusters ([long[]]@(10))
    Check-DChain ($r.copies[0].terminalCounts.reserved -eq 1 -and $r.copies[1].terminalCounts.reserved -eq 1) 'Both reserved entry classes detected'
    $v2=New-DChainImage
    Set-DChainEntry $v2 512 10 ([uint32]0xF0000000)
    $s.Dispose();$s=Open-DChainRO $v2
    $r=Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -StartClusters ([long[]]@(10))
    Check-DChain ($r.copies[0].terminalCounts.free -eq 1) 'Reserved upper nibble masked before classification'
}
finally {$s.Dispose()}

$writable=[System.IO.MemoryStream]::new((New-DChainImage),$true)
try {
    Check-DChain (Throws-DChain {Get-ChappyFatChainAnomalyStats -Stream $writable -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100}) 'Writable stream strictly rejected'
}
finally {$writable.Dispose()}
$s=Open-DChainRO (New-DChainImage)
try {
    Check-DChain (Throws-DChain {Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 513 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100}) 'Unaligned FAT range rejected'
    Check-DChain (Throws-DChain {Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1024 -FatLengthBytes 1024 -MaxDataCluster 100}) 'Overlapping FAT ranges rejected'
    Check-DChain (Throws-DChain {Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes ([long]::MaxValue-3) -FatLengthBytes 1024 -MaxDataCluster 100}) 'FAT offset overflow rejected'
    Check-DChain (Throws-DChain {Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 12 -MaxDataCluster 100}) 'Impossible entry count geometry rejected'
    Check-DChain (Throws-DChain {Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 268435440}) 'Maximum data cluster beyond FAT32 valid data range rejected'
    Check-DChain (Throws-DChain {Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -StartClusters ([long[]]@(2,2))}) 'Repeated start clusters rejected as statistical bias'
    Check-DChain (Throws-DChain {Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -MaxReadBytes 16385}) 'Global maximum read bytes capped'
    Check-DChain (Throws-DChain {Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -MaxTotalEntries 4097}) 'Global maximum entry observations capped'
    Check-DChain (Throws-DChain {Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -MaxStepsPerChain 513}) 'Per-chain maximum step cap enforced'
    Check-DChain (Throws-DChain {Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 4096 -FatLengthBytes 1024 -MaxDataCluster 100 -StartClusters ([long[]](0..16))}) 'More than 16 requested starts rejected'
}
finally {$s.Dispose()}
Write-Host "Team D R3-P3 result: $script:Passed passed; $script:Failed failed."
if($script:Failed -gt 0) {exit 1}
