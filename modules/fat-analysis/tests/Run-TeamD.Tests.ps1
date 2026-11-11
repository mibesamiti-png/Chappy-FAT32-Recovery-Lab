#Requires -Version 5.1
# Self-contained Windows PowerShell 5.1 tests. Creates only artificial images.
param([switch]$KeepFixtures)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\Fat32ReadOnly.psm1') -Force
$script:Passed=0; $script:Failed=0
function Assert-D { param([bool]$Condition,[string]$Label)
    if ($Condition) { Write-Host "PASS $Label"; $script:Passed++ }
    else { Write-Host "FAIL $Label"; $script:Failed++ }
}
function Put-U16 {param([byte[]]$B,[int]$P,[uint16]$Value)
    $x=[BitConverter]::GetBytes($Value); [Array]::Copy($x,0,$B,$P,2)
}
function Put-U32 {param([byte[]]$B,[int]$P,[uint32]$Value)
    $x=[BitConverter]::GetBytes($Value); [Array]::Copy($x,0,$B,$P,4)
}
function Write-Bytes {param([System.IO.FileStream]$S,[long]$Offset,[byte[]]$B)
    [void]$S.Seek($Offset,[IO.SeekOrigin]::Begin);$S.Write($B,0,$B.Length)
}
function New-TestImage {
    param([string]$Path,[long]$VolumeOffset=0,[switch]$Mbr)
    # 64 MiB volume, sparse file. 128,992 data clusters => FAT32 by cluster count.
    $bytes=512; $sectors=131072; $fatSectors=1024; $reserved=32
    $length=$VolumeOffset+[long]$sectors*$bytes
    $s=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $s.SetLength($length)
        $boot=New-Object 'byte[]' 512
        $boot[0]=0xEB;$boot[1]=0x58;$boot[2]=0x90
        [Text.Encoding]::ASCII.GetBytes('MSWIN4.1').CopyTo($boot,3)
        Put-U16 $boot 11 512; $boot[13]=1; Put-U16 $boot 14 $reserved
        $boot[16]=2; $boot[21]=0xF8; Put-U32 $boot 32 $sectors
        Put-U32 $boot 36 $fatSectors;Put-U32 $boot 44 2
        Put-U16 $boot 48 1;Put-U16 $boot 50 6
        $boot[66]=0x29;[Text.Encoding]::ASCII.GetBytes('FAT32   ').CopyTo($boot,82)
        $boot[510]=0x55;$boot[511]=0xAA
        Write-Bytes $s $VolumeOffset $boot
        Write-Bytes $s ($VolumeOffset+6*512) $boot
        $info=New-Object 'byte[]' 512
        Put-U32 $info 0 0x41615252;Put-U32 $info 484 0x61417272
        Put-U32 $info 488 ([uint32]::MaxValue);Put-U32 $info 492 ([uint32]::MaxValue)
        Put-U32 $info 508 ([Convert]::ToUInt32('AA550000',16))
        Write-Bytes $s ($VolumeOffset+512) $info
        $fat=New-Object 'byte[]' 512
        Put-U32 $fat 0 0x0FFFFFF8; Put-U32 $fat 4 0x0FFFFFFF
        Put-U32 $fat 8 0x0FFFFFFF; Put-U32 $fat 12 0x0FFFFFFF
        $fat1=$VolumeOffset+$reserved*512
        $fat2=$fat1+$fatSectors*512
        Write-Bytes $s $fat1 $fat; Write-Bytes $s $fat2 $fat
        $dir=New-Object 'byte[]' 512
        [Text.Encoding]::ASCII.GetBytes('MODEL   GCO').CopyTo($dir,0)
        $dir[11]=0x20;Put-U16 $dir 26 3;Put-U32 $dir 28 100
        Write-Bytes $s ($VolumeOffset+($reserved+2*$fatSectors)*512) $dir
        if ($Mbr) {
            $m=New-Object 'byte[]' 512
            $m[446+4]=0x0C
            Put-U32 $m (446+8) ([uint32]($VolumeOffset/512))
            Put-U32 $m (446+12) ([uint32]$sectors)
            $m[510]=0x55;$m[511]=0xAA
            Write-Bytes $s 0 $m
        }
    } finally { $s.Dispose() }
}
function Change-Bytes {param([string]$Path,[long]$Offset,[byte[]]$Data)
    $s=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{Write-Bytes $s $Offset $Data} finally{$s.Dispose()}
}
function Has-Finding {param($Report,[string]$Code)
    return (@($Report.Findings | Where-Object {$_.Code -eq $Code}).Count -gt 0)
}
$base=Join-Path ([IO.Path]::GetTempPath()) ('ChappyTeamD_SYNTHETIC_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($base)
try {
    $img=Join-Path $base 'healthy.img'
    New-TestImage $img
    $original=(Get-FileHash -LiteralPath $img -Algorithm SHA256).Hash
    $good=Get-TeamDFat32Diagnostic -ImagePath $img -IncludePrivateMetadata
    Assert-D ($null -ne $good.SelectedBoot -and $good.SelectedBoot.VolumeOffset -eq 0) 'Superfloppy VBR offset 0 recognized'
    Assert-D ($good.FatHeaders.Count -eq 2 -and $good.FatHeaders[0].ReservedEntriesValid -and $good.FatHeaders[1].ReservedEntriesValid) 'Both FAT headers valid'
    Assert-D ($good.FatComparison.Complete -and $good.FatComparison.DifferentBytes -eq 0) 'FAT1 == FAT2 full comparison'
    Assert-D ($good.RootChain.StopReason -eq 'EndOfChain') 'Healthy root chain terminates'
    Assert-D ($good.RootDirectory.Entries[0].Name -eq 'MODEL   GCO' -and $good.RootDirectory.Entries[0].FatState -eq 'AllocatedOrChained') 'Root directory and FAT cross-validation'
    Assert-D ($good.FsInfo.SignaturesValid -and $good.BackupBoot.BPBFieldsIdentical) 'FSInfo and backup BPB verification'
    Assert-D (-not (Has-Finding $good 'EB58_REPEATED')) 'EB 58 90 in real boot does NOT trigger FAT anomaly'
    Assert-D ($original -eq (Get-FileHash -LiteralPath $img -Algorithm SHA256).Hash) 'Diagnosis does not mutate image'
    $reportPath=Join-Path $base 'report.json'
    $null=Export-TeamDFat32Diagnostic -ImagePath $img -ReportPath $reportPath
    $json=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    Assert-D ($json.Image.Path -eq '<redacted>' -and $null -eq $json.RootDirectory.Entries[0].Name) 'Default report redacts private IMG paths and names'
    $contract=Get-ChappyFatDiagnostics -ImagePath $img
    Assert-D ($contract.team -eq 'D' -and $contract.schemaVersion -eq '1' -and $contract.metrics.bytesRead -gt 0) 'Team A v1 integration contract'
    Assert-D ($json.Mode -eq 'READ_ONLY' -and $json.WritePermitted -eq $false) 'JSON report declares read-only'
    $blocked=$false
    try { $null=Export-TeamDFat32Diagnostic -ImagePath $img -ReportPath $img } catch {$blocked=$true}
    Assert-D $blocked 'Report cannot overwrite input image'
    $bad=Join-Path $base 'eb58.img';[IO.File]::Copy($img,$bad)
    $repeat=New-Object 'byte[]' 32;for($i=0;$i -lt 32;$i+=2) {$repeat[$i]=0xEB;$repeat[$i+1]=0x58}
    Change-Bytes $bad (32*512) $repeat
    Change-Bytes $bad ((32+1024)*512) $repeat
    $corrupt=Get-TeamDFat32Diagnostic -ImagePath $bad
    Assert-D (Has-Finding $corrupt 'EB58_REPEATED') 'EB 58 repeated data at FAT detected'
    Assert-D (Has-Finding $corrupt 'IDENTICAL_CORRUPTION_POSSIBLE') 'Identical FAT corruption not declared healthy'
    Assert-D ($corrupt.FatComparison.DifferentBytes -eq 0 -and $corrupt.RepairCandidates.Count -gt 0) 'Matching invalid FATs generate only evidence-gathering candidates'
    $diff=Join-Path $base 'different.img';[IO.File]::Copy($img,$diff)
    Change-Bytes $diff ((32+1024)*512+8) ([byte[]](0,0,0,0))
    $d=Get-TeamDFat32Diagnostic -ImagePath $diff
    Assert-D (Has-Finding $d 'FATS_DIFFER') 'FAT mirror byte difference discovered'
    Assert-D ($d.RootChains.Count -eq 2 -and $d.RootChains[1].StopReason -eq 'UnexpectedFree') 'FAT-specific root chain comparison'
    $cyclic=Join-Path $base 'cycle.img';[IO.File]::Copy($img,$cyclic)
    Change-Bytes $cyclic (32*512+8) ([BitConverter]::GetBytes([uint32]3))
    Change-Bytes $cyclic (32*512+12) ([BitConverter]::GetBytes([uint32]2))
    $loop=Get-TeamDFat32Diagnostic -ImagePath $cyclic
    Assert-D ($loop.RootChain.StopReason -eq 'Loop') 'Cyclic root chain stops safely'
    $outRange=Join-Path $base 'out_of_range.img';[IO.File]::Copy($img,$outRange)
    Change-Bytes $outRange (32*512+8) ([BitConverter]::GetBytes([uint32]200000))
    $out=Get-TeamDFat32Diagnostic -ImagePath $outRange
    Assert-D ($out.RootChain.StopReason -eq 'NextOutOfRange') 'Out-of-range FAT link stops safely'
    $limited=Get-TeamDFat32Diagnostic -ImagePath $img -MaxFatCompareBytes 4096
    Assert-D (-not $limited.FatComparison.Complete -and $limited.FatComparison.ComparedBytes -eq 4096) 'FAT comparison byte cap is explicit'
    $offset=Join-Path $base 'mbr_partition.img' 
    New-TestImage $offset 1048576 -Mbr
    $part=Get-TeamDFat32Diagnostic -ImagePath $offset
    Assert-D ($part.SelectedBoot.VolumeOffset -eq 1048576) 'MBR partition offset detection'
    Assert-D ($part.FatHeaders[0].ReservedEntriesValid) 'Partition-relative FAT location correct'
    $zero=Join-Path $base 'no_bpb.img';[IO.File]::WriteAllBytes($zero,(New-Object 'byte[]' 4096))
    $empty=Get-TeamDFat32Diagnostic -ImagePath $zero
    Assert-D (Has-Finding $empty 'NO_TRUSTED_GEOMETRY') 'Invalid geometry stops FAT offset interpretation'
    $short=Join-Path $base 'truncated.img';[IO.File]::Copy($img,$short)
    $ts=[IO.File]::Open($short,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$ts.SetLength(1048576)} finally {$ts.Dispose()}
    $truncated=Get-TeamDFat32Diagnostic -ImagePath $short
    Assert-D (Has-Finding $truncated 'NO_TRUSTED_GEOMETRY') 'Truncated volume stops FAT decoding'
    $blockedDevice=$false
    try {$null=Get-TeamDFat32Diagnostic -ImagePath '\\.\PhysicalDrive2'} catch {$blockedDevice=$true}
    Assert-D $blockedDevice 'Raw PhysicalDrive access rejected'
    Write-Host "Team D result: $script:Passed passed, $script:Failed failed"
    if ($script:Failed -gt 0) {exit 1}
} finally {
    if ($KeepFixtures) {Write-Host "Synthetic fixtures kept: $base"}
    else {[IO.Directory]::Delete($base,$true)}
}