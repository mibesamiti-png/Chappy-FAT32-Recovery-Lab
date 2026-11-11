#Requires -Version 5.1
# Team D R8 exact artificial A/B: 64KiB invented source, no physical media or files.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\Fat32VbrMirrorCrossEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32StratifiedAnomalies.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32AdditiveAnomalyEvidence.psm1') -Force
$script:Pass=0;$script:Fail=0
function Check-D8 {
    param([bool]$Condition,[string]$Name)
    if($Condition){Write-Host "PASS $Name";$script:Pass++}
    else{Write-Host "FAIL $Name";$script:Fail++}
}
function Throws-D8 {
    param([scriptblock]$Action)
    try{$null=& $Action;return $false}catch{return $true}
}
function Set-D8Entry {
    param([byte[]]$Bytes,[int]$Offset,[int]$Index,[uint32]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$Bytes,($Offset+4*$Index),4)
}
function New-D8Fixture {
    $b=New-Object 'byte[]' 65536
    $eoc=[Convert]::ToUInt32('0FFFFFFF',16)
    $reserved=[Convert]::ToUInt32('0FFFFFF8',16)
    foreach($fat in @(4096,4608,8192,8704)){
        Set-D8Entry $b $fat 0 $reserved
        for($i=1;$i -lt 40;$i++){
            Set-D8Entry $b $fat $i $eoc
        }
    }
    [Text.Encoding]::ASCII.GetBytes('SECRET-ARTIFICIAL-CANARY-NO-EXPORT').CopyTo($b,49000)
    return ,$b
}
function New-D8Candidates {
    $a=[pscustomobject]@{plausibility='plausible_unverified';geometry=[pscustomobject]@{
        fat1OffsetBytes=4096L;fat2OffsetBytes=4608L;fatLengthBytes=512L
        rootCluster=2L;dataClusterCount=32L;volumeEndExclusiveBytes=65536L
    }}
    $b=[pscustomobject]@{plausibility='plausible_unverified';geometry=[pscustomobject]@{
        fat1OffsetBytes=8192L;fat2OffsetBytes=8704L;fatLengthBytes=512L
        rootCluster=3L;dataClusterCount=32L;volumeEndExclusiveBytes=65536L
    }}
    return ,@($a,$b)
}
function Hash-D8 {
    param([byte[]]$B)
    $h=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($h.ComputeHash($B)).Replace('-','')}
    finally{$h.Dispose()}
}
function Run-D8 {
    param([byte[]]$B,$C,[string]$Mode,[int]$ReadCap=160,[int]$EntryCap=40)
    $s=[IO.MemoryStream]::new($B,$false)
    try{
        switch($Mode){
            'r6' {return Get-ChappyFatVbrMirrorCrossEvidence -Stream $s -Candidates $C -RootWindowEntries 8 -MaxReadBytes $ReadCap -MaxEntries $EntryCap}
            'r7' {return Get-ChappyFatStratifiedAnomalyEvidence -Stream $s -Candidates $C -MaxReadBytes $ReadCap -MaxEntries $EntryCap}
            'r8' {return Get-ChappyFatAdditiveAnomalyEvidence -Stream $s -Candidates $C -MaxReadBytes $ReadCap -MaxEntries $EntryCap}
        }
    }finally{$s.Dispose()}
}
function Is-D8Positive {
    param($Report,[string]$Mode)
    if($Mode -eq 'r8'){
        return ($Report.rootSuspiciousObserved -or $Report.remoteSuspiciousObserved -or $Report.mirrorDisagreementObserved)
    }
    if($Mode -eq 'r6'){
        return ($Report.metrics.totalAnomalyObservations -gt 0 -or
            $Report.items[0].mirrors.differentEntries -gt 0 -or
            $Report.items[1].mirrors.differentEntries -gt 0)
    }
    return ($Report.metrics.suspiciousEntries -gt 0 -or
        $Report.items[0].mirrors.differingEntries -gt 0 -or
        $Report.items[1].mirrors.differingEntries -gt 0)
}

$good=New-D8Fixture
$cands=New-D8Candidates
$hash=Hash-D8 $good
$r=Run-D8 $good $cands 'r8'
Check-D8 ($r.schemaVersion -eq '1' -and $r.team -eq 'D' -and $r.mode -eq 'experimental_additive_fat_anomaly_evidence') 'R8 fixed schema and research mode'
Check-D8 ($r.experimentalDefaultOff -and -not $r.writePermitted -and $null -eq $r.selectedCandidate -and $r.sourceDecision -eq 'not_selected') 'Explicit default off and no source selection'
Check-D8 ($r.status -eq 'ok' -and -not $r.scanIncomplete -and $r.crossEvidence -eq 'ambiguous_samples_no_selection') 'Normal artificial sample is ambiguous, never verified healthy'
Check-D8 ($r.metrics.rootQuotaEntries -eq 16 -and $r.metrics.remoteQuotaEntries -eq 24) 'Entry quotas split exactly 16 root plus 24 remote'
Check-D8 ($r.metrics.rootBytesRead -eq 64 -and $r.metrics.remoteBytesRead -eq 96) 'Actual bytes read are 64 plus 96'
Check-D8 ($r.metrics.entriesRead -eq 40 -and $r.metrics.bytesRead -eq 160) 'Global 40 entries, 160 bytes, less than 256-byte cap'
Check-D8 ($r.items.Count -eq 2 -and $r.items[0].fatCopies.Count -eq 2) 'Two candidates each with two FAT copies'
Check-D8 ($r.items[0].fatCopies[0].rootChainEvidence -eq 'eoc_observed') 'Root EOC evidence retained'
Check-D8 ($r.items[0].fatCopies[0].remoteObservedUniqueEntries -eq 6 -and $r.items[0].fatCopies[0].remoteUnknownDeclaredEntries -eq 122) 'R7 per-copy coverage 6/128 and 122 unknown'
Check-D8 ($r.metrics.uniqueCoverageAcrossPasses -eq 'not_inferred' -and $r.warnings -contains 'coverage.cross_pass_duplicates_charged') 'Repeated windows charged twice, never claim unique aggregate coverage'
Check-D8 ($r.warnings -contains 'real_master_img_trial_not_authorized' -and $r.warnings -contains 'sample.absence_not_proof_of_health') 'No real-image approval or unsampled healthy inference'
$j=$r|ConvertTo-Json -Depth 14
Check-D8 ($j -notmatch 'SECRET-ARTIFICIAL|CANARY|rawBytes|sourcePath|SHA256|recoveredFilename') 'No raw private canary/paths/hashes leaked'
Check-D8 ((Hash-D8 $good) -eq $hash) 'Synthetic source byte-identical on read'

$cases=@(
    [pscustomobject]@{name='clean';positive=$false;kind='clean'},
    [pscustomobject]@{name='mid_bad_both_mirrors';positive=$true;kind='mid_bad'},
    [pscustomobject]@{name='mid_eb58_pair';positive=$true;kind='mid_eb58'},
    [pscustomobject]@{name='root_free';positive=$true;kind='root_free'},
    [pscustomobject]@{name='root_cycle';positive=$true;kind='root_cycle'},
    [pscustomobject]@{name='mid_free_normal';positive=$false;kind='mid_free'},
    [pscustomobject]@{name='mid_out_of_range';positive=$true;kind='mid_invalid'},
    [pscustomobject]@{name='prefix_fake_eb58';positive=$true;kind='prefix_eb58'}
)
$r6=@{tp=0;fp=0;fn=0;tn=0;bytes=0;entries=0}
$r7=@{tp=0;fp=0;fn=0;tn=0;bytes=0;entries=0}
$r8=@{tp=0;fp=0;fn=0;tn=0;bytes=0;entries=0}
$falseVerified=0
$clock6=[Diagnostics.Stopwatch]::new()
$clock7=[Diagnostics.Stopwatch]::new()
$clock8=[Diagnostics.Stopwatch]::new()
foreach($case in $cases){
    $b=New-D8Fixture
    switch($case.kind){
        'mid_bad' {
            foreach($fat in @(4096,4608)){Set-D8Entry $b $fat 17 ([Convert]::ToUInt32('0FFFFFF7',16))}
        }
        'mid_eb58' {Set-D8Entry $b 4096 17 ([Convert]::ToUInt32('000058EB',16))}
        'root_free' {Set-D8Entry $b 4096 2 0}
        'root_cycle' {
            foreach($fat in @(4096,4608)){
                Set-D8Entry $b $fat 2 3
                Set-D8Entry $b $fat 3 2
            }
        }
        'mid_free' {foreach($fat in @(4096,4608)){Set-D8Entry $b $fat 17 0}}
        'mid_invalid' {Set-D8Entry $b 4096 17 40}
        'prefix_eb58' {Set-D8Entry $b 4096 0 ([Convert]::ToUInt32('000058EB',16))}
    }
    $start=Hash-D8 $b
    $clock6.Start();$baseline=Run-D8 $b $cands 'r6';$clock6.Stop()
    $clock7.Start();$stratified=Run-D8 $b $cands 'r7';$clock7.Stop()
    $clock8.Start();$additive=Run-D8 $b $cands 'r8';$clock8.Stop()
    foreach($mode in @('r6','r7','r8')){
        $a=$(if($mode -eq 'r6'){$baseline}elseif($mode -eq 'r7'){$stratified}else{$additive})
        $positive=Is-D8Positive $a $mode
        if($case.positive) {
            if($positive){Set-Variable -Name ignored -Value 1; switch($mode){'r6'{$r6.tp++};'r7'{$r7.tp++};'r8'{$r8.tp++}}}
            else{switch($mode){'r6'{$r6.fn++};'r7'{$r7.fn++};'r8'{$r8.fn++}}}
        }else{
            if($positive){switch($mode){'r6'{$r6.fp++};'r7'{$r7.fp++};'r8'{$r8.fp++}}}
            else{switch($mode){'r6'{$r6.tn++};'r7'{$r7.tn++};'r8'{$r8.tn++}}}
        }
        switch($mode) {
            'r6'{$r6.bytes+=$a.metrics.bytesRead;$r6.entries+=$a.metrics.entriesRead}
            'r7'{$r7.bytes+=$a.metrics.bytesRead;$r7.entries+=$a.metrics.entriesRead}
            'r8'{$r8.bytes+=$a.metrics.bytesRead;$r8.entries+=$a.metrics.entriesRead}
        }
        if($a.sourceDecision -ne 'not_selected' -or $null -ne $a.selectedCandidate -or $a.crossEvidence -match 'verified|healthy'){
            $falseVerified++
        }
    }
    Check-D8 ($baseline.metrics.bytesRead -eq 160 -and $additive.metrics.bytesRead -eq 160 -and $stratified.metrics.bytesRead -eq 96) ('A/B actual bytes R6=160 R7=96 R8=160: '+$case.name)
    Check-D8 ($baseline.metrics.entriesRead -eq 40 -and $additive.metrics.entriesRead -eq 40 -and $stratified.metrics.entriesRead -eq 24) ('A/B actual entry counts: '+$case.name)
    Check-D8 ((Hash-D8 $b) -eq $start) ('All three leave synthetic fixture unchanged: '+$case.name)
    if($case.kind -eq 'root_cycle'){
        Check-D8 ($additive.rootCyclesObserved -eq 2 -and $additive.rootSuspiciousObserved) 'R8 sees root cycle identically repeated in both mirrors'
        Check-D8 ((-not (Is-D8Positive $stratified 'r7')) -and (Is-D8Positive $baseline 'r6')) 'Regression of R7 alone preserved as evidence'
    }
    if($case.kind -eq 'mid_bad'){
        Check-D8 ($additive.remoteSuspiciousObserved -and (-not (Is-D8Positive $baseline 'r6'))) 'R8 additionally observes distant mirrored bad marker'
    }
}
Check-D8 ($r6.tp -eq 3 -and $r6.fp -eq 0 -and $r6.fn -eq 3 -and $r6.tn -eq 2) 'R6 baseline exact selected-case confusion matrix TP3 FP0 FN3 TN2'
Check-D8 ($r7.tp -eq 5 -and $r7.fp -eq 0 -and $r7.fn -eq 1 -and $r7.tn -eq 2) 'R7 existing research matrix TP5 FP0 FN1 TN2'
Check-D8 ($r8.tp -eq 6 -and $r8.fp -eq 0 -and $r8.fn -eq 0 -and $r8.tn -eq 2) 'R8 additive matrix TP6 FP0 FN0 TN2 on only eight chosen artificial cases'
Check-D8 ($r6.bytes -eq 1280 -and $r7.bytes -eq 768 -and $r8.bytes -eq 1280) 'Eight-case source byte totals and R7 cheaper actual reads disclosed'
Check-D8 ($r6.entries -eq 320 -and $r7.entries -eq 192 -and $r8.entries -eq 320) 'Eight-case source entry totals disclosed'
Check-D8 ($falseVerified -eq 0) 'Never claim healthy source, verified original files, source selection'
Write-Host ('D8 artificial cases=8 R6 TP='+$r6.tp+' FP='+$r6.fp+' FN='+$r6.fn+' TN='+$r6.tn+' R7 TP='+$r7.tp+' FP='+$r7.fp+' FN='+$r7.fn+' TN='+$r7.tn+' R8 TP='+$r8.tp+' FP='+$r8.fp+' FN='+$r8.fn+' TN='+$r8.tn)
Write-Host ('D8 actual bytes R6='+$r6.bytes+' R7='+$r7.bytes+' R8='+$r8.bytes+' elapsed-ms noisy R6='+$clock6.ElapsedMilliseconds+' R7='+$clock7.ElapsedMilliseconds+' R8='+$clock8.ElapsedMilliseconds)

$r=Run-D8 $good $cands 'r8' -ReadCap 32 -EntryCap 8
Check-D8 ($r.metrics.bytesRead -eq 32 -and $r.metrics.entriesRead -eq 8 -and $r.scanIncomplete) 'Tight 32-byte / eight-entry joint quota enforced'
Check-D8 ($r.crossEvidence -eq 'insufficient_evidence' -and $r.warnings -contains 'coverage.incomplete') 'Limited probe does not infer healthy FAT'
$r=Run-D8 $good $cands 'r8' -ReadCap 80 -EntryCap 20
Check-D8 ($r.metrics.bytesRead -eq 80 -and $r.metrics.entriesRead -eq 20 -and $r.scanIncomplete) 'Intermediate 20-entry joint quota and unknown coverage'
$r=Run-D8 $good $cands 'r8' -ReadCap 256 -EntryCap 40
Check-D8 ($r.metrics.bytesRead -le 256 -and $r.metrics.entriesRead -eq 40) '256-byte / 40-entry hard cap independently respected'
$invalid=New-D8Candidates
$invalid[1].geometry.fat1OffsetBytes=[long]::MaxValue-10
$invalid[1].geometry.fat2OffsetBytes=[long]::MaxValue-5
$r=Run-D8 $good $invalid 'r8'
Check-D8 ($r.scanIncomplete -and $r.status -eq 'partial' -and $null -eq $r.selectedCandidate) 'Overflown backup candidate remains unselected and partial'
Check-D8 ($r.metrics.bytesRead -le 160 -and $r.metrics.entriesRead -le 40) 'Invalid geometry does not expand combined budget'
$invalid=New-D8Candidates
$invalid[1].geometry.fat2OffsetBytes=8200L
$r=Run-D8 $good $invalid 'r8'
Check-D8 ($r.scanIncomplete -and $r.items[1].rootStatus -eq 'insufficient_evidence') 'Overlapping FAT geometries remain unresolved'

# Forced short reads, including 1-byte chunks and cutoff, must not bypass sum.
Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class D8ShortReadStream : Stream {
    private readonly MemoryStream inner; private readonly int chunk; private readonly long cutoff;
    public D8ShortReadStream(byte[] b,int size,long limit){inner=new MemoryStream(b,false);chunk=size;cutoff=limit;}
    public override bool CanRead { get {return true;} }
    public override bool CanSeek { get {return true;} }
    public override bool CanWrite { get {return false;} }
    public override long Length { get {return inner.Length;} }
    public override long Position { get {return inner.Position;} set {inner.Position=value;} }
    public override long Seek(long offset,SeekOrigin origin){return inner.Seek(offset,origin);}
    public override int Read(byte[] b,int offset,int count){
        if(inner.Position>=cutoff){return 0;}
        return inner.Read(b,offset,(int)Math.Min(Math.Min(count,chunk),cutoff-inner.Position));
    }
    public override void Flush(){}
    public override void SetLength(long length){throw new NotSupportedException();}
    public override void Write(byte[] b,int offset,int count){throw new NotSupportedException();}
}
'@
$split=[D8ShortReadStream]::new($good,1,[long]::MaxValue)
try{
    $r=Get-ChappyFatAdditiveAnomalyEvidence -Stream $split -Candidates $cands
    Check-D8 ($r.metrics.bytesRead -eq 160 -and $r.metrics.entriesRead -eq 40 -and -not $r.scanIncomplete) 'One-byte fragmented reads assembled within aggregate quota'
}finally{$split.Dispose()}
$cut=[D8ShortReadStream]::new($good,4,8709L)
try{
    $r=Get-ChappyFatAdditiveAnomalyEvidence -Stream $cut -Candidates $cands
    Check-D8 ($r.scanIncomplete -and $r.metrics.bytesRead -le 160 -and $r.status -eq 'partial') 'Cutoff stream cannot be treated as complete evidence'
}finally{$cut.Dispose()}
$w=[IO.MemoryStream]::new($good,$true)
try{Check-D8 (Throws-D8 {Get-ChappyFatAdditiveAnomalyEvidence -Stream $w -Candidates $cands}) 'Writable memory stream refused'}
finally{$w.Dispose()}
$s=[IO.MemoryStream]::new($good,$false)
try{
    Check-D8 (Throws-D8 {Get-ChappyFatAdditiveAnomalyEvidence -Stream $s -Candidates @($cands[0])}) 'Two candidates mandatory'
    Check-D8 (Throws-D8 {Get-ChappyFatAdditiveAnomalyEvidence -Stream $s -Candidates $cands -MaxEntries 41}) '40 entries maximum'
    Check-D8 (Throws-D8 {Get-ChappyFatAdditiveAnomalyEvidence -Stream $s -Candidates $cands -MaxReadBytes 257}) '256 bytes maximum'
}finally{$s.Dispose()}
Check-D8 ((Hash-D8 $good) -eq $hash) 'Original artificial fixture hash remains unchanged'
Write-Host "Team D R8-P1 result: $script:Pass passed; $script:Fail failed."
if($script:Fail -gt 0){exit 1}
