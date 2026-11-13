#Requires -Version 5.1
# Team D -> A R7 negative integration acceptance. Only synthetic nonwritable MemoryStreams.
# No real card/master IMG, no source path, no repair and no A production code edits.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $root 'core\Chappy.LiveBcdEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32GuardedResult.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32GuardedReturnedSourceJoin.psm1') -Force
$script:Pass=0
$script:Fail=0
function Check-D7([bool]$Okay,[string]$Why){
    if($Okay){$script:Pass++;Write-Host ('PASS '+$Why)}
    else{$script:Fail++;Write-Host ('FAIL '+$Why)}
}
function Set-D7U16([byte[]]$Image,[int]$At,[uint16]$Value){
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$Image,$At,2)
}
function Set-D7U32([byte[]]$Image,[int]$At,[uint32]$Value){
    [Array]::Copy([BitConverter]::GetBytes($Value),0,$Image,$At,4)
}
if(-not ('D7Early17SyntheticSource' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class D7Early17SyntheticSource : MemoryStream {
    private bool first=false;
    public D7Early17SyntheticSource(byte[] data):base(data,false){}
    public override int Read(byte[] buffer,int offset,int count) {
        if(first)return 0;
        first=true;
        return base.Read(buffer,offset,Math.Min(17,count));
    }
}
'@
}
# Synthetic scorer owns all mutation positions; none are given to A or D readers.
$cases=@(
    [pscustomobject]@{id='clean_SPC1';spc=1;seed=202625;fault='clean';expect='numeric'},
    [pscustomobject]@{id='clean_SPC2';spc=2;seed=202626;fault='clean';expect='numeric'},
    [pscustomobject]@{id='backup_reserved31';spc=1;seed=202625;fault='backup31';expect='blocked'},
    [pscustomobject]@{id='backup_reserved33';spc=2;seed=202626;fault='backup33';expect='blocked'},
    [pscustomobject]@{id='matching_unsafe_extended_flags';spc=1;seed=202625;fault='flags';expect='blocked'},
    [pscustomobject]@{id='both_mirrors_identical_cycle';spc=2;seed=202626;fault='bothcycle';expect='numeric'},
    [pscustomobject]@{id='fat2_missing_one_link';spc=1;seed=202625;fault='missing';expect='numeric'},
    [pscustomobject]@{id='FAT2_remote_entry60000';spc=2;seed=202626;fault='remote';expect='numeric'},
    [pscustomobject]@{id='true_17_byte_then_zero';spc=1;seed=202625;fault='early17';expect='unknown'}
)
$good=0;$blocked=0;$unknown=0
$totalReturned=0L;$sumUnique=0L;$totalCalls=0L
$scorerPositive=0;$scorerNegative=0;$scorerUnknown=0
$rawSourceForMeter=$null
$sourceLength=0L
foreach($case in $cases){
    $fixture=New-ChappyA3DStandardFixture -Seed $case.seed -SectorsPerCluster $case.spc
    [byte[]]$image=$fixture.image
    [long]$fatLength=[long]([Math]::Ceiling((4.0*(65541+2))/512.0)*512)
    [long]$fat1=33L*512L
    [long]$fat2=$fat1+$fatLength
    switch($case.fault){
        'backup31' {Set-D7U16 $image (512+6*512+14) ([uint16]31)}
        'backup33' {Set-D7U16 $image (512+6*512+14) ([uint16]33)}
        'flags' {
            Set-D7U16 $image (512+40) ([uint16]128)
            Set-D7U16 $image (512+6*512+40) ([uint16]128)
        }
        'bothcycle' {
            Set-D7U32 $image ([int]($fat1+4*4)) ([uint32]4)
            Set-D7U32 $image ([int]($fat2+4*4)) ([uint32]4)
        }
        'missing' {Set-D7U32 $image ([int]($fat2+4*4)) ([uint32]0)}
        'remote' {Set-D7U32 $image ([int]($fat2+4*60000)) ([uint32]1)}
    }
    $before=Get-A3DSha256 $image
    if($case.fault -ceq 'early17'){
        $stream=[D7Early17SyntheticSource]::new($image)
    }else{
        $stream=[IO.MemoryStream]::new($image,$false)
    }
    try{
        $a=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $stream -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedDirectoryReceipts -BindAObservedFatPairReceipts
        $receipt=$a.dPhysicalReceipt
        Check-D7 ($a.schemaVersion -ceq 'a7_live_bcd_envelope_v1' -and
            $a.originalIdentity -ceq 'unknown' -and $a.recoveredOriginalFiles -eq 0 -and
            -not $a.canExport -and -not $a.canSelectFatCopy -and
            $receipt.fatCopyWinner -ceq 'not_selected' -and
            $receipt.originalIdentity -ceq 'unknown' -and -not $receipt.canExport -and
            -not $stream.CanWrite) ($case.id+' no original owner, source selection or write')
        Check-D7 ($a.metrics.actualReturnedBytes -le 120000L -and
            $a.metrics.physicalReadCalls -le 512L -and
            $a.metrics.repeatedReturnedBytes -eq ($a.metrics.actualReturnedBytes-$a.metrics.uniqueReturnedBytes) -and
            (Get-A3DSha256 $image) -ceq $before) ($case.id+' one A stream quota and unchanged synthetic SHA')
        if($case.expect -ceq 'numeric'){
            $good++;$scorerNegative++
            Check-D7 ($a.status -ceq 'partial' -and
                $a.d.contractVersion -ceq 'd6_guarded_fat_result_v1' -and
                $a.d.guardDecision -ceq 'candidate_geometry_unverified' -and
                $a.d.fatProbeState -ceq 'fixed_baseline_sampled' -and
                $receipt.decision -ceq 'A_in_process_numeric_FAT_pair_coverage_consistent' -and
                $receipt.sourceAuthenticity -ceq 'not_real_media_authenticated' -and
                $receipt.outerEventOrigin -ceq 'A_in_process_live_Stream_Read_only') ($case.id+' real A same-session source events reconcile numeric FAT without authenticity')
            Check-D7 ($receipt.pairedFullyObservedEntries -eq 128L -and
                $receipt.unobservedPairedEntryIndices -eq 65536L -and
                $receipt.sourceActualReturnedBytes -eq 4096L -and
                $receipt.physicalReadCalls -gt 0) ($case.id+' physically observed 128/65664 4B pairs, remaining indices UNKNOWN')
            if($case.fault -ceq 'bothcycle' -or $case.fault -ceq 'remote' -or $case.fault -ceq 'missing'){
                $scorerPositive++
                Check-D7 ($a.d.fatWinner -ceq 'not_selected' -and
                    $receipt.sourceAuthenticity -ceq 'not_real_media_authenticated' -and
                    $a.candidateIntegrity -ceq 'not_original_file_integrity') ($case.id+' no healthy/original-file claim despite physical pair observation')
            }
            if($case.fault -ceq 'clean' -and $case.spc -eq 1){
                # Separate D-only A-meter adversarial comparison uses this
                # generated memory fixture, never user's media.
                $rawSourceForMeter=$image
                $sourceLength=[long]$image.Length
            }
        }elseif($case.expect -ceq 'blocked'){
            $blocked++;$scorerPositive++
            Check-D7 ($a.d.guardDecision -cne 'candidate_geometry_unverified' -and
                $a.d.fatFixedReturnedBytes -eq 0L -and
                $receipt.decision -ceq 'A_in_process_geometry_FAT_block_consistent' -and
                $null -eq $receipt.pairedFullyObservedEntries -and
                $null -eq $receipt.unobservedPairedEntryIndices) ($case.id+' conflicting plausible BPB denied before FAT sampling')
        }else{
            $unknown++;$scorerUnknown++
            Check-D7 ($a.status -ceq 'partial' -and
                $a.metrics.actualReturnedBytes -eq 17L -and
                $receipt.decision -cne 'A_in_process_numeric_FAT_pair_coverage_consistent' -and
                $null -eq $receipt.pairedFullyObservedEntries -and
                -not $a.canExport) ($case.id+' actual 17B+zero never promoted into full FAT')
        }
        $totalReturned+=[long]$a.metrics.actualReturnedBytes
        $sumUnique+=[long]$a.metrics.uniqueReturnedBytes
        $totalCalls+=[long]$a.metrics.physicalReadCalls
        $guardLog=$(if($null -ne $a.d.PSObject.Properties['guardDecision']){[string]$a.d.guardDecision}else{'not_evaluated'})
        Write-Host ('D R7 A-live case={0} A_source_status={1} Dguard={2} A_FAT_receipt={3} paired={4}/65664 actual/unique={5}/{6} physicalCalls={7}' -f
            $case.id,$a.status,$guardLog,$receipt.decision,$receipt.pairedFullyObservedEntries,$a.metrics.actualReturnedBytes,$a.metrics.uniqueReturnedBytes,$a.metrics.physicalReadCalls)
    }finally{$stream.Dispose()}
    $fixture=$null;$image=$null
    if($case.id -ne 'clean_SPC1'){[GC]::Collect()}
}
Check-D7 ($good -eq 5 -and $blocked -eq 3 -and $unknown -eq 1) 'nine preregistered standard synthetic controls, BPB blocks and source UNKNOWN'
Check-D7 ($null -ne $rawSourceForMeter -and $sourceLength -gt 30MB) 'test-only generated clean source retained for A meter event-forgery controls'

# Separate test-only protected A meter: no D or test caller may issue A source
# authenticity; this only measures successful physical offset/length events.
$innerMemory=[IO.MemoryStream]::new($rawSourceForMeter,$false)
try{
    $aMeter=[ChappyA7LiveMeterV1]::new($innerMemory,120000L,512)
    $aMeter.BeginConsumer('fat')
    $d=Get-ChappyFatGuardedResult -Stream $aMeter -EnableGuardedDiagnostics -MaxPhysicalReadBytes 4096 -MaxPhysicalReadCalls 256
    $actualEvents=@($aMeter.Events | ForEach-Object {
        [pscustomobject]@{
            Consumer=[string]$_.Consumer
            OffsetBytes=[long]$_.OffsetBytes
            ReturnedBytes=[int]$_.ReturnedBytes
        }
    })
    $base=@{
        GuardedResult=$d
        SourceLengthBytes=$sourceLength
        OuterPhysicalReadCalls=[long]$aMeter.Calls
        OuterPrematureZeroReads=[long]$aMeter.ZeroReads
    }
    $normal=Compare-ChappyFatGuardedReturnedSourceEvents @base -OuterReturnedEvents $actualEvents
    Check-D7 ($normal.decision -ceq 'consistent_numeric_candidate_unattested' -and
        $normal.sourceAuthenticity -ceq 'not_proven' -and
        $normal.metrics.pairedFullyObservedEntries -eq 128L -and
        $normal.metrics.unobservedPairedEntryIndices -eq 65536L) 'unmodified A-meter FAT-event positions consistent yet source authenticity not proven'
    Check-D7 ($aMeter.Returned -eq [long]$d.metrics.actualReturnedBytes -and
        $aMeter.Unique -eq [long]$d.metrics.uniqueReturnedBytes -and
        $aMeter.Repeated -eq [long]$d.metrics.repeatedReturnedBytes -and
        $aMeter.Calls -eq [long]$d.metrics.physicalReadCalls -and
        $aMeter.Returned -le 4096L) 'real A meter independently observes actual/unique/repeated physical source reads'
    $swapped=@($actualEvents)
    $tmp=$swapped[0];$swapped[0]=$swapped[1];$swapped[1]=$tmp
    $bad=Compare-ChappyFatGuardedReturnedSourceEvents @base -OuterReturnedEvents $swapped
    Check-D7 ($bad.decision -ceq 'unknown' -and $null -eq $bad.metrics.pairedCoveragePercent) 'swapped returned-source event order cannot forge paired FAT coverage'
    $wrongConsumer=@(foreach($e in $actualEvents){
        [pscustomobject]@{Consumer='fat';OffsetBytes=[long]$e.OffsetBytes;ReturnedBytes=[int]$e.ReturnedBytes}
    })
    $wrongConsumer[0].Consumer='directory'
    $bad=Compare-ChappyFatGuardedReturnedSourceEvents @base -OuterReturnedEvents $wrongConsumer
    Check-D7 ($bad.decision -ceq 'unknown' -and $null -eq $bad.metrics.pairedFullyObservedEntries) 'foreign B directory phase read cannot substitute for A FAT phase'
    $moved=@(foreach($e in $actualEvents){
        [pscustomobject]@{Consumer='fat';OffsetBytes=[long]$e.OffsetBytes;ReturnedBytes=[int]$e.ReturnedBytes}
    })
    $moved[0].OffsetBytes+=1L
    $bad=Compare-ChappyFatGuardedReturnedSourceEvents @base -OuterReturnedEvents $moved
    Check-D7 ($bad.decision -ceq 'unknown' -and $null -eq $bad.metrics.pairedCoveragePercent) 'same return lengths at shifted location refuse phantom coverage'
    $lost=@($actualEvents | Select-Object -Skip 1)
    $bad=Compare-ChappyFatGuardedReturnedSourceEvents @base -OuterReturnedEvents $lost
    Check-D7 ($bad.decision -ceq 'unknown') 'missing source event refused'
    $replay=@($actualEvents)+@($actualEvents[0])
    $bad=Compare-ChappyFatGuardedReturnedSourceEvents @base -OuterReturnedEvents $replay
    Check-D7 ($bad.decision -ceq 'unknown') 'replayed/duplicated outer A read event refused'
    $bad=Compare-ChappyFatGuardedReturnedSourceEvents -GuardedResult $d -OuterReturnedEvents $actualEvents -SourceLengthBytes $sourceLength -OuterPhysicalReadCalls ($aMeter.Calls+1L) -OuterPrematureZeroReads $aMeter.ZeroReads
    Check-D7 ($bad.decision -ceq 'unknown') 'outer physical Read-call count discrepancy remains UNKNOWN'
    $fakeD=($d | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
    $fakeD.evidence.pairedFullyObservedEntries++
    $bad=Compare-ChappyFatGuardedReturnedSourceEvents -GuardedResult $fakeD -OuterReturnedEvents $actualEvents -SourceLengthBytes $sourceLength -OuterPhysicalReadCalls $aMeter.Calls -OuterPrematureZeroReads $aMeter.ZeroReads
    Check-D7 ($bad.decision -ceq 'unknown' -and $null -eq $bad.metrics.pairedFullyObservedEntries) 'forged D paired index total rejected from physical bytes'
    Check-D7 ((Get-A3DSha256 $rawSourceForMeter) -ceq (Get-A3DSha256 $innerMemory.ToArray())) 'independent D/A meter never wrote artificial source bytes'
}finally{$innerMemory.Dispose()}
# No actual source read in the comparison helper, no source identification,
# and no inference about unseen FAR FAT offset 60000 or both-mirror corruption.
Check-D7 ($scorerPositive -eq 6 -and $scorerNegative -eq 5 -and $scorerUnknown -eq 1) 'scorer units remain narrow damaged BPBs/links vs unknown source, not recovery'
Write-Host ('Team D R7 synthetic A-source negative totals 9 sources actual={0} summedUniquePerSource={1} repeated={2} calls={3}; no real original' -f
    $totalReturned,$sumUnique,($totalReturned-$sumUnique),$totalCalls)
Write-Host ('Team D R7 A7 BPB/source negative matrix: {0} PASS / {1} FAIL' -f $script:Pass,$script:Fail)
if($script:Fail -gt 0){exit 1}
