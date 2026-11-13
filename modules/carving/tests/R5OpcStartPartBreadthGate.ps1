#requires -Version 5.1
# Team C C5-01: independently constructed OPC root StartPart and effective
# model MIME fixtures; old 12-case matrix is ALSO run unchanged.
# Not a real file corpus, does not prove model manufacturability or identity.
function Assert-C5OpcBreadth([bool]$Okay,[string]$Why) {
    if(-not $Okay){throw ('C5_01_OPC_BREADTH_FAIL: '+$Why)}
}
function New-C5OpcBreadthZip {
    param([string]$Case)
    Add-Type -AssemblyName System.IO.Compression
    $ctNs='http://schemas.openxmlformats.org/package/2006/content-types'
    $rNs='http://schemas.openxmlformats.org/package/2006/relationships'
    $mNs='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'
    $start='http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel'
    $mime='application/vnd.ms-package.3dmanufacturing-3dmodel+xml'
    $name=if($Case -in @('canonical','canonical_relative','payload_changed_valid')){'3D/3dmodel.model'}else{'3D/build.model'}
    $target='/'+$name
    if($Case -in @('alt_relative','canonical_relative')){$target=$name}
    if($Case -eq 'nonexistent'){$target='/3D/missing.model'}
    if($Case -eq 'traversal'){$target='/3D/../build.model'}
    if($Case -eq 'encoded_traversal'){$target='/3D/%2e%2e/build.model'}
    if($Case -eq 'wrong_target_decoy'){$target='/3D/decoy.model'}
    $ref='<Relationship Id="r0" Type="'+$start+'" Target="'+$target+'"/>'
    if($Case -eq 'external'){$ref='<Relationship Id="r0" Type="'+$start+'" Target="'+$target+'" TargetMode="External"/>'}
    $rels='<Relationships xmlns="'+$rNs+'">'+$ref+'</Relationships>'
    if($Case -eq 'nested_start'){$rels='<Relationships xmlns="'+$rNs+'"><Wrapper>'+$ref+'</Wrapper></Relationships>'}
    if($Case -eq 'duplicate_start'){$rels='<Relationships xmlns="'+$rNs+'">'+$ref+$ref.Replace('Id="r0"','Id="r1"')+'</Relationships>'}
    if($Case -eq 'duplicate_id'){$rels='<Relationships xmlns="'+$rNs+'">'+$ref+'<Relationship Id="r0" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail" Target="/Metadata/preview.png"/></Relationships>'}
    if($Case -eq 'extra_part'){$rels='<Relationships xmlns="'+$rNs+'">'+$ref+'<Relationship Id="r1" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail" Target="/Metadata/preview.png"/></Relationships>'}
    $override='<Override PartName="/'+$name+'" ContentType="'+$mime+'"/>'
    $default='<Default Extension="model" ContentType="'+$mime+'"/>'
    $ct='<Types xmlns="'+$ctNs+'">'+$override+'</Types>'
    if($Case -in @('default_model','default_alt')){$ct='<Types xmlns="'+$ctNs+'">'+$default+'</Types>'}
    if($Case -eq 'duplicate_override'){$ct='<Types xmlns="'+$ctNs+'">'+$override+$override+'</Types>'}
    if($Case -eq 'duplicate_default'){$ct='<Types xmlns="'+$ctNs+'">'+$default+$default+'</Types>'}
    if($Case -eq 'wrong_override'){$ct='<Types xmlns="'+$ctNs+'">'+$override.Replace($mime,'application/octet-stream')+'</Types>'}
    if($Case -eq 'wrong_default'){$ct='<Types xmlns="'+$ctNs+'">'+$default.Replace($mime,'application/octet-stream')+'</Types>'}
    if($Case -eq 'contradictory_override'){$ct='<Types xmlns="'+$ctNs+'">'+$default+$override.Replace($mime,'application/octet-stream')+'</Types>'}
    if($Case -eq 'override_precedence'){$ct='<Types xmlns="'+$ctNs+'">'+$default.Replace($mime,'application/octet-stream')+$override+'</Types>'}
    $model='<model xmlns="'+$mNs+'" unit="millimeter"><resources/><build/></model>'
    if($Case -eq 'payload_changed_valid'){$model=$model.Replace('unit="millimeter"','unit="inch"')}
    if($Case -eq 'model_dtd'){$model='<!DOCTYPE model SYSTEM "file:///never-open.xml">'+$model}
    if($Case -eq 'wrong_namespace'){$model=$model.Replace($mNs,'https://example.invalid/not-3mf')}
    if($Case -eq 'prefixed_xml'){
        $ct='<c:Types xmlns:c="'+$ctNs+'"><c:Override PartName="/'+$name+'" ContentType="'+$mime+'"/></c:Types>'
        $rels='<r:Relationships xmlns:r="'+$rNs+'"><r:Relationship Id="r0" Type="'+$start+'" Target="'+$target+'"/></r:Relationships>'
        $model='<m:model xmlns:m="'+$mNs+'" unit="millimeter"><m:resources/><m:build/></m:model>'
    }
    $parts=[ordered]@{'[Content_Types].xml'=$ct;'_rels/.rels'=$rels}
    $parts[$name]=$model
    if($Case -eq 'wrong_target_decoy'){
        $parts['3D/decoy.model']='<model xmlns="http://not-real.example.invalid"><resources/><build/></model>'
    }
    if($Case -eq 'extra_part'){$parts['Metadata/preview.png']='invented'}
    $ms=[IO.MemoryStream]::new()
    $archive=[IO.Compression.ZipArchive]::new($ms,[IO.Compression.ZipArchiveMode]::Create,$true)
    try {
        foreach($partName in $parts.Keys){
            $e=$archive.CreateEntry($partName,[IO.Compression.CompressionLevel]::Optimal)
            $e.LastWriteTime=[DateTimeOffset]::new(2020,1,1,0,0,0,[TimeSpan]::Zero)
            [byte[]]$payload=[Text.Encoding]::UTF8.GetBytes([string]$parts[$partName])
            $writer=$e.Open()
            try{$writer.Write($payload,0,$payload.Length)}finally{$writer.Dispose()}
        }
        if($Case -eq 'duplicate_zip_part'){
            $e=$archive.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
            $e.LastWriteTime=[DateTimeOffset]::new(2020,1,1,0,0,0,[TimeSpan]::Zero)
            [byte[]]$b=[Text.Encoding]::UTF8.GetBytes($model)
            $writer=$e.Open()
            try{$writer.Write($b,0,$b.Length)}finally{$writer.Dispose()}
        }
    }finally{$archive.Dispose()}
    [byte[]]$bytes=$ms.ToArray();$ms.Dispose()
    if($Case -eq 'crc_wrong'){
        $at=-1
        for($p=0;$p -le $bytes.Length-46;$p++){
            if([BitConverter]::ToUInt32($bytes,$p) -eq 0x02014b50){$at=$p;break}
        }
        Assert-C5OpcBreadth ($at -ge 0) 'artificial_CRC_mutation_has_cd'
        $bytes[$at+16]=[byte]($bytes[$at+16] -bxor 1)
    }
    return ,$bytes
}
function Invoke-C5OpcStartPartBreadthGate {
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $root 'modules\carving\Chappy.OpcEvidence.psm1') -Force
    $cases=@('canonical','alt_absolute','alt_relative','canonical_relative',
        'default_model','default_alt','prefixed_xml','extra_part',
        'override_precedence','payload_changed_valid',
        'nonexistent','traversal','encoded_traversal','external',
        'nested_start','duplicate_start','duplicate_id','duplicate_override',
        'wrong_override','duplicate_default','wrong_default',
        'contradictory_override','duplicate_zip_part','crc_wrong',
        'model_dtd','wrong_namespace','wrong_target_decoy')
    $positives=@('canonical','alt_absolute','alt_relative','canonical_relative',
        'default_model','default_alt','prefixed_xml','extra_part',
        'override_precedence','payload_changed_valid')
    $tp=0;$fp=0;$fn=0;$tn=0;$baselineTP=0;$baselineFP=0
    $baselineTN=0;$baselineFN=0;$source=0L;$unique=0L;$calls=0
    $parserB=0L;$xmlB=0L;$elapsed=0L;$shaExact=0;$shaDifferent=0
    $canonical=New-C5OpcBreadthZip -Case 'canonical'
    $originalSha=Get-C3mfFixtureSha $canonical
    foreach($case in $cases){
        [byte[]]$zip=New-C5OpcBreadthZip -Case $case
        Assert-C5OpcBreadth ($zip.Length -ge 128 -and $zip.Length -le 8192) ($case+':generated_package_size_cap')
        [byte[]]$img=[byte[]]::new(($zip.Length+512))
        [Array]::Copy($zip,0,$img,512,$zip.Length)
        $before=Get-C3mfFixtureSha $img
        $expected=($positives -ccontains $case)
        $offMeter=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($img,$false))
        try {
            $off=Get-Chappy3MfOpcEvidence -Stream $offMeter -OffsetBytes 512 -LengthBytes $zip.Length
            Assert-C5OpcBreadth ($off.status -eq 'disabled' -and
                $offMeter.BytesRead -eq 0 -and $offMeter.ReadCalls -eq 0 -and
                $offMeter.Position -eq 0) ($case+':disabled_ZERO_source_access')
        }finally{$offMeter.Dispose()}
        $baseMeter=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($img,$false))
        try {
            $bArgs=@{Stream=$baseMeter;StartOffset=512;MaxScanBytes=$zip.Length
                MaxFileBytes=8192;ExtraValidationReadBytes=16384;MaxCandidates=4
                MaxProbes=4;MaxProbeBytes=8192;EnableSmallDeflateCrc=$true}
            $baseline=Get-ChappyCarvingCandidates @bArgs
            $baseHit=(@($baseline.items|Where-Object {$_.offsetBytes -eq 512 -and
                $_.lengthBytes -eq $zip.Length -and $_.format -eq '3mf' -and
                $_.confidence -eq 'verified' -and $_.crc32Status -eq 'match'}).Count -eq 1)
            Assert-C5OpcBreadth ($baseline.metrics.bytesRead -eq $baseMeter.BytesRead -and
                $baseMeter.BytesRead -le 32768) ($case+':old_zip_structural_baseline_bounded')
            if($expected){if($baseHit){$baselineTP++}else{$baselineFN++}}
            else{if($baseHit){$baselineFP++}else{$baselineTN++}}
        }finally{$baseMeter.Dispose()}
        $meter=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($img,$false))
        try{
            $r=Get-Chappy3MfOpcEvidence -Stream $meter -OffsetBytes 512 -LengthBytes $zip.Length -EnableOpcXmlEvidence
            $m=$r.metrics
            Assert-C5OpcBreadth ($m.sourceBytesRead -eq $meter.BytesRead -and
                $m.readRequests -eq $meter.ReadCalls -and
                $m.sourceBytesRead -eq $zip.Length -and
                $meter.UniqueBytes -eq $zip.Length -and
                $m.sourceBytesRead -le 8192 -and
                $m.memoryValidatorBytesRead -le 32768 -and
                $m.inflatedXmlBytes -le 16384 -and
                $m.xmlPartsChecked -le 3 -and $m.zipEntriesChecked -le 8 -and
                $r.originalIdentity -eq 'unknown' -and
                $r.integrityScope -eq 'structural_only_not_original_file_integrity' -and
                $null -eq $r.PSObject.Properties['sourceToken'] -and
                $null -eq $r.PSObject.Properties['candidateSha256'] -and
                @($r.items).Count -eq 0) ($case+':source_reader_and_trust')
            $source+=$meter.BytesRead;$unique+=$meter.UniqueBytes;$calls+=$meter.ReadCalls
            $parserB += [long]$m.memoryValidatorBytesRead
            $xmlB += [long]$m.inflatedXmlBytes;$elapsed += [long]$m.elapsedMilliseconds
        }finally{$meter.Dispose()}
        $hit=($r.status -eq 'ok' -and $r.decision -eq 'opc_xml_consistent' -and $r.confidence -eq 'probable')
        if($expected){if($hit){$tp++}else{$fn++}}else{if($hit){$fp++}else{$tn++}}
        if($hit){
            if((Get-C3mfFixtureSha $zip) -ceq $originalSha){$shaExact++}else{$shaDifferent++}
            Assert-C5OpcBreadth (@($r.evidence).Count -ge 4 -and @($r.warnings).Count -eq 0) ($case+':structural_only_success')
        }else{
            Assert-C5OpcBreadth ($r.status -eq 'partial' -and $r.decision -eq 'unknown' -and
                $r.confidence -eq 'unknown' -and @($r.evidence).Count -eq 0) ($case+':unsafe_unknown')
        }
        Assert-C5OpcBreadth ((Get-C3mfFixtureSha $img) -ceq $before) ($case+':source_SHA_unchanged')
        Write-Host ('C5-01 BREADTH case={0} truth={1} priorZIP={2} OPC={3} sourceB={4} uniqueB={5} calls={6} parserB={7} xmlB={8}' -f
            $case,$expected,$baseHit,$hit,$m.sourceBytesRead,$zip.Length,$m.readRequests,$m.memoryValidatorBytesRead,$m.inflatedXmlBytes)
    }
    Assert-C5OpcBreadth ($cases.Count -eq 27 -and $positives.Count -eq 10 -and
        $tp -eq 10 -and $fn -eq 0 -and $fp -eq 0 -and $tn -eq 17 -and
        $shaExact -eq 1 -and $shaDifferent -eq 9 -and
        $baselineTP -ge 8 -and $baselineFP -ge 4) 'frozen_positive_negative_crc_decoy_truth'
    # On a real short read / true EOF preserve only 17 returned bytes, UNKNOWN.
    [byte[]]$good=New-C5OpcBreadthZip -Case 'alt_relative'
    $short=[ChappyC3mf17Eof]::new([IO.MemoryStream]::new($good,$false))
    try{
        $r=Get-Chappy3MfOpcEvidence -Stream $short -OffsetBytes 0 -LengthBytes $good.Length -EnableOpcXmlEvidence
        Assert-C5OpcBreadth ($r.status -eq 'partial' -and $r.decision -eq 'unknown' -and
            $r.metrics.sourceBytesRead -eq 17 -and $r.metrics.readRequests -eq $short.Calls -and
            $short.Calls -eq 2 -and @($r.evidence).Count -eq 0) '17B_then_real_EOF_does_not_promote'
    }finally{$short.Dispose()}
    $under=[ChappyCFragmentMeter]::new([IO.MemoryStream]::new($good,$false))
    try{
        $r=Get-Chappy3MfOpcEvidence -Stream $under -OffsetBytes 0 -LengthBytes $good.Length -EnableOpcXmlEvidence -MaxSourceBytes 1
        Assert-C5OpcBreadth ($r.status -eq 'partial' -and $under.BytesRead -eq 0 -and $under.ReadCalls -eq 0) 'underquota_zero_actual_IO'
    }finally{$under.Dispose()}
    $writable=[IO.MemoryStream]::new($good,$true)
    try {
        $r=Get-Chappy3MfOpcEvidence -Stream $writable -LengthBytes $good.Length -EnableOpcXmlEvidence
        Assert-C5OpcBreadth ($r.status -eq 'partial' -and $r.decision -eq 'unknown' -and
            $r.metrics.sourceBytesRead -eq 0 -and $writable.Position -eq 0) 'writable_refused_without_read'
    }finally{$writable.Dispose()}
    Write-Host ('C5-01 BREADTH SUMMARY cases={0} baselineZIP_TP={1} FP={2} FN={3} TN={4} new_TP={5} FP={6} FN={7} TN={8} original_SHA_exact={9} structural_but_SHA_different={10} physicalB={11} uniqueB={12} calls={13} parserMemoryB={14} XMLInflatedB={15} elapsedMs={16} falseOriginalClaims=0' -f
        $cases.Count,$baselineTP,$baselineFP,$baselineFN,$baselineTN,$tp,$fp,$fn,$tn,
        $shaExact,$shaDifferent,$source,$unique,$calls,$parserB,$xmlB,$elapsed)
    Write-Host 'PASS: C5-01 dynamic OPC target+mime breadth, decoy rejection, bounded physical I/O and original identity UNKNOWN'
}
