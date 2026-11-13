#requires -Version 5.1
# Team C Issue #72 C5-03 gate: independent scorer knows source positions,
# generated-original SHA and mutation labels; C module never receives them.
function Assert-CFragmentGate([bool]$Okay,[string]$Why) {
    if(-not $Okay){throw ('C5_03_FRAGMENT_FAIL: '+$Why)}
}
if(-not ('ChappyCFragmentMeter' -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class ChappyCFragmentMeter:Stream {
 private readonly Stream s; private readonly HashSet<long> observed=new HashSet<long>();
 public long BytesRead{get;private set;}
 public int ReadCalls{get;private set;}
 public long UniqueBytes{get{return observed.Count;}}
 public ChappyCFragmentMeter(Stream x){
  if(x==null||!x.CanRead||!x.CanSeek||x.CanWrite)throw new ArgumentException("read-only only");
  s=x;
 }
 public override bool CanRead{get{return true;}}
 public override bool CanSeek{get{return true;}}
 public override bool CanWrite{get{return false;}}
 public override long Length{get{return s.Length;}}
 public override long Position{get{return s.Position;}set{s.Position=value;}}
 public override int Read(byte[] b,int o,int n){
  long at=s.Position;int got=s.Read(b,o,n);ReadCalls++;BytesRead+=got;
  for(int i=0;i<got;i++)observed.Add(at+i);
  return got;
 }
 public override long Seek(long at,SeekOrigin origin){return s.Seek(at,origin);}
 public override void Flush(){}
 public override void SetLength(long x){throw new NotSupportedException();}
 public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
 protected override void Dispose(bool x){if(x)s.Dispose();base.Dispose(x);}
}
'@
}
function Get-CFragmentScorer {
    param([byte[]]$Image,[object[]]$Hypotheses,[string]$OriginalSha)
    $exact=0;$structuralWrong=0;$reversedHashWrong=0
    $first=$null
    foreach($hypothesis in $Hypotheses){
        Assert-CFragmentGate (@($hypothesis.sourceSpans).Count -eq 2 -and
            $hypothesis.format -eq '3mf' -and $hypothesis.confidence -eq 'probable' -and
            $hypothesis.originalIdentity -eq 'unknown' -and
            $hypothesis.integrityScope -eq 'structural_only_not_original_file_integrity' -and
            $hypothesis.sourceOrigin -eq 'unattributed_without_A_meter' -and
            $null -eq $hypothesis.PSObject.Properties['candidateSha256'] -and
            $null -eq $hypothesis.PSObject.Properties['sourceToken'] -and
            $null -eq $hypothesis.PSObject.Properties['evidenceId']) 'no fabricated original or A source receipt'
        $start=$hypothesis.sourceSpans[0];$tail=$hypothesis.sourceSpans[1]
        $size=[int]($start.lengthBytes+$tail.lengthBytes)
        Assert-CFragmentGate ($size -gt 0 -and $size -le 1056 -and
            $start.offsetBytes -ge 0 -and $tail.offsetBytes -ge 0 -and
            $start.offsetBytes+$start.lengthBytes -le $Image.Length -and
            $tail.offsetBytes+$tail.lengthBytes -le $Image.Length -and
            ($start.offsetBytes -ge ($tail.offsetBytes+$tail.lengthBytes) -or
             $tail.offsetBytes -ge ($start.offsetBytes+$start.lengthBytes))) 'source extents independently in range nonoverlapping'
        [byte[]]$joined=[byte[]]::new($size)
        [Array]::Copy($Image,[int]$start.offsetBytes,$joined,0,[int]$start.lengthBytes)
        [Array]::Copy($Image,[int]$tail.offsetBytes,$joined,[int]$start.lengthBytes,[int]$tail.lengthBytes)
        $hash=Get-A3DSha256 $joined
        if($hash -ceq $OriginalSha){$exact++;$first=$hypothesis}
        else{$structuralWrong++}
    }
    return [pscustomobject]@{exact=$exact;structuralWrong=$structuralWrong;exactCandidate=$first}
}
function Invoke-CFragmentModuleGateRegression {
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $root 'modules\carving\Chappy.FragmentEvidence.psm1') -Force
    . (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
    $seed=202611
    $clean=New-ChappyA3DCleanFixture -Seed $seed
    $truth=$clean.oracle[1]
    [byte[]]$original=[byte[]]::new([int]$truth.lengthBytes)
    $pos=0
    foreach($span in $truth.extents){
        [Array]::Copy($clean.image,[int]$span.offsetBytes,$original,$pos,[int]$span.lengthBytes)
        $pos+=[int]$span.lengthBytes
    }
    Assert-CFragmentGate ($pos -eq $original.Length -and
        (Get-A3DSha256 $original) -ceq $truth.sha256) 'frozen_generator_byte_exact_truth'
    $cases=@('M01_control','non512_offgrid_tail','offgrid_first','fake_eocd',
        'alternate_zip_metadata','missing_tail','offgrid_plus_two',
        'nonlisted_first_560','physical_reverse')
    $caseTP=0;$caseFN=0;$caseTN=0;$caseFP=0
    $exact=0;$falseStructural=0;$ambiguous=0;$unknown=0
    $oldPhysical=0L;$newPhysical=0L;$newUnique=0L
    $oldRequests=0;$newRequests=0;$oldMem=0L;$newMem=0L
    $oldPairs=0;$newPairs=0;$elapsed=0L
    $referenceCase=$null;$reverseCase=$null;$ambiguousCase=$null
    foreach($kind in $cases){
        $name=if($kind -eq 'physical_reverse'){'M01_control'}else{$kind}
        $case=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind $name
        [byte[]]$image=$case.image
        if($kind -eq 'physical_reverse'){
            [Array]::Clear($image,58880,1024)
            [Array]::Clear($image,60416,1024)
            [Array]::Copy($original,0,$image,60416,512)
            [Array]::Copy($original,512,$image,58880,($original.Length-512))
            $case.trueFirst=60416;$case.trueSecond=58880
            $case.trueFirstBytes=512;$case.trueSecondBytes=$original.Length-512
            Assert-CFragmentGate ($case.trueFirst -gt $case.trueSecond) 'physical_reverse_synthetic_placement'
        }
        $before=Get-A3DSha256 $image
        $off=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($image,$false))
        try{
            $r=Get-ChappyFragmentCandidates -Source $off
            Assert-CFragmentGate ($r.status -eq 'disabled' -and $r.decision -eq 'unknown' -and
                $off.BytesRead -eq 0 -and $off.ReadCalls -eq 0 -and @($r.items).Count -eq 0) ($kind+':default_off_without_reads')
        }finally{$off.Dispose()}
        $baseline=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($image,$false))
        try{
            $old=Test-CVariableZipPairs -Source $baseline -WindowBytes 65536 -MaxStarts 4 -MaxTails 8 -MaxPairs 16 -MaxSourceBytes 81920 -MaxValidationBytes 98304 -MaxMilliseconds 30000
            Assert-CFragmentGate ($old.metrics.sourceBytesRead -eq $baseline.BytesRead -and
                $old.metrics.readRequests -eq $baseline.ReadCalls -and
                $baseline.BytesRead -le 81920) ($kind+':research_baseline_actual_source')
            $oldPhysical+=$baseline.BytesRead
            $oldRequests+=$baseline.ReadCalls
            $oldMem+=[long]$old.metrics.validatorBytesRead
            $oldPairs+=[int]$old.metrics.pairAttempts
        }finally{$baseline.Dispose()}
        $newMeter=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($image,$false))
        try{
            $r=Get-ChappyFragmentCandidates -Source $newMeter -EnableFragmentEvidence -WindowBytes 65536 -MaxStarts 4 -MaxTails 8 -MaxPairs 16 -MaxSourceBytes 81920 -MaxValidationBytes 98304 -MaxMilliseconds 30000
            Assert-CFragmentGate ($r.status -eq 'ok' -and $r.originalIdentity -eq 'unknown' -and
                -not $r.canAutoSelectOriginal -and $null -eq $r.selectedOriginal -and
                $r.scanIncomplete -and $r.warnings -contains 'fragment.unscanned_source_unknown' -and
                $r.metrics.sourceBytesRead -eq $newMeter.BytesRead -and
                $r.metrics.readRequests -eq $newMeter.ReadCalls -and
                $r.metrics.sourceBytesRead -le 81920 -and $r.metrics.validatorBytesRead -le 98304 -and
                $r.metrics.pairAttempts -le 16 -and $r.metrics.sectorProbes -eq 128 -and
                @($r.items).Count -le 16 -and
                $newMeter.UniqueBytes -le $newMeter.BytesRead -and -not $newMeter.CanWrite) ($kind+':bounded_read_only_nonoracle_module')
            Assert-CFragmentGate ($r.decision -ceq $old.decision -and
                @($r.items).Count -eq @($old.items|Where-Object {$_.possible}).Count) ($kind+':same_algorithm_no_accuracy_inflation')
            $newPhysical+=$newMeter.BytesRead
            $newUnique+=$newMeter.UniqueBytes
            $newRequests+=$newMeter.ReadCalls
            $newMem+=[long]$r.metrics.validatorBytesRead
            $newPairs+=[int]$r.metrics.pairAttempts
            $elapsed+=[long]$r.metrics.elapsedMilliseconds
        }finally{$newMeter.Dispose()}
        Assert-CFragmentGate ((Get-A3DSha256 $image) -ceq $before) ($kind+':synthetic_image_unmodified')
        $sc=Get-CFragmentScorer -Image $image -Hypotheses @($r.items) -OriginalSha $truth.sha256
        $exact += $sc.exact;$falseStructural += $sc.structuralWrong
        $inScope=($kind -notin @('missing_tail'))
        if($inScope) {
            if($sc.exact -eq 1){$caseTP++}
            else{$caseFN++}
        } else {
            if(@($r.items).Count -eq 0){$caseTN++}else{$caseFP++}
        }
        if($kind -eq 'M01_control'){
            Assert-CFragmentGate ($sc.exact -eq 1 -and $r.decision -eq 'one_possible') 'clean_2fragment'
            $referenceCase=[pscustomobject]@{image=$image;candidate=$sc.exactCandidate}
        }
        if($kind -eq 'physical_reverse'){
            Assert-CFragmentGate ($sc.exact -eq 1 -and $r.decision -eq 'one_possible' -and
                $sc.exactCandidate.firstOffset -gt $sc.exactCandidate.secondOffset) 'reversed_physical_source_order_reconstructed_logically'
            $reverseCase=$r
        }
        if($kind -eq 'fake_eocd'){
            Assert-CFragmentGate ($sc.exact -eq 1 -and $r.decision -eq 'one_possible' -and
                $r.metrics.tailCandidates -ge 4) 'fake_EOCD_rejected_not_winner'
        }
        if($kind -eq 'alternate_zip_metadata'){
            Assert-CFragmentGate ($r.decision -eq 'ambiguous' -and @($r.items).Count -eq 2 -and
                $sc.exact -eq 1 -and $sc.structuralWrong -eq 1 -and
                $null -eq $r.selectedOriginal) 'CRC_valid_alternative_stays_ambiguous'
            $ambiguousCase=$r
        }
        if($kind -in @('offgrid_plus_two','nonlisted_first_560','missing_tail')){
            Assert-CFragmentGate ($r.decision -eq 'unknown' -and @($r.items).Count -eq 0) ($kind+':unsupported_or_missing_unknown_not_absent')
        }
        if($r.decision -eq 'ambiguous'){$ambiguous++}
        if($r.decision -eq 'unknown'){$unknown++}
        Write-Host ('C5-03 CASE={0} old={1} new={2} exact={3} extra_structural={4} candidates={5} sourceB={6} uniqueB={7} calls={8} parserB={9} pairs={10}' -f
            $kind,$old.decision,$r.decision,$sc.exact,$sc.structuralWrong,@($r.items).Count,
            $r.metrics.sourceBytesRead,$newMeter.UniqueBytes,$r.metrics.readRequests,$r.metrics.validatorBytesRead,$r.metrics.pairAttempts)
        $image=$null;$case=$null
    }
    Assert-CFragmentGate ($cases.Count -eq 9 -and $caseTP -eq 6 -and $caseFN -eq 2 -and
        $caseFP -eq 0 -and $caseTN -eq 1 -and $exact -eq 6 -and $falseStructural -eq 1 -and
        $ambiguous -eq 1 -and $unknown -eq 3 -and
        $null -ne $referenceCase -and $null -ne $reverseCase -and $null -ne $ambiguousCase) 'frozen_9_case_truth_and_unknown'
    # Wrong *logical* ordering is a negative even when physical ordering is
    # free: ZIP local header must precede EOCD in reconstructed bytes.
    $reference=$referenceCase.candidate
    $a=$reference.sourceSpans[0];$b=$reference.sourceSpans[1]
    [byte[]]$wrong=[byte[]]::new([int]($a.lengthBytes+$b.lengthBytes))
    [Array]::Copy($referenceCase.image,[int]$b.offsetBytes,$wrong,0,[int]$b.lengthBytes)
    [Array]::Copy($referenceCase.image,[int]$a.offsetBytes,$wrong,[int]$b.lengthBytes,[int]$a.lengthBytes)
    Assert-CFragmentGate ((Get-A3DSha256 $wrong) -cne $truth.sha256) 'reversed_logical_order_not_original'
    $wrongStream=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($wrong,$false))
    try {
        $check=Get-ChappyCarvingCandidates -Stream $wrongStream -MaxScanBytes $wrong.Length -MaxFileBytes 4096 -ExtraValidationReadBytes 4096 -MaxCandidates 4 -MaxProbes 4 -MaxProbeBytes 4096 -EnableSmallDeflateCrc
        Assert-CFragmentGate (@($check.items|Where-Object {$_.format -eq '3mf' -and $_.lengthBytes -eq $wrong.Length -and $_.confidence -eq 'verified'}).Count -eq 0) 'reversed_logical_order_C_validator_rejects'
    }finally{$wrongStream.Dispose()}
    $short=[ChappyCFragmentMeter]::new([CArtificialShortValidationStream]::new([IO.MemoryStream]::new($referenceCase.image,$false),17))
    try {
        $r=Get-ChappyFragmentCandidates -Source $short -EnableFragmentEvidence
        Assert-CFragmentGate ($r.status -eq 'partial' -and $r.decision -eq 'incomplete' -and
            @($r.items).Count -eq 0 -and $r.metrics.sourceBytesRead -eq 17 -and
            $short.BytesRead -eq 17 -and $short.ReadCalls -eq $r.metrics.readRequests) 'real_17B_then_true_EOF'
    }finally{$short.Dispose()}
    $insufficient=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($referenceCase.image,$false))
    try{
        $r=Get-ChappyFragmentCandidates -Source $insufficient -EnableFragmentEvidence -MaxSourceBytes 1024
        Assert-CFragmentGate ($r.status -eq 'partial' -and $r.decision -eq 'incomplete' -and
            @($r.items).Count -eq 0 -and $insufficient.BytesRead -eq 0) 'quota_preflight_zero_source_reads'
        $r=Get-ChappyFragmentCandidates -Source $insufficient -EnableFragmentEvidence -MaxPairs 1
        Assert-CFragmentGate ($r.status -eq 'partial' -and $r.decision -eq 'incomplete' -and
            @($r.items).Count -eq 0 -and $insufficient.BytesRead -le (65536L+81920L)) 'pair_flood_no_cherrypick'
    }finally{$insufficient.Dispose()}
    $writable=[IO.MemoryStream]::new($referenceCase.image,$true)
    try{
        $denied=$false
        try{Get-ChappyFragmentCandidates -Source $writable -EnableFragmentEvidence|Out-Null}catch{$denied=$true}
        Assert-CFragmentGate $denied 'writable_source_rejected'
    }finally{$writable.Dispose()}
    Write-Host ('C5-03 SUMMARY files=9 labels_present=8 absent=1 case_TP={0} FP={1} FN={2} TN={3} exact_SHA_candidates={4} extra_structural_SHA_wrong={5} ambiguous={6} unknown={7} old_source_B={8} new_source_B={9} new_unique_B={10} old_reads={11} new_reads={12} old_parser_B={13} new_parser_B={14} old_pairs={15} new_pairs={16} elapsed_new_ms={17} false_original_claims=0 A_source_receipts=0' -f
        $caseTP,$caseFP,$caseFN,$caseTN,$exact,$falseStructural,$ambiguous,$unknown,
        $oldPhysical,$newPhysical,$newUnique,$oldRequests,$newRequests,$oldMem,$newMem,$oldPairs,$newPairs,$elapsed)
    Write-Host 'PASS: C5-03 non-oracle guarded production module, reversed order, decoy ambiguity, true EOF and external artificial SHA'
}
