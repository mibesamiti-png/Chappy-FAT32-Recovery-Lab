#requires -Version 5.1
# Team C R5 same-corpus format-vs-original evidence experiment.
# This research is test-only; the default scanner remains unchanged.
function Assert-R5FormatEvidence {
    param([bool]$Condition,[string]$Reason)
    if (-not $Condition) { throw "R5_FORMAT_EVIDENCE_FAIL: $Reason" }
}

function Get-R5OracleCandidateHash {
    param([byte[]]$Image,$Candidate)
    if ($Candidate.lengthBytes -le 0 -or $Candidate.lengthBytes -gt 4096) {
        throw 'R5 candidate length outside scorer bound'
    }
    [byte[]]$bytes=New-Object byte[] ([int]$Candidate.lengthBytes)
    [Array]::Copy($Image,[int]$Candidate.offsetBytes,$bytes,0,$bytes.Length)
    return Get-A3DSha256 $bytes
}

function Invoke-R5SyntheticFormatEvidence {
    $repoRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $repoRoot 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
    $seed=202611
    $clean=New-ChappyA3DCleanFixture -Seed $seed
    $truth3mf=$clean.oracle[1]
    $truthStl=$clean.oracle[2]
    $baseMatches=0
    $candidateMatches=0
    $falseOriginalClaims=0
    $verifiedItems=0
    foreach($case in @('M00','P01','P02','P03')) {
        $fixture=New-ChappyA3DDamagedFixture -Seed $seed -Case $case
        $before=Get-A3DSha256 $fixture.image
        Assert-R5FormatEvidence ($before -ceq $fixture.manifest.imageSha256) ($case+': fixture oracle SHA')
        $source=[IO.MemoryStream]::new($fixture.image,$false)
        try {
            Assert-R5FormatEvidence ($source.CanRead -and $source.CanSeek -and -not $source.CanWrite) ($case+': read-only stream')
            $base=Get-ChappyCarvingCandidates -Stream $source -MaxScanBytes 65536 -MaxFileBytes 4096 -ExtraValidationReadBytes 32768 -MaxCandidates 16 -MaxProbes 16 -MaxProbeBytes 8192
            $candidate=Get-ChappyCarvingCandidates -Stream $source -MaxScanBytes 65536 -MaxFileBytes 4096 -ExtraValidationReadBytes 32768 -MaxCandidates 16 -MaxProbes 16 -MaxProbeBytes 8192 -EnableSmallDeflateCrc
            Assert-R5FormatEvidence ($base.metrics.bytesRead -le 98304 -and $candidate.metrics.bytesRead -le 98304) ($case+': read budget')
            Assert-R5FormatEvidence ($base.metrics.readRequests -le 64 -and $candidate.metrics.readRequests -le 64) ($case+': request budget')
            Assert-R5FormatEvidence (-not $source.CanWrite) ($case+': source remains nonwritable')
        } finally { $source.Dispose() }
        $after=Get-A3DSha256 $fixture.image
        Assert-R5FormatEvidence ($before -ceq $after) ($case+': source image unchanged')

        $base3mf=@($base.items | Where-Object {$_.format -eq '3mf' -and $_.offsetBytes -eq $truth3mf.extents[0].offsetBytes})
        $candidate3mf=@($candidate.items | Where-Object {$_.format -eq '3mf' -and $_.offsetBytes -eq $truth3mf.extents[0].offsetBytes})
        $oracleMatch=$false
        if($candidate3mf.Count -eq 1) {
            $oracleMatch=(Get-R5OracleCandidateHash $fixture.image $candidate3mf[0]) -ceq $truth3mf.sha256
        }
        if($base3mf.Count -eq 1 -and (Get-R5OracleCandidateHash $fixture.image $base3mf[0]) -ceq $truth3mf.sha256) { $baseMatches++ }
        if($oracleMatch) { $candidateMatches++ }

        foreach($item in @($base.items)+@($candidate.items)) {
            if($item.confidence -eq 'verified') {
                $verifiedItems++
                $allowedScope=@('structural_only_not_original_file_integrity','heuristic_text_only_not_original_file_integrity')
                if(-not $item.PSObject.Properties['integrityScope'] -or $item.integrityScope -cnotin $allowedScope) {
                    $falseOriginalClaims++
                }
            }
        }
        switch($case) {
            'M00' {
                Assert-R5FormatEvidence ($base3mf.Count -eq 1 -and $candidate3mf.Count -eq 1) 'M00 detects 3MF'
                Assert-R5FormatEvidence ($base3mf[0].confidence -eq 'verified' -and $candidate3mf[0].crc32Status -eq 'match') 'M00 structural and CRC evidence'
                Assert-R5FormatEvidence $oracleMatch 'M00 candidate exact original SHA'
            }
            'P01' {
                Assert-R5FormatEvidence ($base3mf.Count -eq 0 -and $candidate3mf.Count -eq 0) 'P01 invalid EOCD not promoted to 3MF'
                Assert-R5FormatEvidence (@($candidate.items | Where-Object {$_.format -eq 'zip' -and $_.confidence -eq 'partial'}).Count -gt 0) 'P01 retains partial signature observations'
            }
            'P02' {
                Assert-R5FormatEvidence ($base3mf.Count -eq 1 -and $base3mf[0].confidence -eq 'verified') 'P02 baseline remains structural-only'
                Assert-R5FormatEvidence ($candidate3mf.Count -eq 1 -and $candidate3mf[0].crc32Status -eq 'mismatch' -and $candidate3mf[0].confidence -eq 'partial') 'P02 opt-in CRC mismatch downgrades candidate'
                Assert-R5FormatEvidence (-not $oracleMatch) 'P02 independent original SHA mismatch'
            }
            'P03' {
                Assert-R5FormatEvidence ($candidate3mf.Count -eq 1 -and $oracleMatch) 'P03 unrelated 3MF remains exact'
                [byte[]]$stlBytes=New-Object byte[] $truthStl.lengthBytes
                [Array]::Copy($fixture.image,[int]$truthStl.extents[0].offsetBytes,$stlBytes,0,$stlBytes.Length)
                Assert-R5FormatEvidence ((Get-A3DSha256 $stlBytes) -cne $truthStl.sha256) 'P03 STL payload differs from clean oracle'
                Assert-R5FormatEvidence (@($candidate.items | Where-Object {$_.format -eq 'stl'}).Count -eq 0) 'current module makes no unsupported STL claim'
            }
        }
        Write-Host ('R5 {0}: baselineBytes={1} optInBytes={2} requests={3}/{4} 3mfDetected={5}/{6} candidate3mfExact={7}' -f
            $case,$base.metrics.bytesRead,$candidate.metrics.bytesRead,$base.metrics.readRequests,$candidate.metrics.readRequests,
            ($base3mf.Count -gt 0),($candidate3mf.Count -gt 0),$oracleMatch)
    }
    Assert-R5FormatEvidence ($falseOriginalClaims -eq 0) 'no verified original-byte claims'
    Assert-R5FormatEvidence ($baseMatches -eq 2 -and $candidateMatches -eq 2) 'only clean M00 and unaffected 3MF in P03 match original'
    Write-Host ('PASS: R5 baseline/opt-in format evidence; exact 3MF matches={0}/4, verified items={1}, false original claims={2}, PowerShell={3}.' -f
        $candidateMatches,$verifiedItems,$falseOriginalClaims,$PSVersionTable.PSVersion.ToString())
}