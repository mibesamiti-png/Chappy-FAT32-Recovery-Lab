#requires -Version 5.1
# Team B R4: synthetic-only impossibility / observational equivalence.
# The external scorer knows which artificial file is truly empty or has a
# damaged size field; this truth is NEVER passed to the B directory scanner.
# No FAT/file content is examined by B, no original file/path is certified.

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Security.Cryptography;
namespace ChappyBR4Identifiability {
  public sealed class ArtificialReadTrace : MemoryStream {
    public readonly List<string> Events = new List<string>();
    public long ReturnedBytes { get; private set; }
    public int Calls { get; private set; }
    public ArtificialReadTrace(byte[] bytes) : base(bytes, false) {}
    public override int Read(byte[] bytes, int offset, int count) {
      long start = Position;
      int returned = base.Read(bytes, offset, count);
      Calls++;
      ReturnedBytes += returned;
      // Synthetic-only scorer: commit to the actual bytes of EACH successful
      // read, including BPB/geometry. No bytes or hashes are logged to CI.
      using (var sha = SHA256.Create()) {
        byte[] digest = sha.ComputeHash(bytes, offset, returned);
        Events.Add(start.ToString() + ":" + returned.ToString() + ":" +
                   BitConverter.ToString(digest));
      }
      return returned;
    }
  }
}
'@ -ErrorAction Stop

# Research-only third arm: audit whether B has any independent evidence of
# original file size beyond a single observed zero-size/start-cluster field.
# A matching directory entry, LFN checksum or observed cluster-address alone
# does not prove actual original size, FAT ownership or payload integrity.
function Get-R4YIndependentSizeVerdict {
    param([object]$Result,[object]$Item)
    if ($null -eq $Item) { return 'unobserved' }
    if ($Item.deleted -or $Item.isDirectory) { return 'unscored' }
    if ([long]$Item.sizeBytes -ne 0 -or [long]$Item.startCluster -lt 2) {
        return 'no_alert'
    }
    # No B directory candidate contains an independently verified payload
    # length. A caller-owned read-span counter is not such verification.
    # Returning unknown is deliberate; not an improved damage detector.
    return 'unknown'
}

function Add-R4YOracleResult {
    param([hashtable]$Scores,[string]$Arm,[bool]$ActuallyDamaged,[string]$Verdict)
    if ($Verdict -eq 'unknown') {
        $Scores[$Arm].UNKNOWN++
        if ($ActuallyDamaged) { $Scores[$Arm].UNKNOWN_DAMAGED++ }
    } elseif ($Verdict -eq 'damage') {
        if ($ActuallyDamaged) { $Scores[$Arm].TP++ } else { $Scores[$Arm].FP++ }
    } elseif ($Verdict -eq 'no_alert') {
        if ($ActuallyDamaged) { $Scores[$Arm].FN++ } else { $Scores[$Arm].TN++ }
    } else { throw "Unexpected synthetic oracle verdict category" }
}

$r4YSeed=202611
$r4YRoot=[int]$r4NLayout.rootOffsetBytes
$r4YBroken=New-ChappyA3DDamagedFixture -Case M04 -Seed $r4YSeed
[byte[]]$r4YDamaged=[byte[]]$r4YBroken.image.Clone()
[byte[]]$r4YHealthyTwin=[byte[]]$r4YDamaged.Clone()

# Test-only external truth alteration, OUTSIDE the read window of root and
# next cluster: erase artificial 3MF payload and leave one allocated EOC
# start-cluster entry on both FATs for a logically empty zero-length record.
# This does not assert that all FAT implementations canonically store empty
# files with a nonzero start cluster; it is an explicit synthetic control.
$r4YModelCluster4=$r4YRoot+2*512
if ($r4YModelCluster4 -ne 58880 -or $r4YRoot -ne 57856 -or
    $r4YModelCluster4+1024 -gt $r4YHealthyTwin.Length) {
    throw 'R4 Y artificial layout not the frozen generator layout'
}
[Array]::Clear($r4YHealthyTwin,$r4YModelCluster4,1024)
foreach ($r4YFatStart in @([int]$r4NLayout.fat1OffsetBytes,
                           [int]$r4NLayout.fat2OffsetBytes)) {
    $r4YCluster4Entry=$r4YFatStart+4*4
    $r4YCluster5Entry=$r4YFatStart+5*4
    [Array]::Copy([BitConverter]::GetBytes([uint32]0x0FFFFFFF),0,
                  $r4YHealthyTwin,$r4YCluster4Entry,4)
    [Array]::Clear($r4YHealthyTwin,$r4YCluster5Entry,4)
}
$r4YBrokenHash=Get-A3DSha256 $r4YDamaged
$r4YTwinHash=Get-A3DSha256 $r4YHealthyTwin
Assert-B ($r4YBrokenHash -cne $r4YTwinHash) 'R4 Y distinct artificial full-source SHA for empty and damaged-size truth'
$r4YObservedMismatch=0
for ($r4YI=0; $r4YI -lt 1024; $r4YI++) {
    if ($r4YDamaged[$r4YRoot+$r4YI] -ne
        $r4YHealthyTwin[$r4YRoot+$r4YI]) { $r4YObservedMismatch++ }
}
Assert-B ($r4YObservedMismatch -eq 0) 'R4 Y same 1024 directory bytes for different artificial size truth'

# The preceding B R4 synthetic test prepares these independent NEGATIVE
# controls from generated fixtures. No new real or personal data involved.
$r4YCases=@(
    [pscustomobject]@{id='healthy_empty0_and_9';image=[byte[]]$r4WLegitimate.Clone();deleted=$false},
    [pscustomobject]@{id='M04_real_damaged_size';image=$r4YDamaged;deleted=$false},
    [pscustomobject]@{id='M04_logically_empty_twin';image=$r4YHealthyTwin;deleted=$false},
    [pscustomobject]@{id='M04L_bad_lfn';image=[byte[]]$r4WLfn.Clone();deleted=$false},
    [pscustomobject]@{id='M04_deleted';image=[byte[]]$r4WDeleted.Clone();deleted=$true},
    [pscustomobject]@{id='false_parent_27';image=[byte[]]$r4WFalseParent.Clone();deleted=$false},
    [pscustomobject]@{id='X02_no_directory_data';image=[byte[]](New-ChappyA3DDamagedFixture -Case X02 -Seed $r4YSeed).image;deleted=$false}
)
$r4YArms=@('legacy','conservative','audit')
$r4YScores=@{
    legacy=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0;UNKNOWN_DAMAGED=0}
    conservative=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0;UNKNOWN_DAMAGED=0}
    audit=@{TP=0;FP=0;FN=0;TN=0;UNKNOWN=0;UNKNOWN_DAMAGED=0}
}
$r4YAllDirectoryBytes=0L
$r4YAllSourceBytes=0L
$r4YAllReadCalls=0L
$r4YNotScored=0
$r4YFalseProbablePaths=0
$r4YRetained=0
$r4YElapsed=@{legacy=0L;conservative=0L;audit=0L}
$r4YPairReports=@{}
$r4YPairTrace=@{}
foreach ($r4YCase in $r4YCases) {
    [byte[]]$r4YBytes=[byte[]]$r4YCase.image
    $r4YSourceHash=Get-A3DSha256 $r4YBytes
    $r4YResults=@{}
    $r4YTraces=@{}
    foreach ($r4YArm in $r4YArms) {
        $r4YStream=[ChappyBR4Identifiability.ArtificialReadTrace]::new($r4YBytes)
        try {
            $r4YParams=@{
                Stream=$r4YStream;MaxScanBytes=1024L;MaxCandidates=32;
                MaxDirectories=16;MaxDirectoryReadSpans=8;
                RecordDirectoryReadSpans=$true;
                ClassifyIncompleteDirectoryReadOrigin=$true;
                IncludeDeleted=$r4YCase.deleted
            }
            if ($r4YArm -eq 'legacy') {
                $r4YParams.ExperimentalFlagZeroSizeNonzeroStartCluster=$true
            } elseif ($r4YArm -eq 'conservative') {
                $r4YParams.ExperimentalConservativeZeroSizeUnknown=$true
            }
            $r4YClock=[Diagnostics.Stopwatch]::StartNew()
            $r4YResult=Get-ChappyDirectoryCandidates @r4YParams
            $r4YClock.Stop()
            $r4YElapsed[$r4YArm]+=[long]$r4YClock.ElapsedMilliseconds
            Assert-B (-not $r4YStream.CanWrite -and
                $r4YResult.scanIncomplete -and
                @($r4YResult.items|Where-Object{$null -ne $_.name -or $null -ne $_.shortName}).Count -eq 0) ('R4 Y readonly redacted incomplete scan: '+$r4YCase.id+' '+$r4YArm)
            $r4YAllDirectoryBytes += [long]$r4YResult.metrics.bytesRead
            $r4YAllSourceBytes += [long]$r4YStream.ReturnedBytes
            $r4YAllReadCalls += [long]$r4YStream.Calls
            $r4YResults[$r4YArm]=$r4YResult
            $r4YTraces[$r4YArm]=[string]::Join('|',$r4YStream.Events.ToArray())
            if ($r4YCase.id -eq 'M04_real_damaged_size' -or
                $r4YCase.id -eq 'M04_logically_empty_twin') {
                $r4YPairReports[$r4YCase.id+'_'+$r4YArm]=
                    (ConvertTo-Json -InputObject $r4YResult -Depth 10 -Compress)
                $r4YPairTrace[$r4YCase.id+'_'+$r4YArm]=$r4YTraces[$r4YArm]
            }
        } finally { $r4YStream.Dispose() }
        Assert-B ((Get-A3DSha256 $r4YBytes) -ceq $r4YSourceHash) ('R4 Y unchanged generated image SHA: '+$r4YCase.id+' '+$r4YArm)
    }
    $r4YBase=$r4YResults.legacy
    $r4YConservative=$r4YResults.conservative
    $r4YAudit=$r4YResults.audit
    Assert-B ($r4YBase.items.Count -eq $r4YConservative.items.Count -and
        $r4YBase.items.Count -eq $r4YAudit.items.Count -and
        $r4YBase.metrics.bytesRead -eq $r4YConservative.metrics.bytesRead -and
        $r4YBase.metrics.bytesRead -eq $r4YAudit.metrics.bytesRead -and
        $r4YTraces.legacy -ceq $r4YTraces.conservative -and
        $r4YTraces.legacy -ceq $r4YTraces.audit) ('R4 Y all three methods see same actual source-read transcript/candidates: '+$r4YCase.id)
    $r4YRetained += $r4YConservative.items.Count

    if ($r4YCase.id -eq 'healthy_empty0_and_9' -or
        $r4YCase.id -eq 'M04_real_damaged_size' -or
        $r4YCase.id -eq 'M04_logically_empty_twin') {
        $r4YTargets=if($r4YCase.id -eq 'healthy_empty0_and_9') {
            @([pscustomobject]@{start=0L;damaged=$false},
              [pscustomobject]@{start=9L;damaged=$false})
        } else {
            @([pscustomobject]@{start=4L;damaged=($r4YCase.id -eq 'M04_real_damaged_size')})
        }
        foreach($r4YTarget in $r4YTargets) {
            foreach($r4YArm in $r4YArms) {
                $r4YScan=$r4YResults[$r4YArm]
                $r4YMatches=@($r4YScan.items|Where-Object{
                    -not $_.deleted -and -not $_.isDirectory -and
                    $_.sizeBytes -eq 0 -and $_.startCluster -eq $r4YTarget.start
                })
                Assert-B ($r4YMatches.Count -eq 1) ('R4 Y target live record remains observable: '+$r4YCase.id+' '+$r4YArm+' start='+$r4YTarget.start)
                $r4YItem=$r4YMatches[0]
                $r4YVerdict=if($r4YArm -eq 'legacy') {
                    if($r4YItem.evidence -contains 'zero_size_with_nonzero_start_cluster') {'damage'}else{'no_alert'}
                } elseif($r4YArm -eq 'conservative') {
                    if($r4YItem.sizeIntegrity -eq 'unknown') {'unknown'}else{'no_alert'}
                } else {
                    Get-R4YIndependentSizeVerdict -Result $r4YScan -Item $r4YItem
                }
                Add-R4YOracleResult -Scores $r4YScores -Arm $r4YArm -ActuallyDamaged ([bool]$r4YTarget.damaged) -Verdict $r4YVerdict
            }
        }
    } elseif ($r4YCase.id -eq 'M04L_bad_lfn') {
        Assert-B (@($r4YAudit.items|Where-Object{
            $_.evidence -contains 'lfn_rejected_short_fallback' -and
            $_.confidence -eq 'partial'
        }).Count -eq 1) 'R4 Y independent LFN checksum rejection is not file-size integrity evidence'
        $r4YNotScored++
    } elseif ($r4YCase.id -eq 'M04_deleted') {
        Assert-B (@($r4YAudit.items|Where-Object{
            $_.deleted -and $_.sizeBytes -eq 0 -and $_.startCluster -ge 2
        }).Count -eq 1 -and @($r4YConservative.items|Where-Object{
            $_.deleted -and $_.evidence -contains 'zero_size_start_field_integrity_unknown'
        }).Count -eq 0) 'R4 Y deleted metadata retained but never counted as live-file corruption detection'
        $r4YNotScored++
    } elseif ($r4YCase.id -eq 'false_parent_27') {
        $r4YGraph=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $r4YAudit -DetectConflictingContainerObservations -RequireObservedClusterIntervals -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32 -MaxAncestorSteps 64
        $r4YFalseProbablePaths += [int]$r4YGraph.metrics.probableEdgeAssertions
        Assert-B (@($r4YAudit.items|Where-Object{$_.isDirectory -and $_.startCluster -eq 27}).Count -eq 1 -and
            $r4YGraph.scanIncomplete -and $r4YGraph.metrics.unresolvedTargetReferences -eq 1 -and
            $r4YGraph.metrics.probableEdgeAssertions -eq 0) 'R4 Y unobserved parent/child remains candidate, no probable original path'
        $r4YNotScored++
    } elseif ($r4YCase.id -eq 'X02_no_directory_data') {
        Assert-B ($r4YAudit.status -eq 'error' -and $r4YAudit.metrics.bytesRead -eq 0 -and
            $r4YAudit.items.Count -eq 0 -and $r4YAudit.directoryReadEvidence.readEvents -eq 0) 'R4 Y truncation yields no observed record; not a healthy-file TN'
        $r4YNotScored++
    }
}
foreach($r4YArm in $r4YArms) {
    $r4YA=$r4YPairReports['M04_real_damaged_size_'+$r4YArm]
    $r4YB=$r4YPairReports['M04_logically_empty_twin_'+$r4YArm]
    Assert-B ($r4YA -ceq $r4YB -and
        $r4YPairTrace['M04_real_damaged_size_'+$r4YArm] -ceq
        $r4YPairTrace['M04_logically_empty_twin_'+$r4YArm]) ('R4 Y impossible to distinguish different size truth from identical B-read bytes/metadata: '+$r4YArm)
}
$r4YL=$r4YScores.legacy
$r4YC=$r4YScores.conservative
$r4YA=$r4YScores.audit
Assert-B ($r4YL.TP -eq 1 -and $r4YL.FP -eq 2 -and $r4YL.FN -eq 0 -and $r4YL.TN -eq 1 -and $r4YL.UNKNOWN -eq 0 -and
    $r4YC.TP -eq 0 -and $r4YC.FP -eq 0 -and $r4YC.FN -eq 0 -and $r4YC.TN -eq 1 -and $r4YC.UNKNOWN -eq 3 -and $r4YC.UNKNOWN_DAMAGED -eq 1 -and
    $r4YA.TP -eq 0 -and $r4YA.FP -eq 0 -and $r4YA.FN -eq 0 -and $r4YA.TN -eq 1 -and $r4YA.UNKNOWN -eq 3 -and $r4YA.UNKNOWN_DAMAGED -eq 1) 'R4 Y fixed 4-live-record score legacy TP1 FP2 FN0 TN1; conservative/audit TP0 FP0 FN0 TN1 UNKNOWN3, including real damage'
Assert-B ($r4YAllDirectoryBytes -eq 18432L -and $r4YNotScored -eq 4 -and
    $r4YFalseProbablePaths -eq 0 -and $r4YRetained -ge 20) 'R4 Y bounded 18432 B directory scans across 3 methods, 4 unscored controls, 0 false probable paths'
Write-Host ('SYNTHETIC B R4 Y ONLY: 4 live records legacy TP={0} FP={1} FN={2} TN={3}; conservative TP={4} FP={5} FN={6} TN={7} UNKNOWN={8}; B-only audit TP={9} FP={10} FN={11} TN={12} UNKNOWN={13}; unscored={14}; directory-data bytes={15}; all-source returned bytes={16}; Read calls={17}; false original paths={18}; observationally equivalent M04 pair; no original identity verified' -f
    $r4YL.TP,$r4YL.FP,$r4YL.FN,$r4YL.TN,
    $r4YC.TP,$r4YC.FP,$r4YC.FN,$r4YC.TN,$r4YC.UNKNOWN,
    $r4YA.TP,$r4YA.FP,$r4YA.FN,$r4YA.TN,$r4YA.UNKNOWN,
    $r4YNotScored,$r4YAllDirectoryBytes,$r4YAllSourceBytes,$r4YAllReadCalls,$r4YFalseProbablePaths)
