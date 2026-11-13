#requires -Version 5.1
# Team C / Issue #72 / R5 gate C5-02. Bounded format evidence only.
# Explicit opt-in module. Never opens a path, scans real media or exports bytes.
Set-StrictMode -Version Latest

function Test-CStlFiniteNumber {
    param([string]$Word)
    try {
        $v=[double]::Parse($Word,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture)
    } catch { return $false }
    return (-not [double]::IsNaN($v) -and -not [double]::IsInfinity($v))
}

function Get-CStlBinarySectorLength {
    param([byte[]]$Block)
    if ($null -eq $Block -or $Block.Length -ne 512) { return 0 }
    # Conservative subset of binary STL; reject exotic 80-byte headers.
    for ($i=0;$i -lt 80;$i++) {
        $c=[int]$Block[$i]
        if ($c -ne 0 -and ($c -lt 32 -or $c -gt 126)) { return 0 }
    }
    $triangles=[long][BitConverter]::ToUInt32($Block,80)
    if ($triangles -lt 1 -or $triangles -gt 8) { return 0 }
    $length=[int](84+50*$triangles)
    if ($length -gt 512) { return 0 }
    $nonzeroVertex=$false
    for ($i=0;$i -lt $triangles;$i++) {
        $at=[int](84+50*$i)
        for ($j=0;$j -lt 12;$j++) {
            $v=[BitConverter]::ToSingle($Block,($at+4*$j))
            if ([single]::IsNaN($v) -or [single]::IsInfinity($v)) { return 0 }
            if ($j -ge 3 -and $v -ne 0) { $nonzeroVertex=$true }
        }
        # Attribute words are deliberately restricted to zero in this subset.
        if ([BitConverter]::ToUInt16($Block,($at+48)) -ne 0) { return 0 }
    }
    if (-not $nonzeroVertex) { return 0 }
    return $length
}

function Get-CStlAsciiSectorLength {
    param([byte[]]$Block)
    if ($null -eq $Block -or $Block.Length -ne 512) { return 0 }
    $end=[Array]::IndexOf($Block,[byte]0)
    if ($end -lt 0) { $end=512 }
    if ($end -lt 30) { return 0 }
    $raw=[Text.Encoding]::ASCII.GetString($Block,0,$end)
    if ($raw -match '[^\x09\x0A\x0D\x20-\x7E]') { return 0 }
    $lines=@($raw -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    # Strict, fully observed 1-4 facet ASCII STL subset within ONE sector.
    # Everything longer or requiring a second sector remains UNKNOWN.
    if ($lines.Count -lt 9 -or (($lines.Count-2) % 7) -ne 0) { return 0 }
    $facets=[int](($lines.Count-2)/7)
    if ($facets -lt 1 -or $facets -gt 4) { return 0 }
    $last=$lines.Count-1
    if ($lines[0] -cnotmatch '^solid(?: .*)?$' -or $lines[$last] -cnotmatch '^endsolid(?: .*)?$') { return 0 }
    if ($lines[0].Substring(5).Trim() -cne $lines[$last].Substring(8).Trim()) { return 0 }
    for($f=0;$f -lt $facets;$f++) {
        $base=1+7*$f
        if ($lines[$base+1] -cne 'outer loop' -or $lines[$base+5] -cne 'endloop' -or
            $lines[$base+6] -cne 'endfacet') { return 0 }
        foreach ($index in @($base,($base+2),($base+3),($base+4))) {
            $words=@($lines[$index] -split '\s+')
            if ($index -eq $base) {
                if ($words.Count -ne 5 -or $words[0] -cne 'facet' -or $words[1] -cne 'normal') { return 0 }
                $values=@($words[2],$words[3],$words[4])
            } else {
                if ($words.Count -ne 4 -or $words[0] -cne 'vertex') { return 0 }
                $values=@($words[1],$words[2],$words[3])
            }
            foreach ($number in $values) {
                if (-not (Test-CStlFiniteNumber $number)) { return 0 }
            }
        }
    }
    return $end
}

function Get-ChappyStlCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [switch]$EnableStlEvidence,
        [ValidateRange(0,9223372036854775806)][long]$StartOffset=0,
        [ValidateRange(512,65536)][long]$MaxScanBytes=65536,
        [ValidateRange(1,65536)][long]$MaxSourceBytes=65536,
        [ValidateRange(1,128)][int]$MaxSectorProbes=128,
        [ValidateRange(1,16)][int]$MaxCandidates=16,
        [ValidateRange(1,65536)][long]$MaxValidatorBytes=65536,
        [ValidateRange(100,30000)][int]$MaxWorkMilliseconds=30000
    )
    $result=[ordered]@{
        schemaVersion='1';team='C';status='disabled';scanIncomplete=$true
        originalIdentity='unknown';items=@()
        warnings=@('stl.optin_required');errors=@()
        metrics=[pscustomobject]@{
            bytesRead=0L;readRequests=0;entriesChecked=0
            scannedBytes=0L;scanWindowBytes=0L;validatorBytesRead=0L
            elapsedMilliseconds=0;maxScratchSectorBytes=512
        }
    }
    if (-not $EnableStlEvidence) { return [pscustomobject]$result }
    $result.status='partial';$result.warnings=@('stl.unexamined_regions_unknown')
    if (-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite) {
        $result.status='error';$result.errors=@('stl.readonly_stream_required')
        return [pscustomobject]$result
    }
    if (($MaxScanBytes % 512) -ne 0 -or ($StartOffset % 512) -ne 0) {
        $result.warnings=@('stl.invalid_sector_grid');return [pscustomobject]$result
    }
    # Reserve full window and work quota BEFORE any reads. All slices are
    # read-only, fixed 512B; no file paths, unbounded allocation or rescans.
    if ($MaxSourceBytes -lt $MaxScanBytes -or $MaxValidatorBytes -lt $MaxScanBytes -or
        $MaxSectorProbes -lt ($MaxScanBytes/512)) {
        $result.warnings=@('stl.quota_unavailable');return [pscustomobject]$result
    }
    if ($StartOffset -gt ($Stream.Length-$MaxScanBytes)) {
        $result.warnings=@('stl.window_unavailable');return [pscustomobject]$result
    }
    $result.metrics.scanWindowBytes=$MaxScanBytes
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $items=New-Object 'System.Collections.Generic.List[object]'
    $failed=$false
    $errorCode='stl.unexamined_regions_unknown'
    for ($relative=0L;$relative -lt $MaxScanBytes;$relative+=512L) {
        if ($watch.ElapsedMilliseconds -ge $MaxWorkMilliseconds) {
            $failed=$true;$errorCode='stl.time_budget_exhausted';break
        }
        if ($result.metrics.bytesRead -gt ($MaxSourceBytes-512L) -or
            $result.metrics.validatorBytesRead -gt ($MaxValidatorBytes-512L)) {
            $failed=$true;$errorCode='stl.byte_budget_exhausted';break
        }
        $at=$StartOffset+$relative
        [void]$Stream.Seek($at,[IO.SeekOrigin]::Begin)
        [byte[]]$sector=New-Object byte[] 512
        $done=0
        while ($done -lt 512) {
            $got=$Stream.Read($sector,$done,(512-$done))
            $result.metrics.readRequests++
            if ($got -le 0) {
                $failed=$true;$errorCode='stl.short_read';break
            }
            $result.metrics.bytesRead += [long]$got
            $done += $got
        }
        if ($failed) { break }
        $result.metrics.entriesChecked++
        $result.metrics.scannedBytes += 512L
        $result.metrics.validatorBytesRead += 512L
        $binary=Get-CStlBinarySectorLength $sector
        $ascii=Get-CStlAsciiSectorLength $sector
        if ($binary -gt 0) {
            $items.Add([pscustomobject]@{
                format='stl_binary';offsetBytes=$at;lengthBytes=[long]$binary
                confidence='probable';integrityScope='structural_only_not_original_file_integrity'
                originalIdentity='unknown';evidence=@('stl.binary_bounded_facets')
                truncated=$false
            })
        }
        if ($ascii -gt 0) {
            $items.Add([pscustomobject]@{
                format='stl_ascii';offsetBytes=$at;lengthBytes=[long]$ascii
                confidence='probable';integrityScope='structural_only_not_original_file_integrity'
                originalIdentity='unknown';evidence=@('stl.ascii_bounded_1_to_4_facets_syntax')
                truncated=$false
            })
        }
        if ($items.Count -gt $MaxCandidates) {
            $failed=$true;$errorCode='stl.candidate_budget_exhausted';break
        }
    }
    $watch.Stop()
    $result.metrics.elapsedMilliseconds=[int]$watch.ElapsedMilliseconds
    if ($failed) {
        # Never retain early 'winners' after an incomplete window.
        $result.warnings=@($errorCode)
        $result.items=@()
    } else {
        $result.items=@($items.ToArray())
        # Coverage of one window never implies whole-image absence.
        if ($StartOffset -eq 0 -and $Stream.Length -eq $MaxScanBytes) {
            $result.status='ok';$result.scanIncomplete=$false;$result.warnings=@()
        }
    }
    return [pscustomobject]$result
}

# C5-02: conservative, caller-supplied candidate-span G-code syntax evidence.
# This is NOT a non-oracle scanner and NEVER an assessment of printer safety.
# Unsupported (possibly legitimate) commands remain unknown, not "invalid".
function Get-ChappyGcodeEvidence {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [switch]$EnableGcodeEvidence,
        [ValidateRange(0,9223372036854775806)][long]$OffsetBytes=0,
        [Parameter(Mandatory=$true)][ValidateRange(48,8192)][long]$LengthBytes,
        [ValidateRange(1,8192)][long]$MaxSourceBytes=8192,
        [ValidateRange(1,128)][int]$MaxLines=128,
        [ValidateRange(32,160)][int]$MaxLineBytes=160,
        [ValidateRange(100,30000)][int]$MaxWorkMilliseconds=30000
    )
    $result=[ordered]@{
        schemaVersion='1';team='C';status='disabled';decision='unknown'
        scanIncomplete=$true;originalIdentity='unknown';items=@()
        warnings=@('gcode.optin_required');errors=@()
        metrics=[pscustomobject]@{
            bytesRead=0L;uniquePhysicalBytesRead=0L;readRequests=0
            linesChecked=0;commandsChecked=0;elapsedMilliseconds=0
            maxCandidateScratchBytes=8192;peakProcessMemoryStatus='not_measured'
            peakProcessMemoryBytes=$null
        }
    }
    if (-not $EnableGcodeEvidence) { return [pscustomobject]$result }
    $result.status='partial';$result.warnings=@('gcode.unsupported_or_incomplete')
    if (-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite) {
        $result.status='error';$result.errors=@('gcode.readonly_stream_required')
        return [pscustomobject]$result
    }
    if ($LengthBytes -gt $MaxSourceBytes) {
        $result.warnings=@('gcode.quota_unavailable')
        return [pscustomobject]$result
    }
    if ($OffsetBytes -gt ($Stream.Length-$LengthBytes)) {
        $result.warnings=@('gcode.outside_source')
        return [pscustomobject]$result
    }
    $clock=[Diagnostics.Stopwatch]::StartNew()
    [byte[]]$data=New-Object byte[] ([int]$LengthBytes)
    [void]$Stream.Seek($OffsetBytes,[IO.SeekOrigin]::Begin)
    $gotTotal=0
    $failed=$false
    while($gotTotal -lt $data.Length) {
        if($clock.ElapsedMilliseconds -ge $MaxWorkMilliseconds){
            $failed=$true;$result.warnings=@('gcode.time_budget_exhausted');break
        }
        $got=$Stream.Read($data,$gotTotal,($data.Length-$gotTotal))
        $result.metrics.readRequests++
        if($got -le 0){
            $failed=$true;$result.warnings=@('gcode.true_eof');break
        }
        $gotTotal+=$got
        $result.metrics.bytesRead+=[long]$got
    }
    # One contiguous no-reread candidate span; unique physical source bytes
    # are exactly the actual returned positive Stream.Read bytes.
    $result.metrics.uniquePhysicalBytesRead=$result.metrics.bytesRead
    if(-not $failed) {
        foreach($byte in $data){
            if($byte -ne 9 -and $byte -ne 10 -and $byte -ne 13 -and
               ($byte -lt 32 -or $byte -gt 126)){
                $failed=$true;$result.warnings=@('gcode.unsupported_encoding');break
            }
        }
    }
    if(-not $failed -and $data[$data.Length-1] -ne 10){
        $failed=$true;$result.warnings=@('gcode.unterminated_last_line')
    }
    if(-not $failed){
        $text=[Text.Encoding]::ASCII.GetString($data)
        $lines=$text -split '\n'
        $commands=0;$motion=0;$preamble=0;$count=0
        # Permitted *syntax*, not a safety whitelist to execute on a printer:
        # all other G/M/T codes remain UNKNOWN, including manufacturer dialects.
        $lineRegex='^(?:G(?:0|1|28|90|91|92)|M(?:104|109|106|107|140|190|82|83|84|73))(?:[ \t]+[A-Za-z][-+]?(?:\d+(?:\.\d*)?|\.\d+))*[ \t]*

        foreach($line in $lines){
            if($clock.ElapsedMilliseconds -ge $MaxWorkMilliseconds){
                $failed=$true;$result.warnings=@('gcode.time_budget_exhausted');break
            }
            if($line.Length -eq 0){continue}
            if($line.EndsWith([string][char]13)){$line=$line.Substring(0,$line.Length-1)}
            if($line.Length -gt $MaxLineBytes){
                $failed=$true;$result.warnings=@('gcode.line_limit');break
            }
            $count++
            if($count -gt $MaxLines){
                $failed=$true;$result.warnings=@('gcode.line_count_limit');break
            }
            # A "G1" inside a semicolon comment is NOT a command.
            $head=($line -split ';',2)[0].Trim()
            if($head.Length -eq 0){continue}
            if($head -cnotmatch $lineRegex){
                $failed=$true;$result.warnings=@('gcode.outside_strict_profile');break
            }
            $commands++
            if($head -cmatch '^G(?:0|1)(?:[ \t]|$)' -and
               $head -cmatch '(?:^|[ \t])[XYZ][-+]?(?:\d+(?:\.\d*)?|\.\d+)'){
                $motion++
            }
            if($head -cmatch '^G28(?:[ \t]|$)'){$preamble++}
        }
        $result.metrics.linesChecked=$count
        $result.metrics.commandsChecked=$commands
        if(-not $failed -and ($count -lt 6 -or $commands -lt 4 -or $motion -lt 1 -or $preamble -lt 1)){
            $failed=$true;$result.warnings=@('gcode.insufficient_syntax_evidence')
        }
    }
    $clock.Stop()
    $result.metrics.elapsedMilliseconds=[int]$clock.ElapsedMilliseconds
    if(-not $failed){
        $result.status='ok';$result.decision='format_consistent'
        $result.scanIncomplete=($OffsetBytes -gt 0 -or $LengthBytes -lt $Stream.Length)
        $result.warnings=$(if($result.scanIncomplete){@('gcode.unobserved_source_unknown')}else{@()})
        $result.items=@([pscustomobject]@{
            format='gcode';offsetBytes=$OffsetBytes;lengthBytes=$LengthBytes
            confidence='probable';originalIdentity='unknown'
            integrityScope='heuristic_text_only_not_original_file_integrity'
            evidence=@('gcode.bounded_ascii_syntax_profile','gcode.real_motion','gcode.comment_not_command')
            sourceOrigin='unattributed_without_A_meter'
            truncated=$false
        })
    }
    return [pscustomobject]$result
}

Export-ModuleMember -Function Get-ChappyStlCandidates,Get-ChappyGcodeEvidence


        foreach($line in $lines){
            if($clock.ElapsedMilliseconds -ge $MaxWorkMilliseconds){
                $failed=$true;$result.warnings=@('gcode.time_budget_exhausted');break
            }
            if($line.Length -eq 0){continue}
            if($line.EndsWith([string][char]13)){$line=$line.Substring(0,$line.Length-1)}
            if($line.Length -gt $MaxLineBytes){
                $failed=$true;$result.warnings=@('gcode.line_limit');break
            }
            $count++
            if($count -gt $MaxLines){
                $failed=$true;$result.warnings=@('gcode.line_count_limit');break
            }
            # A "G1" inside a semicolon comment is NOT a command.
            $head=($line -split ';',2)[0].Trim()
            if($head.Length -eq 0){continue}
            if($head -cnotmatch $lineRegex){
                $failed=$true;$result.warnings=@('gcode.outside_strict_profile');break
            }
            $commands++
            if($head -cmatch '^G(?:0|1)(?:[ \t]|$)' -and
               $head -cmatch '(?:^|[ \t])[XYZ][-+]?(?:\d+(?:\.\d*)?|\.\d+)'){
                $motion++
            }
            if($head -cmatch '^G28(?:[ \t]|$)'){$preamble++}
        }
        $result.metrics.linesChecked=$count
        $result.metrics.commandsChecked=$commands
        if(-not $failed -and ($count -lt 6 -or $commands -lt 4 -or $motion -lt 1 -or $preamble -lt 1)){
            $failed=$true;$result.warnings=@('gcode.insufficient_syntax_evidence')
        }
    }
    $clock.Stop()
    $result.metrics.elapsedMilliseconds=[int]$clock.ElapsedMilliseconds
    if(-not $failed){
        $result.status='ok';$result.decision='format_consistent'
        $result.scanIncomplete=($OffsetBytes -gt 0 -or $LengthBytes -lt $Stream.Length)
        $result.warnings=$(if($result.scanIncomplete){@('gcode.unobserved_source_unknown')}else{@()})
        $result.items=@([pscustomobject]@{
            format='gcode';offsetBytes=$OffsetBytes;lengthBytes=$LengthBytes
            confidence='probable';originalIdentity='unknown'
            integrityScope='heuristic_text_only_not_original_file_integrity'
            evidence=@('gcode.bounded_ascii_syntax_profile','gcode.real_motion','gcode.comment_not_command')
            sourceOrigin='unattributed_without_A_meter'
            truncated=$false
        })
    }
    return [pscustomobject]$result
}

Export-ModuleMember -Function Get-ChappyStlCandidates,Get-ChappyGcodeEvidence
