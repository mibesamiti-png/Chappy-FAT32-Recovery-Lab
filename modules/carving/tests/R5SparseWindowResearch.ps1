#Requires -Version 5.1
# Team C #72: synthetic-only, research-only 64KiB contiguous vs geometry-midpoint
# 2 x 32KiB sparse trial. Never production, never uses the scorer oracle.
function Assert-CSparse([bool]$Okay,[string]$Why) {
    if(-not $Okay){ throw ('C_SPARSE_WINDOW_FAIL: '+$Why) }
}
if(-not ('ChappyCSparseReadMeter' -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class ChappyCSparseReadMeter : Stream {
    private readonly Stream source;
    private readonly HashSet<long> seen = new HashSet<long>();
    public long BytesRead { get; private set; }
    public long ReadCalls { get; private set; }
    public long UniqueBytes { get {return seen.Count;} }
    public ChappyCSparseReadMeter(Stream s){
        if(s==null||!s.CanRead||!s.CanSeek||s.CanWrite)throw new ArgumentException("Read-only synthetic stream required");
        source=s;
    }
    public override bool CanRead {get{return true;}}
    public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}}
    public override long Length {get{return source.Length;}}
    public override long Position {get{return source.Position;}set{source.Position=value;}}
    public override int Read(byte[] b,int o,int n){
        long start=source.Position;
        int got=source.Read(b,o,n);
        ReadCalls++;
        BytesRead+=got;
        for(int i=0;i<got;i++)seen.Add(start+i);
        return got;
    }
    public override long Seek(long p,SeekOrigin o){return source.Seek(p,o);}
    public override void Flush(){}
    public override void SetLength(long n){throw new NotSupportedException();}
    public override void Write(byte[] a,int b,int c){throw new NotSupportedException();}
    protected override void Dispose(bool d){if(d)source.Dispose();base.Dispose(d);}
}
'@
}
# Does not re-parse BPB or establish a trusted provenance source. The caller
# must invoke independently reviewed B geometry on the SAME image first.
function Invoke-CSparseDataWindowTrial {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][IO.Stream]$Stream,[psobject]$Geometry=$null,
        [switch]$EnableSparseWindows,[ValidateRange(1,98304)][long]$MaxSourceBytes=98304)
    $unknown=[pscustomobject]@{
        status='unknown';reason='sparse.unavailable';originalIdentity='unknown'
        starts=@();items=@();metrics=[pscustomobject]@{
            sourceBytesRead=0L;readCalls=0;probes=0;candidateCount=0;elapsedMilliseconds=0
            uniqueSourceBytes=0L;windowBytes=0L;scannedBytes=0L
        }
    }
    if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite){
        $unknown.reason='sparse.not_readonly';return $unknown
    }
    if($MaxSourceBytes -lt 98304) {
        $unknown.reason='sparse.quota_unavailable';return $unknown
    }
    if($null -eq $Geometry) {$unknown.reason='sparse.geometry_unknown';return $unknown}
    try{
        [long]$start=[long]$Geometry.dataOffsetBytes
        [long]$first=[long]$Geometry.partitionOffsetBytes
        [long]$end=[long]$Geometry.partitionEndBytes
        [long]$bps=[long]$Geometry.bytesPerSector
        [long]$spc=[long]$Geometry.sectorsPerCluster
        [long]$clusterBytes=[long]$Geometry.clusterSizeBytes
        [long]$clusters=[long]$Geometry.clusterCount
        [long]$fats=[long]$Geometry.fatCount
        [long]$fatSectors=[long]$Geometry.fatSizeSectors
        $valid=($bps -in @(512L,1024L,2048L,4096L) -and
            $spc -ge 1L -and $spc -le 128L -and (($spc -band ($spc-1L)) -eq 0) -and
            $clusterBytes -eq $bps*$spc -and $clusters -ge 65525L -and
            $clusters -le 1000000L -and $fats -ge 1L -and $fats -le 2L -and
            $fatSectors -gt 0L -and $first -ge 0L -and
            $end -le $Stream.Length -and $end -gt $first -and
            $start -gt 65536L -and
            $start -gt ($first+$fats*$fatSectors*$bps) -and
            $start -le ($end-65536L) -and
            (($start-$first)%$bps) -eq 0 -and
            ($end-$start) -ge ($clusters*$clusterBytes) -and
            ($end-$start) -lt (($clusters+1L)*$clusterBytes))
    }catch{$valid=$false}
    if(-not $valid){$unknown.reason='sparse.geometry_conflict';return $unknown}
    $starts=@([long]$start)
    $width=65536L
    $extra=32768L
    if($EnableSparseWindows){
        $width=32768L;$extra=16384L
        # Pure fixed geometry rule: half the cluster range, never content,
        # FAT entries, caller case label, file offsets or original SHA.
        $mid=$start+[long][Math]::Floor($clusters/2.0)*$clusterBytes
        if($mid -le ($start+32768L) -or $mid -gt ($end-32768L)){
            $unknown.reason='sparse.schedule_invalid';return $unknown
        }
        $starts=@([long]$start,[long]$mid)
    }
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $items=New-Object 'System.Collections.Generic.List[object]'
    $sourceRead=0L;$calls=0;$probes=0;$covered=0L
    $failure=$null
    foreach($at in $starts){
        $remaining=30000-[int]$clock.ElapsedMilliseconds
        if($remaining -lt 100){$failure='sparse.time_exhausted';break}
        if($probes -ge 16 -or $items.Count -ge 16){$failure='sparse.probe_or_candidate_exhausted';break}
        $left=16-$probes
        $maxCandidates=16-$items.Count
        $scan=Get-ChappyCarvingCandidates -Stream $Stream -StartOffset $at -MaxScanBytes $width -ExtraValidationReadBytes $extra -MaxFileBytes 4096 -MaxCandidates $maxCandidates -MaxProbes $left -MaxProbeBytes 8192 -MaxWorkMilliseconds $remaining
        $sourceRead += [long]$scan.metrics.bytesRead
        $calls += [int]$scan.metrics.readRequests
        $probes += [int]$scan.metrics.entriesChecked
        $covered += [long]$scan.metrics.scannedBytes
        if($scan.status -eq 'error' -or $scan.metrics.scannedBytes -lt $width -or
            @($scan.warnings|Where-Object {$_ -in @('scan.read_budget_exhausted','scan.probe_budget_exhausted','scan.time_budget_exhausted')}).Count -gt 0) {
            $failure='sparse.scan_truncated_or_exhausted';break
        }
        foreach($candidate in @($scan.items)){
            if($null -eq $candidate.PSObject.Properties['integrityScope'] -or
                $candidate.integrityScope -ceq 'original_file_integrity'){
                $failure='sparse.untrusted_original_claim';break
            }
            $items.Add($candidate)
        }
        if($null -ne $failure){break}
    }
    $clock.Stop()
    if($sourceRead -gt 98304L -or $sourceRead -gt $MaxSourceBytes -or $probes -gt 16 -or
        $items.Count -gt 16 -or $clock.ElapsedMilliseconds -gt 30000){
        throw 'C sparse read/probe/candidate/time cap violated'
    }
    if($null -ne $failure){
        # Refuse cherry-picking a hit before an unobserved second window.
        $items.Clear()
    }
    return [pscustomobject]@{
        status=$(if($null -ne $failure){'unknown'}else{'partial'})
        reason=$(if($null -ne $failure){$failure}else{'sparse.unscanned_regions_unknown'})
        originalIdentity='unknown';starts=@($starts);items=@($items.ToArray())
        metrics=[pscustomobject]@{
            sourceBytesRead=$sourceRead;readCalls=$calls;probes=$probes
            candidateCount=$items.Count;elapsedMilliseconds=[int]$clock.ElapsedMilliseconds
            uniqueSourceBytes=0L;windowBytes=($width*$starts.Count);scannedBytes=$covered
        }
    }
}
# INDEPENDENT TEST-SCORER ONLY. Never called by candidate method.
# Update both FAT copies and directory entry after byte-preserving relocation.
function New-CSparseArtificialRelocation {
    param([int]$Seed,[int]$Spc)
    $fixture=New-ChappyA3DStandardFixture -Seed $Seed -SectorsPerCluster $Spc -Fragment3Mf:($Spc -eq 1)
    [byte[]]$img=$fixture.image
    $clusterBytes=512*$Spc
    $clusters=65541
    $fatSectors=[int][Math]::Ceiling((($clusters+2)*4)/512.0)
    $fat1=(1+32)*512
    $fat2=$fat1+$fatSectors*512
    $data=$fat2+$fatSectors*512
    $quarter=[int][Math]::Floor($clusters/4.0)+2
    $middle=[int][Math]::Floor($clusters/2.0)+2
    $threeQuarter=[int][Math]::Floor($clusters*3.0/4.0)+2
    $truth=New-Object 'System.Collections.Generic.List[object]'
    foreach($file in @($fixture.oracle)){
        $index=$(if($file.shortName -eq 'PRINT   GCO'){0}elseif($file.shortName -eq 'MODEL   3MF'){1}else{2})
        $destination=-1;$split=$false
        if($index -eq 1) {
            if($Seed -eq 202611){$destination=$middle}
            elseif($Seed -eq 202612){$destination=$quarter}
            else{$destination=$middle;$split=$true}
        }
        if($index -eq 0){
            if($Seed -eq 202612){$destination=$middle+16}
            elseif($Seed -eq 202613){$destination=$threeQuarter}
        }
        if($destination -lt 2){$truth.Add($file);continue}
        [byte[]]$content=[byte[]]::new([int]$file.lengthBytes)
        $written=0
        foreach($part in @($file.extents)){
            [Array]::Copy($img,[int]$part.offsetBytes,$content,$written,[int]$part.lengthBytes)
            $written += [int]$part.lengthBytes
        }
        Assert-CSparse ($written -eq $content.Length -and
            (Get-A3DSha256 $content) -ceq $file.sha256) 'test scorer artificial content matches generator'
        # Free old allocated clusters, including the fragmented 3MF second cluster.
        foreach($part in @($file.extents)){
            [Array]::Clear($img,[int]$part.offsetBytes,[int]$part.lengthBytes)
            Set-A3DUint32 $img ($fat1+4*[int]$part.cluster) 0
            Set-A3DUint32 $img ($fat2+4*[int]$part.cluster) 0
        }
        $needed=[int][Math]::Ceiling($content.Length/[double]$clusterBytes)
        Assert-CSparse ($needed -ge 1 -and $needed -le 2) 'test relocation max two clusters'
        $newChain=New-Object 'System.Collections.Generic.List[int]'
        $newChain.Add($destination)
        if($needed -eq 2){$newChain.Add($(if($split){$quarter+16}else{$destination+1}))}
        $newExtents=New-Object 'System.Collections.Generic.List[object]'
        for($i=0;$i -lt $newChain.Count;$i++){
            $c=[int]$newChain[$i]
            Assert-CSparse ($c -gt 10 -and $c -le ($clusters+1)) 'scorer reserved remote cluster'
            $next=$(if($i+1 -lt $newChain.Count){[uint32]$newChain[$i+1]}else{[uint32]0x0FFFFFFF})
            Set-A3DUint32 $img ($fat1+4*$c) $next
            Set-A3DUint32 $img ($fat2+4*$c) $next
            $offset=$data+($c-2)*$clusterBytes
            $length=[int][Math]::Min($clusterBytes,$content.Length-$i*$clusterBytes)
            [Array]::Copy($content,($i*$clusterBytes),$img,$offset,$length)
            $newExtents.Add([pscustomobject]@{cluster=$c;offsetBytes=$offset;lengthBytes=$length})
        }
        $record=$data+$index*32
        Set-A3DUint16 $img ($record+26) ([uint16]$destination)
        Set-A3DUint16 $img ($record+20) ([uint16]0)
        $truth.Add([pscustomobject]@{shortName=$file.shortName;lengthBytes=$file.lengthBytes;sha256=$file.sha256;extents=@($newExtents.ToArray())})
    }
    # FAT signature decoy (outside data area) plus extra PK in unused root slack
    # (metadata-shaped false positive: intentionally not an authenticated file).
    $fatDecoy=$fat1+4096
    [Array]::Copy([byte[]]@(0x50,0x4b,0x03,0x04),0,$img,$fatDecoy,4)
    $rootDecoy=$data+4096
    [Array]::Copy([byte[]]@(0x50,0x4b,0x03,0x04),0,$img,$rootDecoy,4)
    return [pscustomobject]@{image=$img;oracle=@($truth.ToArray());seed=$Seed;spc=$Spc;fatDecoyAt=$fatDecoy;rootDecoyAt=$rootDecoy}
}
# External truth matching; matching a header is NOT an original-file SHA match.
function Get-CSparseSyntheticScore {
    param([byte[]]$Image,[object[]]$Truth,[object[]]$Items,[long]$FatDecoyAt,[long]$RootDecoyAt)
    $headerHits=0;$exact=0;$falseObservations=0;$wrongOriginalClaims=0;$midHits=0
    foreach($item in $Items){
        if($item.integrityScope -ceq 'original_file_integrity' -or $null -ne $item.PSObject.Properties['sourceToken']){$wrongOriginalClaims++}
        $matches=@($Truth|Where-Object {$_.extents[0].offsetBytes -eq $item.offsetBytes})
        if($matches.Count -gt 0){
            $headerHits++
            $one=$matches[0]
            if($item.lengthBytes -eq $one.lengthBytes -and $item.lengthBytes -gt 0){
                [byte[]]$bytes=[byte[]]::new([int]$item.lengthBytes)
                [Array]::Copy($Image,[int]$item.offsetBytes,$bytes,0,$bytes.Length)
                if((Get-A3DSha256 $bytes) -ceq $one.sha256){$exact++}
            }
        }else{$falseObservations++}
    }
    return [pscustomobject]@{
        trueHeader=$headerHits;exact=$exact;falseObservations=$falseObservations
        wrongOriginalClaims=$wrongOriginalClaims;fatDecoyAccepted=@($Items|Where-Object {$_.offsetBytes -eq $FatDecoyAt}).Count
        rootDecoySeen=@($Items|Where-Object {$_.offsetBytes -eq $RootDecoyAt}).Count
    }
}
function Invoke-CSparseWindowRegression {
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
    . (Join-Path $root 'modules\directory\DirectoryScanner.ps1')
    $cases=0;$baseHits=0;$sparseHits=0;$baseExact=0;$sparseExact=0
    $baseFalse=0;$sparseFalse=0;$baseBytes=0L;$sparseBytes=0L
    $baseUnique=0L;$sparseUnique=0L;$baseReads=0L;$sparseReads=0L
    foreach($seed in @(202611,202612,202613)){
        foreach($spc in @(1,2)){
            $fixture=New-CSparseArtificialRelocation -Seed $seed -Spc $spc
            [byte[]]$img=$fixture.image
            $before=Get-A3DSha256 $img
            $g=[IO.MemoryStream]::new($img,$false)
            try{$geo=Get-ChappyFat32Geometry -Stream $g}
            finally{$g.Dispose()}
            Assert-CSparse ($geo.clusterCount -eq 65541 -and $geo.sectorsPerCluster -eq $spc) 'independent standard BPB geometry'
            $a=[ChappyCSparseReadMeter]::new([IO.MemoryStream]::new($img,$false))
            $b=[ChappyCSparseReadMeter]::new([IO.MemoryStream]::new($img,$false))
            try{
                $old=Invoke-CSparseDataWindowTrial -Stream $a -Geometry $geo
                $new=Invoke-CSparseDataWindowTrial -Stream $b -Geometry $geo -EnableSparseWindows
                Assert-CSparse ($old.status -eq 'partial' -and $new.status -eq 'partial' -and
                    $old.originalIdentity -eq 'unknown' -and $new.originalIdentity -eq 'unknown' -and
                    $old.starts.Count -eq 1 -and $new.starts.Count -eq 2 -and
                    $new.starts[0] -eq $old.starts[0] -and
                    $new.starts[1] -eq ($geo.dataOffsetBytes+[long][Math]::Floor($geo.clusterCount/2.0)*$geo.clusterSizeBytes)) 'same geometry, no oracle in schedule'
                Assert-CSparse ($a.BytesRead -eq $old.metrics.sourceBytesRead -and
                    $b.BytesRead -eq $new.metrics.sourceBytesRead -and
                    $a.BytesRead -le 98304 -and $b.BytesRead -le 98304 -and
                    $old.metrics.probes -le 16 -and $new.metrics.probes -le 16 -and
                    @($old.items).Count -le 16 -and @($new.items).Count -le 16 -and
                    $a.UniqueBytes -le $a.BytesRead -and $b.UniqueBytes -le $b.BytesRead -and
                    -not $a.CanWrite -and -not $b.CanWrite) 'same total returned-byte and work ceilings'
                $scA=Get-CSparseSyntheticScore -Image $img -Truth @($fixture.oracle) -Items @($old.items) -FatDecoyAt $fixture.fatDecoyAt -RootDecoyAt $fixture.rootDecoyAt
                $scB=Get-CSparseSyntheticScore -Image $img -Truth @($fixture.oracle) -Items @($new.items) -FatDecoyAt $fixture.fatDecoyAt -RootDecoyAt $fixture.rootDecoyAt
                Assert-CSparse ($scA.wrongOriginalClaims -eq 0 -and $scB.wrongOriginalClaims -eq 0 -and
                    $scA.fatDecoyAccepted -eq 0 -and $scB.fatDecoyAccepted -eq 0) 'no original identity claim or FAT decoy use'
                $baseHits+=$scA.trueHeader;$sparseHits+=$scB.trueHeader
                $baseExact+=$scA.exact;$sparseExact+=$scB.exact
                $baseFalse+=$scA.falseObservations;$sparseFalse+=$scB.falseObservations
                $baseBytes+=$a.BytesRead;$sparseBytes+=$b.BytesRead
                $baseUnique+=$a.UniqueBytes;$sparseUnique+=$b.UniqueBytes
                $baseReads+=$a.ReadCalls;$sparseReads+=$b.ReadCalls
                $cases++
                Write-Host ('C SPARSE CASE seed={0} spc={1} old/new items={2}/{3} truth_headers={4}/{5} exact={6}/{7} false={8}/{9} returned={10}/{11} unique={12}/{13} calls={14}/{15} probes={16}/{17}' -f
                    $seed,$spc,@($old.items).Count,@($new.items).Count,$scA.trueHeader,$scB.trueHeader,$scA.exact,$scB.exact,$scA.falseObservations,$scB.falseObservations,$a.BytesRead,$b.BytesRead,$a.UniqueBytes,$b.UniqueBytes,$a.ReadCalls,$b.ReadCalls,$old.metrics.probes,$new.metrics.probes)
            }finally{$a.Dispose();$b.Dispose()}
            Assert-CSparse ((Get-A3DSha256 $img) -ceq $before) 'scorer synthetic source SHA unchanged'
            if($seed -eq 202611 -and $spc -eq 1){
                # Negative: true 17B then zero EOF; do not retain candidates
                # from first window while second is unobserved.
                $short=[ChappyCSparseReadMeter]::new([ChappyC17ThenEof]::new([IO.MemoryStream]::new($img,$false)))
                try{
                    $r=Invoke-CSparseDataWindowTrial -Stream $short -Geometry $geo -EnableSparseWindows
                    Assert-CSparse ($r.status -eq 'unknown' -and @($r.items).Count -eq 0 -and
                        $short.BytesRead -eq 17 -and $r.metrics.sourceBytesRead -eq 17) 'real returned 17 then EOF unknown'
                }finally{$short.Dispose()}
                $quota=[ChappyCSparseReadMeter]::new([IO.MemoryStream]::new($img,$false))
                try{$r=Invoke-CSparseDataWindowTrial -Stream $quota -Geometry $geo -EnableSparseWindows -MaxSourceBytes 1024
                    Assert-CSparse ($r.status -eq 'unknown' -and @($r.items).Count -eq 0 -and $quota.BytesRead -eq 0) 'quota unavailable pre-read'
                }finally{$quota.Dispose()}
                $forged=[pscustomobject]@{
                    dataOffsetBytes=($img.Length-17);partitionOffsetBytes=$geo.partitionOffsetBytes
                    partitionEndBytes=$geo.partitionEndBytes;bytesPerSector=$geo.bytesPerSector
                    sectorsPerCluster=$geo.sectorsPerCluster;clusterSizeBytes=$geo.clusterSizeBytes
                    clusterCount=$geo.clusterCount;fatCount=$geo.fatCount;fatSizeSectors=$geo.fatSizeSectors
                }
                $invalid=[ChappyCSparseReadMeter]::new([IO.MemoryStream]::new($img,$false))
                try{$r=Invoke-CSparseDataWindowTrial -Stream $invalid -Geometry $forged -EnableSparseWindows
                    Assert-CSparse ($r.status -eq 'unknown' -and $invalid.BytesRead -eq 0) 'forged geometry unknown pre-read'
                }finally{$invalid.Dispose()}
                # Synthetic flood in root slack; capped probe budget must not
                # select an early candidate as original under later truncation.
                [byte[]]$flood=[byte[]]$img.Clone()
                for($i=0;$i -lt 24;$i++){
                    $at=[int]$geo.dataOffsetBytes+6144+$i*64
                    [Array]::Copy([byte[]]@(0x50,0x4b,0x03,0x04),0,$flood,$at,4)
                }
                $floodSha=Get-A3DSha256 $flood
                $fs=[ChappyCSparseReadMeter]::new([IO.MemoryStream]::new($flood,$false))
                try{
                    $r=Invoke-CSparseDataWindowTrial -Stream $fs -Geometry $geo -EnableSparseWindows
                    Assert-CSparse ($r.status -eq 'unknown' -and @($r.items).Count -eq 0 -and
                        $fs.BytesRead -le 98304 -and $r.metrics.probes -le 16) 'adversarial signature flood fail closed'
                }finally{$fs.Dispose()}
                Assert-CSparse ((Get-A3DSha256 $flood) -ceq $floodSha) 'synthetic flood hash unchanged'
            }
            $img=$null;$fixture=$null;[GC]::Collect()
        }
    }
    Assert-CSparse ($cases -eq 6 -and $baseBytes -gt 0 -and $sparseBytes -gt 0 -and
        $baseUnique -le $baseBytes -and $sparseUnique -le $sparseBytes) 'registered six case matrix'
    Write-Host ('C SPARSE SUMMARY cases={0} header_hits={1}/{2} scorer_exact_sha={3}/{4} nontruth_observations={5}/{6} physical_bytes={7}/{8} unique_bytes={9}/{10} reads={11}/{12} original_claims=0' -f
        $cases,$baseHits,$sparseHits,$baseExact,$sparseExact,$baseFalse,$sparseFalse,$baseBytes,$sparseBytes,$baseUnique,$sparseUnique,$baseReads,$sparseReads)
    Write-Host 'PASS: Team C sparse data-window A/B research synthetic-only; no authentic original or real media claims'
}
