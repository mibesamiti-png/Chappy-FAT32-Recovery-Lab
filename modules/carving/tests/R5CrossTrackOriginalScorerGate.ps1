#requires -Version 5.1
# C5-04/C5-05: two-track artificial-original SHA and UNKNOWN gate.
# C scanner receives only source and non-oracle B-derived geometry; all
# generated ground truth is kept in this external scorer.
function Assert-C5Scorer([bool]$Okay,[string]$Why){if(-not $Okay){throw ('C5_04_FAIL: '+$Why)}}
function Invoke-C5CrossTrackOriginalScorer {
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
    . (Join-Path $root 'modules\directory\DirectoryScanner.ps1')
    Import-Module (Join-Path $root 'modules\carving\Chappy.FragmentEvidence.psm1') -Force
    $tiny=[ordered]@{cases=0;TP=0;FP=0;FN=0;TN=0;UNKNOWN=0;exact=0;wrongStructure=0;ambiguous=0;physical=0L;unique=0L;calls=0;parser=0L;probes=0;pairs=0;ms=0L}
    $large=[ordered]@{cases=0;TP=0;FP=0;FN=0;TN=0;UNKNOWN=0;exact=0;wrongStructure=0;physical=0L;unique=0L;calls=0;geomPhysical=0L;geomCalls=0;basePhysical=0L;baseCalls=0;probes=0;candidates=0;ms=0L}
    $kinds=@('M01_control','offgrid_first','offgrid_plus_two',
        'nonlisted_first_560','alternate_zip_metadata','fake_eocd',
        'missing_tail','physical_reverse')
    foreach($seed in @(202611,202612)){
        $clean=New-ChappyA3DCleanFixture -Seed $seed
        $truth=@($clean.oracle|Where-Object {$_.shortName -ceq 'MODEL   3MF'})[0]
        [byte[]]$original=[byte[]]::new([int]$truth.lengthBytes)
        $pos=0
        foreach($span in $truth.extents){
            [Array]::Copy($clean.image,[int]$span.offsetBytes,$original,$pos,[int]$span.lengthBytes)
            $pos+=[int]$span.lengthBytes
        }
        Assert-C5Scorer ($pos -eq $original.Length -and (Get-A3DSha256 $original) -ceq $truth.sha256) ('small_seed_'+$seed+':original_SHA')
        foreach($kind in $kinds){
            $case=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind $(if($kind -eq 'physical_reverse'){'M01_control'}else{$kind})
            [byte[]]$img=$case.image
            if($kind -eq 'physical_reverse'){
                [Array]::Clear($img,58880,1024)
                [Array]::Clear($img,60416,1024)
                [Array]::Copy($original,0,$img,60416,512)
                [Array]::Copy($original,512,$img,58880,($original.Length-512))
            }
            $before=Get-A3DSha256 $img
            $meter=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($img,$false))
            try {
                $args=@{Source=$meter;EnableFragmentEvidence=$true;WindowBytes=65536
                    MaxStarts=4;MaxTails=8;MaxPairs=16;MaxSourceBytes=81920
                    MaxValidationBytes=98304;MaxMilliseconds=30000}
                $r=Get-ChappyFragmentCandidates @args
                Assert-C5Scorer ($r.status -eq 'ok' -and $r.scanIncomplete -and $r.originalIdentity -eq 'unknown' -and
                    $null -eq $r.selectedOriginal -and -not $r.canAutoSelectOriginal -and
                    $r.metrics.sourceBytesRead -eq $meter.BytesRead -and $r.metrics.readRequests -eq $meter.ReadCalls -and
                    $meter.BytesRead -le 81920 -and $meter.UniqueBytes -le $meter.BytesRead -and
                    $r.metrics.validatorBytesRead -le 98304 -and $r.metrics.pairAttempts -le 16 -and
                    $r.metrics.sectorProbes -eq 128 -and @($r.items).Count -le 16) ('small_'+$seed+'_'+$kind+':bounded')
                $tiny.physical += $meter.BytesRead;$tiny.unique += $meter.UniqueBytes;$tiny.calls += $meter.ReadCalls
                $tiny.parser += [long]$r.metrics.validatorBytesRead;$tiny.probes += [int]$r.metrics.sectorProbes
                $tiny.pairs += [int]$r.metrics.pairAttempts;$tiny.ms += [long]$r.metrics.elapsedMilliseconds
                $uni=$meter.UniqueBytes
            }finally{$meter.Dispose()}
            # Post-discovery oracle: independently join the actual returned
            # ordered physical spans and compare to generated original SHA.
            $sc=Get-CFragmentScorer -Image $img -Hypotheses @($r.items) -OriginalSha $truth.sha256
            Assert-C5Scorer (($sc.exact+$sc.structuralWrong) -eq @($r.items).Count) ('small_'+$seed+':all_hypotheses_scored')
            $tiny.exact += $sc.exact;$tiny.wrongStructure += $sc.structuralWrong
            if($r.decision -eq 'ambiguous'){$tiny.ambiguous++}
            $unit=if($kind -eq 'missing_tail'){'absent_target_slot'}elseif($kind -in @('offgrid_plus_two','nonlisted_first_560')){'unobserved_hypothesis'}else{'supported_target_slot'}
            switch($unit){
                'absent_target_slot' {if($sc.exact -gt 0){$tiny.FP++}else{$tiny.TN++}}
                'unobserved_hypothesis' {$tiny.UNKNOWN++}
                'supported_target_slot' {if($sc.exact -eq 1){$tiny.TP++}else{$tiny.FN++}}
            }
            if($unit -eq 'unobserved_hypothesis'){
                Assert-C5Scorer ($r.decision -eq 'unknown' -and $sc.exact -eq 0) ('small_'+$seed+'_'+$kind+':must_stay_UNKNOWN')
            }
            if($kind -eq 'alternate_zip_metadata'){
                Assert-C5Scorer ($r.decision -eq 'ambiguous' -and $sc.exact -eq 1 -and $sc.structuralWrong -eq 1) ('small_'+$seed+':CRC_valid_false_join')
            }
            if($kind -eq 'physical_reverse'){
                Assert-C5Scorer ($sc.exact -eq 1 -and $sc.exactCandidate.firstOffset -gt $sc.exactCandidate.secondOffset) ('small_'+$seed+':physical_reverse')
            }
            Assert-C5Scorer ((Get-A3DSha256 $img) -ceq $before) ('small_'+$seed+'_'+$kind+':unchanged')
            $tiny.cases++
            Write-Host ('C5-04 SMALL seed={0} kind={1} unit={2} decision={3} exact={4} wrongSHA={5} phys={6} unique={7} calls={8} pairs={9}' -f
                $seed,$kind,$unit,$r.decision,$sc.exact,$sc.structuralWrong,$r.metrics.sourceBytesRead,$uni,$r.metrics.readRequests,$r.metrics.pairAttempts)
            $img=$null;$case=$null
        }
        $clean=$null;$original=$null;[GC]::Collect()
    }
    foreach($seed in @(202611,202612)){
        foreach($spc in @(1,2)){
            $variants=if($spc -eq 1){@('fragmented')}else{@('contiguous','crc_damaged')}
            foreach($variant in $variants){
                $fixture=New-ChappyA3DStandardFixture -Seed $seed -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
                [byte[]]$img=$fixture.image
                $oracle=@($fixture.oracle|Where-Object {$_.shortName -ceq 'MODEL   3MF'})[0]
                Assert-C5Scorer ($img.Length -gt 30000000 -and $fixture.generatorVersion -ceq 'A3D-standard-r1') 'standard_large_generated_geometry'
                if($variant -eq 'crc_damaged'){
                    $at=[int]($oracle.extents[0].offsetBytes+42)
                    Assert-C5Scorer ($at -lt $oracle.extents[0].offsetBytes+$oracle.extents[0].lengthBytes) 'mutator_in_synthetic_member'
                    $img[$at]=[byte]($img[$at] -bxor 1)
                }
                # Independent fixture-side false PK in unused FAT area.
                $fatDecoy=(33*512)+120
                [Array]::Copy([byte[]]@(0x50,0x4b,0x03,0x04),0,$img,$fatDecoy,4)
                $before=Get-A3DSha256 $img
                $gm=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($img,$false))
                try{
                    $geo=Get-ChappyFat32Geometry -Stream $gm
                    Assert-C5Scorer ($geo.clusterCount -eq 65541 -and $geo.bytesPerSector -eq 512 -and
                        $geo.sectorsPerCluster -eq $spc -and $geo.dataOffsetBytes -gt 65536 -and
                        $geo.partitionEndBytes -le $img.Length) ('standard_'+$seed+'_'+$spc+':B_parsed_geometry')
                    $large.geomPhysical += $gm.BytesRead;$large.geomCalls += $gm.ReadCalls
                }finally{$gm.Dispose()}
                $fixed=@{MaxScanBytes=65536;MaxFileBytes=4096;ExtraValidationReadBytes=32768
                    MaxCandidates=16;MaxProbes=16;MaxProbeBytes=8192;EnableSmallDeflateCrc=$true}
                $b=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($img,$false))
                try{
                    $baseline=Get-ChappyCarvingCandidates -Stream $b -StartOffset 0 @fixed
                    Assert-C5Scorer ($baseline.metrics.bytesRead -eq $b.BytesRead -and
                        $b.BytesRead -le 98304) ('standard_'+$seed+':physical_baseline')
                    $large.basePhysical += $b.BytesRead;$large.baseCalls += $b.ReadCalls
                }finally{$b.Dispose()}
                $m=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($img,$false))
                try{
                    $r=Get-ChappyCarvingCandidates -Stream $m -StartOffset ([long]$geo.dataOffsetBytes) @fixed
                    Assert-C5Scorer ($r.metrics.bytesRead -eq $m.BytesRead -and $r.metrics.readRequests -eq $m.ReadCalls -and
                        $m.BytesRead -le 98304 -and $m.UniqueBytes -le $m.BytesRead -and
                        $r.metrics.entriesChecked -le 16 -and @($r.items).Count -le 16 -and
                        $r.scanIncomplete -and -not $m.CanWrite) ('standard_'+$seed+'_'+$spc+':bounded')
                    $large.physical += $m.BytesRead;$large.unique += $m.UniqueBytes;$large.calls += $m.ReadCalls
                    $large.probes += [int]$r.metrics.entriesChecked;$large.candidates += @($r.items).Count
                    $large.ms += [long]$r.metrics.elapsedMilliseconds
                    $sourceUnique=$m.UniqueBytes
                }finally{$m.Dispose()}
                $exact=0;$wrong=0
                foreach($item in @($r.items)){
                    Assert-C5Scorer ($item.integrityScope -cne 'original_file_integrity' -and
                        $null -eq $item.PSObject.Properties['sourceToken'] -and
                        $item.offsetBytes -ge $geo.dataOffsetBytes) ('standard_'+$seed+':no_original_or_FAT_decoy')
                    if($item.format -cne '3mf' -or $item.lengthBytes -lt 128 -or $item.lengthBytes -gt 4096 -or
                        $item.offsetBytes -gt ($img.Length-$item.lengthBytes)){continue}
                    [byte[]]$joined=[byte[]]::new([int]$item.lengthBytes)
                    [Array]::Copy($img,[int]$item.offsetBytes,$joined,0,$joined.Length)
                    $fileSha=Get-A3DSha256 $joined
                    if($fileSha -ceq $oracle.sha256 -and $item.lengthBytes -eq $oracle.lengthBytes -and
                        $item.offsetBytes -eq $oracle.extents[0].offsetBytes){$exact++}
                    else{$wrong++}
                }
                Assert-C5Scorer ($exact -le 1) ('standard_'+$seed+':one_original_candidate_max')
                $large.exact += $exact;$large.wrongStructure += $wrong
                if($variant -eq 'fragmented'){
                    Assert-C5Scorer ($exact -eq 0) ('standard_'+$seed+':contiguous_search_fragment_UNKNOWN')
                    $large.UNKNOWN++
                }elseif($variant -eq 'crc_damaged'){
                    if($exact -eq 0){$large.TN++}else{$large.FP++}
                }else{
                    if($exact -eq 1){$large.TP++}else{$large.FN++}
                }
                Assert-C5Scorer ((Get-A3DSha256 $img) -ceq $before) ('standard_'+$seed+'_'+$variant+':source_unchanged')
                $large.cases++
                Write-Host ('C5-04 STANDARD seed={0} spc={1} kind={2} exact={3} structureWrong={4} phys={5} unique={6} calls={7} BgeoB={8} baselineB={9} coverage=partial' -f
                    $seed,$spc,$variant,$exact,$wrong,$r.metrics.bytesRead,$sourceUnique,$r.metrics.readRequests,$large.geomPhysical,$baseline.metrics.bytesRead)
                $img=$null;$fixture=$null;[GC]::Collect()
            }
        }
    }
    # A genuine 17-byte return followed by zero EOF cannot become verified.
    $f=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster 2
    [byte[]]$img=$f.image
    $gs=[IO.MemoryStream]::new($img,$false)
    try{$geo=Get-ChappyFat32Geometry -Stream $gs}finally{$gs.Dispose()}
    $short=[ChappyC17ThenEof]::new([IO.MemoryStream]::new($img,$false))
    try{
        $q=Get-ChappyCarvingCandidates -Stream $short -StartOffset ([long]$geo.dataOffsetBytes) @fixed
        Assert-C5Scorer ($short.Returned -eq 17 -and $q.metrics.bytesRead -eq 17 -and
            $q.scanIncomplete -and $q.status -eq 'partial' -and
            @($q.items|Where-Object {$_.format -eq '3mf' -and $_.confidence -eq 'verified'}).Count -eq 0) 'standard_17_then_EOF_not_original'
    }finally{$short.Dispose()}
    $img=$null;$f=$null;[GC]::Collect()
    Assert-C5Scorer ($tiny.cases -eq 16 -and $tiny.TP -eq 10 -and $tiny.FP -eq 0 -and $tiny.FN -eq 0 -and
        $tiny.TN -eq 2 -and $tiny.UNKNOWN -eq 4 -and $tiny.exact -eq 10 -and
        $tiny.wrongStructure -eq 2 -and $tiny.ambiguous -eq 2) 'small_frozen_truth'
    Assert-C5Scorer ($large.cases -eq 6 -and $large.TP -eq 2 -and $large.FP -eq 0 -and $large.FN -eq 0 -and
        $large.TN -eq 2 -and $large.UNKNOWN -eq 2 -and $large.exact -eq 2) 'standard_frozen_truth'
    Assert-C5Scorer ($tiny.unique -eq (16L*65536L) -and $tiny.physical -le (16L*81920L) -and
        $large.unique -le $large.physical -and $large.physical -le (6L*98304L)) 'aggregate_bounded'
    Write-Host ('C5-04 SMALL SUMMARY cases={0} TP={1} FP={2} FN={3} TN={4} UNKNOWN={5} originalSHA={6} wrongSHA_structural={7} ambiguous={8} physicalB={9} uniqueB={10} calls={11} parserB={12} probes={13} pairs={14} ms={15}' -f
        $tiny.cases,$tiny.TP,$tiny.FP,$tiny.FN,$tiny.TN,$tiny.UNKNOWN,$tiny.exact,$tiny.wrongStructure,$tiny.ambiguous,
        $tiny.physical,$tiny.unique,$tiny.calls,$tiny.parser,$tiny.probes,$tiny.pairs,$tiny.ms)
    Write-Host ('C5-04 STANDARD SUMMARY cases={0} TP={1} FP={2} FN={3} TN={4} UNKNOWN={5} originalSHA={6} wrongSHA_structural={7} physicalB={8} uniqueB={9} calls={10} geometryB={11} geometryCalls={12} baselineB={13} baselineCalls={14} probes={15} candidates={16} ms={17}' -f
        $large.cases,$large.TP,$large.FP,$large.FN,$large.TN,$large.UNKNOWN,$large.exact,$large.wrongStructure,
        $large.physical,$large.unique,$large.calls,$large.geomPhysical,$large.geomCalls,$large.basePhysical,
        $large.baseCalls,$large.probes,$large.candidates,$large.ms)
    Write-Host 'PASS: C5-04 external-only original SHA, both corpus tracks, UNKNOWN distinct, actual source accounting'
}
