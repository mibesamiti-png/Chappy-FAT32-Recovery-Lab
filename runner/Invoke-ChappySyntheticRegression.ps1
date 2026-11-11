#Requires -Version 5.1
<#
.SYNOPSIS
Runs all current synthetic-only QuickProbe, B, C, D and A regression suites in isolated
Windows PowerShell 5.1 processes. Never accepts an IMG path or scans real media.
.DESCRIPTION
Each child test creates its own artificial fixture and cleans up. This runner
does not implement file extraction, disk access, repair, or report upload.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
    throw 'Windows PowerShell 5.1 is required for the synthetic regression runner'
}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$exe=Join-Path $PSHOME 'powershell.exe'
if(-not [IO.File]::Exists($exe)){throw 'powershell.exe not found; cannot validate Windows PS5.1'}
$tests=@(
    'tests\Test-QuickProbe.ps1',
    'tests\Test-DirectoryScanner.ps1',
    'modules\carving\tests\Test-ChappyCarving.ps1',
    'modules\fat-analysis\tests\Run-TeamD.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R2.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R3-Mirror.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R3-Eb58.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R3-ChainStats.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R3-Consistency.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R4-Geometry.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R5-Disagreement.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R6-MirrorVbr.Tests.ps1',
    'tests\Test-LocalReadOnlyPreflight.ps1',
    'tests\Test-SyntheticDamageBenchmark.ps1'
)
$passed=0
Push-Location $root
try {
    foreach($relative in $tests){
        $full=Join-Path $root $relative
        if(-not [IO.File]::Exists($full)){throw "Missing synthetic test: $relative"}
        Write-Host "=== SYNTHETIC TEST: $relative ==="
        & $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $full
        $code=$LASTEXITCODE
        if($code -ne 0){throw "Synthetic test failed: $relative (exit $code)"}
        $passed++
    }
} finally {
    Pop-Location
}
if($passed -ne $tests.Count){throw 'Synthetic suite did not execute all expected tests'}
Write-Host "PASS: $passed/$($tests.Count) isolated synthetic test scripts completed."
Write-Host 'This is not a real 31GB IMG validation or data recovery test.'