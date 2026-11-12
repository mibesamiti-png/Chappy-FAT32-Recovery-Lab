#Requires -Version 5.1
# Team D Issue #73 R6-P10: only A-generated memory volumes; no physical IMG.
# Test-only independent source-byte observation and conservative FAT coverage.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$repoRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $repoRoot 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32ObservedIoEvidence.psm1') -Force
$script:Pass=0;$script:Fail=0
function Check-D24([bool]$Okay,[string]$Why){
    if($Okay){$script:Pass++;Write-Host ('PASS '+$Why)}
    else{$script:Fail++;Write-Host ('FAIL '+$Why)}
}
function Throws-D24([scriptblock]$Code){
    try{$null=(& $Code);return $false}catch{return $true}
}
# Independent of the in-module D13 events and its claimed coverage.
# Strictly nonwritable, no raw content/event-byte exposure to reports or logs.
if(-not ('D24ExternalSource' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D24PhysicalEvent {
    public long OffsetBytes {get;set;}
    public int ReturnedBytes {get;set;}
}
public sealed class D24ExternalSource : Stream {
    readonly MemoryStream source;
    readonly Dictionary<long,byte> seen=new Dictionary<long,byte>();
    readonly List<D24PhysicalEvent> events=new List<D24PhysicalEvent>();
    readonly long maxSourceBytes;
    readonly long stopAt;
    readonly int chunk;
    long used=0,calls=0,earlyZero=0;
    public D24ExternalSource(byte[] input,long maxBytes,long stopAfter,int maxChunk){
        if(input==null || maxBytes<2048 || maxBytes>120000 || maxChunk<1 || maxChunk>4096 || stopAfter<0)
            throw new ArgumentException("Invalid artificial observer limits");
        source=new MemoryStream(input,false);
        maxSourceBytes=maxBytes;stopAt=stopAfter;chunk=maxChunk;
    }
    public long ActualBytes {get{return used;}}
    public long UniqueBytes {get{return seen.Count;}}
    public long DuplicateBytes {get{return used-seen.Count;}}
    public long ReadCalls {get{return calls;}}
    public long EarlyZeroBeforeLength {get{return earlyZero;}}
    public D24PhysicalEvent[] GetEvents(){return events.ToArray();}
    public bool HasRange(long start,int count){
        if(start<0 || count<0 || start>long.MaxValue-count)return false;
        for(int i=0;i<count;i++)if(!seen.ContainsKey(start+i))return false;
        return true;
    }
    public byte ObservedByte(long offset){
        byte value;
        if(!seen.TryGetValue(offset,out value))throw new InvalidOperationException("Byte not physically observed");
        return value;
    }
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return source.Length;}}
    public override long Position {get{return source.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long offset,SeekOrigin origin){return source.Seek(offset,origin);}
    public override int Read(byte[] buffer,int offset,int count){
        if(buffer==null || offset<0 || count<0 || offset>buffer.Length-count)throw new ArgumentException("Invalid Read");
        calls++;
        if(count>maxSourceBytes-used)throw new IOException("D24.outer_source_budget_exhausted");
        if(count==0)return 0;
        long at=source.Position;
        if(used>=stopAt){
            if(at<source.Length)earlyZero++;
            return 0;
        }
        int allowed=(int)Math.Min((long)count,Math.Min((long)chunk,stopAt-used));
        int n=source.Read(buffer,offset,allowed);
        if(n==0 && at<source.Length)earlyZero++;
        if(n>0){
            used+=n;
            events.Add(new D24PhysicalEvent{OffsetBytes=at,ReturnedBytes=n});
            for(int i=0;i<n;i++)seen[at+i]=buffer[offset+i];
        }
        return n;
    }
    public override void Flush(){}
    public override void SetLength(long x){throw new NotSupportedException();}
    public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
    // Input belongs to this tests-only memory fixture; no file handles exist.
}
'@
}
# Parse only physical bytes previously returned into D24ExternalSource.
# This is an independently checked *numeric candidate*, NOT FAT authenticity.
function Get-D24CandidateGeometry {
    param([D24ExternalSource]$Observed)
    $unknown=[pscustomobject]@{valid=$false;reason='numeric_metadata_not_observed_or_invalid';
        fat1=0L;fat2=0L;fatBytes=0L;entries=0L;clusters=0L}
    if(-not $Observed.HasRange(0,512)){return $unknown}
    $mbr=[byte[]]::new(512)
    for($i=0;$i -lt 512;$i++){$mbr[$i]=$Observed.ObservedByte([long]$i)}
    if($mbr[510] -ne 0x55 -or $mbr[511] -ne 0xAA -or
        @([int]0x0B,[int]0x0C) -notcontains [int]$mbr[450] -or
        @([int]0,[int]0x80) -notcontains [int]$mbr[446]){return $unknown}
    $lba=[long][BitConverter]::ToUInt32($mbr,454)
    $sectors=[long][BitConverter]::ToUInt32($mbr,458)
    if($lba -lt 1 -or $sectors -lt 1){return $unknown}
    $start=$lba*512L;$end=$start+$sectors*512L
    if($end -gt $Observed.Length -or -not $Observed.HasRange($start,512)){return $unknown}
    $vbr=[byte[]]::new(512)
    for($i=0;$i -lt 512;$i++){$vbr[$i]=$Observed.ObservedByte($start+$i)}
    $bps=[long][BitConverter]::ToUInt16($vbr,11)
    $spc=[long]$vbr[13]
    $reserved=[long][BitConverter]::ToUInt16($vbr,14)
    $fatCopies=[long]$vbr[16]
    $fatSectors=[long][BitConverter]::ToUInt32($vbr,36)
    $total=[long][BitConverter]::ToUInt32($vbr,32)
    if($vbr[510] -ne 0x55 -or $vbr[511] -ne 0xAA -or
        $bps -ne 512 -or $spc -notin @(1L,2L,4L,8L,16L,32L,64L) -or
        $reserved -lt 2 -or $fatCopies -ne 2 -or
        $fatSectors -lt 1 -or $total -lt 1 -or $total -gt $sectors){
        return $unknown
    }
    $fatBytes=$fatSectors*$bps
    $first=$start+$reserved*$bps
    $second=$first+$fatBytes
    $afterFat=$second+$fatBytes
    $volumeEnd=$start+$total*$bps
    $dataSectors=$total-$reserved-$fatCopies*$fatSectors
    if($dataSectors -le 0 -or $afterFat -ge $volumeEnd -or
        $volumeEnd -gt $end -or $second -ge $volumeEnd -or $fatBytes%4 -ne 0){return $unknown}
    $clusters=[long][Math]::Floor($dataSectors/$spc)
    $entries=[long]($fatBytes/4)
    if($clusters -lt 65525 -or $clusters -ge 0x0FFFFFF5 -or
        $entries -lt ($clusters+2) -or $entries -gt 1000000){return $unknown}
    return [pscustomobject]@{valid=$true;reason='numeric_bounds_only_not_authenticated';
        fat1=$first;fat2=$second;fatBytes=$fatBytes;entries=$entries;clusters=$clusters}
}
# This receives only actually returned bytes, never D event claims or scorer data.
# Counts full 4-byte FAT entries by physical copy, plus paired mirror indices.
function Get-D24ConservativeCoverage {
    param([D24ExternalSource]$Observed)
    $numeric=Get-D24CandidateGeometry -Observed $Observed
    if(-not $numeric.valid -or $Observed.EarlyZeroBeforeLength -gt 0){
        return [pscustomobject]@{state='unknown';reason=$(
            if(-not $numeric.valid){$numeric.reason}else{'io.premature_zero_before_advertised_length'});
            fatEntries=$null;fat1Observed=$null;fat2Observed=$null;paired=$null;
            pairCoveragePercent=$null;unobservedPairPercent=$null;
            geometryAuthentic=$false;wholeFatVerified=$false;
            copyWinner='not_selected';originalIdentity='unknown';fileOwner='unknown';writePermitted=$false}
    }
    $inF1=New-Object 'System.Collections.Generic.HashSet[long]'
    $inF2=New-Object 'System.Collections.Generic.HashSet[long]'
    foreach($ev in $Observed.GetEvents()){
        $start=[long]$ev.OffsetBytes;$end=$start+[long]$ev.ReturnedBytes
        foreach($copyIndex in @(0,1)){
            $base=$(if($copyIndex -eq 0){$numeric.fat1}else{$numeric.fat2})
            $bound=$base+$numeric.fatBytes
            $lo=[long][Math]::Max($start,$base)
            $hi=[long][Math]::Min($end,$bound)
            if($hi -le $lo){continue}
            $first=[long][Math]::Floor(($lo-$base)/4)
            $last=[long][Math]::Floor(($hi-1-$base)/4)
            for($i=$first;$i -le $last;$i++){
                if($copyIndex -eq 0){[void]$inF1.Add([long]$i)}
                else{[void]$inF2.Add([long]$i)}
            }
        }
    }
    $full1=New-Object 'System.Collections.Generic.HashSet[long]'
    $full2=New-Object 'System.Collections.Generic.HashSet[long]'
    foreach($i in $inF1){
        if($Observed.HasRange(($numeric.fat1+[long]$i*4L),4)){[void]$full1.Add([long]$i)}
    }
    foreach($i in $inF2){
        if($Observed.HasRange(($numeric.fat2+[long]$i*4L),4)){[void]$full2.Add([long]$i)}
    }
    $paired=0L
    foreach($i in $full1){if($full2.Contains($i)){$paired++}}
    $pct=[Math]::Round(100.0*[double]$paired/[double]$numeric.entries,8)
    return [pscustomobject]@{
        state='partial_numeric_candidate_only'
        reason='only_complete_physically_returned_4byte_entries_counted'
        fatEntries=[long]$numeric.entries
        fat1Observed=[long]$full1.Count
        fat2Observed=[long]$full2.Count
        paired=[long]$paired
        pairCoveragePercent=$pct
        unobservedPairPercent=[Math]::Round(100.0-$pct,8)
        geometryAuthentic=$false;wholeFatVerified=$false
        copyWinner='not_selected';originalIdentity='unknown';fileOwner='unknown';writePermitted=$false
    }
}
$cases=@(
    [pscustomobject]@{id='clean512';seed=202611;spc=1;fault='clean';stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='clean1024';seed=202611;spc=2;fault='clean';stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='clean512_seed2';seed=202612;spc=1;fault='clean';stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='single_copy_link4';seed=202613;spc=1;fault='fat2_only';stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='common_mode_cycle';seed=202613;spc=2;fault='both_cycle';stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='remote60000';seed=202612;spc=2;fault='remote';stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='bad_spc';seed=202611;spc=1;fault='bad_spc';stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='oversized_fat';seed=202611;spc=2;fault='bad_fat';stop=[long]::MaxValue;chunk=4096},
    [pscustomobject]@{id='short_early_eof';seed=202611;spc=1;fault='clean';stop=1100L;chunk=7}
)
$caseCount=0;$knownClean=0;$knownFault=0;$unknownOriginal=0
$totalActual=0L;$totalUnique=0L;$totalCalls=0L
foreach($c in $cases){
    $synthetic=New-ChappyA3DStandardFixture -Seed $c.seed -SectorsPerCluster $c.spc -Fragment3Mf:($c.spc -eq 1)
    [byte[]]$data=[byte[]]$synthetic.image
    # Synthetic-only truth used by the scorer. The D diagnostic does not see it.
    $fatSectors=[int][Math]::Ceiling(4.0*(65541+2)/512.0)
    $fat1=(1+32)*512
    $fat2=(1+32+$fatSectors)*512
    switch($c.fault){
        'fat2_only' {
            [byte[]]$patch=[BitConverter]::GetBytes([uint32]4)
            [Array]::Copy($patch,0,$data,$fat2+16,4)
        }
        'both_cycle' {
            [byte[]]$patch=[BitConverter]::GetBytes([uint32]4)
            [Array]::Copy($patch,0,$data,$fat1+16,4)
            [Array]::Copy($patch,0,$data,$fat2+16,4)
        }
        'remote' {
            [byte[]]$patch=[BitConverter]::GetBytes([uint32]1)
            [Array]::Copy($patch,0,$data,$fat2+4*60000,4)
        }
        'bad_spc' {$data[525]=0}
        'bad_fat' {
            [byte[]]$patch=[BitConverter]::GetBytes([uint32]::MaxValue)
            [Array]::Copy($patch,0,$data,512+36,4)
        }
    }
    $before=Get-A3DSha256 $data
    $out=[D24ExternalSource]::new($data,120000L,$c.stop,$c.chunk)
    try{
        $baseline=Get-ChappyFatObservedIoEvidence -Stream $out -Mode MirrorAndChain -MaxReadBytes 2048
        $coverage=Get-D24ConservativeCoverage -Observed $out
        Check-D24 ($baseline.team -ceq 'D' -and $baseline.experimentalDefaultOff -and
            -not $baseline.writePermitted -and $baseline.sourceDecision -ceq 'not_selected' -and
            $baseline.metrics.bytesRead -le 2048L) ($c.id+' unchanged D read-only default-off and D subcap')
        Check-D24 ($out.ActualBytes -eq [long]$baseline.metrics.bytesRead -and
            $out.ActualBytes -le 2048L -and $out.ActualBytes -le 120000L -and
            $out.UniqueBytes -le $out.ActualBytes) ($c.id+' independent real returned byte budget')
        $sum=0L
        foreach($ev in $out.GetEvents()){$sum+=[long]$ev.ReturnedBytes}
        Check-D24 ($sum -eq $out.ActualBytes -and
            $out.DuplicateBytes -eq ($out.ActualBytes-$out.UniqueBytes) -and
            $out.ReadCalls -ge @($out.GetEvents()).Count) ($c.id+' independent physical event, unique/duplicate reconciliation')
        Check-D24 (-not $coverage.geometryAuthentic -and -not $coverage.wholeFatVerified -and
            $coverage.copyWinner -ceq 'not_selected' -and
            $coverage.fileOwner -ceq 'unknown' -and
            $coverage.originalIdentity -ceq 'unknown' -and -not $coverage.writePermitted) ($c.id+' no full FAT, owner, original or repair confidence')
        Check-D24 ((Get-A3DSha256 $data) -ceq $before) ($c.id+' generated source hash unchanged')
        if($c.fault -in @('bad_spc','bad_fat') -or $c.id -ceq 'short_early_eof'){
            Check-D24 ($coverage.state -ceq 'unknown' -and $null -eq $coverage.fatEntries -and
                $null -eq $coverage.pairCoveragePercent) ($c.id+' invalid or source-incomplete metadata abstains UNKNOWN')
            if($c.id -ceq 'short_early_eof'){
                Check-D24 ($out.EarlyZeroBeforeLength -gt 0 -and
                    $baseline.metrics.prematureSourceZeroReads -gt 0) 'actual early zero before claimed 32MiB length stays UNKNOWN'
            }
        }else{
            Check-D24 ($coverage.state -ceq 'partial_numeric_candidate_only' -and
                $coverage.fatEntries -ge 65543 -and
                $coverage.fat1Observed -ge 64 -and $coverage.fat2Observed -ge 64 -and
                $coverage.paired -ge 64 -and $coverage.paired -lt $coverage.fatEntries) ($c.id+' full 4-byte FAT entries physically observed but tiny fraction')
            Check-D24 ($coverage.pairCoveragePercent -lt 0.2 -and
                $coverage.unobservedPairPercent -gt 99.8) ($c.id+' >99.8% FAT pair entries genuinely UNOBSERVED')
            Check-D24 ($out.DuplicateBytes -gt 0 -and
                $out.HasRange($fat1+4*4,4) -and $out.HasRange($fat2+4*4,4)) ($c.id+' repeated source and FAT1/FAT2 link4 independently observed')
        }
        switch($c.fault){
            'clean' {
                if($c.id -ne 'short_early_eof'){
                    $knownClean++
                    Check-D24 ($baseline.evidence.mirrorDifferentEntries -eq 0 -and
                        $baseline.evidence.observedCycles -eq 0) ($c.id+' matching observed clean mirrors not whole FAT health')
                }
            }
            'fat2_only' {
                $knownFault++
                Check-D24 ($baseline.evidence.mirrorDifferentEntries -ge 1) 'scorer planted FAT2 link4 difference detected, no winner'
            }
            'both_cycle' {
                $knownFault++
                Check-D24 ($baseline.evidence.mirrorDifferentEntries -eq 0 -and
                    $baseline.evidence.observedCycles -gt 0) 'both mirrors identically cyclic; mirror equality not proof'
            }
            'remote' {
                $knownFault++
                Check-D24 ($baseline.evidence.mirrorDifferentEntries -eq 0 -and
                    $out.HasRange($fat2+4*60000,4) -eq $false) 'remote60000 not observed: no false healthy claim'
            }
        }
        $unknownOriginal++
        $totalActual+=$out.ActualBytes;$totalUnique+=$out.UniqueBytes;$totalCalls+=$out.ReadCalls
        $caseCount++
        Write-Host ('D P10 case={0} seed={1} spc={2} status={3} FATentries={4} observed FAT1/FAT2/paired={5}/{6}/{7} observedPairPct={8} bytes actual/unique={9}/{10} ReadCalls={11} earlyZero={12} mirrorDiff={13} cycles={14} originalIdentity=unknown' -f
            $c.id,$c.seed,$c.spc,$coverage.state,$coverage.fatEntries,
            $coverage.fat1Observed,$coverage.fat2Observed,$coverage.paired,
            $coverage.pairCoveragePercent,$out.ActualBytes,$out.UniqueBytes,$out.ReadCalls,
            $out.EarlyZeroBeforeLength,$baseline.evidence.mirrorDifferentEntries,$baseline.evidence.observedCycles)
    }finally{$out.Dispose();$synthetic=$null;$data=$null;[GC]::Collect()}
}
Check-D24 ($caseCount -eq 9 -and $knownClean -eq 3 -and $knownFault -eq 3 -and
    $unknownOriginal -eq 9) 'nine predeclared artificial cases, no original file identity claims'
# The observer enforces outer 120000B source ceiling, D separately uses 2048B.
[byte[]]$fake=[byte[]]::new(4096)
$writable=[IO.MemoryStream]::new($fake,$true)
try{
    Check-D24 (Throws-D24 {Get-ChappyFatObservedIoEvidence -Stream $writable -MaxReadBytes 2048}) 'D existing API rejects writable input'
}finally{$writable.Dispose()}
$refused=[D24ExternalSource]::new($fake,2048L,[long]::MaxValue,4096)
try{
    [byte[]]$tooMany=[byte[]]::new(2049)
    Check-D24 (Throws-D24 {[void]$refused.Read($tooMany,0,$tooMany.Length)}) 'External source over-cap request fails closed, not synthetic EOF'
    Check-D24 ($refused.ActualBytes -eq 0 -and @($refused.GetEvents()).Count -eq 0) 'Denied read produces no returned bytes or false event'
}finally{$refused.Dispose()}
Write-Host ('D P10 SUMMARY cases={0} clean={1} plantedFaults={2} originalUnknown={3} actualBytes={4} summedUniquePerSource={5} duplicateBytes={6} physicalReadCalls={7}' -f
    $caseCount,$knownClean,$knownFault,$unknownOriginal,$totalActual,$totalUnique,($totalActual-$totalUnique),$totalCalls)
Write-Host ('Team D R6 P10 standards-shaped physical FAT coverage: {0} PASS, {1} FAIL' -f $script:Pass,$script:Fail)
if($script:Fail -gt 0){exit 1}
