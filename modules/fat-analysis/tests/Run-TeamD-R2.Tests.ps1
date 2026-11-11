#Requires -Version 5.1
# Team D R2 tests: all bytes are synthetic and remain in memory.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\Fat32SyntheticSimulation.psm1') -Force
$script:Pass=0;$script:Fail=0
function Assert-R2 {
    param([bool]$Condition,[string]$Name)
    if($Condition){Write-Host "PASS $Name";$script:Pass++}
    else{Write-Host "FAIL $Name";$script:Fail++}
}
function Throws-R2 {
    param([scriptblock]$Code)
    try { $null=& $Code; return $false } catch {return $true}
}
function Put-R2U16 {
    param([byte[]]$B,[int]$Offset,[uint16]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$B,$Offset,2)
}
function Put-R2U32 {
    param([byte[]]$B,[int]$Offset,[uint32]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$B,$Offset,4)
}
function Hash-R2 {
    param([byte[]]$B)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($B)).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}
function New-R2Fixture {
    $b=New-Object 'byte[]' 1048576
    $b[0]=0xEB;$b[1]=0x58;$b[2]=0x90
    Put-R2U16 $b 11 512
    $b[13]=1
    Put-R2U16 $b 14 32
    $b[16]=2;$b[21]=0xF8
    Put-R2U32 $b 32 2048
    Put-R2U32 $b 36 32
    Put-R2U32 $b 44 2
    $b[510]=0x55;$b[511]=0xAA
    [Text.Encoding]::ASCII.GetBytes('CHAPPY-SYNTH-R2').CopyTo($b,480)
    $first=32*512;$second=(32+32)*512
    $bad=[Convert]::ToUInt32('EB58EB58',16)
    Put-R2U32 $b $first $bad
    Put-R2U32 $b ($first+4) ([Convert]::ToUInt32('0FFFFFFF',16))
    Put-R2U32 $b ($first+8) ([Convert]::ToUInt32('0FFFFFFF',16))
    Put-R2U32 $b $second $bad
    Put-R2U32 $b ($second+4) ([Convert]::ToUInt32('0FFFFFFF',16))
    Put-R2U32 $b ($second+8) ([Convert]::ToUInt32('0FFFFFFF',16))
    return ,$b
}
$source=New-R2Fixture
$sourceHash=Hash-R2 $source
$bad=[Convert]::ToUInt32('EB58EB58',16)
$expected=[Convert]::ToUInt32('0FFFFFF8',16)
$a=[pscustomobject]@{FatIndex=0;EntryIndex=0;ExpectedValue=$bad;ProposedValue=$expected}
$b=[pscustomobject]@{FatIndex=1;EntryIndex=0;ExpectedValue=$bad;ProposedValue=$expected}
$plan=New-ChappySyntheticFatPatchPlan -ImageBytes $source -Proposals @($b,$a) -ReasonCode FAT_RESERVED
Assert-R2 ($plan.Schema -eq 'chappy.teamD.synthetic.plan.v1' -and $plan.WritePermitted -eq $false) 'Plan can never authorize writes'
Assert-R2 ($plan.Patches.Count -eq 2 -and $plan.Patches[0].OffsetBytes -eq (32*512)) 'Patches sorted by real FAT offset'
Assert-R2 ($plan.Patches[0].BeforeHex -eq '58EB58EB') 'Hex payload is little-endian'
Assert-R2 ($plan.Patches[0].Confidence -eq 'unknown') 'Repair confidence remains unknown'
$sim=Invoke-ChappySyntheticFatPatchSimulation -ImageBytes $source -Plan $plan
Assert-R2 ($sim.Mode -eq 'SYNTHETIC_MEMORY_ONLY' -and $sim.WritePermitted -eq $false) 'Simulation strictly in-memory'
Assert-R2 ($sim.ModifiedByteCount -gt 0 -and $sim.PatchCount -eq 2 -and $sim.Diff.Count -eq 2) 'Bounded range diff report emitted'
Assert-R2 ((Hash-R2 $source) -eq $sourceHash -and $sim.OriginalInputUnchanged) 'Original input byte array unchanged'
Assert-R2 ((Hash-R2 $sim.SimulatedImageBytes) -eq $sim.SimulatedSha256 -and $sim.SimulatedSha256 -ne $sourceHash) 'Simulated hash matches clone only'
Assert-R2 ([BitConverter]::ToUInt32($sim.SimulatedImageBytes,(32*512)) -eq $expected -and [BitConverter]::ToUInt32($source,(32*512)) -eq $bad) 'Correct FAT entry modified on clone'
Assert-R2 ($sim.RollbackPlan.Role -eq 'Rollback' -and $sim.RollbackPlan.ImageSha256 -eq $sim.SimulatedSha256) 'Rollback is bound to simulated SHA'
$undo=Invoke-ChappySyntheticFatPatchSimulation -ImageBytes $sim.SimulatedImageBytes -Plan $sim.RollbackPlan
Assert-R2 ($undo.SimulatedSha256 -eq $sourceHash) 'In-memory rollback restores whole synthetic image SHA'
Assert-R2 ((Hash-R2 $source) -eq $sourceHash) 'Rollback does not mutate original array'
Assert-R2 (Throws-R2 { New-ChappySyntheticFatPatchPlan -ImageBytes $source -Proposals @() }) 'Empty patch plan rejected'
Assert-R2 (Throws-R2 { New-ChappySyntheticFatPatchPlan -ImageBytes $source -Proposals @($a,$a) }) 'Duplicate FAT patch rejected'
Assert-R2 (Throws-R2 { New-ChappySyntheticFatPatchPlan -ImageBytes $source -Proposals @([pscustomobject]@{FatIndex=2;EntryIndex=0;ExpectedValue=$bad;ProposedValue=$expected}) }) 'Invalid FAT index rejected'
Assert-R2 (Throws-R2 { New-ChappySyntheticFatPatchPlan -ImageBytes $source -Proposals @([pscustomobject]@{FatIndex=0;EntryIndex=-1;ExpectedValue=$bad;ProposedValue=$expected}) }) 'Negative FAT entry rejected'
Assert-R2 (Throws-R2 { New-ChappySyntheticFatPatchPlan -ImageBytes $source -Proposals @([pscustomobject]@{FatIndex=0;EntryIndex=4096;ExpectedValue=$bad;ProposedValue=$expected}) }) 'FAT entry beyond table rejected'
Assert-R2 (Throws-R2 { New-ChappySyntheticFatPatchPlan -ImageBytes $source -Proposals @([pscustomobject]@{FatIndex=0;EntryIndex=0;ExpectedValue=0;ProposedValue=$expected}) }) 'Incorrect before-value rejected'
Assert-R2 (Throws-R2 { New-ChappySyntheticFatPatchPlan -ImageBytes $source -Proposals @([pscustomobject]@{FatIndex=0;EntryIndex=0;ExpectedValue=$bad;ProposedValue=$bad}) }) 'No-op patch rejected'
Assert-R2 (Throws-R2 { Invoke-ChappySyntheticFatPatchSimulation -ImageBytes $sim.SimulatedImageBytes -Plan $plan }) 'Original plan cannot apply to changed image'
Assert-R2 (Throws-R2 { Invoke-ChappySyntheticFatPatchSimulation -ImageBytes $source -Plan $sim.RollbackPlan }) 'Rollback cannot apply to original image'
$forged=New-ChappySyntheticFatPatchPlan -ImageBytes $source -Proposals @($a)
$forged.Patches[0].OffsetBytes=0
Assert-R2 (Throws-R2 { Invoke-ChappySyntheticFatPatchSimulation -ImageBytes $source -Plan $forged }) 'Forged boot-sector target rejected'
$hexPlan=New-ChappySyntheticFatPatchPlan -ImageBytes $source -Proposals @($a)
$hexPlan.Patches[0].AfterHex='00-00-00-00'
Assert-R2 (Throws-R2 { Invoke-ChappySyntheticFatPatchSimulation -ImageBytes $source -Plan $hexPlan }) 'Tampered patch hex rejected'
$missing=New-R2Fixture;$missing[480]=0
Assert-R2 (Throws-R2 { New-ChappySyntheticFatPatchPlan -ImageBytes $missing -Proposals @($a) }) 'Unmarked image rejected'
$missingVbr=New-R2Fixture;$missingVbr[510]=0
Assert-R2 (Throws-R2 { New-ChappySyntheticFatPatchPlan -ImageBytes $missingVbr -Proposals @($a) }) 'Invalid VBR signature rejected'
$malformed=New-R2Fixture;Put-R2U32 $malformed 36 65535
Assert-R2 (Throws-R2 { New-ChappySyntheticFatPatchPlan -ImageBytes $malformed -Proposals @($a) }) 'Impossible FAT geometry rejected'
$oversized=New-Object 'byte[]' 8388609
Assert-R2 (Throws-R2 { New-ChappySyntheticFatPatchPlan -ImageBytes $oversized -Proposals @($a) }) 'Oversized fixture rejected before accessing contents'
$tooMany=New-Object System.Collections.ArrayList
for($i=1;$i -le 33;$i++){[void]$tooMany.Add([pscustomobject]@{FatIndex=0;EntryIndex=$i;ExpectedValue=0;ProposedValue=1})}
Assert-R2 (Throws-R2 { New-ChappySyntheticFatPatchPlan -ImageBytes $source -Proposals @($tooMany.ToArray()) }) 'Patch count bounded to 32'
$brief=$sim | Select-Object Schema,Mode,OriginalSha256,SimulatedSha256,ModifiedByteCount,PatchCount,Diff
$reportJson=$brief | ConvertTo-Json -Depth 6
Assert-R2 ($reportJson -notmatch 'SimulatedImageBytes' -and $reportJson -notmatch 'CHAPPY-SYNTH') 'Summary JSON excludes byte arrays'
Write-Host "R2 result: $script:Pass passed; $script:Fail failed"
if($script:Fail -ne 0){exit 1}
