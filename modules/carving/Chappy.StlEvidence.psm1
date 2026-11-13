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
    # Strict 1-facet ASCII STL subset; other STL remains UNKNOWN, not invalid.
    if ($lines.Count -ne 9) { return 0 }
    if ($lines[0] -cnotmatch '^solid(?: .*)?$' -or $lines[8] -cnotmatch '^endsolid(?: .*)?$') { return 0 }
    if ($lines[0].Substring(5).Trim() -cne $lines[8].Substring(8).Trim()) { return 0 }
    if ($lines[2] -cne 'outer loop' -or $lines[6] -cne 'endloop' -or
        $lines[7] -cne 'endfacet') { return 0 }
    foreach ($index in @(1,3,4,5)) {
        $words=@($lines[$index] -split '\s+')
        if ($index -eq 1) {
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
                originalIdentity='unknown';evidence=@('stl.ascii_one_facet_syntax')
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
Export-ModuleMember -Function Get-ChappyStlCandidates
