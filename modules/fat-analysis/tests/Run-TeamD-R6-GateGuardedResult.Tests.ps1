#Requires -Version 5.1
# Team D D6-05: generated artificial memory sources only, native PS5.1.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32GuardedResult.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32ObservedIoEvidence.psm1') -Force
$script:Pass=0;$script:Fail=0
function Assert-D605([bool]$Yes,[string]$Label){
    if($Yes){$script:Pass++;Write-Host ('PASS '+$Label)}
    else{$script:Fail++;Write-Host ('FAIL '+$Label)}
}
function Throws-D605([scriptblock]$Code){
    try{$null=& $Code;return $false}catch{return $true}
}
function Hash-D605([byte[]]$Data){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($Data)).Replace('-','')}
    finally{$sha.Dispose()}
}
function Set-D605U16([byte[]]$Data,[int]$At,[uint16]$V){
    [Array]::Copy([BitConverter]::GetBytes($V),0,$Data,$At,2)
}
function Set-D605U32([byte[]]$Data,[int]$At,[uint32]$V){
    [Array]::Copy([BitConverter]::GetBytes($V),0,$Data,$At,4)
}
# Test-side independent physical observer records each successful return and
# unique source offset. It is not the new D605 module's internal meter.
if(-not ('D605IndependentMemorySource' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D605IndependentMemorySource : Stream {
    readonly MemoryStream input;
    readonly HashSet<long> unique=new HashSet<long>();
    readonly long cutoff;
    readonly int chunk;
    long actual=0,calls=0,early=0,fatCalls=0;
    public D605IndependentMemorySource(byte[] data,long stopAfter,int chunkSize){
        if(data==null||stopAfter<0||chunkSize<1||chunkSize>4096)
           throw new ArgumentException("Invalid artificial memory source");
        input=new MemoryStream(data,false);cutoff=stopAfter;chunk=chunkSize;
    }
    public long Actual {get{return actual;}}
    public long Unique {get{return unique.Count;}}
    public long Repeated {get{return actual-unique.Count;}}
    public long Calls {get{return calls;}}
    public long EarlyZero {get{return early;}}
    public long FatCalls {get{return fatCalls;}}
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return input.Length;}}
    public override long Position {get{return input.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long offset,SeekOrigin origin){return input.Seek(offset,origin);}
    public override int Read(byte[] b,int off,int count){
        if(b==null||off<0||count<0||off>b.Length-count)throw new ArgumentException("Invalid Read");
        if(calls>=800||count>120000-actual)throw new IOException("D605.external_synthetic_source_cap");
        calls++;
        long at=input.Position;
        if(at>=16896&&at<543000)fatCalls++;
        if(actual>=cutoff){if(at<input.Length)early++;return 0;}
        int n=input.Read(b,off,(int)Math.Min((long)count,Math.Min((long)chunk,cutoff-actual)));
        if(n==0&&at<input.Length)early++;
        for(int i=0;i<n;i++)unique.Add(at+i);
        actual+=n;
        return n;
    }
    public override void Flush(){}
    public override void SetLength(long n){throw new NotSupportedException();}
    public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
    protected override void Dispose(bool disposing){if(disposing)input.Dispose();base.Dispose(disposing);}
}
'@
}
function Invoke-D605Case {
    param([byte[]]$Data,[switch]$Enabled,[switch]$Chains,
        [long]$Cutoff=[long]::MaxValue,[int]$Chunk=4096,
        [int]$Bytes=4096,[int]$Calls=512)
    $src=[D605IndependentMemorySource]::new($Data,$Cutoff,$Chunk)
    try{
        $args=@{Stream=$src;MaxPhysicalReadBytes=$Bytes;MaxPhysicalReadCalls=$Calls}
        if($Enabled){$args.EnableGuardedDiagnostics=$true}
        if($Chains){$args.IncludeFixedChainEvidence=$true}
        $report=Get-ChappyFatGuardedResult @args
        return [pscustomobject]@{
            report=$report;actual=$src.Actual;unique=$src.Unique
            repeated=$src.Repeated;calls=$src.Calls;early=$src.EarlyZero
            fatCalls=$src.FatCalls
        }
    }finally{$src.Dispose()}
}
function Check-D605Contract($Case,$T,[int]$Cap,[int]$CallCap){
    $o=$T.report;$m=$o.metrics
    Assert-D605 ($o.schemaVersion -ceq '1' -and
        $o.contractVersion -ceq 'd6_guarded_fat_result_v1' -and
        $o.team -ceq 'D' -and
        $o.mode -ceq 'default_off_guarded_fixed_fat_diagnostics' -and
        $o.PSObject.Properties['hypotheses'] -ne $null -and
        $o.PSObject.Properties['evidence'] -ne $null -and
        $o.PSObject.Properties['copies'] -ne $null -and
        @($o.copies).Count -eq 2 -and
        $o.copies[0].fatCopyIndex -eq 0 -and
        $o.copies[1].fatCopyIndex -eq 1) ($Case+' stable schema and two FAT roles in every state')
    Assert-D605 ($o.geometryAuthenticity -ceq 'unknown' -and
        $o.sourceIdentity -ceq 'unknown' -and $o.originalIdentity -ceq 'unknown' -and
        $o.fileOwner -ceq 'unknown' -and
        $o.fatCopyWinner -ceq 'not_selected' -and
        $o.sourceDecision -ceq 'not_selected' -and
        $null -eq $o.selectedCandidate -and
        -not $o.fatReadAllowed -and -not $o.writePermitted -and
        -not $o.canRepair -and -not $o.canExport -and
        -not $o.wholeFatVerified -and $o.scanIncomplete) ($Case+' no original, source, FAT winner, repair or export')
    Assert-D605 ($m.actualReturnedBytes -eq $T.actual -and
        $m.uniqueReturnedBytes -eq $T.unique -and
        $m.repeatedReturnedBytes -eq $T.repeated -and
        $m.physicalReadCalls -eq $T.calls -and
        $T.actual -le $Cap -and $T.calls -le $CallCap -and
        $m.geometryGateReturnedBytes+$m.fatFixedReturnedBytes -eq $T.actual) ($Case+' independent physical returned/unique/repeated/calls and summed phase budgets')
    Assert-D605 ($o.sourceReadProvenance -ceq 'internal_D_source_events_NOT_A_attested' -and
        $o.warnings -contains 'd6.unobserved_fat_entries_UNKNOWN_not_clean') ($Case+' D events never promoted to A authenticated source')
}
$cases=@(
    [pscustomobject]@{id='clean_spc1';seed=202614;spc=1;fault='none';chain=$false;expect='fixed_baseline_sampled';pairs=128;cut=[long]::MaxValue;chunk=4096;calls=512},
    [pscustomobject]@{id='clean_spc2';seed=202615;spc=2;fault='none';chain=$false;expect='fixed_baseline_sampled';pairs=128;cut=[long]::MaxValue;chunk=4096;calls=512},
    [pscustomobject]@{id='healthy_fragmented';seed=202616;spc=1;fault='fragment';chain=$false;expect='fixed_baseline_sampled';pairs=128;cut=[long]::MaxValue;chunk=4096;calls=512},
    [pscustomobject]@{id='fat2_link4_mismatch';seed=202614;spc=1;fault='fat2';chain=$false;expect='fixed_baseline_sampled';pairs=128;cut=[long]::MaxValue;chunk=4096;calls=512},
    [pscustomobject]@{id='identical_fat_cycles';seed=202615;spc=2;fault='both_cycle';chain=$true;expect='fixed_baseline_sampled';pairs=64;cut=[long]::MaxValue;chunk=4096;calls=512},
    [pscustomobject]@{id='far_fat2_entry60000';seed=202616;spc=2;fault='far';chain=$false;expect='fixed_baseline_sampled';pairs=128;cut=[long]::MaxValue;chunk=4096;calls=512},
    [pscustomobject]@{id='backup_reserved33';seed=202614;spc=1;fault='reserve';chain=$false;expect='blocked_geometry_or_source_UNKNOWN';pairs=$null;cut=[long]::MaxValue;chunk=4096;calls=512},
    [pscustomobject]@{id='backup_root3';seed=202614;spc=1;fault='root';chain=$false;expect='blocked_geometry_or_source_UNKNOWN';pairs=$null;cut=[long]::MaxValue;chunk=4096;calls=512},
    [pscustomobject]@{id='invalid_backup_signature';seed=202614;spc=1;fault='backup_sig';chain=$false;expect='blocked_geometry_or_source_UNKNOWN';pairs=$null;cut=[long]::MaxValue;chunk=4096;calls=512},
    [pscustomobject]@{id='invalid_primary_spc';seed=202614;spc=1;fault='spc';chain=$false;expect='blocked_geometry_or_source_UNKNOWN';pairs=$null;cut=[long]::MaxValue;chunk=4096;calls=512},
    [pscustomobject]@{id='early_zero_1100';seed=202614;spc=1;fault='none';chain=$false;expect='blocked_geometry_or_source_UNKNOWN';pairs=$null;cut=1100L;chunk=7;calls=512},
    [pscustomobject]@{id='call_cap4_1byte';seed=202614;spc=1;fault='none';chain=$false;expect='blocked_geometry_or_source_UNKNOWN';pairs=$null;cut=[long]::MaxValue;chunk=1;calls=4}
)
$sampled=0;$blocked=0;$allActual=0L;$allUnique=0L;$allCalls=0L
$normalBaselineActual=0L;$normalAdapterActual=0L
foreach($c in $cases){
    $fixture=New-ChappyA3DStandardFixture -Seed $c.seed -SectorsPerCluster $c.spc -Fragment3Mf:($c.fault -eq 'fragment')
    [byte[]]$data=$fixture.image
    $fatSectors=[int][Math]::Ceiling((4.0*(65541+2))/512.0)
    $f1=33*512;$f2=$f1+$fatSectors*512
    switch($c.fault){
        'fat2' {Set-D605U32 $data ($f2+16) ([uint32]4)}
        'both_cycle' {
            Set-D605U32 $data ($f1+16) ([uint32]4)
            Set-D605U32 $data ($f2+16) ([uint32]4)
        }
        'far' {Set-D605U32 $data ($f2+4*60000) ([uint32]1)}
        'reserve' {Set-D605U16 $data (3584+14) ([uint16]33)}
        'root' {Set-D605U32 $data (3584+44) ([uint32]3)}
        'backup_sig' {$data[3584+510]=0}
        'spc' {$data[512+13]=0}
    }
    $shaBefore=Hash-D605 $data
    $t=Invoke-D605Case -Data $data -Enabled -Chains:($c.chain) -Cutoff $c.cut -Chunk $c.chunk -Calls $c.calls
    $o=$t.report
    Write-Host ('D605 reason '+$c.id+' = '+([string]::Join(';',[string[]]@($o.reasonCodes))))
    Check-D605Contract $c.id $t 4096 $c.calls
    Assert-D605 ($o.fatProbeState -ceq $c.expect) ($c.id+' explicit fixed baseline or deny-before-FAT classification')
    Assert-D605 ((Hash-D605 $data) -ceq $shaBefore) ($c.id+' input synthetic SHA256 unchanged')
    if($c.pairs -ne $null){
        $sampled++
        Assert-D605 ($o.guardDecision -ceq 'candidate_geometry_unverified' -and
            $o.status -ceq 'partial' -and
            $o.evidence.coverageStatus -ceq 'partial_numeric_candidate_only' -and
            $o.evidence.totalDeclaredEntriesPerCopy -eq 65664 -and
            $o.evidence.pairedFullyObservedEntries -eq $c.pairs -and
            $o.evidence.unobservedPairedEntryIndices -eq (65664-$c.pairs) -and
            $o.evidence.unobservedPairPercent -gt 99.8 -and
            $o.copies[0].fullyObservedEntries -ge $c.pairs -and
            $o.copies[1].fullyObservedEntries -ge $c.pairs) ($c.id+' 2 copies exact physically complete paired indices and vast UNKNOWN remainder')
        Assert-D605 ($t.fatCalls -gt 0 -and
            $o.metrics.geometryGateReturnedBytes -eq 2048 -and
            $o.metrics.fatFixedReturnedBytes -le 2048 -and
            $o.metrics.fatFixedReturnedBytes -ge 1536) ($c.id+' only allowed candidate hypothesis can use bounded fixed FAT sampler')
        if($c.id -eq 'fat2_link4_mismatch'){
            Assert-D605 ($o.evidence.mirrorDifferentEntries -gt 0) 'FAT2 mismatch observed but neither copy chosen'
        }
        if($c.id -eq 'identical_fat_cycles'){
            Assert-D605 ($o.evidence.mirrorDifferentEntries -eq 0 -and
                $o.evidence.observedCycles -gt 0) 'Equal mirrors with observed cycle are NOT certified healthy'
        }
        if($c.id -eq 'far_fat2_entry60000'){
            Assert-D605 ($o.evidence.unobservedPairedEntryIndices -gt 65000 -and
                $o.warnings -contains 'd6.unobserved_fat_entries_UNKNOWN_not_clean') 'Remote FAT2 mutation outside fixed window stays unknown'
        }
        if($c.id -eq 'clean_spc1'){
            # Same bytes and mode in *unchanged* D13 source-only baseline, but
            # the new wrapper incurs a separate 2048 B VBR contradiction gate.
            $baseline=[D605IndependentMemorySource]::new($data,[long]::MaxValue,4096)
            try{
                $original=Get-ChappyFatObservedIoEvidence -Stream $baseline -Mode MirrorOnly -MaxReadBytes 2048
                Assert-D605 ($original.evidence.mirrorDifferentEntries -eq $o.evidence.mirrorDifferentEntries -and
                    $original.metrics.bytesRead -eq $o.metrics.fatFixedReturnedBytes -and
                    $original.metrics.uniquePhysicalBytes -le $original.metrics.bytesRead) 'Unchanged fixed MirrorOnly module compared on same generated source'
                $normalBaselineActual=$baseline.Actual
                $normalAdapterActual=$t.actual
                Assert-D605 ($normalAdapterActual -eq $normalBaselineActual+2048 -and
                    $o.metrics.geometryGateReturnedBytes -eq 2048) 'Added safety preflight measured exactly 2048 physical returned B (not free)'
            }finally{$baseline.Dispose()}
        }
    }else{
        $blocked++
        Assert-D605 ($o.status -eq 'partial' -and
            $o.guardDecision -ne 'candidate_geometry_unverified' -and
            $t.fatCalls -eq 0 -and $o.metrics.fatFixedReturnedBytes -eq 0 -and
            $null -eq $o.evidence.pairedCoveragePercent -and
            $null -eq $o.evidence.pairedFullyObservedEntries -and
            $null -eq $o.copies[0].fullyObservedEntries -and
            $null -eq $o.copies[1].fullyObservedEntries) ($c.id+' real external source observed ZERO FAT reads under conflict/EOF')
        if($c.id -eq 'early_zero_1100'){
            Assert-D605 ($t.early -gt 0 -and $o.metrics.prematureSourceZeroReads -gt 0 -and
                $t.actual -eq 1100) 'Premature early zero after real 1100 returned bytes stays UNKNOWN'
        }
        if($c.id -eq 'call_cap4_1byte'){
            Assert-D605 ($t.calls -eq 4 -and $o.metrics.physicalReadCalls -eq 4 -and
                $o.reasonCodes -contains 'io.bounded_structure_observation_failed' -and
                $o.guardDecision -ceq 'blocked_insufficient_evidence') 'Inner VBR call quota stops at four physical reads; outer quota not falsely claimed exceeded'
        }
    }
    $allActual+=$t.actual;$allUnique+=$t.unique;$allCalls+=$t.calls
    Write-Host ('D6-05 fixture={0} guard={1} fat={2} pairs={3} / {4} actual/unique={5}/{6} calls={7} sourceOriginal=UNKNOWN' -f
        $c.id,$o.guardDecision,$o.fatProbeState,$o.evidence.pairedFullyObservedEntries,
        $o.evidence.totalDeclaredEntriesPerCopy,$t.actual,$t.unique,$t.calls)
    $fixture=$null;$data=$null;[GC]::Collect()
}
Assert-D605 ($sampled -eq 6 -and $blocked -eq 6) 'Six fixed-sample and six conservative denied synthetic scenarios; never recovery rate'
# Disabled is genuinely no I/O, even with a readable synthetic source.
$bytes=[byte[]]::new(8192)
$source=[D605IndependentMemorySource]::new($bytes,[long]::MaxValue,4096)
try{
    $disabled=Get-ChappyFatGuardedResult -Stream $source
    Check-D605Contract 'default_off' ([pscustomobject]@{report=$disabled;actual=$source.Actual;unique=$source.Unique;repeated=0;calls=$source.Calls}) 4096 512
    Assert-D605 ($disabled.status -ceq 'disabled' -and
        $disabled.fatProbeState -ceq 'not_attempted' -and
        $disabled.reasonCodes -contains 'd6.enable_explicit_optin_required' -and
        $source.Calls -eq 0) 'Default OFF causes zero source reads'
    Assert-D605 (Throws-D605 {Get-ChappyFatGuardedResult -Stream $source -EnableGuardedDiagnostics -MaxPhysicalReadBytes 4097}) 'Physical source byte cap max 4096 validated'
    Assert-D605 (Throws-D605 {Get-ChappyFatGuardedResult -Stream $source -EnableGuardedDiagnostics -MaxPhysicalReadCalls 513}) 'Physical call cap max 512 validated'
}finally{$source.Dispose()}
$writable=[IO.MemoryStream]::new($bytes,$true)
try{
    $blocked=Get-ChappyFatGuardedResult -Stream $writable -EnableGuardedDiagnostics
    Assert-D605 ($blocked.status -ceq 'unknown' -and
        $blocked.reasonCodes -contains 'input.strictly_nonwritable_seekable_stream_required' -and
        $blocked.metrics.actualReturnedBytes -eq 0 -and
        $blocked.metrics.physicalReadCalls -eq 0 -and
        $blocked.fatCopyWinner -eq 'not_selected') 'Writable source refused before physical Read'
}finally{$writable.Dispose()}
$ro=[IO.MemoryStream]::new($bytes,$false)
try{
    $json=Get-ChappyFatGuardedResult -Stream $ro -EnableGuardedDiagnostics | ConvertTo-Json -Depth 9
    Assert-D605 ($json -notmatch '(?i)sourcePath|fileName|repairTarget|rawBytes|originalSha256|recoveredPayload|originalOwner' -and
        $json -match 'd6_guarded_fat_result_v1' -and $json -match 'not_selected') 'Stable JSON excludes paths, payload, hashes and auto FAT copy winner'
}finally{$ro.Dispose()}
Write-Host ('D6-05 synthetic guard matrix sampled={0} blocked={1} source physical actual/unique={2}/{3} repeats={4} calls={5}; baseline normal={6} adapter normal={7}' -f
    $sampled,6,$allActual,$allUnique,($allActual-$allUnique),$allCalls,$normalBaselineActual,$normalAdapterActual)
Write-Host ('Team D D6-05 stable guarded v1 result: {0} PASS / {1} FAIL' -f $script:Pass,$script:Fail)
if($script:Fail -gt 0){exit 1}
