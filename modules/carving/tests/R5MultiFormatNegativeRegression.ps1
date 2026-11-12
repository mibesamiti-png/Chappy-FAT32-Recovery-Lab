#requires -Version 5.1
# Issue #72: external synthetic scorer. Oracle offsets and SHA NEVER enter
# Get-CMultiFormatEvidence; only invented controls and mutations are used.
function Invoke-CMultiFormatNegativeControls {
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $root 'tests\helpers\New-Chappy3DCleanFixture.ps1')
    $seed=202611
    $clean=New-ChappyA3DCleanFixture -Seed $seed -IncludeFormatControls
    $truth=@{}
    foreach($record in $clean.oracle){$truth[$record.format]=$record}
    foreach($format in @('stl_binary','stl_ascii','zip_plain','decoy')){
        Assert-CMulti ($truth.ContainsKey($format)) ('missing_artificial_oracle_'+$format)
        Assert-CMulti ($truth[$format].extents.Count -eq 1 -and $truth[$format].lengthBytes -le 512) ('one_sector_control_'+$format)
    }
    $cases=@('clean','binary_vertex_modified','binary_count_invalid','ascii_keyword_invalid','zip_metadata_modified','zip_payload_modified')
    $baseTP=0;$baseFP=0;$baseFN=0;$baseTN=0
    $newTP=0;$newFP=0;$newFN=0;$newTN=0
    $exact=0;$validButDifferent=0;$falseOriginalClaims=0
    $baseBytesTotal=0L;$newBytesTotal=0L;$newValidatorTotal=0L
    $baseRequests=0;$newRequests=0;$sectorProbes=0;$zipRejected=0
    $baseElapsedMs=0L;$newElapsedMs=0L
    foreach($name in $cases){
        [byte[]]$image=$clean.image.Clone()
        $bin=$truth['stl_binary'];$ascii=$truth['stl_ascii'];$zip=$truth['zip_plain']
        switch($name){
            'binary_vertex_modified' {
                $at=[int]$bin.extents[0].offsetBytes+84+12
                $image[$at]=[byte]($image[$at] -bxor 1)
            }
            'binary_count_invalid' {
                $at=[int]$bin.extents[0].offsetBytes+80
                [Array]::Copy([BitConverter]::GetBytes([uint32]65535),0,$image,$at,4)
            }
            'ascii_keyword_invalid' {
                $at=[int]$ascii.extents[0].offsetBytes
                $text=[Text.Encoding]::ASCII.GetString($image,$at,[int]$ascii.lengthBytes)
                $pos=$text.IndexOf('endfacet',[StringComparison]::Ordinal)
                Assert-CMulti ($pos -ge 0) 'ascii_mutation_target'
                $image[$at+$pos+7]=[byte][char]'x'
            }
            'zip_metadata_modified' {
                $at=[int]$zip.extents[0].offsetBytes
                $end=$at+[int]$zip.lengthBytes-46
                $central=-1
                for($i=$at;$i -le $end;$i++){
                    if([BitConverter]::ToUInt32($image,$i) -eq 0x02014B50){$central=$i;break}
                }
                Assert-CMulti ($central -ge 0) 'zip_central_mutation_target'
                # ZIP entry central-directory version-made-by does not change
                # uncompressed member content or its CRC; SHA changes.
                $image[$central+4]=[byte]($image[$central+4] -bxor 1)
            }
            'zip_payload_modified' {
                $at=[int]$zip.extents[0].offsetBytes
                Assert-CMulti ([BitConverter]::ToUInt32($image,$at) -eq 0x04034B50) 'zip_local_header'
                $nameLen=[BitConverter]::ToUInt16($image,$at+26)
                $extraLen=[BitConverter]::ToUInt16($image,$at+28)
                $compressed=[BitConverter]::ToUInt32($image,$at+18)
                $data=$at+30+$nameLen+$extraLen
                Assert-CMulti ($compressed -gt 0 -and ($data+$compressed) -le ($at+$zip.lengthBytes)) 'zip_member_range'
                $image[$data+[int]($compressed/2)]=[byte]($image[$data+[int]($compressed/2)] -bxor 1)
            }
        }
        $before=Get-A3DSha256 $image
        $baselineStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($image,$false))
        try{
            $base=Get-ChappyCarvingCandidates -Stream $baselineStream -MaxScanBytes 65536 -MaxFileBytes 4096 -ExtraValidationReadBytes 32768 -MaxCandidates 16 -MaxProbes 16 -MaxProbeBytes 8192 -MaxWorkMilliseconds 30000 -EnableSmallDeflateCrc
            Assert-CMulti ($baselineStream.BytesRead -eq $base.metrics.bytesRead -and $base.metrics.bytesRead -le 98304) ($name+':baseline_read_budget')
            $baseBytesTotal+=$baselineStream.BytesRead
            $baseRequests+=[int]$base.metrics.readRequests
            $baseElapsedMs+=[long]$base.metrics.elapsedMilliseconds
        }finally{$baselineStream.Dispose()}
        $researchStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($image,$false))
        try{
            $candidate=Get-CMultiFormatEvidence -Source $researchStream -WindowBytes 65536 -MaxSourceBytes 65536 -MaxSectorProbes 128 -MaxCandidates 16 -MaxValidatorBytes 32768 -MaxMilliseconds 30000
            Assert-CMulti ($candidate.status -eq 'ok' -and $candidate.decision -eq 'bounded_evidence') ($name+':research_complete')
            Assert-CMulti ($researchStream.BytesRead -eq $candidate.metrics.sourceBytesRead -and $researchStream.BytesRead -le 65536) ($name+':research_read_budget')
            Assert-CMulti ($candidate.metrics.validatorBytesRead -le 32768 -and $candidate.metrics.sectorProbes -eq 128) ($name+':research_validation_bounds')
            Assert-CMulti (-not $researchStream.CanWrite) ($name+':nonwritable')
            $newBytesTotal+=$researchStream.BytesRead
            $newValidatorTotal+=[long]$candidate.metrics.validatorBytesRead
            $newRequests+=[int]$candidate.metrics.readRequests
            $newElapsedMs+=[long]$candidate.metrics.elapsedMilliseconds
            $sectorProbes+=[int]$candidate.metrics.sectorProbes
            $zipRejected+=[int]$candidate.metrics.zipRejected
        }finally{$researchStream.Dispose()}
        Assert-CMulti ((Get-A3DSha256 $image) -ceq $before) ($name+':image_unmodified')

        foreach($format in @('stl_binary','stl_ascii','zip_plain','decoy')){
            $record=$truth[$format]
            $isValid=($format -ne 'decoy')
            if($name -eq 'binary_count_invalid' -and $format -eq 'stl_binary'){$isValid=$false}
            if($name -eq 'ascii_keyword_invalid' -and $format -eq 'stl_ascii'){$isValid=$false}
            if($name -eq 'zip_payload_modified' -and $format -eq 'zip_plain'){$isValid=$false}
            # Existing C module does not expose STL candidates by design.
            $b=@($base.items | Where-Object {
                $_.offsetBytes -eq $record.extents[0].offsetBytes -and
                $_.lengthBytes -eq $record.lengthBytes -and
                $_.format -eq 'zip' -and $_.confidence -eq 'verified' -and
                $_.crc32Status -eq 'match' -and
                $_.integrityScope -eq 'structural_only_not_original_file_integrity'
            })
            $baselineAccepted=($format -eq 'zip_plain' -and $b.Count -eq 1)
            $n=@($candidate.items | Where-Object {
                $_.format -eq $format -and $_.offsetBytes -eq $record.extents[0].offsetBytes -and
                $_.lengthBytes -eq $record.lengthBytes
            })
            $proposedAccepted=($n.Count -eq 1)
            if($isValid){
                if($baselineAccepted){$baseTP++}else{$baseFN++}
                if($proposedAccepted){$newTP++}else{$newFN++}
            }else{
                if($baselineAccepted){$baseFP++}else{$baseTN++}
                if($proposedAccepted){$newFP++}else{$newTN++}
            }
            if($proposedAccepted){
                Assert-CMulti ($n[0].originalIdentity -ceq 'unknown' -and $n[0].integrityScope -ceq 'structural_only_not_original_file_integrity') ($name+':no_original_provenance_'+$format)
                [byte[]]$slice=New-Object byte[] ([int]$record.lengthBytes)
                [Array]::Copy($image,[int]$record.extents[0].offsetBytes,$slice,0,$slice.Length)
                if((Get-A3DSha256 $slice) -ceq $record.sha256){$exact++}
                else{$validButDifferent++}
            }
        }
        # Existing module may call ZIP evidence verified, but ONLY in a
        # structural integrity scope, never original source identity.
        foreach($item in $base.items){
            if($item.confidence -eq 'verified' -and
               $item.integrityScope -cne 'structural_only_not_original_file_integrity' -and
               $item.integrityScope -cne 'heuristic_text_only_not_original_file_integrity'){
                $falseOriginalClaims++
            }
        }
        Assert-CMulti (@($candidate.items | Where-Object {$_.format -eq 'decoy' -or $_.originalIdentity -cne 'unknown'}).Count -eq 0) ($name+':decoy_not_promoted')
        Write-Host ('R5 MULTIFORMAT CASE={0} baselineBytes={1} researchBytes={2} validatorBytes={3} structuralCandidates={4} falseClaims={5}' -f
            $name,$base.metrics.bytesRead,$candidate.metrics.sourceBytesRead,$candidate.metrics.validatorBytesRead,$candidate.items.Count,$falseOriginalClaims)
    }
    # Predeclared labels: 6 cases x (binary STL, ASCII STL, plain ZIP,
    # signature decoy). Changed data may remain format-valid but not original.
    Assert-CMulti ($baseTP -eq 5 -and $baseFP -eq 0 -and $baseFN -eq 10 -and $baseTN -eq 9) 'baseline_truth_table'
    Assert-CMulti ($newTP -eq 15 -and $newFP -eq 0 -and $newFN -eq 0 -and $newTN -eq 9) 'research_truth_table'
    Assert-CMulti ($validButDifferent -eq 2 -and $exact -eq 13 -and $falseOriginalClaims -eq 0) 'structural_not_original_byte_identity'
    Assert-CMulti ($zipRejected -ge 6 -and $sectorProbes -eq 768) 'fake_signature_rejected_safely'
    Write-Host ('R5 MULTIFORMAT METRICS cases=6 format_slots=24 baseline_TP={0} baseline_FP={1} baseline_FN={2} baseline_TN={3} research_TP={4} research_FP={5} research_FN={6} research_TN={7} structural_exact_sha={8} structural_changed_sha={9} false_original_claims={10} baseline_source_bytes={11} research_source_bytes={12} research_validator_bytes={13} baseline_requests={14} research_requests={15} sampled_sectors={16} rejected_zip_signatures={17} baseline_elapsed_ms={18} research_elapsed_ms={19}' -f
        $baseTP,$baseFP,$baseFN,$baseTN,$newTP,$newFP,$newFN,$newTN,$exact,$validButDifferent,$falseOriginalClaims,$baseBytesTotal,$newBytesTotal,$newValidatorTotal,$baseRequests,$newRequests,$sectorProbes,$zipRejected,$baseElapsedMs,$newElapsedMs)

    $small=[IO.MemoryStream]::new([byte[]]::new(1024),$false)
    try{
        $partial=Get-CMultiFormatEvidence -Source $small
        Assert-CMulti ($partial.status -eq 'partial' -and $partial.decision -eq 'incomplete' -and $partial.metrics.sourceBytesRead -eq 0) 'truncated_without_read'
    }finally{$small.Dispose()}
    $cap=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($clean.image,$false))
    try{
        $partial=Get-CMultiFormatEvidence -Source $cap -MaxSourceBytes 1024
        Assert-CMulti ($partial.decision -eq 'incomplete' -and $cap.BytesRead -eq 0) 'quota_without_read'
        $partial=Get-CMultiFormatEvidence -Source $cap -MaxCandidates 1
        Assert-CMulti ($partial.decision -eq 'incomplete' -and @($partial.items).Count -eq 0 -and $cap.BytesRead -le 65536) 'candidate_overflow_no_cherrypick'
    }finally{$cap.Dispose()}
    $bad=[IO.MemoryStream]::new($clean.image,$true)
    try{
        $rejected=$false
        try{Get-CMultiFormatEvidence -Source $bad | Out-Null}catch{$rejected=$true}
        Assert-CMulti $rejected 'writable_source_refused'
    }finally{$bad.Dispose()}
    Write-Host 'PASS: R5 multiformat artificial binary/ASCII STL, plain ZIP and PK decoy, source-safe bounds and independent original SHA'
}
