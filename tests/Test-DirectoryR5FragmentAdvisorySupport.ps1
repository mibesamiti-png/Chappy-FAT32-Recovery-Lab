#requires -Version 5.1
# B -> C5-03 advisory-only non-oracle two-fragment support.
# Test-only synthetic SHA truth is NEVER supplied to C or B production.
# R0/R1 frozen in B Issue #71 comment 6864857286 and C #72 6864858313.
. (Join-Path (Join-Path $PSScriptRoot '..\modules\directory') 'DirectoryFragmentAdvisory.ps1')
. (Join-Path $PSScriptRoot 'helpers\New-Chappy3DCleanFixture.ps1')
Import-Module (Join-Path (Join-Path $PSScriptRoot '..\modules\carving') 'Chappy.FragmentEvidence.psm1') -Force -ErrorAction Stop

function Copy-BC503Envelope {
    param([psobject]$Object)
    return ($Object|ConvertTo-Json -Depth 16 -Compress|ConvertFrom-Json)
}
function Get-BC503ScoreSha {
    param([byte[]]$Image,[psobject]$Item)
    [int]$first=[int]$Item.firstBytes
    [int]$second=[int]$Item.secondBytes
    if($first -lt 1 -or $second -lt 1 -or ($first+$second) -gt 1056){throw 'B/C test oracle invalid C candidate bounds'}
    [byte[]]$assembled=New-Object byte[] ($first+$second)
    [Array]::Copy($Image,[int]$Item.firstOffset,$assembled,0,$first)
    [Array]::Copy($Image,[int]$Item.secondOffset,$assembled,$first,$second)
    return (Get-A3DSha256 $assembled)
}
function Assert-BC503Safety {
    param([psobject]$Advice,[string]$Context)
    Assert-B ($Advice.schemaVersion -ceq 'b_fragment_advisory_v1' -and
        $Advice.originalIdentity -ceq 'unknown' -and
        $Advice.originalParent -ceq 'unknown' -and
        $Advice.originalPath -ceq 'not_reconstructed' -and
        $Advice.sourceAuthenticity -ceq 'not_proven' -and
        $Advice.externalEventAuthority -ceq 'caller_supplied_not_A_receipt' -and
        $Advice.originalSha -ceq 'not_tested' -and
        -not $Advice.canExport -and -not $Advice.canSelectOriginal -and
        -not $Advice.canSelectFatCopy -and
        $Advice.metrics.additionalSourceReadCalls -eq 0 -and
        $Advice.metrics.additionalSourceReturnedBytes -eq 0 -and
        @($Advice.annotations|Where-Object{
            $_.originalIdentity -ne 'unknown' -or
            $_.sourceAuthenticity -ne 'not_proven' -or
            $_.canSelectOriginal
        }).Count -eq 0) ('BC5-03 no original/path/FAT winner/authenticity promotion: '+$Context)
}
$bc503Seed=202611
$bc503Clean=New-ChappyA3DCleanFixture -Seed $bc503Seed
[byte[]]$bc503Zip=New-A3D3MfBytes
Assert-B ($bc503Zip.Length -gt 512 -and $bc503Zip.Length -le 1056) 'BC5-03 generated ZIP is 512+tail within C original fixed two-piece profile'
$bc503OriginalSha=Get-A3DSha256 $bc503Zip
$bc503Central=-1
for($n=512;$n -le $bc503Zip.Length-46;$n++){
    if($bc503Zip[$n] -eq 0x50 -and $bc503Zip[$n+1] -eq 0x4B -and
       $bc503Zip[$n+2] -eq 1 -and $bc503Zip[$n+3] -eq 2){
        $bc503Central=$n;break
    }
}
Assert-B ($bc503Central -ge 512) 'BC5-03 mutable synthetic ZIP central directory metadata is only in second fragment'
[byte[]]$bc503Alternative=[byte[]]$bc503Zip.Clone()
$bc503Alternative[$bc503Central+4]=[byte]($bc503Alternative[$bc503Central+4] -bxor 1)
Assert-B ((Get-A3DSha256 $bc503Alternative) -cne $bc503OriginalSha) 'BC5-03 decoy is full-byte SHA different but ZIP data CRC unaffected'
$bc503Root=[int]$bc503Clean.layout.rootOffsetBytes
$bc503ModelAt=$bc503Root+2*512
$bc503TailBytes=$bc503Zip.Length-512
$bc503ScenarioCount=0
$bc503BaselineTP=0;$bc503BaselineFP=0;$bc503BaselineFN=0;$bc503BaselineTN=0
$bc503AdvisorTP=0;$bc503AdvisorFP=0;$bc503AdvisorFN=0;$bc503AdvisorTN=0;$bc503AdvisorUnknown=0
$bc503TotalCActual=0L;$bc503TotalCUnique=0L;$bc503TotalCReads=0L
$bc503TotalBActual=0L;$bc503TotalBCalls=0L
$bc503ShortUnknown=0;$bc503QuotaUnknown=0;$bc503ForgedDenied=0
foreach($scenario in @('normal','wrong_size','hidden_entry','reverse_order')){
    [byte[]]$bc503Image=[byte[]]$bc503Clean.image.Clone()
    # The directory contains the independently observed start cluster4 and
    # declared size; it does NOT contain the second-fragment truth or SHA.
    [Array]::Copy($bc503Zip,0,$bc503Image,$bc503ModelAt,512)
    [Array]::Clear($bc503Image,$bc503ModelAt+512,$bc503TailBytes)
    $bc503TailAt=if($scenario -eq 'reverse_order'){58368}else{60928}
    $bc503DecoyAt=if($scenario -eq 'reverse_order'){60928}else{61952}
    [Array]::Copy($bc503Zip,512,$bc503Image,$bc503TailAt,$bc503TailBytes)
    [Array]::Copy($bc503Alternative,512,$bc503Image,$bc503DecoyAt,$bc503TailBytes)
    Set-A3DUint32 $bc503Image ($bc503Root+32+28) ([uint32]$bc503Zip.Length)
    if($scenario -eq 'wrong_size'){
        Set-A3DUint32 $bc503Image ($bc503Root+32+28) ([uint32]($bc503Zip.Length+7))
    }
    if($scenario -eq 'hidden_entry'){$bc503Image[$bc503Root+32]=0xE5}
    $bc503Before=Get-A3DSha256 $bc503Image

    # The C search is run TWICE independently, same source, flags and caps.
    # A B advisory pass is purely post-hoc, never a new C source input.
    $bc503Runs=New-Object System.Collections.ArrayList
    for($pass=0;$pass -lt 2;$pass++){
        $read=[ChappyBR4ObservedParentPositive.MeteredStream]::new($bc503Image,512,-1L,384)
        try{
            $c=Get-ChappyFragmentCandidates -Source $read -EnableFragmentEvidence -WindowBytes 65536 -MaxStarts 4 -MaxTails 8 -MaxPairs 16 -MaxSourceBytes 81920 -MaxValidationBytes 98304 -MaxMilliseconds 30000
            Assert-B ((Test-BR4EventsMatchInput @($read.Events) $bc503Image) -and
                -not $read.CanWrite -and
                $read.ReturnedBytes -eq [long]$c.metrics.sourceBytesRead -and
                $read.Calls -eq [long]$c.metrics.readRequests -and
                $read.ReturnedBytes -le 81920 -and
                $c.metrics.pairAttempts -le 16 -and
                $c.metrics.sectorProbes -eq 128) ('BC5-03 independent C real source returns/Read/probe budget '+$scenario+' pass'+$pass)
            $unique=Get-BR4FormalUniqueReturnedBytes @($read.Events)
            Assert-B ($unique -le $read.ReturnedBytes -and $unique -ge 65536) ('BC5-03 C actual vs unique returned source intervals '+$scenario)
            [void]$bc503Runs.Add([pscustomobject]@{
                report=$c;returned=[long]$read.ReturnedBytes;unique=[long]$unique
                calls=[long]$read.Calls
            })
            $bc503TotalCActual+=[long]$read.ReturnedBytes
            $bc503TotalCUnique+=[long]$unique
            $bc503TotalCReads+=[long]$read.Calls
        }finally{$read.Dispose()}
    }
    $bc503C0=$bc503Runs[0]
    $bc503C1=$bc503Runs[1]
    Assert-B ($bc503C0.report.status -ceq 'ok' -and
        $bc503C1.report.status -ceq 'ok' -and
        $bc503C0.report.decision -ceq 'ambiguous' -and
        $bc503C1.report.decision -ceq 'ambiguous' -and
        @($bc503C0.report.items).Count -eq 2 -and
        @($bc503C1.report.items).Count -eq 2 -and
        $bc503C0.returned -eq $bc503C1.returned -and
        $bc503C0.unique -eq $bc503C1.unique -and
        $bc503C0.calls -eq $bc503C1.calls -and
        $bc503C0.report.metrics.pairAttempts -eq $bc503C1.report.metrics.pairAttempts -and
        $bc503C0.report.metrics.sectorProbes -eq $bc503C1.report.metrics.sectorProbes -and
        $bc503C0.report.metrics.validatorBytesRead -eq $bc503C1.report.metrics.validatorBytesRead -and
        ($bc503C0.report.items|ConvertTo-Json -Depth 9 -Compress) -ceq
        ($bc503C1.report.items|ConvertTo-Json -Depth 9 -Compress)) ('BC5-03 two actual C non-oracle scans identical hypotheses and physical budgets '+$scenario)

    # B observes only the actual root directory cluster, not a true FAT chain.
    $bStream=[ChappyBR4ObservedParentPositive.MeteredStream]::new($bc503Image,97,-1L,128)
    try{
        $b=Get-ChappyBDirectoryEvidenceV1 -Stream $bStream -EnableDirectoryEvidenceV1 -MaxScanBytes 512 -MaxCandidates 16 -MaxDirectories 8 -MaxReadSpans 8
        $events=@(New-B404AEventCopies @($bStream.Events) ([long]$b.geometry.dataOffsetBytes))
        Assert-B ((Test-BR4EventsMatchInput @($bStream.Events) $bc503Image) -and
            $bStream.ReturnedBytes -eq 1536L -and $bStream.Calls -eq 18 -and
            $b.metrics.bCompletedDirectoryBytes -eq 512 -and
            $b.metrics.bReturnedDirectoryBytes -eq 512 -and
            $b.directoryReadSpans.Count -eq 1 -and
            $b.originalIdentity -ceq 'unknown') ('BC5-03 B 32B metadata physically observed, B self ledger still unattested '+$scenario)
        $off=Get-ChappyBFragmentAdvisoryV1 -DirectoryEnvelope $b -OuterReadEvents $events -FragmentReport $bc503C1.report -SourceLengthBytes $bc503Image.Length
        Assert-B ($off.status -ceq 'disabled' -and
            $off.annotations.Count -eq 0 -and $off.metrics.additionalSourceReadCalls -eq 0) ('BC5-03 default-OFF no advisory and no extra reads '+$scenario)
        $readsBefore=$bStream.Calls
        $cBefore=($bc503C1.report|ConvertTo-Json -Depth 12 -Compress)
        $advice=Get-ChappyBFragmentAdvisoryV1 -DirectoryEnvelope $b -OuterReadEvents $events -FragmentReport $bc503C1.report -SourceLengthBytes $bc503Image.Length -EnableBFragmentAdvisory
        Assert-BC503Safety $advice $scenario
        Assert-B ($readsBefore -eq $bStream.Calls -and
            ($bc503C1.report|ConvertTo-Json -Depth 12 -Compress) -ceq $cBefore -and
            $advice.annotations.Count -eq 2 -and
            $advice.metrics.cCandidateCount -eq 2) ('BC5-03 same C candidates untouched, no B extra source IO '+$scenario)
        $bc503Exact=0;$bc503False=0
        for($index=0;$index -lt $bc503C1.report.items.Count;$index++){
            $item=$bc503C1.report.items[$index]
            $isExact=((Get-BC503ScoreSha $bc503Image $item) -ceq $bc503OriginalSha)
            if($isExact){$bc503Exact++;$bc503BaselineTP++}
            else{$bc503False++;$bc503BaselineFP++}
            $state=[string]$advice.annotations[$index].relation
            if($state -ceq 'size_consistent_unattested'){
                if($isExact){$bc503AdvisorTP++}else{$bc503AdvisorFP++}
            }else{
                $bc503AdvisorUnknown++
            }
        }
        Assert-B ($bc503Exact -eq 1 -and $bc503False -eq 1 -and
            $bc503C1.report.selectedOriginal -eq $null -and
            -not $bc503C1.report.canAutoSelectOriginal) ('BC5-03 exact SHA vs plausible CRC-only false original kept strictly test-side '+$scenario)
        if($scenario -eq 'normal' -or $scenario -eq 'reverse_order'){
            Assert-B ($advice.status -ceq 'partial' -and
                $advice.metrics.sizeConsistentUnattested -eq 2 -and
                $advice.decision -ceq 'advisory_only') ('BC5-03 both genuine+CRC-decoy same observed B size, cannot select original '+$scenario)
        }elseif($scenario -eq 'wrong_size'){
            Assert-B ($advice.metrics.sizeConflictUnknown -eq 2 -and
                @($advice.annotations|Where-Object{$_.relation -ne 'size_conflict_unknown'}).Count -eq 0) 'BC5-03 forged/corrupt observed size does not discard both C candidates'
        }else{
            Assert-B ($advice.metrics.entryUnobservedUnknown -eq 2 -and
                @($advice.annotations|Where-Object{$_.relation -ne 'entry_unobserved_unknown'}).Count -eq 0) 'BC5-03 hidden directory record UNKNOWN, C candidate list unchanged'
        }
        if($scenario -eq 'normal'){
            # Caller may forge only B spans, or add a parent/path assertion.
            # Neither is permitted to claim B-supported fragment original.
            $bad=Copy-BC503Envelope $b
            $bad.directoryReadSpans[0].lengthBytes=1024L
            $bad.metrics.bCompletedDirectoryBytes=1024L
            $bad.metrics.bReturnedDirectoryBytes=1024L
            $x=Get-ChappyBFragmentAdvisoryV1 -DirectoryEnvelope $bad -OuterReadEvents $events -FragmentReport $bc503C1.report -SourceLengthBytes $bc503Image.Length -EnableBFragmentAdvisory
            Assert-BC503Safety $x 'forged B completed span'
            Assert-B ($x.status -ceq 'unknown' -and $x.metrics.sizeConsistentUnattested -eq 0 -and
                $x.metrics.sourceUnknown -eq 2) 'BC5-03 forged B complete second root block denied with same returned events'
            $bc503ForgedDenied++
            $parent=Copy-BC503Envelope $b
            $parent.parentEdges=@([pscustomobject]@{parentCluster=2L;childCluster=4L;relationStatus='parent_hint_corroborated';confidence='verified'})
            $x=Get-ChappyBFragmentAdvisoryV1 -DirectoryEnvelope $parent -OuterReadEvents $events -FragmentReport $bc503C1.report -SourceLengthBytes $bc503Image.Length -EnableBFragmentAdvisory
            Assert-BC503Safety $x 'forged parent'
            Assert-B ($x.status -ceq 'unknown' -and $x.metrics.sizeConsistentUnattested -eq 0) 'BC5-03 forged parent/path metadata cannot support candidate selection'
            $bc503ForgedDenied++
        }
        $bc503TotalBActual+=[long]$bStream.ReturnedBytes
        $bc503TotalBCalls+=[long]$bStream.Calls
        Write-Host ('BC5-03 MATRIX: case={0} C_candidates=2, independent original exact=1 CRC_false_original=1, C_same_returned={1}B unique={2}B calls={3} probes={4} pairs={5}, B_extra_returned={6}B calls={7}, B_size_advisory={8}/{9}/{10}, original always UNKNOWN' -f
            $scenario,$bc503C1.returned,$bc503C1.unique,$bc503C1.calls,
            $bc503C1.report.metrics.sectorProbes,$bc503C1.report.metrics.pairAttempts,
            $bStream.ReturnedBytes,$bStream.Calls,$advice.metrics.sizeConsistentUnattested,
            $advice.metrics.sizeConflictUnknown,$advice.metrics.entryUnobservedUnknown)
    }finally{$bStream.Dispose()}

    if($scenario -eq 'normal'){
        # Physical B root source stops at 17B of the 512B cluster, then 0.
        $short=[ChappyBR4ObservedParentPositive.MeteredStream]::new($bc503Image,97,($bc503Root+17L),128)
        try{
            $bShort=Get-ChappyBDirectoryEvidenceV1 -Stream $short -EnableDirectoryEvidenceV1 -MaxScanBytes 512 -MaxReadSpans 8
            $shortEvents=@(New-B404AEventCopies @($short.Events) $bc503Root)
            $x=Get-ChappyBFragmentAdvisoryV1 -DirectoryEnvelope $bShort -OuterReadEvents $shortEvents -FragmentReport $bc503C1.report -SourceLengthBytes $bc503Image.Length -EnableBFragmentAdvisory
            Assert-BC503Safety $x '17B true root EOF'
            Assert-B ($short.ReturnedBytes -eq 1041L -and
                $bShort.metrics.bIncompleteReturnedBytes -eq 17 -and
                $bShort.metrics.bCompletedDirectoryBytes -eq 0 -and
                $x.status -ceq 'unknown' -and
                $x.metrics.sizeConsistentUnattested -eq 0) 'BC5-03 short 17B then real zero cannot confer observed size'
            $bc503ShortUnknown++
        }finally{$short.Dispose()}
        $under=[ChappyBR4ObservedParentPositive.MeteredStream]::new($bc503Image,512,-1L,384)
        try{
            $cUnder=Get-ChappyFragmentCandidates -Source $under -EnableFragmentEvidence -WindowBytes 65536 -MaxSourceBytes 512
            $x=Get-ChappyBFragmentAdvisoryV1 -DirectoryEnvelope $b -OuterReadEvents $events -FragmentReport $cUnder -SourceLengthBytes $bc503Image.Length -EnableBFragmentAdvisory
            Assert-BC503Safety $x 'C underquota no source'
            Assert-B ($under.Calls -eq 0 -and $cUnder.status -ceq 'partial' -and
                $x.status -ceq 'unknown' -and $x.annotations.Count -eq 0) 'BC5-03 C underquota does no physical reads or advisory promotion'
            $bc503QuotaUnknown++
        }finally{$under.Dispose()}
    }
    Assert-B ((Get-A3DSha256 $bc503Image) -ceq $bc503Before) ('BC5-03 invented full source SHA before/after intact '+$scenario)
    $bc503ScenarioCount++
}
Assert-B ($bc503ScenarioCount -eq 4 -and
    $bc503BaselineTP -eq 4 -and $bc503BaselineFP -eq 4 -and
    $bc503BaselineFN -eq 0 -and $bc503BaselineTN -eq 0 -and
    $bc503AdvisorTP -eq 2 -and $bc503AdvisorFP -eq 2 -and
    $bc503AdvisorUnknown -eq 4 -and
    $bc503ForgedDenied -eq 2 -and $bc503ShortUnknown -eq 1 -and
    $bc503QuotaUnknown -eq 1 -and
    $bc503TotalBActual -eq 6144L -and $bc503TotalBCalls -eq 72L -and
    $bc503TotalCUnique -le $bc503TotalCActual -and
    $bc503TotalCActual -le (8L*81920L)) 'BC5-03 four matched-budget synthetic C pairs, no fictitious original selection or free B reads'
Write-Host ('BC5-03 ACCEPTANCE: cases={0}, distinct C original-SHA scorer units=8 baseline TP={1} FP={2} FN={3} TN={4}; advisory consistent TP={5} FP={6} abstain/UNKNOWN={7} (never recovered); total C actual={8}B unique={9}B calls={10} (2 equal runs each case); extra B actual={11}B calls={12}; forged metadata denied={13} earlyEOFunknown={14} underquotaUnknown={15}; generated only, C5-03 still PARTIAL' -f
    $bc503ScenarioCount,$bc503BaselineTP,$bc503BaselineFP,$bc503BaselineFN,$bc503BaselineTN,
    $bc503AdvisorTP,$bc503AdvisorFP,$bc503AdvisorUnknown,
    $bc503TotalCActual,$bc503TotalCUnique,$bc503TotalCReads,
    $bc503TotalBActual,$bc503TotalBCalls,$bc503ForgedDenied,$bc503ShortUnknown,$bc503QuotaUnknown)
