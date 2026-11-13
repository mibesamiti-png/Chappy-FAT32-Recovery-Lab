#Requires -Version 5.1
# A objective gate metrics: no IMG reads or physical media, only the text ledger.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tool=Join-Path $root 'core\Get-ChappyABCDProgress.ps1'
$ledger=Join-Path $root 'docs\ABCD_GATE_LEDGER.md'
function Assert-AProgress([bool]$Good,[string]$Why){
    if(-not $Good){throw ('A_PROGRESS_FAIL: '+$Why)}
}
function Throws-AProgress([scriptblock]$Call){
    try{$null=& $Call;return $false}catch{return $true}
}
$before=[Security.Cryptography.SHA256]::Create()
try{
    $original=[IO.File]::ReadAllBytes($ledger)
    $sha=[BitConverter]::ToString($before.ComputeHash($original)).Replace('-','')
}finally{$before.Dispose()}
$live=[IO.File]::ReadAllText($ledger,[Text.Encoding]::UTF8)
$liveResult=& $tool -LedgerText $live
Assert-AProgress ($liveResult.totalConditions -eq 22 -and
    $liveResult.officialWeightedProjectPercent -eq 59 -and
    $liveResult.officialRemainingWeightPercent -eq 41 -and
    @($liveResult.officialUncreditedStages).Count -eq 5 -and
    $liveResult.remainingIncompleteGateCount -eq ($liveResult.totalConditions-$liveResult.signedConditions) -and
    @($liveResult.incompleteGateIds).Count -eq $liveResult.remainingIncompleteGateCount -and
    ($liveResult.signedConditions+$liveResult.partialConditions+
     $liveResult.auditNeededConditions+$liveResult.blockedConditions+
     $liveResult.missingConditions) -eq 22) 'current_live_ledger_valid_but_not_frozen_in_test'
# A frozen independent test ledger ensures future honest A row signoffs do
# not break CI merely because the live signed-off count has increased.
$syntheticStates=@{
    'B4-01'='PASS'; 'B4-02'='PASS'
    'C5-01'='PARTIAL';'C5-02'='PARTIAL';'C5-06'='PARTIAL'
    'D6-01'='PASS';'D6-02'='PARTIAL';'D6-03'='PARTIAL'
    'A7-02'='PARTIAL';'A7-03'='PASS'
}
$lines=New-Object 'System.Collections.Generic.List[string]'
$lines.Add('# Frozen artificial A gate ledger for parameter tests')
$lines.Add(('Synthetic-only explanatory padding '+('x'*300)))
foreach($group in @(
    [pscustomobject]@{prefix='B4';count=5},
    [pscustomobject]@{prefix='C5';count=6},
    [pscustomobject]@{prefix='D6';count=5},
    [pscustomobject]@{prefix='A7';count=6}
)){
    for($i=1;$i -le $group.count;$i++){
        $id=('{0}-{1:D2}' -f $group.prefix,$i)
        $state='AUDIT_NEEDED'
        if($syntheticStates.ContainsKey($id)){$state=$syntheticStates[$id]}
        $lines.Add(('| {0} | {1} | synthetic test-only record | no file access |' -f $id,$state))
    }
}
$text=$lines -join "`n"
$progress=& $tool -LedgerText $text
Assert-AProgress ($progress.schemaVersion -ceq 'abcd_gate_progress_v1' -and
    $progress.officialWeightedProjectPercent -eq 59 -and
    $progress.totalConditions -eq 22 -and
    $progress.signedConditions -eq 4 -and
    $progress.partialConditions -eq 6 -and
    $progress.auditNeededConditions -eq 12 -and
    $progress.blockedConditions -eq 0 -and
    $progress.missingConditions -eq 0) 'ledger_exact_known_row_counts'
$teams=@($progress.parameters)
Assert-AProgress ($teams.Count -eq 4 -and
    (($teams|ForEach-Object {$_.team}) -join ',') -ceq 'B,C,D,A' -and
    ($teams|Measure-Object -Property totalConditions -Sum).Sum -eq 22) 'four_original_team_roles'
$expected=@(
    [pscustomobject]@{name='B';p=2;q=0;u=3;v=40.0;a=40.0},
    [pscustomobject]@{name='C';p=0;q=3;u=3;v=0.0;a=50.0},
    [pscustomobject]@{name='D';p=1;q=2;u=2;v=20.0;a=60.0},
    [pscustomobject]@{name='A';p=1;q=1;u=4;v=16.7;a=33.3}
)
for($i=0;$i -lt 4;$i++){
    $x=$teams[$i];$want=$expected[$i]
    Assert-AProgress ($x.team -ceq $want.name -and
        $x.passed -eq $want.p -and $x.partial -eq $want.q -and
        $x.auditNeeded -eq $want.u -and
        $x.evidenceVerifiedPercent -eq $want.v -and
        $x.conditionAssessmentPercent -eq $want.a -and
        $x.officialStagePassed -eq ($want.name -cin @('B','D'))) ('team_'+$want.name+'_measured')
}
Assert-AProgress ($progress.conditionVerifiedPercent -eq 18.2 -and
    $progress.conditionAssessmentPercent -eq 45.5) 'different_verification_and_audit_percentages'
Assert-AProgress ($progress.officialRemainingWeightPercent -eq 41 -and
    $progress.officialCompletedStages.Count -eq 6 -and
    ($progress.officialCompletedStages -join ',') -ceq 'R0,R1,R2,R3,R4,R6' -and
    @($progress.officialUncreditedStages).Count -eq 5 -and
    $progress.futureStageWeights.R5 -eq 15 -and
    $progress.futureStageWeights.R7 -eq 10 -and
    $progress.formalStageWeights.R0 -eq 5 -and
    $progress.formalStageWeights.R10 -eq 2) 'explicit_formal_weight_59_plus_remaining_41'
Assert-AProgress ($progress.remainingIncompleteGateCount -eq 18 -and
    @($progress.incompleteGateIds).Count -eq 18 -and
    $teams[0].nextIncompleteGateId -ceq 'B4-03' -and
    @($teams[0].incompleteGateIds).Count -eq 3 -and
    @($teams[0].gateRows).Count -eq 5 -and
    $teams[0].formalStageState -ceq 'A_ACCEPTED_SYNTHETIC' -and
    $teams[0].creditedFormalWeight -eq 10 -and
    $teams[1].formalStageState -ceq 'NOT_YET_ACCEPTED' -and
    $teams[1].creditedFormalWeight -eq 0 -and
    $teams[2].formalStageState -ceq 'A_ACCEPTED_SYNTHETIC' -and
    $teams[2].creditedFormalWeight -eq 10 -and
    $teams[3].nextIncompleteGateId -ceq 'A7-01') 'frozen_four_team_machine_readable_gate_parameter_vector'
$pathResult=& $tool -LedgerPath $ledger
Assert-AProgress ($pathResult.signedConditions -eq $liveResult.signedConditions -and
    $pathResult.partialConditions -eq $liveResult.partialConditions) 'path_and_text_same_current_ledger_result'
$json=& $tool -LedgerText $text -AsJson | ConvertFrom-Json
Assert-AProgress ($json.officialWeightedProjectPercent -eq 59 -and
    $json.parameters.Count -eq 4 -and $json.originalRecoveryRate -ceq 'unknown' -and
    $json.officialRemainingWeightPercent -eq 41 -and
    $json.remainingIncompleteGateCount -eq 18 -and
    $json.parameters[0].nextIncompleteGateId -ceq 'B4-03') 'json_export_safe'
# A previously audited PASS row may regress to PARTIAL on re-audit.
$regressed=$text.Replace('| B4-02 | PASS |','| B4-02 | PARTIAL |')
Assert-AProgress ($regressed -cne $text) 'regression_fixture_modified'
$delta=& $tool -LedgerText $regressed
Assert-AProgress ($delta.signedConditions -eq 3 -and
    $delta.partialConditions -eq 7 -and
    $delta.parameters[0].evidenceVerifiedPercent -eq 20.0 -and
    $delta.officialWeightedProjectPercent -eq 59) 'regressions_not_hidden'
# Do not mint official acceptance even when all 22 subrows say PASS:
# independent original-stage scope and A formal signoff are still required.
$allPass=[regex]::Replace($text,
 '(?m)^(\|\s*(?:B4|C5|D6|A7)-\d{2}\s*\|\s*)(?:PARTIAL|AUDIT_NEEDED|BLOCKED|MISSING)(\s*\|)',
 '${1}PASS${2}')
$hypothetical=& $tool -LedgerText $allPass
Assert-AProgress ($hypothetical.signedConditions -eq 22 -and
    $hypothetical.officialWeightedProjectPercent -eq 59 -and
    @($hypothetical.parameters|Where-Object {$_.officialStagePassed}).Count -eq 2 -and
    $hypothetical.parameters[0].stage -ceq 'R4' -and
    $hypothetical.parameters[2].stage -ceq 'R6' -and
    $hypothetical.parameters[1].fullStageReviewCandidate -and
    $hypothetical.parameters[3].fullStageReviewCandidate -and
    $hypothetical.remainingIncompleteGateCount -eq 0 -and
    $hypothetical.officialRemainingWeightPercent -eq 41) 'no_automatic_extra_full_gate_credit'
# Refuse malformed/missing/duplicate/forged counts fail-closed.
$duplicated=$text+"`n| B4-01 | PASS | duplicate forged row | x |`n"
Assert-AProgress (Throws-AProgress { & $tool -LedgerText $duplicated }) 'reject_duplicate_row'
$missing=$text.Replace('| C5-06 | PARTIAL |','| C5-06 | REDACTED |')
Assert-AProgress (Throws-AProgress { & $tool -LedgerText $missing }) 'reject_unknown_row_status'
$wrongId=$text.Replace('| A7-03 | PASS |','| A7-09 | PASS |')
Assert-AProgress (Throws-AProgress { & $tool -LedgerText $wrongId }) 'reject_unexpected_stage_id'
Assert-AProgress (Throws-AProgress { & $tool -LedgerText $text -LedgerPath $ledger }) 'reject_multiple_sources'
Assert-AProgress (Throws-AProgress { & $tool -LedgerPath 'not_an_img.img' }) 'reject_non_markdown_path'
$afterHasher=[Security.Cryptography.SHA256]::Create()
try{
    $actual=[BitConverter]::ToString($afterHasher.ComputeHash([IO.File]::ReadAllBytes($ledger))).Replace('-','')
}finally{$afterHasher.Dispose()}
Assert-AProgress ($actual -ceq $sha) 'ledger_never_mutated'
Write-Host ('PASS: ABCD gate parameters B={0}/{1} C={2}/{3} D={4}/{5} A={6}/{7} official={8}%: passed={9}, partial={10}, auditNeeded={11}, independent evidence only, no real IMG' -f
    $teams[0].passed,$teams[0].totalConditions,
    $teams[1].passed,$teams[1].totalConditions,
    $teams[2].passed,$teams[2].totalConditions,
    $teams[3].passed,$teams[3].totalConditions,
    $progress.officialWeightedProjectPercent,
    $progress.signedConditions,$progress.partialConditions,$progress.auditNeededConditions)
