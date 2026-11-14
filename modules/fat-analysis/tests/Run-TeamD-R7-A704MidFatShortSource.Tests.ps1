#Requires -Version 5.1
# Team D -> A7-04: genuine mid-FAT short successful physical Read + premature zero.
# Artificial standard FAT32 memory only. No FileStream, user device, copy, repair or export.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $root 'core\Chappy.LiveBcdEvidence.psm1') -Force
$script:Pass=0; $script:Fail=0
function Check-D7Late([bool]$Good,[string]$Label) {
    if($Good){$script:Pass++;Write-Host ('PASS '+$Label)}
    else{$script:Fail++;Write-Host ('FAIL '+$Label)}
}
if(-not ('D7LateFat3ByteZeroMemory' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
public sealed class D7LateFat3ByteZeroMemory : MemoryStream {
    readonly long target;
    bool tripped=false;
    long calls=0, zeros=0, triggerCall=0, returned=0;
    int delivered=0;
    public D7LateFat3ByteZeroMemory(byte[] generated, long fatOffset)
        :base(generated,false) {
        if(generated==null || fatOffset<4096 || fatOffset>=generated.LongLength)
            throw new ArgumentException("Generated synthetic FAT target required");
        target=fatOffset;
    }
    public bool Triggered {get{return tripped;}}
    public long TargetOffset {get{return target;}}
    public long TriggerCall {get{return triggerCall;}}
    public long Calls {get{return calls;}}
    public long Returned {get{return returned;}}
    public long SubsequentZeroReads {get{return zeros;}}
    public int TriggerReturnedBytes {get{return delivered;}}
    public override int Read(byte[] buffer,int offset,int count) {
        if(buffer==null || offset<0 || count<0 || offset>buffer.Length-count)
            throw new ArgumentException("Read bounds invalid");
        if(calls>=512)throw new IOException("synthetic source independently capped");
        calls++;
        if(tripped) {zeros++;return 0;}
        // Prior A geometry, B directory, C carving, and D geometry must read
        // before this FAT-window-specific 3B physical success. Not an early VBR failure.
        if(Position==target && calls>8 && count>=3) {
            triggerCall=calls;
            delivered=base.Read(buffer,offset,3);
            returned+=delivered;
            tripped=true;
            return delivered;
        }
        int got=base.Read(buffer,offset,count);
        returned+=got;
        return got;
    }
}
'@
}
$seeds=@(
    [pscustomobject]@{id='SPC1_FAT1_first_4B_only_3_returned';seed=202627;spc=1;fatCopy=1},
    [pscustomobject]@{id='SPC2_FAT2_first_4B_only_3_returned';seed=202628;spc=2;fatCopy=2}
)
$sumGoodReturned=0L; $sumBadReturned=0L; $sumBadUnique=0L
$sumBadRepeated=0L; $sumBadCalls=0L; $hit=0
foreach($case in $seeds){
    $fixture=New-ChappyA3DStandardFixture -Seed $case.seed -SectorsPerCluster $case.spc
    [byte[]]$image=$fixture.image
    [long]$fatSize=[long]([Math]::Ceiling((4.0*(65541+2))/512.0)*512)
    [long]$fat1=33L*512L
    [long]$fat2=$fat1+$fatSize
    [long]$target=$(if($case.fatCopy -eq 1){$fat1}else{$fat2})
    $sha=Get-A3DSha256 $image
    $clean=[IO.MemoryStream]::new($image,$false)
    try{
        $reference=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $clean -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedDirectoryReceipts -BindAObservedFatPairReceipts
        $refReceipt=$reference.dPhysicalReceipt
        Check-D7Late ($reference.status -ceq 'partial' -and
            $reference.d.guardDecision -ceq 'candidate_geometry_unverified' -and
            $refReceipt.decision -ceq 'A_in_process_numeric_FAT_pair_coverage_consistent' -and
            $refReceipt.pairedFullyObservedEntries -eq 128L -and
            $refReceipt.unobservedPairedEntryIndices -eq 65536L -and
            $refReceipt.sourceActualReturnedBytes -eq 4096L) ($case.id+' clean control true A returned 128/65664 paired 4-byte entries')
        Check-D7Late ($reference.metrics.actualReturnedBytes -le 120000L -and
            $reference.metrics.physicalReadCalls -le 512L -and
            $reference.metrics.repeatedReturnedBytes -eq ($reference.metrics.actualReturnedBytes-$reference.metrics.uniqueReturnedBytes) -and
            $reference.originalIdentity -ceq 'unknown' -and -not $reference.canExport) ($case.id+' clean control source costs, no original claim')
        $sumGoodReturned += [long]$reference.metrics.actualReturnedBytes
    }finally{$clean.Dispose()}
    $source=[D7LateFat3ByteZeroMemory]::new($image,$target)
    try{
        $late=Invoke-ChappyA7SyntheticLiveBcdEnvelope -Source $source -EnableSyntheticLiveBcd -UseVersionedBDContracts -BindAObservedDirectoryReceipts -BindAObservedFatPairReceipts
        $receipt=$late.dPhysicalReceipt
        Check-D7Late ($source.Triggered -and
            $source.TargetOffset -eq $target -and
            $source.TriggerReturnedBytes -eq 3 -and
            $source.TriggerCall -gt 8 -and
            $source.SubsequentZeroReads -gt 0 -and
            $source.Position -lt $source.Length) ($case.id+' physical FAT entry produced exactly 3B then true zero despite remaining source')
        Check-D7Late ($late.status -ceq 'partial' -and
            $receipt.decision -cne 'A_in_process_numeric_FAT_pair_coverage_consistent' -and
            $receipt.decision -cne 'A_in_process_geometry_FAT_block_consistent' -and
            $null -eq $receipt.pairedFullyObservedEntries -and
            $null -eq $receipt.unobservedPairedEntryIndices) ($case.id+' no positive A FAT evidence from incomplete 4B source entry')
        Check-D7Late ($late.originalIdentity -ceq 'unknown' -and
            $late.recoveredOriginalFiles -eq 0 -and
            -not $late.canExport -and -not $late.canSelectFatCopy -and
            $receipt.originalIdentity -ceq 'unknown' -and
            $receipt.fatCopyWinner -ceq 'not_selected' -and
            -not $receipt.canExport -and
            -not $source.CanWrite) ($case.id+' original source, FAT winner, export and repair never inferred')
        Check-D7Late ($late.metrics.actualReturnedBytes -eq $source.Returned -and
            $late.metrics.actualReturnedBytes -le 120000L -and
            $late.metrics.physicalReadCalls -eq $source.Calls -and
            $late.metrics.physicalReadCalls -le 512L -and
            $late.metrics.repeatedReturnedBytes -eq ($late.metrics.actualReturnedBytes-$late.metrics.uniqueReturnedBytes)) ($case.id+' independent source call/returned-byte totals reconcile')
        Check-D7Late ((Get-A3DSha256 $image) -ceq $sha) ($case.id+' generated image SHA unchanged after clean and injected A runs')
        if($source.Triggered){$hit++}
        $sumBadReturned += [long]$late.metrics.actualReturnedBytes
        $sumBadUnique += [long]$late.metrics.uniqueReturnedBytes
        $sumBadRepeated += [long]$late.metrics.repeatedReturnedBytes
        $sumBadCalls += [long]$late.metrics.physicalReadCalls
        $phase=$(if($null -ne $late.d.PSObject.Properties['fatProbeState']){[string]$late.d.fatProbeState}else{'not_evaluated'})
        Write-Host ('D R7 midFAT {0}: target={1} 3B_source_call={2} Adecision={3} Dstate={4} returned/unique={5}/{6} reads={7} zeroAfter={8}' -f
            $case.id,$target,$source.TriggerCall,$receipt.decision,$phase,
            $late.metrics.actualReturnedBytes,$late.metrics.uniqueReturnedBytes,$late.metrics.physicalReadCalls,$source.SubsequentZeroReads)
    }finally{$source.Dispose()}
    $fixture=$null;$image=$null
    [GC]::Collect()
}
Check-D7Late ($hit -eq 2 -and $sumGoodReturned -gt $sumBadReturned -and
    $sumBadCalls -gt 0 -and $sumBadRepeated -eq $sumBadReturned-$sumBadUnique) 'Two independent synthetic source faults occurred during FAT phase; meter totals consistent'
Write-Host ('Team D R7 midFAT actual physically returned: two sources total={0} B, sourceLocalUnique={1} B, repeated={2} B, calls={3} (NOT original file recovery)' -f
    $sumBadReturned,$sumBadUnique,$sumBadRepeated,$sumBadCalls)
Write-Host ('Team D R7 A7-04 mid-4B FAT source EOF: {0} PASS / {1} FAIL' -f $script:Pass,$script:Fail)
if($script:Fail -gt 0){exit 1}
