#Requires -Version 5.1
# R3-P1 synthetic-only regional FAT mirror tests. No local paths or physical IMG are opened.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\Fat32MirrorWindows.psm1') -Force
$script:Passed=0;$script:Failed=0
function Assert-D3 {
    param([bool]$Result,[string]$Name)
    if($Result){Write-Host "PASS $Name";$script:Passed++}
    else{Write-Host "FAIL $Name";$script:Failed++}
}
function Throws-D3 {
    param([scriptblock]$Action)
    try { $null=& $Action;return $false }catch{return $true}
}
function Set-D3Entry {
    param([byte[]]$Buffer,[int]$FatOffset,[int]$Entry,[uint32]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$Buffer,($FatOffset+$Entry*4),4)
}
function New-D3Fixture {
    $b=New-Object 'byte[]' 4096
    for($i=0;$i -lt 64;$i++){
        $v=[uint32]($i*3+1)
        Set-D3Entry $b 512 $i $v
        Set-D3Entry $b 1024 $i $v
    }
    [Text.Encoding]::ASCII.GetBytes('SYNTHETIC-NOT-A-FILENAME').CopyTo($b,3500)
    return ,$b
}
function New-D3Readonly {
    param([byte[]]$Buffer)
    return [System.IO.MemoryStream]::new($Buffer,$false)
}
function Hash-D3 {
    param([byte[]]$Buffer)
    $h=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($h.ComputeHash($Buffer)).Replace('-','')}
    finally{$h.Dispose()}
}

$img=New-D3Fixture;$original=Hash-D3 $img
$s=New-D3Readonly $img
try {
    $r=Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1024 -FatLengthBytes 256 -WindowEntries 8 -MaxWindows 8 -MaxReadBytes 512
    Assert-D3 ($r.status -eq 'ok' -and -not $r.scanIncomplete -and $r.metrics.wholeFatCompared) 'Full FAT coverage marked only when all entries observed'
    Assert-D3 ($r.metrics.entriesChecked -eq 64 -and $r.metrics.equalEntries -eq 64 -and $r.metrics.differentEntries -eq 0) 'Equal FAT copies count all 64 entries'
    Assert-D3 ($r.metrics.bytesRead -eq 512 -and $r.items.Count -eq 8) 'Read count is cumulative for both FATs'
    Assert-D3 ($r.warnings -contains 'mirror_agreement_does_not_establish_health') 'Equal FATs are not certified healthy'
    Assert-D3 ($r.writePermitted -eq $false -and $r.geometryProvenance -eq 'caller_supplied_unverified') 'Read-only output keeps geometry provenance uncertain'
    Assert-D3 ($r.schemaVersion -eq '1' -and $r.team -eq 'D' -and $r.items[0].confidence -eq 'verified') 'Shared v1 metadata and per-window checked confidence'
    Assert-D3 ((Hash-D3 $img) -eq $original) 'Read-only FAT mirror comparison did not alter byte array'
    $json=$r|ConvertTo-Json -Depth 8
    Assert-D3 ($json -notmatch 'SYNTHETIC-NOT-A-FILENAME' -and $json -notmatch 'PRIVATE' -and $json -notmatch 'Sha256' -and $json -notmatch 'samples') 'JSON excludes raw bytes, sample content, and hashes'
}
finally {$s.Dispose()}

$bad=New-D3Fixture
Set-D3Entry $bad 1024 12 ([uint32]38)
Set-D3Entry $bad 1024 63 ([uint32]0x00070000)
$before=Hash-D3 $bad
$s=New-D3Readonly $bad
try {
    $r=Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1024 -FatLengthBytes 256 -WindowEntries 8 -MaxWindows 8 -MaxReadBytes 512
    Assert-D3 ($r.metrics.differentEntries -eq 2 -and $r.metrics.equalEntries -eq 62) 'Mismatches in distant regions counted independently'
    Assert-D3 ($r.metrics.differingBytes -eq 3 -and $r.items[1].differentEntries -eq 1 -and $r.items[7].differentEntries -eq 1) 'Differing byte count and window localization exact'
    Assert-D3 ($r.status -eq 'ok' -and $r.warnings -contains 'fat.mirror_disagreement_no_winner_inferred') 'Full comparison does not select correct FAT'
    $first=Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1024 -FatLengthBytes 256 -WindowEntries 8 -MaxWindows 1 -MaxReadBytes 512
    Assert-D3 ($first.metrics.differentEntries -eq 0 -and $first.scanIncomplete -and $first.metrics.comparisonCoveragePercent -eq 12.5) 'First 32-byte match is only 12.5 percent of FAT'
    $budget=Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1024 -FatLengthBytes 256 -WindowEntries 8 -MaxWindows 8 -MaxReadBytes 16
    Assert-D3 ($budget.metrics.entriesChecked -eq 2 -and $budget.metrics.bytesRead -eq 16 -and $budget.scanIncomplete) 'Cumulative byte budget stops partial window'
    Assert-D3 ($budget.items[0].evidence -contains 'budget.byte_limit') 'Budget-limited range is explicitly marked'
    $sample=Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1024 -FatLengthBytes 256 -WindowEntries 8 -StrideEntries 16 -MaxWindows 4 -MaxReadBytes 512
    Assert-D3 ($sample.metrics.entriesChecked -eq 32 -and $sample.metrics.comparisonCoveragePercent -eq 50 -and $sample.scanIncomplete) 'Sparse non-overlap sampling reports 50 percent coverage'
    Assert-D3 ((Hash-D3 $bad) -eq $before) 'Divergent synthetic source unchanged'
    $wrong=Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1028 -FatLengthBytes 256 -WindowEntries 8 -MaxWindows 1 -MaxReadBytes 512
    Assert-D3 ($wrong.metrics.differentEntries -gt 0 -and $wrong.geometryProvenance -eq 'caller_supplied_unverified') 'Misleading aligned offset remains unverified'
}
finally {$s.Dispose()}

$short=New-Object 'byte[]' 1200
$valid=New-D3Fixture
[Array]::Copy($valid,0,$short,0,$short.Length)
$s=New-D3Readonly $short
try {
    $r=Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1024 -FatLengthBytes 256 -WindowEntries 8 -MaxWindows 8 -MaxReadBytes 512
    Assert-D3 ($r.scanIncomplete -and $r.status -eq 'partial' -and $r.metrics.entriesChecked -eq 44) 'Truncated mirror never counted beyond actual length'
    Assert-D3 ($r.items[$r.items.Count-1].evidence -contains 'io.range_truncated') 'Truncated range exposes diagnostic reason'
    Assert-D3 ($r.metrics.bytesRead -le $r.metrics.readByteBudget) 'Even truncated reads stay within cumulative limit'
}
finally {$s.Dispose()}

$plain=New-D3Fixture
$writable=[System.IO.MemoryStream]::new($plain,$true)
try {Assert-D3 (Throws-D3 {Get-ChappyFatMirrorWindows -Stream $writable -Fat1OffsetBytes 512 -Fat2OffsetBytes 1024 -FatLengthBytes 256}) 'Writable input stream rejected'}
finally {$writable.Dispose()}
$s=New-D3Readonly $plain
try {
    Assert-D3 (Throws-D3 {Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 513 -Fat2OffsetBytes 1024 -FatLengthBytes 256}) 'Misaligned FAT offset rejected'
    Assert-D3 (Throws-D3 {Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 700 -FatLengthBytes 256}) 'Overlapping FAT regions rejected'
    Assert-D3 (Throws-D3 {Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1024 -FatLengthBytes 256 -WindowEntries 8 -StrideEntries 4}) 'Overlapping sampled windows rejected'
    Assert-D3 (Throws-D3 {Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1024 -FatLengthBytes 256 -MaxWindows 65}) 'Window count cap enforced'
    Assert-D3 (Throws-D3 {Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1024 -FatLengthBytes 256 -MaxReadBytes 1048577}) 'Cumulative byte budget maximum enforced'
    Assert-D3 (Throws-D3 {Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1024 -FatLengthBytes 256 -StartEntry 64}) 'Start beyond declared FAT fails safe'
    Assert-D3 (Throws-D3 {Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes ([long]::MaxValue-3) -FatLengthBytes 256}) 'Int64 offset overflow rejected before reads'
    Assert-D3 (Throws-D3 {Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1024 -FatLengthBytes 10}) 'Non-aligned FAT size rejected'
    $huge=Get-ChappyFatMirrorWindows -Stream $s -Fat1OffsetBytes 512 -Fat2OffsetBytes 1099511628288 -FatLengthBytes 1099511627776 -WindowEntries 8 -MaxWindows 8 -MaxReadBytes 512
    Assert-D3 ($huge.scanIncomplete -and $huge.metrics.entriesChecked -eq 0 -and $huge.metrics.bytesRead -le 512) 'Huge declared geometry with absent mirror stops bounded'
    Assert-D3 ($huge.metrics.fatEntriesDeclared -eq 274877906944 -and $huge.metrics.wholeFatCompared -eq $false) 'Huge declared size does not imply checked contents'
}
finally {$s.Dispose()}
Write-Host "Team D R3-P1 result: $script:Passed passed, $script:Failed failed."
if ($script:Failed -gt 0) {exit 1}
