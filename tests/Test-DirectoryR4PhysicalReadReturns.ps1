#requires -Version 5.1
# Team B R4 P1 - generated-only partial Stream.Read byte provenance.
# Oracle, generated filenames and source SHA remain test-side.
# Dot-sourced after existing B R4 tests, with no original media access.

Add-Type -TypeDefinition @'
using System;
using System.IO;
namespace ChappyBR4Physical {
  public sealed class TracedSyntheticReadStream : MemoryStream {
    private readonly long target;
    private readonly int maxChunk;
    private readonly int stopAfter;
    private readonly long directoryStart;
    private readonly long directoryEnd;
    public long AllSourceReturnedBytes { get; private set; }
    public long DirectorySourceReturnedBytes { get; private set; }
    public int DirectoryReadCalls { get; private set; }
    public TracedSyntheticReadStream(byte[] b, long at, int chunk, int stop,
                                     long directoryOffset, int directoryLength)
      : base(b, false) {
      target=at; maxChunk=chunk; stopAfter=stop;
      directoryStart=directoryOffset;
      directoryEnd=directoryOffset+directoryLength;
    }
    public override int Read(byte[] buffer, int offset, int count) {
      long at=Position;
      if (at >= target && at < target+512L) {
        if (stopAfter >= 0 && at >= target + stopAfter) {
          DirectoryReadCalls++;
          return 0;
        }
        count=Math.Min(count,maxChunk);
        if (stopAfter >= 0)
          count=Math.Min(count,(int)(target+stopAfter-at));
      }
      int n=base.Read(buffer,offset,count);
      if (at >= directoryStart && at < directoryEnd)
        DirectoryReadCalls++;
      if (n > 0) {
        AllSourceReturnedBytes+=n;
        if (at >= directoryStart && at < directoryEnd)
          DirectorySourceReturnedBytes+=n;
      }
      return n;
    }
  }
}
'@ -ErrorAction Stop

$r4VRoot=[long]$r4NLayout.rootOffsetBytes
[byte[]]$r4VImage=[byte[]]$r4QFake
# Fixed scanner caps and paired synthetic truth. Only the test knows that the
# child named by the invented root record is not part of the observed region.
$r4VCases=@(
  [pscustomobject]@{id='root_short_17';target=$r4VRoot;chunk=17;stop=17;scan=1024L;spans=8;physical=17L;complete=0L;positive=1;zeros=1;isPartial=$true},
  [pscustomobject]@{id='root_chunked_success';target=$r4VRoot;chunk=17;stop=-1;scan=512L;spans=8;physical=512L;complete=512L;positive=31;zeros=0;isPartial=$false},
  [pscustomobject]@{id='next_cluster_short_17';target=($r4VRoot+512);chunk=17;stop=17;scan=1024L;spans=8;physical=529L;complete=512L;positive=2;zeros=1;isPartial=$true},
  [pscustomobject]@{id='span_cap_with_complete_reads';target=$r4VRoot;chunk=512;stop=-1;scan=1024L;spans=1;physical=1024L;complete=1024L;positive=2;zeros=0;isPartial=$false},
  [pscustomobject]@{id='under_cluster_scan_budget';target=$r4VRoot;chunk=512;stop=-1;scan=256L;spans=8;physical=0L;complete=0L;positive=0;zeros=0;isPartial=$false}
)
$r4VTPBase=0;$r4VFPBase=0;$r4VFNBase=0;$r4VTNBase=0
$r4VTPNew=0;$r4VFPNew=0;$r4VFNNew=0;$r4VTNNew=0
$r4VPhysicalTotal=0L;$r4VCompletedTotal=0L;$r4VPartialTotal=0L
$r4VBaseMs=0L;$r4VNewMs=0L;$r4VFalsePaths=0
$r4VOriginalHash=Get-A3DSha256 $r4VImage
$r4VForgedSample=$null
$r4VForgedSourceBytes=0L
foreach($r4VCase in $r4VCases) {
  $r4VOldStream=[ChappyBR4Physical.TracedSyntheticReadStream]::new(
    $r4VImage,[long]$r4VCase.target,[int]$r4VCase.chunk,[int]$r4VCase.stop,
    $r4VRoot,1024)
  $r4VNewStream=[ChappyBR4Physical.TracedSyntheticReadStream]::new(
    $r4VImage,[long]$r4VCase.target,[int]$r4VCase.chunk,[int]$r4VCase.stop,
    $r4VRoot,1024)
  try {
    $r4VCommon=@{MaxScanBytes=$r4VCase.scan;MaxCandidates=32;MaxDirectories=16;
                 RecordDirectoryReadSpans=$true;ClassifyIncompleteDirectoryReadOrigin=$true;
                 MaxDirectoryReadSpans=$r4VCase.spans}
    $r4VTimer=[Diagnostics.Stopwatch]::StartNew()
    $r4VCommon.Stream=$r4VOldStream
    $r4VBase=Get-ChappyDirectoryCandidates @r4VCommon
    $r4VTimer.Stop();$r4VBaseMs+=$r4VTimer.ElapsedMilliseconds
    $r4VTimer=[Diagnostics.Stopwatch]::StartNew()
    $r4VCommon.Stream=$r4VNewStream
    $r4VNew=Get-ChappyDirectoryCandidates @r4VCommon -RecordDirectoryPhysicalReadBytes
    $r4VTimer.Stop();$r4VNewMs+=$r4VTimer.ElapsedMilliseconds

    Assert-B (-not $r4VOldStream.CanWrite -and -not $r4VNewStream.CanWrite -and
      $r4VBase.status -eq $r4VNew.status -and
      $r4VBase.scanIncomplete -eq $r4VNew.scanIncomplete -and
      $r4VBase.items.Count -eq $r4VNew.items.Count -and
      $r4VBase.metrics.bytesRead -eq $r4VNew.metrics.bytesRead -and
      $null -eq $r4VBase.directoryPhysicalReadEvidence) ('R4 V default-off A/B unchanged parser and completed-cluster count: '+$r4VCase.id)
    $r4VBaseJson=ConvertTo-Json -InputObject @($r4VBase.items) -Depth 8 -Compress
    $r4VNewJson=ConvertTo-Json -InputObject @($r4VNew.items) -Depth 8 -Compress
    Assert-B ($r4VBaseJson -ceq $r4VNewJson -and
      (ConvertTo-Json -InputObject $r4VBase.directoryReadEvidence -Depth 6 -Compress) -ceq
      (ConvertTo-Json -InputObject $r4VNew.directoryReadEvidence -Depth 6 -Compress)) ('R4 V same candidate grading and successful-read spans: '+$r4VCase.id)

    $r4VM=$r4VNew.directoryPhysicalReadEvidence
    Assert-B ($r4VM.source -eq 'directory_stream_read_returns_v1' -and
      $r4VM.streamReturnedBytes -eq $r4VCase.physical -and
      $r4VM.completedClusterBytes -eq $r4VCase.complete -and
      $r4VM.incompleteClusterReturnedBytes -eq ($r4VCase.physical-$r4VCase.complete) -and
      $r4VM.positiveReadCalls -eq $r4VCase.positive -and
      $r4VM.zeroReadCalls -eq $r4VCase.zeros -and
      $r4VM.readCalls -eq ($r4VCase.positive+$r4VCase.zeros)) ('R4 V exact positive Stream.Read returns, not requested bytes: '+$r4VCase.id)
    Assert-B ($r4VOldStream.DirectorySourceReturnedBytes -eq $r4VCase.physical -and
      $r4VNewStream.DirectorySourceReturnedBytes -eq $r4VCase.physical -and
      $r4VNewStream.AllSourceReturnedBytes -ge $r4VM.streamReturnedBytes -and
      $r4VBase.metrics.bytesRead -eq $r4VCase.complete) ('R4 V independent test-side outer meter agrees with B directory-only return bytes: '+$r4VCase.id)
    if($r4VCase.isPartial) {
      $r4VFNBase++
      if($r4VM.incompleteClusterReturnedBytes -gt 0L){$r4VTPNew++}else{$r4VFNNew++}
    } else {
      $r4VTNBase++
      if($r4VM.incompleteClusterReturnedBytes -gt 0L){$r4VFPNew++}else{$r4VTNNew++}
    }
    $r4VPhysicalTotal += [long]$r4VM.streamReturnedBytes
    $r4VCompletedTotal += [long]$r4VM.completedClusterBytes
    $r4VPartialTotal += [long]$r4VM.incompleteClusterReturnedBytes
    if($r4VCase.id -eq 'root_short_17') {
      Assert-B ($r4VNew.status -eq 'error' -and $r4VNew.directoryReadEvidence.status -eq 'scan_error' -and
        $r4VNew.directoryReadEvidence.readEvents -eq 0 -and $r4VNew.items.Count -eq 0) 'R4 V root 17/512 failure does not count a completed cluster or path'
    }
    if($r4VCase.id -eq 'root_chunked_success') {
      Assert-B ($r4VM.readCalls -eq 31 -and $r4VM.streamReturnedBytes -eq 512 -and
        $r4VM.incompleteClusterReturnedBytes -eq 0 -and
        $r4VNew.directoryReadEvidence.readEvents -eq 1) 'R4 V 31 short Stream.Read calls form one complete 512-byte cluster'
    }
    if($r4VCase.id -eq 'span_cap_with_complete_reads') {
      Assert-B ($r4VNew.directoryReadEvidence.status -eq 'span_limit' -and
        $r4VNew.directoryReadEvidence.recordedSpans -eq 1 -and
        $r4VM.streamReturnedBytes -eq 1024 -and $r4VM.completedClusterBytes -eq 1024) 'R4 V one-span ledger cap does not change actual completed 1024 bytes'
    }
    if($r4VCase.id -eq 'under_cluster_scan_budget') {
      Assert-B ($r4VNew.directoryReadEvidence.status -eq 'scan_incomplete' -and
        $r4VM.streamReturnedBytes -eq 0 -and $r4VM.readCalls -eq 0) 'R4 V under-512 scan budget never attempts a directory read'
    }
    if($r4VCase.id -eq 'next_cluster_short_17' -or
       $r4VCase.id -eq 'root_chunked_success' -or
       $r4VCase.id -eq 'span_cap_with_complete_reads') {
      $r4VGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4VNew -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
      if($r4VGraph.metrics.probableEdgeAssertions -gt 0){$r4VFalsePaths++}
      Assert-B (@($r4VNew.items|Where-Object{$_.isDirectory -and $_.startCluster -eq 27}).Count -eq 1 -and
        $r4VGraph.scanIncomplete -and $r4VGraph.metrics.probableEdgeAssertions -eq 0) ('R4 V unobserved fake child preserved without high-confidence original path: '+$r4VCase.id)
    }
    if($r4VCase.id -eq 'next_cluster_short_17') {
      Assert-B ($r4VM.streamReturnedBytes -eq 529 -and $r4VM.completedClusterBytes -eq 512 -and
        $r4VNew.directoryReadEvidence.readEvents -eq 1 -and
        $r4VNew.directoryReadEvidence.spans[0].offsetBytes -eq $r4VRoot) 'R4 V root complete plus following 17-byte failed cluster tracked separately'
      $r4VForgedSample=$r4VNew
      $r4VForgedSourceBytes=[long]$r4VNewStream.DirectorySourceReturnedBytes
    }
    $r4VReportJson=ConvertTo-Json -InputObject $r4VM -Depth 5
    Assert-B ($r4VReportJson -notmatch 'BAITDIR|EMPTY|originalPath|originalIdentity|filename') ('R4 V no filenames, raw data or claimed original identity in metrics: '+$r4VCase.id)
  } finally {$r4VOldStream.Dispose();$r4VNewStream.Dispose()}
  Assert-B ((Get-A3DSha256 $r4VImage) -ceq $r4VOriginalHash) ('R4 V artificial SHA invariant after paired reads: '+$r4VCase.id)
}

# Self-reported B numbers can be forged by a caller. A outer meter must be
# authoritative; B must not synthesize an A-owned event ID or receipt.
$r4VForged=$r4VForgedSample | ConvertTo-Json -Depth 10 -Compress | ConvertFrom-Json
$r4VForged.directoryPhysicalReadEvidence.streamReturnedBytes=1024L
$r4VForged.directoryPhysicalReadEvidence.completedClusterBytes=1024L
$r4VForged.directoryPhysicalReadEvidence.incompleteClusterReturnedBytes=0L
Assert-B ($r4VForged.directoryPhysicalReadEvidence.streamReturnedBytes -ne $r4VForgedSourceBytes -and
  $r4VForgedSourceBytes -eq 529L -and
  $r4VForged.directoryPhysicalReadEvidence.PSObject.Properties.Name -notcontains 'sourceToken') 'R4 V forged B counter disagrees with independent outer meter and carries no A receipt'
Assert-B ($r4VFalsePaths -eq 0 -and $r4VTPBase -eq 0 -and $r4VFPBase -eq 0 -and
  $r4VFNBase -eq 2 -and $r4VTNBase -eq 3 -and
  $r4VTPNew -eq 2 -and $r4VFPNew -eq 0 -and $r4VFNNew -eq 0 -and $r4VTNNew -eq 3) 'R4 V finite partial-return detection baseline TP0 FP0 FN2 TN3 versus new TP2 FP0 FN0 TN3, no false original parent'
Assert-B ($r4VPhysicalTotal -eq 2082L -and $r4VCompletedTotal -eq 2048L -and
  $r4VPartialTotal -eq 34L) 'R4 V 2082 actual B Stream.Read returned, 2048 complete cluster bytes, 34 incomplete bytes across 5 invented cases'
Write-Host ('SYNTHETIC B R4 V: partial-byte visibility baseline TP={0} FP={1} FN={2} TN={3}; new TP={4} FP={5} FN={6} TN={7}; B returned bytes={8}, completed={9}, unfinished={10}; geometry excluded; elapsed-ms old={11} new={12}; original identity unknown' -f
  $r4VTPBase,$r4VFPBase,$r4VFNBase,$r4VTNBase,$r4VTPNew,$r4VFPNew,$r4VFNNew,$r4VTNNew,
  $r4VPhysicalTotal,$r4VCompletedTotal,$r4VPartialTotal,$r4VBaseMs,$r4VNewMs)
