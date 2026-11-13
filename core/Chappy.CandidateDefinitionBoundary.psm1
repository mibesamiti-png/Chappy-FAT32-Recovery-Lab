#Requires -Version 5.1
# Team A / R7 A7-02 — declared candidate identity boundary, not authenticity.
# Pure in-memory metadata normalization. Does not read any stream or export.
Set-StrictMode -Version Latest

function Resolve-ChappyCandidateDefinitionBoundary {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory)][ValidateRange(1,100MB)][long]$ImageLengthBytes,
        [Parameter(Mandatory)][string]$SourceToken,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Proposals
    )
    if([string]::IsNullOrWhiteSpace($SourceToken) -or $SourceToken.Length -gt 64 -or
       $Proposals.Count -gt 32) {
        throw 'A7 candidate-definition source/proposal limits'
    }
    $groups=[System.Collections.Generic.Dictionary[string,object]]::new(
        [StringComparer]::Ordinal)
    $total=0
    foreach($p in $Proposals) {
        if($null -eq $p -or
           $null -eq $p.PSObject.Properties['candidateId'] -or
           $null -eq $p.PSObject.Properties['format'] -or
           $null -eq $p.PSObject.Properties['sourceToken'] -or
           $null -eq $p.PSObject.Properties['extents']) {
            throw 'A7 candidate definition requires explicit fields'
        }
        $id=[string]$p.candidateId
        $format=[string]$p.format
        $source=[string]$p.sourceToken
        if([string]::IsNullOrWhiteSpace($id) -or $id.Length -gt 128 -or
           $format -cnotin @('3mf','zip','stl','stl_ascii','stl_binary','gcode','unknown') -or
           [string]::IsNullOrWhiteSpace($source) -or $source.Length -gt 64) {
            throw 'A7 candidate definition invalid format/id/source'
        }
        [object[]]$raw=@($p.extents)
        if($raw.Count -lt 1 -or $raw.Count -gt 4) {
            throw 'A7 candidate ordered extent count outside limits'
        }
        $normalized=New-Object 'System.Collections.Generic.List[object]'
        $spans=New-Object 'System.Collections.Generic.List[string]'
        foreach($e in $raw) {
            if($null -eq $e -or
               $null -eq $e.PSObject.Properties['offsetBytes'] -or
               $null -eq $e.PSObject.Properties['lengthBytes'] -or
               ($e.offsetBytes -isnot [int] -and $e.offsetBytes -isnot [long]) -or
               ($e.lengthBytes -isnot [int] -and $e.lengthBytes -isnot [long])) {
                throw 'A7 candidate extent must contain numeric physical offsets'
            }
            [long]$at=$e.offsetBytes
            [long]$len=$e.lengthBytes
            if($at -lt 0 -or $len -le 0 -or $len -gt $ImageLengthBytes -or
               $at -gt $ImageLengthBytes-$len) {
                throw 'A7 candidate extent outside declared synthetic image'
            }
            $normalized.Add([pscustomobject]@{offsetBytes=$at;lengthBytes=$len})
            $spans.Add(('{0}+{1}' -f $at,$len))
        }
        $last=-1L
        foreach($e in @($normalized.ToArray() | Sort-Object offsetBytes)) {
            if([long]$e.offsetBytes -lt $last) {
                throw 'A7 candidate overlapping ordered physical extents'
            }
            $last=[long]$e.offsetBytes+[long]$e.lengthBytes
        }
        # Ordering is intentionally preserved: 3MF fragment A+B != B+A.
        $canonical=$format+':'+($spans.ToArray() -join ',')
        $signature=$source+'|'+$canonical
        if(-not $groups.ContainsKey($id)) {
            $groups.Add($id,[pscustomobject]@{
                candidateId=$id
                entries=(New-Object System.Collections.ArrayList)
                signatures=[System.Collections.Generic.HashSet[string]]::new(
                    [StringComparer]::Ordinal)
            })
        }
        $group=$groups[$id]
        [void]$group.signatures.Add($signature)
        [void]$group.entries.Add([pscustomobject]@{
            candidateId=$id
            sourceToken=$source
            format=$format
            canonicalId=$canonical
            orderedExtents=@($normalized.ToArray())
        })
        $total++
    }

    # One canonical ordered physical definition must never certify multiple
    # different candidate IDs without explicit ambiguity disposition.
    $owners=[System.Collections.Generic.Dictionary[string,object]]::new(
        [StringComparer]::Ordinal)
    foreach($id in $groups.Keys) {
        foreach($entry in @($groups[$id].entries)) {
            $sig=[string]$entry.sourceToken+'|'+[string]$entry.canonicalId
            if(-not $owners.ContainsKey($sig)) {
                $owners.Add($sig,[System.Collections.Generic.HashSet[string]]::new(
                    [StringComparer]::Ordinal))
            }
            [void]$owners[$sig].Add($id)
        }
    }
    $result=New-Object 'System.Collections.Generic.List[object]'
    $conflicts=0
    foreach($id in @($groups.Keys | Sort-Object)) {
        $g=$groups[$id]
        $entries=@($g.entries)
        $first=$entries[0]
        $reasons=New-Object 'System.Collections.Generic.List[string]'
        if($g.signatures.Count -ne 1) {
            $reasons.Add('identity.same_id_conflicting_definitions')
        }
        if([string]$first.sourceToken -cne $SourceToken -or
           @($entries | Where-Object {$_.sourceToken -cne $SourceToken}).Count -gt 0) {
            $reasons.Add('identity.wrong_source_token')
        }
        if(@($entries | Where-Object {$_.candidateId -cne $_.canonicalId}).Count -gt 0) {
            $reasons.Add('identity.id_not_bound_to_ordered_extents')
        }
        foreach($entry in $entries) {
            $sig=[string]$entry.sourceToken+'|'+[string]$entry.canonicalId
            if($owners[$sig].Count -gt 1) {
                $reasons.Add('identity.same_extents_competing_ids')
                break
            }
        }
        $bad=@($reasons.ToArray() | Sort-Object -Unique)
        if($bad.Count -gt 0){$conflicts++}
        $result.Add([pscustomobject]@{
            candidateId=$id
            sourceToken=$SourceToken
            canonicalId=$first.canonicalId
            format=$first.format
            orderedExtents=@($first.orderedExtents)
            definitionCount=$entries.Count
            distinctDefinitionCount=$g.signatures.Count
            status=$(if($bad.Count -gt 0){'conflicting'}else{'consistent_definition_only'})
            independentPhysicalReceiptEligible=($bad.Count -eq 0)
            sourceAuthority='caller_supplied_unverified_not_A_meter'
            readEvidenceStatus='unattributed_pending_A_meter_receipt'
            originalIdentity='unknown'
            reasons=$bad
        })
    }
    return [pscustomobject]@{
        schemaVersion='a7_candidate_definition_v1'
        team='A'
        status=$(if($conflicts -gt 0){'conflicting'}elseif($total -eq 0){'empty'}else{'partial'})
        originalIdentity='unknown'
        sourceAuthority='caller_supplied_unverified_not_A_meter'
        proposalCount=$total
        uniqueCandidateIds=$result.Count
        conflictingCandidateIds=$conflicts
        candidates=@($result.ToArray())
    }
}
Export-ModuleMember -Function Resolve-ChappyCandidateDefinitionBoundary
