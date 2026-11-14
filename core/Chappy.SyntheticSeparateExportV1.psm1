#Requires -Version 5.1
# R8 Team A: first-stage, disposable synthetic-only candidate export.
# No FileStream source, physical microSD/IMG input or original-byte authority.
Set-StrictMode -Version Latest

function Get-ChappyR8SyntheticSha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') }
    finally { $sha.Dispose() }
}
function Test-ChappyR8SyntheticRoot {
    param([string]$Root,[string]$SourceRootForDisjointness)
    if([string]::IsNullOrWhiteSpace($Root) -or
       $Root -match '(^\\\\|^//|[/\\]\.\.?([/\\]|$))' -or
       $Root -match '(^\\\\\?\\|^\\\\\.\\) -or
       ($Root.Length -ge 3 -and $Root.Substring(2) -match ':')') {
        return $null
    }
    if(-not [IO.Path]::IsPathRooted($Root)){return $null}
    try{
        $full=[IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\','/'))
        $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/'))
        $parent=[IO.Path]::GetDirectoryName($full).TrimEnd([char[]]@('\','/'))
        $name=[IO.Path]::GetFileName($full)
        # Accept ONLY one unique disposable generated-test directory directly
        # below the OS temporary directory, never arbitrary output folders.
        if(-not [string]::Equals($parent,$temp,[StringComparison]::OrdinalIgnoreCase) -or
           $name -cnotmatch '^ChappyR8Synthetic-[0-9a-f]{32}$' -or
           -not [IO.Directory]::Exists($full)){
            return $null
        }
        $attributes=[IO.File]::GetAttributes($full)
        if(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
           ($attributes -band [IO.FileAttributes]::Directory) -eq 0){
            return $null
        }
        if(-not [string]::IsNullOrWhiteSpace($SourceRootForDisjointness)){
            if(-not [IO.Path]::IsPathRooted($SourceRootForDisjointness) -or
               $SourceRootForDisjointness -match '(^\\\\|^//|[/\\]\.\.?([/\\]|$))' -or
               $SourceRootForDisjointness -match '(^\\\\\?\\|^\\\\\.\\) -or
               ($SourceRootForDisjointness.Length -ge 3 -and $SourceRootForDisjointness.Substring(2) -match ':')'){
                return $null
            }
            # This is ONLY a caller-declared synthetic source location
            # for path-disjointness checks. Never inspect or read that path.
            $source=[IO.Path]::GetFullPath($SourceRootForDisjointness).TrimEnd([char[]]@('\','/'))
            $slash=[string][IO.Path]::DirectorySeparatorChar
            if([string]::Equals($full,$source,[StringComparison]::OrdinalIgnoreCase) -or
               $full.StartsWith(($source+$slash),[StringComparison]::OrdinalIgnoreCase) -or
               $source.StartsWith(($full+$slash),[StringComparison]::OrdinalIgnoreCase)){
                return $null
            }
        }
        return $full
    }catch{return $null}
}
function Export-ChappyR8SyntheticCandidateV1 {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory)][byte[]]$SourceBytes,
        [Parameter(Mandatory)][string]$CandidateId,
        [Parameter(Mandatory)][object[]]$OrderedExtents,
        [Parameter(Mandatory)][string]$OutputRoot,
        [Parameter(Mandatory)][string]$SyntheticFixtureTag,
        [string]$SourceRootForDisjointness='',
        [switch]$EnableSyntheticExport,
        [ValidateRange(1,8192)][int]$MaxOutputBytes=4096,
        # Fault injection is synthetic-test-only; never a real-file mechanism.
        [switch]$InjectSyntheticWriteFailure
    )
    $result=[ordered]@{
        schemaVersion='r8_synthetic_separate_export_v1'
        status='disabled';decision='not_requested'
        outputPath=$null;outputName=$null;outputBytes=0
        outputSha256=$null;sourceUnchanged=$null;outputVerified=$false
        originalIdentity='unknown';originalShaVerified=$false
        originalSourceAuthenticated=$false;canExportOriginal=$false
        outputScope='generated_test_bytes_only'
        warningCodes=@('r8.default_disabled')
    }
    # No filesystem read/access when mode is disabled.
    if(-not $EnableSyntheticExport){return [pscustomobject]$result}
    $result.status='rejected'
    $result.decision='unknown'
    $result.warningCodes=@('r8.unsafe_or_unverified_synthetic_export_request')
    # Byte arrays are a caller-supplied artificial input, never a path or
    # a source stream. The label is NOT a cryptographic authenticity proof.
    if($SourceBytes.Length -lt 1024 -or $SourceBytes.Length -gt 131072 -or
       $SyntheticFixtureTag -cnotmatch '^A3D-(clean|standard)-[0-9]{1,6}$' -or
       $CandidateId -cnotmatch '^3mf:[0-9]+\+[0-9]+,[0-9]+\+[0-9]+$' -or
       @($OrderedExtents).Count -ne 2){
        return [pscustomobject]$result
    }
    [long]$total=0
    $parts=New-Object 'System.Collections.Generic.List[object]'
    foreach($p in @($OrderedExtents)){
        if($null -eq $p -or $null -eq $p.PSObject.Properties['offsetBytes'] -or
           $null -eq $p.PSObject.Properties['lengthBytes'] -or
           ($p.offsetBytes -isnot [int] -and $p.offsetBytes -isnot [long]) -or
           ($p.lengthBytes -isnot [int] -and $p.lengthBytes -isnot [long])){
            return [pscustomobject]$result
        }
        [long]$start=$p.offsetBytes;[long]$size=$p.lengthBytes
        if($start -lt 0 -or $size -le 0 -or
           $size -gt $MaxOutputBytes -or
           $start -gt ([long]$SourceBytes.Length-$size)){
            return [pscustomobject]$result
        }
        $total+=$size
        if($total -gt $MaxOutputBytes){return [pscustomobject]$result}
        $parts.Add([pscustomobject]@{offsetBytes=$start;lengthBytes=$size})
    }
    $a=$parts[0];$b=$parts[1]
    if(([long]$a.offsetBytes -lt [long]$b.offsetBytes+[long]$b.lengthBytes) -and
       ([long]$b.offsetBytes -lt [long]$a.offsetBytes+[long]$a.lengthBytes)){
        return [pscustomobject]$result
    }
    $canonical=('3mf:{0}+{1},{2}+{3}' -f
        $a.offsetBytes,$a.lengthBytes,$b.offsetBytes,$b.lengthBytes)
    if($CandidateId -cne $canonical){return [pscustomobject]$result}
    $root=Test-ChappyR8SyntheticRoot -Root $OutputRoot -SourceRootForDisjointness $SourceRootForDisjointness
    if($null -eq $root){return [pscustomobject]$result}
    $idHash=Get-ChappyR8SyntheticSha256 ([Text.Encoding]::ASCII.GetBytes($CandidateId))
    $filename=('candidate-'+$idHash.Substring(0,32)+'.3mf')
    $destination=[IO.Path]::Combine($root,$filename)
    if(-not [string]::Equals([IO.Path]::GetDirectoryName($destination),$root,[StringComparison]::OrdinalIgnoreCase)){
        return [pscustomobject]$result
    }
    # End all metadata/source/path validation BEFORE any output write.
    $sourceBefore=Get-ChappyR8SyntheticSha256 $SourceBytes
    [byte[]]$candidate=[byte[]]::new([int]$total)
    [int]$cursor=0
    foreach($part in $parts){
        [Array]::Copy($SourceBytes,[int]$part.offsetBytes,$candidate,$cursor,[int]$part.lengthBytes)
        $cursor+=[int]$part.lengthBytes
    }
    $candidateSha=Get-ChappyR8SyntheticSha256 $candidate
    $createdByThisCall=$false
    $file=$null
    try{
        # CREATE NEW is atomic with respect to an existing file name; NO
        # FileMode.Create, truncation, deleting an unrelated preexisting file.
        $file=[IO.FileStream]::new($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $createdByThisCall=$true
        [int]$written=0
        while($written -lt $candidate.Length){
            [int]$n=[Math]::Min(256,$candidate.Length-$written)
            $file.Write($candidate,$written,$n)
            $written+=$n
            if($InjectSyntheticWriteFailure){throw 'r8.synthetic_injected_write_failure'}
        }
        $file.Flush($true)
        $file.Dispose();$file=$null
        [byte[]]$verify=[IO.File]::ReadAllBytes($destination)
        if($verify.Length -ne $candidate.Length -or
           (Get-ChappyR8SyntheticSha256 $verify) -cne $candidateSha){
            throw 'r8.synthetic_export_digest_mismatch'
        }
        if((Get-ChappyR8SyntheticSha256 $SourceBytes) -cne $sourceBefore){
            throw 'r8.synthetic_source_mutated_during_export'
        }
        $result.status='complete'
        $result.decision='synthetic_output_sha_verified_original_UNKNOWN'
        $result.outputPath=$destination;$result.outputName=$filename
        $result.outputBytes=$candidate.Length;$result.outputSha256=$candidateSha
        $result.sourceUnchanged=$true;$result.outputVerified=$true
        $result.warningCodes=@('r8.generated_only_not_real_source','r8.original_identity_unknown')
    }catch{
        # Do not delete a file that existed before this call. Cleanup applies
        # only when CreateNew succeeded in this invocation, within disposable
        # synthetic temp root. Race-proof reparse/root handles are future R8 work.
        $result.status='partial'
        $result.decision='synthetic_export_failed_UNKNOWN'
        $result.warningCodes=@('r8.write_or_collision_failed_no_original_export')
    }finally{
        if($null -ne $file){$file.Dispose()}
        if($createdByThisCall -and $result.status -cne 'complete'){
            try {
                $attrs=[IO.File]::GetAttributes($destination)
                if(($attrs -band [IO.FileAttributes]::ReparsePoint) -eq 0){
                    [IO.File]::Delete($destination)
                }
            }catch{}
        }
    }
    return [pscustomobject]$result
}
Export-ModuleMember -Function Export-ChappyR8SyntheticCandidateV1
