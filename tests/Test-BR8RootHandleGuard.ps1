#requires -Version 5.1
# Team B R8-P4 isolated Windows synthetic test (A must wire to central runner).
# Never addresses real media, images or arbitrary user files.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5 -or
   $PSVersionTable.PSVersion.Minor -ne 1 -or $env:OS -cne 'Windows_NT'){
    throw 'B R8 P4 requires native Windows PowerShell 5.1'
}
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Chappy.R8RootHandleGuard.psm1') -Force -ErrorAction Stop
function Assert-BR8P4([bool]$ok,[string]$reason){
    if(-not $ok){throw ('BR8_P4_FAIL: '+$reason)}
    $script:checks++
    Write-Host ('PASS: B R8 P4 '+$reason)
}
function New-BR8P4Root {
    $p=Join-Path ([IO.Path]::GetTempPath()) ('ChappyR8Synthetic-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($p)
    return $p
}
function Assert-BR8P4Denied([object]$r,[string]$tag){
    Assert-BR8P4 ($r.schemaVersion -ceq 'b_r8_root_handle_guard_v1' -and
        $r.status -ceq 'unsafe_root' -and $r.decision -ceq 'UNKNOWN' -and
        -not $r.handleIdentityVerified -and -not $r.canAuthorizeWrite -and
        -not $r.canExportOriginal -and $null -eq $r.lease -and
        $null -eq $r.rootPathPublic -and
        $r.metrics.sourceReadCalls -eq 0 -and
        $r.metrics.outputFilesCreated -eq 0 -and
        $r.metrics.filesDeleted -eq 0) $tag
}
function Test-BR8P4Sentinel([string]$dir){
    $p=Join-Path $dir 'sentinel-owned-by-this-test.txt'
    return ([IO.File]::Exists($p) -and [IO.File]::ReadAllText($p) -ceq 'GENERATED_SENTINEL')
}
$checks=0
[byte[]]$source=New-Object byte[] 887
for($i=0;$i -lt $source.Length;$i++){$source[$i]=[byte](($i*37+11)%256)}
$hash=[Security.Cryptography.SHA256]::Create()
try{$before=[BitConverter]::ToString($hash.ComputeHash($source))}finally{$hash.Dispose()}
$stream=[IO.MemoryStream]::new($source,$false)
try{
    Assert-BR8P4 (-not $stream.CanWrite -and $stream.Position -eq 0) 'synthetic input stream never writable or read by guard'
    # Default OFF must not inspect even a nonexistent root.
    $disabled=Open-ChappyR8SyntheticRootLeaseV1 -OutputRoot 'X:\never_exists\forbidden'
    Assert-BR8P4 ($disabled.status -ceq 'disabled' -and
        -not $disabled.canAuthorizeWrite -and
        $null -eq $disabled.lease -and
        $disabled.metrics.sourceReadCalls -eq 0) 'explicit opt-in mandatory; disabled read and write counts zero'

    $root=New-BR8P4Root
    $parking=Join-Path ([IO.Path]::GetTempPath()) ('ChappyR8Parking-'+[guid]::NewGuid().ToString('N'))
    $lease=$null
    try {
        $lease=Open-ChappyR8SyntheticRootLeaseV1 -OutputRoot $root -EnableSyntheticRootGuard
        Assert-BR8P4 ($lease.status -ceq 'handle_observed' -and
            $lease.decision -ceq 'HANDLE_OBSERVED_PREFLIGHT_ONLY' -and
            $lease.handleIdentityVerified -and $null -ne $lease.lease -and
            -not $lease.canAuthorizeWrite -and -not $lease.canExportOriginal -and
            $null -eq $lease.rootPathPublic -and
            $lease.metrics.sourceReadCalls -eq 0 -and
            $lease.metrics.outputFilesCreated -eq 0) 'normal direct-child OS temp: actual handle observed, never output-authorized'

        $still=Test-ChappyR8SyntheticRootLeaseV1 -GuardResult $lease
        Assert-BR8P4 ($still.status -ceq 'handle_observed' -and
            $still.handleIdentityVerified -and -not $still.canAuthorizeWrite -and
            $null -eq $still.lease) 'same-open-handle volume+file-index and reopened identity consistent'

        $invalid=@(
            (Join-Path $root 'ChappyR8Synthetic-00000000000000000000000000000000'),
            (Join-Path ([IO.Path]::GetTempPath()) '..\ChappyR8Synthetic-00000000000000000000000000000000'),
            '.\ChappyR8Synthetic-00000000000000000000000000000000',
            '\\example.invalid\share\ChappyR8Synthetic-00000000000000000000000000000000',
            '\\?\C:\ChappyR8Synthetic-00000000000000000000000000000000',
            ($root+':stream'),
            (Join-Path ([IO.Path]::GetTempPath()) 'not-an-approved-root')
        )
        $denials=0
        foreach($bad in $invalid) {
            $no=Open-ChappyR8SyntheticRootLeaseV1 -OutputRoot $bad -EnableSyntheticRootGuard
            Assert-BR8P4Denied $no ('invalid-root-case-'+$denials)
            $denials++
        }

        # Ordinary rename of a held directory should be denied, because
        # the native root lease excludes FILE_SHARE_DELETE. If this OS does
        # permit a rename, MUST NOT remain "handle observed" after the move.
        $movedWhileHeld=$false
        try{
            [IO.Directory]::Move($root,$parking)
            $movedWhileHeld=$true
        }catch [IO.IOException] {} catch [UnauthorizedAccessException] {}
        $afterAttempt=Test-ChappyR8SyntheticRootLeaseV1 -GuardResult $lease
        if($movedWhileHeld){
            Assert-BR8P4 (-not $afterAttempt.handleIdentityVerified -and
                $afterAttempt.status -ceq 'unsafe_root') 'unexpected root rename detected as unsafe, never reused'
        }else{
            Assert-BR8P4 ($afterAttempt.handleIdentityVerified -and
                $afterAttempt.status -ceq 'handle_observed') 'live handle blocks ordinary root rename; identity remains stable'
        }
    }finally{
        if($null -ne $lease){
            $closed=Close-ChappyR8SyntheticRootLeaseV1 -GuardResult $lease
            Assert-BR8P4 ($closed.status -ceq 'closed' -and
                -not $closed.canAuthorizeWrite -and
                (Test-ChappyR8SyntheticRootLeaseV1 -GuardResult $lease).status -ceq 'unsafe_root') 'closed lease can never be replayed as authority'
        }
    }
    # Deliberate *owned* root substitution AFTER lease close: identity of a
    # different directory at the same canonical string must be different.
    if([IO.Directory]::Exists($parking)){
        [IO.Directory]::Move($parking,$root)
    }
    $oldGuard=Open-ChappyR8SyntheticRootLeaseV1 -OutputRoot $root -EnableSyntheticRootGuard
    Assert-BR8P4 ($oldGuard.handleIdentityVerified -and $null -ne $oldGuard.lease) 'root opened for post-release substitution control'
    [void](Close-ChappyR8SyntheticRootLeaseV1 -GuardResult $oldGuard)
    [IO.Directory]::Move($root,$parking)
    [void][IO.Directory]::CreateDirectory($root)
    $replacement=Open-ChappyR8SyntheticRootLeaseV1 -OutputRoot $root -EnableSyntheticRootGuard
    try{
        Assert-BR8P4 ($replacement.handleIdentityVerified -and
            -not $oldGuard.lease.StoredRootIsSameObject($replacement.lease) -and
            -not $replacement.canAuthorizeWrite) 'new directory at same path has different file identity, old lease never authorizes it'
    }finally{
        if($null -ne $replacement.lease){
            [void](Close-ChappyR8SyntheticRootLeaseV1 -GuardResult $replacement)
        }
        [IO.Directory]::Delete($root,$false)
        [IO.Directory]::Move($parking,$root)
    }
    Assert-BR8P4 ([IO.Directory]::Exists($root)) 'original test-owned directory restored after root substitution'
    [IO.Directory]::Delete($root,$false)

    # Actual NTFS junction target is wholly disposable and carries one
    # generated sentinel. Skip as NOT TESTED if runner disallows mklink.
    $target=Join-Path ([IO.Path]::GetTempPath()) ('ChappyR8Target-'+[guid]::NewGuid().ToString('N'))
    $jroot=Join-Path ([IO.Path]::GetTempPath()) ('ChappyR8Synthetic-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($target)
    $sentinel=Join-Path $target 'sentinel-owned-by-this-test.txt'
    [IO.File]::WriteAllText($sentinel,'GENERATED_SENTINEL',[Text.Encoding]::ASCII)
    $junctionMade=$false
    try{
        $null=(& $env:ComSpec /d /c ('mklink /J "{0}" "{1}"' -f $jroot,$target) 2>&1)
        $junctionMade=($LASTEXITCODE -eq 0 -and [IO.Directory]::Exists($jroot) -and
            (([IO.File]::GetAttributes($jroot) -band [IO.FileAttributes]::ReparsePoint) -ne 0))
        if($junctionMade){
            $deny=Open-ChappyR8SyntheticRootLeaseV1 -OutputRoot $jroot -EnableSyntheticRootGuard
            Assert-BR8P4Denied $deny 'real generated junction root rejected'
            Assert-BR8P4 (Test-BR8P4Sentinel $target) 'junction target synthetic sentinel preserved'
        }else{Write-Host 'B R8 P4 JUNCTION ROOT: NOT TESTED (mklink denied by Windows runner)'}
    }finally{
        if($junctionMade){[IO.Directory]::Delete($jroot,$false)}
        Assert-BR8P4 (Test-BR8P4Sentinel $target) 'no unrelated generated target cleanup occurred'
        [IO.File]::Delete($sentinel)
        [IO.Directory]::Delete($target,$false)
    }

    $target=Join-Path ([IO.Path]::GetTempPath()) ('ChappyR8Target-'+[guid]::NewGuid().ToString('N'))
    $sroot=Join-Path ([IO.Path]::GetTempPath()) ('ChappyR8Synthetic-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($target)
    $sentinel=Join-Path $target 'sentinel-owned-by-this-test.txt'
    [IO.File]::WriteAllText($sentinel,'GENERATED_SENTINEL',[Text.Encoding]::ASCII)
    $symlinkMade=$false
    try {
        $null=(& $env:ComSpec /d /c ('mklink /D "{0}" "{1}"' -f $sroot,$target) 2>&1)
        $symlinkMade=($LASTEXITCODE -eq 0 -and [IO.Directory]::Exists($sroot) -and
            (([IO.File]::GetAttributes($sroot) -band [IO.FileAttributes]::ReparsePoint) -ne 0))
        if($symlinkMade){
            Assert-BR8P4Denied (Open-ChappyR8SyntheticRootLeaseV1 -OutputRoot $sroot -EnableSyntheticRootGuard) 'real synthetic directory symlink root denied'
        }else{Write-Host 'B R8 P4 DIRECTORY SYMLINK: NOT TESTED (runner lacks privilege)'}
    }finally{
        if($symlinkMade){[IO.Directory]::Delete($sroot,$false)}
        Assert-BR8P4 (Test-BR8P4Sentinel $target) 'symlink disposable target sentinel unchanged'
        [IO.File]::Delete($sentinel)
        [IO.Directory]::Delete($target,$false)
    }

    # A nested ancestor would require traversal past a caller-controlled
    # directory and is refused *before* any such path could become a root.
    $nestedParent=New-BR8P4Root
    try{
        $nestedRoot=Join-Path $nestedParent ('ChappyR8Synthetic-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($nestedRoot)
        Assert-BR8P4Denied (Open-ChappyR8SyntheticRootLeaseV1 -OutputRoot $nestedRoot -EnableSyntheticRootGuard) 'nested ancestor output root denied by direct OS-temp-child rule'
        [IO.Directory]::Delete($nestedRoot,$false)
    }finally{[IO.Directory]::Delete($nestedParent,$false)}
}finally{$stream.Dispose()}
$hash=[Security.Cryptography.SHA256]::Create()
try{$after=[BitConverter]::ToString($hash.ComputeHash($source))}finally{$hash.Dispose()}
Assert-BR8P4 ($before -ceq $after) 'invented 887-byte original synthetic source SHA unchanged'
Write-Host ('B R8-P4 STANDALONE: checks={0}; actual external source reads=0, output writes=0, output deletes=0, original UNKNOWN; handle PRECHECK ONLY / canAuthorizeWrite=false; junction/symlink NOT TESTED when OS rejects creation' -f $checks)
Write-Host 'PASS: B R8-P4 standalone handle/root negative test completed. Not a race-proof exporter.'
