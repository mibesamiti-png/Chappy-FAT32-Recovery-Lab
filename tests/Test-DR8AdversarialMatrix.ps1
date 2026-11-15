#Requires -Version 5.1
# Team D #200 / R8-P6: independent generated-only R7 -> R8 adversarial matrix.
# No user file, original IMG, physical device, arbitrary output directory, or source path input.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $repoRoot 'core\Chappy.R8SourceBoundSyntheticBridge.psm1') -Force
$script:checks=0
$script:cases=0
# Only roots created in this invocation can ever be removed.
$script:DMatrixCreatedRoots=@{}

function Assert-DMatrix([bool]$Condition,[string]$Name) {
    if(-not $Condition){throw ('D_R8_P6_FAIL: '+$Name)}
    $script:checks++
}
function New-DMatrixRoot {
    $path=Join-Path ([IO.Path]::GetTempPath()) ('ChappyR8Synthetic-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($path)
    $script:DMatrixCreatedRoots[$path]=$true
    return $path
}
function Remove-DMatrixRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ExpectedFilePath='',
        [string]$ExpectedFileName='',
        [string]$ExpectedSha256=''
    )
    # A path that merely LOOKS like a synthetic root does not grant deletion.
    if(-not $script:DMatrixCreatedRoots.ContainsKey($Path)){
        throw 'D_R8_P6_FAIL: root not created by this invocation'
    }
    $full=[IO.Path]::GetFullPath($Path)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/'))
    $parent=[IO.Path]::GetDirectoryName($full).TrimEnd([char[]]@('\','/'))
    $name=[IO.Path]::GetFileName($full)
    if(-not [string]::Equals($full,$Path,[StringComparison]::OrdinalIgnoreCase) -or
       -not [string]::Equals($parent,$temp,[StringComparison]::OrdinalIgnoreCase) -or
       $name -cnotmatch '^ChappyR8Synthetic-[0-9a-f]{32}$'){
        throw 'D_R8_P6_FAIL: unsafe cleanup root'
    }
    if(-not [IO.Directory]::Exists($full)){
        throw 'D_R8_P6_FAIL: owned root missing or substituted'
    }
    $attrs=[IO.File]::GetAttributes($full)
    if(($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       ($attrs -band [IO.FileAttributes]::Directory) -eq 0){
        throw 'D_R8_P6_FAIL: root reparse or not directory'
    }
    $entries=@([IO.Directory]::GetFileSystemEntries($full))
    if([string]::IsNullOrEmpty($ExpectedFilePath)){
        # All failed/disabled/unknown cases must leave NO file or subdirectory.
        if(-not [string]::IsNullOrEmpty($ExpectedSha256) -or
           -not [string]::IsNullOrEmpty($ExpectedFileName) -or $entries.Count -ne 0){
            throw 'D_R8_P6_FAIL: unexpected entry in no-output root'
        }
    } else {
        $candidate=[IO.Path]::GetFullPath($ExpectedFilePath)
        $filename=[IO.Path]::GetFileName($candidate)
        if(-not [string]::Equals($candidate,$ExpectedFilePath,[StringComparison]::OrdinalIgnoreCase) -or
           -not [string]::Equals([IO.Path]::GetDirectoryName($candidate),$full,[StringComparison]::OrdinalIgnoreCase) -or
           $filename -cnotmatch '^candidate-[0-9A-F]{32}\.3mf
           $ExpectedSha256 -cnotmatch '^[0-9A-F]{64}$' -or
           $entries.Count -ne 1 -or
           -not [string]::Equals([string]$entries[0],$candidate,[StringComparison]::OrdinalIgnoreCase)){
            throw 'D_R8_P6_FAIL: unexpected or non-owned output entry'
        }
        $fileAttrs=[IO.File]::GetAttributes($candidate)
        if(($fileAttrs -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
           ($fileAttrs -band [IO.FileAttributes]::Directory) -ne 0){
            throw 'D_R8_P6_FAIL: output reparse or directory'
        }
        $length=([IO.FileInfo]::new($candidate)).Length
        if($length -ne 887L -or $length -gt 4096L -or
           (Get-A3DSha256 ([IO.File]::ReadAllBytes($candidate))) -cne $ExpectedSha256){
            throw 'D_R8_P6_FAIL: owned artificial output SHA or length changed'
        }
        # Only the exact verified A-reported output is deleted; no wildcard.
        [IO.File]::Delete($candidate)
    }
    # Nonrecursive removal fails closed if anything unrecognized appeared.
    if(@([IO.Directory]::GetFileSystemEntries($full)).Count -ne 0){
        throw 'D_R8_P6_FAIL: root not empty after exact-owned cleanup'
    }
    [IO.Directory]::Delete($full,$false)
    [void]$script:DMatrixCreatedRoots.Remove($Path)
}
function Invoke-DMatrixBridge([byte[]]$Image,[string]$Directory,[hashtable]$Extra) {
    $mem=[IO.MemoryStream]::new($Image,$false)
    try {
        $p=@{
            Source=$mem
            OutputRoot=$Directory
            SyntheticFixtureTag='A3D-standard-202611'
            EnableSyntheticR7SourceBindingAndExport=$true
        }
        if($null -ne $Extra){
            foreach($key in $Extra.Keys){$p[$key]=$Extra[$key]}
        }
        return Export-ChappyR8SourceBoundSyntheticCandidateV1 @p
    } finally { $mem.Dispose() }
}
function Assert-DNoOutput([object]$Result,[string]$Directory,[string]$Name) {
    Assert-DMatrix ($Result.status -cne 'complete' -and
        -not $Result.outputVerified -and -not $Result.canExportOriginal -and
        -not $Result.originalShaVerified -and
        $null -eq $Result.outputPath -and
        @([IO.Directory]::GetFiles($Directory)).Count -eq 0) $Name
}

if(-not ('ChappyDR8P6ThreeThenZero' -as [type])) {
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class ChappyDR8P6ThreeThenZero : MemoryStream {
    private bool first = false;
    public ChappyDR8P6ThreeThenZero(byte[] data) : base(data, false) { }
    public override int Read(byte[] buffer, int offset, int count) {
        if (first) return 0;
        first = true;
        return base.Read(buffer, offset, Math.Min(3, count));
    }
}
'@
}

foreach($spc in @(1,2)){
    $fixture=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
    [byte[]]$image=$fixture.image
    $sourceSha=Get-A3DSha256 $image
    $oracle=@($fixture.oracle | Where-Object {$_.shortName -ceq 'MODEL   3MF'})
    Assert-DMatrix ($oracle.Count -eq 1 -and $oracle[0].lengthBytes -eq 887) ('SPC'+$spc+':independent_generated_truth')
    $oracleSha=[string]$oracle[0].sha256
    $dir=New-DMatrixRoot
    $ownedOutputPath=''
    $ownedOutputName=''
    try {
        # Default OFF: no source bytes observed, no output even with a valid fixture.
        $offStream=[IO.MemoryStream]::new($image,$false)
        try {
            $off=Export-ChappyR8SourceBoundSyntheticCandidateV1 -Source $offStream -OutputRoot $dir -SyntheticFixtureTag 'A3D-standard-202611'
            Assert-DMatrix ($off.status -ceq 'disabled' -and
                $off.r7SourceSessionCount -eq 0 -and
                $off.metrics.r7ActualReturnedBytes -eq 0L -and
                $off.metrics.r8CandidateActualReturnedBytes -eq 0L -and
                $offStream.Position -eq 0L -and
                @([IO.Directory]::GetFiles($dir)).Count -eq 0) ('SPC'+$spc+':default_off')
        } finally { $offStream.Dispose() }

        # ONE structural candidate: a synthetic export is allowed but never an original-file claim.
        $yes=Invoke-DMatrixBridge $image $dir @{}
        # Track exactly the path A reported on this successful CreateNew.
        # If the result is invalid, fail closed rather than recurse into TEMP.
        if($yes.status -ceq 'complete' -and $yes.outputVerified){
            $ownedOutputPath=[string]$yes.outputPath
            $ownedOutputName=[string]$yes.outputName
        }
        Assert-DMatrix ($yes.schemaVersion -ceq 'r8_synthetic_r7_source_binding_v1' -and
            $yes.status -ceq 'complete' -and $yes.candidateCount -eq 1 -and
            $yes.decision -ceq 'synthetic_source_bound_output_verified_original_UNKNOWN' -and
            $yes.r7SourceSessionCount -eq 1 -and $yes.r8CandidateRereadSessionCount -eq 1 -and
            $yes.sourcePhaseAccounting -ceq 'two_separate_A_source_sessions_do_not_pool_unique_bytes' -and
            $yes.outputVerified -and $yes.outputBytes -eq 887 -and
            $yes.sourceAuthenticity -ceq 'not_real_media_authenticated' -and
            -not $yes.canExportOriginal -and -not $yes.originalShaVerified -and
            -not $yes.canSelectOriginal -and -not $yes.canRepairOriginal) ('SPC'+$spc+':one_candidate_synthetic_only')
        Assert-DMatrix ($yes.metrics.r7ActualReturnedBytes -gt 0L -and
            $yes.metrics.r7ActualReturnedBytes -le 120000L -and
            $yes.metrics.r7PhysicalReadCalls -gt 0 -and
            $yes.metrics.r7PhysicalReadCalls -le 512 -and
            $yes.metrics.r8CandidateActualReturnedBytes -eq 887L -and
            $yes.metrics.r8CandidateUniqueReturnedBytes -eq 887L -and
            $yes.metrics.r8CandidateRepeatedReturnedBytes -eq 0L -and
            $yes.metrics.r8CandidatePhysicalReadCalls -ge 2 -and
            $yes.metrics.r8CandidatePhysicalReadCalls -le 16 -and
            $yes.metrics.projectedCandidateBytes -eq 887L) ('SPC'+$spc+':physical_source_receipt_bounds')
        Assert-DMatrix ([IO.File]::Exists([string]$yes.outputPath) -and
            [string]::Equals([IO.Path]::GetDirectoryName([string]$yes.outputPath),$dir,[StringComparison]::OrdinalIgnoreCase) -and
            $yes.outputSha256 -ceq $oracleSha -and
            (Get-A3DSha256 ([IO.File]::ReadAllBytes([string]$yes.outputPath))) -ceq $oracleSha -and
            (Get-A3DSha256 $image) -ceq $sourceSha) ('SPC'+$spc+':private_scorer_only_and_source_immutable')

        # Same candidate/name cannot overwrite or delete the first successful output.
        $collision=Invoke-DMatrixBridge $image $dir @{}
        Assert-DMatrix ($collision.status -ceq 'partial' -and -not $collision.outputVerified -and
            @([IO.Directory]::GetFiles($dir)).Count -eq 1 -and
            (Get-A3DSha256 ([IO.File]::ReadAllBytes([string]$yes.outputPath))) -ceq $oracleSha) ('SPC'+$spc+':CreateNew_collision_owned_file_untouched')

        # The canonical ID is observed from A, but is never a selection hint passed in.
        $id=[string]$yes.r7CandidateId
        Assert-DMatrix ($id -cmatch '^3mf:([0-9]+)\+([0-9]+),([0-9]+)\+([0-9]+)$') ('SPC'+$spc+':bounded_canonical_R7_id')
        $head=[long]$Matches[1]
        $tail=[long]$Matches[3]
        Assert-DMatrix ($head -ge 0L -and $tail -ge 0L -and
            $head -le [long]$image.Length-4L -and
            $tail -le [long]$image.Length-512L) ('SPC'+$spc+':artificial_extent_bounds')

        # ZERO hypotheses: corrupt the generated ZIP local header (not an actual user source).
        [byte[]]$zero=[byte[]]$image.Clone()
        for($j=0;$j -lt 4;$j++){$zero[[int]$head+$j]=0}
        $zeroSha=Get-A3DSha256 $zero
        $zeroRoot=New-DMatrixRoot
        try {
            $none=Invoke-DMatrixBridge $zero $zeroRoot @{}
            Assert-DNoOutput $none $zeroRoot ('SPC'+$spc+':header_destroyed_no_output')
            Assert-DMatrix ($none.candidateCount -eq 0 -and
                $none.r8CandidateRereadSessionCount -eq 0 -and
                (Get-A3DSha256 $zero) -ceq $zeroSha) ('SPC'+$spc+':zero_candidate_unknown_not_winner')
            $script:cases++
        } finally {Remove-DMatrixRoot $zeroRoot}

        # MULTIPLE hypotheses: duplicate a generated 512-byte CRC-valid tail sector
        # into a previously vacant generated location, with NO scanner hints.
        [long]$from=[long][Math]::Floor([double]$tail / 512.0)*512L
        [long]$to=$from+6144L
        Assert-DMatrix ($to -gt ($from+512L) -and
            $to -gt ($head+1056L) -and
            $to -le ([long]$image.Length-512L)) ('SPC'+$spc+':duplicate_generated_tail_bounds')
        [byte[]]$multi=[byte[]]$image.Clone()
        [Array]::Copy($image,[int]$from,$multi,[int]$to,512)
        $multiSha=Get-A3DSha256 $multi
        $multiRoot=New-DMatrixRoot
        try {
            $ambiguous=Invoke-DMatrixBridge $multi $multiRoot @{}
            Assert-DNoOutput $ambiguous $multiRoot ('SPC'+$spc+':multiple_valid_source_hypotheses_no_output')
            Assert-DMatrix ($ambiguous.candidateCount -ge 2 -and
                $ambiguous.candidateCount -le 16 -and
                $ambiguous.r7SourceSessionCount -eq 1 -and
                $ambiguous.r8CandidateRereadSessionCount -eq 0 -and
                $ambiguous.warningCodes -contains 'r8.R7_missing_or_multiple_hypotheses_UNKNOWN' -and
                $ambiguous.metrics.r7ActualReturnedBytes -le 120000L -and
                (Get-A3DSha256 $multi) -ceq $multiSha) ('SPC'+$spc+':multiple_candidates_remain_UNKNOWN')
            $script:cases++
        } finally {Remove-DMatrixRoot $multiRoot}

        # Independent per-R7 budget and per-R8 physical-read cap failures.
        $quotaRoot=New-DMatrixRoot
        try {
            $quota=Invoke-DMatrixBridge $image $quotaRoot @{MaxR7ReturnedBytes=1024L}
            Assert-DNoOutput $quota $quotaRoot ('SPC'+$spc+':R7_global_quota_no_output')
            Assert-DMatrix ($quota.metrics.r7ActualReturnedBytes -le 1024L -and
                $quota.r8CandidateRereadSessionCount -eq 0) ('SPC'+$spc+':R7_measured_budget_not_inferred')
            $cap=Invoke-DMatrixBridge $image $quotaRoot @{MaxCandidateReadCalls=1}
            Assert-DNoOutput $cap $quotaRoot ('SPC'+$spc+':R8_per_session_read_cap_no_output')
            Assert-DMatrix ($cap.r8CandidateRereadSessionCount -eq 1 -and
                $cap.metrics.r7ActualReturnedBytes -le 120000L) ('SPC'+$spc+':R8_second_meter_early_abort')
            $script:cases+=2
        } finally {Remove-DMatrixRoot $quotaRoot}

        # A real Stream.Read returns three synthetic bytes, then a genuine zero.
        # This is different from a quota exception and is not "file absent".
        $eofRoot=New-DMatrixRoot
        $three=[ChappyDR8P6ThreeThenZero]::new($image)
        try {
            $short=Export-ChappyR8SourceBoundSyntheticCandidateV1 -Source $three -OutputRoot $eofRoot -SyntheticFixtureTag 'A3D-standard-202611' -EnableSyntheticR7SourceBindingAndExport
            Assert-DNoOutput $short $eofRoot ('SPC'+$spc+':true_3B_then_zero_no_output')
            Assert-DMatrix ($short.metrics.r7ActualReturnedBytes -eq 3L -and
                $short.r8CandidateRereadSessionCount -eq 0) ('SPC'+$spc+':true_short_source_receipt')
            $script:cases++
        } finally {$three.Dispose();Remove-DMatrixRoot $eofRoot}

        # Synthetic injected failure must not leave any file in test-owned root.
        $failureRoot=New-DMatrixRoot
        try {
            $failure=Invoke-DMatrixBridge $image $failureRoot @{InjectSyntheticWriteFailure=$true}
            Assert-DNoOutput $failure $failureRoot ('SPC'+$spc+':injected_write_failure_owned_cleanup')
            $script:cases++
        } finally {Remove-DMatrixRoot $failureRoot}
        Assert-DMatrix ((Get-A3DSha256 $image) -ceq $sourceSha -and
            @([IO.Directory]::GetFiles($dir)).Count -eq 1) ('SPC'+$spc+':baseline_source_and_output_untouched')
        $script:cases+=3 # default-off, positive one-candidate export and CreateNew collision.
        Write-Host ('D R8-P6: SPC{0} candidate=1 R7={1}B/{2}calls R8={3}B/{4}calls, zero/multiple/quotas/EOF/failure=NO_EXPORT original=UNKNOWN' -f
            $spc,$yes.metrics.r7ActualReturnedBytes,$yes.metrics.r7PhysicalReadCalls,$yes.metrics.r8CandidateActualReturnedBytes,$yes.metrics.r8CandidatePhysicalReadCalls)
    } finally {
        $cleanupSha=if($ownedOutputPath){$oracleSha}else{''}
        Remove-DMatrixRoot -Path $dir -ExpectedFilePath $ownedOutputPath -ExpectedFileName $ownedOutputName -ExpectedSha256 $cleanupSha
    }
}
Assert-DMatrix ($script:cases -eq 18) 'exact_tested_synthetic_case_denominator'
Write-Host ('PASS: D R8-P6 {0} generated-only scenario groups, {1} assertions; never original-media success.' -f $script:cases,$script:checks)
