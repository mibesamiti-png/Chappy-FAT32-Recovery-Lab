#Requires -Version 5.1
# A-owned unit test for delegated R8 native test manifest (synthetic file names only).
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'runner\Chappy.R8DelegatedTestSelection.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('ChappyR8Selection-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$count=0
function Assert-Manifest([bool]$ok,[string]$name) {
    if(-not $ok){ throw ('A R8 runner manifest fail: '+$name) }
    $script:count++
    Write-Host ('PASS: A R8 delegated manifest '+$name)
}
function Add-Fake([string]$relative) {
    $full=Join-Path $root $relative
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full))
    [IO.File]::WriteAllText($full,'GENERATED_TEST_MARKER',[Text.Encoding]::ASCII)
}
function Remove-Fake([string]$relative) {
    [IO.File]::Delete((Join-Path $root $relative))
}
function Assert-PartialRejected([string]$why) {
    $rejected=$false
    try { @(Get-ChappyR8DelegatedTestSelection -RepositoryRoot $root) | Out-Null }
    catch {
        if($_.Exception.Message -like 'Delegated R8 team *'){ $rejected=$true }
        else { throw }
    }
    Assert-Manifest $rejected $why
}
$bModule='core\Chappy.R8RootHandleGuard.psm1'
$bTest='tests\Test-BR8RootHandleGuard.ps1'
$cModule='core\Chappy.R8FaultSafeWriter.psm1'
$cTest='tests\Test-CR8FaultSafeWriter.ps1'
$dTest='tests\Test-DR8AdversarialMatrix.ps1'
try {
    Assert-Manifest (@(Get-ChappyR8DelegatedTestSelection -RepositoryRoot $root).Count -eq 0) 'no unmerged delegated files => no premature tests'
    Add-Fake $bModule
    Assert-PartialRejected 'B module without native test fails closed'
    Add-Fake $bTest
    $got=@(Get-ChappyR8DelegatedTestSelection -RepositoryRoot $root)
    Assert-Manifest ($got.Count -eq 1 -and $got[0] -ceq $bTest) 'B module+test => required standalone test'
    Remove-Fake $bModule
    Assert-PartialRejected 'B test without module fails closed'
    Remove-Fake $bTest
    Add-Fake $cTest
    Assert-PartialRejected 'C test without module fails closed'
    Add-Fake $cModule
    $got=@(Get-ChappyR8DelegatedTestSelection -RepositoryRoot $root)
    Assert-Manifest ($got.Count -eq 1 -and $got[0] -ceq $cTest) 'C module+test => required standalone test'
    Add-Fake $bModule
    Add-Fake $bTest
    Add-Fake $dTest
    $got=@(Get-ChappyR8DelegatedTestSelection -RepositoryRoot $root)
    Assert-Manifest ($got.Count -eq 3 -and $got[0] -ceq $bTest -and $got[1] -ceq $cTest -and $got[2] -ceq $dTest) 'B+C+D all selected in stable order'
    Remove-Fake $bModule
    Remove-Fake $bTest
    Remove-Fake $cModule
    Remove-Fake $cTest
    $got=@(Get-ChappyR8DelegatedTestSelection -RepositoryRoot $root)
    Assert-Manifest ($got.Count -eq 1 -and $got[0] -ceq $dTest) 'D standalone independent negative test runs without B/C'
} finally {
    # Only delete the exact generated temp directory that this test created.
    if([IO.Directory]::Exists($root)){[IO.Directory]::Delete($root,$true)}
}
Write-Host ('PASS: A R8 delegated native runner selection {0} checks passed; no user IMG read or output.' -f $count)
