#requires -Version 5.1
# Team B R4: artificial incomplete-read provenance versus legacy capture.
# This test owns oracle truth; B scanner receives only readonly bytes.
Add-Type -TypeDefinition @'
using System;
using System.IO;
namespace ChappyBSynthR4 {
 public sealed class ShortRootStream : MemoryStream {
  private readonly long target;
  public int RootCalls { get; private set; }
  public long ActualRootBytes { get; private set; }
  public ShortRootStream(byte[] bytes, long at) : base(bytes, false) { target = at; }
  public override int Read(byte[] b, int offset, int count) {
   if (Position >= target && Position < target + 512) {
    RootCalls++;
    if (Position == target) {
     int n = base.Read(b, offset, Math.Min(17, count));
     ActualRootBytes += n;
     return n;
    }
    return 0;
   }
   return base.Read(b, offset, count);
  }
 }
}
'@ -ErrorAction Stop

$r4QRoot=[long]$r4NLayout.rootOffsetBytes
$r4QClean=New-ChappyA3DDamagedFixture -Case M00 -Seed 202611
[byte[]]$r4QFake=[byte[]]$r4QClean.image.Clone()
if($r4QFake[$r4QRoot+96] -ne 0){throw 'R4 Q artificial parent slot occupied'}
[byte[]]$r4QEntry=New-ShortB 'BAITDIR    ' 0x10 27 0
[Array]::Copy($r4QEntry,0,$r4QFake,([int]$r4QRoot+96),32)

$r4QCases=@(
 [pscustomobject]@{id='full';bytes=[byte[]]$r4Image;geo=$r4Geo;budget=30720L;cap=32;expected='recorded';events=30},
 [pscustomobject]@{id='partial_false_parent';bytes=$r4QFake;geo=$null;budget=1024L;cap=8;expected='scan_incomplete';events=2},
 [pscustomobject]@{id='span_limit_false_parent';bytes=$r4QFake;geo=$null;budget=1024L;cap=1;expected='span_limit';events=2}
)
$r4QCounts=@{oldTP=0;oldFP=0;oldFN=0;oldTN=0;newTP=0;newFP=0;newFN=0;newTN=0}
$r4QCompleted=0L
$r4QOldMs=0L
$r4QNewMs=0L
foreach($r4QCase in $r4QCases){
 [byte[]]$r4QBytes=$r4QCase.bytes
 $r4QHash=Get-A3DSha256 $r4QBytes
 $r4QOldStream=[IO.MemoryStream]::new($r4QBytes,$false)
 $r4QNewStream=[IO.MemoryStream]::new($r4QBytes,$false)
 try {
  $r4QParams=@{MaxScanBytes=$r4QCase.budget;MaxCandidates=32;MaxDirectories=16;RecordDirectoryReadSpans=$true;MaxDirectoryReadSpans=$r4QCase.cap}
  if($null -ne $r4QCase.geo){$r4QParams.Geometry=$r4QCase.geo}
  $r4QClock=[Diagnostics.Stopwatch]::StartNew()
  $r4QParams.Stream=$r4QOldStream
  $r4QOld=Get-ChappyDirectoryCandidates @r4QParams
  $r4QClock.Stop();$r4QOldMs+=$r4QClock.ElapsedMilliseconds
  $r4QClock=[Diagnostics.Stopwatch]::StartNew()
  $r4QParams.Stream=$r4QNewStream
  $r4QNew=Get-ChappyDirectoryCandidates @r4QParams -ClassifyIncompleteDirectoryReadOrigin
  $r4QClock.Stop();$r4QNewMs+=$r4QClock.ElapsedMilliseconds
  $r4QCompleted += [long]$r4QOld.metrics.bytesRead + [long]$r4QNew.metrics.bytesRead
  Assert-B (-not $r4QOldStream.CanWrite -and -not $r4QNewStream.CanWrite -and $r4QOld.metrics.bytesRead -eq $r4QNew.metrics.bytesRead -and $r4QOld.scanIncomplete -eq $r4QNew.scanIncomplete -and $r4QOld.items.Count -eq $r4QNew.items.Count) ('R4 Q bounded same artificial source: '+$r4QCase.id)
  Assert-B ((ConvertTo-Json -InputObject @($r4QOld.items) -Depth 8 -Compress) -ceq (ConvertTo-Json -InputObject @($r4QNew.items) -Depth 8 -Compress)) ('R4 Q candidates and confidence unchanged: '+$r4QCase.id)
  Assert-B ($r4QNew.directoryReadEvidence.status -eq $r4QCase.expected -and $r4QNew.directoryReadEvidence.readEvents -eq $r4QCase.events -and $r4QNew.directoryReadEvidence.recordedSpans -le $r4QCase.cap -and $r4QNew.directoryReadEvidence.recordedSpans -eq $r4QOld.directoryReadEvidence.recordedSpans) ('R4 Q actual event-origin classification: '+$r4QCase.id)
  $r4QTrueIncomplete=($r4QCase.id -ne 'full')
  foreach($r4QVariant in @(@{key='old';record=$r4QOld},@{key='new';record=$r4QNew})){
   $r4QPred=($r4QVariant.record.directoryReadEvidence.status -ne 'recorded')
   $r4QClass=if($r4QTrueIncomplete){if($r4QPred){'TP'}else{'FN'}}else{if($r4QPred){'FP'}else{'TN'}}
   $r4QCounts[$r4QVariant.key+$r4QClass]++
  }
  if($r4QTrueIncomplete){
   $r4QGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4QNew -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
   Assert-B ($r4QGraph.scanIncomplete -and $r4QGraph.metrics.probableEdgeAssertions -eq 0 -and $r4QGraph.metrics.unresolvedTargetReferences -eq 1 -and @($r4QNew.items|Where-Object{$_.isDirectory -and $_.startCluster -eq 27}).Count -eq 1) ('R4 Q false-parent candidate kept, missing child not a proven path: '+$r4QCase.id)
   Assert-B ($r4QNew.directoryReadEvidence.spans[0].offsetBytes -eq $r4QRoot -and $r4QNew.directoryReadEvidence.spans[0].lengthBytes -eq 512) ('R4 Q only successful reads yield source byte spans: '+$r4QCase.id)
  } else {
   Assert-B (-not $r4QNew.scanIncomplete -and $r4QNew.directoryReadEvidence.recordedSpans -eq 30) 'R4 Q full artificial 30-cluster control remains complete'
  }
 } finally {$r4QOldStream.Dispose();$r4QNewStream.Dispose()}
 Assert-B ((Get-A3DSha256 $r4QBytes) -ceq $r4QHash) ('R4 Q input SHA unchanged: '+$r4QCase.id)
}

# Synthetic short-read stream delivers 17 of the required 512 root bytes,
# then EOF. Neither scan is allowed to record a successful root event.
[byte[]]$r4QShortBytes=[byte[]]$r4QClean.image
$r4QShortHash=Get-A3DSha256 $r4QShortBytes
$r4QShortOld=[ChappyBSynthR4.ShortRootStream]::new($r4QShortBytes,$r4QRoot)
$r4QShortNew=[ChappyBSynthR4.ShortRootStream]::new($r4QShortBytes,$r4QRoot)
try {
 $r4QShortParams=@{MaxScanBytes=1024;MaxCandidates=32;MaxDirectories=16;RecordDirectoryReadSpans=$true;MaxDirectoryReadSpans=8}
 $r4QShortParams.Stream=$r4QShortOld
 $r4QShortBaseline=Get-ChappyDirectoryCandidates @r4QShortParams
 $r4QShortParams.Stream=$r4QShortNew
 $r4QShortCandidate=Get-ChappyDirectoryCandidates @r4QShortParams -ClassifyIncompleteDirectoryReadOrigin
 if($r4QShortBaseline.directoryReadEvidence.status -ne 'recorded'){$r4QCounts.oldTP++}else{$r4QCounts.oldFN++}
 if($r4QShortCandidate.directoryReadEvidence.status -ne 'recorded'){$r4QCounts.newTP++}else{$r4QCounts.newFN++}
 Assert-B (-not $r4QShortOld.CanWrite -and -not $r4QShortNew.CanWrite -and $r4QShortOld.ActualRootBytes -eq 17 -and $r4QShortNew.ActualRootBytes -eq 17 -and $r4QShortOld.RootCalls -eq 2 -and $r4QShortNew.RootCalls -eq 2) 'R4 Q controlled root partial-read actually returned 17 bytes then EOF'
 Assert-B ($r4QShortBaseline.status -eq 'error' -and $r4QShortCandidate.status -eq 'error' -and $r4QShortCandidate.metrics.bytesRead -eq 0 -and $r4QShortCandidate.items.Count -eq 0 -and $r4QShortCandidate.directoryReadEvidence.readEvents -eq 0 -and $r4QShortCandidate.directoryReadEvidence.spans.Count -eq 0) 'R4 Q partial physical read cannot count as completed directory cluster'
 Assert-B ($r4QShortBaseline.directoryReadEvidence.status -eq 'no_successful_reads' -and $r4QShortCandidate.directoryReadEvidence.status -eq 'scan_error' -and @($r4QShortCandidate.errors|Where-Object{$_ -match 'truncated during read'}).Count -eq 1) 'R4 Q scanner error distinguished from merely zero recorded events'
} finally {$r4QShortOld.Dispose();$r4QShortNew.Dispose()}
Assert-B ((Get-A3DSha256 $r4QShortBytes) -ceq $r4QShortHash) 'R4 Q short-read source artificial SHA unchanged'

# Deliberately forge externally supplied metadata. A valid-looking claim
# does not add the missing child directory to the observation graph.
$r4QFakeHash=Get-A3DSha256 $r4QFake
$r4QFakeStream=[IO.MemoryStream]::new($r4QFake,$false)
try {
 $r4QObserved=Get-ChappyDirectoryCandidates -Stream $r4QFakeStream -MaxScanBytes 1024 -MaxCandidates 32 -MaxDirectories 16 -RecordDirectoryReadSpans -ClassifyIncompleteDirectoryReadOrigin
} finally {$r4QFakeStream.Dispose()}
$r4QForged=$r4QObserved | ConvertTo-Json -Depth 10 -Compress | ConvertFrom-Json
$r4QForged.scanIncomplete=$false
$r4QForged.metrics.bytesRead=([long]$r4QForged.geometry.clusterCount*[long]$r4QForged.geometry.clusterSizeBytes)
$r4QForged.directoryReadEvidence.status='recorded'
$r4QForged | Add-Member NoteProperty coverageProvenance ([pscustomobject]@{
 source='scanner_read_events_v1';status='recorded'
 uniqueClusters=[long]$r4QForged.geometry.clusterCount
 readEvents=[long]$r4QForged.geometry.clusterCount
 duplicateReadEvents=0L
 intervals=@([pscustomobject]@{firstCluster=2L;lastCluster=[long]$r4QForged.geometry.maxCluster})
}) -Force
$r4QForgedGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4QForged -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
Assert-B ($r4QForgedGraph.metrics.unresolvedTargetReferences -eq 1 -and $r4QForgedGraph.edges.Count -eq 0 -and $r4QForgedGraph.nodes.Count -ge 1) 'R4 Q caller-forged complete counters still cannot invent unobserved child'
Assert-B ((Get-A3DSha256 $r4QFake) -ceq $r4QFakeHash) 'R4 Q forged-metadata source unchanged'
Assert-B ($r4QCounts.oldTP -eq 2 -and $r4QCounts.oldFP -eq 0 -and $r4QCounts.oldFN -eq 1 -and $r4QCounts.oldTN -eq 1 -and $r4QCounts.newTP -eq 3 -and $r4QCounts.newFP -eq 0 -and $r4QCounts.newFN -eq 0 -and $r4QCounts.newTN -eq 1) 'R4 Q origin-completeness detection baseline TP2 FN1 versus opt-in TP3 FN0, both FP0 TN1'
Assert-B ($r4QCompleted -eq 65536) 'R4 Q 65536 completed directory bytes across equivalent 3-case baseline and opt-in, short-read partial bytes excluded'
Write-Host ('SYNTHETIC B R4 Q: 4 case completeness oracle; baseline TP={0} FP={1} FN={2} TN={3}; opt-in TP={4} FP={5} FN={6} TN={7}; completed directory bytes={8}; artificial-only, no original identity claim' -f $r4QCounts.oldTP,$r4QCounts.oldFP,$r4QCounts.oldFN,$r4QCounts.oldTN,$r4QCounts.newTP,$r4QCounts.newFP,$r4QCounts.newFN,$r4QCounts.newTN,$r4QCompleted)
