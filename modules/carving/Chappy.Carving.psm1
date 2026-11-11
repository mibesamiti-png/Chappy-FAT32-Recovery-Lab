#requires -Version 5.1
Set-StrictMode -Version Latest
$script:CStoredCrcTable = $null

function Read-CBytes {
    param([IO.Stream]$Stream, [long]$Offset, [int]$Count)
    if ($Offset -lt 0 -or $Count -lt 0 -or $Offset -gt ($Stream.Length - [long]$Count)) { return $null }
    [void]$Stream.Seek($Offset, [IO.SeekOrigin]::Begin)
    $bytes = New-Object byte[] $Count
    $n = 0
    while ($n -lt $Count) {
        $got = $Stream.Read($bytes, $n, $Count - $n)
        if ($got -le 0) { return $null }
        $n += $got
    }
    return ,$bytes
}
function Get-CU16 { param([byte[]]$Bytes,[int]$At) return [BitConverter]::ToUInt16($Bytes,$At) }
function Get-CU32 { param([byte[]]$Bytes,[int]$At) return [BitConverter]::ToUInt32($Bytes,$At) }

function Find-CSignature {
    param([IO.Stream]$Stream,[long]$Start,[long]$Length,[byte[]]$Signature,[int]$Limit=256)
    $hits = New-Object 'System.Collections.Generic.List[long]'
    $end = [Math]::Min($Stream.Length, $Start + $Length)
    $cursor = $Start
    $tail = New-Object byte[] 0
    while ($cursor -lt $end -and $hits.Count -lt $Limit) {
        $want = [int][Math]::Min(65536L, $end - $cursor)
        $block = Read-CBytes $Stream $cursor $want
        if ($null -eq $block) { break }
        $combined = New-Object byte[] ($tail.Length + $block.Length)
        [Array]::Copy($tail,0,$combined,0,$tail.Length)
        [Array]::Copy($block,0,$combined,$tail.Length,$block.Length)
        $base = $cursor - $tail.Length
        $i = 0
        while ($i -le $combined.Length - $Signature.Length -and $hits.Count -lt $Limit) {
            $found = [Array]::IndexOf($combined,$Signature[0],$i)
            if ($found -lt 0 -or $found -gt $combined.Length - $Signature.Length) { break }
            $ok = $true
            for ($k=1; $k -lt $Signature.Length; $k++) {
                if ($combined[$found+$k] -ne $Signature[$k]) { $ok=$false; break }
            }
            if ($ok -and ($base+$found) -ge $Start) { $hits.Add($base+$found) }
            $i = $found + 1
        }
        $retain = [Math]::Min($Signature.Length-1,$combined.Length)
        $tail = New-Object byte[] $retain
        if ($retain -gt 0) { [Array]::Copy($combined,$combined.Length-$retain,$tail,0,$retain) }
        $cursor += $want
    }
    return $hits.ToArray()
}


# Bounded CRC32 for ZIP STORED (method 0) entries only.
# This is content evidence, never proof of the original filesystem's integrity.
function Get-CStoredCrc32 {
    param([IO.Stream]$Stream,[long]$Offset,[long]$Length)
    if ($Length -lt 0 -or $Length -gt 65536L -or $Offset -lt 0 -or $Offset -gt ($Stream.Length-$Length)) { return $null }
    if ($null -eq $script:CStoredCrcTable) {
        $script:CStoredCrcTable = New-Object 'uint32[]' 256
        for ($n=0; $n -lt 256; $n++) {
            $c=[uint32]$n
            for ($k=0; $k -lt 8; $k++) {
                if (($c -band 1) -ne 0) { $c=[uint32](($c -shr 1) -bxor 3988292384L) }
                else { $c=[uint32]($c -shr 1) }
            }
            $script:CStoredCrcTable[$n]=$c
        }
    }
    $crc=[uint32]4294967295L
    $cursor=$Offset; $remaining=$Length
    while ($remaining -gt 0) {
        $take=[int][Math]::Min(16384L,$remaining)
        $bytes=Read-CBytes $Stream $cursor $take
        if ($null -eq $bytes) { return $null }
        foreach ($b in $bytes) {
            $index=[int](($crc -bxor [uint32]$b) -band 255L)
            $crc=[uint32](($crc -shr 8) -bxor $script:CStoredCrcTable[$index])
        }
        $cursor+=$take; $remaining-=$take
    }
    return [uint32]($crc -bxor 4294967295L)
}

function Test-CZip {
    param([IO.Stream]$Stream,[long]$Offset,[long]$MaxFileBytes)
    $first = Read-CBytes $Stream $Offset 30
    if ($null -eq $first -or (Get-CU32 $first 0) -ne 0x04034b50) { return $null }
    $flags = Get-CU16 $first 6
    $method = Get-CU16 $first 8
    $firstNameLength = Get-CU16 $first 26
    if (($flags -band 1) -ne 0 -or $method -notin @(0,8) -or $firstNameLength -eq 0) { return $null }
    $limit=[Math]::Min($MaxFileBytes,$Stream.Length-$Offset)
    if ($limit -lt 52) { return $null }
    $endMarkers = @(Find-CSignature $Stream ($Offset+30) ($limit-30) ([byte[]](0x50,0x4b,0x05,0x06)) 128)
    foreach ($eocd in $endMarkers) {
        $endRec = Read-CBytes $Stream $eocd 22
        if ($null -eq $endRec) { continue }
        $commentSize = [long](Get-CU16 $endRec 20)
        $endOffset = $eocd + 22L + $commentSize
        if ($endOffset -gt ($Offset+$limit)) { continue }
        $entries = [int](Get-CU16 $endRec 10)
        $cdSize = [long](Get-CU32 $endRec 12)
        $cdRel = [long](Get-CU32 $endRec 16)
        if ((Get-CU16 $endRec 4) -ne 0 -or (Get-CU16 $endRec 6) -ne 0 -or
            (Get-CU16 $endRec 8) -ne $entries -or $entries -lt 1 -or $entries -gt 4096 -or
            $cdSize -eq 0 -or $cdRel -eq 0xffffffffL -or $cdSize -eq 0xffffffffL -or
            $cdRel + $cdSize -ne ($eocd - $Offset)) { continue }
        $pos = $Offset + $cdRel
        $cdEnd = $pos + $cdSize
        $valid = $true
        $crcChecked=0; $crcUnchecked=0; $crcMismatch=$false; $crcBudget=65536L
        $names = New-Object 'System.Collections.Generic.List[string]'
        for ($j=0; $j -lt $entries; $j++) {
            $entry = Read-CBytes $Stream $pos 46
            if ($null -eq $entry -or (Get-CU32 $entry 0) -ne 0x02014b50) { $valid=$false; break }
            $eflags = Get-CU16 $entry 8
            $emode = Get-CU16 $entry 10
            $comp = [long](Get-CU32 $entry 20)
            $uncomp = [long](Get-CU32 $entry 24)
            $expectedCrc = [uint32](Get-CU32 $entry 16)
            $nameLen = [long](Get-CU16 $entry 28)
            $extraLen = [long](Get-CU16 $entry 30)
            $cmtLen = [long](Get-CU16 $entry 32)
            $localRel = [long](Get-CU32 $entry 42)
            $recordLen = 46L + $nameLen + $extraLen + $cmtLen
            if ($recordLen -gt ($cdEnd-$pos) -or $nameLen -eq 0 -or
                $localRel -eq 0xffffffffL -or $comp -eq 0xffffffffL -or
                ($eflags -band 1) -ne 0 -or $emode -notin @(0,8)) { $valid=$false; break }
            $nameBytes = Read-CBytes $Stream ($pos+46) ([int]$nameLen)
            $local = Read-CBytes $Stream ($Offset+$localRel) 30
            if ($null -eq $nameBytes -or $null -eq $local -or (Get-CU32 $local 0) -ne 0x04034b50) { $valid=$false; break }
            $localNameLen = [long](Get-CU16 $local 26)
            $localExtraLen = [long](Get-CU16 $local 28)
            $dataStart = $Offset+$localRel+30L+$localNameLen+$localExtraLen
            $dataEnd = $dataStart+$comp
            if ($localNameLen -ne $nameLen -or (Get-CU16 $local 8) -ne $emode -or
                $dataEnd -gt ($Offset+$cdRel) -or $dataEnd -lt ($Offset+$localRel)) { $valid=$false; break }
            $localName = Read-CBytes $Stream ($Offset+$localRel+30) ([int]$localNameLen)
            if ($null -eq $localName -or -not [Collections.StructuralComparisons]::StructuralEqualityComparer.Equals($nameBytes,$localName)) { $valid=$false; break }
            # CRC budget is per archive, 64 KiB maximum; deflate and oversized entries are NOT checked.
            if ($emode -eq 0 -and $comp -eq $uncomp -and $comp -le $crcBudget) {
                $actualCrc = Get-CStoredCrc32 $Stream $dataStart $comp
                if ($null -eq $actualCrc) { $valid=$false; break }
                $crcChecked++
                $crcBudget-=$comp
                if ([uint32]$actualCrc -ne $expectedCrc) { $crcMismatch=$true }
            } else { $crcUnchecked++ }
            # Names are used for *classification only* and never returned or logged.
            $names.Add([Text.Encoding]::UTF8.GetString($nameBytes))
            $pos += $recordLen
        }
        if (-not $valid -or $pos -ne $cdEnd) { continue }
        $contentTypes = $false; $model = $false; $relationships = $false
        foreach ($entryName in $names) {
            if ($entryName -eq '[Content_Types].xml') { $contentTypes = $true }
            if ($entryName -ieq '_rels/.rels') { $relationships = $true }
            if ($entryName -match '(?i)^3D/[^/]+\.model$') { $model = $true }
        }
        $is3mf = $contentTypes -and $model -and $relationships
        $crcStatus=if($crcMismatch){'mismatch'}elseif($crcChecked -eq 0){'not_checked'}elseif($crcUnchecked -gt 0){'partial'}else{'match'}
        $evidence=@('zip.local_header','zip.eocd','zip.central_directory','zip.local_references')
        if($crcChecked -gt 0){$evidence+= 'zip.stored_crc_checked'}
        if($crcMismatch){$evidence+= 'zip.stored_crc_mismatch'}
        return [pscustomobject]@{
            offsetBytes=$Offset; lengthBytes=($endOffset-$Offset)
            format=$(if($is3mf){'3mf'}else{'zip'})
            confidence=$(if($crcMismatch){'partial'}else{'verified'})
            evidence=$evidence
            checks=$(if($crcMismatch){'zip_stored_crc_mismatch'}elseif($crcStatus -eq 'match'){'zip_structure_and_stored_crc32'}else{'zip_structure_with_crc_unchecked'})
            crc32Status=$crcStatus; crc32CheckedEntries=$crcChecked; crc32UncheckedEntries=$crcUnchecked
            truncated=$false
        }
    }
    return [pscustomobject]@{
        offsetBytes=$Offset; lengthBytes=0L; format='zip'; confidence='partial'
        evidence=@('zip.local_header','zip.central_directory_not_validated')
        checks='signature_only'; truncated=$true
    }
}

function Test-CGcode {
    param([IO.Stream]$Stream,[long]$Offset,[long]$MaxFileBytes)
    $limit=[Math]::Min($MaxFileBytes,$Stream.Length-$Offset)
    if ($limit -lt 48) { return $null }
    [void]$Stream.Seek($Offset,[IO.SeekOrigin]::Begin)
    $cursor=$Offset; $lineStart=$Offset; $lastGood=$Offset
    $partial=New-Object 'System.Collections.Generic.List[byte]'
    $lines=0; $commands=0; $stopped=$false
    $badRun=0; $fragmentationSuspected=$false
    while ($cursor -lt ($Offset+$limit) -and $lines -lt 200000) {
        $want=[int][Math]::Min(32768L, ($Offset+$limit)-$cursor)
        $data=Read-CBytes $Stream $cursor $want
        if ($null -eq $data) { break }
        for ($i=0; $i -lt $data.Length; $i++) {
            $b=$data[$i]
            if ($b -eq 10) {
                $line=[Text.Encoding]::ASCII.GetString($partial.ToArray()).TrimEnd([char]13)
                $printable=$true
                foreach($c in $partial) { if (($c -lt 32 -and $c -ne 9 -and $c -ne 13) -or $c -gt 126) { $printable=$false;break } }
                if ($printable -and $line -match '^\s*(?:;.*|(?:G|M|T)\d+(?:\.\d+)?(?:\s|$)|N\d+\s+(?:G|M)\d+|$)') {
                    $lines++
                    if ($line -match '^\s*(?:[GMT]\d+|N\d+\s+[GM]\d+)') { $commands++ }
                    $lastGood = $cursor + $i + 1
                    $badRun=0
                } else { $badRun++; $fragmentationSuspected=($line.Trim([char]0,[char]32,[char]9,[char]13).Length -gt 0); if ($badRun -ge 1) { $stopped=$true;break } }
                $partial.Clear()
                $lineStart=$cursor+$i+1
            } else {
                if ($partial.Count -ge 4096) { $stopped=$true; break }
                $partial.Add($b)
            }
        }
        if ($stopped) { break }
        $cursor += $data.Length
    }
    if ($commands -lt 4 -or $lines -lt 6 -or $lastGood -le $Offset) { return $null }
    $windowEnd=$Offset+$limit
    # Trailing zero-filled slack is not a file fragment by itself.
    $zeroPaddedTail = ($partial.Count -gt 0)
    foreach ($tailByte in $partial) { if ($tailByte -ne 0) { $zeroPaddedTail=$false; break } }
    $bounded = (-not $stopped -and -not $zeroPaddedTail -and ($lastGood -ge ($windowEnd-4096)))
    $incomplete = $bounded -or $fragmentationSuspected
    return [pscustomobject]@{
        offsetBytes=$Offset; lengthBytes=($lastGood-$Offset); format='gcode'
        confidence=$(if($incomplete){'partial'}else{'probable'})
        evidence=@('gcode.printable_lines','gcode.command_sequence',"gcode.command_count_$commands")
        checks='text_syntax_only'; truncated=$incomplete; fragmentationSuspected=$fragmentationSuspected
    }
}

function Get-ChappyCarvingCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [ValidateRange(0,9223372036854775806)][long]$StartOffset=0,
        [ValidateRange(1,1073741824)][long]$MaxScanBytes=67108864,
        [ValidateRange(1024,1073741824)][long]$MaxFileBytes=134217728,
        [ValidateRange(1,10000)][int]$MaxCandidates=128
    )
    $out=[ordered]@{schemaVersion='1';team='C';status='ok';scanIncomplete=$false;items=@();warnings=@();errors=@();metrics=@{bytesRead=0L;entriesChecked=0}}
    if (-not $Stream.CanRead -or -not $Stream.CanSeek) {
        $out.status='error';$out.errors=@('stream.not_seekable_readable');return [pscustomobject]$out
    }
    if ($StartOffset -gt $Stream.Length) {
        $out.status='error';$out.errors=@('scan.offset_out_of_range');return [pscustomobject]$out
    }
    $range=[Math]::Min($MaxScanBytes,$Stream.Length-$StartOffset)
    $limit=$StartOffset+$range
    $hits=@(Find-CSignature $Stream $StartOffset $range ([byte[]](0x50,0x4b,0x03,0x04)) ($MaxCandidates*8))
    $candidates=New-Object 'System.Collections.Generic.List[object]'
    $skipUntil=$StartOffset
    foreach($hit in $hits) {
        if ($hit -lt $skipUntil) { continue }
        $item=Test-CZip $Stream $hit $MaxFileBytes
        if ($null -ne $item) {
            $candidates.Add($item)
            if ($item.lengthBytes -gt 0) { $skipUntil=$hit+$item.lengthBytes }
            if ($candidates.Count -ge $MaxCandidates) { break }
        }
    }
    # G-code candidate anchors must be at line starts, not arbitrary parameter strings.
    $cursor=$StartOffset; $overlap=''; $gskip=$StartOffset
    while ($cursor -lt $limit -and $candidates.Count -lt $MaxCandidates) {
        $want=[int][Math]::Min(65536L,$limit-$cursor)
        $buf=Read-CBytes $Stream $cursor $want
        if ($null -eq $buf) {break}
        $text=$overlap+[Text.Encoding]::ASCII.GetString($buf)
        $base=$cursor-$overlap.Length
        $rx='(?m)(?:^|[\x00\n])(?<anchor>;\s*(?:FLAVOR:|generated|HEADER_START|BambuStudio)|G28\b|M104\b|M140\b|M73\b)'
        foreach ($m in [regex]::Matches($text,$rx,[Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $at=$base+[long]$m.Groups['anchor'].Index
            if ($at -lt $StartOffset -or $at -ge $limit -or $at -lt $gskip) {continue}
            $gc=Test-CGcode $Stream $at $MaxFileBytes
            if ($null -ne $gc) {
                $candidates.Add($gc)
                $gskip=$at+[Math]::Max(1L,[long]$gc.lengthBytes)
            }
            if ($candidates.Count -ge $MaxCandidates) {break}
        }
        $overlap=$text.Substring([Math]::Max(0,$text.Length-256))
        $cursor+=$want
    }
    $out.items=@($candidates.ToArray() | Sort-Object offsetBytes)
    $out.metrics.bytesRead=$range
    $out.metrics.entriesChecked=$hits.Count
    if ($range -lt ($Stream.Length-$StartOffset) -or $candidates.Count -ge $MaxCandidates -or $hits.Count -ge ($MaxCandidates*8)) {
        $out.scanIncomplete=$true;$out.status='partial';$out.warnings=@('scan.bounds_reached')
    }
    return [pscustomobject]$out
}

function Export-ChappyCarvingCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ImagePath,
        [Parameter(Mandatory=$true)][psobject]$Candidate,
        [Parameter(Mandatory=$true)][string]$OutputDirectory,
        [ValidateRange(1,1073741824)][long]$MaxFileBytes=134217728
    )
    $source=[IO.Path]::GetFullPath($ImagePath)
    $destination=[IO.Path]::GetFullPath($OutputDirectory)
    if (-not [IO.File]::Exists($source)) {throw 'Source file not found'}
    if (-not [IO.Directory]::Exists($destination)) {throw 'Output directory must already exist'}
    if ([string]::Equals([IO.Path]::GetDirectoryName($source).TrimEnd('\','/'),$destination.TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)) {throw 'Output must be in another directory'}
    $start=[long]$Candidate.offsetBytes; $length=[long]$Candidate.lengthBytes
    if ($start -lt 0 -or $length -le 0 -or $length -gt $MaxFileBytes) {throw 'Invalid or unbounded candidate length'}
    if ($Candidate.confidence -notin @('verified','probable','partial')) {throw 'Unrecognized confidence'}
    if ($Candidate.format -notin @('zip','3mf','gcode')) {throw 'Unrecognized format'}
    $suffix= switch ($Candidate.format) {'gcode' {'.gcode'} '3mf' {'.3mf'} default {'.zip'}}
    $group=if ($Candidate.confidence -eq 'partial') {'partial'} elseif ($Candidate.confidence -eq 'verified') {'structurally_verified'} else {'probable'}
    $subdir=Join-Path $destination $group
    [void][IO.Directory]::CreateDirectory($subdir)
    $name=('carved_{0:X16}{1}' -f $start,$suffix)
    $target=Join-Path $subdir $name
    $input=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $output=$null; $created=$false
    try {
        if ($start -gt $input.Length -or $length -gt ($input.Length-$start)) {throw 'Candidate exceeds source image bounds'}
        $output=[IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $created=$true
        [void]$input.Seek($start,[IO.SeekOrigin]::Begin)
        $remaining=$length
        $buf=New-Object byte[] 65536
        $sha=[Security.Cryptography.SHA256]::Create()
        try {
            while ($remaining -gt 0) {
                $n=$input.Read($buf,0,[int][Math]::Min($buf.Length,$remaining))
                if ($n -le 0) {throw 'Unexpected end of source image'}
                $output.Write($buf,0,$n)
                [void]$sha.TransformBlock($buf,0,$n,$buf,0)
                $remaining-=$n
            }
            [void]$sha.TransformFinalBlock($buf,0,0)
            $hash=([BitConverter]::ToString($sha.Hash)).Replace('-','').ToLowerInvariant()
        } finally {$sha.Dispose()}
        $output.Dispose(); $output=$null
        return [pscustomobject]@{schemaVersion='1';team='C';status='ok';fileName=$name;group=$group;offsetBytes=$start;lengthBytes=$length;sha256=$hash;confidence=$Candidate.confidence;format=$Candidate.format;integrity='extracted_bytes_only_not_original_integrity'}
    } catch {
        if ($null -ne $output) {$output.Dispose();$output=$null}
        if ($created -and [IO.File]::Exists($target)) {[IO.File]::Delete($target)}
        throw
    } finally {
        if ($null -ne $output) {$output.Dispose()}
        $input.Dispose()
    }
}
Export-ModuleMember -Function Get-ChappyCarvingCandidates,Export-ChappyCarvingCandidate

function Write-ChappyCarvingReport {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Result,
          [Parameter(Mandatory=$true)][string]$ReportPath)
    $path=[IO.Path]::GetFullPath($ReportPath)
    if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($path))) {throw 'Report directory must already exist'}
    # Whitelist fields: no source path, original filenames, snippets, or contents.
    $safeItems=@(foreach($candidate in $Result.items) {
        [pscustomobject]@{
            offsetBytes=[long]$candidate.offsetBytes
            lengthBytes=[long]$candidate.lengthBytes
            format=[string]$candidate.format
            confidence=[string]$candidate.confidence
            evidence=@($candidate.evidence)
            checks=[string]$candidate.checks
            crc32Status=$(if($null -ne $candidate.PSObject.Properties['crc32Status']){[string]$candidate.crc32Status}else{'not_applicable'})
            crc32CheckedEntries=$(if($null -ne $candidate.PSObject.Properties['crc32CheckedEntries']){[int]$candidate.crc32CheckedEntries}else{0})
            crc32UncheckedEntries=$(if($null -ne $candidate.PSObject.Properties['crc32UncheckedEntries']){[int]$candidate.crc32UncheckedEntries}else{0})
            truncated=[bool]$candidate.truncated
        }
    })
    $safe=[ordered]@{
        schemaVersion='1'; team='C'; status=[string]$Result.status
        scanIncomplete=[bool]$Result.scanIncomplete;items=$safeItems
        warnings=@($Result.warnings); errors=@($Result.errors)
        metrics=$Result.metrics
    }
    $json=ConvertTo-Json -InputObject $safe -Depth 8
    $utf8=New-Object System.Text.UTF8Encoding($false)
    $bytes=$utf8.GetBytes($json)
    $file=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$file.Write($bytes,0,$bytes.Length)} finally {$file.Dispose()}
    return [pscustomobject]@{status='ok'; bytesWritten=$bytes.Length; reportFileName=[IO.Path]::GetFileName($path)}
}
Export-ModuleMember -Function Write-ChappyCarvingReport
