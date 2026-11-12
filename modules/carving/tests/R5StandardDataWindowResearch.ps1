#Requires -Version 5.1
# C #72 research/test-only, default OFF. No production interface, export, oracle input or receipts.
function Invoke-CStandardDataTrial {
    param([IO.Stream]$Stream,[psobject]$Geometry=$null,[switch]$EnableDataWindow,
        [ValidateRange(1,98304)][long]$MaxSourceBytes=98304)
    $unknown=[pscustomobject]@{status='unknown';reason='window.not_validated';originalIdentity='unknown';start=$null;items=@();metrics=[pscustomobject]@{sourceBytesRead=0L;readRequests=0;probes=0;elapsedMilliseconds=0}}
    if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite){$unknown.reason='window.not_readonly';return $unknown}
    if($MaxSourceBytes -lt 98304){$unknown.reason='window.quota_unavailable';return $unknown}
    $start=0L
    if($EnableDataWindow){
        if($null -eq $Geometry){$unknown.reason='window.geometry_unknown';return $unknown}
        try {
            [long]$start=$Geometry.dataOffsetBytes
            [long]$first=$Geometry.partitionOffsetBytes
            [long]$end=$Geometry.partitionEndBytes
            [long]$bps=$Geometry.bytesPerSector
            [long]$spc=$Geometry.sectorsPerCluster
            [long]$size=$Geometry.clusterSizeBytes
            [long]$count=$Geometry.clusterCount
            [long]$fats=$Geometry.fatCount
            [long]$fatSectors=$Geometry.fatSizeSectors
            $valid=($bps -in @(512L,1024L,2048L,4096L) -and $spc -ge 1 -and $spc -le 128 -and
                (($spc -band ($spc-1L)) -eq 0) -and $size -eq $bps*$spc -and
                $count -ge 65525L -and $count -le 1000000L -and $fats -ge 1 -and $fats -le 2 -and
                $fatSectors -gt 0 -and $first -ge 0 -and $end -le $Stream.Length -and
                $start -gt ($first+$fats*$fatSectors*$bps) -and
                $start -gt 65536L -and $start -le ($end-65536L) -and
                (($start-$first)%$bps) -eq 0 -and
                ($end-$start) -ge $count*$size -and ($end-$start) -lt ($count+1L)*$size)
        } catch {$valid=$false}
        if(-not $valid){$unknown.reason='window.geometry_conflict';return $unknown}
    }
    if($start -gt ($Stream.Length-65536L)){$unknown.reason='window.short_source';return $unknown}
    # Identical C settings/caps for both arms, only StartOffset changes.
    $scan=Get-ChappyCarvingCandidates -Stream $Stream -StartOffset $start -MaxScanBytes 65536 -ExtraValidationReadBytes 32768 -MaxFileBytes 4096 -MaxCandidates 16 -MaxProbes 16 -MaxProbeBytes 8192 -MaxWorkMilliseconds 30000
    if($scan.status -eq 'error'){$unknown.reason='window.carver_error';return $unknown}
    if([long]$scan.metrics.bytesRead -gt $MaxSourceBytes){throw 'C source quota exceeded'}
    return [pscustomobject]@{
        status=$(if($scan.scanIncomplete){'partial'}else{'observed'})
        reason=$(if($scan.scanIncomplete){'window.incomplete'}else{'window.observed'})
        originalIdentity='unknown';start=$start;items=@($scan.items)
        metrics=[pscustomobject]@{sourceBytesRead=[long]$scan.metrics.bytesRead;readRequests=[int]$scan.metrics.readRequests;probes=[int]$scan.metrics.entriesChecked;elapsedMilliseconds=[int]$scan.metrics.elapsedMilliseconds}
    }
}
function Assert-CStandardTrial([bool]$Okay,[string]$Message){if(-not $Okay){throw ('C_STANDARD_DATA_WINDOW_FAIL: '+$Message)}}

# Synthetic-only fake stream returns 17 physical bytes and then genuine zero EOF.
if(-not ('ChappyC17ThenEof' -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class ChappyC17ThenEof : Stream {
    private Stream s; private bool served; public long Returned {get;private set;}
    public ChappyC17ThenEof(Stream input) { if(input.CanWrite)throw new ArgumentException(); s=input; }
    public override bool CanRead {get{return true;}} public override bool CanSeek {get{return true;}}
    public override bool CanWrite {get{return false;}} public override long Length {get{return s.Length;}}
    public override long Position {get{return s.Position;}set{s.Position=value;}}
    public override int Read(byte[] b,int o,int n){if(served)return 0;served=true;int got=s.Read(b,o,Math.Min(17,n));Returned+=got;return got;}
    public override long Seek(long a,SeekOrigin o){return s.Seek(a,o);}
    public override void Flush(){} public override void SetLength(long x){throw new NotSupportedException();}
    public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
    protected override void Dispose(bool d){if(d)s.Dispose();base.Dispose(d);}
}
'@
}
function Invoke-CStandardDataWindowRegression {
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
    . (Join-Path $root 'modules\directory\DirectoryScanner.ps1')
    $baseTotal=0;$newTotal=0;$baseBytes=0L;$newBytes=0L;$baseRequests=0;$newRequests=0;$exactBase=0;$exactNew=0
    foreach($spc in @(1,2)){
        $fixture=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
        [byte[]]$img=$fixture.image
        $before=Get-A3DSha256 $img
        $geoStream=[IO.MemoryStream]::new($img,$false)
        try{$geo=Get-ChappyFat32Geometry -Stream $geoStream}finally{$geoStream.Dispose()}
        Assert-CStandardTrial ($geo.clusterCount -eq 65541 -and $geo.dataOffsetBytes -gt 65536) 'independent B geometry'
        $sourceA=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($img,$false))
        $sourceB=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($img,$false))
        try{
            $a=Invoke-CStandardDataTrial -Stream $sourceA -Geometry $geo
            $b=Invoke-CStandardDataTrial -Stream $sourceB -Geometry $geo -EnableDataWindow
            Assert-CStandardTrial ($a.start -eq 0 -and $b.start -eq $geo.dataOffsetBytes -and
                $a.originalIdentity -eq 'unknown' -and $b.originalIdentity -eq 'unknown') 'no oracle-derived start or original identity'
            Assert-CStandardTrial ($a.metrics.sourceBytesRead -eq $sourceA.BytesRead -and
                $b.metrics.sourceBytesRead -eq $sourceB.BytesRead -and
                $a.metrics.sourceBytesRead -le 98304 -and $b.metrics.sourceBytesRead -le 98304 -and
                $a.metrics.probes -le 16 -and $b.metrics.probes -le 16 -and
                -not $sourceA.CanWrite -and -not $sourceB.CanWrite) 'actual physical C cap'
            $nA=@($a.items).Count;$nB=@($b.items).Count
            Assert-CStandardTrial ($nA -eq 0 -and $nB -gt 0) 'bounded data scan discovers synthetic file-shaped bytes'
            # External-only scorer: known SHA and physical extents NEVER passed to candidate search.
            $truth=@($fixture.oracle|Where-Object {$_.format -eq '3mf'})[0]
            foreach($arm in @('a','b')){
                $result=if($arm -eq 'a'){$a}else{$b}
                foreach($c in @($result.items)){
                    Assert-CStandardTrial ($c.integrityScope -cne 'original_file_integrity' -and
                        $null -eq $c.PSObject.Properties['sourceToken']) 'no false original claim or minted A receipt'
                    if($c.format -eq '3mf' -and $c.lengthBytes -eq $truth.lengthBytes -and
                        $c.offsetBytes -eq $truth.extents[0].offsetBytes){
                        [byte[]]$blob=[byte[]]::new([int]$c.lengthBytes)
                        [Array]::Copy($img,[int]$c.offsetBytes,$blob,0,$blob.Length)
                        if((Get-A3DSha256 $blob) -ceq $truth.sha256){
                            if($arm -eq 'a'){$exactBase++}else{$exactNew++}
                        }
                    }
                }
            }
            $baseTotal+=$nA;$newTotal+=$nB
            $baseBytes+=[long]$a.metrics.sourceBytesRead;$newBytes+=[long]$b.metrics.sourceBytesRead
            $baseRequests+=[int]$a.metrics.readRequests;$newRequests+=[int]$b.metrics.readRequests
            Write-Host ('C R5 WINDOW spc={0} start={1} candidates={2}/{3} sourceB={4}/{5} calls={6}/{7} status={8}/{9}' -f
                $spc,$geo.dataOffsetBytes,$nA,$nB,$a.metrics.sourceBytesRead,$b.metrics.sourceBytesRead,
                $a.metrics.readRequests,$b.metrics.readRequests,$a.status,$b.status)
        }finally{$sourceA.Dispose();$sourceB.Dispose()}
        Assert-CStandardTrial ((Get-A3DSha256 $img) -ceq $before) 'source SHA unchanged'
        if($spc -eq 1){
            [byte[]]$fake=[byte[]]$img.Clone()
            $fakeAt=[int]($geo.partitionOffsetBytes+(32+8)*$geo.bytesPerSector)
            [Array]::Copy([byte[]]@(0x50,0x4b,0x03,0x04),0,$fake,$fakeAt,4)
            $fakeBefore=Get-A3DSha256 $fake
            $f=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($fake,$false))
            try{$fg=Get-ChappyFat32Geometry -Stream $f;$prior=$f.BytesRead
                $out=Invoke-CStandardDataTrial -Stream $f -Geometry $fg -EnableDataWindow
                Assert-CStandardTrial ($out.start -gt $fakeAt -and
                    @($out.items|Where-Object {$_.offsetBytes -eq $fakeAt}).Count -eq 0 -and
                    $f.BytesRead-$prior -eq $out.metrics.sourceBytesRead) 'FAT false ZIP cannot become data-region candidate'
            }finally{$f.Dispose()}
            Assert-CStandardTrial ((Get-A3DSha256 $fake) -ceq $fakeBefore) 'FAT spoof source unchanged'
            [byte[]]$bad=[byte[]]$img.Clone();$bad[[int]($geo.partitionOffsetBytes+11)]=0
            $badInput=[IO.MemoryStream]::new($bad,$false);$badGeo=$null
            try{try{$badGeo=Get-ChappyFat32Geometry -Stream $badInput}catch{$badGeo=$null}}
            finally{$badInput.Dispose()}
            $u=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($bad,$false))
            try{$out=Invoke-CStandardDataTrial -Stream $u -Geometry $badGeo -EnableDataWindow
                Assert-CStandardTrial ($out.status -eq 'unknown' -and $u.BytesRead -eq 0) 'corrupt BPB UNKNOWN before C I/O'
            }finally{$u.Dispose()}
            $forged=[pscustomobject]@{
                dataOffsetBytes=($img.Length-17);partitionOffsetBytes=$geo.partitionOffsetBytes
                partitionEndBytes=$geo.partitionEndBytes;bytesPerSector=$geo.bytesPerSector
                sectorsPerCluster=$geo.sectorsPerCluster;clusterSizeBytes=$geo.clusterSizeBytes
                clusterCount=$geo.clusterCount;fatCount=$geo.fatCount;fatSizeSectors=$geo.fatSizeSectors
            }
            $u=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($img,$false))
            try{$out=Invoke-CStandardDataTrial -Stream $u -Geometry $forged -EnableDataWindow
                Assert-CStandardTrial ($out.status -eq 'unknown' -and $u.BytesRead -eq 0) 'out-of-source geometry UNKNOWN'
            }finally{$u.Dispose()}
            $short=[ChappyC17ThenEof]::new([IO.MemoryStream]::new($img,$false))
            try{$out=Invoke-CStandardDataTrial -Stream $short -Geometry $geo -EnableDataWindow
                Assert-CStandardTrial ($out.status -eq 'partial' -and $short.Returned -eq 17 -and
                    $out.metrics.sourceBytesRead -eq 17 -and @($out.items).Count -eq 0) '17 physical bytes and EOF partial'
            }finally{$short.Dispose()}
            $u=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($img,$false))
            try{$out=Invoke-CStandardDataTrial -Stream $u -Geometry $geo -EnableDataWindow -MaxSourceBytes 1024
                Assert-CStandardTrial ($out.status -eq 'unknown' -and $u.BytesRead -eq 0) 'quota shortfall UNKNOWN before reads'
            }finally{$u.Dispose()}
        }
        $fixture=$null;$img=$null;[GC]::Collect()
    }
    Assert-CStandardTrial ($baseTotal -eq 0 -and $newTotal -gt 0 -and $exactBase -eq 0) '2-case preregistered baseline gap'
    Write-Host ('C R5 WINDOW SUMMARY cases=2 base/newCandidates={0}/{1} 3MF_exact_SHA_scorer={2}/{3} sourceB={4}/{5} requests={6}/{7} false_original_claims=0' -f
        $baseTotal,$newTotal,$exactBase,$exactNew,$baseBytes,$newBytes,$baseRequests,$newRequests)
    Write-Host 'PASS: C bounded data-region experiment and artificial negatives only'
}
