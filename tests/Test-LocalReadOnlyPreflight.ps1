#Requires -Version 5.1
<#
Artificial temporary .img regression for the opt-in read-only A preflight.
Never reads any actual device, user backup or master IMG.
#>
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cli=Join-Path $repo 'runner\Invoke-ChappyLocalReadOnlyPreflight.ps1'
$dir=Join-Path ([IO.Path]::GetTempPath()) ('ChappyA_Synthetic_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($dir)
function Put-U16A([byte[]]$B,[int]$At,[uint16]$Value) {
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$B,$At,2)
}
function Put-U32A([byte[]]$B,[int]$At,[uint32]$Value) {
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$B,$At,4)
}
function Write-AtA([IO.Stream]$S,[long]$At,[byte[]]$Bytes) {
    [void]$S.Seek($At,[IO.SeekOrigin]::Begin)
    $S.Write($Bytes,0,$Bytes.Length)
}
function Assert-A([bool]$Ok,[string]$Message) {
    if(-not $Ok){throw "FAIL: $Message"}
    Write-Host "PASS: $Message"
}
function Throws-A([scriptblock]$Block) {
    try { $null=& $Block;return $false } catch {return $true}
}
function New-ArtificialImageA([string]$Path) {
    $s=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $s.SetLength(2097152L)
        $mbr=New-Object 'byte[]' 512
        $mbr[450]=0x0C
        Put-U32A $mbr 454 ([uint32]1)
        Put-U32A $mbr 458 ([uint32]4095)
        $mbr[510]=0x55;$mbr[511]=0xAA
        Write-AtA $s 0 $mbr
        $boot=New-Object 'byte[]' 512
        $boot[0]=0xEB;$boot[1]=0x58;$boot[2]=0x90
        Put-U16A $boot 11 ([uint16]512)
        $boot[13]=1
        Put-U16A $boot 14 ([uint16]32)
        $boot[16]=2;$boot[21]=0xF8
        Put-U32A $boot 32 ([uint32]4095)
        Put-U32A $boot 36 ([uint32]40)
        Put-U32A $boot 44 ([uint32]2)
        $boot[510]=0x55;$boot[511]=0xAA
        Write-AtA $s 512 $boot
        $fat=New-Object 'byte[]' 20480
        Put-U32A $fat 0 ([uint32]0x0FFFFFF8)
        Put-U32A $fat 4 ([uint32]0x0FFFFFFF)
        Put-U32A $fat 8 ([uint32]0x0FFFFFFF)
        for($i=0;$i -lt 4;$i++){ $fat[128+$i*2]=0xEB; $fat[129+$i*2]=0x58 }
        Write-AtA $s 16896 $fat
        Write-AtA $s 37376 $fat
        $root=New-Object 'byte[]' 512
        [Text.Encoding]::ASCII.GetBytes('ALPHA   TXT').CopyTo($root,0)
        $root[11]=0x20
        Put-U16A $root 26 ([uint16]3)
        Put-U32A $root 28 ([uint32]5)
        Write-AtA $s 57856 $root
    } finally { $s.Dispose() }
}
try {
    $img=Join-Path $dir 'artificial-fat32.img'
    New-ArtificialImageA $img
    $before=(Get-FileHash -LiteralPath $img -Algorithm SHA256).Hash
    Assert-A (Throws-A { & $cli -ImagePath $img | Out-Null }) 'Explicit consent is mandatory'
    Assert-A (Throws-A { & $cli -ImagePath '\\.\PhysicalDrive0' -IUnderstandReadOnlyLocal | Out-Null }) 'Physical device paths blocked before opening'
    Assert-A (Throws-A { & $cli -ImagePath '\\server\share\disk.img' -IUnderstandReadOnlyLocal | Out-Null }) 'UNC paths blocked before opening'
    Assert-A (Throws-A { & $cli -ImagePath '.\relative.img' -IUnderstandReadOnlyLocal | Out-Null }) 'Relative paths blocked'
    Assert-A (Throws-A { & $cli -ImagePath (Join-Path $dir 'not-an-image.txt') -IUnderstandReadOnlyLocal | Out-Null }) 'Unapproved file extension blocked'
    Assert-A (Throws-A { & $cli -ImagePath (Join-Path $repo 'forbidden-real-data.img') -IUnderstandReadOnlyLocal | Out-Null }) 'Repository IMG path blocked without creating it'

    $result=& $cli -ImagePath $img -IUnderstandReadOnlyLocal -MaxDirectoryScanBytes 16384 -MaxMirrorReadBytes 8192 -MaxEb58ReadBytes 2560
    Assert-A ($result.team -eq 'A' -and $result.mode -eq 'local_read_only_preflight' -and $result.sourceOpenedReadOnly) 'Fixed schema from read-only source'
    Assert-A ($result.geometry.partitionOffsetBytes -eq 512 -and $result.geometry.fat1OffsetBytes -eq 16896 -and $result.geometry.fat2OffsetBytes -eq 37376) 'Synthetic BPB and FAT offset calculations'
    Assert-A ($result.directory.candidateRecords -ge 1 -and $result.hierarchy.nodes -ge 1) 'Directory metadata and hierarchy candidate integration'
    Assert-A ($result.fatMirrors.differentEntries -eq 0 -and $result.fatMirrors.bytesRead -le 8192) 'FAT mirror comparison obeys read budget'
    Assert-A ($result.eb58.observedPatternRuns -ge 2 -and $result.eb58.bytesRead -le 2560) 'EB58 mapping obeys read budget'
    Assert-A (-not $result.extractionAttempted -and -not $result.repairAttempted -and -not $result.reportFileWritten -and -not $result.privateNamesIncluded) 'No recovery, repair, report or filenames'
    Assert-A ($result.scanIncomplete -and $result.status -eq 'partial') 'Bounded partial scan cannot claim whole image inspected'
    $json=ConvertTo-Json -InputObject $result -Depth 9
    Assert-A ($json -notmatch 'ALPHA' -and $json -notmatch [regex]::Escape($img) -and $json -notmatch 'artificial-fat32.img') 'Summary never exposes source path or filename'
    Assert-A ((Get-FileHash -LiteralPath $img -Algorithm SHA256).Hash -eq $before) 'Source artificial IMG SHA-256 remains unchanged'
    Write-Host 'PASS: Team A local-only read-only synthetic preflight completed'
} finally {
    if([IO.Directory]::Exists($dir)){[IO.Directory]::Delete($dir,$true)}
}