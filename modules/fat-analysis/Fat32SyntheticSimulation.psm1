#Requires -Version 5.1
# Team D R2: Synthetic byte-array FAT patch simulation. NO disk/file opening or writes.
Set-StrictMode -Version 2.0

function Get-D2Hash {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $h=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($h.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant() }
    finally { $h.Dispose() }
}
function Get-D2Hex {
    param([uint32]$Value)
    return [BitConverter]::ToString([BitConverter]::GetBytes($Value)).Replace('-','')
}
function Assert-D2Fixture {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    if ($Bytes.LongLength -lt 4096 -or $Bytes.LongLength -gt 8388608) {throw 'Synthetic R2 image length must be 4 KiB .. 8 MiB'}
    if ([Text.Encoding]::ASCII.GetString($Bytes,480,15) -cne 'CHAPPY-SYNTH-R2') {throw 'Synthetic fixture marker missing; real IMG inputs prohibited'}
    if ($Bytes[0] -ne 0xEB -or $Bytes[2] -ne 0x90 -or $Bytes[510] -ne 0x55 -or $Bytes[511] -ne 0xAA) {throw 'Synthetic VBR signature invalid'}
    $bps=[BitConverter]::ToUInt16($Bytes,11)
    $spc=[int]$Bytes[13]
    $reserved=[BitConverter]::ToUInt16($Bytes,14)
    $fatCount=[int]$Bytes[16]
    $fatSectors=[BitConverter]::ToUInt32($Bytes,36)
    if ($bps -ne 512 -or $spc -eq 0 -or ($spc -band ($spc - 1)) -ne 0 -or $reserved -lt 1 -or $fatCount -ne 2 -or $fatSectors -lt 1) {
        throw 'Only explicit two-FAT, 512 B/sector synthetic fixtures supported'
    }
    $fatOffset=[long]$reserved * $bps
    $fatBytes=[long]$fatSectors * $bps
    $dataOffset=$fatOffset+2*$fatBytes
    if ($fatBytes -lt 16 -or $dataOffset -ge $Bytes.LongLength) {throw 'Synthetic FAT range outside memory image'}
    return [pscustomobject]@{FatOffset=$fatOffset;FatBytes=$fatBytes;MaxEntry=[long]($fatBytes/4)}
}
function New-ChappySyntheticFatPatchPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][byte[]]$ImageBytes,
        [Parameter(Mandatory=$true)][object[]]$Proposals,
        [ValidateSet('FAT_RESERVED','ROOT_CHAIN','MIRROR_DIVERGENCE','SYNTHETIC_EXPERIMENT')][string]$ReasonCode='SYNTHETIC_EXPERIMENT'
    )
    $g=Assert-D2Fixture $ImageBytes
    if ($Proposals.Count -lt 1 -or $Proposals.Count -gt 32) {throw 'Exactly 1..32 explicit synthetic patches required'}
    $patches=New-Object System.Collections.ArrayList
    $seen=New-Object 'System.Collections.Generic.HashSet[long]'
    foreach ($proposal in $Proposals) {
        if ($null -eq $proposal) {throw 'Null patch'}
        try {
            $fat=[int]$proposal.FatIndex
            $entry=[long]$proposal.EntryIndex
            $before=[uint32]$proposal.ExpectedValue
            $after=[uint32]$proposal.ProposedValue
        } catch {throw 'Patch must contain FatIndex, EntryIndex, ExpectedValue, ProposedValue'}
        if ($fat -lt 0 -or $fat -gt 1 -or $entry -lt 0 -or $entry -ge $g.MaxEntry) {throw 'Patch must target an aligned FAT32 entry within either FAT'}
        $position=[long]$g.FatOffset+[long]$fat*$g.FatBytes+$entry*4
        if (-not $seen.Add($position)) {throw 'Overlapping/duplicate FAT entry patch'}
        $observed=[BitConverter]::ToUInt32($ImageBytes,[int]$position)
        if ($observed -ne $before) {throw 'Before-value mismatch; refusing to construct patch'}
        if ($before -eq $after) {throw 'No-op patch rejected'}
        [void]$patches.Add([pscustomobject]@{
            FatIndex=$fat;EntryIndex=$entry;OffsetBytes=$position;ExpectedValue=$before;ProposedValue=$after;
            BeforeHex=(Get-D2Hex $before);AfterHex=(Get-D2Hex $after);ReasonCode=$ReasonCode;Confidence='unknown'
        })
    }
    return [pscustomobject]@{
        Schema='chappy.teamD.synthetic.plan.v1';Role='Forward';Mode='SYNTHETIC_MEMORY_ONLY';
        WritePermitted=$false;RequiresHumanReview=$true;SyntheticOnly=$true;
        ImageLength=$ImageBytes.LongLength;ImageSha256=(Get-D2Hash $ImageBytes);
        Patches=@($patches | Sort-Object OffsetBytes)
    }
}
function Invoke-ChappySyntheticFatPatchSimulation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][byte[]]$ImageBytes,
        [Parameter(Mandatory=$true)][psobject]$Plan
    )
    $g=Assert-D2Fixture $ImageBytes
    if ($Plan.Schema -cne 'chappy.teamD.synthetic.plan.v1' -or $Plan.Mode -cne 'SYNTHETIC_MEMORY_ONLY' -or
        $Plan.WritePermitted -ne $false -or $Plan.SyntheticOnly -ne $true -or $Plan.RequiresHumanReview -ne $true) {
        throw 'Unrecognized or unsafe plan'
    }
    $originalHash=Get-D2Hash $ImageBytes
    if ($Plan.ImageSha256 -cne $originalHash -or [long]$Plan.ImageLength -ne $ImageBytes.LongLength) {
        throw 'Source SHA-256 or image length mismatch'
    }
    $patches=@($Plan.Patches)
    if ($patches.Count -lt 1 -or $patches.Count -gt 32) {throw 'Plan patch limit exceeded'}
    $seen=New-Object 'System.Collections.Generic.HashSet[long]'
    # Complete validation happens before the clone is modified.
    foreach ($patch in $patches) {
        $fat=[int]$patch.FatIndex;$entry=[long]$patch.EntryIndex
        if ($fat -lt 0 -or $fat -gt 1 -or $entry -lt 0 -or $entry -ge $g.MaxEntry) {throw 'Out-of-range FAT entry in plan'}
        $calculated=[long]$g.FatOffset+[long]$fat*$g.FatBytes+$entry*4
        if ([long]$patch.OffsetBytes -ne $calculated -or -not $seen.Add($calculated)) {throw 'Misaligned, duplicate or forged patch offset'}
        $existing=[BitConverter]::ToUInt32($ImageBytes,[int]$calculated)
        if ([uint32]$patch.ExpectedValue -ne $existing -or [uint32]$patch.ProposedValue -eq $existing) {
            throw 'Patch expected value incorrect or no change'
        }
        if ($patch.BeforeHex -cne (Get-D2Hex ([uint32]$patch.ExpectedValue)) -or
            $patch.AfterHex -cne (Get-D2Hex ([uint32]$patch.ProposedValue))) {throw 'Patch hex manifest mismatch'}
    }
    $clone=[byte[]]$ImageBytes.Clone()
    $diff=New-Object System.Collections.ArrayList
    $reverse=New-Object System.Collections.ArrayList
    $byteChanges=0
    foreach ($patch in $patches) {
        $position=[int]$patch.OffsetBytes
        $old=[BitConverter]::GetBytes([uint32]$patch.ExpectedValue)
        $new=[BitConverter]::GetBytes([uint32]$patch.ProposedValue)
        for($i=0;$i -lt 4;$i++){if($old[$i] -ne $new[$i]){$byteChanges++}}
        [Array]::Copy($new,0,$clone,$position,4)
        [void]$diff.Add([pscustomobject]@{
            OffsetBytes=[long]$position;LengthBytes=4;BeforeHex=$patch.BeforeHex;AfterHex=$patch.AfterHex;
            FatIndex=$patch.FatIndex;EntryIndex=$patch.EntryIndex;ReasonCode=$patch.ReasonCode;Confidence='unknown'
        })
        [void]$reverse.Add([pscustomobject]@{
            FatIndex=$patch.FatIndex;EntryIndex=$patch.EntryIndex;OffsetBytes=$patch.OffsetBytes;
            ExpectedValue=[uint32]$patch.ProposedValue;ProposedValue=[uint32]$patch.ExpectedValue;
            BeforeHex=$patch.AfterHex;AfterHex=$patch.BeforeHex;ReasonCode='SYNTHETIC_EXPERIMENT';Confidence='unknown'
        })
    }
    $afterHash=Get-D2Hash $clone
    if ($afterHash -ceq $originalHash) {throw 'Unexpected identical hash after non-empty patch'}
    $rollback=[pscustomobject]@{
        Schema='chappy.teamD.synthetic.plan.v1';Role='Rollback';Mode='SYNTHETIC_MEMORY_ONLY';
        WritePermitted=$false;RequiresHumanReview=$true;SyntheticOnly=$true;
        ImageLength=$clone.LongLength;ImageSha256=$afterHash;Patches=@($reverse)
    }
    return [pscustomobject]@{
        Schema='chappy.teamD.synthetic.simulation.v1';Mode='SYNTHETIC_MEMORY_ONLY';WritePermitted=$false;
        OriginalSha256=$originalHash;SimulatedSha256=$afterHash;OriginalLength=$ImageBytes.LongLength;
        ModifiedByteCount=$byteChanges;PatchCount=$patches.Count;Diff=@($diff);
        RollbackPlan=$rollback;SimulatedImageBytes=$clone;
        OriginalInputUnchanged=((Get-D2Hash $ImageBytes) -ceq $originalHash);
        Conclusions='Artificial in-memory experiment only; a hash match after rollback does not validate any real repair.'
    }
}
Export-ModuleMember -Function New-ChappySyntheticFatPatchPlan,Invoke-ChappySyntheticFatPatchSimulation
