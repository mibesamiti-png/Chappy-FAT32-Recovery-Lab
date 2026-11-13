#requires -Version 5.1
# C5-01: independent synthetic ZIP/3MF OPC/XML scorer. No real files.
function Assert-C3mfOpc([bool]$Valid,[string]$Message) {
    if(-not $Valid){throw ('C5_01_OPC_FAIL: '+$Message)}
}
if(-not ('ChappyC3mf17Eof' -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class ChappyC3mf17Eof:Stream {
 private readonly Stream s;private bool served;
 public long Returned{get;private set;}
 public int Calls{get;private set;}
 public ChappyC3mf17Eof(Stream x){if(x.CanWrite)throw new ArgumentException();s=x;}
 public override bool CanRead{get{return true;}}
 public override bool CanSeek{get{return true;}}
 public override bool CanWrite{get{return false;}}
 public override long Length{get{return s.Length;}}
 public override long Position{get{return s.Position;}set{s.Position=value;}}
 public override int Read(byte[] b,int o,int n){Calls++;if(served)return 0;served=true;int v=s.Read(b,o,Math.Min(n,17));Returned+=v;return v;}
 public override long Seek(long p,SeekOrigin o){return s.Seek(p,o);}
 public override void Flush(){}
 public override void SetLength(long n){throw new NotSupportedException();}
 public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
 protected override void Dispose(bool d){if(d)s.Dispose();base.Dispose(d);}
}
'@
}
function Get-C3mfFixtureSha([byte[]]$Bytes) {
    $hasher=[Security.Cryptography.SHA256]::Create()
    try {return [BitConverter]::ToString($hasher.ComputeHash($Bytes)).Replace('-','')}
    finally{$hasher.Dispose()}
}
function New-C3mfOpcSyntheticZip {
    param([string]$Case)
    Add-Type -AssemblyName System.IO.Compression
    $typeXml='<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/3D/3dmodel.model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/></Types>'
    $relXml='<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="r0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="/3D/3dmodel.model"/></Relationships>'
    $modelXml='<model xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" unit="millimeter"><resources/><build/></model>'
    switch($Case){
        'model_xml_invalid' {$modelXml='<model><resources>'}
        'wrong_relationship_target' {$relXml=$relXml.Replace('/3D/3dmodel.model','/3D/missing.model')}
        'wrong_content_type' {$typeXml=$typeXml.Replace('application/vnd.ms-package.3dmanufacturing-3dmodel+xml','application/octet-stream')}
        'missing_startpart' {$relXml='<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships" />'}
        'duplicate_startpart' {$relXml=$relXml.Replace('</Relationships>','<Relationship Id="r1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="/3D/3dmodel.model"/></Relationships>')}
        'model_with_external_dtd' {$modelXml='<!DOCTYPE model SYSTEM "file:///sensitive.xml"><model xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02"><resources/><build/></model>'}
        'model_payload_changed' {$modelXml=$modelXml.Replace('unit="millimeter"','unit="inch"')}
        'oversized_model_xml' {$modelXml=$modelXml.Replace('<resources/>',('<resources/><!--'+('X'*9000)+'-->'))}
    }
    $parts=[ordered]@{'[Content_Types].xml'=$typeXml;'_rels/.rels'=$relXml;'3D/3dmodel.model'=$modelXml}
    if($Case -eq 'missing_model_part'){$parts.Remove('3D/3dmodel.model')}
    if($Case -eq 'plain_zip'){$parts=[ordered]@{'synthetic_not_a_3mf_file_with_a_longer_name.txt'='invented'}}
    $mem=[IO.MemoryStream]::new()
    $zip=[IO.Compression.ZipArchive]::new($mem,[IO.Compression.ZipArchiveMode]::Create,$true)
    try{
        foreach($name in $parts.Keys){
            $entry=$zip.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime=[DateTimeOffset]::new(2020,1,1,0,0,0,[TimeSpan]::Zero)
            [byte[]]$body=[Text.Encoding]::UTF8.GetBytes($parts[$name])
            $output=$entry.Open()
            try{$output.Write($body,0,$body.Length)}finally{$output.Dispose()}
        }
    }finally{$zip.Dispose()}
    [byte[]]$bytes=$mem.ToArray()
    $mem.Dispose()
    if($Case -eq 'crc_payload_corrupt'){
        # Alter a compressed local member without adjusting the ZIP central CRC.
        Assert-C3mfOpc ([BitConverter]::ToUInt32($bytes,0) -eq 0x04034b50) 'synthetic_local_zip_marker'
        $nameSize=[BitConverter]::ToUInt16($bytes,26)
        $extraSize=[BitConverter]::ToUInt16($bytes,28)
        $at=30+$nameSize+$extraSize
        Assert-C3mfOpc ($at -lt ($bytes.Length-100)) 'synthetic_crc_mutation_offset'
        $bytes[$at]=[byte]($bytes[$at] -bxor 1)
    }
    return ,$bytes
}
function Invoke-C3mfOpcGateRegression {
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $root 'modules\carving\Chappy.OpcEvidence.psm1') -Force
    $names=@('clean','model_xml_invalid','wrong_relationship_target','wrong_content_type',
        'missing_startpart','duplicate_startpart','missing_model_part',
        'model_with_external_dtd','model_payload_changed','plain_zip',
        'crc_payload_corrupt','oversized_model_xml')
    $canonical=New-C3mfOpcSyntheticZip -Case 'clean'
    $canonicalSha=Get-C3mfFixtureSha $canonical
    $newTP=0;$newTN=0;$newFP=0;$newFN=0
    $baseTP=0;$baseTN=0;$baseFP=0;$baseFN=0
    $shaExact=0;$shaDifferent=0;$phys=0L;$calls=0
    $memoryValidation=0L;$inflated=0L;$elapsed=0L
    foreach($case in $names){
        [byte[]]$zip=New-C3mfOpcSyntheticZip -Case $case
        Assert-C3mfOpc ($zip.Length -ge 128 -and $zip.Length -le 8192) ($case+':fixture_under_cap')
        [byte[]]$image=[byte[]]::new(($zip.Length+512))
        [Array]::Copy($zip,0,$image,512,$zip.Length)
        $sha=Get-C3mfFixtureSha $image
        $label=($case -in @('clean','model_payload_changed'))
        $offSource=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($image,$false))
        try{
            $off=Get-Chappy3MfOpcEvidence -Stream $offSource -OffsetBytes 512 -LengthBytes $zip.Length
            Assert-C3mfOpc ($off.status -eq 'disabled' -and $offSource.BytesRead -eq 0 -and @($off.items).Count -eq 0) ($case+':default_off_zero_source_io')
        }finally{$offSource.Dispose()}
        $baseSource=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($image,$false))
        try {
            $base=Get-ChappyCarvingCandidates -Stream $baseSource -StartOffset 512 -MaxScanBytes $zip.Length -MaxFileBytes 8192 -ExtraValidationReadBytes 16384 -MaxCandidates 4 -MaxProbes 4 -MaxProbeBytes 8192 -EnableSmallDeflateCrc
            Assert-C3mfOpc ($base.metrics.bytesRead -eq $baseSource.BytesRead -and $baseSource.BytesRead -le 32768) ($case+':same_baseline_source_counter')
            $baseHit=(@($base.items|Where-Object {$_.format -eq '3mf' -and $_.offsetBytes -eq 512 -and $_.lengthBytes -eq $zip.Length -and $_.confidence -eq 'verified' -and $_.crc32Status -eq 'match'}).Count -eq 1)
        }finally{$baseSource.Dispose()}
        if($label){if($baseHit){$baseTP++}else{$baseFN++}}else{if($baseHit){$baseFP++}else{$baseTN++}}
        $read=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($image,$false))
        try{
            $r=Get-Chappy3MfOpcEvidence -Stream $read -OffsetBytes 512 -LengthBytes $zip.Length -EnableOpcXmlEvidence
            Assert-C3mfOpc ($r.metrics.sourceBytesRead -eq $read.BytesRead -and
                $read.BytesRead -le 8192 -and $r.metrics.readRequests -ge 1 -and
                $r.metrics.maxSourceBufferBytes -eq 8192 -and
                $r.metrics.memoryValidatorBytesRead -le 32768 -and
                $r.metrics.inflatedXmlBytes -le 16384 -and
                $r.metrics.zipEntriesChecked -le 8 -and $r.metrics.xmlPartsChecked -le 3 -and
                $r.originalIdentity -eq 'unknown' -and
                $r.integrityScope -eq 'structural_only_not_original_file_integrity' -and
                $null -eq $r.PSObject.Properties['sourceToken'] -and
                @($r.items).Count -eq 0 -and -not $read.CanWrite) ($case+':actual_io_bounds_and_original_scope')
            $phys+=$read.BytesRead;$calls+=$r.metrics.readRequests
            $memoryValidation+=$r.metrics.memoryValidatorBytesRead
            $inflated+=$r.metrics.inflatedXmlBytes
            $elapsed+=$r.metrics.elapsedMilliseconds
        }finally{$read.Dispose()}
        $hit=($r.status -eq 'ok' -and $r.decision -eq 'opc_xml_consistent')
        if($label){if($hit){$newTP++}else{$newFN++}}else{if($hit){$newFP++}else{$newTN++}}
        if($hit){
            Assert-C3mfOpc ($r.confidence -eq 'probable' -and
                $r.evidence -contains 'opc.root_startpart') ($case+':only_structural_verdict')
            if((Get-C3mfFixtureSha $zip) -ceq $canonicalSha){$shaExact++}else{$shaDifferent++}
        }else{
            Assert-C3mfOpc ($r.status -eq 'partial' -and $r.decision -eq 'unknown' -and
                @($r.evidence).Count -eq 0) ($case+':unsafe_xml_must_remain_unknown')
        }
        Assert-C3mfOpc ((Get-C3mfFixtureSha $image) -ceq $sha) ($case+':input_SHA_not_modified')
        Write-Host ('C5-01 OPC case={0} truth={1} baseline={2} guarded={3} sourceB={4} calls={5} zipParserB={6} xmlB={7}' -f
            $case,$label,$baseHit,$hit,$r.metrics.sourceBytesRead,$r.metrics.readRequests,$r.metrics.memoryValidatorBytesRead,$r.metrics.inflatedXmlBytes)
    }
    Assert-C3mfOpc ($names.Count -eq 12 -and $newTP -eq 2 -and $newFP -eq 0 -and
        $newFN -eq 0 -and $newTN -eq 10 -and $shaExact -eq 1 -and $shaDifferent -eq 1) 'frozen_twelve_case_OPC_truth'
    Assert-C3mfOpc ($baseFP -gt 0 -and $baseTP -ge 1 -and $baseTP+$baseTN+$baseFP+$baseFN -eq 12) 'baseline_filename_only_false_opc_inference'
    # Additional negative source-read and trust tests use the same clean corpus.
    [byte[]]$good=New-C3mfOpcSyntheticZip -Case 'clean'
    $short=[ChappyC3mf17Eof]::new([IO.MemoryStream]::new($good,$false))
    try{
        $r=Get-Chappy3MfOpcEvidence -Stream $short -OffsetBytes 0 -LengthBytes $good.Length -EnableOpcXmlEvidence
        Assert-C3mfOpc ($r.status -eq 'partial' -and $r.decision -eq 'unknown' -and
            $short.Returned -eq 17 -and $short.Calls -eq $r.metrics.readRequests -and $r.metrics.sourceBytesRead -eq 17) '17B_true_EOF_no_original'
    }finally{$short.Dispose()}
    $under=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($good,$false))
    try{
        $r=Get-Chappy3MfOpcEvidence -Stream $under -LengthBytes $good.Length -MaxSourceBytes 1 -EnableOpcXmlEvidence
        Assert-C3mfOpc ($r.status -eq 'partial' -and $under.BytesRead -eq 0) 'underquota_zero_IO'
        $r=Get-Chappy3MfOpcEvidence -Stream $under -OffsetBytes ($good.Length-1) -LengthBytes $good.Length -EnableOpcXmlEvidence
        Assert-C3mfOpc ($r.status -eq 'partial' -and $under.BytesRead -eq 0) 'out_of_source_span_zero_IO'
    }finally{$under.Dispose()}
    $writable=[IO.MemoryStream]::new($good,$true)
    try{
        $r=Get-Chappy3MfOpcEvidence -Stream $writable -LengthBytes $good.Length -EnableOpcXmlEvidence
        Assert-C3mfOpc ($r.status -eq 'partial' -and $r.decision -eq 'unknown' -and $r.metrics.sourceBytesRead -eq 0) 'writable_stream_never_read'
    }finally{$writable.Dispose()}
    Write-Host ('C5-01 OPC SUMMARY cases={0} baseline_TP={1} FP={2} FN={3} TN={4} new_TP={5} FP={6} FN={7} TN={8} original_SHA_exact={9} structural_but_sha_different={10} source_B={11} source_calls={12} zip_memory_validator_B={13} inflated_xml_B={14} elapsed_ms={15} original_claims=0' -f
        $names.Count,$baseTP,$baseFP,$baseFN,$baseTN,$newTP,$newFP,$newFN,$newTN,$shaExact,$shaDifferent,$phys,$calls,$memoryValidation,$inflated,$elapsed)
    Write-Host 'PASS: C5-01 bounded optional ZIP/3MF OPC XML checks and CRC/DTD/EOF adversarial fixture matrix'
}
