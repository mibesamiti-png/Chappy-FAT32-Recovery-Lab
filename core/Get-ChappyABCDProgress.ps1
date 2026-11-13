#Requires -Version 5.1
# Team A: auditable progress parameters from the canonical R4-R7 gate ledger.
# Reads only a repository .md document; never opens/scans any IMG or device.
[CmdletBinding()]
param(
    [string]$LedgerPath='',
    [AllowEmptyString()][string]$LedgerText='',
    [switch]$AsJson
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($LedgerPath -ne '' -and $LedgerText -ne ''){throw 'Supply LedgerPath OR LedgerText, not both'}
if($LedgerText -eq '') {
    if($LedgerPath -eq '') {
        $LedgerPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'docs\ABCD_GATE_LEDGER.md'
    }
    # This is deliberately a FILE TEXT read, not an image/source reader.
    $full=[IO.Path]::GetFullPath($LedgerPath)
    if(-not [IO.File]::Exists($full) -or [IO.Path]::GetExtension($full) -cne '.md'){
        throw 'Gate progress requires a readable .md ledger path'
    }
    $LedgerText=[IO.File]::ReadAllText($full,[Text.Encoding]::UTF8)
}
if($LedgerText.Length -gt 200000 -or $LedgerText.Length -lt 300){
    throw 'Invalid gate evidence ledger length'
}
# Deliberately match the canonical 4-field tabular rows only, not the
# later explanatory tables or old archive text.
$matchPattern='(?m)^\|\s*((?:B4|C5|D6|A7)-\d{2})\s*\|\s*(PASS|PARTIAL|AUDIT_NEEDED|MISSING|BLOCKED)\s*\|'
$matchesFound=[regex]::Matches($LedgerText,$matchPattern)
$map=[System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
foreach($m in $matchesFound){
    $id=$m.Groups[1].Value
    $status=$m.Groups[2].Value
    if($map.ContainsKey($id)){throw ('Duplicate gate row: '+$id)}
    $map.Add($id,$status)
}
$stages=@(
    [pscustomobject]@{Team='B';Stage='R4';Prefix='B4';Count=5;FormalWeight=10},
    [pscustomobject]@{Team='C';Stage='R5';Prefix='C5';Count=6;FormalWeight=15},
    [pscustomobject]@{Team='D';Stage='R6';Prefix='D6';Count=5;FormalWeight=10},
    [pscustomobject]@{Team='A';Stage='R7';Prefix='A7';Count=6;FormalWeight=10}
)
# Formal approval is an EXPLICIT independent Team A original-stage decision,
# never obtained by summing narrow subrow PASS labels. Values total exactly 100.
$formalStageWeights=[ordered]@{
    R0=5;R1=10;R2=12;R3=12;R4=10;R5=15;R6=10;R7=10;R8=9;R9=5;R10=2
}
$explicitAApprovedFormalStages=@('R0','R1','R2','R3','R4','R6')
[long]$allWeight=0L;[long]$officialWeight=0L
$uncreditedWeights=[ordered]@{}
foreach($key in @($formalStageWeights.Keys)) {
    $weight=[long]$formalStageWeights[$key]
    $allWeight+=$weight
    if($key -cin $explicitAApprovedFormalStages){$officialWeight+=$weight}
    else{$uncreditedWeights[$key]=$weight}
}
if($allWeight -ne 100 -or $officialWeight -lt 0 -or $officialWeight -gt 100){
    throw 'Formal original roadmap weights invalid: expected exactly 100'
}
if($explicitAApprovedFormalStages.Count -ne (@($explicitAApprovedFormalStages | Select-Object -Unique).Count)){
    throw 'Duplicate explicitly A-approved original roadmap stage'
}
$expected=0
foreach($stage in $stages){$expected += $stage.Count}
if($map.Count -ne $expected){
    throw ('Expected '+$expected+' distinct formal gate rows; found '+$map.Count)
}
$rows=New-Object 'System.Collections.Generic.List[object]'
foreach($s in $stages){
    $group=@(for($i=1;$i -le $s.Count;$i++){
        $id=('{0}-{1:D2}' -f $s.Prefix,$i)
        if(-not $map.ContainsKey($id)){throw ('Missing required gate row: '+$id)}
        [pscustomobject]@{id=$id;status=$map[$id]}
    })
    $passed=@($group | Where-Object {$_.status -ceq 'PASS'}).Count
    $partial=@($group | Where-Object {$_.status -ceq 'PARTIAL'}).Count
    $audit=@($group | Where-Object {$_.status -ceq 'AUDIT_NEEDED'}).Count
    $blocked=@($group | Where-Object {$_.status -ceq 'BLOCKED'}).Count
    $missing=@($group | Where-Object {$_.status -ceq 'MISSING'}).Count
    $assessed=$s.Count-$audit
    $worked=$passed+$partial
    $unpassed=$s.Count-$passed
    $openGateIds=@($group | Where-Object {$_.status -cne 'PASS'} | ForEach-Object {$_.id})
    $approved=($s.Stage -cin $explicitAApprovedFormalStages)
    $nextId=$(if($openGateIds.Count -gt 0){[string]$openGateIds[0]}else{$null})
    $rows.Add([pscustomobject]@{
        team=$s.Team
        stage=$s.Stage
        officialStageWeight=$s.FormalWeight
        officialStagePassed=$approved
        formalStageState=$(if($approved){'A_ACCEPTED_SYNTHETIC'}else{'NOT_YET_ACCEPTED'})
        creditedFormalWeight=$(if($approved){[int]$s.FormalWeight}else{0})
        nextIncompleteGateId=$nextId
        incompleteGateIds=@($openGateIds)
        gateRows=@($group)
        allIndexedSubchecksPassed=($unpassed -eq 0)
        fullStageReviewCandidate=($unpassed -eq 0 -and -not $approved)
        totalConditions=$s.Count
        passed=$passed
        partial=$partial
        auditNeeded=$audit
        blocked=$blocked
        missing=$missing
        unpassed=$unpassed
        assessed=$assessed
        evidenceVerifiedPercent=[math]::Round((100.0*$passed/$s.Count),1)
        conditionAssessmentPercent=[math]::Round((100.0*$assessed/$s.Count),1)
        evidencedActivityPercent=[math]::Round((100.0*$worked/$s.Count),1)
        nextUnauditedIds=@($group | Where-Object {$_.status -ceq 'AUDIT_NEEDED'}|ForEach-Object {$_.id})
    })
}
$ary=@($rows.ToArray())
$totalPass=0;$totalPartial=0;$totalAudit=0;$totalBlocked=0;$totalMissing=0
foreach($x in $ary){
    $totalPass+=$x.passed;$totalPartial+=$x.partial
    $totalAudit+=$x.auditNeeded;$totalBlocked+=$x.blocked
    $totalMissing+=$x.missing
}
# Explicit Team A original R4 whole-stage audit/signoff is recorded in docs/R4_FORMAL_ACCEPTANCE_A_SIGNOFF.md (PR #165 exact-head + main CI).
# Original R6 formal approval is separately recorded in docs/R6_FORMAL_ACCEPTANCE_A_SIGNOFF.md; do NOT infer from D5/5 rows.
# R0-R4 and R6 fully signed stages, all other stage weights are fixed from the
# formally approved roadmap. DO NOT derive a new official number from row PASS.
$result=[pscustomobject]@{
    schemaVersion='abcd_gate_progress_v1'
    source='docs/ABCD_GATE_LEDGER.md'
    statusScope='audited_synthetic_engineering_evidence_only'
    originalRecoveryRate='unknown'
    officialWeightedProjectPercent=[int]$officialWeight
    officialRemainingWeightPercent=[int](100-$officialWeight)
    officialCompletedStages=@($explicitAApprovedFormalStages)
    officialUncreditedStages=@($uncreditedWeights.Keys)
    formalStageWeights=[pscustomobject]$formalStageWeights
    futureStageWeights=[pscustomobject]$uncreditedWeights
    signedConditions=$totalPass
    partialConditions=$totalPartial
    auditNeededConditions=$totalAudit
    blockedConditions=$totalBlocked
    missingConditions=$totalMissing
    totalConditions=$expected
    incompleteGateIds=@($ary | ForEach-Object {$_.incompleteGateIds} | Where-Object {$null -ne $_ -and [string]$_ -ne ''})
    remainingIncompleteGateCount=$expected-$totalPass
    conditionVerifiedPercent=[math]::Round(100.0*$totalPass/$expected,1)
    conditionAssessmentPercent=[math]::Round(100.0*($expected-$totalAudit)/$expected,1)
    parameters=@($ary)
    limitations=@(
        'PASS labels are A-signed narrow synthetic gate subconditions, not full milestone completion.',
        'R4 and R6 were independently A-approved on original formal two-track synthetic corpus, not inferred from subrow counts.',
        'PARTIAL is no numeric percentage of implementation completeness.',
        'AUDIT_NEEDED does not mean feature missing.',
        'evidenceVerifiedPercent is PASS rows / total rows, NOT engineering or real recovery completion.',
        'The official 59 percent is derived solely from explicit independently A-approved original stage IDs and fixed roadmap weights.',
        'nextIncompleteGateId is a ledger-order first incomplete row, not a priority estimate or predicted implementation duration.',
        'conditionAssessmentPercent is reviewed rows / total rows, NOT implementation completeness.',
        'Real microSD and sole master IMG are NOT APPROVED for any access.',
        'R8 output remains blocked until full R7 official stage pass.'
    )
}
if($AsJson){$result | ConvertTo-Json -Depth 8}else{$result}
