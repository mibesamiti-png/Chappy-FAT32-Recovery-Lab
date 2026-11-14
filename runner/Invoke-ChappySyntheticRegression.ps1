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
    'modules\fat-analysis\tests\Run-TeamD-R7-StratifiedAB.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R8-AdditiveAB.Tests.ps1',
    'tests\Test-LocalReadOnlyPreflight.ps1',
    'tests\Test-SyntheticDamageBenchmark.ps1',
    'tests\Test-A3DCleanFixture.ps1',
    'tests\Test-A3DDamagedFixture.ps1',
    'tests\Test-A3DStandardFixture.ps1',
    'modules\fat-analysis\tests\Run-TeamD-P02Evidence.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R6-FixtureChainAB.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R6-ObservedIo.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R6-IntervalNegatives.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R6-SourceIdentity.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R6-DualFatAmbiguity.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R6-SamplingBlindspots.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R6-Remote512Tradeoff.Tests.ps1',
    'modules\fat-analysis\tests\Run-TeamD-R6-StandardFatCoverage.Tests.ps1',
    'tests\Test-A3DEvidenceBaseline.ps1',
    'tests\Test-A3DSharedReadProvenance.ps1',
    'tests\Test-A3DSharedMultiSeedQuota.ps1',
    'tests\Test-A3DStandardSharedSourceGate.ps1',
    'tests\Test-A3DStandardDataWindowBridge.ps1',
    'tests\Test-A3DStandardCCandidateReceipts.ps1',
    'tests\Test-A3DCandidateReadTrust.ps1',
    'tests\Test-A3DCandidateDefinitionBoundary.ps1',
    'tests\Test-A3DGateProgressParameters.ps1',
    'tests\Test-A3DLiveBcdEnvelope.ps1',
    'tests\Test-A3DVersionedBDContracts.ps1',
    'tests\Test-A3DFragmentPhysicalReceipts.ps1',
    'tests\Test-A3DLiveDirectoryOuterReceipts.ps1',
    'tests\Test-A3DLiveFatPairOuterReceipts.ps1',
    'tests\Test-A3DLiveStandardFragmentReceipts.ps1',
    'tests\Test-A3DOneSourceBcdFragmentReceipts.ps1',
    'tests\Test-A3DPublicSafeEvidenceV1.ps1',
    'tests\Test-A3DPublicAdversarialOracleSeparation.ps1',
    'tests\Test-A3DOutcomeEvidenceAccounting.ps1',
    'tests\Test-A3DPublicDuplicateTailAmbiguity.ps1',
    'tests\Test-A3DR8SyntheticSeparateExportV1.ps1',
    'tests\Test-A3DR8ConcurrentJunctionSafety.ps1',
    'tests\Test-A3DLiveCCandidateReceipts.ps1',
    'tests\Test-A3DLiveMultiCandidateBoundary.ps1',
    'tests\Test-A3DDiscoveredAmbiguousReceipts.ps1'
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
