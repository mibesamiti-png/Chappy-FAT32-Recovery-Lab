#requires -Version 5.1
# Team C R5/C5-01: bounded opt-in OPC XML evidence on a caller-supplied
# candidate extent. Not discovery, original authentication, or extraction.
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.Xml

function Read-C3MfBoundedXml {
    param([System.IO.Compression.ZipArchiveEntry]$Entry,[int]$MaxXmlBytes=8192)
    if ($null -eq $Entry -or $Entry.Length -le 0 -or $Entry.Length -gt $MaxXmlBytes -or
        $Entry.CompressedLength -gt 8192) {throw 'opc.xml_size_outside_bound'}
    $opened=$Entry.Open()
    try {
        [byte[]]$bytes=New-Object byte[] ($MaxXmlBytes+1)
        $done=0
        while ($done -lt $bytes.Length) {
            $n=$opened.Read($bytes,$done,($bytes.Length-$done))
            if ($n -le 0) {break}
            $done+=$n
        }
        if ($done -ne $Entry.Length -or $done -gt $MaxXmlBytes) {throw 'opc.xml_inflate_length_conflict'}
    } finally {$opened.Dispose()}
    $input=[IO.MemoryStream]::new($bytes,0,$done,$false)
    try {
        $settings=[Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver=$null
        $settings.MaxCharactersFromEntities=0
        $settings.MaxCharactersInDocument=16384L
        $settings.IgnoreComments=$true
        $reader=[Xml.XmlReader]::Create($input,$settings)
        try {
            $xml=[Xml.XmlDocument]::new()
            $xml.XmlResolver=$null
            $xml.Load($reader)
            return [pscustomobject]@{xml=$xml;inflatedBytes=[long]$done}
        } finally {$reader.Dispose()}
    } finally {$input.Dispose()}
}

function Get-Chappy3MfOpcEvidence {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [switch]$EnableOpcXmlEvidence,
        [ValidateRange(0,9223372036854775806)][long]$OffsetBytes=0,
        [ValidateRange(128,8192)][int]$LengthBytes=8192,
        [ValidateRange(1,8192)][long]$MaxSourceBytes=8192,
        [ValidateRange(100,30000)][int]$MaxWorkMilliseconds=30000
    )
    $metrics=[pscustomobject]@{
        sourceBytesRead=0L;readRequests=0;memoryValidatorBytesRead=0L
        inflatedXmlBytes=0L;zipEntriesChecked=0;xmlPartsChecked=0
        elapsedMilliseconds=0;maxSourceBufferBytes=8192
    }
    $result=[ordered]@{
        schemaVersion='1';team='C';status='disabled';decision='unknown'
        confidence='unknown';integrityScope='structural_only_not_original_file_integrity'
        originalIdentity='unknown';offsetBytes=$OffsetBytes;lengthBytes=[long]$LengthBytes
        evidence=@();warnings=@('opc.optin_required');items=@();metrics=$metrics
    }
    if (-not $EnableOpcXmlEvidence) {return [pscustomobject]$result}
    $result.status='partial';$result.warnings=@('opc.incomplete_or_unsupported')
    if (-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite) {
        $result.warnings=@('opc.readonly_stream_required')
        return [pscustomobject]$result
    }
    if ($OffsetBytes -gt ($Stream.Length-[long]$LengthBytes) -or
        $MaxSourceBytes -lt [long]$LengthBytes) {
        $result.warnings=@('opc.span_or_quota_unavailable')
        return [pscustomobject]$result
    }
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $zip=$null;$memory=$null
    try {
        [byte[]]$buffer=New-Object byte[] $LengthBytes
        [void]$Stream.Seek($OffsetBytes,[IO.SeekOrigin]::Begin)
        $done=0
        while ($done -lt $LengthBytes) {
            if ($timer.ElapsedMilliseconds -ge $MaxWorkMilliseconds) {throw 'opc.timeout'}
            $n=$Stream.Read($buffer,$done,($LengthBytes-$done))
            $metrics.readRequests++
            if ($n -le 0) {throw 'opc.short_source'}
            $metrics.sourceBytesRead += [long]$n
            $done+=$n
        }
        $memory=[IO.MemoryStream]::new($buffer,$false)
        # Reuse the existing C ZIP local/central/EOCD and CRC checker.
        Import-Module (Join-Path $PSScriptRoot 'Chappy.Carving.psm1') -ErrorAction Stop
        $scanArgs=@{
            Stream=$memory;StartOffset=0;MaxScanBytes=$LengthBytes;MaxFileBytes=8192
            ExtraValidationReadBytes=16384;MaxCandidates=4;MaxProbes=4
            MaxProbeBytes=8192;EnableSmallDeflateCrc=$true
            MaxWorkMilliseconds=[int][Math]::Max(100,($MaxWorkMilliseconds-$timer.ElapsedMilliseconds))
        }
        $scan=Get-ChappyCarvingCandidates @scanArgs
        $metrics.memoryValidatorBytesRead=[long]$scan.metrics.bytesRead
        $qualified=@($scan.items | Where-Object {
            $_.offsetBytes -eq 0 -and $_.lengthBytes -eq $LengthBytes -and
            $_.format -eq '3mf' -and $_.confidence -eq 'verified' -and
            $_.crc32Status -eq 'match' -and
            $_.integrityScope -eq 'structural_only_not_original_file_integrity'
        })
        if ($qualified.Count -ne 1 -or $scan.scanIncomplete -or
            $metrics.memoryValidatorBytesRead -gt 32768L) {
            throw 'opc.zip_crc_or_structure_unconfirmed'
        }
        [void]$memory.Seek(0,[IO.SeekOrigin]::Begin)
        $zip=[IO.Compression.ZipArchive]::new($memory,[IO.Compression.ZipArchiveMode]::Read,$true)
        $all=@($zip.Entries)
        if ($all.Count -lt 3 -or $all.Count -gt 8) {throw 'opc.zip_entry_limit'}
        $metrics.zipEntriesChecked=$all.Count
        # Unique package entry names prevent an attacker from shadowing a
        # referenced part in different ZIP libraries. Case-fold collisions
        # are conservative UNKNOWN (this small profile is deliberately strict).
        $parts=@{};$declaredTotal=0L
        foreach($entry in $all){
            $name=[string]$entry.FullName
            if($name.Length -gt 128 -or $name.Contains('..') -or $name.Contains('\') -or
                $name.StartsWith('/') -or $name.Contains(':') -or
                $entry.Length -gt 32768 -or $entry.CompressedLength -gt 8192){
                throw 'opc.part_name_or_size'
            }
            if($parts.ContainsKey($name)){throw 'opc.duplicate_zip_part'}
            $parts[$name]=$entry
            $declaredTotal += [long]$entry.Length
            if($declaredTotal -gt 32768L){throw 'opc.package_expansion_limit'}
        }
        foreach($name in @('[Content_Types].xml','_rels/.rels')){
            if(-not $parts.ContainsKey($name)){throw 'opc.required_metadata_missing'}
        }
        $xmlTotal=0L;$docs=@{}
        foreach($name in @('[Content_Types].xml','_rels/.rels')){
            if($timer.ElapsedMilliseconds -ge $MaxWorkMilliseconds){throw 'opc.timeout'}
            $part=Read-C3MfBoundedXml -Entry $parts[$name] -MaxXmlBytes 8192
            $xmlTotal += [long]$part.inflatedBytes
            if($xmlTotal -gt 16384L){throw 'opc.xml_total_limit'}
            $docs[$name]=$part.xml
            $metrics.xmlPartsChecked++
        }
        $typesNs='http://schemas.openxmlformats.org/package/2006/content-types'
        $relsNs='http://schemas.openxmlformats.org/package/2006/relationships'
        $modelNs='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'
        $startPart='http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel'
        $modelType='application/vnd.ms-package.3dmanufacturing-3dmodel+xml'
        $types=$docs['[Content_Types].xml'];$rels=$docs['_rels/.rels']
        if($null -eq $types.DocumentElement -or $types.DocumentElement.LocalName -cne 'Types' -or
            $types.DocumentElement.NamespaceURI -cne $typesNs -or
            $null -eq $rels.DocumentElement -or $rels.DocumentElement.LocalName -cne 'Relationships' -or
            $rels.DocumentElement.NamespaceURI -cne $relsNs){
            throw 'opc.metadata_xml_root_mismatch'
        }
        # OPC package-root relationships target exactly ONE primary 3D model.
        # Valid root Targets can be '/3D/build.model' or '3D/build.model'.
        # Reject external/scheme/traversal/percent-query names; no URL resolving.
        $startHits=0;$chosenModel=$null
        $seenIds=@{}
        foreach($node in $rels.DocumentElement.ChildNodes){
            if($node.NodeType -ne [Xml.XmlNodeType]::Element){continue}
            if($node.LocalName -cne 'Relationship' -or $node.NamespaceURI -cne $relsNs){
                throw 'opc.relationship_child_invalid'
            }
            $id=$node.GetAttribute('Id')
            if($id -cnotmatch '^[A-Za-z_][A-Za-z0-9_.-]{0,63}$' -or
                $seenIds.ContainsKey($id)){throw 'opc.relationship_id_invalid_or_duplicate'}
            $seenIds[$id]=$true
            if($node.GetAttribute('Type') -cne $startPart){continue}
            $startHits++
            if($startHits -gt 1){throw 'opc.startpart_ambiguous'}
            $target=$node.GetAttribute('Target')
            if($target -cnotmatch '^/?3D/[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\.model$' -or
                $target.Contains('..') -or
                ($node.HasAttribute('TargetMode') -and
                 $node.GetAttribute('TargetMode') -cne 'Internal')){
                throw 'opc.invalid_startpart_target'
            }
            $chosenModel=$target.TrimStart([char]'/')
        }
        if($startHits -ne 1 -or $null -eq $chosenModel -or
            -not $parts.ContainsKey($chosenModel)){throw 'opc.model_startpart_missing'}
        # Resolve effective content type by exact Override first, then
        # Default Extension='model'. Reject duplicate/conflicting declarations
        # rather than accepting one correct value among contradictory ones.
        $seenOverrides=@{};$seenDefaults=@{}
        $overridden=$false;$overrideMime=$null;$defaultMime=$null
        foreach($node in $types.DocumentElement.ChildNodes){
            if($node.NodeType -ne [Xml.XmlNodeType]::Element){continue}
            if($node.NamespaceURI -cne $typesNs){throw 'opc.types_child_namespace'}
            if($node.LocalName -ceq 'Override'){
                $partName=$node.GetAttribute('PartName')
                $mime=$node.GetAttribute('ContentType')
                if([string]::IsNullOrWhiteSpace($partName) -or
                    [string]::IsNullOrWhiteSpace($mime) -or
                    $seenOverrides.ContainsKey($partName)){throw 'opc.override_invalid_or_duplicate'}
                $seenOverrides[$partName]=$true
                if($partName -ceq ('/'+$chosenModel)){
                    $overridden=$true;$overrideMime=$mime
                }
            }elseif($node.LocalName -ceq 'Default'){
                $ext=$node.GetAttribute('Extension')
                $mime=$node.GetAttribute('ContentType')
                if([string]::IsNullOrWhiteSpace($ext) -or
                    [string]::IsNullOrWhiteSpace($mime) -or
                    $seenDefaults.ContainsKey($ext)){throw 'opc.default_invalid_or_duplicate'}
                $seenDefaults[$ext]=$true
                if($ext -ceq 'model'){$defaultMime=$mime}
            }else{throw 'opc.content_type_child_invalid'}
        }
        $effectiveMime=if($overridden){$overrideMime}else{$defaultMime}
        if($effectiveMime -cne $modelType){throw 'opc.model_content_type_invalid'}
        # Validate the referenced XML, never a coincidentally named decoy.
        if($timer.ElapsedMilliseconds -ge $MaxWorkMilliseconds){throw 'opc.timeout'}
        $part=Read-C3MfBoundedXml -Entry $parts[$chosenModel] -MaxXmlBytes 8192
        $xmlTotal += [long]$part.inflatedBytes
        if($xmlTotal -gt 16384L){throw 'opc.xml_total_limit'}
        $model=$part.xml
        $metrics.xmlPartsChecked++
        $metrics.inflatedXmlBytes=$xmlTotal
        if($null -eq $model.DocumentElement -or
            $model.DocumentElement.LocalName -cne 'model' -or
            $model.DocumentElement.NamespaceURI -cne $modelNs){
            throw 'opc.model_root_invalid'
        }
        $resources=@($model.DocumentElement.ChildNodes|Where-Object {
            $_.NodeType -eq [Xml.XmlNodeType]::Element -and $_.LocalName -eq 'resources' -and $_.NamespaceURI -ceq $modelNs
        })
        $build=@($model.DocumentElement.ChildNodes|Where-Object {
            $_.NodeType -eq [Xml.XmlNodeType]::Element -and $_.LocalName -eq 'build' -and $_.NamespaceURI -ceq $modelNs
        })
        if ($resources.Count -ne 1 -or $build.Count -ne 1) {throw 'opc.model_sections_missing'}
        if ($timer.ElapsedMilliseconds -ge $MaxWorkMilliseconds) {throw 'opc.timeout'}
        $result.status='ok';$result.decision='opc_xml_consistent';$result.confidence='probable'
        $result.evidence=@('zip.crc_checked','opc.content_type','opc.root_startpart','opc.model_root_xml','opc.dtd_prohibited')
        $result.warnings=@()
    } catch {
        # Never reflect parser errors, hostile archive names or private XML data.
        $result.status='partial';$result.decision='unknown';$result.confidence='unknown'
        $result.evidence=@();$result.warnings=@('opc.incomplete_or_unsupported')
    } finally {
        if ($null -ne $zip) {$zip.Dispose()}
        if ($null -ne $memory) {$memory.Dispose()}
        $timer.Stop();$metrics.elapsedMilliseconds=[int]$timer.ElapsedMilliseconds
    }
    return [pscustomobject]$result
}
Export-ModuleMember -Function Get-Chappy3MfOpcEvidence
