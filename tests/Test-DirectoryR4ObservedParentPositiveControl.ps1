#requires -Version 5.1
# Team B R4: independently metered synthetic positive parent-evidence control.
# Frozen R0/R1 card: Issue #71 comment 6827663929. Synthetic data only.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Security.Cryptography;
namespace ChappyBR4ObservedParentPositive {
  public sealed class ReadEvent {
    public long Offset;
    public int Requested;
    public int Returned;
    public string Sha256;
  }
  public sealed class MeteredStream : MemoryStream {
    readonly int maxChunk;
    readonly long stopAt;
    readonly int callLimit;
    public readonly List<ReadEvent> Events = new List<ReadEvent>();
    public int Calls { get; private set; }
    public long ReturnedBytes { get; private set; }
    public MeteredStream(byte[] bytes, int chunk, long stop, int limit) : base(bytes, false) {
      maxChunk=chunk; stopAt=stop; callLimit=limit;
    }
    static string Digest(byte[] b, int offset, int count) {
      using (SHA256 sha=SHA256.Create()) {
        byte[] h=sha.ComputeHash(b,offset,count);
        return BitConverter.ToString(h).Replace("-","");
      }
    }
    public override int Read(byte[] b, int offset, int count) {
      if (++Calls > callLimit) throw new InvalidOperationException("synthetic read-call budget exceeded");
      long at=Position;
      if (stopAt >= 0 && at >= stopAt) {
        Events.Add(new ReadEvent { Offset=at, Requested=count, Returned=0, Sha256=Digest(new byte[0],0,0) });
        return 0;
      }
      int allowed=Math.Min(count,maxChunk);
      if (stopAt >= 0 && at < stopAt && stopAt-at < allowed) allowed=(int)(stopAt-at);
      int n=base.Read(b,offset,allowed);
      Events.Add(new ReadEvent { Offset=at, Requested=count, Returned=n, Sha256=Digest(b,offset,n) });
      ReturnedBytes += n;
      return n;
    }
  }
}
'@

function Assert-BR4([bool]$Pass,[string]$Label) {
    if (-not $Pass) { throw "FAIL: $Label" }
    Write-Host "PASS: $Label"
}
function Set-BR4U16([byte[]]$Bytes,[int]$Offset,[int]$Value) {
    [BitConverter]::GetBytes([uint16]$Value).CopyTo($Bytes,$Offset)
}
function Set-BR4U32([byte[]]$Bytes,[int]$Offset,[long]$Value) {
    [BitConverter]::GetBytes([uint32]$Value).CopyTo($Bytes,$Offset)
}
function New-BR4Entry([string]$Alias11,[int]$Attr,[int]$Start,[long]$Size) {
    if ($Alias11.Length -ne 11) { throw 'Synthetic alias length must be 11' }
    [byte[]]$e=New-Object byte[] 32
    [Text.Encoding]::ASCII.GetBytes($Alias11).CopyTo($e,0)
    $e[11]=[byte]$Attr
    Set-BR4U16 $e 20 0
    Set-BR4U16 $e 26 $Start
    Set-BR4U32 $e 28 $Size
    return ,$e
}
function Add-BR4Entries([byte[]]$Image,[int]$At,[object[]]$Entries) {
    $cursor=$At
    foreach($entry in $Entries) {
        [byte[]]$raw=$entry
        [Array]::Copy($raw,0,$Image,$cursor,32)
        $cursor+=32
    }
}
function Get-BR4Sha([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') }
    finally { $sha.Dispose() }
}
function Test-BR4RangeReturned([object[]]$Events,[long]$Start,[long]$Length) {
    $end=$Start+$Length
    $cursor=$Start
    foreach($e in ($Events | Where-Object {$_.Returned -gt 0} | Sort-Object Offset)) {
        $eventStart=[long]$e.Offset
        $eventEnd=$eventStart+[long]$e.Returned
        if($eventEnd -le $cursor) { continue }
        if($eventStart -gt $cursor) { break }
        $cursor=[Math]::Min($end,$eventEnd)
        if($cursor -ge $end) { return $true }
    }
    return $false
}
function Get-BR4CompletedDataBytes([object[]]$Events,[long]$DataOffset,[int]$ClusterBytes,[int]$ClusterCount) {
    $total=0L
    for($i=0;$i -lt $ClusterCount;$i++) {
        if(Test-BR4RangeReturned $Events ($DataOffset+$i*$ClusterBytes) $ClusterBytes) {
            $total+=$ClusterBytes
        }
    }
    return $total
}
function New-BR4ParentImage([int]$Seed,[string]$Case) {
    [byte[]]$image=New-Object byte[] 2560
    $root=New-Object System.Collections.ArrayList
    if($Case -ne 'orphan') {
        [void]$root.Add((New-BR4Entry 'CHILD   DIR' 0x10 3 0))
    }
    Add-BR4Entries $image 1024 @($root.ToArray())

    $child=New-Object System.Collections.ArrayList
    [void]$child.Add((New-BR4Entry '.          ' 0x10 3 0))
    $parentHint=if($Case -eq 'duplicate_parent') {4} elseif($Case -eq 'orphan') {0} else {2}
    [void]$child.Add((New-BR4Entry '..         ' 0x10 $parentHint 0))
    [void]$child.Add((New-BR4Entry 'INNER   TXT' 0x20 4 (100+($Seed%3))))
    Add-BR4Entries $image 1536 @($child.ToArray())

    if($Case -eq 'duplicate_parent') {
        $other=New-Object System.Collections.ArrayList
        [void]$other.Add((New-BR4Entry '.          ' 0x10 4 0))
        [void]$other.Add((New-BR4Entry '..         ' 0x10 0 0))
        [void]$other.Add((New-BR4Entry 'ALTCHD  DIR' 0x10 3 0))
        Add-BR4Entries $image 2048 @($other.ToArray())
    }
    return ,$image
}
function Test-BR4EventsMatchInput([object[]]$Events,[byte[]]$Image) {
    foreach($e in $Events) {
        if($e.Returned -le 0) { continue }
        [byte[]]$chunk=New-Object byte[] $e.Returned
        [Array]::Copy($Image,[int]$e.Offset,$chunk,0,$chunk.Length)
        if((Get-BR4Sha $chunk) -cne $e.Sha256) { return $false }
    }
    return $true
}

$repoRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'modules\directory\DirectoryScanner.ps1')
. (Join-Path $repoRoot 'modules\directory\DirectoryHierarchy.ps1')
$geometry=[pscustomobject]@{
    dataOffsetBytes=1024L; clusterSizeBytes=512L; maxCluster=4L
    rootCluster=2L; partitionEndBytes=2560L; clusterCount=3L
}
$seedSet=@(202611,202612,202613)
$cases=@('matched_parent','duplicate_parent','short_child','orphan')
$baseline=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0}
$guarded=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0}
$totalReturned=0L; $totalBCompleted=0L; $totalCalls=0L; $falsePathClaims=0
$completedPositive=0; $ambiguousObserved=0; $partialUnknown=0; $orphanTrueNegative=0
$strictFullyObservedUnknown=0; $strictLostStructuralProbable=0

foreach($seed in $seedSet) {
    foreach($case in $cases) {
        $fixture=New-BR4ParentImage -Seed $seed -Case $case
        $before=Get-BR4Sha $fixture
        $stopAt=if($case -eq 'short_child'){1536L+17L}else{-1L}
        $stream=[ChappyBR4ObservedParentPositive.MeteredStream]::new($fixture,97,$stopAt,128)
        try {
            Assert-BR4 (-not $stream.CanWrite -and $stream.CanRead -and $stream.CanSeek) "$seed/$case source is read-only, seekable and readable"
            $scan=Get-ChappyDirectoryCandidates -Stream $stream -Geometry $geometry -MaxScanBytes 1536 -MaxCandidates 32 -MaxDirectories 16
            $graph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $scan -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorDepth 8 -MaxAncestorSteps 64
            # B4-03 conservative graph reuses this exact DirectoryResult:
            # no extra Stream.Read and no caller-provided receipt/token.
            $strictGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $scan -NeverPromoteUnattestedParentEdges -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorDepth 8 -MaxAncestorSteps 64
            Assert-BR4 ($strictGraph.metrics.probableEdgeAssertions -eq 0 -and
                $strictGraph.metrics.edgeAssertions -eq $graph.metrics.edgeAssertions -and
                $strictGraph.nodes.Count -eq $graph.nodes.Count -and
                $strictGraph.parentHints.Count -eq $graph.parentHints.Count -and
                @($strictGraph.edges|Where-Object{$_.confidence -eq 'verified'}).Count -eq 0) "$seed/$case B4-03 strict preserves structural candidates without probable promotion"
            $events=@($stream.Events)
            Assert-BR4 ($stream.Calls -le 128 -and $stream.ReturnedBytes -le 1536) "$seed/$case respects physical returned-byte and call caps"
            Assert-BR4 (Test-BR4EventsMatchInput $events $fixture) "$seed/$case event digests match generated bytes"
            $completed=Get-BR4CompletedDataBytes $events 1024 512 3
            Assert-BR4 ($scan.metrics.bytesRead -eq $completed) "$seed/$case B completed-directory bytes match independently observed complete clusters"
            Assert-BR4 ((Get-BR4Sha $fixture) -ceq $before) "$seed/$case input SHA-256 unchanged"
            Assert-BR4 (($graph.PSObject.Properties.Name -notcontains 'paths') -and
                (@($graph.edges | Where-Object {$_.confidence -eq 'verified' -or $_.PSObject.Properties.Name -contains 'originalPath' -or $_.PSObject.Properties.Name -contains 'path'}).Count -eq 0)) "$seed/$case makes no original-path claim"

            $rootRecord=@($scan.items | Where-Object {$_.isDirectory -and $_.containerCluster -eq 2 -and $_.startCluster -eq 3} | Sort-Object offsetBytes | Select-Object -First 1)
            $naiveParent=$null
            if($rootRecord.Count -gt 0) { $naiveParent=[long]$rootRecord[0].containerCluster }
            $truthParent=if($case -eq 'duplicate_parent'){4L} elseif($case -eq 'orphan'){$null}else{2L}
            if($null -eq $truthParent) {
                if($null -eq $naiveParent) {$baseline.TN++} else {$baseline.FP++}
            } elseif($null -eq $naiveParent) {$baseline.FN++}
            elseif($naiveParent -eq $truthParent) {$baseline.TP++} else {$baseline.FP++}

            $parentRecordOffset=1024L
            $childDotDotOffset=1536L+32L
            $parentSpan=Test-BR4RangeReturned $events $parentRecordOffset 32
            $dotdotSpan=Test-BR4RangeReturned $events $childDotDotOffset 32
            $complete=($completed -eq 1536L -and -not $scan.scanIncomplete)
            $probableEdges=@($graph.edges | Where-Object {
                $_.childCluster -eq 3 -and $_.relationStatus -eq 'parent_hint_corroborated' -and $_.confidence -eq 'probable'
            })
            $ambiguousEdges=@($graph.edges | Where-Object {
                $_.childCluster -eq 3 -and $_.relationStatus -eq 'ambiguous_multiple_parents'
            })
            if($case -eq 'matched_parent') {
                $validEvidence=($parentSpan -and $dotdotSpan -and $complete -and $probableEdges.Count -eq 1 -and $probableEdges[0].parentCluster -eq 2)
                Assert-BR4 $validEvidence "$seed positive control has independently returned parent entry and matching child dotdot"
                if($validEvidence){$guarded.TP++;$completedPositive++} else {$guarded.FN++}
                Assert-BR4 ($strictGraph.metrics.unattestedProbableSuppressed -eq 1 -and
                    $strictGraph.edges[0].confidence -eq 'partial' -and
                    $strictGraph.edges[0].relationStatus -eq 'parent_hint_corroborated' -and
                    $strictGraph.edges[0].evidence -contains 'independent_source_attestation_required') "$seed fully returned structural positive deliberately abstains without external receipt"
                $strictFullyObservedUnknown++
                $strictLostStructuralProbable++
            } elseif($case -eq 'duplicate_parent') {
                $secondParentSpan=Test-BR4RangeReturned $events (2048L+64L) 32
                Assert-BR4 ($complete -and $parentSpan -and $secondParentSpan -and $dotdotSpan -and
                    $probableEdges.Count -eq 0 -and $ambiguousEdges.Count -eq 2) "$seed fully observed competing parents remain ambiguous"
                if($complete -and $ambiguousEdges.Count -ge 2) {$guarded.UNKNOWN++;$ambiguousObserved++}
                elseif($probableEdges.Count -gt 0){$guarded.FP++} else {$guarded.UNKNOWN++}
            } elseif($case -eq 'short_child') {
                Assert-BR4 ($parentSpan -and -not $dotdotSpan -and $scan.scanIncomplete -and
                    $scan.metrics.bytesRead -eq 512 -and $stream.ReturnedBytes -eq 529 -and
                    $probableEdges.Count -eq 0) "$seed child short read preserves UNKNOWN and separates returned from complete bytes"
                $guarded.UNKNOWN++;$partialUnknown++
            } else {
                $childObserved=Test-BR4RangeReturned $events $childDotDotOffset 32
                Assert-BR4 ($complete -and $childObserved -and $probableEdges.Count -eq 0 -and
                    @($graph.nodes | Where-Object {$_.cluster -eq 3 -and $_.linkStatus -eq 'orphan_candidate'}).Count -eq 1) "$seed fully observed orphan remains unlinked"
                $guarded.TN++;$orphanTrueNegative++
            }

            if(@($graph.edges | Where-Object {$_.confidence -eq 'verified' -or $_.PSObject.Properties.Name -contains 'originalPath' -or $_.PSObject.Properties.Name -contains 'path'}).Count -gt 0) {$falsePathClaims++}
            $totalReturned += [long]$stream.ReturnedBytes
            $totalBCompleted += [long]$scan.metrics.bytesRead
            $totalCalls += [long]$stream.Calls
        } finally {$stream.Dispose()}
    }
}
Assert-BR4 ($baseline.TP -eq 6 -and $baseline.FP -eq 3 -and $baseline.FN -eq 0 -and $baseline.TN -eq 3 -and $baseline.UNKNOWN -eq 0) 'naive first-parent baseline scores TP6 FP3 FN0 TN3 UNKNOWN0'
Assert-BR4 ($guarded.TP -eq 3 -and $guarded.FP -eq 0 -and $guarded.FN -eq 0 -and $guarded.TN -eq 3 -and $guarded.UNKNOWN -eq 6) 'observed B evidence scores TP3 FP0 FN0 TN3 UNKNOWN6'
Assert-BR4 ($completedPositive -eq 3 -and $ambiguousObserved -eq 3 -and $partialUnknown -eq 3 -and $orphanTrueNegative -eq 3) 'three-seed positive, ambiguity, short-read and orphan strata all measured'
Assert-BR4 ($totalReturned -eq 15411 -and $totalBCompleted -eq 15360 -and $totalReturned-$totalBCompleted -eq 51) 'aggregate returned 15411B, completed clusters 15360B, incomplete returns 51B'
Assert-BR4 ($totalCalls -le 256 -and $falsePathClaims -eq 0 -and
    $strictFullyObservedUnknown -eq 3 -and $strictLostStructuralProbable -eq 3) 'aggregate read events bounded; strict abstention also loses 3 structural positives'
Write-Host "R4 B/A: naive TP=$($baseline.TP) FP=$($baseline.FP) FN=$($baseline.FN) TN=$($baseline.TN) UNKNOWN=$($baseline.UNKNOWN); evidence TP=$($guarded.TP) FP=$($guarded.FP) FN=$($guarded.FN) TN=$($guarded.TN) UNKNOWN=$($guarded.UNKNOWN); returned=$totalReturned B completed=$totalBCompleted calls=$totalCalls."
Write-Host "B4-03 STRICT control: independently physically returned synthetic structural positives=3; strict mode deliberately leaves UNKNOWN=$strictFullyObservedUnknown, suppressed probable=$strictLostStructuralProbable; bytes/calls unchanged; NO original-parent attestation"

