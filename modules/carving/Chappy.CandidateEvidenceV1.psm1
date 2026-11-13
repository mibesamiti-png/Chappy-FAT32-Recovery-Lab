#requires -Version 5.1
# Team C / R5 C5-06 — guarded, versioned, export-free C evidence facade.
# This is NOT a trusted A interface or proof of original file identity.
# The user-provided source must be generated artificial memory; the C module
# cannot authenticate the provenance of bytes supplied by a caller.
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Chappy.CoverageEvidence.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Chappy.FragmentEvidence.psm1') -ErrorAction Stop

function Get-ChappyCarvingCandidateEvidenceV1 {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][IO.Stream]$Source,
        [switch]$EnableCandidateEvidence,
        # Only search-region hints. Never first/tail correct positions or SHA.
        [ValidateRange(0,9223372036854775806)][long]$WindowStartBytes=0,
        [ValidateRange(512,65536)][int]$WindowBytes=65536,
        [switch]$EnableStandardsShapedSource,
        [switch]$EnableExpandedFiniteHypotheses,
        [ValidateRange(512,81920)][long]$MaxSourceReturnedBytes=81920,
        [ValidateRange(2,512)][int]$MaxPhysicalReadCalls=512,
        [ValidateRange(100,30000)][int]$MaxWorkMilliseconds=30000
    )
    $m=[pscustomobject][ordered]@{
        sourceReturnedBytes=0L;sourceUniqueReturnedBytes=0L
        sourceRepeatedReturnedBytes=0L;sourceReadCalls=0
        successfulReadCalls=0;zeroByteReadCalls=0;sourceObservedReadIntervals=0
        sectorProbes=0;startSignatures=0;tailSignatures=0
        pairAttempts=0;candidateCount=0;inMemoryZipValidatorBytes=0L
        elapsedMilliseconds=0L
        maxReturnedSourceBytes=[long]$MaxSourceReturnedBytes
        maxReadCalls=[int]$MaxPhysicalReadCalls
        maxInMemoryZipValidatorBytes=98304L
        maxSectorScratchBytes=512;maxPairScratchBytes=1056
        processPeakMemoryBytes=$null;processPeakMemoryStatus='not_measured'
        stopCode='candidate.optin_required'
    }
    $out=[ordered]@{
        schemaVersion='c_candidate_evidence_v1';team='C';status='disabled'
        decision='unknown';scanIncomplete=$true
        evidenceMode='disabled'
        searchWindowStartBytes=$null;searchWindowBytes=$null
        searchWindowHintOrigin='caller_unattested'
        sourceAuthenticity='not_proven';sourceReadAttestation='C_unattested_A_outer_receipt_required'
        originalIdentity='unknown';originalShaVerified=$false
        canSelectOriginal=$false;selectedOriginal=$null
        canExport=$false;canRepair=$false
        candidateDefinitions=@();candidateCount=0
        warnings=@('candidate.optin_required');metrics=$m
    }
    # Entire API is deny-by-default; do not access Source properties or Read.
    if(-not $EnableCandidateEvidence){return [pscustomobject]$out}

    $out.status='partial';$out.decision='incomplete'
    $out.evidenceMode='finite_two_fragment_zip_3mf_window_only'
    $out.searchWindowStartBytes=[long]$WindowStartBytes
    $out.searchWindowBytes=[long]$WindowBytes
    $out.warnings=@('candidate.preflight_denied')
    $m.stopCode='candidate.preflight_denied'
    # No physical devices, paths, FileStreams or external stream wrappers are
    # accepted by this *new* C-facing experimental entry point.
    # NOTE: an in-memory source alone does NOT attest original data origin.
    if($Source -isnot [IO.MemoryStream] -or
       -not $Source.CanRead -or -not $Source.CanSeek -or $Source.CanWrite) {
        $m.stopCode='candidate.readonly_memory_required'
        $out.warnings=@($m.stopCode)
        return [pscustomobject]$out
    }
    if(($WindowStartBytes%512L) -ne 0 -or ($WindowBytes%512) -ne 0 -or
       $MaxSourceReturnedBytes -lt $WindowBytes -or
       $WindowStartBytes -gt ($Source.Length-[long]$WindowBytes) -or
       ($Source.Length -gt 2097152L -and -not $EnableStandardsShapedSource) -or
       ($EnableStandardsShapedSource -and $Source.Length -gt 134217728L)) {
        $m.stopCode='candidate.window_or_budget_unavailable'
        $out.warnings=@($m.stopCode)
        return [pscustomobject]$out
    }
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $meter=$null
    try {
        $meter=[ChappyC5ReturnedByteMeterV1]::new(
            $Source,[long]$MaxSourceReturnedBytes,[int]$MaxPhysicalReadCalls
        )
        # Fixed candidate enumeration. All cases use the same caller-chosen
        # hypotheses; no oracle start/tail offsets or lengths are ever input.
        $kwargs=@{
            Source=$meter;EnableFragmentEvidence=$true
            StartOffsetBytes=[long]$WindowStartBytes
            WindowBytes=[int]$WindowBytes
            EnableStandardsShapedSource=[bool]$EnableStandardsShapedSource
            IncludeStartPhasePlusTwo=[bool]$EnableExpandedFiniteHypotheses
            IncludeFirstPiece560=[bool]$EnableExpandedFiniteHypotheses
            MaxStarts=4;MaxTails=8;MaxPairs=16
            MaxSourceBytes=[long]$MaxSourceReturnedBytes
            MaxValidationBytes=98304L;MaxMilliseconds=[int]$MaxWorkMilliseconds
        }
        $scan=Get-ChappyFragmentCandidates @kwargs
        $m.sectorProbes=[int]$scan.metrics.sectorProbes
        $m.startSignatures=[int]$scan.metrics.startCandidates
        $m.tailSignatures=[int]$scan.metrics.tailCandidates
        $m.pairAttempts=[int]$scan.metrics.pairAttempts
        $m.inMemoryZipValidatorBytes=[long]$scan.metrics.validatorBytesRead

        if($scan.status -cne 'ok' -or $meter.RefusedBudget -or
           $scan.metrics.sourceBytesRead -ne $meter.ReturnedBytes -or
           $scan.metrics.readRequests -ne $meter.ReadCalls -or
           $m.sectorProbes -gt [int]($WindowBytes/512) -or
           $m.startSignatures -gt 4 -or $m.tailSignatures -gt 8 -or
           $m.pairAttempts -gt 16 -or
           $m.inMemoryZipValidatorBytes -gt 98304L -or
           @($scan.items).Count -gt 16) {
            $m.stopCode='candidate.incomplete_or_meter_conflict'
        }else{
            $safe=New-Object 'System.Collections.Generic.List[object]'
            $seen=New-Object 'System.Collections.Generic.HashSet[string]'
            foreach($item in @($scan.items)){
                $spans=@($item.sourceSpans)
                if($spans.Count -ne 2 -or $item.format -cne '3mf' -or
                   $item.confidence -cne 'probable' -or
                   $item.originalIdentity -cne 'unknown' -or
                   $item.integrityScope -cne 'structural_only_not_original_file_integrity' -or
                   $item.sourceOrigin -cne 'unattributed_without_A_meter') {
                    throw 'candidate.invalid_format_evidence'
                }
                $first=$spans[0];$tail=$spans[1]
                [long]$a=$first.offsetBytes;[long]$al=$first.lengthBytes
                [long]$b=$tail.offsetBytes;[long]$bl=$tail.lengthBytes
                [long]$end=[long]$WindowStartBytes+[long]$WindowBytes
                $key=('3mf:{0}+{1},{2}+{3}' -f $a,$al,$b,$bl)
                if($al -le 0 -or $bl -le 0 -or ($al+$bl) -gt 1056L -or
                   $a -lt $WindowStartBytes -or $b -lt $WindowStartBytes -or
                   $a -gt ($end-$al) -or $b -gt ($end-$bl) -or
                   ($a -lt ($b+$bl) -and $b -lt ($a+$al)) -or
                   $item.candidateKey -cne $key -or -not $seen.Add($key)) {
                    throw 'candidate.invalid_window_spans'
                }
                $safe.Add([pscustomobject]@{
                    candidateKey=$key;keyScope='C_unattested_source_relative_only'
                    format='3mf';extentCount=2;lengthBytes=[long]($al+$bl)
                    confidence='probable'
                    integrityScope='structural_only_not_original_file_integrity'
                    originalIdentity='unknown';sourceAuthenticity='not_proven'
                    canSelectOriginal=$false;canExport=$false
                    sourceSpans=@(
                        [pscustomobject]@{sequence=0;offsetBytes=$a;lengthBytes=$al;origin='source_observed_unattested'},
                        [pscustomobject]@{sequence=1;offsetBytes=$b;lengthBytes=$bl;origin='source_observed_unattested'}
                    )
                    evidence=@('zip.local_header','zip.central_directory','zip.eocd','zip.crc_consistent')
                })
            }
            if(($scan.decision -eq 'one_possible' -and $safe.Count -ne 1) -or
               ($scan.decision -eq 'ambiguous' -and $safe.Count -lt 2) -or
               ($scan.decision -eq 'unknown' -and $safe.Count -ne 0) -or
               $scan.decision -notin @('one_possible','ambiguous','unknown')) {
                throw 'candidate.invalid_decision'
            }
            # Partial coverage is ALWAYS explicit even if a local window was
            # fully scanned and ZIP structure is consistent.
            $out.status='partial';$out.decision=[string]$scan.decision
            $out.scanIncomplete=$true
            $out.candidateDefinitions=@($safe.ToArray())
            $out.candidateCount=$safe.Count
            $m.candidateCount=$safe.Count
            $m.stopCode='candidate.unscanned_source_unknown'
            $out.warnings=@($m.stopCode)
        }
    }catch{
        # Fail-closed, static reason code: never log exception strings which
        # could contain a caller path, raw bytes, private filename or content.
        $out.status='partial';$out.decision='incomplete'
        $out.candidateDefinitions=@();$out.candidateCount=0
        $m.candidateCount=0;$m.stopCode='candidate.source_or_scanner_error'
        $out.warnings=@($m.stopCode)
    }finally{
        $timer.Stop()
        $m.elapsedMilliseconds=[long]$timer.ElapsedMilliseconds
        if($null -ne $meter){
            $m.sourceReturnedBytes=[long]$meter.ReturnedBytes
            $m.sourceUniqueReturnedBytes=[long]$meter.UniqueReturnedBytes
            $m.sourceRepeatedReturnedBytes=[long]($meter.ReturnedBytes-$meter.UniqueReturnedBytes)
            $m.sourceReadCalls=[int]$meter.ReadCalls
            $m.successfulReadCalls=[int]$meter.PositiveReadCalls
            $m.zeroByteReadCalls=[int]$meter.ZeroByteReadCalls
            $m.sourceObservedReadIntervals=[int]$meter.ObservationCount
            if($meter.RefusedBudget){
                $out.status='partial';$out.decision='incomplete'
                $out.candidateDefinitions=@();$out.candidateCount=0
                $m.candidateCount=0;$m.stopCode='candidate.meter_budget_refused'
                $out.warnings=@($m.stopCode)
            }
            $meter.Dispose()
        }
    }
    return [pscustomobject]$out
}
Export-ModuleMember -Function Get-ChappyCarvingCandidateEvidenceV1
