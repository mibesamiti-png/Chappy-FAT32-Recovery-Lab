#Requires -Version 5.1
# Team D R8 research only: sum R6 root and R7 remote evidence, NEVER select source.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Fat32VbrMirrorCrossEvidence.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Fat32StratifiedAnomalies.psm1') -ErrorAction Stop

function Get-ChappyFatAdditiveAnomalyEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [Parameter(Mandatory=$true)][object[]]$Candidates,
        [ValidateRange(32,256)][int]$MaxReadBytes=160,
        [ValidateRange(8,40)][int]$MaxEntries=40
    )
    if(-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.CanWrite) {
        throw 'Readable seekable nonwritable source required'
    }
    if($Candidates.Count -ne 2 -or $null -eq $Candidates[0] -or $null -eq $Candidates[1]) {
        throw 'Two unverified geometry candidate summaries required'
    }
    # Reserve disjoint quotas across two passes; duplicate reads are charged twice.
    $quota=[int][Math]::Min(40,[Math]::Min($MaxEntries,[Math]::Floor($MaxReadBytes/4.0)))
    $rootEntries=[int][Math]::Min(16,4*[Math]::Floor(($quota-4)/4.0))
    $remoteEntries=[int](4*[Math]::Floor(($quota-$rootEntries)/4.0))
    if($rootEntries -lt 4 -or $remoteEntries -lt 4){throw 'Insufficient joint quota'}
    $root=Get-ChappyFatVbrMirrorCrossEvidence -Stream $Stream -Candidates $Candidates -RootWindowEntries 2 -MaxReadBytes ($rootEntries*4) -MaxEntries $rootEntries
    $remote=Get-ChappyFatStratifiedAnomalyEvidence -Stream $Stream -Candidates $Candidates -MaxReadBytes ($remoteEntries*4) -MaxEntries $remoteEntries
    $bytes=[long]$root.metrics.bytesRead+[long]$remote.metrics.bytesRead
    $entries=[int]$root.metrics.entriesRead+[int]$remote.metrics.entriesRead
    if($bytes -gt $MaxReadBytes -or $bytes -gt 256 -or $entries -gt $MaxEntries -or $entries -gt 40) {
        throw 'Internal cumulative budget exceeded'
    }
    $rootBad=($root.metrics.totalAnomalyObservations -gt 0)
    $remoteBad=($remote.metrics.suspiciousEntries -gt 0)
    $mirrorBad=$false
    $cycles=0
    $reports=New-Object System.Collections.ArrayList
    for($c=0;$c -lt 2;$c++){
        $r=$root.items[$c]
        $s=$remote.items[$c]
        if($r.mirrors.differentEntries -gt 0 -or $s.mirrors.differingEntries -gt 0){
            $mirrorBad=$true
        }
        $copies=New-Object System.Collections.ArrayList
        for($f=0;$f -lt 2;$f++){
            $rootEvidence='unknown'
            if($r.fatCopies.Count -gt $f){
                $rootEvidence=$r.fatCopies[$f].rootChainEvidence
                if($rootEvidence -eq 'cycle_observed'){$cycles++}
            }
            $sampled=0;$remoteSuspect=0;$unknown=$null
            if($s.samples.Count -gt $f){
                $sampled=$s.samples[$f].observedUniqueEntries
                $remoteSuspect=$s.samples[$f].suspiciousEntries
                $unknown=$s.samples[$f].unknownDeclaredEntries
            }
            [void]$copies.Add([pscustomobject]@{
                fatIndex=$f
                rootChainEvidence=$rootEvidence
                remoteObservedUniqueEntries=$sampled
                remoteSuspiciousEntries=$remoteSuspect
                remoteUnknownDeclaredEntries=$unknown
                crossPassDuplicateReadsCharged=$true
            })
        }
        [void]$reports.Add([pscustomobject]@{
            sourceRole=$(if($c -eq 0){'primary'}else{'backup'})
            rootStatus=$r.status
            remoteStatus=$s.status
            geometryUnverified=$true
            fatCopies=@($copies.ToArray())
        })
    }
    $suspicious=($rootBad -or $remoteBad -or $mirrorBad)
    $partial=($root.scanIncomplete -or $remote.scanIncomplete)
    $cross=$(if($suspicious){'suspicious_samples_no_selection'}
        elseif($partial){'insufficient_evidence'}
        else{'ambiguous_samples_no_selection'})
    $warnings=@('candidate.geometry_unverified','fat.mirror_agreement_not_integrity',
        'coverage.unsampled_entries_unknown','coverage.cross_pass_duplicates_charged',
        'budget.subpasses_not_transferable','sample.absence_not_proof_of_health',
        'source.no_winner_or_repair','real_master_img_trial_not_authorized')
    if($partial){$warnings+=,'coverage.incomplete'}
    return [pscustomobject]@{
        schemaVersion='1';team='D'
        mode='experimental_additive_fat_anomaly_evidence'
        status=$(if($partial){'partial'}else{'ok'})
        scanIncomplete=$partial
        crossEvidence=$cross
        rootSuspiciousObserved=$rootBad
        remoteSuspiciousObserved=$remoteBad
        mirrorDisagreementObserved=$mirrorBad
        rootCyclesObserved=$cycles
        items=@($reports.ToArray())
        experimentalDefaultOff=$true
        selectedCandidate=$null
        sourceDecision='not_selected'
        writePermitted=$false
        warnings=@($warnings)
        errors=@()
        metrics=[pscustomobject]@{
            bytesRead=$bytes
            entriesRead=$entries
            maxReadBytes=$MaxReadBytes
            maxEntries=$MaxEntries
            rootQuotaEntries=$rootEntries
            remoteQuotaEntries=$remoteEntries
            rootBytesRead=$root.metrics.bytesRead
            remoteBytesRead=$remote.metrics.bytesRead
            rootEntriesRead=$root.metrics.entriesRead
            remoteEntriesRead=$remote.metrics.entriesRead
            uniqueCoverageAcrossPasses='not_inferred'
        }
    }
}
Export-ModuleMember -Function Get-ChappyFatAdditiveAnomalyEvidence
