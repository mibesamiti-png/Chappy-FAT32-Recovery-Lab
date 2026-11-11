#Requires -Version 5.1
# Team D R7-P1 research A/B with identical synthetic data; no real media.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\Fat32VbrMirrorCrossEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32StratifiedAnomalies.psm1') -Force
$script:Pass=0;$script:Fail=0
function Check-D7 {
    param([bool]$Condition,[string]$Label)
    if($Condition){Write-Host "PASS $Label";$script:Pass++}
    else{Write-Host "FAIL $Label";$script:Fail++}
}
function Throws-D7 {
    param([scriptblock]$Command)
    try{$null=& $Command;return $false}catch{return $true}
}
function Set-D7Entry {
    param([byte[]]$Buffer,[long]$Base,[int]$Index,[uint32]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$Buffer,([int]($Base+4*$Index)),4)
}
function New-D7Fixture {
    $b=New-Object 'byte[]' 65536
    $eoc=[Convert]::ToUInt32('0FFFFFFF',16)
    $reserved=[Convert]::ToUInt32('0FFFFFF8',16)
    foreach($base in @(4096,4608,8192,8704)){
        Set-D7Entry $b $base 0 $reserved
        for($i=1;$i -lt 40;$i++){
            Set-D7Entry $b $base $i $eoc
        }
    }
    [Text.Encoding]::ASCII.GetBytes('SECRET-ARTIFICIAL-CANARY-DO-NOT-EXPORT').CopyTo($b,49000)
    return ,$b
}
function New-D7Candidates {
    $p=[pscustomobject]@{plausibility='plausible_unverified';geometry=[pscustomobject]@{
        fat1OffsetBytes=4096L;fat2OffsetBytes=4608L;fatLengthBytes=512L
        rootCluster=2L;dataClusterCount=32L;volumeEndExclusiveBytes=65536L
    }}
    $b=[pscustomobject]@{plausibility='plausible_unverified';geometry=[pscustomobject]@{
        fat1OffsetBytes=8192L;fat2OffsetBytes=8704L;fatLengthBytes=512L
        rootCluster=3L;dataClusterCount=32L;volumeEndExclusiveBytes=65536L
    }}
    return ,@($p,$b)
}
function Hash-D7 {
    param([byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','')}
    finally{$sha.Dispose()}
}
function Run-D7 {
    param([byte[]]$Data,$Candidates,[int]$Bytes=128,[int]$Entries=32)
    $s=[IO.MemoryStream]::new($Data,$false)
    try{
        return Get-ChappyFatStratifiedAnomalyEvidence -Stream $s -Candidates $Candidates -MaxReadBytes $Bytes -MaxEntries $Entries
    }finally{$s.Dispose()}
}
function Run-D6Baseline {
    param([byte[]]$Data,$Candidates)
    $s=[IO.MemoryStream]::new($Data,$false)
    try {
        return Get-ChappyFatVbrMirrorCrossEvidence -Stream $s -Candidates $Candidates -RootWindowEntries 4 -MaxReadBytes 128 -MaxEntries 32
    }finally{$s.Dispose()}
}
$good=New-D7Fixture
$sourceHash=Hash-D7 $good
$candidates=New-D7Candidates
$r=Run-D7 $good $candidates
Check-D7 ($r.schemaVersion -eq '1' -and $r.team -eq 'D' -and $r.mode -eq 'experimental_stratified_fat_anomaly_samples') 'R7 fixed schema and experimental mode'
Check-D7 ($r.experimentalDefaultOff -and -not $r.writePermitted -and $null -eq $r.selectedCandidate -and $r.sourceDecision -eq 'not_selected') 'Default off and no selected repair/source'
Check-D7 ($r.status -eq 'ok' -and -not $r.scanIncomplete -and $r.crossEvidence -eq 'ambiguous_samples_no_selection') 'Clean synthetic sample remains ambiguous not verified'
Check-D7 ($r.metrics.bytesRead -eq 96 -and $r.metrics.entriesRead -eq 24) 'Same 24 FAT entries and 96 bytes as R6 baseline'
Check-D7 ($r.metrics.maxWindowsPerCopy -eq 3 -and $r.metrics.perCopyEntryQuota -eq 8) 'Three 2-entry windows, equal 8-entry quota per copy'
Check-D7 ($r.items.Count -eq 2 -and $r.items[0].samples.Count -eq 2 -and $r.items[1].samples.Count -eq 2) 'Both unverified candidates and all four FAT copies retained'
Check-D7 ($r.items[0].samples[0].sampleWindows.Count -eq 3 -and $r.items[0].samples[0].sampleWindows[2].region -eq 'midpoint') 'Three stable named sampling regions'
Check-D7 ($r.items[0].samples[0].unknownDeclaredEntries -eq 122 -and $r.items[0].samples[0].densityDenominator -eq 6) '122 out of 128 FAT entries explicitly unobserved'
Check-D7 ($r.items[0].mirrors.matchingEntries -eq 6 -and $r.items[0].mirrors.differingEntries -eq 0 -and $r.items[0].mirrors.matchingDoesNotEstablishIntegrity) 'Mirror agreement does not certify health'
Check-D7 ($r.metrics.suspiciousEntries -eq 0 -and $r.metrics.eb58LikeEntries -eq 0) 'Unmodified synthetic fixture has no sampled suspicion'
Check-D7 ($r.warnings -contains 'coverage.unsampled_entries_unknown' -and $r.warnings -contains 'real_master_img_trial_not_authorized') 'Coverage and real-image approval caveats mandatory'
$json=$r|ConvertTo-Json -Depth 14
Check-D7 ($json -notmatch 'SECRET-ARTIFICIAL|CANARY|rawBytes|sourcePath|Sha256|originalFilename') 'No artificial privacy canary, byte samples, hashes or paths in report'
Check-D7 ((Hash-D7 $good) -eq $sourceHash) 'Synthetic original byte-identical after reads'

# Required clean positive and negative controls. Truth labels are injected
# suspicious FAT markers/cyclic root hints only; never user-file correctness.
$cases=New-Object System.Collections.ArrayList
[void]$cases.Add([pscustomobject]@{name='clean';positive=$false;kind='clean'})
[void]$cases.Add([pscustomobject]@{name='mid_bad_both_mirrors';positive=$true;kind='mid_bad'})
[void]$cases.Add([pscustomobject]@{name='mid_eb58_pair';positive=$true;kind='mid_eb58'})
[void]$cases.Add([pscustomobject]@{name='root_free';positive=$true;kind='root_free'})
[void]$cases.Add([pscustomobject]@{name='root_cycle';positive=$true;kind='root_cycle'})
[void]$cases.Add([pscustomobject]@{name='mid_free_normal';positive=$false;kind='mid_free'})
[void]$cases.Add([pscustomobject]@{name='mid_out_of_range';positive=$true;kind='mid_invalid'})
[void]$cases.Add([pscustomobject]@{name='prefix_fake_eb58';positive=$true;kind='prefix_eb58'})
$bTP=0;$bFP=0;$bFN=0;$bTN=0
$vTP=0;$vFP=0;$vFN=0;$vTN=0
$bytesB=0;$bytesV=0;$falseVerified=0
$stopwatchB=[Diagnostics.Stopwatch]::new()
$stopwatchV=[Diagnostics.Stopwatch]::new()
foreach($case in $cases){
    $img=New-D7Fixture
    switch($case.kind){
        'mid_bad' {
            Set-D7Entry $img 4096 17 ([Convert]::ToUInt32('0FFFFFF7',16))
            Set-D7Entry $img 4608 17 ([Convert]::ToUInt32('0FFFFFF7',16))
        }
        'mid_eb58' {Set-D7Entry $img 4096 17 ([Convert]::ToUInt32('000058EB',16))}
        'root_free' {Set-D7Entry $img 4096 2 0}
        'root_cycle' {
            # Put the same cycle in both mirrors. A mirror-only difference
            # must NOT mask the loss of direct chain-cycle detection in R7.
            foreach($base in @(4096,4608)){
                Set-D7Entry $img $base 2 3
                Set-D7Entry $img $base 3 2
            }
        }
        'mid_free' {
            Set-D7Entry $img 4096 17 0
            Set-D7Entry $img 4608 17 0
        }
        'mid_invalid' {Set-D7Entry $img 4096 17 40}
        'prefix_eb58' {
            Set-D7Entry $img 4096 0 ([Convert]::ToUInt32('000058EB',16))
        }
    }
    $before=Hash-D7 $img
    $stopwatchB.Start()
    $old=Run-D6Baseline $img $candidates
    $stopwatchB.Stop()
    $stopwatchV.Start()
    $new=Run-D7 $img $candidates
    $stopwatchV.Stop()
    $basePositive=($old.metrics.totalAnomalyObservations -gt 0 -or
       $old.items[0].mirrors.differentEntries -gt 0 -or
       $old.items[1].mirrors.differentEntries -gt 0)
    $variantPositive=($new.metrics.suspiciousEntries -gt 0 -or
       $new.items[0].mirrors.differingEntries -gt 0 -or
       $new.items[1].mirrors.differingEntries -gt 0)
    if($case.positive){
        if($basePositive){$bTP++}else{$bFN++}
        if($variantPositive){$vTP++}else{$vFN++}
    }else{
        if($basePositive){$bFP++}else{$bTN++}
        if($variantPositive){$vFP++}else{$vTN++}
    }
    if($old.sourceDecision -ne 'not_selected' -or $new.sourceDecision -ne 'not_selected' -or
       $null -ne $old.selectedCandidate -or $null -ne $new.selectedCandidate){
        $falseVerified++
    }
    $bytesB+=$old.metrics.bytesRead
    $bytesV+=$new.metrics.bytesRead
    Check-D7 ($old.metrics.bytesRead -eq 96 -and $new.metrics.bytesRead -eq 96) ('A/B equal actual read bytes: '+$case.name)
    Check-D7 ($old.metrics.entriesRead -eq 24 -and $new.metrics.entriesRead -eq 24) ('A/B equal entries sampled: '+$case.name)
    Check-D7 ((Hash-D7 $img) -eq $before) ('A/B source unchanged: '+$case.name)
}
Check-D7 ($bTP -eq 3 -and $bFP -eq 0 -and $bFN -eq 3 -and $bTN -eq 2) 'R6 baseline measured synthetic confusion matrix TP3 FP0 FN3 TN2'
Check-D7 ($vTP -eq 5 -and $vFP -eq 0 -and $vFN -eq 1 -and $vTN -eq 2) 'R7 experimental synthetic confusion matrix TP5 FP0 FN1 TN2'
Check-D7 ($vFN -gt 0 -and $bFN -gt 0) 'Root-cycle regression remains visible; no perfect detection claim'
Check-D7 ($falseVerified -eq 0 -and $bytesB -eq 768 -and $bytesV -eq 768) 'No false source-selection claims; identical aggregate 768-byte budget each'
Write-Host ('A/B truth fixture count='+$cases.Count+' baseline TP='+$bTP+' FP='+$bFP+' FN='+$bFN+' TN='+$bTN+' candidate TP='+$vTP+' FP='+$vFP+' FN='+$vFN+' TN='+$vTN)
Write-Host ('A/B actual aggregate bytes baseline='+$bytesB+' candidate='+$bytesV+'; stopwatch milliseconds baseline='+$stopwatchB.ElapsedMilliseconds+' candidate='+$stopwatchV.ElapsedMilliseconds+' (CI environment only)')
# No file carving or original user bytes: file byte-identity metric NOT APPLICABLE.

$midBad=New-D7Fixture
foreach($base in @(4096,4608)){Set-D7Entry $midBad $base 17 ([Convert]::ToUInt32('0FFFFFF7',16))}
$r=Run-D7 $midBad $candidates
Check-D7 ($r.items[0].mirrors.differingEntries -eq 0 -and $r.metrics.suspiciousEntries -eq 2) 'Both FAT copies can match on suspicious damaged marker'
Check-D7 ($r.crossEvidence -eq 'suspicious_samples_no_selection' -and -not $r.scanIncomplete) 'Complete tiny sample still does not select authentic FAT'

$invalid=New-D7Candidates
$invalid[1].geometry.fat1OffsetBytes=[long]::MaxValue-20
$invalid[1].geometry.fat2OffsetBytes=[long]::MaxValue-10
$r=Run-D7 $good $invalid
Check-D7 ($r.items[1].status -eq 'insufficient_evidence' -and $r.scanIncomplete) 'Int64 overflow candidate never probed'
Check-D7 ($r.metrics.bytesRead -eq 48 -and $r.crossEvidence -eq 'insufficient_evidence') 'Invalid geometry spends no extra bytes and cannot select primary'
$invalid=New-D7Candidates
$invalid[1].geometry.fat2OffsetBytes=8000L
$r=Run-D7 $good $invalid
Check-D7 ($r.items[1].reasonCodes -contains 'geometry.fat_exceeds_volume') 'Overlapping or shifted FAT2 rejected'
$invalid=New-D7Candidates
$invalid[1].plausibility='contradicted'
$r=Run-D7 $good $invalid
Check-D7 ($r.items[1].reasonCodes -contains 'candidate.upstream_unverified_or_contradicted') 'Prior rejected VBR not rehabilitated by random FAT data'
$r=Run-D7 $good $candidates -Bytes 16 -Entries 4
Check-D7 ($r.metrics.bytesRead -eq 16 -and $r.metrics.entriesRead -eq 4 -and $r.scanIncomplete) 'Global 16-byte / 4-entry cap enforced across four hypotheses'
Check-D7 ($r.crossEvidence -eq 'insufficient_evidence' -and $r.items[1].samples[1].sampleWindows[2].scanIncomplete) 'Quota exhaustion cannot be called clean'
$r=Run-D7 $good $candidates -Bytes 256 -Entries 40
Check-D7 ($r.metrics.entriesRead -le 40 -and $r.metrics.bytesRead -le 256 -and $r.metrics.bytesRead -eq 96) 'Maximum caps cannot create unbounded extra reads'
# Partial-returning source: valid stream may return 1 byte at a time.
Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class D7ShortStream : Stream {
    private readonly MemoryStream inner;
    private readonly long cutoff;
    private readonly int chunk;
    public D7ShortStream(byte[] bytes,long cutoff,int chunk){
        inner=new MemoryStream(bytes,false);this.cutoff=cutoff;this.chunk=chunk;
    }
    public override bool CanRead { get { return true; } }
    public override bool CanSeek { get { return true; } }
    public override bool CanWrite { get { return false; } }
    public override long Length { get { return inner.Length; } }
    public override long Position { get { return inner.Position; } set { inner.Position=value; } }
    public override long Seek(long offset,SeekOrigin origin) { return inner.Seek(offset,origin); }
    public override void Flush() {}
    public override int Read(byte[] buffer,int offset,int count) {
        if(inner.Position>=cutoff){return 0;}
        return inner.Read(buffer,offset,(int)Math.Min(Math.Min(count,chunk),cutoff-inner.Position));
    }
    public override void SetLength(long length){throw new NotSupportedException();}
    public override void Write(byte[] buffer,int offset,int count){throw new NotSupportedException();}
}
'@
$s=[D7ShortStream]::new($good,[long]::MaxValue,1)
try{
    $r=Get-ChappyFatStratifiedAnomalyEvidence -Stream $s -Candidates $candidates
    Check-D7 ($r.metrics.bytesRead -eq 96 -and -not $r.scanIncomplete) 'One-byte fragmented reads assembled without overcounting'
}finally{$s.Dispose()}
$s=[D7ShortStream]::new($good,8709L,2)
try{
    $r=Get-ChappyFatStratifiedAnomalyEvidence -Stream $s -Candidates $candidates
    Check-D7 ($r.scanIncomplete -and $r.crossEvidence -eq 'insufficient_evidence') 'Truncated stream marks uncertainty'
    Check-D7 ($r.items[1].samples[1].reasonCodes -contains 'io.entry_truncated') 'Short entry classified, not silently padded'
    Check-D7 ($r.metrics.bytesRead -le 96) 'Partial reads count actual data, not requested bytes'
}finally{$s.Dispose()}
$s=[IO.MemoryStream]::new($good,$true)
try{Check-D7 (Throws-D7 {Get-ChappyFatStratifiedAnomalyEvidence -Stream $s -Candidates $candidates}) 'Writable stream rejected'}
finally{$s.Dispose()}
$s=[IO.MemoryStream]::new($good,$false)
try{
    Check-D7 (Throws-D7 {Get-ChappyFatStratifiedAnomalyEvidence -Stream $s -Candidates @($candidates[0])}) 'Single candidate rejected'
    Check-D7 (Throws-D7 {Get-ChappyFatStratifiedAnomalyEvidence -Stream $s -Candidates $candidates -MaxEntries 41}) 'Max entries 40'
    Check-D7 (Throws-D7 {Get-ChappyFatStratifiedAnomalyEvidence -Stream $s -Candidates $candidates -MaxReadBytes 257}) 'Max cumulative bytes 256'
}finally{$s.Dispose()}
Write-Host "Team D R7-P1 result: $script:Pass passed; $script:Fail failed."
if($script:Fail -gt 0){exit 1}
