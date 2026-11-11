#requires -Version 5.1
[CmdletBinding()]
param([switch]$CheckTracked)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  $blockedExt=@('.img','.raw','.dd','.e01','.vhd','.vhdx','.vmdk','.iso','.bin','.gcode','.gco','.3mf','.stl','.obj','.jpg','.jpeg','.png','.mp4','.mov','.zip','.log','.key','.pem')
  $forbiddenDir='(^|[\\/])(private|local-data|recovered|reports|SD_Backups)([\\/]|$)'
  if($CheckTracked) {
    if(-not (Get-Command git -ErrorAction SilentlyContinue)){throw 'git was not found'}
    $paths=@(& git ls-files)
    if($LASTEXITCODE -ne 0){throw 'git ls-files failed'}
  } else {
    $paths=@(Get-ChildItem -LiteralPath $root -Recurse -File -Force |
      Where-Object {$_.FullName -notmatch '[\\/][.]git[\\/]'} |
      ForEach-Object {$_.FullName.Substring($root.Length).TrimStart([char[]]@('\','/'))})
  }
  $errors=New-Object System.Collections.Generic.List[string]
  foreach($p in $paths) {
    $ext=[IO.Path]::GetExtension($p).ToLowerInvariant()
    if($blockedExt -contains $ext){$errors.Add("Blocked extension: $p")}
    if($p -match $forbiddenDir){$errors.Add("Private data folder: $p")}
    if([IO.Path]::GetFileName($p) -ieq 'microSD_disk1.img'){$errors.Add("Original image name: $p")}
    $full=Join-Path $root $p
    if(Test-Path -LiteralPath $full -PathType Leaf) {
      if((Get-Item -LiteralPath $full).Length -gt 10MB){$errors.Add("File >10 MiB: $p")}
    }
  }
  if($errors.Count) {
    $errors | ForEach-Object {Write-Warning $_}
    throw "Unsafe repository content detected: $($errors.Count) path(s)"
  }
  Write-Host "PASS: $($paths.Count) file(s) scanned for blocked types, paths and large size."
  Write-Host "IMPORTANT: manual review is still necessary; .gitignore is not sufficient."
} finally {Pop-Location}