#requires -Version 5.1
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Chappy.Carving.psm1') -Force
Add-Type -AssemblyName System.IO.Compression
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
function WriteSynthetic([string]$path,[byte[]]$content,[int]$size=0) {
    $s=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$s.Write($content,0,$content.Length);if($size -gt $content.Length){$s.SetLength($size)}} finally {$s.Dispose()}
}
function Scan([string]$file,[long]$start=0,[long]$count=1048576) {
    $s=[IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {return Get-ChappyCarvingCandidates -Stream $s -StartOffset $start -MaxScanBytes $count -MaxFileBytes 1048576} finally {$s.Dispose()}
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
    Assert (($three[0].checks -eq 'zip_structure_only_no_crc')) 'CRC limitation clearly identified'
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

    # False positive starts and invalid stream ranges.
    $f5=Join-Path $fixtureRoot 'fixture_e.img'
    WriteSynthetic $f5 ([Text.Encoding]::ASCII.GetBytes('trash PK' + [char]3 + [char]4 + ' nonzip'))
    $r5=Scan $f5
    Assert (@($r5.items | Where-Object {$_.confidence -eq 'verified'}).Count -eq 0) 'fake ZIP header not verified'
    $s=[IO.File]::OpenRead($f5)
    try {$bad=Get-ChappyCarvingCandidates -Stream $s -StartOffset ($s.Length+1); Assert ($bad.status -eq 'error') 'invalid offset rejected'}finally{$s.Dispose()}
    Write-Host 'PASS: false signatures and out-of-range scan'

    # Report cannot overwrite an existing file.
    $reportBlocked=$false
    try {Write-ChappyCarvingReport -Result $result -ReportPath $report | Out-Null} catch {$reportBlocked=$true}
    Assert $reportBlocked 'JSON report CreateNew no-overwrite'
    Write-Host 'PASS: report no-overwrite'
    Write-Host 'PASS: synthetic C-carving suite completed'
} finally {
    if ([IO.Directory]::Exists($fixtureRoot)) {[IO.Directory]::Delete($fixtureRoot,$true)}
}
