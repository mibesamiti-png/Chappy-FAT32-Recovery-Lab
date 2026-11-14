#Requires -Version 5.1
# Team A first-stage R8: only generated synthetic bytes, temp destination.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-Chappy3DCleanFixture.ps1')
Import-Module (Join-Path $root 'core\Chappy.SyntheticSeparateExportV1.psm1') -Force
function Assert-R8([bool]$OK,[string]$Why) {
    if(-not $OK){throw ('A_R8_SYNTHETIC_EXPORT_FAIL: '+$Why)}
}
# Windows PowerShell 5.1 does NOT allow explicit overriding of splatted keys.
function Invoke-R8CaseOverride {
    param([hashtable]$Parameters,[string]$Key,[object]$Value)
    $copy=$Parameters.Clone()
    $copy[$Key]=$Value
    return Export-ChappyR8SyntheticCandidateV1 @copy -EnableSyntheticExport
}

$fixture=New-ChappyA3DCleanFixture -Seed 202611
$matches=@($fixture.oracle | Where-Object {$_.shortName -ceq 'MODEL   3MF'})
Assert-R8 ($matches.Count -eq 1) 'synthetic_original_3mf_exists'
$oracle=$matches[0]
# First 64KiB of the generated compact test image. Never a file path input.
[byte[]]$source=[byte[]]::new(65536)
[Array]::Copy($fixture.image,0,$source,0,$source.Length)
$sourceSha=Get-A3DSha256 $source
$ordered=@($oracle.extents | ForEach-Object {
    [pscustomobject]@{offsetBytes=[long]$_.offsetBytes;lengthBytes=[long]$_.lengthBytes}
})
Assert-R8 ($ordered.Count -eq 2 -and
    ($ordered | Measure-Object -Property lengthBytes -Sum).Sum -eq [long]$oracle.lengthBytes -and
    [long]$oracle.lengthBytes -le 4096) 'synthetic_two_piece_extents'
$candidateId=('3mf:{0}+{1},{2}+{3}' -f
    $ordered[0].offsetBytes,$ordered[0].lengthBytes,$ordered[1].offsetBytes,$ordered[1].lengthBytes)
$directory=Join-Path ([IO.Path]::GetTempPath()) ('ChappyR8Synthetic-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
try {
    $arguments=@{
        SourceBytes=$source;CandidateId=$candidateId;OrderedExtents=$ordered
        OutputRoot=$directory;SyntheticFixtureTag='A3D-clean-202611'
    }
    $off=Export-ChappyR8SyntheticCandidateV1 @arguments
    Assert-R8 ($off.status -ceq 'disabled' -and $off.outputPath -eq $null -and
        @([IO.Directory]::GetFiles($directory)).Count -eq 0 -and
        (Get-A3DSha256 $source) -ceq $sourceSha) 'disabled_no_output'
    $good=Export-ChappyR8SyntheticCandidateV1 @arguments -EnableSyntheticExport
    Assert-R8 ($good.schemaVersion -ceq 'r8_synthetic_separate_export_v1' -and
        $good.status -ceq 'complete' -and
        $good.decision -ceq 'synthetic_output_sha_verified_original_UNKNOWN' -and
        $good.outputBytes -eq [int]$oracle.lengthBytes -and
        $good.outputVerified -and $good.sourceUnchanged -and
        -not $good.canExportOriginal -and -not $good.originalShaVerified -and
        $good.originalIdentity -ceq 'unknown' -and
        $good.outputName -match '^candidate-[0-9A-F]{32}\.3mf$' -and
        [IO.File]::Exists($good.outputPath) -and
        [string]::Equals([IO.Path]::GetDirectoryName($good.outputPath),$directory,
          [StringComparison]::OrdinalIgnoreCase)) 'CreateNew_to_only_explicit_synthetic_temp_root'
    $oracleSha=[string]$oracle.sha256
    Assert-R8 ($good.outputSha256 -ceq $oracleSha -and
        (Get-A3DSha256 ([IO.File]::ReadAllBytes($good.outputPath))) -ceq $oracleSha -and
        (Get-A3DSha256 $source) -ceq $sourceSha) 'external_oracle_SHA_and_source_unchanged'
    # Same deterministic name must fail without touching the existing file.
    $duplicate=Export-ChappyR8SyntheticCandidateV1 @arguments -EnableSyntheticExport
    Assert-R8 ($duplicate.status -ceq 'partial' -and
        $duplicate.decision -ceq 'synthetic_export_failed_UNKNOWN' -and
        (Get-A3DSha256 ([IO.File]::ReadAllBytes($good.outputPath))) -ceq $oracleSha -and
        @([IO.Directory]::GetFiles($directory)).Count -eq 1) 'no_overwrite_or_delete_existing_file'
    # Distinct canonical ID, own new path, forced short write, cleanup only own.
    $alternate=@(
        [pscustomobject]@{offsetBytes=[long]$ordered[0].offsetBytes;lengthBytes=([long]$ordered[0].lengthBytes-1)},
        [pscustomobject]@{offsetBytes=[long]$ordered[1].offsetBytes;lengthBytes=[long]$ordered[1].lengthBytes}
    )
    $alternateId=('3mf:{0}+{1},{2}+{3}' -f
        $alternate[0].offsetBytes,$alternate[0].lengthBytes,$alternate[1].offsetBytes,$alternate[1].lengthBytes)
    $fault=Export-ChappyR8SyntheticCandidateV1 -SourceBytes $source -CandidateId $alternateId -OrderedExtents $alternate -OutputRoot $directory -SyntheticFixtureTag 'A3D-clean-202611' -EnableSyntheticExport -InjectSyntheticWriteFailure
    Assert-R8 ($fault.status -ceq 'partial' -and $fault.outputPath -eq $null -and
        @([IO.Directory]::GetFiles($directory)).Count -eq 1 -and
        (Get-A3DSha256 ([IO.File]::ReadAllBytes($good.outputPath))) -ceq $oracleSha) 'simulated_write_failure_only_owned_cleanup'
    $reversed=Invoke-R8CaseOverride -Parameters $arguments -Key 'OrderedExtents' -Value @($ordered[1],$ordered[0])
    Assert-R8 ($reversed.status -ceq 'rejected') 'reordered_span_without_new_ID_deny'
    $overlap=@($ordered[0],$ordered[0])
    $overlapId=('3mf:{0}+{1},{2}+{3}' -f $overlap[0].offsetBytes,$overlap[0].lengthBytes,$overlap[1].offsetBytes,$overlap[1].lengthBytes)
    $overlapArgs=$arguments.Clone()
    $overlapArgs.CandidateId=$overlapId
    $overlapArgs.OrderedExtents=$overlap
    $overlapRejected=Export-ChappyR8SyntheticCandidateV1 @overlapArgs -EnableSyntheticExport
    Assert-R8 ($overlapRejected.status -ceq 'rejected') 'overlapping_extents_denied'
    $quota=Export-ChappyR8SyntheticCandidateV1 @arguments -EnableSyntheticExport -MaxOutputBytes ([int]$oracle.lengthBytes-1)
    Assert-R8 ($quota.status -ceq 'rejected') 'strict_output_quota'
    $same=Export-ChappyR8SyntheticCandidateV1 @arguments -EnableSyntheticExport -SourceRootForDisjointness $directory
    Assert-R8 ($same.status -ceq 'rejected') 'declared_source_output_same_denied'
    $nested=Join-Path $directory 'subfolder'
    $inside=Export-ChappyR8SyntheticCandidateV1 @arguments -EnableSyntheticExport -SourceRootForDisjointness $nested
    Assert-R8 ($inside.status -ceq 'rejected') 'declared_source_below_output_denied'
    $parent=Invoke-R8CaseOverride -Parameters $arguments -Key 'OutputRoot' -Value ([IO.Path]::GetTempPath())
    Assert-R8 ($parent.status -ceq 'rejected') 'arbitrary_temp_root_denied'
    $nestedRoot=Invoke-R8CaseOverride -Parameters $arguments -Key 'OutputRoot' -Value $nested
    Assert-R8 ($nestedRoot.status -ceq 'rejected') 'nested_output_root_denied'
    $traversal=Invoke-R8CaseOverride -Parameters $arguments -Key 'OutputRoot' -Value (Join-Path $directory '..')
    Assert-R8 ($traversal.status -ceq 'rejected') 'traversal_denied'
    $ads=Invoke-R8CaseOverride -Parameters $arguments -Key 'OutputRoot' -Value ($directory+':meta')
    Assert-R8 ($ads.status -ceq 'rejected') 'ADS_denied'
    $unc=Invoke-R8CaseOverride -Parameters $arguments -Key 'OutputRoot' -Value '\\server\share\out'
    Assert-R8 ($unc.status -ceq 'rejected') 'UNC_denied'
    $device=Invoke-R8CaseOverride -Parameters $arguments -Key 'OutputRoot' -Value '\\.\C:\notallowed'
    Assert-R8 ($device.status -ceq 'rejected') 'device_path_denied'
    $badId=Invoke-R8CaseOverride -Parameters $arguments -Key 'CandidateId' -Value '3mf:../../a'
    Assert-R8 ($badId.status -ceq 'rejected') 'filename_not_user_controlled'
    $tag=Invoke-R8CaseOverride -Parameters $arguments -Key 'SyntheticFixtureTag' -Value 'non-synthetic'
    Assert-R8 ($tag.status -ceq 'rejected') 'synthetic_label_required'
    [byte[]]$tooBig=[byte[]]::new(131073)
    $large=Invoke-R8CaseOverride -Parameters $arguments -Key 'SourceBytes' -Value $tooBig
    Assert-R8 ($large.status -ceq 'rejected') 'source_bytes_strict_cap'
    Assert-R8 (@([IO.Directory]::GetFiles($directory)).Count -eq 1 -and
        (Get-A3DSha256 $source) -ceq $sourceSha) 'all_denials_leave_source_and_existing_output_unchanged'
    Write-Host ('R8 SYNTHETIC VERIFIED: exportedB={0} externalOracleSHA=YES sourceUnchanged=YES collision=CREATE_NEW_DENIED failedWrite=OWNED_FILE_CLEANUP originalUnknown=YES' -f $good.outputBytes)
}finally{
    # Only a freshly generated, owned, disposable synthetic test directory.
    if([IO.Directory]::Exists($directory)){[IO.Directory]::Delete($directory,$true)}
}
Write-Host 'PASS: R8 temp-only synthetic CreateNew export, collision, path/root, quota, SHA and failure cleanup checks.'
