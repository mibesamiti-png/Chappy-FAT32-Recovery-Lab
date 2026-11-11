#requires -Version 5.1
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Chappy.Carving.psm1') -Force
Add-Type -AssemblyName System.IO.Compression
# Test-only wrapper independently counts actual source reads. Write always throws.
Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class ChappyCountingReadStream : Stream {
    private readonly Stream inner;
    public long BytesRead { get; private set; }
    public ChappyCountingReadStream(Stream stream) { inner = stream; }
    public override bool CanRead { get { return inner.CanRead; } }
    public override bool CanSeek { get { return inner.CanSeek; } }
    public override bool CanWrite { get { return false; } }
    public override long Length { get { return inner.Length; } }
    public override long Position { get { return inner.Position; } set { inner.Position=value; } }
    public override void Flush() { }
    public override int Read(byte[] buffer,int offset,int count) {
        int got=inner.Read(buffer,offset,count); BytesRead+=got; return got;
    }
    public override long Seek(long offset,SeekOrigin origin) { return inner.Seek(offset,origin); }
    public override void SetLength(long value) { throw new NotSupportedException(); }
    public override void Write(byte[] buffer,int offset,int count) { throw new NotSupportedException(); }
    protected override void Dispose(bool disposing) { if (disposing) inner.Dispose(); base.Dispose(disposing); }
}
'@
$fixtureRoot=[IO.Path]::Combine([IO.Path]::GetTempPath(),'ChappyCarveSynthetic_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)
function Assert($cond,$message) {if (-not $cond) {throw "FAIL: $message"}}
function MakeZip([bool]$is3mf) {
    $ms=New-Object IO.MemoryStream
    $archive=[IO.Compression.ZipArchive]::new($ms,[IO.Compression.ZipArchiveMode]::Create,$true)
    try {
        $names=if($is3mf){@('[Content_Types].xml','_rels/.rels','3D/3dmodel.model')}else{@('foo.txt')}
        foreach($name in $names){
            $entry=$archive.CreateEntry($name)
            $out=$entry.Open()
            try {$b=[Text.Encoding]::UTF8.GetBytes('synthetic test body');$out.Write($b,0,$b.Length)} finally {$out.Dispose()}
        }
    } finally {$archive.Dispose()}
    $bytes=$ms.ToArray();$ms.Dispose()
    return ,$bytes
}
# Deterministic single-entry STORED ZIP, with standard CRC32 test vector "123456789".
function MakeStoredZip([bool]$Corrupt,[int]$PayloadSize=9) {
    $mem=New-Object IO.MemoryStream
    $writer=New-Object IO.BinaryWriter($mem)
    try {
        $fileName=[Text.Encoding]::ASCII.GetBytes('synthetic.txt')
        $data=if ($PayloadSize -eq 9) {[Text.Encoding]::ASCII.GetBytes('123456789')} else {New-Object byte[] $PayloadSize}
        if ($Corrupt) { $data[3]=[byte][char]'X' }
        $knownCrc=[uint32]3421780262L
        $writer.Write([uint32]0x04034b50)
        $writer.Write([uint16]20); $writer.Write([uint16]0); $writer.Write([uint16]0)
        $writer.Write([uint16]0); $writer.Write([uint16]0)
        $writer.Write($knownCrc)
        $writer.Write([uint32]$data.Length); $writer.Write([uint32]$data.Length)
        $writer.Write([uint16]$fileName.Length); $writer.Write([uint16]0)
        $writer.Write([byte[]]$fileName); $writer.Write([byte[]]$data)
        $centralStart=[uint32]$mem.Position
        $writer.Write([uint32]0x02014b50)
        $writer.Write([uint16]20); $writer.Write([uint16]20)
        $writer.Write([uint16]0); $writer.Write([uint16]0)
        $writer.Write([uint16]0); $writer.Write([uint16]0)
        $writer.Write($knownCrc)
        $writer.Write([uint32]$data.Length); $writer.Write([uint32]$data.Length)
        $writer.Write([uint16]$fileName.Length)
        $writer.Write([uint16]0); $writer.Write([uint16]0)
        $writer.Write([uint16]0); $writer.Write([uint16]0)
        $writer.Write([uint32]0); $writer.Write([uint32]0)
        $writer.Write([byte[]]$fileName)
        $centralLength=[uint32]($mem.Position-$centralStart)
        $writer.Write([uint32]0x06054b50)
        $writer.Write([uint16]0); $writer.Write([uint16]0)
        $writer.Write([uint16]1); $writer.Write([uint16]1)
        $writer.Write([uint32]$centralLength); $writer.Write([uint32]$centralStart)
        $writer.Write([uint16]0)
        $writer.Flush()
        return ,$mem.ToArray()
    } finally { $writer.Dispose();$mem.Dispose() }
}

function WriteSynthetic([string]$path,[byte[]]$content,[int]$size=0) {
    $s=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$s.Write($content,0,$content.Length);if($size -gt $content.Length){$s.SetLength($size)}} finally {$s.Dispose()}
}
function Scan([string]$file,[long]$start=0,[long]$count=1048576) {
    $s=[IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    # Synthetic regression fixture: explicitly permit rereads, never access beyond scan window.
    try {return Get-ChappyCarvingCandidates -Stream $s -StartOffset $start -MaxScanBytes $count -MaxFileBytes 1048576 -ExtraValidationReadBytes 1048576} finally {$s.Dispose()}
}
try {
    # Valid 3MF: central directory and all three required part names.
    $prefix=New-Object byte[] 65534; $zip=MakeZip $true
    $image=New-Object byte[] ($prefix.Length+$zip.Length+1024)
    [Array]::Copy($zip,0,$image,$prefix.Length,$zip.Length)
    $f=Join-Path $fixtureRoot 'fixture_a.img'
    WriteSynthetic $f $image
    $before=(Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash
    $result=Scan $f
    $three=@($result.items | Where-Object {$_.format -eq '3mf' -and $_.confidence -eq 'verified'})
    Assert ($three.Count -eq 1) '3MF should have exactly one structurally valid candidate'
    Assert ($three[0].offsetBytes -eq 65534) 'precise offset across 64 KiB boundary'
    Assert ($three[0].lengthBytes -eq $zip.Length) '3MF length from EOCD'
    Assert ($three[0].crc32Status -in @('match','partial','not_checked')) 'CRC status explicitly classified'
    $dest=Join-Path $fixtureRoot 'restore';[void][IO.Directory]::CreateDirectory($dest)
    $saved=Export-ChappyCarvingCandidate -ImagePath $f -Candidate $three[0] -OutputDirectory $dest
    $restored=Join-Path (Join-Path $dest $saved.group) $saved.fileName
    Assert ($saved.sha256 -eq (Get-FileHash -LiteralPath $restored -Algorithm SHA256).Hash.ToLowerInvariant()) 'SHA-256 on extraction'
    Assert ($before -eq (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash) 'source SHA unchanged'
    $againThrew=$false
    try {Export-ChappyCarvingCandidate -ImagePath $f -Candidate $three[0] -OutputDirectory $dest | Out-Null} catch {$againThrew=$true}
    Assert $againThrew 'no-overwrite guard'
    Assert ([IO.File]::Exists($restored)) 'pre-existing output preserved after duplicate attempt'
    $report=Join-Path $fixtureRoot 'candidates.json'
    $written=Write-ChappyCarvingReport -Result $result -ReportPath $report
    $json=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
    Assert ($json.items[0].format -eq '3mf') 'JSON report contains format'
    Assert (-not ((Get-Content -LiteralPath $report -Raw) -match [regex]::Escape($f))) 'report does not include IMG path'
    Write-Host 'PASS: 3MF central directory, boundary offsets, read-only SHA, output no-overwrite and report'

    # Non-3MF ZIP; required 3MF part missing.
    $z=MakeZip $false; $f2=Join-Path $fixtureRoot 'fixture_b.img';WriteSynthetic $f2 $z
    $r2=Scan $f2;Assert (@($r2.items | Where-Object {$_.format -eq 'zip' -and $_.confidence -eq 'verified'}).Count -eq 1) 'ordinary ZIP classification'
    Write-Host 'PASS: ordinary ZIP classification'

    # CRC32 of a known synthetic STORED ZIP: CRC(123456789) = CBF43926.
    $stored=MakeStoredZip $false
    $storedPath=Join-Path $fixtureRoot 'stored_good.img'
    WriteSynthetic $storedPath $stored
    $storedBefore=(Get-FileHash -LiteralPath $storedPath -Algorithm SHA256).Hash
    $storedScan=Scan $storedPath
    $storedHits=@($storedScan.items | Where-Object {$_.format -eq 'zip'})
    Assert ($storedHits.Count -eq 1) 'deterministic stored ZIP candidate found'
    Assert ($storedHits[0].confidence -eq 'verified' -and $storedHits[0].crc32Status -eq 'match') 'valid stored ZIP CRC32 matches'
    Assert ($storedHits[0].crc32CheckedEntries -eq 1 -and $storedHits[0].crc32UncheckedEntries -eq 0) 'stored CRC checked entry count'
    Assert ($storedHits[0].checks -eq 'zip_structure_and_stored_crc32') 'ZIP checks record CRC coverage'
    Assert ($storedBefore -eq (Get-FileHash -LiteralPath $storedPath -Algorithm SHA256).Hash) 'CRC check is source-read-only'

    $corruptStored=MakeStoredZip $true
    $corruptPath=Join-Path $fixtureRoot 'stored_corrupt.img'
    WriteSynthetic $corruptPath $corruptStored
    $corruptScan=Scan $corruptPath
    $corruptHits=@($corruptScan.items | Where-Object {$_.format -eq 'zip'})
    Assert ($corruptHits.Count -eq 1) 'damaged stored ZIP candidate found'
    Assert ($corruptHits[0].confidence -eq 'partial' -and $corruptHits[0].crc32Status -eq 'mismatch') 'corrupted body is not verified'
    Assert ($corruptHits[0].evidence -contains 'zip.stored_crc_mismatch') 'CRC failure reason code'
    Assert (@($corruptScan.items | Where-Object {$_.confidence -eq 'verified'}).Count -eq 0) 'known corrupt ZIP never verified'
    $crcReport=Join-Path $fixtureRoot 'crc-check-report.json'
    [void](Write-ChappyCarvingReport -Result $corruptScan -ReportPath $crcReport)
    $crcJson=Get-Content -LiteralPath $crcReport -Raw | ConvertFrom-Json
    Assert ($crcJson.items[0].crc32Status -eq 'mismatch') 'sanitized JSON retains CRC mismatch status'
    Assert (-not ((Get-Content -LiteralPath $crcReport -Raw) -match 'synthetic.txt')) 'report never includes inner filename'
    Write-Host 'PASS: ZIP STORED CRC-32 known vector, mismatch and sanitized JSON'
    # >64 KiB STORED entry is structurally recognized, but content CRC is not checked.
    $largeStored=MakeStoredZip $false 65537
    $largeStoredPath=Join-Path $fixtureRoot 'stored_over_crc_budget.img'
    WriteSynthetic $largeStoredPath $largeStored
    $largeStoredScan=Scan $largeStoredPath
    $largeStoredHits=@($largeStoredScan.items | Where-Object {$_.format -eq 'zip'})
    Assert ($largeStoredHits.Count -eq 1) 'large stored ZIP candidate found'
    Assert ($largeStoredHits[0].crc32Status -eq 'not_checked' -and $largeStoredHits[0].crc32CheckedEntries -eq 0) 'CRC byte-budget skip explicit'
    Assert ($largeStoredHits[0].checks -eq 'zip_structure_with_crc_unchecked') 'no full integrity claim when CRC skipped'
    Write-Host 'PASS: bounded CRC budget marks unchecked ZIP content'


    # Truncated central directory is not verified.
    $broken=New-Object byte[] ($z.Length-9)
    [Array]::Copy($z,0,$broken,0,$broken.Length)
    $f3=Join-Path $fixtureRoot 'fixture_c.img';WriteSynthetic $f3 $broken
    $r3=Scan $f3;Assert (@($r3.items | Where-Object {$_.confidence -eq 'verified'}).Count -eq 0) 'truncated ZIP not verified'
    Write-Host 'PASS: truncated ZIP is not marked verified'

    # G-code: 8 valid instruction/comment lines and explicit binary end.
    $gcode=";FLAVOR:Marlin`nG28`nM104 S200`nM140 S55`nG1 X10 Y10 F1000`nG1 X20 Y20`nM73 P10`nM84`n"
    $data=[Text.Encoding]::ASCII.GetBytes($gcode)
    $g=New-Object byte[] (256+$data.Length+1024)
    [Array]::Copy($data,0,$g,256,$data.Length)
    $f4=Join-Path $fixtureRoot 'fixture_d.img';WriteSynthetic $f4 $g
    $r4=Scan $f4
    $gc=@($r4.items | Where-Object {$_.format -eq 'gcode' -and $_.offsetBytes -eq 256})
    Assert ($gc.Count -eq 1) 'G-code start recognized'
    Assert ($gc[0].lengthBytes -eq $data.Length) 'G-code end inferred at newline before padding'
    Assert ($gc[0].confidence -eq 'probable') 'G-code syntax alone is probable, not verified'
    Write-Host 'PASS: contiguous G-code and end estimation'
    # A G-code result lacks ZIP-specific optional properties; sanitization must not throw.
    $gReport=Join-Path $fixtureRoot 'gcode_sanitized_report.json'
    [void](Write-ChappyCarvingReport -Result $r4 -ReportPath $gReport)
    $gJson=Get-Content -LiteralPath $gReport -Raw | ConvertFrom-Json
    $gItem=@($gJson.items | Where-Object {$_.format -eq 'gcode'})
    Assert ($gItem.Count -eq 1) 'G-code report survives missing ZIP optional fields'
    Assert ($gItem[0].crc32Status -eq 'not_applicable') 'G-code CRC status is not applicable'
    Assert (@($gItem[0].evidence | Where-Object {$_ -match '^gcode\.command_count_[0-9]+

    # A non-text interruption after valid commands means at most a partial segment.
    $fragBytes=[Text.Encoding]::ASCII.GetBytes($gcode + "BROKEN_BINARY_FRAGMENT`nG28`n")
    $f6=Join-Path $fixtureRoot 'fixture_fragmented.img'
    $fragImage=New-Object byte[] (256+$fragBytes.Length+8192)
    [Array]::Copy($fragBytes,0,$fragImage,256,$fragBytes.Length)
    WriteSynthetic $f6 $fragImage
    $r6=Scan $f6
    $frag=@($r6.items | Where-Object {$_.format -eq 'gcode' -and $_.offsetBytes -eq 256})
    Assert ($frag.Count -eq 1) 'discontinuous G-code candidate found'
    Assert ($frag[0].fragmentationSuspected -and $frag[0].confidence -eq 'partial') 'discontinuous G-code marked partial'
    Write-Host 'PASS: non-text G-code discontinuity is partial'

    # Bounded scanning intentionally ignores later bytes, reporting incomplete coverage.
    $f7=Join-Path $fixtureRoot 'fixture_bounded.img'
    WriteSynthetic $f7 (New-Object byte[] 0) 2097152
    $r7=Scan $f7 0 4096
    Assert ($r7.scanIncomplete -and $r7.metrics.bytesRead -eq 4096) 'scan is range bounded'
    Write-Host 'PASS: bounded scan reports incomplete coverage'

    # Read-budget stress: adversarial dense local headers cannot induce cumulative I/O amplification.
    $spam=New-Object byte[] (256*1024)
    for ($p=0; $p -lt $spam.Length-8; $p+=8) { $spam[$p]=0x50; $spam[$p+1]=0x4b; $spam[$p+2]=3; $spam[$p+3]=4 }
    $spamPath=Join-Path $fixtureRoot 'dense_fake_signatures.img'; WriteSynthetic $spamPath $spam
    $spamStream=[ChappyCountingReadStream]::new([IO.File]::OpenRead($spamPath))
    try {
        $stress=Get-ChappyCarvingCandidates -Stream $spamStream -StartOffset 0 -MaxScanBytes 65536 -MaxFileBytes 1048576 -MaxCandidates 128 -MaxProbes 16
        Assert ($stress.status -eq 'partial' -and $stress.scanIncomplete) 'dense fake ZIP results in partial scan'
        Assert ($stress.metrics.entriesChecked -le 16) 'global candidate-probe cap enforced'
        Assert ($stress.metrics.bytesRead -le 65536) 'cumulative real reads fit default MaxScanBytes'
        Assert ($spamStream.BytesRead -eq $stress.metrics.bytesRead) 'I/O metric matches independent counting stream'
        Assert (-not $spamStream.CanWrite) 'test source stream has no write capability'
        Assert (@($stress.warnings | Where-Object { $_ -in @('scan.probe_budget_exhausted','scan.read_budget_exhausted') }).Count -gt 0) 'explicit resource-limit reason'
    } finally { $spamStream.Dispose() }
    Write-Host 'PASS: dense fake ZIPs bounded by global byte and probe limits'

    # Malformed local file header with plausible name causes EOCD search; capped globally.
    $longFake=New-Object byte[] 262144
    $longFake[0]=0x50;$longFake[1]=0x4b;$longFake[2]=3;$longFake[3]=4;$longFake[26]=8
    $longPath=Join-Path $fixtureRoot 'malformed_zip_eocd_stress.img'; WriteSynthetic $longPath $longFake
    $longStream=[ChappyCountingReadStream]::new([IO.File]::OpenRead($longPath))
    try {
        $stress2=Get-ChappyCarvingCandidates -Stream $longStream -MaxScanBytes 32768 -MaxFileBytes 1048576 -MaxProbes 128
        Assert ($stress2.metrics.bytesRead -le 32768) 'repeated EOCD search fits cumulative read budget'
        Assert ($longStream.BytesRead -eq $stress2.metrics.bytesRead) 'malformed ZIP exact actual I/O metric'
        Assert ($stress2.scanIncomplete -and ($stress2.warnings -contains 'scan.read_budget_exhausted')) 'malformed ZIP exhausts budget safely'
    } finally { $longStream.Dispose() }
    Write-Host 'PASS: malformed ZIP EOS search safely consumes shared read budget'
    # False positive starts and invalid stream ranges.
    $f5=Join-Path $fixtureRoot 'fixture_e.img'
    WriteSynthetic $f5 ([Text.Encoding]::ASCII.GetBytes('trash PK' + [char]3 + [char]4 + ' nonzip'))
    $r5=Scan $f5
    Assert (@($r5.items | Where-Object {$_.confidence -eq 'verified'}).Count -eq 0) 'fake ZIP header not verified'
    $s=[IO.File]::OpenRead($f5)
    try {$bad=Get-ChappyCarvingCandidates -Stream $s -StartOffset ($s.Length+1); Assert ($bad.status -eq 'error') 'invalid offset rejected'}finally{$s.Dispose()}
    Write-Host 'PASS: false signatures and out-of-range scan'

    # Malicious caller-controlled metadata must not leak paths, names or free-form text to JSON.
    $privateMarker='PRIVATE_SYNTHETIC_SENTINEL_NEVER_SERIALIZE_731'
    $poisoned=[pscustomobject]@{
        status=$privateMarker
        scanIncomplete=$true
        items=@([pscustomobject]@{
            offsetBytes="../$privateMarker"; lengthBytes=$privateMarker
            format=$privateMarker; confidence=$privateMarker
            evidence=@('zip.local_header',"C:\private\$privateMarker",'gcode.command_count_7','gcode.command_count_999999')
            checks=$privateMarker; crc32Status=$privateMarker
            crc32CheckedEntries=$privateMarker; crc32UncheckedEntries=-7
            truncated=$privateMarker; extraRawFilename="secret_$privateMarker.3mf"
        })
        warnings=@('scan.bounds_reached',"D:\secret\$privateMarker")
        errors=@('stream.not_seekable_readable',"error:$privateMarker")
        metrics=[pscustomobject]@{
            bytesRead=$privateMarker; entriesChecked=-99; readRequests='9'
            scannedBytes=1024; scanWindowBytes=2048; elapsedMilliseconds=12
            rawUserPath="C:\work\$privateMarker"
        }
        privateMessage=$privateMarker
    }
    $poisonPath=Join-Path $fixtureRoot 'synthetic_injection_report.json'
    [void](Write-ChappyCarvingReport -Result $poisoned -ReportPath $poisonPath)
    $poisonText=Get-Content -LiteralPath $poisonPath -Raw
    $poisonJson=$poisonText | ConvertFrom-Json
    Assert (-not $poisonText.Contains($privateMarker)) 'private marker not serialized anywhere'
    Assert ($poisonJson.status -eq 'error') 'arbitrary result status sanitized'
    Assert ($poisonJson.items[0].format -eq 'unknown' -and $poisonJson.items[0].confidence -eq 'unknown') 'untrusted enum fields sanitized'
    Assert ($poisonJson.items[0].checks -eq 'not_validated' -and $poisonJson.items[0].crc32Status -eq 'not_applicable') 'untrusted check/CRC strings sanitized'
    Assert ($poisonJson.items[0].offsetBytes -eq 0 -and $poisonJson.items[0].lengthBytes -eq 0) 'untrusted numeric strings sanitized'
    Assert ($poisonJson.items[0].crc32CheckedEntries -eq 0 -and $poisonJson.items[0].crc32UncheckedEntries -eq 0) 'untrusted counts sanitized'
    Assert ($poisonJson.items[0].evidence.Count -eq 2) 'only allowed evidence and bounded G-code count retained'
    Assert ($poisonJson.items[0].evidence -contains 'gcode.command_count_7') 'numeric G-code reason preserved safely'
    Assert ($poisonJson.warnings.Count -eq 1 -and $poisonJson.warnings[0] -eq 'scan.bounds_reached') 'only allowlisted warning codes emitted'
    Assert ($poisonJson.errors.Count -eq 1 -and $poisonJson.errors[0] -eq 'stream.not_seekable_readable') 'only allowlisted error codes emitted'
    Assert ($poisonJson.metrics.bytesRead -eq 0 -and $poisonJson.metrics.entriesChecked -eq 0) 'metrics numeric sanitization'
    Assert ($poisonJson.metrics.readRequests -eq 9) 'allowed numeric metrics preserved'
    Assert ($null -eq $poisonJson.metrics.PSObject.Properties['rawUserPath']) 'unexpected metric key excluded'
    Assert ($null -eq $poisonJson.items[0].PSObject.Properties['extraRawFilename']) 'unexpected candidate key excluded'
    Write-Host 'PASS: hostile caller strings, paths, fields, diagnostic codes and metrics are sanitized'

    # Report cannot overwrite an existing file.
    $reportBlocked=$false
    try {Write-ChappyCarvingReport -Result $result -ReportPath $report | Out-Null} catch {$reportBlocked=$true}
    Assert $reportBlocked 'JSON report CreateNew no-overwrite'
    Write-Host 'PASS: report no-overwrite'
    Write-Host 'PASS: synthetic C-carving suite completed'
} finally {
    if ([IO.Directory]::Exists($fixtureRoot)) {[IO.Directory]::Delete($fixtureRoot,$true)}
}
}).Count -eq 1) 'safe G-code evidence count retained'
    Write-Host 'PASS: G-code report optional CRC fields and bounded numeric evidence'


    # A non-text interruption after valid commands means at most a partial segment.
    $fragBytes=[Text.Encoding]::ASCII.GetBytes($gcode + "BROKEN_BINARY_FRAGMENT`nG28`n")
    $f6=Join-Path $fixtureRoot 'fixture_fragmented.img'
    $fragImage=New-Object byte[] (256+$fragBytes.Length+8192)
    [Array]::Copy($fragBytes,0,$fragImage,256,$fragBytes.Length)
    WriteSynthetic $f6 $fragImage
    $r6=Scan $f6
    $frag=@($r6.items | Where-Object {$_.format -eq 'gcode' -and $_.offsetBytes -eq 256})
    Assert ($frag.Count -eq 1) 'discontinuous G-code candidate found'
    Assert ($frag[0].fragmentationSuspected -and $frag[0].confidence -eq 'partial') 'discontinuous G-code marked partial'
    Write-Host 'PASS: non-text G-code discontinuity is partial'

    # Bounded scanning intentionally ignores later bytes, reporting incomplete coverage.
    $f7=Join-Path $fixtureRoot 'fixture_bounded.img'
    WriteSynthetic $f7 (New-Object byte[] 0) 2097152
    $r7=Scan $f7 0 4096
    Assert ($r7.scanIncomplete -and $r7.metrics.bytesRead -eq 4096) 'scan is range bounded'
    Write-Host 'PASS: bounded scan reports incomplete coverage'

    # Read-budget stress: adversarial dense local headers cannot induce cumulative I/O amplification.
    $spam=New-Object byte[] (256*1024)
    for ($p=0; $p -lt $spam.Length-8; $p+=8) { $spam[$p]=0x50; $spam[$p+1]=0x4b; $spam[$p+2]=3; $spam[$p+3]=4 }
    $spamPath=Join-Path $fixtureRoot 'dense_fake_signatures.img'; WriteSynthetic $spamPath $spam
    $spamStream=[ChappyCountingReadStream]::new([IO.File]::OpenRead($spamPath))
    try {
        $stress=Get-ChappyCarvingCandidates -Stream $spamStream -StartOffset 0 -MaxScanBytes 65536 -MaxFileBytes 1048576 -MaxCandidates 128 -MaxProbes 16
        Assert ($stress.status -eq 'partial' -and $stress.scanIncomplete) 'dense fake ZIP results in partial scan'
        Assert ($stress.metrics.entriesChecked -le 16) 'global candidate-probe cap enforced'
        Assert ($stress.metrics.bytesRead -le 65536) 'cumulative real reads fit default MaxScanBytes'
        Assert ($spamStream.BytesRead -eq $stress.metrics.bytesRead) 'I/O metric matches independent counting stream'
        Assert (-not $spamStream.CanWrite) 'test source stream has no write capability'
        Assert (@($stress.warnings | Where-Object { $_ -in @('scan.probe_budget_exhausted','scan.read_budget_exhausted') }).Count -gt 0) 'explicit resource-limit reason'
    } finally { $spamStream.Dispose() }
    Write-Host 'PASS: dense fake ZIPs bounded by global byte and probe limits'

    # Malformed local file header with plausible name causes EOCD search; capped globally.
    $longFake=New-Object byte[] 262144
    $longFake[0]=0x50;$longFake[1]=0x4b;$longFake[2]=3;$longFake[3]=4;$longFake[26]=8
    $longPath=Join-Path $fixtureRoot 'malformed_zip_eocd_stress.img'; WriteSynthetic $longPath $longFake
    $longStream=[ChappyCountingReadStream]::new([IO.File]::OpenRead($longPath))
    try {
        $stress2=Get-ChappyCarvingCandidates -Stream $longStream -MaxScanBytes 32768 -MaxFileBytes 1048576 -MaxProbes 128
        Assert ($stress2.metrics.bytesRead -le 32768) 'repeated EOCD search fits cumulative read budget'
        Assert ($longStream.BytesRead -eq $stress2.metrics.bytesRead) 'malformed ZIP exact actual I/O metric'
        Assert ($stress2.scanIncomplete -and ($stress2.warnings -contains 'scan.read_budget_exhausted')) 'malformed ZIP exhausts budget safely'
    } finally { $longStream.Dispose() }
    Write-Host 'PASS: malformed ZIP EOS search safely consumes shared read budget'
    # False positive starts and invalid stream ranges.
    $f5=Join-Path $fixtureRoot 'fixture_e.img'
    WriteSynthetic $f5 ([Text.Encoding]::ASCII.GetBytes('trash PK' + [char]3 + [char]4 + ' nonzip'))
    $r5=Scan $f5
    Assert (@($r5.items | Where-Object {$_.confidence -eq 'verified'}).Count -eq 0) 'fake ZIP header not verified'
    $s=[IO.File]::OpenRead($f5)
    try {$bad=Get-ChappyCarvingCandidates -Stream $s -StartOffset ($s.Length+1); Assert ($bad.status -eq 'error') 'invalid offset rejected'}finally{$s.Dispose()}
    Write-Host 'PASS: false signatures and out-of-range scan'

    # Malicious caller-controlled metadata must not leak paths, names or free-form text to JSON.
    $privateMarker='PRIVATE_SYNTHETIC_SENTINEL_NEVER_SERIALIZE_731'
    $poisoned=[pscustomobject]@{
        status=$privateMarker
        scanIncomplete=$true
        items=@([pscustomobject]@{
            offsetBytes="../$privateMarker"; lengthBytes=$privateMarker
            format=$privateMarker; confidence=$privateMarker
            evidence=@('zip.local_header',"C:\private\$privateMarker",'gcode.command_count_7','gcode.command_count_999999')
            checks=$privateMarker; crc32Status=$privateMarker
            crc32CheckedEntries=$privateMarker; crc32UncheckedEntries=-7
            truncated=$privateMarker; extraRawFilename="secret_$privateMarker.3mf"
        })
        warnings=@('scan.bounds_reached',"D:\secret\$privateMarker")
        errors=@('stream.not_seekable_readable',"error:$privateMarker")
        metrics=[pscustomobject]@{
            bytesRead=$privateMarker; entriesChecked=-99; readRequests='9'
            scannedBytes=1024; scanWindowBytes=2048; elapsedMilliseconds=12
            rawUserPath="C:\work\$privateMarker"
        }
        privateMessage=$privateMarker
    }
    $poisonPath=Join-Path $fixtureRoot 'synthetic_injection_report.json'
    [void](Write-ChappyCarvingReport -Result $poisoned -ReportPath $poisonPath)
    $poisonText=Get-Content -LiteralPath $poisonPath -Raw
    $poisonJson=$poisonText | ConvertFrom-Json
    Assert (-not $poisonText.Contains($privateMarker)) 'private marker not serialized anywhere'
    Assert ($poisonJson.status -eq 'error') 'arbitrary result status sanitized'
    Assert ($poisonJson.items[0].format -eq 'unknown' -and $poisonJson.items[0].confidence -eq 'unknown') 'untrusted enum fields sanitized'
    Assert ($poisonJson.items[0].checks -eq 'not_validated' -and $poisonJson.items[0].crc32Status -eq 'not_applicable') 'untrusted check/CRC strings sanitized'
    Assert ($poisonJson.items[0].offsetBytes -eq 0 -and $poisonJson.items[0].lengthBytes -eq 0) 'untrusted numeric strings sanitized'
    Assert ($poisonJson.items[0].crc32CheckedEntries -eq 0 -and $poisonJson.items[0].crc32UncheckedEntries -eq 0) 'untrusted counts sanitized'
    Assert ($poisonJson.items[0].evidence.Count -eq 2) 'only allowed evidence and bounded G-code count retained'
    Assert ($poisonJson.items[0].evidence -contains 'gcode.command_count_7') 'numeric G-code reason preserved safely'
    Assert ($poisonJson.warnings.Count -eq 1 -and $poisonJson.warnings[0] -eq 'scan.bounds_reached') 'only allowlisted warning codes emitted'
    Assert ($poisonJson.errors.Count -eq 1 -and $poisonJson.errors[0] -eq 'stream.not_seekable_readable') 'only allowlisted error codes emitted'
    Assert ($poisonJson.metrics.bytesRead -eq 0 -and $poisonJson.metrics.entriesChecked -eq 0) 'metrics numeric sanitization'
    Assert ($poisonJson.metrics.readRequests -eq 9) 'allowed numeric metrics preserved'
    Assert ($null -eq $poisonJson.metrics.PSObject.Properties['rawUserPath']) 'unexpected metric key excluded'
    Assert ($null -eq $poisonJson.items[0].PSObject.Properties['extraRawFilename']) 'unexpected candidate key excluded'
    Write-Host 'PASS: hostile caller strings, paths, fields, diagnostic codes and metrics are sanitized'

    # Report cannot overwrite an existing file.
    $reportBlocked=$false
    try {Write-ChappyCarvingReport -Result $result -ReportPath $report | Out-Null} catch {$reportBlocked=$true}
    Assert $reportBlocked 'JSON report CreateNew no-overwrite'
    Write-Host 'PASS: report no-overwrite'
    Write-Host 'PASS: synthetic C-carving suite completed'
} finally {
    if ([IO.Directory]::Exists($fixtureRoot)) {[IO.Directory]::Delete($fixtureRoot,$true)}
}
