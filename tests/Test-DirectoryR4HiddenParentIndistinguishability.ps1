#requires -Version 5.1
# Team B R4: synthetic hidden-parent/LFN observational indistinguishability.
# R0/R1 pre-frozen in Issue #71 comment 6826726439. No real image.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Security.Cryptography;
namespace ChappyBR4Hidden {
  public sealed class TranscriptStream : MemoryStream {
    readonly long partialAt; readonly int partialLimit;
    public readonly List<string> Events = new List<string>();
    public long ActualBytes {get;private set;}
    public int Calls {get;private set;}
    public TranscriptStream(byte[] b,long at,int limit) : base(b,false) {partialAt=at;partialLimit=limit;}
    public override int Read(byte[] b,int offset,int count) {
      if(Calls++ >= 128) throw new InvalidOperationException("synthetic read call cap");
      long at=Position;
      if(partialLimit>=0 && at>=partialAt && at<partialAt+512L) {
        if(at>=partialAt+partialLimit) {Events.Add("zero:"+at);return 0;}
        count=Math.Min(count,(int)(partialAt+partialLimit-at));
      }
      int n=base.Read(b,offset,count);
      if(ActualBytes+n>120000L) throw new InvalidOperationException("synthetic returned-byte cap");
      ActualBytes+=n;
      if(n>0) {
        using(SHA256 h=SHA256.Create()) {
          Events.Add("positive:"+at+":"+n+":"+BitConverter.ToString(h.ComputeHash(b,offset,n)).Replace("-",""));
        }
      } else {Events.Add("zero:"+at);}
      return n;
    }
  }
}
'@ -ErrorAction Stop
$r4HSeeds=@(202611,202612,202613)
$r4HPairs=0;$r4HCount=0;$r4HBytes=0L;$r4HComplete=0L;$r4HDirReturned=0L
$r4HCalls=0L;$r4HRetained=0L;$r4HForged=0L;$r4HProbable=0L;$r4HLfnValidated=0L
$r4HParent=@{naive=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0};abstain=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0}}
$r4HLfn=@{naive=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0};abstain=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0}}
function Add-R4HTruth([hashtable]$Table,[string]$Arm,[string]$Truth,[string]$Decision) {
    if($Decision -eq 'unknown'){$Table[$Arm].UNKNOWN++;return}
    if($Truth -eq 'supported') {
        if($Decision -eq 'positive'){$Table[$Arm].TP++}else{$Table[$Arm].FN++}
    } elseif($Truth -eq 'contradicted') {
        if($Decision -eq 'positive'){$Table[$Arm].FP++}else{$Table[$Arm].TN++}
    } else {throw 'unregistered synthetic scorer truth'}
}
foreach($r4HSeed in $r4HSeeds) {
    $r4HBase=New-ChappyA3DDamagedFixture -Case M00 -Seed $r4HSeed
    $r4HLayout=(New-ChappyA3DCleanFixture -Seed $r4HSeed).layout
    [byte[]]$r4HImage=[byte[]]$r4HBase.image.Clone()
    $r4HRoot=[int]$r4HLayout.rootOffsetBytes
    $r4HChild=$r4HRoot+2048
    $r4HRemote=$r4HRoot+3072
    if($r4HRoot -ne 57856 -or $r4HRemote+512 -gt $r4HImage.Length -or
       $r4HImage[$r4HRoot+96] -ne 0 -or
       $r4HImage[$r4HRoot+128] -ne 0 -or $r4HImage[$r4HRoot+160] -ne 0) {
        throw 'R4 H artificial fixed root layout changed'
    }
    [byte[]]$r4HLink=New-ShortB 'CHILD6  DIR' 0x10 6 0
    $r4HRootLfn=New-LfnB 'artificial-parent-six' $r4HLink
    if($r4HRootLfn.Count -ne 2){throw 'expected two LFN slots'}
    [Array]::Copy([byte[]]$r4HRootLfn[0],0,$r4HImage,($r4HRoot+96),32)
    [Array]::Copy([byte[]]$r4HRootLfn[1],0,$r4HImage,($r4HRoot+128),32)
    [Array]::Copy($r4HLink,0,$r4HImage,($r4HRoot+160),32)
    [byte[]]$r4HChildBytes=New-Object byte[] 512
    [Array]::Copy((New-ShortB '.          ' 0x10 6 0),0,$r4HChildBytes,0,32)
    [Array]::Copy((New-ShortB '..         ' 0x10 2 0),0,$r4HChildBytes,32,32)
    [byte[]]$r4HHiddenShort=New-ShortB 'HIDDEN  TXT' 0x20 28 7
    $r4HHiddenLfn=New-LfnB 'hidden-child' $r4HHiddenShort
    if($r4HHiddenLfn.Count -ne 1){throw 'expected one hidden LFN slot'}
    [Array]::Copy([byte[]]$r4HHiddenLfn[0],0,$r4HChildBytes,64,32)
    [Array]::Copy($r4HHiddenShort,0,$r4HChildBytes,96,32)
    [Array]::Copy((New-ShortB 'ORPHAN  TXT' 0x20 29 11),0,$r4HChildBytes,128,32)
    [Array]::Copy($r4HChildBytes,0,$r4HImage,$r4HChild,512)
    [Array]::Clear($r4HImage,$r4HRemote,512)
    foreach($r4HMode in @('partial_child','hidden_duplicate')) {
        [byte[]]$r4HGood=[byte[]]$r4HImage.Clone()
        [byte[]]$r4HBad=[byte[]]$r4HImage.Clone()
        $r4HPartial=($r4HMode -eq 'partial_child')
        if($r4HPartial) {
            [Array]::Copy((New-ShortB '..         ' 0x10 9 0),0,$r4HBad,($r4HChild+32),32)
            $r4HBad[$r4HChild+64+13]=[byte](($r4HBad[$r4HChild+64+13]+1) -band 255)
            $r4HBad[$r4HChild+128]=0xE5
        } else {
            # Hidden extra parent reference beyond MaxScanBytes.
            [Array]::Copy((New-ShortB 'OTHER   DIR' 0x10 6 0),0,$r4HBad,$r4HRemote,32)
        }
        Assert-B ((Get-A3DSha256 $r4HGood) -cne (Get-A3DSha256 $r4HBad)) ('R4 H synthetic full sources differ: '+$r4HSeed+' '+$r4HMode)
        $r4HResults=@{}
        foreach($r4HTruth in @('supported','contradicted')) {
            [byte[]]$r4HSource=if($r4HTruth -eq 'supported'){$r4HGood}else{$r4HBad}
            $r4HBefore=Get-A3DSha256 $r4HSource
            $r4HStop=if($r4HPartial){17}else{-1}
            $r4HStream=[ChappyBR4Hidden.TranscriptStream]::new($r4HSource,[long]$r4HChild,$r4HStop)
            try {
                $r4HArgs=@{
                    Stream=$r4HStream;MaxScanBytes=2560L;MaxCandidates=32;MaxDirectories=16
                    MaxDirectoryReadSpans=8;RecordDirectoryReadSpans=$true
                    RecordDirectoryPhysicalReadBytes=$true;ClassifyIncompleteDirectoryReadOrigin=$true
                    RecordClusterCoverage=$true
                }
                $r4HScan=Get-ChappyDirectoryCandidates @r4HArgs
                $r4HGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4HScan -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
                $r4HResults[$r4HTruth]=[pscustomobject]@{
                    reads=[string]::Join('|',$r4HStream.Events.ToArray())
                    scan=(ConvertTo-Json -InputObject $r4HScan -Depth 10 -Compress)
                    graph=(ConvertTo-Json -InputObject $r4HGraph -Depth 10 -Compress)
                    actual=[long]$r4HStream.ActualBytes
                    completed=[long]$r4HScan.metrics.bytesRead
                    directory=[long]$r4HScan.directoryPhysicalReadEvidence.streamReturnedBytes
                    calls=[long]$r4HStream.Calls
                }
                $r4HLinkItems=@($r4HScan.items|Where-Object{$_.isDirectory -and -not $_.deleted -and $_.containerCluster -eq 2 -and $_.startCluster -eq 6})
                Assert-B (-not $r4HStream.CanWrite -and $r4HScan.scanIncomplete -and $r4HGraph.scanIncomplete -and
                    $r4HGraph.metrics.probableEdgeAssertions -eq 0 -and
                    $r4HLinkItems.Count -eq 1 -and $r4HLinkItems[0].nameSource -eq 'lfn_validated' -and
                    $r4HLinkItems[0].confidence -ne 'verified' -and
                    $r4HStream.ActualBytes -ge $r4HScan.directoryPhysicalReadEvidence.streamReturnedBytes -and
                    @($r4HScan.items|Where-Object{$null -ne $_.name -or $null -ne $_.shortName}).Count -eq 0) ('R4 H only structural root LFN, no original path: '+$r4HSeed+' '+$r4HMode+' '+$r4HTruth)
                $r4HProbable += [long]$r4HGraph.metrics.probableEdgeAssertions
                $r4HLfnValidated++
                $r4HBytes += [long]$r4HStream.ActualBytes
                $r4HComplete += [long]$r4HScan.metrics.bytesRead
                $r4HDirReturned += [long]$r4HScan.directoryPhysicalReadEvidence.streamReturnedBytes
                $r4HCalls += [long]$r4HStream.Calls
                $r4HRetained += [long]$r4HScan.items.Count
                if($r4HPartial) {
                    Assert-B ($r4HScan.status -eq 'error' -and $r4HScan.directoryReadEvidence.status -eq 'scan_error' -and
                        $r4HScan.metrics.bytesRead -eq 2048 -and $r4HScan.directoryPhysicalReadEvidence.streamReturnedBytes -eq 2065 -and
                        $r4HScan.directoryPhysicalReadEvidence.incompleteClusterReturnedBytes -eq 17 -and
                        $r4HGraph.metrics.unresolvedTargetReferences -eq 1 -and $r4HGraph.edges.Count -eq 0) ('R4 H child returned 17 then EOF: '+$r4HSeed+' '+$r4HTruth)
                } else {
                    $r4HEdge=@($r4HGraph.edges|Where-Object{$_.parentCluster -eq 2 -and $_.childCluster -eq 6})
                    Assert-B ($r4HScan.metrics.bytesRead -eq 2560 -and $r4HEdge.Count -eq 1 -and
                        $r4HEdge[0].relationStatus -eq 'parent_hint_corroborated' -and
                        $r4HEdge[0].confidence -eq 'partial') ('R4 H observed child does not prove remote parent: '+$r4HSeed+' '+$r4HTruth)
                    $r4HForgedScan=$r4HScan|ConvertTo-Json -Depth 10 -Compress|ConvertFrom-Json
                    $r4HForgedScan.scanIncomplete=$false
                    $r4HForgedScan.metrics.bytesRead=[long]$r4HForgedScan.geometry.clusterCount*[long]$r4HForgedScan.geometry.clusterSizeBytes
                    $r4HForgedScan.coverageProvenance.status='recorded'
                    $r4HForgedScan.coverageProvenance.source='scanner_read_events_v1'
                    $r4HForgedScan.coverageProvenance.uniqueClusters=[long]$r4HForgedScan.geometry.clusterCount
                    $r4HForgedScan.coverageProvenance.readEvents=[long]$r4HForgedScan.geometry.clusterCount
                    $r4HForgedScan.coverageProvenance.duplicateReadEvents=0L
                    $r4HForgedScan.coverageProvenance.intervals=@([pscustomobject]@{firstCluster=2L;lastCluster=[long]$r4HForgedScan.geometry.maxCluster})
                    $r4HFakeGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4HForgedScan -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
                    $r4HForged += [long]$r4HFakeGraph.metrics.probableEdgeAssertions
                    Assert-B ($r4HFakeGraph.metrics.probableEdgeAssertions -ge 1 -and
                        $r4HForgedScan.metrics.bytesRead -gt $r4HStream.ActualBytes) ('R4 H self-forged full scan is not external source proof: '+$r4HSeed+' '+$r4HTruth)
                }
            } finally {$r4HStream.Dispose()}
            Assert-B ((Get-A3DSha256 $r4HSource) -ceq $r4HBefore) ('R4 H artificial SHA preserved: '+$r4HSeed+' '+$r4HMode+' '+$r4HTruth)
            Add-R4HTruth $r4HParent 'naive' $r4HTruth 'positive'
            Add-R4HTruth $r4HParent 'abstain' $r4HTruth 'unknown'
            if($r4HPartial) {
                # This is a deliberately unsafe naive claim about an UNSEEN
                # child LFN. The visible root LFN is still valid in both.
                Add-R4HTruth $r4HLfn 'naive' $r4HTruth 'positive'
                Add-R4HTruth $r4HLfn 'abstain' $r4HTruth 'unknown'
            }
            $r4HCount++
        }
        $r4HA=$r4HResults.supported;$r4HB=$r4HResults.contradicted
        Assert-B ($r4HA.reads -ceq $r4HB.reads -and $r4HA.scan -ceq $r4HB.scan -and
            $r4HA.graph -ceq $r4HB.graph -and $r4HA.actual -eq $r4HB.actual -and
            $r4HA.completed -eq $r4HB.completed -and $r4HA.directory -eq $r4HB.directory -and
            $r4HA.calls -eq $r4HB.calls) ('R4 H identical positive/zero Stream.Read offset+length+SHA transcript and result: '+$r4HSeed+' '+$r4HMode)
        $r4HPairs++
    }
}
Assert-B ($r4HPairs -eq 6 -and $r4HCount -eq 12 -and $r4HLfnValidated -eq 12 -and
    $r4HProbable -eq 0 -and $r4HForged -eq 6 -and
    $r4HDirReturned -eq 27750 -and $r4HComplete -eq 27648 -and ($r4HDirReturned-$r4HComplete) -eq 102) 'R4 H six synthetic pairs, 102 partial return bytes, six forged probable edges'
Assert-B ($r4HParent.naive.TP -eq 6 -and $r4HParent.naive.FP -eq 6 -and
    $r4HParent.abstain.UNKNOWN -eq 12 -and
    $r4HLfn.naive.TP -eq 3 -and $r4HLfn.naive.FP -eq 3 -and
    $r4HLfn.abstain.UNKNOWN -eq 6) 'R4 H naive oracle-only false-parent/LFN claims versus calibrated unknown'
Write-Host ('SYNTHETIC B R4 H: seeds=3 pairs=6 sources=12; parent naive TP={0} FP={1}, abstain UNKNOWN={2}; unseen child LFN naive TP={3} FP={4}, abstain UNKNOWN={5}; source actual={6} directory returned={7} complete={8} partial={9}; Read calls={10}; retained candidates={11}; honest probable={12} forged apparent probable={13}; original identity UNKNOWN' -f
    $r4HParent.naive.TP,$r4HParent.naive.FP,$r4HParent.abstain.UNKNOWN,
    $r4HLfn.naive.TP,$r4HLfn.naive.FP,$r4HLfn.abstain.UNKNOWN,
    $r4HBytes,$r4HDirReturned,$r4HComplete,($r4HDirReturned-$r4HComplete),
    $r4HCalls,$r4HRetained,$r4HProbable,$r4HForged)
