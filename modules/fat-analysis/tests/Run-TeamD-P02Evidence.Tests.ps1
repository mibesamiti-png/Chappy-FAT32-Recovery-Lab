#Requires -Version 5.1
# Synthetic-only D evidence handoff test. The oracle is read by the scorer only.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $repoRoot 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32GeometryTrust.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32MirrorWindows.psm1') -Force

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D10ObservedMemoryStream : Stream {
    private readonly MemoryStream inner;
    private readonly HashSet<long> unique = new HashSet<long>();
    private readonly long stopAfter;
    private long actual;
    public D10ObservedMemoryStream(byte[] bytes, long stopAfterBytes) {
        inner = new MemoryStream(bytes, false);
        stopAfter = stopAfterBytes;
    }
    public long ActualReadBytes { get { return actual; } }
    public long UniqueReadBytes { get { return unique.Count; } }
    public override bool CanRead { get { return true; } }
    public override bool CanSeek { get { return true; } }
    public override bool CanWrite { get { return false; } }
    public override long Length { get { return inner.Length; } }
    public override long Position { get { return inner.Position; } set { throw new NotSupportedException(); } }
    public override int Read(byte[] buffer, int offset, int count) {
        if (actual >= stopAfter) return 0;
        int allowed = (int)Math.Min((long)count, stopAfter - actual);
        long start = inner.Position;
        int read = inner.Read(buffer, offset, allowed);
        for (int i = 0; i < read; i++) unique.Add(start + i);
        actual += read;
        return read;
    }
    public override long Seek(long offset, SeekOrigin origin) { return inner.Seek(offset, origin); }
    public override void Flush() { throw new NotSupportedException(); }
    public override void SetLength(long value) { throw new NotSupportedException(); }
    public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
    protected override void Dispose(bool disposing) { if (disposing) inner.Dispose(); base.Dispose(disposing); }
}
'@

function Assert-D10([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "D10_EVIDENCE_FAIL: $Name" }
}
function Get-D10Sha([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '') }
    finally { $sha.Dispose() }
}
function Get-D10Evidence([D10ObservedMemoryStream]$Source, [int]$ReadLimit=1024) {
    $geometry = Get-ChappyFatGeometryTrust -Stream $Source
    if ($null -eq $geometry.geometry) { throw 'Synthetic geometry parser returned no bounded candidate' }
    # Use only the numeric geometry emitted by the image parser. Do not pass the
    # fixture mutation manifest, oracle extents, filenames or original hashes.
    $mirror = Get-ChappyFatMirrorWindows -Stream $Source `
        -Fat1OffsetBytes $geometry.geometry.fat1OffsetBytes `
        -Fat2OffsetBytes $geometry.geometry.fat2OffsetBytes `
        -FatLengthBytes $geometry.geometry.fatLengthBytes `
        -WindowEntries 128 -MaxWindows 1 -MaxReadBytes $ReadLimit
    [pscustomobject]@{ geometry=$geometry; mirror=$mirror }
}

$seed = 202611
$cases = @('M00','M01','M02','X02')
$results = @{}
foreach ($caseId in $cases) {
    $fixture = New-ChappyA3DDamagedFixture -Seed $seed -Case $caseId
    $beforeHash = Get-D10Sha $fixture.image
    Assert-D10 ($beforeHash -ceq $fixture.manifest.imageSha256) "$caseId synthetic fixture manifest" 
    $source = [D10ObservedMemoryStream]::new($fixture.image, [long]::MaxValue)
    try {
        Assert-D10 (-not $source.CanWrite) "$caseId read-only source"
        $evidence = Get-D10Evidence $source
        $afterHash = Get-D10Sha $fixture.image
        Assert-D10 ($beforeHash -ceq $afterHash) "$caseId source bytes unchanged"
        Assert-D10 ($source.ActualReadBytes -le 2048) "$caseId total observation read cap"
        Assert-D10 ($source.UniqueReadBytes -le $source.ActualReadBytes) "$caseId unique physical read accounting"
        if ($caseId -in @('M00','M01','M02')) {
            Assert-D10 ($evidence.geometry.trustDecision -eq 'reject' -and
                $evidence.geometry.reasons -contains 'bpb.fsinfo_location_invalid' -and
                $evidence.geometry.reasons -contains 'bpb.backup_vbr_location_invalid') "$caseId geometry remains untrusted"
            Assert-D10 ($evidence.mirror.metrics.bytesRead -eq 1024 -and
                $evidence.mirror.metrics.entriesChecked -eq 128) "$caseId bounded mirror sample"
        }
        switch ($caseId) {
            'M00' { Assert-D10 ($evidence.mirror.metrics.differentEntries -eq 0) 'M00 sampled mirror agreement only' }
            'M01' { Assert-D10 ($evidence.mirror.metrics.differentEntries -eq 0) 'M01 fragmented copies agree; no chain-success claim' }
            'M02' { Assert-D10 ($evidence.mirror.metrics.differentEntries -eq 1) 'M02 one sampled FAT-copy disagreement' }
            'X02' {
                Assert-D10 ($evidence.geometry.trustDecision -eq 'reject' -and
                    $evidence.geometry.reasons -contains 'geometry.partition_exceeds_stream') 'X02 declared image extent exceeds stream'
                Assert-D10 ($evidence.mirror.metrics.differentEntries -eq 0) 'X02 retained FAT windows still agree; this does not detect payload truncation'
            }
        }
        $results[$caseId] = [pscustomobject]@{
            case=$caseId; trust=$evidence.geometry.trustDecision
            geometryReasons=@($evidence.geometry.reasons)
            differences=$evidence.mirror.metrics.differentEntries
            compared=$evidence.mirror.metrics.entriesChecked
            mirrorBytes=$evidence.mirror.metrics.bytesRead
            totalBytes=$source.ActualReadBytes; uniqueBytes=$source.UniqueReadBytes
            imageLength=$fixture.image.Length
        }
        Write-Host ('D synthetic {0}: trust={1}, differingEntries={2}, compared={3}, bytes actual/unique={4}/{5}, inputLength={6}.' -f
            $caseId,$evidence.geometry.trustDecision,$evidence.mirror.metrics.differentEntries,
            $evidence.mirror.metrics.entriesChecked,$source.ActualReadBytes,$source.UniqueReadBytes,$fixture.image.Length)
    } finally { $source.Dispose() }
}
Assert-D10 ($results.M00.differences -eq 0 -and $results.M01.differences -eq 0 -and
    $results.M02.differences -eq 1) 'same-corpus clean, fragmented and mirror-disagreement distinction'

# Fault injection is separate from X02: its payload truncation does not shorten
# the FAT windows. Stop a non-writable stream after 1200 bytes (1024 geometry
# bytes plus 176 FAT bytes) to prove the mirror reader preserves incomplete I/O.
$faultFixture = New-ChappyA3DDamagedFixture -Seed $seed -Case M00
$faultBeforeHash = Get-D10Sha $faultFixture.image
$faultSource = [D10ObservedMemoryStream]::new($faultFixture.image, 1200)
try {
    $fault = Get-D10Evidence $faultSource
    Assert-D10 ((Get-D10Sha $faultFixture.image) -ceq $faultBeforeHash) 'short-read source bytes unchanged'
    Assert-D10 ($faultSource.ActualReadBytes -eq 1200 -and $faultSource.UniqueReadBytes -eq 1200) 'injected short-read byte accounting'
    Assert-D10 ($fault.mirror.scanIncomplete -and $fault.mirror.warnings -contains 'io.truncated_fat_window') 'short read preserved as incomplete evidence'
    Assert-D10 ($fault.mirror.metrics.bytesRead -eq 176) 'short-read FAT bytes separate from geometry bytes'
    Write-Host ('D synthetic short-read: geometry=1024 bytes, mirror={0}, total={1}, unique={2}, incomplete={3}.' -f
        $fault.mirror.metrics.bytesRead,$faultSource.ActualReadBytes,$faultSource.UniqueReadBytes,$fault.mirror.scanIncomplete)
} finally { $faultSource.Dispose() }
Write-Host 'PASS: D synthetic handoff separates fragmented agreement, mirror disagreement, X02 geometry rejection, and injected short-read uncertainty.'

