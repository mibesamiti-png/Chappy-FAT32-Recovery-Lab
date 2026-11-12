#Requires -Version 5.1
# Team A R7 synthetic-only shared physical-source read accounting.
# Never accepts a path, opens a physical device, writes an IMG or extracts data.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-Chappy3DDamagedFixture.ps1')
. (Join-Path $root 'modules\directory\DirectoryScanner.ps1')
Import-Module (Join-Path $root 'modules\carving\Chappy.Carving.psm1') -Force
Import-Module (Join-Path $root 'modules\fat-analysis\Fat32ObservedIoEvidence.psm1') -Force

if (-not ('ChappyA7SharedSource' -as [type])) {
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;

public sealed class ChappyA7ReadEvent {
    public string Consumer { get; set; }
    public long OffsetBytes { get; set; }
    public int ReturnedBytes { get; set; }
}
public sealed class ChappyA7SharedSource : Stream {
    private readonly Stream source;
    private readonly long limit;
    private long used;
    private long requests;
    private string consumer;
    private readonly HashSet<long> seen = new HashSet<long>();
    private readonly List<ChappyA7ReadEvent> events = new List<ChappyA7ReadEvent>();
    public ChappyA7SharedSource(Stream input, long maxSourceBytes) {
        if (input == null || !input.CanRead || !input.CanSeek || input.CanWrite)
            throw new ArgumentException("Synthetic source must be readable, seekable and strictly nonwritable");
        if (maxSourceBytes < 1024 || maxSourceBytes > 131072)
            throw new ArgumentOutOfRangeException("maxSourceBytes");
        source=input; limit=maxSourceBytes;
    }
    public void BeginConsumer(string name) {
        if (name!="geometry" && name!="directory" && name!="carving" && name!="fat")
            throw new ArgumentException("Unknown source-read consumer");
        consumer=name;
    }
    public long TotalBytes { get { return used; } }
    public long UniqueBytes { get { return seen.Count; } }
    public long DuplicateBytes { get { return used-seen.Count; } }
    public long ReadRequests { get { return requests; } }
    public long MaximumBytes { get { return limit; } }
    public ChappyA7ReadEvent[] GetEvents() { return events.ToArray(); }
    public override bool CanRead { get { return true; } }
    public override bool CanSeek { get { return true; } }
    public override bool CanWrite { get { return false; } }
    public override long Length { get { return source.Length; } }
    public override long Position {
        get { return source.Position; }
        set { throw new NotSupportedException(); }
    }
    public override long Seek(long offset, SeekOrigin origin) { return source.Seek(offset,origin); }
    public override int Read(byte[] buffer, int offset, int count) {
        if (String.IsNullOrEmpty(consumer))
            throw new InvalidOperationException("BeginConsumer required");
        if (count < 0 || buffer == null || offset < 0 || offset > buffer.Length-count)
            throw new ArgumentException("Invalid read request");
        requests++;
        // An oversized request FAILS CLOSED; never disguise budget exhaustion as EOF.
        if (count > limit-used)
            throw new IOException("A7.shared_source_budget_exhausted");
        long at=source.Position;
        int n=source.Read(buffer,offset,count);
        if (n > 0) {
            used+=n;
            events.Add(new ChappyA7ReadEvent {Consumer=consumer,OffsetBytes=at,ReturnedBytes=n});
            for(int i=0;i<n;i++)seen.Add(at+i);
        }
        return n;
    }
    public override void Flush() {}
    public override void SetLength(long length) { throw new NotSupportedException(); }
    public override void Write(byte[] buffer,int offset,int count) { throw new NotSupportedException(); }
    // The underlying read-only Stream is caller-owned.
}
'@
}

function Assert-A7([bool]$Okay,[string]$Why) {
    if (-not $Okay) { throw ('A7_SYNTHETIC_FAIL: '+$Why) }
}

$seed=202611
$clean=New-ChappyA3DCleanFixture -Seed $seed
$truth=$clean.oracle[1]
foreach ($case in @('M00','P02')) {
    $fixture=New-ChappyA3DDamagedFixture -Seed $seed -Case $case
    $inputSha=Get-A3DSha256 $fixture.image
    $memory=[IO.MemoryStream]::new($fixture.image,$false)
    $meter=[ChappyA7SharedSource]::new($memory,120000L)
    try {
        Assert-A7 (-not $meter.CanWrite -and $meter.MaximumBytes -eq 120000) 'strict_shared_source'
        $meter.BeginConsumer('geometry')
        $geometry=Get-ChappyFat32Geometry -Stream $meter
        Assert-A7 ($geometry.fatCount -eq 2) 'bounded_synthetic_geometry'

        $meter.BeginConsumer('directory')
        $directory=Get-ChappyDirectoryCandidates -Stream $meter -Geometry $geometry -MaxScanBytes 512 -MaxCandidates 16 -MaxDirectories 4 -RecordDirectoryReadSpans -MaxDirectoryReadSpans 8
        Assert-A7 ($directory.team -ceq 'B' -and $directory.directoryReadEvidence.status -ceq 'recorded' -and
            $directory.directoryReadEvidence.readEvents -eq 1 -and $directory.metrics.bytesRead -eq 512) 'B_observed_cluster_read'

        $meter.BeginConsumer('carving')
        $carving=Get-ChappyCarvingCandidates -Stream $meter -MaxScanBytes 65536 -ExtraValidationReadBytes 32768 -MaxFileBytes 4096 -MaxCandidates 16 -MaxProbes 16 -MaxProbeBytes 8192
        Assert-A7 ($carving.team -ceq 'C' -and $carving.status -ne 'error') 'C_readonly_format_observations'

        $meter.BeginConsumer('fat')
        $fat=Get-ChappyFatObservedIoEvidence -Stream $meter -Mode MirrorAndChain -MaxReadBytes 2048
        Assert-A7 ($fat.team -ceq 'D' -and $fat.experimentalDefaultOff -eq $true -and
            -not $fat.writePermitted -and $fat.sourceDecision -ceq 'not_selected') 'D_observed_only'

        $events=@($meter.GetEvents())
        $bEvents=@($events|Where-Object{$_.Consumer -ceq 'directory'})
        $cEvents=@($events|Where-Object{$_.Consumer -ceq 'carving'})
        $dEvents=@($events|Where-Object{$_.Consumer -ceq 'fat'})
        Assert-A7 ($bEvents.Count -eq 1 -and $cEvents.Count -gt 0 -and $dEvents.Count -gt 0) 'all_three_observed_at_source'
        $span=$directory.directoryReadEvidence.spans[0]
        Assert-A7 ($bEvents[0].OffsetBytes -eq [long]$span.offsetBytes -and
            $bEvents[0].ReturnedBytes -eq [long]$span.lengthBytes) 'B_trace_equals_source_meter'
        $dTotal=0L
        foreach($item in $dEvents){$dTotal += [long]$item.ReturnedBytes}
        Assert-A7 ($dTotal -eq [long]$fat.metrics.bytesRead -and $dTotal -le 2048) 'D_trace_equals_source_meter'

        $sum=0L
        foreach($evt in $events){$sum += [long]$evt.ReturnedBytes}
        Assert-A7 ($sum -eq $meter.TotalBytes -and $meter.TotalBytes -le 120000 -and
            $meter.UniqueBytes -le $meter.TotalBytes -and $meter.DuplicateBytes -gt 0 -and
            $meter.ReadRequests -ge $events.Count) 'shared_cumulative_quota_and_unique_union'

        $candidate=@($carving.items|Where-Object{$_.format -ceq '3mf' -and
            $_.offsetBytes -eq $truth.extents[0].offsetBytes})
        Assert-A7 ($candidate.Count -eq 1 -and $candidate[0].confidence -ceq 'verified' -and
            $candidate[0].integrityScope -ceq 'structural_only_not_original_file_integrity') 'C_structure_not_originality'
        [byte[]]$candidateBytes=[byte[]]::new([int]$candidate[0].lengthBytes)
        [Array]::Copy($fixture.image,[int]$candidate[0].offsetBytes,$candidateBytes,0,$candidateBytes.Length)
        # Only the scorer compares against the clean original SHA.
        $originalExact=(Get-A3DSha256 $candidateBytes) -ceq $truth.sha256
        Assert-A7 ($originalExact -eq ($case -eq 'M00')) 'independent_original_SHA_not_exposed_to_modules'

        Assert-A7 ((Get-A3DSha256 $fixture.image) -ceq $inputSha) 'unchanged_synthetic_source'
        Write-Host ('A7 SHARED synthetic={0} totalBytes={1} uniqueBytes={2} duplicateBytes={3} reads={4} B_spans={5} D_events={6} oracleExact={7}' -f
            $case,$meter.TotalBytes,$meter.UniqueBytes,$meter.DuplicateBytes,
            $meter.ReadRequests,$directory.directoryReadEvidence.recordedSpans,
            $fat.readEvents.Count,$originalExact)
    } finally {
        $memory.Dispose()
    }
}

# Direct negative gate: budget exhaustion raises a reason instead of quietly
# returning zero bytes and being mistaken for real IMG end of file.
$shortMemory=[IO.MemoryStream]::new([byte[]]::new(2048),$false)
$short=[ChappyA7SharedSource]::new($shortMemory,1024L)
try {
    $short.BeginConsumer('carving')
    $rejected=$false
    try {
        [byte[]]$oversize=[byte[]]::new(1025)
        [void]$short.Read($oversize,0,$oversize.Length)
    } catch {
        # PowerShell 5.1 wraps a .NET Stream.Read IOException in a
        # MethodInvocationException; inspect the causal chain, not just the
        # outer wrapper's display string. Never accept an unrelated exception.
        $fault=$_.Exception
        for($depth=0; $depth -lt 5 -and $null -ne $fault; $depth++) {
            if($fault.Message -match 'A7[.]shared_source_budget_exhausted'){
                $rejected=$true
                break
            }
            $fault=$fault.InnerException
        }
    }
    Assert-A7 ($rejected -and $short.TotalBytes -eq 0) 'hard_fail_closed_on_budget_exhaustion'
    $writeRejected=$false
    try{ $short.Write([byte[]]@(1),0,1) }catch{ $writeRejected=$true }
    Assert-A7 $writeRejected 'write_prohibited'
} finally {$shortMemory.Dispose()}
Write-Host 'PASS: A7 shared B/C/D synthetic source meter, origin scoped read events, no original identity promotion and bounded refusal.'
