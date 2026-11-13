#Requires -Version 5.1
# A7-02: exercise ACTUAL C-discovered synthetic candidate then adversarial
# ID/extent/source definition claims, under independent physical source reads.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-Chappy3DDamagedFixture.ps1')
. (Join-Path $PSScriptRoot 'helpers\Resolve-A3DReadEvidence.ps1')
Import-Module (Join-Path $root 'core\Chappy.CandidateDefinitionBoundary.psm1') -Force
Import-Module (Join-Path $root 'modules\carving\Chappy.Carving.psm1') -Force
. (Join-Path $root 'modules\carving\tests\R5M01PairResearch.ps1')
function Assert-A7Definition([bool]$Okay,[string]$Reason) {
    if(-not $Okay){throw ('A7_DEFINITION_BINDING_FAIL: '+$Reason)}
}
function New-A7Definition([string]$Id,[object[]]$Ordered,[string]$Token,[string]$Format='3mf') {
    return [pscustomobject]@{
        candidateId=$Id;sourceToken=$Token;format=$Format;extents=@($Ordered)
    }
}
function Get-A7CanonicalId([string]$Format,[object[]]$Ordered) {
    return ($Format+':'+((@($Ordered | ForEach-Object {
        '{0}+{1}' -f [long]$_.offsetBytes,[long]$_.lengthBytes
    })) -join ','))
}
$fixture=New-ChappyA3DDamagedFixture -Seed 202611 -Case M00
[byte[]]$image=$fixture.image
$sha=Get-A3DSha256 $image
$raw=[IO.MemoryStream]::new($image,$false)
$token='A7_actual_C_discovery_202611'
try{
    # Candidate is discovered by actual existing C research scanner. The
    # independent artificial fixture oracle is NOT provided to C.
    $scan=Test-CM01FiniteZipPairs -Source $raw
    $items=@($scan.items)
    Assert-A7Definition ($scan.status -ceq 'ok' -and $items.Count -eq 1 -and
        -not $raw.CanWrite) 'C_real_two_piece_3mf_discovery'
    $candidate=$items[0]
    $spans=@($candidate.sourceSpans)
    Assert-A7Definition ($spans.Count -eq 2) 'real_C_ordered_two_piece_extents'
    $id=Get-A7CanonicalId '3mf' $spans
    $good=New-A7Definition $id $spans $token
    $valid=Resolve-ChappyCandidateDefinitionBoundary -ImageLengthBytes ([long]$image.Length) -SourceToken $token -Proposals @($good)
    Assert-A7Definition ($valid.status -ceq 'partial' -and $valid.uniqueCandidateIds -eq 1 -and
        $valid.conflictingCandidateIds -eq 0 -and
        $valid.candidates[0].status -ceq 'consistent_definition_only' -and
        $valid.candidates[0].independentPhysicalReceiptEligible -and
        $valid.candidates[0].originalIdentity -ceq 'unknown' -and
        $valid.candidates[0].readEvidenceStatus -ceq 'unattributed_pending_A_meter_receipt') 'C_canonical_definition_not_original_proof'
    $dup=Resolve-ChappyCandidateDefinitionBoundary -ImageLengthBytes ([long]$image.Length) -SourceToken $token -Proposals @($good,$good)
    Assert-A7Definition ($dup.uniqueCandidateIds -eq 1 -and
        $dup.candidates[0].definitionCount -eq 2 -and
        $dup.candidates[0].distinctDefinitionCount -eq 1 -and
        $dup.conflictingCandidateIds -eq 0) 'duplicate_C_definition_does_not_double_count'

    $changed=@(
        [pscustomobject]@{offsetBytes=[long]$spans[0].offsetBytes;lengthBytes=([long]$spans[0].lengthBytes-1L)},
        [pscustomobject]@{offsetBytes=[long]$spans[1].offsetBytes;lengthBytes=[long]$spans[1].lengthBytes}
    )
    $bad=New-A7Definition $id $changed $token
    # A actual artificial-source reads cover the full original variant.
    # The old purely range-based receipt resolver can legitimately report
    # source coverage for BOTH extents; that is not a proof that the shared
    # candidate ID refers to one unique physical reconstruction.
    $events=New-Object 'System.Collections.Generic.List[object]'
    foreach($e in $spans) {
        [void]$raw.Seek([long]$e.offsetBytes,[IO.SeekOrigin]::Begin)
        [byte[]]$data=[byte[]]::new([int]$e.lengthBytes)
        $got=$raw.Read($data,0,$data.Length)
        Assert-A7Definition ($got -eq $data.Length) 'A_test_read_actual_physical_source'
        $events.Add([pscustomobject]@{
            evidenceId=('{0}#{1:D4}' -f $token,$events.Count)
            sourceToken=$token;consumer='carving';purpose='candidate_validation'
            candidateId=$id;offsetBytes=[long]$e.offsetBytes;returnedBytes=$got
        })
    }
    $claimed=@($events.ToArray()|ForEach-Object {$_.evidenceId})
    $physical=0L
    foreach($ev in $events){$physical+=[long]$ev.returnedBytes}
    $args=@{
        ImageLengthBytes=[long]$image.Length;SourceToken=$token
        CandidateId=$id;MeterEvents=@($events.ToArray())
        ClaimedEventIds=$claimed;MaxPhysicalReadBytes=120000L
    }
    $r1=Resolve-A3DReadEvidence @args -CandidateExtents $spans
    $r2=Resolve-A3DReadEvidence @args -CandidateExtents $changed
    Assert-A7Definition ($r1.status -ceq 'source_observed' -and
        $r2.status -ceq 'source_observed' -and
        $r1.originalIdentity -ceq 'unknown' -and
        $r2.originalIdentity -ceq 'unknown' -and
        $r1.sourceActualReadBytes -eq $physical) 'both_have_physical_coverage_but_not_same_definition'
    $clash=Resolve-ChappyCandidateDefinitionBoundary -ImageLengthBytes ([long]$image.Length) -SourceToken $token -Proposals @($good,$bad)
    Assert-A7Definition ($clash.status -ceq 'conflicting' -and
        $clash.conflictingCandidateIds -eq 1 -and
        -not $clash.candidates[0].independentPhysicalReceiptEligible -and
        $clash.candidates[0].reasons -contains 'identity.same_id_conflicting_definitions' -and
        $clash.candidates[0].reasons -contains 'identity.id_not_bound_to_ordered_extents') 'same_id_different_extent_must_not_inherit_physical_coverage'

    $reversed=@($spans[1],$spans[0])
    $reverseId=Get-A7CanonicalId '3mf' $reversed
    $reverse=New-A7Definition $reverseId $reversed $token
    $distinct=Resolve-ChappyCandidateDefinitionBoundary -ImageLengthBytes ([long]$image.Length) -SourceToken $token -Proposals @($good,$reverse)
    Assert-A7Definition ($distinct.conflictingCandidateIds -eq 0 -and
        $distinct.uniqueCandidateIds -eq 2 -and
        $reverseId -cne $id -and
        $distinct.candidates[0].readEvidenceStatus -ceq 'unattributed_pending_A_meter_receipt') 'same_physical_slices_reverse_order_separate_hypotheses'

    $alias=New-A7Definition ($id+'_replayed') $spans $token
    $ambiguous=Resolve-ChappyCandidateDefinitionBoundary -ImageLengthBytes ([long]$image.Length) -SourceToken $token -Proposals @($good,$alias)
    Assert-A7Definition ($ambiguous.uniqueCandidateIds -eq 2 -and
        $ambiguous.conflictingCandidateIds -eq 2 -and
        @($ambiguous.candidates|Where-Object {
            $_.reasons -contains 'identity.same_extents_competing_ids'
        }).Count -eq 2) 'different_ids_same_spans_cannot_fake_two_original_files'

    $other=New-A7Definition $id $spans 'A7_different_generated_source'
    $mixed=Resolve-ChappyCandidateDefinitionBoundary -ImageLengthBytes ([long]$image.Length) -SourceToken $token -Proposals @($good,$other)
    Assert-A7Definition ($mixed.conflictingCandidateIds -eq 1 -and
        $mixed.candidates[0].reasons -contains 'identity.wrong_source_token') 'source_token_scope_must_match'
    foreach($invalid in @(
        (New-A7Definition $id @([pscustomobject]@{offsetBytes=[long]$image.Length;lengthBytes=1L}) $token),
        (New-A7Definition $id @(
            [pscustomobject]@{offsetBytes=256L;lengthBytes=80L},
            [pscustomobject]@{offsetBytes=260L;lengthBytes=80L}
        ) $token)
    )) {
        $refused=$false
        try{$null=Resolve-ChappyCandidateDefinitionBoundary -ImageLengthBytes ([long]$image.Length) -SourceToken $token -Proposals @($invalid)}
        catch{$refused=$true}
        Assert-A7Definition $refused 'out_of_range_or_overlapping_extents_rejected'
    }
    $tooMany=@(for($i=0;$i -lt 33;$i++){$good})
    $cap=$false
    try{$null=Resolve-ChappyCandidateDefinitionBoundary -ImageLengthBytes ([long]$image.Length) -SourceToken $token -Proposals $tooMany}
    catch{$cap=$true}
    Assert-A7Definition $cap 'bounded_32_candidate_definitions'
    Assert-A7Definition ((Get-A3DSha256 $image) -ceq $sha -and -not $raw.CanWrite) 'generated_original_unchanged'
    Write-Host ('PASS: A7-02 real C candidate definition collision, actual A synthetic reads={0}B, same-id mismatch denied, reverse ordering separate, cross-source/alias/invalid/cap rejected, originalIdentity=UNKNOWN' -f $physical)
}finally{$raw.Dispose()}
