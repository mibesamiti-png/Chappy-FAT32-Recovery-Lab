#requires -Version 5.1
# Team B B4-05: bounded, redacted, versioned, read-only result interface.
# Directory stream byte counts and extents are self-reported, NOT A receipts.
. (Join-Path $PSScriptRoot 'DirectoryScanner.ps1')
. (Join-Path $PSScriptRoot 'DirectoryHierarchy.ps1')

function Get-ChappyBSafeEvidenceCodes {
    param([object]$Codes,[int]$Limit=16)
    $out=New-Object System.Collections.ArrayList
    foreach($code in @($Codes)){
        if($out.Count -ge $Limit){break}
        if($code -isnot [string] -or $code -cnotmatch '^[a-z][a-z0-9_]{0,63}$'){continue}
        if(-not $out.Contains($code)){[void]$out.Add($code)}
    }
    return @($out.ToArray())
}
function Get-ChappyBDirectoryEvidenceV1 {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [switch]$EnableDirectoryEvidenceV1,
        [object]$Geometry=$null,
        [ValidateRange(512,32768)][long]$MaxScanBytes=1024L,
        [ValidateRange(1,32)][int]$MaxCandidates=16,
        [ValidateRange(1,16)][int]$MaxDirectories=8,
        [ValidateRange(1,32)][int]$MaxReadSpans=16,
        [ValidateRange(1,32)][int]$MaxNodes=16,
        [ValidateRange(1,32)][int]$MaxEdges=16,
        [ValidateRange(1,128)][int]$MaxMetadataItems=64,
        [ValidateRange(1,512)][int]$MaxAncestorSteps=128,
        [switch]$IncludeDeleted
    )
    $limits=[pscustomobject]@{
        maxScanBytes=$MaxScanBytes;maxCandidates=$MaxCandidates
        maxDirectories=$MaxDirectories;maxReadSpans=$MaxReadSpans
        maxNodes=$MaxNodes;maxEdges=$MaxEdges
        maxMetadataItems=$MaxMetadataItems;maxAncestorSteps=$MaxAncestorSteps
    }
    $m=[pscustomobject]@{
        candidateCount=0;nodeCount=0;edgeCount=0;probableParentEdges=0
        unknownOriginalPaths=0
        bCompletedDirectoryBytes=0L;bReturnedDirectoryBytes=0L
        bIncompleteReturnedBytes=0L;bDirectoryReadCalls=0L
        bCompletedReadSpans=0;sourceReadAttestation='unattested'
        totalSourceReturnedBytes=$null;uniqueSourceReturnedBytes=$null
        geometryReturnedBytes=$null
    }
    $report=[ordered]@{
        schemaVersion='b_directory_evidence_v1';team='B'
        status='disabled';scanStatus='not_run';graphStatus='not_run'
        scanIncomplete=$true;originalIdentity='unknown'
        originalPathValidation='not_performed';canExport=$false
        canSelectFatCopy=$false
        sourceAuthority='B_scanner_report_unattested_not_A_receipt'
        geometry=$null;candidates=@();nodes=@();parentEdges=@();parentHints=@()
        directoryReadSpans=@();warnings=@('b4_05_optin_required');errors=@()
        bounds=$limits;metrics=$m
    }
    if(-not $EnableDirectoryEvidenceV1){return [pscustomobject]$report}
    $report.status='partial'
    $report.warnings=@('b4_05_original_identity_unknown')
    try {
        if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite){
            $report.warnings=@('b4_05_readonly_seekable_source_required')
            return [pscustomobject]$report
        }
        if($Stream.Length -lt 512){
            $report.warnings=@('b4_05_source_too_short')
            return [pscustomobject]$report
        }
        $scanArgs=@{
            Stream=$Stream;Geometry=$Geometry;MaxScanBytes=$MaxScanBytes
            MaxCandidates=$MaxCandidates;MaxDirectories=$MaxDirectories
            RecordDirectoryReadSpans=$true;MaxDirectoryReadSpans=$MaxReadSpans
            ClassifyIncompleteDirectoryReadOrigin=$true
            RecordDirectoryPhysicalReadBytes=$true
            IncludeDeleted=[bool]$IncludeDeleted
        }
        # Deliberately no IncludeNames, no FAT or source authenticity claims.
        $scan=Get-ChappyDirectoryCandidates @scanArgs
        $graphArgs=@{
            DirectoryResult=$scan;NeverPromoteUnattestedParentEdges=$true
            DetectConflictingContainerObservations=$true
            MaxContainerObservations=$MaxDirectories;MaxNodes=$MaxNodes
            MaxEdges=$MaxEdges;MaxMetadataItems=$MaxMetadataItems
            MaxAncestorSteps=$MaxAncestorSteps
        }
        $graph=Get-ChappyDirectoryHierarchyEvidence @graphArgs
        $report.scanStatus=[string]$scan.status
        $report.graphStatus=[string]$graph.status
        $report.scanIncomplete=([bool]$scan.scanIncomplete -or [bool]$graph.scanIncomplete)
        $report.status=$(if($scan.status -eq 'error'){'error'}else{'partial'})
        $codes=New-Object System.Collections.ArrayList
        [void]$codes.Add('b4_05_original_identity_unknown')
        if($scan.status -eq 'error'){[void]$codes.Add('b4_05_directory_scan_error')}
        foreach($code in (Get-ChappyBSafeEvidenceCodes (@($scan.warnings)+@($graph.warnings)) 32)){
            if(-not $codes.Contains($code)){[void]$codes.Add($code)}
        }
        $report.warnings=@($codes.ToArray())
        if($scan.status -eq 'error'){$report.errors=@('b4_05_directory_scan_error')}
        if($null -ne $scan.geometry){
            $report.geometry=[pscustomobject]@{
                dataOffsetBytes=[long]$scan.geometry.dataOffsetBytes
                clusterSizeBytes=[long]$scan.geometry.clusterSizeBytes
                rootCluster=[long]$scan.geometry.rootCluster
                maxCluster=[long]$scan.geometry.maxCluster
                attestation='unattested'
            }
        }
        $list=New-Object System.Collections.ArrayList
        foreach($item in @($scan.items)){
            if($list.Count -ge $MaxCandidates){break}
            $ns=[string]$item.nameSource
            if($ns -cnotin @('lfn_validated','short_8_3','deleted_short_partial')){$ns='unknown'}
            [void]$list.Add([pscustomobject]@{
                entryOffsetBytes=[long]$item.offsetBytes
                containerCluster=[long]$item.containerCluster
                startCluster=[long]$item.startCluster
                sizeBytes=[long]$item.sizeBytes
                isDirectory=[bool]$item.isDirectory
                deleted=[bool]$item.deleted
                nameAssociation=$ns
                structuralConfidence=$(if([string]$item.confidence -ceq 'probable'){'probable'}else{'partial'})
                originalIdentity='unknown'
                reasonCodes=@(Get-ChappyBSafeEvidenceCodes $item.evidence 16)
            })
        }
        $report.candidates=@($list.ToArray())
        $list=New-Object System.Collections.ArrayList
        foreach($node in @($graph.nodes)){
            if($list.Count -ge $MaxNodes){break}
            $linkStatus=[string]$node.linkStatus
            if($linkStatus -cnotmatch '^[a-z][a-z0-9_]{0,63}$'){$linkStatus='unknown'}
            [void]$list.Add([pscustomobject]@{
                cluster=[long]$node.cluster;isRoot=[bool]$node.isRoot
                parentClusterHint=$(if($null -eq $node.parentClusterHint){$null}else{[long]$node.parentClusterHint})
                linkStatus=$linkStatus;structuralConfidence='partial'
                originalIdentity='unknown'
            })
        }
        $report.nodes=@($list.ToArray())
        $list=New-Object System.Collections.ArrayList
        foreach($edge in @($graph.edges)){
            if($list.Count -ge $MaxEdges){break}
            if([string]$edge.confidence -in @('probable','verified')){
                throw 'B4-05 unattested graph promoted a parent'
            }
            $reason=[string]$edge.relationStatus
            if($reason -cnotmatch '^[a-z][a-z0-9_]{0,63}$'){$reason='unknown'}
            [void]$list.Add([pscustomobject]@{
                parentCluster=[long]$edge.parentCluster
                childCluster=[long]$edge.childCluster
                entryOffsetBytes=[long]$edge.entryOffsetBytes
                relationStatus=$reason;confidence='partial'
                sourceAttestation='unattested';originalIdentity='unknown'
                reasonCodes=@(Get-ChappyBSafeEvidenceCodes $edge.evidence 16)
            })
        }
        $report.parentEdges=@($list.ToArray())
        $list=New-Object System.Collections.ArrayList
        foreach($hint in @($graph.parentHints)){
            if($list.Count -ge $MaxNodes){break}
            $relation=[string]$hint.relationStatus
            if($relation -cnotmatch '^[a-z][a-z0-9_]{0,63}$'){$relation='unknown'}
            [void]$list.Add([pscustomobject]@{
                childCluster=[long]$hint.childCluster
                hintedParentCluster=[long]$hint.hintedParentCluster
                relationStatus=$relation;sourceAttestation='unattested'
            })
        }
        $report.parentHints=@($list.ToArray())
        $list=New-Object System.Collections.ArrayList
        if($null -ne $scan.directoryReadEvidence){
            foreach($span in @($scan.directoryReadEvidence.spans)){
                if($list.Count -ge $MaxReadSpans){break}
                $at=[long]$span.offsetBytes;$len=[long]$span.lengthBytes
                if($at -lt 0 -or $len -lt 1 -or $at -gt $Stream.Length-$len){
                    throw 'B4-05 invalid scanner read span'
                }
                [void]$list.Add([pscustomobject]@{
                    offsetBytes=$at;lengthBytes=$len
                    cluster=[long]$span.cluster;attestation='unattested'
                })
            }
        }
        $report.directoryReadSpans=@($list.ToArray())
        $p=$scan.directoryPhysicalReadEvidence
        if($null -eq $p){throw 'B4-05 missing B read accounting'}
        $returned=[long]$p.streamReturnedBytes
        $complete=[long]$scan.metrics.bytesRead
        $partial=$returned-$complete
        if($returned -lt 0 -or $complete -lt 0 -or $partial -lt 0 -or
           $returned -gt ($MaxScanBytes+131072L) -or [long]$p.readCalls -lt 0){
            throw 'B4-05 invalid B scanner self accounting'
        }
        $report.metrics=[pscustomobject]@{
            candidateCount=$report.candidates.Count
            nodeCount=$report.nodes.Count;edgeCount=$report.parentEdges.Count
            probableParentEdges=0;unknownOriginalPaths=$report.parentEdges.Count
            bCompletedDirectoryBytes=$complete;bReturnedDirectoryBytes=$returned
            bIncompleteReturnedBytes=$partial;bDirectoryReadCalls=[long]$p.readCalls
            bCompletedReadSpans=$report.directoryReadSpans.Count
            sourceReadAttestation='unattested'
            totalSourceReturnedBytes=$null;uniqueSourceReturnedBytes=$null
            geometryReturnedBytes=$null
        }
        return [pscustomobject]$report
    } catch {
        # Never print raw exception contents: possible source-specific text.
        # Read errors can happen AFTER physical returns; their counts are
        # UNKNOWN, not dishonestly reported as zero.
        $report.status='error';$report.scanIncomplete=$true
        $report.candidates=@();$report.nodes=@();$report.parentEdges=@()
        $report.parentHints=@();$report.directoryReadSpans=@()
        $report.geometry=$null
        $report.warnings=@('b4_05_module_or_source_unknown')
        $report.errors=@('b4_05_module_or_source_unknown')
        $report.metrics=[pscustomobject]@{
            candidateCount=0;nodeCount=0;edgeCount=0;probableParentEdges=0
            unknownOriginalPaths=0;bCompletedDirectoryBytes=$null
            bReturnedDirectoryBytes=$null;bIncompleteReturnedBytes=$null
            bDirectoryReadCalls=$null;bCompletedReadSpans=0
            sourceReadAttestation='unattested'
            totalSourceReturnedBytes=$null;uniqueSourceReturnedBytes=$null
            geometryReturnedBytes=$null
        }
        return [pscustomobject]$report
    }
}
