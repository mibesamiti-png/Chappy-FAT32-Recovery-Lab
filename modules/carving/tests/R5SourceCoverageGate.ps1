#requires -Version 5.1
# Team C C5-05: generated-only coverage truth independently meters the
# exported C coverage adapter. No original media, no A receipts, no export.
function Assert-C5Coverage([bool]$Good,[string]$Why){
    if(-not $Good){throw ('C5_05_COVERAGE_FAIL: '+$Why)}
}
if(-not ('ChappyC5OneByteSource' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class ChappyC5OneByteSource : Stream {
 private readonly Stream s;
 public ChappyC5OneByteSource(Stream x) {
   if(x==null||!x.CanRead||!x.CanSeek||x.CanWrite)throw new ArgumentException("read only");
   s=x;
 }
 public override bool CanRead {get{return true;}}
 public override bool CanSeek {get{return true;}}
 public override bool CanWrite {get{return false;}}
 public override long Length {get{return s.Length;}}
 public override long Position {get{return s.Position;}set{s.Position=value;}}
 public override int Read(byte[] b,int o,int n){return s.Read(b,o,Math.Min(1,n));}
 public override long Seek(long n,SeekOrigin o){return s.Seek(n,o);}
 public override void Flush(){}
 public override void SetLength(long n){throw new NotSupportedException();}
 public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
 protected override void Dispose(bool x){if(x)s.Dispose();base.Dispose(x);}
}
'@
}
function Get-C5ExternalJoinedShaComparison {
    param([byte[]]$Image,[object[]]$Reported,[string]$TrueSha)
    $exact=0;$wrong=0
    foreach($item in $Reported) {
        Assert-C5Coverage ($item.originalIdentity -eq 'unknown' -and
            $item.integrityScope -eq 'structural_only_not_original_file_integrity' -and
            $item.confidence -eq 'probable' -and
            $null -eq $item.PSObject.Properties['sourceToken'] -and
            $null -eq $item.PSObject.Properties['evidenceId'] -and
            $null -eq $item.PSObject.Properties['candidateSha256']) 'only_structural_candidates_no_source_authority'
        $a=[long]$item.firstOffset;$b=[long]$item.secondOffset
        $la=[int]$item.firstBytes;$lb=[int]$item.secondBytes
        Assert-C5Coverage ($a -ge 0 -and $b -ge 0 -and $la -gt 0 -and $lb -gt 0 -and
            $a+$la -le $Image.Length -and $b+$lb -le $Image.Length -and
            ($a -ge $b+$lb -or $b -ge $a+$la) -and $la+$lb -le 1056) 'reported_physical_extent_range'
        [byte[]]$joined=[byte[]]::new($la+$lb)
        [Array]::Copy($Image,[int]$a,$joined,0,$la)
        [Array]::Copy($Image,[int]$b,$joined,$la,$lb)
        if((Get-A3DSha256 $joined) -ceq $TrueSha){$exact++}else{$wrong++}
    }
    return [pscustomobject]@{exact=$exact;wrong=$wrong}
}
function Invoke-C5CoverageGate {
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $root 'modules\carving\Chappy.CoverageEvidence.psm1') -Force
    . (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
    . (Join-Path $root 'modules\directory\DirectoryScanner.ps1')
    $clean=New-ChappyA3DCleanFixture -Seed 202611
    $originalTruth=@($clean.oracle|Where-Object {$_.shortName -ceq 'MODEL   3MF'})[0]
    [byte[]]$original=[byte[]]::new([int]$originalTruth.lengthBytes)
    $written=0
    foreach($span in $originalTruth.extents){
        [Array]::Copy($clean.image,[int]$span.offsetBytes,$original,$written,[int]$span.lengthBytes)
        $written+=[int]$span.lengthBytes
    }
    Assert-C5Coverage ($written -eq $original.Length -and
        (Get-A3DSha256 $original) -ceq $originalTruth.sha256) 'generated_original_source_hash'
    $sumActual=0L;$sumUnique=0L;$sumCalls=0;$sumRepeat=0L;$cases=0
    foreach($kind in @('M01_control','alternate_zip_metadata','missing_tail')){
        $fx=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind $kind
        [byte[]]$image=$fx.image
        $imageBefore=Get-A3DSha256 $image
        $outer=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($image,$false))
        try{
            # Disabled is really zero source observation, not a fake 0-cost
            # answer inferred from the case label.
            $disabled=Get-ChappyCarvingCoverageEvidence -Source $outer
            Assert-C5Coverage ($disabled.status -eq 'disabled' -and
                $disabled.metrics.actualReturnedBytes -eq 0 -and
                $outer.ReadCalls -eq 0 -and $outer.BytesRead -eq 0 -and
                $outer.Position -eq 0) ($kind+':disabled_has_no_source_access')
            $r=Get-ChappyCarvingCoverageEvidence -Source $outer -EnableCoverageEvidence -Mode Fragment
            $m=$r.metrics
            Assert-C5Coverage ($r.schemaVersion -eq 'c5_source_coverage_v1' -and
                $r.status -eq 'partial' -and $r.scanIncomplete -and
                $r.sourceReadAttestation -eq 'C_unattested_A_outer_receipt_required' -and
                $r.originalIdentity -eq 'unknown' -and
                $null -eq $r.selectedOriginal -and -not $r.canAutoSelectOriginal -and
                $m.actualReturnedBytes -eq $outer.BytesRead -and
                $m.uniqueReturnedBytes -eq $outer.UniqueBytes -and
                $m.repeatedReturnedBytes -eq ($outer.BytesRead-$outer.UniqueBytes) -and
                $m.readCalls -eq $outer.ReadCalls -and $m.readCalls -le 4096 -and
                $m.successfulReadCalls -le $m.readCalls -and
                $m.observedReadIntervals -eq $m.successfulReadCalls -and
                $m.actualReturnedBytes -le 81920 -and $m.uniqueReturnedBytes -le $m.actualReturnedBytes -and
                $m.sectorProbes -eq 128 -and $m.pairAttempts -le 16 -and
                $m.candidateCount -eq @($r.items).Count -and
                $m.validatorMemoryReadStatus -eq 'measured_in_memory_only' -and
                $m.validatorMemoryReadBytes -le 98304 -and
                $m.maxPairBufferBytes -eq 1056 -and $m.maxSectorScratchBytes -eq 512 -and
                $m.peakProcessMemoryStatus -eq 'not_measured' -and
                $null -eq $m.peakProcessMemoryBytes) ($kind+':outer_independent_interval_union_and_caps')
            $sumActual += $m.actualReturnedBytes;$sumUnique += $m.uniqueReturnedBytes
            $sumCalls += $m.readCalls;$sumRepeat += $m.repeatedReturnedBytes
            $cases++
            $score=Get-C5ExternalJoinedShaComparison -Image $image -Reported @($r.items) -TrueSha $originalTruth.sha256
            if($kind -eq 'M01_control'){
                Assert-C5Coverage ($r.decision -eq 'one_possible' -and @($r.items).Count -eq 1 -and
                    $score.exact -eq 1 -and $score.wrong -eq 0) 'one_valid_structural_not_autoselected'
            }elseif($kind -eq 'alternate_zip_metadata'){
                Assert-C5Coverage ($r.decision -eq 'ambiguous' -and @($r.items).Count -eq 2 -and
                    $score.exact -eq 1 -and $score.wrong -eq 1) 'same_CRC_wrong_original_stays_ambiguous'
            }else{
                Assert-C5Coverage ($r.decision -eq 'unknown' -and @($r.items).Count -eq 0 -and
                    $score.exact -eq 0) 'missing_tail_stays_unknown'
            }
            Write-Host ('C5-05 FRAGMENT case={0} decision={1} items={2} actualB={3} uniqueB={4} repeatedB={5} calls={6} zeroEOFCalls={7} pairs={8} parserB={9}' -f
                $kind,$r.decision,@($r.items).Count,$m.actualReturnedBytes,
                $m.uniqueReturnedBytes,$m.repeatedReturnedBytes,$m.readCalls,
                $m.zeroByteReadCalls,$m.pairAttempts,$m.validatorMemoryReadBytes)
        }finally{$outer.Dispose()}
        Assert-C5Coverage ((Get-A3DSha256 $image) -ceq $imageBefore) ($kind+':synthetic_source_unchanged')
        $image=$null;$fx=$null
    }
    Assert-C5Coverage ($cases -eq 3 -and $sumActual -gt $sumUnique -and
        $sumRepeat -eq $sumActual-$sumUnique -and $sumCalls -ge (3*128)) 'fragment_read_union_aggregate'
    # True physical short return = 17 B then 0 EOF. The inner and outer
    # independent counters must count both requests and only returned bytes.
    $small=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind 'M01_control'
    $short=[ChappyCFragmentMeter]::new([CArtificialShortValidationStream]::new([IO.MemoryStream]::new($small.image,$false),17))
    try{
        $q=Get-ChappyCarvingCoverageEvidence -Source $short -EnableCoverageEvidence -Mode Fragment
        Assert-C5Coverage ($q.status -eq 'partial' -and $q.decision -eq 'incomplete' -and
            @($q.items).Count -eq 0 -and $q.metrics.actualReturnedBytes -eq 17 -and
            $q.metrics.uniqueReturnedBytes -eq 17 -and $q.metrics.repeatedReturnedBytes -eq 0 -and
            $q.metrics.zeroByteReadCalls -eq 1 -and $q.metrics.readCalls -eq 2 -and
            $q.metrics.readCalls -eq $short.ReadCalls -and $short.BytesRead -eq 17) 'fragment_17B_then_real_zero_EOF'
    }finally{$short.Dispose()}
    $short1=[ChappyCFragmentMeter]::new([ChappyC5OneByteSource]::new([IO.MemoryStream]::new($small.image,$false)))
    try{
        $q=Get-ChappyCarvingCoverageEvidence -Source $short1 -EnableCoverageEvidence -Mode Fragment -MaxReadCalls 512
        Assert-C5Coverage ($q.status -eq 'partial' -and $q.decision -eq 'incomplete' -and
            @($q.items).Count -eq 0 -and $q.metrics.readCalls -le 513 -and
            $q.metrics.actualReturnedBytes -le 512 -and
            $short1.BytesRead -eq $q.metrics.actualReturnedBytes) 'fragment_many_microreads_must_fail_closed'
    }finally{$short1.Dispose()}
    $insufficient=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($small.image,$false))
    try{
        $q=Get-ChappyCarvingCoverageEvidence -Source $insufficient -EnableCoverageEvidence -Mode Fragment -MaxSourceBytes 1024
        Assert-C5Coverage ($q.status -eq 'partial' -and $q.decision -eq 'incomplete' -and
            $q.metrics.actualReturnedBytes -eq 0 -and $insufficient.BytesRead -eq 0 -and
            $insufficient.ReadCalls -eq 0) 'fragment_underquota_preflight_zero_reads'
    }finally{$insufficient.Dispose()}
    $writable=[IO.MemoryStream]::new($small.image,$true)
    try{
        $q=Get-ChappyCarvingCoverageEvidence -Source $writable -EnableCoverageEvidence -Mode Fragment
        Assert-C5Coverage ($q.status -eq 'partial' -and $q.decision -eq 'incomplete' -and
            $q.metrics.actualReturnedBytes -eq 0 -and $writable.Position -eq 0) 'writable_denied_zero_reads'
    }finally{$writable.Dispose()}
    $clean=$null;$original=$null;$small=$null;[GC]::Collect()

    $stdActual=0L;$stdUnique=0L;$stdCalls=0;$stdGeo=0L;$stdCases=0
    foreach($spc in @(1,2)){
        $fixture=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
        [byte[]]$image=$fixture.image
        $before=Get-A3DSha256 $image
        $g=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($image,$false))
        try{
            $geometry=Get-ChappyFat32Geometry -Stream $g
            Assert-C5Coverage ($geometry.dataOffsetBytes -gt 65536 -and
                $geometry.clusterCount -eq 65541) 'B_numeric_geometry_before_C'
            $stdGeo += $g.BytesRead
        }finally{$g.Dispose()}
        $outer=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($image,$false))
        try{
            $r=Get-ChappyCarvingCoverageEvidence -Source $outer -EnableCoverageEvidence -Mode Window -StartOffsetBytes ([long]$geometry.dataOffsetBytes)
            $m=$r.metrics
            Assert-C5Coverage ($r.status -eq 'partial' -and $r.decision -eq 'source_window_partial_coverage' -and
                $r.scanIncomplete -and $r.originalIdentity -eq 'unknown' -and -not $r.canAutoSelectOriginal -and
                $r.sourceReadAttestation -eq 'C_unattested_A_outer_receipt_required' -and
                $m.actualReturnedBytes -eq $outer.BytesRead -and
                $m.uniqueReturnedBytes -eq $outer.UniqueBytes -and
                $m.readCalls -eq $outer.ReadCalls -and
                $m.repeatedReturnedBytes -eq $m.actualReturnedBytes-$m.uniqueReturnedBytes -and
                $m.actualReturnedBytes -le 98304 -and $m.formatProbes -le 16 -and
                $m.candidateCount -le 16 -and $m.maxScannerChunkBytes -eq 16384 -and
                $m.validatorMemoryReadStatus -eq 'not_separately_instrumented' -and
                $null -eq $m.validatorMemoryReadBytes -and
                $m.peakProcessMemoryStatus -eq 'not_measured') ('standard_spc_'+$spc+':independent_outer_source_meter')
            foreach($item in @($r.items)){
                Assert-C5Coverage ($item.offsetBytes -ge $geometry.dataOffsetBytes -and
                    $item.originalIdentity -eq 'unknown' -and
                    $null -eq $item.PSObject.Properties['sourceToken']) 'standard_no_FAT_metadata_decoy_or_original'
            }
            $stdActual += $m.actualReturnedBytes;$stdUnique += $m.uniqueReturnedBytes
            $stdCalls += $m.readCalls;$stdCases++
            Write-Host ('C5-05 STANDARD spc={0} decision={1} candidates={2} sourceB={3} uniqueB={4} repeatedB={5} calls={6} formatProbes={7} BgeometrySeparateB={8}' -f
                $spc,$r.decision,$m.candidateCount,$m.actualReturnedBytes,$m.uniqueReturnedBytes,
                $m.repeatedReturnedBytes,$m.readCalls,$m.formatProbes,$stdGeo)
        }finally{$outer.Dispose()}
        Assert-C5Coverage ((Get-A3DSha256 $image) -ceq $before) ('standard_spc_'+$spc+':source_unmodified')
        $image=$null;$fixture=$null;[GC]::Collect()
    }
    Assert-C5Coverage ($stdCases -eq 2 -and $stdActual -gt $stdUnique -and $stdUnique -eq 131072 -and
        $stdCalls -gt 0 -and $stdGeo -gt 0) 'two_standard_read_union_and_geometry_separate'
    $fixture=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster 2
    [byte[]]$image=$fixture.image
    $g=[IO.MemoryStream]::new($image,$false)
    try{$geo=Get-ChappyFat32Geometry -Stream $g}finally{$g.Dispose()}
    $short=[ChappyCFragmentMeter]::new([ChappyC17ThenEof]::new([IO.MemoryStream]::new($image,$false)))
    try{
        $q=Get-ChappyCarvingCoverageEvidence -Source $short -EnableCoverageEvidence -Mode Window -StartOffsetBytes ([long]$geo.dataOffsetBytes)
        Assert-C5Coverage ($q.status -eq 'partial' -and $q.decision -eq 'incomplete' -and
            @($q.items).Count -eq 0 -and $q.metrics.actualReturnedBytes -eq 17 -and
            $q.metrics.uniqueReturnedBytes -eq 17 -and
            $q.metrics.zeroByteReadCalls -eq 1 -and
            $q.metrics.readCalls -eq $short.ReadCalls -and $short.BytesRead -eq 17) 'standard_17B_true_EOF'
    }finally{$short.Dispose()}
    $low=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($image,$false))
    try{
        $q=Get-ChappyCarvingCoverageEvidence -Source $low -EnableCoverageEvidence -Mode Window -StartOffsetBytes ([long]$geo.dataOffsetBytes) -MaxSourceBytes 1024
        Assert-C5Coverage ($q.status -eq 'partial' -and $q.metrics.actualReturnedBytes -eq 0 -and
            $low.BytesRead -eq 0 -and $low.ReadCalls -eq 0 -and @($q.items).Count -eq 0) 'standard_source_budget_preflight_zero_IO'
    }finally{$low.Dispose()}
    $image=$null;$fixture=$null;[GC]::Collect()
    Write-Host ('C5-05 COVERAGE SUMMARY compact_cases={0} compact_actualB={1} compact_uniqueB={2} compact_repeatedB={3} compact_readCalls={4} standard_cases={5} standard_actualB={6} standard_uniqueB={7} standard_readCalls={8} Bgeometry_separate_B={9} process_peak_RAM=not_measured false_original_claims=0 A_source_receipts_minted=0' -f
        $cases,$sumActual,$sumUnique,$sumRepeat,$sumCalls,$stdCases,$stdActual,$stdUnique,$stdCalls,$stdGeo)
    Write-Host 'PASS: C5-05 C-owned untrusted coverage module matches independent source meter, excludes EOF bytes and refuses quota/flood'
}
