#Requires -Version 5.1
# Issue #73 R6-P12: held-out position sweep of the P11 test-only sampler.
# Inputs are generated FAT32 memory images. No disk or image paths are accepted.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32GeometryTrust.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32MirrorWindows.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32ChainStats.psm1') -Force
$script:pass = 0
$script:fail = 0

if (-not ('D26ReadMeter' -as [type])) {
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D26ReadMeter : Stream {
    private readonly MemoryStream backing;
    private readonly Dictionary<long,byte> observed = new Dictionary<long,byte>();
    private readonly long dLimit, outerLimit, stopAfter;
    private readonly int callLimit, chunkLimit;
    private long actual, calls, denied, earlyZeros;
    public D26ReadMeter(byte[] image, long stop, int chunk) {
        if(image == null || stop < 0 || chunk < 1 || chunk > 4096)
            throw new ArgumentException("Invalid synthetic stream limits");
        backing = new MemoryStream(image, false);
        dLimit = 2048; outerLimit = 120000; callLimit = 256;
        stopAfter = stop; chunkLimit = chunk;
    }
    public long Actual { get { return actual; } }
    public long Unique { get { return observed.Count; } }
    public long Repeated { get { return actual-observed.Count; } }
    public long Calls { get { return calls; } }
    public long Denied { get { return denied; } }
    public long EarlyZeros { get { return earlyZeros; } }
    public bool Has(long p, int n) {
        if(p < 0 || n < 0 || p > long.MaxValue-n) return false;
        for(int i=0;i<n;i++) if(!observed.ContainsKey(p+i)) return false;
        return true;
    }
    public uint ObservedUInt32(long p) {
        if(!Has(p,4)) throw new InvalidOperationException("Bytes were not physically returned");
        return (uint)(observed[p] | ((uint)observed[p+1]<<8) |
            ((uint)observed[p+2]<<16) | ((uint)observed[p+3]<<24));
    }
    public long CompletePairedEntries(long fat1, long fat2, long entries) {
        long complete=0;
        for(long i=0;i<entries;i++) if(Has(fat1+i*4,4) && Has(fat2+i*4,4)) complete++;
        return complete;
    }
    public override bool CanRead { get { return true; } }
    public override bool CanSeek { get { return true; } }
    public override bool CanWrite { get { return false; } }
    public override long Length { get { return backing.Length; } }
    public override long Position { get { return backing.Position; } set { throw new NotSupportedException(); } }
    public override long Seek(long offset, SeekOrigin origin) { return backing.Seek(offset,origin); }
    public override int Read(byte[] buffer, int offset, int count) {
        if(buffer == null || offset < 0 || count < 0 || offset > buffer.Length-count)
            throw new ArgumentException("Invalid read buffer");
        if(calls >= callLimit || count > dLimit-actual || count > outerLimit-actual) {
            denied++; throw new IOException("D26 physical read limit rejected");
        }
        calls++;
        if(count == 0) return 0;
        long start = backing.Position;
        if(actual >= stopAfter) { if(start < backing.Length) earlyZeros++; return 0; }
        int request = (int)Math.Min((long)count, Math.Min((long)chunkLimit, stopAfter-actual));
        int n = backing.Read(buffer,offset,request);
        if(n == 0 && start < backing.Length) earlyZeros++;
        for(int i=0;i<n;i++) observed[start+i]=buffer[offset+i];
        actual += n;
        return n;
    }
    public override void Flush() { throw new NotSupportedException(); }
    public override void SetLength(long value) { throw new NotSupportedException(); }
    public override void Write(byte[] buffer,int offset,int count) { throw new NotSupportedException(); }
    protected override void Dispose(bool disposing) { if(disposing) backing.Dispose(); base.Dispose(disposing); }
}
'@
}

function Assert-D26([bool]$Condition, [string]$Name) {
    if ($Condition) { $script:pass++; Write-Host ('PASS ' + $Name) }
    else { $script:fail++; Write-Host ('FAIL ' + $Name) }
}
function Patch-D26([byte[]]$Image, [long]$Offset, [uint32]$Value) {
    [Array]::Copy([BitConverter]::GetBytes($Value), 0, $Image, [int]$Offset, 4)
}
function Get-D26Sha([byte[]]$Image) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hash.ComputeHash($Image)).Replace('-', '') }
    finally { $hash.Dispose() }
}
function Get-D26Sample {
    param([D26ReadMeter]$Source, [ValidateSet('fixed','adaptive')][string]$Method)
    if (-not $Source.CanRead -or -not $Source.CanSeek -or $Source.CanWrite) {
        throw 'Require readable, seekable, strictly non-writable input'
    }
    $geo = Get-ChappyFatGeometryTrust -Stream $Source -MaxReadBytes 1024
    if ($geo.trustDecision -eq 'reject' -or $null -eq $geo.geometry) {
        return [pscustomobject]@{ state='unknown'; target=$null; starts=@(); windows=@(); different=0; cycles=0; detected=$false; scanIncomplete=$true }
    }
    $g = $geo.geometry
    $fat1 = [long]$g.fat1OffsetBytes
    $fat2 = [long]$g.fat2OffsetBytes
    $fatLength = [long]$g.fatLengthBytes
    $clusters = [long]$g.dataClusterCount
    $entries = [long]($fatLength / 4L)
    if ($fat1 -lt 0 -or $fat2 -le $fat1 -or $fatLength -le 0 -or
        $fatLength % 4 -ne 0 -or $entries -gt 1000000 -or
        $clusters -lt 65525 -or $entries -lt ($clusters + 2) -or
        $fat1 -gt ($Source.Length - $fatLength) -or
        $fat2 -gt ($Source.Length - $fatLength) -or $fat1 + $fatLength -gt $fat2) {
        return [pscustomobject]@{ state='unknown'; target=$null; starts=@(); windows=@(); different=0; cycles=0; detected=$false; scanIncomplete=$true }
    }
    $readArgs = @{ Stream=$Source; Fat1OffsetBytes=$fat1; Fat2OffsetBytes=$fat2;
        FatLengthBytes=$fatLength; WindowEntries=16; MaxWindows=1; MaxReadBytes=128 }
    $first = Get-ChappyFatMirrorWindows @readArgs -StartEntry 0
    $windows = New-Object System.Collections.ArrayList
    foreach ($window in @($first.items)) { [void]$windows.Add($window) }
    $starts = New-Object System.Collections.ArrayList
    [void]$starts.Add([long]0)
    $prefixComplete = (@($first.items).Count -eq 1 -and
        $first.items[0].comparedEntries -eq 16 -and -not $first.items[0].scanIncomplete)
    $target = $null
    if ($Method -eq 'adaptive' -and $prefixComplete) {
        foreach ($index in 9..15) {
            $p = $fat1 + [long]$index * 4L
            $q = $fat2 + [long]$index * 4L
            if (-not $Source.Has($p,4) -or -not $Source.Has($q,4)) { continue }
            $x = ([long]$Source.ObservedUInt32($p)) -band 0x0FFFFFFF
            $y = ([long]$Source.ObservedUInt32($q)) -band 0x0FFFFFFF
            if ($x -eq $y -and $x -ge 16 -and $x -le ($clusters + 1L) -and
                $x -le ($entries - 16L)) { $target = [long]$x; break }
        }
    }
    $later = if ($null -ne $target) { @([long]$target,[long]128) } else { @([long]128,[long]256) }
    foreach ($start in $later) {
        $sample = Get-ChappyFatMirrorWindows @readArgs -StartEntry ([long]$start)
        foreach ($window in @($sample.items)) { [void]$windows.Add($window) }
        [void]$starts.Add([long]$start)
    }
    $chain = Get-ChappyFatChainAnomalyStats -Stream $Source -Fat1OffsetBytes $fat1 -Fat2OffsetBytes $fat2 `
        -FatLengthBytes $fatLength -MaxDataCluster ($clusters + 1L) `
        -StartClusters ([long[]]@(2,3,4,5,6,7,8)) -MaxStepsPerChain 8 -MaxTotalEntries 32 -MaxReadBytes 448
    $different = 0L
    foreach ($window in $windows) { $different += [long]$window.differentEntries }
    $cycles = @($chain.items | Where-Object { $_.terminal -eq 'cycle' }).Count
    return [pscustomobject]@{
        state='partial_numeric_only'; target=$target; starts=@($starts.ToArray()); windows=@($windows.ToArray())
        different=$different; cycles=$cycles; detected=($different -gt 0 -or $cycles -gt 0)
        scanIncomplete=$true; copyWinner='not_selected'; owner='unknown'; original='unknown'; writePermitted=$false
    }
}
function Invoke-D26Trial([byte[]]$Image, [string]$Method) {
    $source = [D26ReadMeter]::new($Image,[long]::MaxValue,4096)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $result = Get-D26Sample -Source $source -Method $Method
        $watch.Stop()
        return [pscustomobject]@{ mode=$Method; result=$result; source=$source; ms=$watch.ElapsedMilliseconds }
    } catch {
        $source.Dispose()
        throw
    }
}

$seeds = @(202614,202615,202616)
$targetStarts = @(128,143,144,255,256,257,271,272,320,512)
$fatSectors = [long][Math]::Ceiling(4.0 * (65541 + 2) / 512.0)
$fat1Base = 33L * 512L
$fat2Base = $fat1Base + $fatSectors * 512L
$scores = @{
    fixed=@{ TP=0; FP=0; FN=0; TN=0 }
    adaptive=@{ TP=0; FP=0; FN=0; TN=0 }
}
$totals = @{
    fixed=@{ actual=0L; unique=0L; repeated=0L; calls=0L; pairedEntries=0L; ms=0L }
    adaptive=@{ actual=0L; unique=0L; repeated=0L; calls=0L; pairedEntries=0L; ms=0L }
}
$casesRun = 0

foreach ($seed in $seeds) {
    foreach ($target in $targetStarts) {
        $fixture = New-ChappyA3DStandardFixture -Seed $seed -SectorsPerCluster 1 -Fragment3Mf
        [byte[]]$image = $fixture.image
        $events = New-Object System.Collections.ArrayList
        foreach ($fat in @($fat1Base,$fat2Base)) { Patch-D26 $image ($fat + 56L) ([uint32]$target) }
        foreach ($fat in @($fat1Base,$fat2Base)) { Patch-D26 $image ($fat + [long]$target * 4L) ([uint32]0x0FFFFFFF) }
        Patch-D26 $image ($fat2Base + [long]$target * 4L) ([uint32]1)
        [void]$events.Add([long]$target)
        if ($target -ne 256) {
            Patch-D26 $image ($fat2Base + 1024L) ([uint32]1)
            [void]$events.Add([long]256)
        }
        $before = Get-D26Sha $image
        $fixed = Invoke-D26Trial -Image $image -Method fixed
        $adaptive = Invoke-D26Trial -Image $image -Method adaptive
        Assert-D26 ((Get-D26Sha $image) -ceq $before) ("seed {0} target {1} generated image unchanged" -f $seed,$target)
        foreach ($trial in @($fixed,$adaptive)) {
            $method = $trial.result
            $meter = $trial.source
            Assert-D26 (-not $meter.CanWrite -and $method.writePermitted -eq $false -and
                $method.copyWinner -ceq 'not_selected' -and $method.original -ceq 'unknown') `
                ("seed {0} target {1} {2} read-only and no identity claim" -f $seed,$target,$trial.result.starts[0])
            Assert-D26 ($meter.Actual -le 2048 -and $meter.Calls -le 256 -and
                $meter.Denied -eq 0 -and $meter.Unique -le $meter.Actual -and
                $meter.Repeated -eq ($meter.Actual - $meter.Unique)) `
                ("seed {0} target {1} physical limits" -f $seed,$target)
            $pairedEntries = $meter.CompletePairedEntries($fat1Base,$fat2Base,65664L)
            $expectedDiff = 0
            foreach ($window in @($method.windows)) {
                foreach ($eventIndex in $events) {
                    if ($eventIndex -ge $window.startEntry -and $eventIndex -lt $window.endEntryExclusive) {
                        $expectedDiff++
                    }
                }
            }
            Assert-D26 ($method.different -eq $expectedDiff) `
                ("seed {0} target {1} {2} sampled discrepancy count matches independent event positions" -f $seed,$target,$trial.mode)
            $scored = @($events.ToArray())
            foreach ($eventIndex in $scored) {
                $pairedBytes = $meter.Has($fat1Base + [long]$eventIndex * 4L,4) -and
                    $meter.Has($fat2Base + [long]$eventIndex * 4L,4)
                $sampledEventWindows = @($method.windows | Where-Object {
                    $eventIndex -ge $_.startEntry -and $eventIndex -lt $_.endEntryExclusive
                })
                $coveredWindow = $sampledEventWindows.Count -gt 0
                Assert-D26 ($pairedBytes -eq $coveredWindow) `
                    ("seed {0} target {1} {2} event {3} physical pair coverage is explicit" -f $seed,$target,$trial.mode,$eventIndex)
                $eventReported = $pairedBytes -and (@($sampledEventWindows | Where-Object { $_.differentEntries -gt 0 }).Count -gt 0)
                if ($eventReported) { $scores[$trial.mode].TP++ } else { $scores[$trial.mode].FN++ }
            }
            $totals[$trial.mode].actual += $meter.Actual
            $totals[$trial.mode].unique += $meter.Unique
            $totals[$trial.mode].repeated += $meter.Repeated
            $totals[$trial.mode].calls += $meter.Calls
            $totals[$trial.mode].pairedEntries += $pairedEntries
            $totals[$trial.mode].ms += $trial.ms
        }
        Write-Host ('D P12 seed={0} target={1} fixedStarts={2} adaptiveTarget={3} targetPair={4}/{5} displaced256Pair={6}/{7} pairedEntries={8}/{9}/65664 bytes={10}/{11} hashes={12}->{13}.' -f
            $seed,$target,($fixed.result.starts -join ','),$adaptive.result.target,
            ($fixed.source.Has($fat1Base + [long]$target*4L,4) -and $fixed.source.Has($fat2Base + [long]$target*4L,4)),
            ($adaptive.source.Has($fat1Base + [long]$target*4L,4) -and $adaptive.source.Has($fat2Base + [long]$target*4L,4)),
            ($fixed.source.Has($fat1Base + 1024L,4) -and $fixed.source.Has($fat2Base + 1024L,4)),
            ($adaptive.source.Has($fat1Base + 1024L,4) -and $adaptive.source.Has($fat2Base + 1024L,4)),
            $fixed.source.CompletePairedEntries($fat1Base,$fat2Base,65664L),
            $adaptive.source.CompletePairedEntries($fat1Base,$fat2Base,65664L),
            $fixed.source.Actual,$adaptive.source.Actual,$before,(Get-D26Sha $image))
        $fixed.source.Dispose(); $adaptive.source.Dispose()
        $casesRun++
        $image = $null; $fixture = $null; [GC]::Collect()
    }

    # A healthy link is a negative control. It is observed but both FAT copies
    # point identically to EOC, so no mirror-mismatch event should be invented.
    $healthyFixture = New-ChappyA3DStandardFixture -Seed $seed -SectorsPerCluster 1 -Fragment3Mf
    [byte[]]$healthy = $healthyFixture.image
    foreach ($fat in @($fat1Base,$fat2Base)) {
        Patch-D26 $healthy ($fat + 56L) ([uint32]512)
        Patch-D26 $healthy ($fat + 512L*4L) ([uint32]0x0FFFFFFF)
    }
    $healthySha = Get-D26Sha $healthy
    $healthyFixed = Invoke-D26Trial -Image $healthy -Method fixed
    $healthyAdaptive = Invoke-D26Trial -Image $healthy -Method adaptive
    Assert-D26 ((Get-D26Sha $healthy) -ceq $healthySha) ("seed {0} healthy control image unchanged" -f $seed)
    foreach ($trial in @($healthyFixed,$healthyAdaptive)) {
        $expectedTarget = if ($trial.mode -eq 'adaptive') { 512 } else { $null }
        Assert-D26 (-not $trial.result.detected -and $trial.result.target -eq $expectedTarget) `
            ("seed {0} healthy control {1} no false mismatch" -f $seed,$trial.mode)
        Assert-D26 ($trial.source.Actual -le 2048 -and $trial.source.Calls -le 256 -and $trial.source.Denied -eq 0) `
            ("seed {0} healthy control physical limits" -f $seed)
        $scores[$trial.mode].TN++
        $totals[$trial.mode].actual += $trial.source.Actual
        $totals[$trial.mode].unique += $trial.source.Unique
        $totals[$trial.mode].repeated += $trial.source.Repeated
        $totals[$trial.mode].calls += $trial.source.Calls
        $totals[$trial.mode].pairedEntries += $trial.source.CompletePairedEntries($fat1Base,$fat2Base,65664L)
        $totals[$trial.mode].ms += $trial.ms
    }
    Write-Host ('D P12 seed={0} healthyLink fallbackTarget={1}, fixed/adaptive bytes={2}/{3}, SHA={4}->{5}.' -f
        $seed,$healthyAdaptive.result.target,$healthyFixed.source.Actual,$healthyAdaptive.source.Actual,
        $healthySha,(Get-D26Sha $healthy))
    $healthyFixed.source.Dispose(); $healthyAdaptive.source.Dispose()
    $healthy = $null; $healthyFixture = $null; [GC]::Collect()

    # No-link fallback control with a single mismatch at the fixed index 256.
    $fallbackFixture = New-ChappyA3DStandardFixture -Seed $seed -SectorsPerCluster 1 -Fragment3Mf
    [byte[]]$fallback = $fallbackFixture.image
    Patch-D26 $fallback ($fat2Base + 1024L) ([uint32]1)
    $fallbackSha = Get-D26Sha $fallback
    $fallbackFixed = Invoke-D26Trial -Image $fallback -Method fixed
    $fallbackAdaptive = Invoke-D26Trial -Image $fallback -Method adaptive
    Assert-D26 ((Get-D26Sha $fallback) -ceq $fallbackSha) ("seed {0} no-link control image unchanged" -f $seed)
    Assert-D26 ($null -eq $fallbackAdaptive.result.target -and
        ($fallbackAdaptive.result.starts -join ',') -ceq '0,128,256') ("seed {0} adaptive no-link falls back to fixed window schedule" -f $seed)
    foreach ($trial in @($fallbackFixed,$fallbackAdaptive)) {
        $meter=$trial.source
        $hits=$meter.Has($fat1Base+1024L,4) -and $meter.Has($fat2Base+1024L,4)
        Assert-D26 ($hits -and $trial.result.different -gt 0 -and
            $meter.Actual -le 2048 -and $meter.Calls -le 256 -and $meter.Denied -eq 0) `
            ("seed {0} no-link fallback samples index 256 within bounds" -f $seed)
        if ($hits -and $trial.result.different -gt 0) { $scores[$trial.mode].TP++ } else { $scores[$trial.mode].FN++ }
        $totals[$trial.mode].actual += $meter.Actual
        $totals[$trial.mode].unique += $meter.Unique
        $totals[$trial.mode].repeated += $meter.Repeated
        $totals[$trial.mode].calls += $meter.Calls
        $totals[$trial.mode].pairedEntries += $meter.CompletePairedEntries($fat1Base,$fat2Base,65664L)
        $totals[$trial.mode].ms += $trial.ms
    }
    Write-Host ('D P12 seed={0} no-link fallback fixed/adaptive bytes={1}/{2}, SHA={3}->{4}.' -f
        $seed,$fallbackFixed.source.Actual,$fallbackAdaptive.source.Actual,$fallbackSha,(Get-D26Sha $fallback))
    $fallbackFixed.source.Dispose(); $fallbackAdaptive.source.Dispose()
    $fallback = $null; $fallbackFixture = $null; [GC]::Collect()
}

Write-Host ('D P12 totals: cases={0} scoredEvents fixed TP/FP/FN/TN={1}/{2}/{3}/{4}, adaptive={5}/{6}/{7}/{8}.' -f
    $casesRun,$scores.fixed.TP,$scores.fixed.FP,$scores.fixed.FN,$scores.fixed.TN,
    $scores.adaptive.TP,$scores.adaptive.FP,$scores.adaptive.FN,$scores.adaptive.TN)
foreach ($mode in @('fixed','adaptive')) {
    Write-Host ('D P12 resources {0}: actual={1}, sourceLocalUniqueSum={2}, repeated={3}, calls={4}, sourceLocalPairedEntrySum={5}, elapsedMs={6}.' -f
        $mode,$totals[$mode].actual,$totals[$mode].unique,$totals[$mode].repeated,$totals[$mode].calls,$totals[$mode].pairedEntries,$totals[$mode].ms)
}
if ($script:fail -gt 0) { throw ("P12 synthetic assertions failed: {0}/{1}" -f $script:fail,($script:pass+$script:fail)) }
Write-Host ('PASS: D P12 held-out target displacement sweep {0}/{1}; event coverage remains partial evidence only.' -f
    $script:pass,($script:pass+$script:fail))
