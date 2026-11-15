#Requires -Version 5.1
# Team A owned: discover B/C/D delegated R8 native Windows tests, fail closed on partial submissions.
# This is a test-manifest helper only: no original data/media access and no output export.
function Get-ChappyR8DelegatedTestSelection {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RepositoryRoot)
    $pairs=@(
        [pscustomobject]@{Team='B';Module='core\Chappy.R8RootHandleGuard.psm1';Test='tests\Test-BR8RootHandleGuard.ps1'},
        [pscustomobject]@{Team='C';Module='core\Chappy.R8FaultSafeWriter.psm1';Test='tests\Test-CR8FaultSafeWriter.ps1'}
    )
    $selected=New-Object 'System.Collections.Generic.List[string]'
    foreach($p in $pairs) {
        $moduleHere=[IO.File]::Exists((Join-Path $RepositoryRoot $p.Module))
        $testHere=[IO.File]::Exists((Join-Path $RepositoryRoot $p.Test))
        if($moduleHere -ne $testHere) {
            throw ('Delegated R8 team {0}: production adapter and native test must be submitted together (cannot silently skip)' -f $p.Team)
        }
        if($moduleHere) {
            [void]$selected.Add($p.Test)
        }
    }
    $d='tests\Test-DR8AdversarialMatrix.ps1'
    if([IO.File]::Exists((Join-Path $RepositoryRoot $d))) {
        [void]$selected.Add($d)
    }
    return $selected.ToArray()
}
