#requires -Version 5.1
<#
Stage ONLY the known v0.5 experimental source and its synthetic test.
Does not scan a disk, touch an IMG, commit, or push.
Usage:
  .\tools\Import-Legacy-v0.5.ps1
  .\tools\Import-Legacy-v0.5.ps1 -SourceDirectory 'C:\Some\Extracted\v0.5'
#>
[CmdletBinding()]
param(
    [string]$SourceDirectory='C:\SD_Backups\Chappy_FAT32_Recovery_Lab_v0.5'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$backup = [IO.Path]::GetFullPath('C:\SD_Backups')
if ($repo.TrimEnd('\','/').StartsWith($backup.TrimEnd('\','/')+'\',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'The Git repository must not be inside C:\SD_Backups'
}
if (-not (Test-Path -LiteralPath (Join-Path $repo '.git') -PathType Container)) {
    throw 'This importer must be run inside a cloned Git repository'
}
$mapping=@(
    @{name='Chappy_FAT32_Recovery_Lab_v0.5.ps1'; rel='legacy\Chappy_FAT32_Recovery_Lab_v0.5.ps1'; sha='925e8428d11296ea5a4976d3961cfe87f377228019b6565c11e6775a3fbb44ce'},
    @{name='Test_Chappy_FAT32_v0.5.ps1'; rel='tests\legacy\Test_Chappy_FAT32_v0.5.ps1'; sha='9b6ba6b97f87d0caf154d8fd27e219fc303ae99f0944e9d3eae5d1aa9ba95d23'}
)
foreach($item in $mapping) {
    $src=Join-Path $SourceDirectory $item.name
    if(-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Required source missing: $src" }
    $file=Get-Item -LiteralPath $src
    if($file.Length -gt 1MB){throw "Unexpectedly large code file: $src"}
    $hash=(Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
    if($hash -ine $item.sha){throw "Checksum mismatch for $($item.name). Do not publish unknown content."}
}
foreach($item in $mapping) {
    $src=Join-Path $SourceDirectory $item.name
    $dst=Join-Path $repo $item.rel
    $parent=Split-Path -Parent $dst
    if(-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void][IO.Directory]::CreateDirectory($parent)
    }
    if(Test-Path -LiteralPath $dst -PathType Leaf){throw "Target already exists: $dst"}
    Copy-Item -LiteralPath $src -Destination $dst
    Write-Host "Prepared: $($item.rel)"
}
Write-Host 'Source files were copied by exact name and verified SHA-256.'
Write-Host 'Review their code before committing. No Git add/commit/push was performed.'
Write-Host 'When ready, run (from repo root):'
Write-Host '  git add -- legacy/Chappy_FAT32_Recovery_Lab_v0.5.ps1 tests/legacy/Test_Chappy_FAT32_v0.5.ps1'
Write-Host '  git diff --cached --stat'
Write-Host '  git commit -m "chore: import experimental v0.5 baseline"'
Write-Host '  git push origin main'