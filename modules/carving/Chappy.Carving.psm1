#requires -Version 5.1
Set-StrictMode -Version Latest
$script:CStoredCrcTable = $null

function Read-CBytes {
    param([IO.Stream]$Stream, [long]$Offset, [int]$Count, [psobject]$Budget=$null)
    if ($Offset -lt 0 -or $Count -lt 0 -or $Offset -gt ($Stream.Length - [long]$Count)) { return $null }
    if ($null -ne $Budget) {
        if ($Budget.Timer.ElapsedMilliseconds -gt $Budget.MaxElapsedMilliseconds) {
            $Budget.StopCode='scan.time_budget_exhausted'; return $null
        }
        if ($Offset -lt $Budget.Start -or $Offset -gt $Budget.End -or [long]$Count -gt ($Budget.End-$Offset)) {
            $Budget.WindowLimited=$true; return $null
        }
        if ([long]$Count -gt ($Budget.MaxBytes-$Budget.BytesRead)) {
            $Budget.StopCode='scan.read_budget_exhausted'; return $null
        }
    }
    [void]$Stream.Seek($Offset, [IO.SeekOrigin]::Begin)
    $bytes = New-Object byte[] $Count
    $n = 0
    while ($n -lt $Count) {
        $got = $Stream.Read($bytes, $n, $Count - $n)
        if ($got -le 0) { return $null }
        if ($null -ne $Budget) {
            $Budget.BytesRead += [long]$got
            $Budget.ReadRequests++
        }
        $n += $got
    }
    return ,$bytes
}
function Get-CU16 { param([byte[]]$Bytes,[int]$At) return [BitConverter]::ToUInt16($Bytes,$At) }
function Get-CU32 { param([byte[]]$Bytes,[int]$At) return [BitConverter]::ToUInt32($Bytes,$At) }

function Find-CSignature {
    param([IO.Stream]$Stream,[long]$Start,[long]$Length,[byte[]]$Signature,[int]$Limit=256,[psobject]$Budget=$null)
    $hits = New-Object 'System.Collections.Generic.List[long]'
    $end = [Math]::Min($Stream.Length, $Start + $Length)
    $cursor = $Start
    $tail = New-Object byte[] 0
    while ($cursor -lt $end -and $hits.Count -lt $Limit) {
        $want = [int][Math]::Min(65536L, $end - $cursor)
        $block = Read-CBytes $Stream $cursor $want $Budget
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
        if ($null -ne $Budget -and $null -ne $Budget.StopCode) { break }
    }
    return $hits.ToArray()
}


# CRC table shared by bounded STORED and opt-in DEFLATE payload CRC checks.
function Initialize-CCrcTable {
    if ($null -ne $script:CStoredCrcTable) { return }
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

# Bounded CRC32 for ZIP STORED (method 0) entries only.
# This is content evidence, never proof of the original filesystem's integrity.
function Get-CStoredCrc32 {
    param([IO.Stream]$Stream,[long]$Offset,[long]$Length,[psobject]$Budget=$null)
    if ($Length -lt 0 -or $Length -gt 65536L -or $Offset -lt 0 -or $Offset -gt ($Stream.Length-$Length)) { return $null }
    Initialize-CCrcTable
    $crc=[uint32]4294967295L
    $cursor=$Offset; $remaining=$Length
    while ($remaining -gt 0) {
        $take=[int][Math]::Min(16384L,$remaining)
        $bytes=Read-CBytes $Stream $cursor $take $Budget
        if ($null -eq $bytes) { return $null }
        foreach ($b in $bytes) {
            $index=[int](($crc -bxor [uint32]$b) -band 255L)
            $crc=[uint32](($crc -shr 8) -bxor $script:CStoredCrcTable[$index])
        }
        $cursor+=$take; $remaining-=$take
    }
    return [uint32]($crc -bxor 4294967295L)
}


# Experimental opt-in only: check one small raw ZIP method-8 payload with built-in
# DeflateStream (ZIP uses raw DEFLATE, not a zlib header). No path/output APIs.
# The caller enforces per-entry compressed <=32KiB, expanded <=64KiB, ratio <=64,
# 16 checked entries, aggregate compressed <=128KiB and expanded <=64KiB.
# Compressed bytes are acquired ONLY by Read-CBytes, shared with global scan I/O caps.
# No decompressed content is returned or logged. The loop reads <=4096 bytes/call.
function Get-CDeflateCrc32 {
    param([IO.Stream]$Stream,[long]$Offset,[long]$CompressedBytes,
          [long]$ExpectedExpandedBytes,[psobject]$Budget=$null)
    if ($CompressedBytes -le 0 -or $CompressedBytes -gt 32768L -or
        $ExpectedExpandedBytes -lt 0 -or $ExpectedExpandedBytes -gt 65536L) {
        return [pscustomobject]@{status='skipped';crc32=$null}
    }
    $raw=Read-CBytes $Stream $Offset ([int]$CompressedBytes) $Budget
    if ($null -eq $raw) { return [pscustomobject]@{status='aborted';crc32=$null} }
    Initialize-CCrcTable
    $memory=New-Object IO.MemoryStream(,$raw)
    $inflater=$null
    $crc=[uint32]4294967295L
    $produced=0L
    try {
        $inflater=New-Object IO.Compression.DeflateStream($memory,[IO.Compression.CompressionMode]::Decompress,$false)
        $buf=New-Object byte[] 4096
        # A fixed 65,536-byte maximum is checked before every read. An attempted
        # overrun performs at most one 4 KiB read and never stores that output.
        while ($true) {
            if ($null -ne $Budget -and $Budget.Timer.ElapsedMilliseconds -gt $Budget.MaxElapsedMilliseconds) {
                $Budget.StopCode='scan.time_budget_exhausted'
                return [pscustomobject]@{status='aborted';crc32=$null}
            }
            $n=$inflater.Read($buf,0,$buf.Length)
            if ($n -eq 0) { break }
            $produced += [long]$n
            if ($produced -gt $ExpectedExpandedBytes -or $produced -gt 65536L) {
                return [pscustomobject]@{status='failed';crc32=$null}
            }
            for($k=0;$k -lt $n;$k++){
                $idx=[int](($crc -bxor [uint32]$buf[$k]) -band 255L)
                $crc=[uint32](($crc -shr 8) -bxor $script:CStoredCrcTable[$idx])
            }
        }
        if ($produced -ne $ExpectedExpandedBytes -or $memory.Position -ne $memory.Length) {
            return [pscustomobject]@{status='failed';crc32=$null}
        }
        return [pscustomobject]@{status='checked';crc32=([uint32]($crc -bxor 4294967295L))}
    } catch [IO.InvalidDataException] {
        return [pscustomobject]@{status='failed';crc32=$null}
    } catch [IO.IOException] {
        return [pscustomobject]@{status='failed';crc32=$null}
    } finally {
        if ($null -ne $inflater) {$inflater.Dispose()} else {$memory.Dispose()}
    }
}

function Test-CZip {
    param([IO.Stream]$Stream,[long]$Offset,[long]$MaxFileBytes,[psobject]$Budget=$null,[long]$MaxProbeBytes=16777216,[switch]$EnableSmallDeflateCrc)
    $first = Read-CBytes $Stream $Offset 30 $Budget
    if ($null -eq $first -or (Get-CU32 $first 0) -ne 0x04034b50) { return $null }
    $flags = Get-CU16 $first 6
    $method = Get-CU16 $first 8
    $firstNameLength = Get-CU16 $first 26
    if (($flags -band 1) -ne 0 -or $method -notin @(0,8) -or $firstNameLength -eq 0) { return $null }
    $limit=[Math]::Min($MaxProbeBytes,[Math]::Min($MaxFileBytes,$Stream.Length-$Offset))
    if ($null -ne $Budget) { $limit=[Math]::Min($limit,$Budget.End-$Offset) }
    if ($limit -lt 52) { return $null }
    $endMarkers = @(Find-CSignature $Stream ($Offset+30) ($limit-30) ([byte[]](0x50,0x4b,0x05,0x06)) 128 $Budget)
    foreach ($eocd in $endMarkers) {
        $endRec = Read-CBytes $Stream $eocd 22 $Budget
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
        $deflateChecked=0; $deflateMismatch=$false; $deflateFailure=$false
        $deflateCompressedBudget=131072L; $deflateAttempts=0
        $names = New-Object 'System.Collections.Generic.List[string]'
        for ($j=0; $j -lt $entries; $j++) {
            $entry = Read-CBytes $Stream $pos 46 $Budget
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
            $nameBytes = Read-CBytes $Stream ($pos+46) ([int]$nameLen) $Budget
            $local = Read-CBytes $Stream ($Offset+$localRel) 30 $Budget
            if ($null -eq $nameBytes -or $null -eq $local -or (Get-CU32 $local 0) -ne 0x04034b50) { $valid=$false; break }
            $localNameLen = [long](Get-CU16 $local 26)
            $localExtraLen = [long](Get-CU16 $local 28)
            $dataStart = $Offset+$localRel+30L+$localNameLen+$localExtraLen
            $dataEnd = $dataStart+$comp
            if ($localNameLen -ne $nameLen -or (Get-CU16 $local 8) -ne $emode -or
                $dataEnd -gt ($Offset+$cdRel) -or $dataEnd -lt ($Offset+$localRel)) { $valid=$false; break }
            $localName = Read-CBytes $Stream ($Offset+$localRel+30) ([int]$localNameLen) $Budget
            if ($null -eq $localName -or -not [Collections.StructuralComparisons]::StructuralEqualityComparer.Equals($nameBytes,$localName)) { $valid=$false; break }
            # Both CRC modes share a fixed 64KiB decompressed-byte budget.
            # DEFLATE remains OFF by default. Do not allocate or inflate huge claims.
            if ($emode -eq 0 -and $comp -eq $uncomp -and $comp -le $crcBudget) {
                $actualCrc = Get-CStoredCrc32 $Stream $dataStart $comp $Budget
                if ($null -eq $actualCrc) { $valid=$false; break }
                $crcChecked++
                $crcBudget-=$comp
                if ([uint32]$actualCrc -ne $expectedCrc) { $crcMismatch=$true }
            } elseif ($emode -eq 8 -and $EnableSmallDeflateCrc -and
                      $deflateAttempts -lt 16 -and $comp -gt 0 -and $comp -le 32768L -and
                      $comp -le $deflateCompressedBudget -and $uncomp -le 65536L -and
                      $uncomp -le $crcBudget -and $uncomp -le ($comp * 64L)) {
                $deflateAttempts++
                $deflateCompressedBudget-=$comp
                $inflate=Get-CDeflateCrc32 $Stream $dataStart $comp $uncomp $Budget
                if ($inflate.status -eq 'checked') {
                    $crcChecked++; $deflateChecked++
                    $crcBudget-=$uncomp
                    if ([uint32]$inflate.crc32 -ne $expectedCrc) {
                        $crcMismatch=$true; $deflateMismatch=$true
                    }
                } elseif ($inflate.status -eq 'aborted') {
                    $valid=$false; break
                } else {
                    # A structurally present but invalid compressed body is not
                    # a valid content check and must never be called verified.
                    $deflateFailure=$true
                    $crcUnchecked++
                }
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
        $crcStatus=if($crcMismatch){'mismatch'}elseif($deflateFailure){'partial'}elseif($crcChecked -eq 0){'not_checked'}elseif($crcUnchecked -gt 0){'partial'}else{'match'}
        $evidence=@('zip.local_header','zip.eocd','zip.central_directory','zip.local_references')
        if(($crcChecked-$deflateChecked) -gt 0){$evidence+= 'zip.stored_crc_checked'}
        if($deflateChecked -gt 0){$evidence+= 'zip.deflate_crc_checked'}
        if($crcMismatch -and -not $deflateMismatch){$evidence+= 'zip.stored_crc_mismatch'}
        if($deflateMismatch){$evidence+= 'zip.deflate_crc_mismatch'}
        if($deflateFailure){$evidence+= 'zip.deflate_inflate_failed'}
        return [pscustomobject]@{
            offsetBytes=$Offset; lengthBytes=($endOffset-$Offset)
            format=$(if($is3mf){'3mf'}else{'zip'})
            confidence=$(if($crcMismatch -or $deflateFailure){'partial'}else{'verified'})
            # ZIP references may be structurally valid while payload CRC/deflate is unverified.
            # CRC match on selected STORED entries is not proof of the original file integrity.
            integrityScope='structural_only_not_original_file_integrity'
            evidence=$evidence
            checks=$(if($deflateFailure){'zip_deflate_inflate_failed'}elseif($deflateMismatch){'zip_deflate_crc_mismatch'}elseif($crcMismatch){'zip_stored_crc_mismatch'}elseif($deflateChecked -gt 0){'zip_structure_and_optin_deflate_crc32'}elseif($crcStatus -eq 'match'){'zip_structure_and_stored_crc32'}else{'zip_structure_with_crc_unchecked'})
            crc32Status=$crcStatus; crc32CheckedEntries=$crcChecked; crc32UncheckedEntries=$crcUnchecked
            truncated=$false
        }
    }
    return [pscustomobject]@{
        offsetBytes=$Offset; lengthBytes=0L; format='zip'; confidence='partial'
        integrityScope='signature_only_not_validated'
        evidence=@('zip.local_header','zip.central_directory_not_validated')
        checks='signature_only'; truncated=$true
    }
}

function Test-CGcode {
    param([IO.Stream]$Stream,[long]$Offset,[long]$MaxFileBytes,[psobject]$Budget=$null,[long]$MaxProbeBytes=16777216)
    $limit=[Math]::Min($MaxProbeBytes,[Math]::Min($MaxFileBytes,$Stream.Length-$Offset))
    if ($null -ne $Budget) { $limit=[Math]::Min($limit,$Budget.End-$Offset) }
    if ($limit -lt 48) { return $null }
    [void]$Stream.Seek($Offset,[IO.SeekOrigin]::Begin)
    $cursor=$Offset; $lineStart=$Offset; $lastGood=$Offset
    $partial=New-Object 'System.Collections.Generic.List[byte]'
    $lines=0; $commands=0; $stopped=$false
    $badRun=0; $fragmentationSuspected=$false
    while ($cursor -lt ($Offset+$limit) -and $lines -lt 200000) {
        $want=[int][Math]::Min(32768L, ($Offset+$limit)-$cursor)
        $data=Read-CBytes $Stream $cursor $want $Budget
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
        checks='text_syntax_only'; integrityScope='heuristic_text_only_not_original_file_integrity'
        truncated=$incomplete; fragmentationSuspected=$fragmentationSuspected
    }
}

function Get-ChappyCarvingCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [ValidateRange(0,9223372036854775806)][long]$StartOffset=0,
        [ValidateRange(1,1073741824)][long]$MaxScanBytes=67108864,
        [ValidateRange(1024,1073741824)][long]$MaxFileBytes=134217728,
        [ValidateRange(1,10000)][int]$MaxCandidates=128,
        [ValidateRange(1,4096)][int]$MaxProbes=128,
        [ValidateRange(1024,268435456)][long]$MaxProbeBytes=16777216,
        [ValidateRange(0,1073741824)][long]$ExtraValidationReadBytes=0,
        [ValidateRange(100,120000)][int]$MaxWorkMilliseconds=30000,
        [switch]$EnableSmallDeflateCrc
    )
    $out=[ordered]@{
        schemaVersion='1'; team='C'; status='ok'; scanIncomplete=$false; items=@(); warnings=@(); errors=@();
        metrics=@{bytesRead=0L; entriesChecked=0; readRequests=0; scannedBytes=0L; scanWindowBytes=0L; elapsedMilliseconds=0}
    }
    if (-not $Stream.CanRead -or -not $Stream.CanSeek) {
        $out.status='error'; $out.errors=@('stream.not_seekable_readable'); return [pscustomobject]$out
    }
    if ($StartOffset -gt $Stream.Length) {
        $out.status='error'; $out.errors=@('scan.offset_out_of_range'); return [pscustomobject]$out
    }
    $range=[long][Math]::Min($MaxScanBytes,$Stream.Length-$StartOffset)
    $limit=$StartOffset+$range
    # By default all reads (including nested ZIP, CRC, G-code validation) share one byte budget
    # no larger than the scan window. Extra rereads require an explicit named opt-in.
    $budget=[pscustomobject]@{
        Start=[long]$StartOffset; End=[long]$limit; MaxBytes=([long]$range+$ExtraValidationReadBytes)
        BytesRead=0L; ReadRequests=0; Probes=0
        StopCode=$null; WindowLimited=$false
        Timer=[Diagnostics.Stopwatch]::StartNew(); MaxElapsedMilliseconds=$MaxWorkMilliseconds
    }
    $candidates=New-Object 'System.Collections.Generic.List[object]'
    $cursor=$StartOffset; $scanAdvanced=$StartOffset; $tail=New-Object byte[] 0
    $skipZip=$StartOffset; $skipGcode=$StartOffset
    $lastZipProbed=-1L; $lastGcodeProbed=-1L
    $sig=[byte[]](0x50,0x4b,0x03,0x04)
    $rx='(?m)(?:^|[\x00\n])(?<anchor>;\s*(?:FLAVOR:|generated|HEADER_START|BambuStudio)|G28\b|M104\b|M140\b|M73\b)'
    while ($cursor -lt $limit -and $candidates.Count -lt $MaxCandidates) {
        if ($budget.Timer.ElapsedMilliseconds -gt $MaxWorkMilliseconds) {
            $budget.StopCode='scan.time_budget_exhausted'; break
        }
        $want=[int][Math]::Min(16384L,$limit-$cursor)
        $buf=Read-CBytes $Stream $cursor $want $budget
        if ($null -eq $buf) { break }
        $scanAdvanced=$cursor+$want
        $combined=New-Object byte[] ($tail.Length+$buf.Length)
        [Array]::Copy($tail,0,$combined,0,$tail.Length)
        [Array]::Copy($buf,0,$combined,$tail.Length,$buf.Length)
        $base=$cursor-$tail.Length
        # Collect both signature families before validating. ZIP-first validation previously
        # suppressed an earlier, non-overlapping G-code whenever ZIP ended later in this chunk.
        # Per-chunk event discovery is bounded by the 16 KiB scan chunk (+ 256-byte tail).
        $events=New-Object 'System.Collections.Generic.List[object]'
        $i=0
        while ($i -le ($combined.Length - $sig.Length)) {
            $hit=[Array]::IndexOf($combined,$sig[0],$i)
            if ($hit -lt 0 -or $hit -gt ($combined.Length-$sig.Length)) { break }
            $i=$hit+1
            if ($combined[$hit+1] -ne 0x4b -or $combined[$hit+2] -ne 3 -or $combined[$hit+3] -ne 4) { continue }
            $at=$base+[long]$hit
            if ($at -ge $StartOffset -and $at -lt $limit -and $at -gt $lastZipProbed) {
                $events.Add([pscustomobject]@{at=$at; kind='zip'; priority=0})
            }
        }
        $text=[Text.Encoding]::ASCII.GetString($combined)
        foreach ($m in [regex]::Matches($text,$rx,[Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $at=$base+[long]$m.Groups['anchor'].Index
            if ($at -ge $StartOffset -and $at -lt $limit -and $at -gt $lastGcodeProbed) {
                $events.Add([pscustomobject]@{at=$at; kind='gcode'; priority=1})
            }
        }
        # Monotonic offsets allow skipZip/skipGcode to mean "end of an earlier
        # accepted candidate", rather than incorrectly excluding preceding data.
        foreach ($event in ($events | Sort-Object at,priority)) {
            $at=[long]$event.at
            if ($event.kind -eq 'zip') {
                if ($at -le $lastZipProbed -or $at -lt $skipZip -or $at -lt $skipGcode) { continue }
            } else {
                if ($at -le $lastGcodeProbed -or $at -lt $skipGcode -or $at -lt $skipZip) { continue }
            }
            if ($budget.Probes -ge $MaxProbes) { $budget.StopCode='scan.probe_budget_exhausted'; break }
            if ($budget.Timer.ElapsedMilliseconds -gt $MaxWorkMilliseconds) {
                $budget.StopCode='scan.time_budget_exhausted'; break
            }
            $budget.Probes++
            if ($event.kind -eq 'zip') {
                $lastZipProbed=$at
                $item=Test-CZip $Stream $at $MaxFileBytes $budget $MaxProbeBytes -EnableSmallDeflateCrc:$EnableSmallDeflateCrc
                if ($null -ne $item) {
                    $candidates.Add($item)
                    if ($item.lengthBytes -gt 0) { $skipZip=$at+[long]$item.lengthBytes }
                }
            } else {
                $lastGcodeProbed=$at
                $gc=Test-CGcode $Stream $at $MaxFileBytes $budget $MaxProbeBytes
                if ($null -ne $gc) {
                    $candidates.Add($gc)
                    $skipGcode=$at+[Math]::Max(1L,[long]$gc.lengthBytes)
                }
            }
            if ($null -ne $budget.StopCode -or $candidates.Count -ge $MaxCandidates) { break }
        }
        if ($null -ne $budget.StopCode -or $candidates.Count -ge $MaxCandidates) { break }
        $keep=[Math]::Min(256,$combined.Length)
        $tail=New-Object byte[] $keep
        if ($keep -gt 0) { [Array]::Copy($combined,$combined.Length-$keep,$tail,0,$keep) }
        $cursor+=$want
    }
    $budget.Timer.Stop()
    $out.items=@($candidates.ToArray() | Sort-Object offsetBytes)
    $out.metrics.bytesRead=[long]$budget.BytesRead
    $out.metrics.entriesChecked=[int]$budget.Probes
    $out.metrics.readRequests=[int]$budget.ReadRequests
    $out.metrics.scannedBytes=[long]($scanAdvanced-$StartOffset)
    $out.metrics.scanWindowBytes=[long]$range
    $out.metrics.elapsedMilliseconds=[int]$budget.Timer.ElapsedMilliseconds
    $warnings=New-Object 'System.Collections.Generic.List[string]'
    if ($null -ne $budget.StopCode) { $warnings.Add([string]$budget.StopCode) }
    if ($budget.WindowLimited) { $warnings.Add('scan.validation_window_limit') }
    if ($range -lt ($Stream.Length-$StartOffset) -or $cursor -lt $limit -or $candidates.Count -ge $MaxCandidates) {
        $warnings.Add('scan.bounds_reached')
    }
    if ($warnings.Count -gt 0) {
        $out.scanIncomplete=$true; $out.status='partial'; $out.warnings=@($warnings.ToArray())
    }
    return [pscustomobject]$out
}
# Fail closed: no physical drives, device namespaces, UNC shares, relative drive paths,
# symlinks, directory junctions, mount-point aliases, or paths under reparse ancestors.
# Existing local drive-letter paths only; access checks are done before creating output.
function Assert-CSafeCarvingPath {
    param([string]$Path,[bool]$Directory)
    if ([string]::IsNullOrWhiteSpace($Path) -or
        $Path -notmatch '^[A-Za-z]:[\\/]' -or
        $Path -match '[*?"<>|]' -or
        $Path.Substring(2).Contains(':')) {
        throw 'Only absolute regular drive-letter paths are permitted'
    }
    $full=[IO.Path]::GetFullPath($Path)
    if ($full -notmatch '^[A-Za-z]:\\') { throw 'Invalid path namespace' }
    if ($Directory) {
        if (-not [IO.Directory]::Exists($full)) { throw 'Destination directory must already exist' }
    } else {
        if (-not [IO.File]::Exists($full)) { throw 'Source must be an existing regular file' }
    }
    $attrs=[IO.File]::GetAttributes($full)
    if (($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse/alias paths are forbidden' }
    if ($Directory) {
        if (($attrs -band [IO.FileAttributes]::Directory) -eq 0) { throw 'A regular directory is required' }
    } elseif (($attrs -band [IO.FileAttributes]::Directory) -ne 0) {
        throw 'A regular source file is required'
    }
    $root=[IO.Path]::GetPathRoot($full)
    $part=if($Directory){$full}else{[IO.Path]::GetDirectoryName($full)}
    while (-not [string]::IsNullOrWhiteSpace($part)) {
        $attributes=[IO.File]::GetAttributes($part)
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Reparse/alias parent is forbidden'
        }
        if ([string]::Equals($part.TrimEnd('\'),$root.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) { break }
        $part=[IO.Path]::GetDirectoryName($part.TrimEnd('\'))
    }
    return $full
}

function Export-ChappyCarvingCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ImagePath,
        [Parameter(Mandatory=$true)][psobject]$Candidate,
        [Parameter(Mandatory=$true)][string]$OutputDirectory,
        [ValidateRange(1,1073741824)][long]$MaxFileBytes=134217728,
        [switch]$EnableFileExport
    )
    if (-not $EnableFileExport) { throw 'File extraction is disabled unless explicitly enabled' }
    $source=Assert-CSafeCarvingPath -Path $ImagePath -Directory $false
    $destination=Assert-CSafeCarvingPath -Path $OutputDirectory -Directory $true
    # Do not mix recovered output with the source/backup directory tree.
    $sourceParent=([IO.Path]::GetDirectoryName($source).TrimEnd('\')+'\')
    $destPrefix=($destination.TrimEnd('\')+'\')
    if ($sourceParent.StartsWith($destPrefix,[StringComparison]::OrdinalIgnoreCase) -or
        $destPrefix.StartsWith($sourceParent,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Destination must be in a separate directory tree'
    }
    $start=[long]$Candidate.offsetBytes; $length=[long]$Candidate.lengthBytes
    if ($start -lt 0 -or $length -le 0 -or $length -gt $MaxFileBytes) {throw 'Invalid or unbounded candidate length'}
    if ($Candidate.confidence -notin @('verified','probable','partial')) {throw 'Unrecognized confidence'}
    if ($Candidate.format -notin @('zip','3mf','gcode')) {throw 'Unrecognized format'}
    $suffix= switch ($Candidate.format) {'gcode' {'.gcode'} '3mf' {'.3mf'} default {'.zip'}}
    $group=if ($Candidate.confidence -eq 'partial') {'partial'} elseif ($Candidate.confidence -eq 'verified') {'structurally_verified'} else {'probable'}
    $subdir=Join-Path $destination $group
    [void][IO.Directory]::CreateDirectory($subdir)
    [void](Assert-CSafeCarvingPath -Path $subdir -Directory $true)
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
        # The SHA-256 identifies copied output bytes only. Neither the folder name nor hash
        # certifies that those bytes match the original pre-damage file.
        return [pscustomobject]@{schemaVersion='1';team='C';status='ok';fileName=$name;group=$group;offsetBytes=$start;lengthBytes=$length;sha256=$hash;confidence=$Candidate.confidence;format=$Candidate.format;integrity='extracted_bytes_only_not_original_integrity';integrityScope='copied_bytes_sha256_only_not_original_file_integrity'}
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

function Get-CReportField {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $property=$Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

# Report values are untrusted (including metadata added by callers).
# Never serialize arbitrary strings or arbitrary metric keys into a "safe" report.
function Convert-CReportEnum {
    param([object]$Value,[string[]]$Allowed,[string]$Fallback='unknown')
    if ($null -eq $Value -or $Value -isnot [string] -or $Value.Length -gt 80) { return $Fallback }
    if ($Allowed -ccontains $Value) { return $Value }
    return $Fallback
}

function Convert-CReportUnsigned {
    param([object]$Value,[long]$Maximum=9223372036854775807L)
    if ($null -eq $Value) { return [long]0 }
    $raw=[string]$Value
    if ($raw.Length -gt 19 -or $raw -cnotmatch '^(0|[1-9][0-9]{0,18})$') { return [long]0 }
    [long]$number=0
    if (-not [long]::TryParse($raw,[ref]$number)) { return [long]0 }
    if ($number -lt 0 -or $number -gt $Maximum) { return [long]0 }
    return $number
}

function Convert-CReportCodes {
    param([object[]]$Values,[string[]]$Allowed,[int]$MaxCodes=32,[switch]$GcodeCounts)
    $safe=New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $Values) { return }
    foreach ($rawCode in $Values) {
        if ($safe.Count -ge $MaxCodes) { break }
        if ($rawCode -isnot [string] -or $rawCode.Length -gt 80) { continue }
        if ($Allowed -ccontains $rawCode) {
            $safe.Add($rawCode)
        } elseif ($GcodeCounts -and $rawCode -cmatch '^gcode\.command_count_([0-9]{1,6})$') {
            $count=[int]$Matches[1]
            if ($count -le 200000) { $safe.Add(('gcode.command_count_{0}' -f $count)) }
        }
    }
    return $safe.ToArray()
}

function Write-ChappyCarvingReport {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Result,
          [Parameter(Mandatory=$true)][string]$ReportPath)
    $path=[IO.Path]::GetFullPath($ReportPath)
    if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($path))) {throw 'Report directory must already exist'}

    $evidenceCodes=@(
        'zip.local_header','zip.eocd','zip.central_directory','zip.local_references',
        'zip.stored_crc_checked','zip.stored_crc_mismatch','zip.central_directory_not_validated',
        'zip.deflate_crc_checked','zip.deflate_crc_mismatch','zip.deflate_inflate_failed',
        'gcode.printable_lines','gcode.command_sequence'
    )
    $checkCodes=@(
        'zip_stored_crc_mismatch','zip_structure_and_stored_crc32',
        'zip_deflate_inflate_failed','zip_deflate_crc_mismatch','zip_structure_and_optin_deflate_crc32',
        'zip_structure_with_crc_unchecked','signature_only','text_syntax_only'
    )
    $diagnosticCodes=@(
        'scan.read_budget_exhausted','scan.probe_budget_exhausted','scan.time_budget_exhausted',
        'scan.validation_window_limit','scan.bounds_reached','scan.offset_out_of_range',
        'stream.not_seekable_readable'
    )
    $safeItems=New-Object 'System.Collections.Generic.List[object]'
    foreach($candidate in (Get-CReportField $Result 'items')) {
        if ($safeItems.Count -ge 10000) { break }
        if ($null -eq $candidate) { continue }
        $safeEvidence=@(Convert-CReportCodes -Values @((Get-CReportField $candidate 'evidence')) -Allowed $evidenceCodes -GcodeCounts -MaxCodes 32)
        $safeItems.Add([pscustomobject]@{
            offsetBytes=(Convert-CReportUnsigned (Get-CReportField $candidate 'offsetBytes'))
            lengthBytes=(Convert-CReportUnsigned (Get-CReportField $candidate 'lengthBytes'))
            format=(Convert-CReportEnum (Get-CReportField $candidate 'format') @('zip','3mf','gcode'))
            confidence=(Convert-CReportEnum (Get-CReportField $candidate 'confidence') @('verified','probable','partial','unknown'))
            integrityScope=(Convert-CReportEnum (Get-CReportField $candidate 'integrityScope') @('structural_only_not_original_file_integrity','signature_only_not_validated','heuristic_text_only_not_original_file_integrity'))
            evidence=$safeEvidence
            checks=(Convert-CReportEnum (Get-CReportField $candidate 'checks') $checkCodes 'not_validated')
            crc32Status=(Convert-CReportEnum (Get-CReportField $candidate 'crc32Status') @('match','mismatch','partial','not_checked','not_applicable') 'not_applicable')
            crc32CheckedEntries=(Convert-CReportUnsigned (Get-CReportField $candidate 'crc32CheckedEntries') 4096)
            crc32UncheckedEntries=(Convert-CReportUnsigned (Get-CReportField $candidate 'crc32UncheckedEntries') 4096)
            truncated=((Get-CReportField $candidate 'truncated') -eq $true)
        })
    }
    # Fixed schema with numeric-only metrics. Unexpected properties cannot reach JSON.
    $rawMetrics=(Get-CReportField $Result 'metrics')
    $safeMetrics=[ordered]@{
        bytesRead=(Convert-CReportUnsigned (Get-CReportField $rawMetrics 'bytesRead') 2147483648L)
        entriesChecked=(Convert-CReportUnsigned (Get-CReportField $rawMetrics 'entriesChecked') 4096)
        readRequests=(Convert-CReportUnsigned (Get-CReportField $rawMetrics 'readRequests') 2147483647L)
        scannedBytes=(Convert-CReportUnsigned (Get-CReportField $rawMetrics 'scannedBytes') 1073741824L)
        scanWindowBytes=(Convert-CReportUnsigned (Get-CReportField $rawMetrics 'scanWindowBytes') 1073741824L)
        elapsedMilliseconds=(Convert-CReportUnsigned (Get-CReportField $rawMetrics 'elapsedMilliseconds') 120000)
    }
    $safe=[ordered]@{
        schemaVersion='1'; team='C'
        status=(Convert-CReportEnum (Get-CReportField $Result 'status') @('ok','partial','error') 'error')
        scanIncomplete=((Get-CReportField $Result 'scanIncomplete') -eq $true)
        items=@($safeItems.ToArray())
        warnings=@(Convert-CReportCodes -Values @((Get-CReportField $Result 'warnings')) -Allowed $diagnosticCodes -MaxCodes 32)
        errors=@(Convert-CReportCodes -Values @((Get-CReportField $Result 'errors')) -Allowed $diagnosticCodes -MaxCodes 32)
        metrics=$safeMetrics
    }
    $json=ConvertTo-Json -InputObject $safe -Depth 8
    $utf8=New-Object System.Text.UTF8Encoding($false)
    $bytes=$utf8.GetBytes($json)
    $file=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$file.Write($bytes,0,$bytes.Length)} finally {$file.Dispose()}
    return [pscustomobject]@{status='ok'; bytesWritten=$bytes.Length; reportFileName=[IO.Path]::GetFileName($path)}
}
Export-ModuleMember -Function Write-ChappyCarvingReport
