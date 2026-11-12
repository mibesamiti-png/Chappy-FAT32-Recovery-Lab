#Requires -Version 5.1
# Team A: bounded real C validation of competing synthetic 3MF candidates.
# Uses only locally generated nonwritable memory sources. Never accepts IMG paths.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Reuse (and rerun) the A-owned live validator/meter baseline in an isolated
# PowerShell process, then add independently exercised adversarial scenarios.
. (Join-Path $PSScriptRoot 'Test-A3DLiveCCandidateReceipts.ps1')

function Assert-A7Multiple([bool]$Condition,[string]$Reason) {
    if(-not $Condition){throw ('A7_MULTI_FAIL: '+$Reason)}
}
function Get-A7CandidateKey([object[]]$spans) {
    return ('3mf:{0}+{1},{2}+{3}' -f
        $spans[0].offsetBytes,$spans[0].lengthBytes,
        $spans[1].offsetBytes,$spans[1].lengthBytes)
}
$a7mFixture=New-ChappyA3DDamagedFixture -Seed 202611 -Case M00
$a7mBefore=Get-A3DSha256 $a7mFixture.image
$a7mRaw=[IO.MemoryStream]::new($a7mFixture.image,$false)
$meterToken='A7_multi_generated_source'
$a7mMeter=[ChappyA7CandidateMeter]::new($a7mRaw,$meterToken,120000L)
try {
    $a7mMeter.BeginPhase('scan','')
    $a7mScout=Test-CM01FiniteZipPairs -Source $a7mMeter
    Assert-A7Multiple ($a7mScout.status -ceq 'ok' -and @($a7mScout.items).Count -eq 1) 'real_C_discovers_one_test_case_candidate'
    $a7mBaseCandidate=@($a7mScout.items)[0]
    $a7mSpans=@($a7mBaseCandidate.sourceSpans)
    $a7mKey=Get-A7CandidateKey $a7mSpans
    $a7mScoutBytes=$a7mMeter.BytesRead
    $a7mMeter.BeginPhase('candidate_validation',$a7mKey)
    $a7mPass=Test-CObservedCandidateValidation -Source $a7mMeter -Candidate $a7mBaseCandidate
    Assert-A7Multiple ($a7mPass.status -ceq 'format_consistent') 'first_real_C_3mf_validates_structure'
    $a7mEventsAfterFirst=@($a7mMeter.GetEvents())
    $a7mIdsOne=@($a7mEventsAfterFirst|Where-Object {
        $_.Purpose -ceq 'candidate_validation' -and $_.CandidateId -ceq $a7mKey
    }|ForEach-Object {$_.EvidenceId})
    $a7mExtentBytes=[long]$a7mSpans[0].lengthBytes+[long]$a7mSpans[1].lengthBytes
    Assert-A7Multiple ($a7mPass.metrics.sourceBytesRead -eq $a7mExtentBytes -and $a7mIdsOne.Count -eq 2) 'first_candidate_exact_physical_reads'

    # Deliberately competing ordered hypothesis: same two observed physical
    # slices, reversed assembly order. It must NOT inherit the first candidate's
    # CRC conclusion or meter receipts, even though both slices get re-read.
    $a7mReversedSpans=@($a7mSpans[1],$a7mSpans[0])
    $a7mWrongKey=Get-A7CandidateKey $a7mReversedSpans
    $a7mReverse=[pscustomobject]@{sourceSpans=$a7mReversedSpans}
    $a7mMeter.BeginPhase('candidate_validation',$a7mWrongKey)
    $a7mReverseResult=Test-CObservedCandidateValidation -Source $a7mMeter -Candidate $a7mReverse
    Assert-A7Multiple ($a7mReverseResult.status -ceq 'format_rejected' -and
        $a7mReverseResult.originalIdentity -ceq 'unknown') 'reverse_bytes_read_but_format_rejected'
    $a7mEvents=@($a7mMeter.GetEvents())
    $a7mIdsTwo=@($a7mEvents|Where-Object {
        $_.Purpose -ceq 'candidate_validation' -and $_.CandidateId -ceq $a7mWrongKey
    }|ForEach-Object {$_.EvidenceId})
    Assert-A7Multiple ($a7mIdsTwo.Count -eq 2 -and
        @($a7mIdsOne | Where-Object {$a7mIdsTwo -ccontains $_}).Count -eq 0) 'distinct_candidate_receipts'
    $a7mArgs=@{
        ImageLengthBytes=[long]$a7mFixture.image.Length
        SourceToken=$meterToken
        MeterEvents=$a7mEvents
        MaxPhysicalReadBytes=120000L
    }
    $a7mFirst=Resolve-A3DReadEvidence @a7mArgs -CandidateId $a7mKey -CandidateExtents $a7mSpans -ClaimedEventIds $a7mIdsOne
    $a7mSecond=Resolve-A3DReadEvidence @a7mArgs -CandidateId $a7mWrongKey -CandidateExtents $a7mReversedSpans -ClaimedEventIds $a7mIdsTwo
    Assert-A7Multiple ($a7mFirst.status -ceq 'source_observed' -and
        $a7mSecond.status -ceq 'source_observed' -and
        $a7mFirst.candidateReadBytes -eq $a7mExtentBytes -and
        $a7mSecond.candidateReadBytes -eq $a7mExtentBytes -and
        $a7mFirst.originalIdentity -ceq 'unknown' -and
        $a7mSecond.originalIdentity -ceq 'unknown') 'both_candidates_read_but_not_authenticated'
    $a7mCross=Resolve-A3DReadEvidence @a7mArgs -CandidateId $a7mKey -CandidateExtents $a7mSpans -ClaimedEventIds $a7mIdsTwo
    Assert-A7Multiple ($a7mCross.status -ceq 'unattributed' -and
        $a7mCross.candidateReadBytes -eq 0 -and
        $a7mCross.reasons -contains 'origin.not_candidate_validation') 'competing_receipts_not_interchangeable'
    $a7mPhysicalExpected=$a7mScoutBytes+2*$a7mExtentBytes
    Assert-A7Multiple ($a7mMeter.BytesRead -eq $a7mPhysicalExpected -and
        $a7mMeter.BytesRead -le $a7mMeter.Maximum -and
        -not $a7mMeter.CanWrite) 'shared_budget_counts_both_physical_validations'

    # Phase abuse: C does a real validation but A deliberately calls it a
    # broad scan. Thus no candidate-validation receipts exist for this pass.
    $a7mMeter.BeginPhase('scan','')
    $a7mScanValidation=Test-CObservedCandidateValidation -Source $a7mMeter -Candidate $a7mBaseCandidate
    Assert-A7Multiple ($a7mScanValidation.status -ceq 'format_consistent') 'phase_abuse_actual_structural_scan'
    $a7mUpdated=@($a7mMeter.GetEvents())
    $a7mScanIds=@($a7mUpdated|Where-Object {
        $_.Purpose -ceq 'scan' -and $_.OffsetBytes -eq [long]$a7mSpans[0].offsetBytes
    }|Select-Object -Last 1|ForEach-Object {$_.EvidenceId})
    $a7mScanCannotProve=Resolve-A3DReadEvidence -ImageLengthBytes ([long]$a7mFixture.image.Length) -SourceToken $meterToken -CandidateId $a7mKey -CandidateExtents $a7mSpans -MeterEvents $a7mUpdated -ClaimedEventIds $a7mScanIds -MaxPhysicalReadBytes 120000
    Assert-A7Multiple ($a7mScanCannotProve.status -ceq 'unattributed' -and
        $a7mScanCannotProve.reasons -contains 'origin.not_candidate_validation') 'phase_not_validated_without_A_label'
    Assert-A7Multiple ((Get-A3DSha256 $a7mFixture.image) -ceq $a7mBefore) 'multi_source_unchanged'
    Write-Host ('A7 MULTI actual={0} first_structural={1} reversed_structural={2} first_source={3} reverse_source={4} originalIdentity=unknown' -f
        $a7mMeter.BytesRead,$a7mPass.status,$a7mReverseResult.status,$a7mFirst.status,$a7mSecond.status)
}finally{$a7mRaw.Dispose()}

# Deliberate shared-budget interruption: 300 real scout bytes leave only 724
# bytes of a 1024-byte A quota. First 512-byte candidate slice completes;
# second slice is refused. This is not an EOF or successful reconstruction.
$a7mLimitedRaw=[IO.MemoryStream]::new($a7mFixture.image,$false)
$a7mLimitedToken='A7_multi_budget_cut'
$a7mLimited=[ChappyA7CandidateMeter]::new($a7mLimitedRaw,$a7mLimitedToken,1024L)
try{
    $a7mLimited.BeginPhase('scan','')
    [byte[]]$a7mPrefill=[byte[]]::new(300)
    [void]$a7mLimited.Seek(0L,[IO.SeekOrigin]::Begin)
    $a7mPreRead=$a7mLimited.Read($a7mPrefill,0,300)
    Assert-A7Multiple ($a7mPreRead -eq 300) 'actual_300_byte_scout_budget'
    $a7mLimited.BeginPhase('candidate_validation',$a7mKey)
    $a7mPartial=Test-CObservedCandidateValidation -Source $a7mLimited -Candidate $a7mBaseCandidate
    Assert-A7Multiple ($a7mPartial.status -ceq 'partial' -and
        $a7mPartial.decision -ceq 'incomplete' -and
        $a7mPartial.metrics.sourceBytesRead -eq [long]$a7mSpans[0].lengthBytes -and
        $a7mLimited.BytesRead -eq 300L+[long]$a7mSpans[0].lengthBytes) 'interrupted_second_fragment_preserves_partial'
    $a7mLimitedEvents=@($a7mLimited.GetEvents())
    $a7mLimitedIds=@($a7mLimitedEvents|Where-Object {$_.Purpose -ceq 'candidate_validation'}|ForEach-Object {$_.EvidenceId})
    $a7mUnattributed=Resolve-A3DReadEvidence -ImageLengthBytes ([long]$a7mFixture.image.Length) -SourceToken $a7mLimitedToken -CandidateId $a7mKey -CandidateExtents $a7mSpans -MeterEvents $a7mLimitedEvents -ClaimedEventIds $a7mLimitedIds -MaxPhysicalReadBytes 1024L
    Assert-A7Multiple ($a7mUnattributed.status -ceq 'unattributed' -and
        $a7mUnattributed.reasons -contains 'coverage.candidate_bytes_not_fully_read' -and
        $a7mUnattributed.originalIdentity -ceq 'unknown' -and
        -not $a7mLimited.CanWrite) 'budget_interruption_cannot_promote_partial_candidate'
    Assert-A7Multiple ((Get-A3DSha256 $a7mFixture.image) -ceq $a7mBefore) 'budget_source_unchanged'
    Write-Host ('A7 CUT sourceBytes={0} candidateBytes={1} Cstatus={2} Astatus={3}' -f
        $a7mLimited.BytesRead,$a7mPartial.metrics.sourceBytesRead,$a7mPartial.status,$a7mUnattributed.status)
}finally{$a7mLimitedRaw.Dispose()}
Write-Host 'PASS: A7 live competing ordered candidates and phase/quota negative controls on artificial nonwritable streams.'
