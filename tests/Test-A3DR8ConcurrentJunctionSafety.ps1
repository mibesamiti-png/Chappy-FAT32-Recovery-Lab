#Requires -Version 5.1
# Team A R8 P2. All sources generated in RAM and all outputs disposable temp.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-Chappy3DCleanFixture.ps1')
$module=Join-Path $root 'core\Chappy.SyntheticSeparateExportV1.psm1'
Import-Module $module -Force
function Assert-R8P2([bool]$OK,[string]$Why) {
    if(-not $OK){throw ('A_R8_P2_FAIL: '+$Why)}
}
$fixture=New-ChappyA3DCleanFixture -Seed 202612
$oracle=@($fixture.oracle | Where-Object {$_.shortName -ceq 'MODEL   3MF'})[0]
[byte[]]$source=[byte[]]::new(65536)
[Array]::Copy($fixture.image,0,$source,0,$source.Length)
$sourceSha=Get-A3DSha256 $source
$extents=@($oracle.extents | ForEach-Object {
    [pscustomobject]@{offsetBytes=[long]$_.offsetBytes;lengthBytes=[long]$_.lengthBytes}
})
$id=('3mf:{0}+{1},{2}+{3}' -f $extents[0].offsetBytes,$extents[0].lengthBytes,$extents[1].offsetBytes,$extents[1].lengthBytes)
$temp=[IO.Path]::GetTempPath()
$owned=Join-Path $temp ('ChappyR8Synthetic-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($owned)
try {
    # Explicit barrier proves all 5 child processes are ready together before
    # any exporter gets to call CreateNew, rather than just sequential retries.
    $signal=Join-Path $owned 'synthetic-start.signal'
    $jobs=@()
    for($i=0;$i -lt 5;$i++){
        $jobs+=Start-Job -Name ('R8P2_'+$i) -ScriptBlock {
            param($modulePath,[byte[]]$data,[string]$key,[object[]]$parts,[string]$out,[int]$index,[string]$release)
            $ErrorActionPreference='Stop'
            Import-Module $modulePath -Force
            [IO.File]::WriteAllText((Join-Path $out ('ready-'+$index+'.signal')),'READY')
            $released=$false
            for($wait=0;$wait -lt 600;$wait++){
                if([IO.File]::Exists($release)){$released=$true;break}
                Start-Sleep -Milliseconds 50
            }
            if(-not $released){throw 'R8 P2 concurrency barrier timeout'}
            Export-ChappyR8SyntheticCandidateV1 -SourceBytes $data -CandidateId $key -OrderedExtents $parts -OutputRoot $out -SyntheticFixtureTag 'A3D-clean-202612' -EnableSyntheticExport
        } -ArgumentList $module,$source,$id,$extents,$owned,$i,$signal
    }
    try {
        $allReady=$false
        for($poll=0;$poll -lt 600;$poll++){
            if(@([IO.Directory]::GetFiles($owned,'ready-*.signal')).Count -eq 5){
                $allReady=$true
                break
            }
            Start-Sleep -Milliseconds 50
        }
        Assert-R8P2 $allReady 'five_workers_ready_before_simultaneous_release'
        [IO.File]::WriteAllText($signal,'GO')
        $done=@($jobs|Wait-Job -Timeout 90)
        Assert-R8P2 ($done.Count -eq 5 -and @($jobs|Where-Object {$_.State -cne 'Completed'}).Count -eq 0) 'all_five_concurrent_workers_finished'
        $results=@($jobs | Receive-Job -ErrorAction Stop)
        $ok=@($results | Where-Object {$_.status -ceq 'complete'})
        $collisions=@($results | Where-Object {$_.status -ceq 'partial' -and $_.decision -ceq 'synthetic_export_failed_UNKNOWN'})
        Assert-R8P2 ($results.Count -eq 5 -and $ok.Count -eq 1 -and $collisions.Count -eq 4 -and @([IO.Directory]::GetFiles($owned,'candidate-*.3mf')).Count -eq 1) 'atomic_CreateNew_one_winner_four_failures'
        $winner=$ok[0]
        [byte[]]$outBytes=[IO.File]::ReadAllBytes([string]$winner.outputPath)
        Assert-R8P2 ($winner.outputVerified -and $winner.sourceUnchanged -and $winner.originalIdentity -ceq 'unknown' -and -not $winner.canExportOriginal -and $winner.outputBytes -eq [int]$oracle.lengthBytes -and (Get-A3DSha256 $outBytes) -ceq [string]$oracle.sha256 -and (Get-A3DSha256 $source) -ceq $sourceSha) 'parallel_artificial_sha_and_source_unchanged'
        Write-Host ('A R8 P2 CONCURRENT: 5 independent writers winner=1 collisions=4 outputB={0} originalUNKNOWN=yes' -f $winner.outputBytes)
    }finally{
        foreach($job in $jobs){
            if($job.State -notin @('Completed','Failed','Stopped')){Stop-Job $job -ErrorAction SilentlyContinue}
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }
    }
}finally{
    if([IO.Directory]::Exists($owned)){[IO.Directory]::Delete($owned,$true)}
}
# An NTFS junction to a second disposable synthetic root must not be traversed.
$target=Join-Path $temp ('ChappyR8Target-'+[guid]::NewGuid().ToString('N'))
$junction=Join-Path $temp ('ChappyR8Synthetic-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($target)
[IO.File]::WriteAllText((Join-Path $target 'untouched.txt'),'SYNTHETIC_SENTINEL',[Text.Encoding]::ASCII)
$junctionCreated=$false
try{
    $mklink='mklink /J "{0}" "{1}"' -f $junction,$target
    $output=@(& $env:ComSpec /d /c $mklink 2>&1)
    $junctionCreated=($LASTEXITCODE -eq 0 -and [IO.Directory]::Exists($junction) -and (([IO.File]::GetAttributes($junction) -band [IO.FileAttributes]::ReparsePoint) -ne 0))
    if($junctionCreated){
        $reject=Export-ChappyR8SyntheticCandidateV1 -SourceBytes $source -CandidateId $id -OrderedExtents $extents -OutputRoot $junction -SyntheticFixtureTag 'A3D-clean-202612' -EnableSyntheticExport
        Assert-R8P2 ($reject.status -ceq 'rejected' -and @([IO.Directory]::GetFiles($target)).Count -eq 1 -and [IO.File]::ReadAllText((Join-Path $target 'untouched.txt')) -ceq 'SYNTHETIC_SENTINEL') 'NTFS_junction_root_must_not_redirect_output'
        Write-Host 'A R8 P2 ROOT-JUNCTION: real NTFS junction created, exporter denied without touching target'
    }else{
        Write-Host 'A R8 P2 ROOT-JUNCTION: NOT TESTED (Windows runner could not create junction). Formal R8 remains blocked.'
    }
}finally{
    if($junctionCreated -and [IO.Directory]::Exists($junction)){
        # Non-recursive Delete removes the junction entry, not its target.
        [IO.Directory]::Delete($junction,$false)
    }
    Assert-R8P2 ([IO.File]::Exists((Join-Path $target 'untouched.txt'))) 'owned_target_survives_junction_removal'
    if([IO.Directory]::Exists($target)){[IO.Directory]::Delete($target,$true)}
}
Write-Host 'PASS: R8 P2 five-source-process CreateNew contention; NTFS junction denial when supported; synthetic-only.'
