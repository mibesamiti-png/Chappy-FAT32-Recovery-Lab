#Requires -Version 5.1
# A R7 negative-control regression: only synthetic bytes and A-metered reads.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-Chappy3DDamagedFixture.ps1')
. (Join-Path $PSScriptRoot 'helpers\Resolve-A3DReadEvidence.ps1')

function Assert-A7Claim([bool]$Success,[string]$Why){
    if(-not $Success){throw "A7_CLAIM_FAIL: $Why"}
}
$fixture=New-ChappyA3DDamagedFixture -Seed 202611 -Case M00
$before=Get-A3DSha256 $fixture.image
$source='synthetic_m00_stream_A_1'
$candidate='3mf:256+64,512+16'
$extent=@(
    [pscustomobject]@{offsetBytes=[long]256;lengthBytes=[long]64},
    [pscustomobject]@{offsetBytes=[long]512;lengthBytes=[long]16}
)
$memory=[IO.MemoryStream]::new($fixture.image,$false)
$events=New-Object System.Collections.ArrayList
function Add-A7PhysicalEvent {
    param([string]$Id,[long]$At,[int]$Count,[string]$Consumer,
          [string]$Purpose,[string]$Candidate,[string]$Source)
    [void]$memory.Seek($At,[IO.SeekOrigin]::Begin)
    [byte[]]$buf=[byte[]]::new($Count)
    $got=$memory.Read($buf,0,$Count)
    Assert-A7Claim ($got -eq $Count -and -not $memory.CanWrite) 'strict_real_memory_read'
    [void]$events.Add([pscustomobject]@{
        evidenceId=$Id;sourceToken=$Source;consumer=$Consumer
        purpose=$Purpose;candidateId=$Candidate
        offsetBytes=$At;returnedBytes=$got
    })
}
try{
    Add-A7PhysicalEvent 'A001' 256 64 'carving' 'candidate_validation' $candidate $source
    Add-A7PhysicalEvent 'A002' 512 16 'carving' 'candidate_validation' $candidate $source
    Add-A7PhysicalEvent 'A003' 512 16 'carving' 'candidate_validation' $candidate $source
    Add-A7PhysicalEvent 'S001' 256 64 'carving' 'scan' $candidate $source
    Add-A7PhysicalEvent 'X001' 512 16 'carving' 'candidate_validation' $candidate 'synthetic_other_stream'
    $base=@{
        ImageLengthBytes=[long]$fixture.image.Length
        SourceToken=$source
        CandidateId=$candidate
        CandidateExtents=$extent
        MeterEvents=@($events.ToArray())
        MaxPhysicalReadBytes=200L
    }
    $full=Resolve-A3DReadEvidence @base -ClaimedEventIds @('A001','A002')
    Assert-A7Claim ($full.status -ceq 'source_observed' -and
        $full.candidateReadBytes -eq 80 -and
        $full.sourceActualReadBytes -eq 160 -and
        $full.originalIdentity -ceq 'unknown' -and
        $full.integrityScope -ceq 'source_read_coverage_only_not_original_integrity') 'full_actual_metered_read_is_not_original_integrity'

    $duplicate=Resolve-A3DReadEvidence @base -ClaimedEventIds @('A001','A002','A003')
    Assert-A7Claim ($duplicate.status -ceq 'source_observed' -and
        $duplicate.candidateReadBytes -eq 80) 'duplicate_range_does_not_inflate_covered_bytes'

    $noReceipt=Resolve-A3DReadEvidence @base -ClaimedEventIds @()
    Assert-A7Claim ($noReceipt.status -ceq 'unattributed' -and
        $noReceipt.reasons -contains 'origin.no_candidate_specific_receipt') 'aggregate_reads_cannot_claim_specific_file_validation'

    $scan=Resolve-A3DReadEvidence @base -ClaimedEventIds @('S001')
    Assert-A7Claim ($scan.status -ceq 'unattributed' -and
        $scan.candidateReadBytes -eq 0 -and
        $scan.reasons -contains 'origin.not_candidate_validation') 'full_window_scan_is_not_candidate_validation'

    $crossSource=Resolve-A3DReadEvidence @base -ClaimedEventIds @('A001','X001')
    Assert-A7Claim ($crossSource.status -ceq 'unattributed' -and
        $crossSource.reasons -contains 'origin.wrong_source') 'other_image_source_cannot_complete_extent'

    $wrongCandidate=$base.Clone()
    $wrongCandidate.CandidateId='3mf:512+16,256+64'
    $order=Resolve-A3DReadEvidence @wrongCandidate -ClaimedEventIds @('A001','A002')
    Assert-A7Claim ($order.status -ceq 'unattributed' -and
        $order.reasons -contains 'origin.not_candidate_validation') 'reversed_fragment_order_requires_distinct_candidate_receipts'

    $partial=Resolve-A3DReadEvidence @base -ClaimedEventIds @('A001')
    Assert-A7Claim ($partial.status -ceq 'unattributed' -and
        $partial.candidateReadBytes -eq 64 -and
        $partial.reasons -contains 'coverage.candidate_bytes_not_fully_read') 'partial_fragment_preserved_as_unknown'

    $ghost=Resolve-A3DReadEvidence @base -ClaimedEventIds @('A001','F999')
    Assert-A7Claim ($ghost.status -ceq 'unattributed' -and
        $ghost.reasons -contains 'origin.event_not_observed') 'self_reported_ghost_event_rejected'

    $repeatClaim=Resolve-A3DReadEvidence @base -ClaimedEventIds @('A001','A001','A002')
    Assert-A7Claim ($repeatClaim.status -ceq 'unattributed' -and
        $repeatClaim.candidateReadBytes -eq 80 -and
        $repeatClaim.reasons -contains 'origin.duplicate_claim') 'replayed_receipt_not_extra_confidence'

    $low=$base.Clone();$low.MaxPhysicalReadBytes=120L
    $exhausted=Resolve-A3DReadEvidence @low -ClaimedEventIds @('A001','A002')
    Assert-A7Claim ($exhausted.status -ceq 'unattributed' -and
        $exhausted.reasons -contains 'budget.physical_read_limit') 'global_actual_reads_including_rereads_budgeted'

    $bad=$base.Clone()
    $bad.CandidateExtents=@([pscustomobject]@{offsetBytes=[long]$fixture.image.Length;lengthBytes=[long]1})
    $caught=$false
    try{$null=Resolve-A3DReadEvidence @bad -ClaimedEventIds @('A001')}catch{$caught=$true}
    Assert-A7Claim $caught 'outside_image_extent_rejected'

    $bad=$base.Clone();$bad.MeterEvents=@($events.ToArray())+@($events[0])
    $caught=$false
    try{$null=Resolve-A3DReadEvidence @bad -ClaimedEventIds @('A001')}catch{$caught=$true}
    Assert-A7Claim $caught 'forged_duplicate_meter_event_id_rejected'

    Assert-A7Claim ((Get-A3DSha256 $fixture.image) -ceq $before) 'source_sha_unchanged'
    Write-Host ('A R7 synthetic receipts actual={0} covered={1} status={2} distinctEvidence=2; source nonwritable; original=unknown.' -f
        $full.sourceActualReadBytes,$full.candidateReadBytes,$full.status)
}finally{
    $memory.Dispose()
}
Write-Host 'PASS: A R7 synthetic candidate receipt attribution rejects scans, other sources, ghost/replayed events, partial coverage and quota excess.'
