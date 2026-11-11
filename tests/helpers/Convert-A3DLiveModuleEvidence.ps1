#Requires -Version 5.1

function Convert-A3DLiveModuleEvidence {
    # Synthetic test adapter for the module schemas used by the shared baseline.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateRange(1, 100MB)][long]$ImageLengthBytes,
        [Parameter(Mandatory)]$Directory,
        [Parameter(Mandatory)]$Carving,
        [Parameter(Mandatory)]$Mirrors
    )
    if ($Directory.team -cne 'B' -or $Carving.team -cne 'C' -or $Mirrors.team -cne 'D' -or
        $Directory.schemaVersion -cne '1' -or $Carving.schemaVersion -cne '1' -or
        $Mirrors.schemaVersion -cne '1') {
        throw 'Unsupported synthetic module result schema'
    }
    if ($Directory.items.Count -gt 16 -or $Carving.items.Count -gt 16 -or $Mirrors.items.Count -gt 1) {
        throw 'Synthetic module result budget exceeded'
    }

    $signatureOnly = 0
    $proposals = @(foreach ($item in $Carving.items) {
        if ($item.lengthBytes -eq 0 -and $item.integrityScope -ceq 'signature_only_not_validated') {
            $signatureOnly++
            continue
        }
        $check = switch ($item.confidence) {
            'verified' {
                if ($item.integrityScope -cne 'structural_only_not_original_file_integrity') {
                    throw 'Unsupported verified carving evidence'
                }
                'structurally_valid'
            }
            'partial' { 'partial' }
            'probable' { 'detected' }
            'unknown' { 'unknown' }
            default { throw 'Unsupported carving confidence' }
        }
        # A proposed extent does not describe which bytes the validator read.
        @{
            format = $item.format
            extents = @(@{ offsetBytes = $item.offsetBytes; lengthBytes = $item.lengthBytes })
            check = $check
            observations = @()
        }
    })
    $grouped = Merge-A3DSyntheticEvidence -ImageLengthBytes $ImageLengthBytes -Proposals $proposals

    $directoryRecords = @(foreach ($item in $Directory.items) {
        if (-not $item.isDirectory) {
            [pscustomobject]@{
                recordOffsetBytes = $item.offsetBytes
                startCluster = $item.startCluster
                declaredSizeBytes = $item.sizeBytes
                confidence = $item.confidence
            }
        }
    })
    # Keep metadata and volume-wide observations separate from C's byte proposals.
    [pscustomobject]@{
        schemaVersion = 'synthetic-live-evidence-1'
        candidates = $grouped.candidates
        signatureOnlyCount = $signatureOnly
        directory = [pscustomobject]@{
            records = $directoryRecords
            scanIncomplete = $Directory.scanIncomplete
            directoryDataBytesRead = $Directory.metrics.bytesRead
        }
        carving = [pscustomobject]@{
            scanIncomplete = $Carving.scanIncomplete
            bytesRead = $Carving.metrics.bytesRead
        }
        mirrors = [pscustomobject]@{
            scanIncomplete = $Mirrors.scanIncomplete
            comparedEntries = $Mirrors.metrics.entriesChecked
            differingEntries = $Mirrors.metrics.differentEntries
            bytesRead = $Mirrors.metrics.bytesRead
        }
    }
}
