#requires -Version 5.1
<#
Synthetic-only smoke tests for read-only FAT32 QuickProbe.
Creates two disposable ~2MiB disk images in the system TEMP folder.
Never opens a real microSD or user-provided IMG.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ("ChappyQuickProbeTest_" + [guid]::NewGuid().ToString('N'))
$probe = Join-Path (Split-Path -Parent $PSScriptRoot) 'legacy\Chappy_FAT32_QuickProbe_v0.5.1.ps1'
function Put-U16([byte[]]$b,[int]$at,[int]$value) {
    [Array]::Copy([BitConverter]::GetBytes([uint16]$value),0,$b,$at,2)
}
function Put-U32([byte[]]$b,[int]$at,[uint32]$value) {
    [Array]::Copy([BitConverter]::GetBytes($value),0,$b,$at,4)
}
function Write-At([IO.FileStream]$file,[long]$offset,[byte[]]$bytes) {
    [void]$file.Seek($offset,[IO.SeekOrigin]::Begin)
    $file.Write($bytes,0,$bytes.Length)
}
function Make-Fixture([string]$path,[bool]$corrupt) {
    $partLba=1L
    $partSectors=4095L
    $reserved=32L
    $fatSectors=40L
    $bytes=($partLba+$partSectors)*512L
    $fat1=($partLba+$reserved)*512L
    $fat2=$fat1+$fatSectors*512L
    $dataStart=$fat2+$fatSectors*512L
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $stream.SetLength($bytes)
        $mbr=New-Object byte[] 512
        $mbr[450]=12
        Put-U32 $mbr 454 ([uint32]$partLba)
        Put-U32 $mbr 458 ([uint32]$partSectors)
        $mbr[510]=0x55; $mbr[511]=0xAA
        Write-At $stream 0L $mbr
        $boot=New-Object byte[] 512
        $boot[0]=0xEB; $boot[1]=0x58; $boot[2]=0x90
        Put-U16 $boot 11 512
        $boot[13]=1
        Put-U16 $boot 14 ([int]$reserved)
        $boot[16]=2
        Put-U32 $boot 32 ([uint32]$partSectors)
        Put-U32 $boot 36 ([uint32]$fatSectors)
        Put-U32 $boot 44 ([uint32]2)
        $boot[510]=0x55; $boot[511]=0xAA
        Write-At $stream ($partLba*512L) $boot
        $fat=New-Object byte[] ([int]($fatSectors*512L))
        if ($corrupt) {
            # Raw bytes EB 58 EB 58; masked FAT32 value becomes 0x08EB58EB.
            Put-U32 $fat 0 ([uint32]0x58EB58EB)
            Put-U32 $fat 4 ([uint32]0x0FFFFFFF)
            Put-U32 $fat 8 ([uint32]0x58EB58EB)
        } else {
            Put-U32 $fat 0 ([uint32]0x0FFFFFF8)
            Put-U32 $fat 4 ([uint32]0x0FFFFFFF)
            Put-U32 $fat 8 ([uint32]0x0FFFFFFF)
        }
        Write-At $stream $fat1 $fat
        Write-At $stream $fat2 $fat
        $root=New-Object byte[] 512
        [Array]::Copy([Text.Encoding]::ASCII.GetBytes('README  TXT'),0,$root,0,11)
        $root[11]=0x20
        Write-At $stream $dataStart $root
    } finally {
        $stream.Dispose()
    }
}
function Assert-Probe([string]$path,[bool]$corrupt) {
    $before=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $out=(& $probe -ImagePath $path 2>&1 | Out-String)
    if ($out -match 'STOPPED:' -or $out -notmatch 'DONE\. No image writes') {
        throw "Probe failed on synthetic input: $out"
    }
    if ($out -notmatch 'FAT1/FAT2 first 32 bytes identical: True') { throw 'FAT mirror comparison failed' }
    if ($out -notmatch 'Root directory first 512 bytes all zero: False') { throw 'Directory probe failed' }
    if ($corrupt) {
        if (([regex]::Matches($out,'reserved entries plausible: False')).Count -ne 2) {
            throw "Corrupt FAT was not recognized twice: $out"
        }
        if (([regex]::Matches($out,'Root-chain entry: 0x08EB58EB')).Count -ne 2) {
            throw "Synthetic corrupt root chain was not reported twice: $out"
        }
    } else {
        if (([regex]::Matches($out,'reserved entries plausible: True')).Count -ne 2) {
            throw "Valid FAT did not pass twice: $out"
        }
    }
    $after=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($before -ne $after) { throw 'Source IMG changed during read-only probe' }
    Write-Host "PASS: $(if($corrupt){'corrupted'}else{'valid'}) fixture, FAT semantics and SHA-256 unchanged"
}
try {
    if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw "Missing probe $probe" }
    [void][IO.Directory]::CreateDirectory($root)
    $valid=Join-Path $root 'synthetic_valid.img'
    $corrupt=Join-Path $root 'synthetic_corrupt.img'
    Make-Fixture $valid $false
    Make-Fixture $corrupt $true
    Assert-Probe $valid $false
    Assert-Probe $corrupt $true
    Write-Host 'PASS: Synthetic QuickProbe test suite completed.'
} finally {
    if (Test-Path -LiteralPath $root -PathType Container) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}