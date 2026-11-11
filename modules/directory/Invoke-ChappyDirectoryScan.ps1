#requires -Version 5.1
<#[
  Read-only local IMG directory metadata scan.
  Example:
  .\Invoke-ChappyDirectoryScan.ps1 -ImagePath 'C:\SD_Backups\disk.img' `
    -OutputJsonPath 'C:\SD_Backups\local-only-b-report.json' -IncludeNames `
    -MaxScanBytes 67108864
  Results may contain private filenames. Never publish local results to GitHub.
]#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ImagePath,
    [string]$OutputJsonPath = '',
    [long]$PartitionOffsetBytes = -1L,
    [long]$MaxScanBytes = 67108864L,
    [long]$StartCluster = 2L,
    [int]$MaxCandidates = 10000,
    [int]$MaxDirectories = 1000,
    [switch]$IncludeNames,
    [switch]$IncludeDeleted
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DirectoryScanner.ps1')
if ($ImagePath.StartsWith('\\.\') -or $ImagePath.StartsWith('\\?\')) {
    throw 'Only regular image files allowed; physical devices and raw volume paths forbidden'
}
$resolved = (Resolve-Path -LiteralPath $ImagePath -ErrorAction Stop).ProviderPath
if (-not [IO.File]::Exists($resolved)) { throw 'ImagePath is not a file' }
if ($OutputJsonPath) {
    $outFull = [IO.Path]::GetFullPath($OutputJsonPath)
    if ([string]::Equals($resolved, $outFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'JSON output may not equal input image'
    }
    if ([IO.File]::Exists($outFull)) { throw 'Output exists; overwrite is forbidden' }
    if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($outFull))) {
        throw 'Output directory must already exist'
    }
}
$stream = $null
try {
    $stream = [IO.File]::Open($resolved, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $result = Get-ChappyDirectoryCandidates -Stream $stream -PartitionOffsetBytes $PartitionOffsetBytes `
        -MaxScanBytes $MaxScanBytes -StartCluster $StartCluster -MaxCandidates $MaxCandidates `
        -MaxDirectories $MaxDirectories -IncludeNames:$IncludeNames -IncludeDeleted:$IncludeDeleted
} finally {
    if ($null -ne $stream) { $stream.Dispose() }
}
if ($OutputJsonPath) {
    $json = ConvertTo-Json -InputObject $result -Depth 9
    $utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)
    $outStream = $null
    try {
        $outStream = [IO.File]::Open($outFull, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $data = $utf8.GetBytes($json)
        $outStream.Write($data, 0, $data.Length)
    } finally {
        if ($null -ne $outStream) { $outStream.Dispose() }
    }
}
Write-Output $result
