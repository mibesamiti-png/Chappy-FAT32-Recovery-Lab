#Requires -Version 5.1

function Merge-A3DSyntheticEvidence {
    # A test-only boundary for normalized observations of one generated image.
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Mandatory)][ValidateRange(1, 100MB)][long]$ImageLengthBytes,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Proposals
    )
    if ($Proposals.Count -gt 32) { throw 'Synthetic proposal budget exceeded' }

    $groups = [ordered]@{}
    foreach ($proposal in $Proposals) {
        if ($proposal.format -cnotin @('3mf', 'zip', 'stl', 'gcode', 'unknown') -or
            $proposal.check -cnotin @('detected', 'structurally_valid', 'partial', 'unknown') -or
            $proposal.extents.Count -lt 1 -or $proposal.extents.Count -gt 4 -or
            $proposal.observations.Count -gt 8) {
            throw 'Invalid synthetic evidence proposal'
        }
        $extents = @(foreach ($extent in $proposal.extents) {
            if (($extent.offsetBytes -isnot [long] -and $extent.offsetBytes -isnot [int]) -or
                ($extent.lengthBytes -isnot [long] -and $extent.lengthBytes -isnot [int]) -or
                $extent.offsetBytes -lt 0 -or $extent.lengthBytes -le 0 -or
                $extent.offsetBytes -gt $ImageLengthBytes - $extent.lengthBytes) {
                throw 'Candidate extent outside synthetic image'
            }
            [pscustomobject]@{ offsetBytes = [long]$extent.offsetBytes; lengthBytes = [long]$extent.lengthBytes }
        })
        $end = -1L
        foreach ($extent in ($extents | Sort-Object offsetBytes)) {
            if ($extent.offsetBytes -lt $end) { throw 'Overlapping candidate extents' }
            $end = $extent.offsetBytes + $extent.lengthBytes
        }
        $key = $proposal.format + ':' + (($extents | ForEach-Object { "$($_.offsetBytes)+$($_.lengthBytes)" }) -join ',')
        if (-not $groups.Contains($key)) {
            $groups[$key] = @{
                format = $proposal.format
                extents = $extents
                checks = [System.Collections.Generic.HashSet[string]]::new()
                origins = [ordered]@{}
            }
        }
        $group = $groups[$key]
        [void]$group.checks.Add($proposal.check)
        foreach ($observation in $proposal.observations) {
            $offset = $observation.offsetBytes
            $length = $observation.lengthBytes
            if (($offset -isnot [long] -and $offset -isnot [int]) -or
                ($length -isnot [long] -and $length -isnot [int]) -or
                $offset -lt 0 -or $length -le 0 -or $offset -gt $ImageLengthBytes - $length -or
                $observation.kind -cnotin @('geometry', 'directory', 'format', 'fat_mirror')) {
                throw 'Invalid synthetic observation'
            }
            $range = "$offset+$length"
            if (-not $group.origins.Contains($range)) {
                $group.origins[$range] = [pscustomobject]@{
                    offsetBytes = [long]$offset
                    lengthBytes = [long]$length
                    kinds = [System.Collections.Generic.HashSet[string]]::new()
                }
            }
            [void]$group.origins[$range].kinds.Add($observation.kind)
        }
    }

    $candidates = @(foreach ($key in ($groups.Keys | Sort-Object)) {
        $group = $groups[$key]
        $end = 0L
        $uniqueBytes = 0L
        $observations = @(foreach ($origin in ($group.origins.Values | Sort-Object offsetBytes, lengthBytes)) {
            $originEnd = $origin.offsetBytes + $origin.lengthBytes
            $uniqueBytes += [Math]::Max(0L, $originEnd - [Math]::Max($end, $origin.offsetBytes))
            $end = [Math]::Max($end, $originEnd)
            [pscustomobject]@{
                offsetBytes = $origin.offsetBytes
                lengthBytes = $origin.lengthBytes
                kinds = @($origin.kinds | Sort-Object)
            }
        })
        [pscustomobject]@{
            candidateId = $key
            format = $group.format
            extents = $group.extents
            checks = @($group.checks | Sort-Object)
            observations = $observations
            uniqueObservationBytes = $uniqueBytes
        }
    })
    [pscustomobject]@{ schemaVersion = 'synthetic-evidence-1'; candidates = $candidates }
}
