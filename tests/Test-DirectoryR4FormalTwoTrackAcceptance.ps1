#requires -Version 5.1
# B original R4 complete-stage acceptance audit, generated artificial data only.
# R0/R1 preregistration: Issue #71 comment 6863350674.
. (Join-Path $PSScriptRoot 'helpers\New-ChappyA3DStandardFixture.ps1')
. (Join-Path (Join-Path $PSScriptRoot '..\modules\directory') 'DirectoryEvidenceEnvelope.ps1')
. (Join-Path (Join-Path $PSScriptRoot '..\modules\directory') 'DirectoryReadReconciliation.ps1')
. (Join-Path (Join-Path $PSScriptRoot '..\modules\directory') 'DirectoryParentObservationJoin.ps1')

function Get-BR4FormalUniqueReturnedBytes {
    param([object[]]$Events)
    [long]$unique=0
    [long]$end=-1
    foreach($ev in @($Events|Where-Object{[long]$_.Returned -gt 0}|Sort-Object Offset)) {
        [long]$at=$ev.Offset
        [long]$next=$at+[long]$ev.Returned
        if($at -lt 0 -or $next -lt $at){throw 'R4 formal invalid event extent'}
        if($at -ge $end){$unique+=$next-$at}
        elseif($next -gt $end){$unique+=$next-$end}
        if($next -gt $end){$end=$next}
    }
    return $unique
}

# All counters came from earlier, independently executing B tests.
# These are different units and MUST NOT be pooled into one success rate.
Assert-B ($r4GateScores.legacy.TP -eq 3 -and $r4GateScores.legacy.FP -eq 9 -and
    $r4GateScores.legacy.FN -eq 0 -and $r4GateScores.legacy.TN -eq 6 -and
    $r4GateScores.legacy.UNKNOWN -eq 6 -and
    $r4GateScores.conservative.TP -eq 0 -and $r4GateScores.conservative.FP -eq 0 -and
    $r4GateScores.conservative.FN -eq 0 -and $r4GateScores.conservative.TN -eq 6 -and
    $r4GateScores.conservative.UNKNOWN -eq 18 -and $r4GateUnobservedEdgeUnits -eq 24L) 'R4 FORMAL: 24 size units/arm, base parent UNKNOWN24 not TN'
Assert-B ($b402Lfn.TP -eq 6 -and $b402Lfn.FP -eq 0 -and
    $b402Lfn.FN -eq 0 -and $b402Lfn.TN -eq 6 -and
    $b402Deletion.TP -eq 6 -and $b402Deletion.TN -eq 6 -and
    $b402Orphan.TP -eq 12 -and $b402Orphan.TN -eq 12 -and
    $b402UnknownPaths -eq 12L -and $b402Retained -eq 66L) 'R4 FORMAL: clean/bad LFN, deletion visibility, orphan/decoy, retained candidates'
Assert-B ($r4HPairs -eq 6 -and $r4HCount -eq 12 -and
    $r4HParent.naive.TP -eq 6 -and $r4HParent.naive.FP -eq 6 -and
    $r4HParent.abstain.UNKNOWN -eq 12 -and
    $r4HStrictTruthSupported -eq 3 -and $r4HStrictTruthContradicted -eq 3 -and
    $r4HStrictSuppressed -eq 6) 'R4 FORMAL: six indistinguishable hidden-parent pairs and forged ledger no original path'
Assert-B ($b403Scans -eq 12 -and $b403Observed -eq 3 -and
    $b403Ambiguous -eq 3 -and $b403ShortUnknown -eq 3 -and
    $b403NoParent -eq 3 -and $b404ControlScans -eq 9 -and
    $b404Contradictions -eq 8 -and $b404Unknown -eq 2 -and
    $b405Total -eq 12 -and $b405Errors -eq 3) 'R4 FORMAL: parent/dotdot physical cases, EOF, outer ledger mismatches and versioned bounds'

# R3 genuine standards-shaped artificial FAT32, >65,525 data clusters.
# Both cluster-size variants use the same production B evidence reader.
$r4FormalSeed=202611
$r4FormalStdCases=0
$r4FormalReturned=0L
$r4FormalUnique=0L
$r4FormalDirectory=0L
$r4FormalCalls=0L
$r4FormalCandidates=0L
$r4FormalForgedDenied=0
$r4FormalShortUnknown=0
$r4FormalPeakProcessBytes=0L
$r4FormalElapsed=0L
foreach($spc in @(1,2)){
    $std=New-ChappyA3DStandardFixture -Seed $r4FormalSeed -SectorsPerCluster $spc
    [byte[]]$img=$std.image
    $before=Get-A3DSha256 $img
    $clusterSize=512*$spc
    $reader=[ChappyBR4ObservedParentPositive.MeteredStream]::new($img,97,-1L,64)
    try{
        $disabled=Get-ChappyBDirectoryEvidenceV1 -Stream $reader
        Assert-B ($disabled.status -ceq 'disabled' -and
            $disabled.parentEdges.Count -eq 0 -and
            $disabled.candidates.Count -eq 0 -and $reader.Calls -eq 0) ('R4 FORMAL R3-SPC'+$spc+': default-OFF zero reads')
        $timer=[Diagnostics.Stopwatch]::StartNew()
        $b=Get-ChappyBDirectoryEvidenceV1 -Stream $reader -EnableDirectoryEvidenceV1 -MaxScanBytes $clusterSize -MaxCandidates 16 -MaxDirectories 8 -MaxReadSpans 8 -MaxNodes 16 -MaxEdges 16 -MaxMetadataItems 32
        $timer.Stop()
        $r4FormalElapsed += [long]$timer.ElapsedMilliseconds
        $raw=@($reader.Events)
        Assert-B ((Test-BR4EventsMatchInput $raw $img) -and
            -not $reader.CanWrite -and $reader.Calls -le 64 -and
            $img.Length -gt 30MB -and $img.Length -lt 80MB) ('R4 FORMAL R3-SPC'+$spc+': independent successful Stream.Read chunk SHA and artificial readonly')
        $events=@(New-B404AEventCopies $raw ([long]$b.geometry.dataOffsetBytes))
        $match=Compare-ChappyBDirectoryReturnedEvidenceV1 -DirectoryEnvelope $b -OuterReadEvents $events -SourceLengthBytes $img.Length -MaxEvents 64 -MaxSpans 8
        $parent=Get-ChappyBParentObservationV1 -DirectoryEnvelope $b -OuterReadEvents $events -SourceLengthBytes $img.Length -MaxEdges 16 -MaxSpans 8 -MaxEvents 64
        $unique=Get-BR4FormalUniqueReturnedBytes $raw
        $expectedReturned=1024L+[long]$clusterSize
        $expectedCalls=12+[int][Math]::Ceiling($clusterSize/97.0)
        Assert-B ($b.schemaVersion -ceq 'b_directory_evidence_v1' -and
            $b.status -eq 'partial' -and $b.scanIncomplete -and
            $b.geometry.clusterSizeBytes -eq $clusterSize -and
            $b.geometry.maxCluster -eq 65542L -and $b.geometry.rootCluster -eq 2L -and
            $b.candidates.Count -eq 3 -and
            @($b.candidates|Where-Object{$_.isDirectory -or $_.deleted}).Count -eq 0 -and
            $b.nodes.Count -ge 1 -and $b.parentEdges.Count -eq 0 -and
            $b.directoryReadSpans.Count -eq 1 -and
            $b.metrics.bCompletedDirectoryBytes -eq $clusterSize -and
            $b.metrics.bReturnedDirectoryBytes -eq $clusterSize -and
            $b.metrics.bIncompleteReturnedBytes -eq 0 -and
            $null -eq $b.metrics.totalSourceReturnedBytes -and
            $reader.ReturnedBytes -eq $expectedReturned -and
            $reader.Calls -eq $expectedCalls) ('R4 FORMAL R3-SPC'+$spc+': 3 candidates, only one of 65541 data clusters observed')
        Assert-B ($match.decision -ceq 'consistent_unattested' -and
            $match.metrics.matchingCompletedSpans -eq 1 -and
            $match.metrics.outerDirectoryReturnedBytes -eq $clusterSize -and
            $match.metrics.outerDirectoryUniqueBytes -eq $clusterSize -and
            $parent.metrics.observedPairUnattested -eq 0 -and
            $parent.parentObservations.Count -eq 0 -and
            $parent.originalIdentity -ceq 'unknown' -and
            $parent.sourceAuthenticity -ceq 'not_proven' -and
            $parent.metrics.additionalStreamReads -eq 0 -and
            $reader.ReturnedBytes -eq $unique) ('R4 FORMAL R3-SPC'+$spc+': exact returned/unique bytes not authenticated source receipts')
        $json=ConvertTo-Json -InputObject $b -Depth 12 -Compress
        Assert-B ($json -notmatch '"name"\s*:|"shortName"\s*:|"path"\s*:|verified|sourceToken|originalPath"\s*:' -and
            @($b.candidates|Where-Object{$_.originalIdentity -ne 'unknown'}).Count -eq 0 -and
            $b.originalIdentity -ceq 'unknown' -and
            -not $b.canExport -and -not $b.canSelectFatCopy) ('R4 FORMAL R3-SPC'+$spc+': candidate metadata visible but original path UNKNOWN')
        # Forge only B's self-reported completed cluster; physical events stay unchanged.
        $fake=$b|ConvertTo-Json -Depth 12 -Compress|ConvertFrom-Json
        $fake.directoryReadSpans[0].lengthBytes=2*$clusterSize
        $fake.metrics.bCompletedDirectoryBytes=2*$clusterSize
        $fake.metrics.bReturnedDirectoryBytes=2*$clusterSize
        $wrong=Compare-ChappyBDirectoryReturnedEvidenceV1 -DirectoryEnvelope $fake -OuterReadEvents $events -SourceLengthBytes $img.Length -MaxEvents 64 -MaxSpans 8
        Assert-B ($wrong.decision -ceq 'contradicted' -and
            $wrong.originalIdentity -ceq 'unknown' -and
            -not $wrong.canExport) ('R4 FORMAL R3-SPC'+$spc+': forged second complete B cluster contradicted')
        $r4FormalForgedDenied++
        $r4FormalStdCases++
        $r4FormalReturned += [long]$reader.ReturnedBytes
        $r4FormalUnique += $unique
        $r4FormalDirectory += [long]$b.metrics.bReturnedDirectoryBytes
        $r4FormalCalls += [long]$reader.Calls
        $r4FormalCandidates += [long]$b.candidates.Count
        # OS process peak includes fixture generation and other suites, not B-only peak.
        $peak=[Diagnostics.Process]::GetCurrentProcess().PeakWorkingSet64
        $r4FormalPeakProcessBytes=[Math]::Max($r4FormalPeakProcessBytes,[long]$peak)
        Write-Host ('R4 FORMAL TWO-TRACK: track=R3-SPC{0}, seed={1}, candidateUnits=3, observedDirClusters=1/65541, actualReturned={2}B unique={3}B directory={4}B readCalls={5} elapsed-ms={6}, processGlobalPeakBytes={7}, sourceAuth=UNKNOWN' -f $spc,$r4FormalSeed,$reader.ReturnedBytes,$unique,$clusterSize,$reader.Calls,$timer.ElapsedMilliseconds,$peak)
    }finally{$reader.Dispose()}
    # Independent short-root EOF on SAME SPC1 artificial source.
    if($spc -eq 1){
        $rootBytes=[long]$b.geometry.dataOffsetBytes
        $short=[ChappyBR4ObservedParentPositive.MeteredStream]::new($img,97,($rootBytes+17L),64)
        try{
            $partial=Get-ChappyBDirectoryEvidenceV1 -Stream $short -EnableDirectoryEvidenceV1 -MaxScanBytes 512 -MaxCandidates 16 -MaxDirectories 8 -MaxReadSpans 8
            $shortEvents=@(New-B404AEventCopies @($short.Events) $rootBytes)
            $uncertain=Compare-ChappyBDirectoryReturnedEvidenceV1 -DirectoryEnvelope $partial -OuterReadEvents $shortEvents -SourceLengthBytes $img.Length -MaxEvents 64 -MaxSpans 8
            Assert-B ((Test-BR4EventsMatchInput @($short.Events) $img) -and
                $short.ReturnedBytes -eq 1041L -and $short.Calls -le 64 -and
                $partial.metrics.bReturnedDirectoryBytes -eq 17L -and
                $partial.metrics.bCompletedDirectoryBytes -eq 0L -and
                $partial.metrics.bIncompleteReturnedBytes -eq 17L -and
                $partial.candidates.Count -eq 0 -and $partial.directoryReadSpans.Count -eq 0 -and
                $uncertain.decision -ceq 'partial_unknown' -and
                $uncertain.metrics.outerDirectoryReturnedBytes -eq 17L -and
                $uncertain.originalIdentity -ceq 'unknown' -and
                -not $uncertain.canExport) 'R4 FORMAL R3-SPC1: 17/512 source-read EOF stays UNKNOWN, not TN'
            $r4FormalShortUnknown++
            Write-Host ('R4 FORMAL SHORT EOF: standard SPC1, total source returned={0}B, directory returned=17B complete=0B, calls={1}, original path UNKNOWN' -f $short.ReturnedBytes,$short.Calls)
        }finally{$short.Dispose()}
    }
    Assert-B ((Get-A3DSha256 $img) -ceq $before) ('R4 FORMAL R3-SPC'+$spc+': full artificial source SHA unchanged')
}
Assert-B ($r4FormalStdCases -eq 2 -and $r4FormalReturned -eq 3584L -and
    $r4FormalUnique -eq 3584L -and $r4FormalDirectory -eq 1536L -and
    $r4FormalCalls -eq 41L -and $r4FormalCandidates -eq 6L -and
    $r4FormalForgedDenied -eq 2 -and $r4FormalShortUnknown -eq 1) 'R4 FORMAL: standard 2 variants, 6 candidate metadata units, 2 forged-deny and one short UNKNOWN'
Write-Host ('R4 ORIGINAL STAGE AUDIT: standards cases={0} candidateInstances={1}, returned={2}B unique={3}B directory={4}B calls={5}, forgedDenied={6}, shortUnknown={7}; original file/path UNKNOWN, source B consistency NOT A receipt, A-only full R4 signoff, official 39 percent unchanged' -f $r4FormalStdCases,$r4FormalCandidates,$r4FormalReturned,$r4FormalUnique,$r4FormalDirectory,$r4FormalCalls,$r4FormalForgedDenied,$r4FormalShortUnknown)
