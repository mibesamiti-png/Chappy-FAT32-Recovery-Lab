#requires -Version 5.1
# B4-05 gate acceptance: actual versioned B consumer interface, artificial only.
# R1 fixed before code: Issue #71 comment 6856884541. No original IMG.
. (Join-Path (Join-Path $PSScriptRoot '..\modules\directory') 'DirectoryEvidenceEnvelope.ps1')
$b405Cases=@('M00','M01','M04','X02')
$b405Seeds=@(202611,202612,202613)
$b405Total=0L;$b405Outer=0L;$b405Directory=0L;$b405Calls=0L
$b405Candidates=0L;$b405Unknown=0L;$b405Errors=0L
$b405SourceHashes=New-Object System.Collections.ArrayList
foreach($b405Seed in $b405Seeds){
    foreach($b405Case in $b405Cases){
        $b405Fixture=New-ChappyA3DDamagedFixture -Case $b405Case -Seed $b405Seed
        [byte[]]$b405Image=[byte[]]$b405Fixture.image.Clone()
        $b405Before=Get-A3DSha256 $b405Image
        [void]$b405SourceHashes.Add($b405Before)
        $b405Stream=[ChappyBR4ObservedParentPositive.MeteredStream]::new($b405Image,97,-1L,128)
        try {
            $b405Off=Get-ChappyBDirectoryEvidenceV1 -Stream $b405Stream
            Assert-B ($b405Off.schemaVersion -ceq 'b_directory_evidence_v1' -and
                $b405Off.status -eq 'disabled' -and $b405Off.candidates.Count -eq 0 -and
                $b405Off.parentEdges.Count -eq 0 -and $b405Stream.Calls -eq 0 -and
                $b405Off.metrics.totalSourceReturnedBytes -eq $null) ('B4-05 default off never touches source: '+$b405Seed+' '+$b405Case)
            $b405Report=Get-ChappyBDirectoryEvidenceV1 -Stream $b405Stream -EnableDirectoryEvidenceV1 -MaxScanBytes 1024 -MaxCandidates 16 -MaxDirectories 8 -MaxReadSpans 8
            $b405Events=@($b405Stream.Events)
            Assert-B (-not $b405Stream.CanWrite -and
                (Test-BR4EventsMatchInput $b405Events $b405Image) -and
                $b405Stream.Calls -le 128 -and $b405Stream.ReturnedBytes -le 2048 -and
                $b405Report.schemaVersion -ceq 'b_directory_evidence_v1' -and
                $b405Report.team -eq 'B' -and $b405Report.originalIdentity -eq 'unknown' -and
                $b405Report.originalPathValidation -eq 'not_performed' -and
                $b405Report.sourceAuthority -eq 'B_scanner_report_unattested_not_A_receipt' -and
                -not $b405Report.canExport -and -not $b405Report.canSelectFatCopy -and
                $b405Report.metrics.probableParentEdges -eq 0 -and
                $null -eq $b405Report.metrics.totalSourceReturnedBytes -and
                $null -eq $b405Report.metrics.uniqueSourceReturnedBytes -and
                $null -eq $b405Report.metrics.geometryReturnedBytes -and
                $b405Report.candidates.Count -le 16 -and $b405Report.parentEdges.Count -le 16 -and
                $b405Report.directoryReadSpans.Count -le 8 -and
                @($b405Report.directoryReadSpans|Where-Object{$_.attestation -ne 'unattested'}).Count -eq 0
            ) ('B4-05 bounded redacted versioned B result and untrusted read claims: '+$b405Seed+' '+$b405Case)
            $b405Json=ConvertTo-Json -InputObject $b405Report -Depth 12 -Compress
            Assert-B ($b405Json -notmatch '"name"\s*:|"shortName"\s*:|"path"\s*:|"sourceToken"\s*:|"originalPath"\s*:|verified' -and
                $b405Json -notmatch 'artificial-retained-name|M04-ORACLE|SYNTHETIC_ONLY' -and
                @($b405Report.candidates|Where-Object{
                    $null -ne $_.PSObject.Properties['name'] -or
                    $null -ne $_.PSObject.Properties['shortName'] -or
                    $_.originalIdentity -ne 'unknown'
                }).Count -eq 0) ('B4-05 serialized public-safe result excludes names and authenticated paths: '+$b405Seed+' '+$b405Case)
            if($b405Case -eq 'X02'){
                Assert-B ($b405Report.status -eq 'error' -and
                    $b405Report.scanStatus -eq 'error' -and
                    $b405Report.candidates.Count -eq 0 -and
                    $b405Report.directoryReadSpans.Count -eq 0 -and
                    $b405Report.metrics.bReturnedDirectoryBytes -eq 0 -and
                    $b405Stream.ReturnedBytes -eq 1024 -and
                    $b405Report.errors -contains 'b4_05_directory_scan_error') ('B4-05 X02 geometry truncated before any directory observation: '+$b405Seed)
                $b405Errors++
            } else {
                Assert-B ($b405Report.status -eq 'partial' -and
                    $b405Report.scanStatus -eq 'partial' -and
                    $b405Report.scanIncomplete -and
                    $b405Report.metrics.bCompletedDirectoryBytes -eq 1024 -and
                    $b405Report.metrics.bReturnedDirectoryBytes -eq 1024 -and
                    $b405Report.metrics.bIncompleteReturnedBytes -eq 0 -and
                    $b405Report.metrics.bCompletedReadSpans -eq 2 -and
                    $b405Report.candidates.Count -eq 3 -and
                    $b405Stream.ReturnedBytes -eq 2048 -and
                    @($b405Report.candidates|Where-Object{$_.originalIdentity -ne 'unknown'}).Count -eq 0
                ) ('B4-05 M00/M01/M04 preserve three unknown metadata candidates: '+$b405Seed+' '+$b405Case)
                $b405Candidates += [long]$b405Report.candidates.Count
            }
            $b405Total++
            $b405Outer += [long]$b405Stream.ReturnedBytes
            $b405Directory += [long]$b405Report.metrics.bReturnedDirectoryBytes
            $b405Calls += [long]$b405Stream.Calls
            $b405Unknown++
        } finally {$b405Stream.Dispose()}
        Assert-B ((Get-A3DSha256 $b405Image) -ceq $b405Before) ('B4-05 full artificial SHA unchanged: '+$b405Seed+' '+$b405Case)
    }
}
# Real, synthetically observed parent link under supplied A-style geometry:
# B retains the edge but always refuses source-unattested probable confidence.
$b405ParentImage=New-BR4ParentImage -Seed 202611 -Case matched_parent
$b405ParentBefore=Get-BR4Sha $b405ParentImage
$b405ParentGeo=[pscustomobject]@{
    dataOffsetBytes=1024L;clusterSizeBytes=512L;rootCluster=2L
    maxCluster=4L;partitionEndBytes=2560L;clusterCount=3L
}
$b405ParentStream=[ChappyBR4ObservedParentPositive.MeteredStream]::new($b405ParentImage,97,-1L,128)
try {
    $b405ParentReport=Get-ChappyBDirectoryEvidenceV1 -Stream $b405ParentStream -Geometry $b405ParentGeo -EnableDirectoryEvidenceV1 -MaxScanBytes 1536 -MaxReadSpans 8
    Assert-B ($b405ParentReport.status -eq 'partial' -and
        $b405ParentReport.metrics.bReturnedDirectoryBytes -eq 1536 -and
        $b405ParentReport.metrics.bCompletedDirectoryBytes -eq 1536 -and
        $b405ParentReport.metrics.probableParentEdges -eq 0 -and
        $b405ParentReport.parentEdges.Count -eq 1 -and
        $b405ParentReport.parentEdges[0].parentCluster -eq 2 -and
        $b405ParentReport.parentEdges[0].childCluster -eq 3 -and
        $b405ParentReport.parentEdges[0].relationStatus -eq 'parent_hint_corroborated' -and
        $b405ParentReport.parentEdges[0].confidence -eq 'partial' -and
        $b405ParentReport.parentEdges[0].reasonCodes -contains 'independent_source_attestation_required' -and
        $b405ParentReport.parentEdges[0].sourceAttestation -eq 'unattested' -and
        $b405ParentReport.metrics.unknownOriginalPaths -eq 1 -and
        $b405ParentReport.directoryReadSpans.Count -eq 3 -and
        $b405ParentStream.ReturnedBytes -eq 1536 -and
        (Test-BR4EventsMatchInput @($b405ParentStream.Events) $b405ParentImage)
    ) 'B4-05 genuine structural dotdot matched parent remains partial without A receipt'
} finally {$b405ParentStream.Dispose()}
Assert-B ((Get-BR4Sha $b405ParentImage) -ceq $b405ParentBefore) 'B4-05 parent positive generated SHA unchanged'
# Genuine physical partial return: completed=0, returned=17, spans empty.
$b405Root=[long](New-ChappyA3DCleanFixture -Seed 202611).layout.rootOffsetBytes
$b405EarlyImage=[byte[]](New-ChappyA3DDamagedFixture -Case M00 -Seed 202611).image.Clone()
$b405EarlyBefore=Get-A3DSha256 $b405EarlyImage
$b405Early=[ChappyBR4Physical.TracedSyntheticReadStream]::new(
    $b405EarlyImage,$b405Root,17,17,$b405Root,512)
try {
    $b405Truncated=Get-ChappyBDirectoryEvidenceV1 -Stream $b405Early -EnableDirectoryEvidenceV1 -MaxScanBytes 512 -MaxReadSpans 8
    Assert-B ($b405Truncated.status -eq 'error' -and
        $b405Truncated.scanStatus -eq 'error' -and
        $b405Truncated.metrics.bCompletedDirectoryBytes -eq 0 -and
        $b405Truncated.metrics.bReturnedDirectoryBytes -eq 17 -and
        $b405Truncated.metrics.bIncompleteReturnedBytes -eq 17 -and
        $b405Truncated.directoryReadSpans.Count -eq 0 -and
        $b405Truncated.candidates.Count -eq 0 -and
        $b405Early.DirectorySourceReturnedBytes -eq 17 -and
        $b405Early.AllSourceReturnedBytes -eq 1041
    ) 'B4-05 premature EOF returned 17B but completed zero clusters and original UNKNOWN'
} finally {$b405Early.Dispose()}
Assert-B ((Get-A3DSha256 $b405EarlyImage) -ceq $b405EarlyBefore) 'B4-05 early EOF synthetic SHA unchanged'
# Deny writable input and invalid budgets BEFORE touching source.
$b405Writable=[IO.MemoryStream]::new($b405EarlyImage,$true)
try {
    $b405Wrong=Get-ChappyBDirectoryEvidenceV1 -Stream $b405Writable -EnableDirectoryEvidenceV1
    Assert-B ($b405Wrong.status -eq 'partial' -and
        $b405Wrong.warnings -contains 'b4_05_readonly_seekable_source_required' -and
        $b405Writable.Position -eq 0 -and
        $b405Wrong.candidates.Count -eq 0) 'B4-05 writable stream rejected before read'
} finally {$b405Writable.Dispose()}
$b405BadCapStream=[ChappyBR4ObservedParentPositive.MeteredStream]::new($b405EarlyImage,97,-1L,128)
try {
    $b405Rejected=$false
    try {$null=Get-ChappyBDirectoryEvidenceV1 -Stream $b405BadCapStream -EnableDirectoryEvidenceV1 -MaxCandidates 33}
    catch {$b405Rejected=$true}
    Assert-B ($b405Rejected -and $b405BadCapStream.Calls -eq 0) 'B4-05 candidate cap over32 rejected before read'
} finally {$b405BadCapStream.Dispose()}
Assert-B ($b405Total -eq 12 -and $b405Errors -eq 3 -and
    $b405Candidates -eq 27 -and $b405Unknown -eq 12 -and
    $b405SourceHashes.Count -eq 12 -and
    $b405Outer -eq 21504 -and $b405Directory -eq 9216 -and
    $b405Calls -eq 252) 'B4-05 fixed 3seed x four-case corpus with independent outer source returns'
Write-Host ('B4-05 SYNTHETIC: rows={0} unknownIdentity={1} unreadableX02={2}, retainedCandidateInstances={3}; actual outer Source.Read return={4}B, B directory return={5}B, Read calls={6}; parent matched structural retained1 partial; early EOF directory17B complete0; user files recovered=0' -f
    $b405Total,$b405Unknown,$b405Errors,$b405Candidates,$b405Outer,$b405Directory,$b405Calls)
