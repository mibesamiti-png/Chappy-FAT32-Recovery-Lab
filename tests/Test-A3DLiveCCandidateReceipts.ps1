#Requires -Version 5.1
# Team A: actual C candidate validator reads observed by an independent A-owned Stream.
# ONLY generated in-memory images; no path, real device, extraction or writes.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'helpers\New-Chappy3DDamagedFixture.ps1')
. (Join-Path $PSScriptRoot 'helpers\Resolve-A3DReadEvidence.ps1')
Import-Module (Join-Path $root 'modules\carving\Chappy.Carving.psm1') -Force
. (Join-Path $root 'modules\carving\tests\R5M01PairResearch.ps1')
. (Join-Path $root 'modules\carving\tests\R5CandidateValidatorOriginResearch.ps1')

if(-not ('ChappyA7CandidateMeter' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class ChappyA7CandidateRead {
    public string EvidenceId {get;set;}
    public string SourceToken {get;set;}
    public string Consumer {get;set;}
    public string Purpose {get;set;}
    public string CandidateId {get;set;}
    public long OffsetBytes {get;set;}
    public int ReturnedBytes {get;set;}
}
public sealed class ChappyA7CandidateMeter : Stream {
    private readonly Stream input;
    private readonly long maximum;
    private readonly string sourceToken;
    private readonly List<ChappyA7CandidateRead> events=new List<ChappyA7CandidateRead>();
    private long used=0, requests=0;
    private string purpose="",candidate="";
    public ChappyA7CandidateMeter(Stream source,string token,long budget) {
        if(source==null||!source.CanRead||!source.CanSeek||source.CanWrite)
            throw new ArgumentException("Nonwritable readable seekable source required");
        if(String.IsNullOrEmpty(token)||token.Length>48||budget<1024||budget>120000)
            throw new ArgumentException("Invalid artificial source token or quota");
        input=source;sourceToken=token;maximum=budget;
    }
    public void BeginPhase(string name,string candidateKey) {
        if(name!="scan"&&name!="candidate_validation")
            throw new ArgumentException("Unrecognized A meter phase");
        if(name=="candidate_validation"&&(String.IsNullOrEmpty(candidateKey)||candidateKey.Length>128))
            throw new ArgumentException("Candidate key required");
        purpose=name;candidate=name=="scan"?"":candidateKey;
    }
    public ChappyA7CandidateRead[] GetEvents(){return events.ToArray();}
    public long BytesRead{get{return used;}}
    public long ReadRequests{get{return requests;}}
    public long Maximum{get{return maximum;}}
    public override bool CanRead{get{return true;}}
    public override bool CanSeek{get{return true;}}
    public override bool CanWrite{get{return false;}}
    public override long Length{get{return input.Length;}}
    public override long Position{get{return input.Position;}set{throw new NotSupportedException();}}
    public override long Seek(long offset,SeekOrigin origin){return input.Seek(offset,origin);}
    public override int Read(byte[] buffer,int offset,int count){
        if(String.IsNullOrEmpty(purpose))throw new InvalidOperationException("A meter phase required");
        if(buffer==null||offset<0||count<0||offset>buffer.Length-count)
            throw new ArgumentException("Invalid meter read buffer");
        requests++;
        if(count>maximum-used)throw new IOException("A7.total_source_budget_exhausted");
        long start=input.Position;
        int got=input.Read(buffer,offset,count);
        if(got>0) {
            used+=got;
            events.Add(new ChappyA7CandidateRead{
                // A-issued IDs must remain unique when independently metered sources
                // are aggregated; a per-stream bare sequence number collides.
                EvidenceId=sourceToken+"#"+events.Count.ToString("D4"),
                SourceToken=sourceToken,Consumer="carving",
                Purpose=purpose,CandidateId=candidate,
                OffsetBytes=start,ReturnedBytes=got
            });
        }
        return got;
    }
    public override void Flush(){}
    public override void SetLength(long length){throw new NotSupportedException();}
    public override void Write(byte[] buffer,int offset,int count){throw new NotSupportedException();}
    // This wrapper never closes the caller-owned synthetic source.
}
'@
}
function Assert-A7Live([bool]$Success,[string]$Code) {
    if(-not $Success){throw ('A7_LIVE_C_FAIL: '+$Code)}
}
$clean=New-ChappyA3DCleanFixture -Seed 202611
$originalSha=$clean.oracle[1].sha256
foreach($case in @('M00','M01','P02')){
    $fixture=New-ChappyA3DDamagedFixture -Seed 202611 -Case $case
    $imageHash=Get-A3DSha256 $fixture.image
    $source=[IO.MemoryStream]::new($fixture.image,$false)
    $token=('A7generated_'+$case+'_202611')
    $meter=[ChappyA7CandidateMeter]::new($source,$token,120000L)
    try{
        $meter.BeginPhase('scan','')
        $scout=Test-CM01FiniteZipPairs -Source $meter
        Assert-A7Live ($scout.status -ceq 'ok' -and
            @($scout.items).Count -eq 1 -and
            $meter.BytesRead -eq [long]$scout.metrics.sourceBytesRead) 'bounded_real_C_scout'
        $candidate=@($scout.items)[0]
        $spans=@($candidate.sourceSpans)
        $id=('3mf:{0}+{1},{2}+{3}' -f
            $spans[0].offsetBytes,$spans[0].lengthBytes,
            $spans[1].offsetBytes,$spans[1].lengthBytes)
        $scoutBytes=$meter.BytesRead
        # The A caller selects the phase/key, not C. C receives only a Stream.
        $meter.BeginPhase('candidate_validation',$id)
        $c=Test-CObservedCandidateValidation -Source $meter -Candidate $candidate
        $events=@($meter.GetEvents())
        $validated=@($events|Where-Object {
            $_.Purpose -ceq 'candidate_validation' -and $_.CandidateId -ceq $id
        })
        $ids=@($validated|ForEach-Object{$_.EvidenceId})
        $sum=0L
        foreach($evt in $validated){$sum += [long]$evt.ReturnedBytes}
        Assert-A7Live ($c.candidateKey -ceq $id -and
            $c.originStatus -ceq 'unattributed_pending_A_meter_receipt' -and
            $c.originalIdentity -ceq 'unknown' -and
            $c.metrics.sourceBytesRead -eq $sum -and
            $meter.BytesRead -eq $scoutBytes+$sum) 'C_diagnostics_agree_with_independent_A_meter'
        $cReads=@($c.observedPhysicalReads)
        Assert-A7Live ($cReads.Count -eq $validated.Count -and
            $cReads.Count -ge 2 -and $ids.Count -le 32) 'actual_source_read_events'
        for($j=0;$j -lt $cReads.Count;$j++){
            Assert-A7Live ($cReads[$j].offsetBytes -eq $validated[$j].OffsetBytes -and
                $cReads[$j].returnedBytes -eq $validated[$j].ReturnedBytes -and
                $cReads[$j].candidateKey -ceq $id -and
                $null -eq $cReads[$j].PSObject.Properties['evidenceId']) 'diagnostic_read_equals_A_event_without_fake_receipt'
        }
        $scope=@{
            ImageLengthBytes=[long]$fixture.image.Length
            SourceToken=$token
            CandidateId=$id
            CandidateExtents=$spans
            MeterEvents=$events
            MaxPhysicalReadBytes=120000L
        }
        $resolved=Resolve-A3DReadEvidence @scope -ClaimedEventIds $ids
        $extentSum=[long]$spans[0].lengthBytes+[long]$spans[1].lengthBytes
        Assert-A7Live ($resolved.status -ceq 'source_observed' -and
            $resolved.candidateReadBytes -eq $extentSum -and
            $resolved.sourceActualReadBytes -eq $meter.BytesRead -and
            $resolved.originalIdentity -ceq 'unknown' -and
            $meter.BytesRead -le $meter.Maximum -and -not $meter.CanWrite) 'real_A_events_reconcile_to_C_candidate_read'
        $scanId=@($events|Where-Object{$_.Purpose -ceq 'scan'}|Select-Object -First 1)
        Assert-A7Live ($scanId.Count -eq 1) 'must_have_scout_read'
        $wrongPhase=Resolve-A3DReadEvidence @scope -ClaimedEventIds @($scanId[0].EvidenceId)
        Assert-A7Live ($wrongPhase.status -ceq 'unattributed' -and
            $wrongPhase.reasons -contains 'origin.not_candidate_validation') 'scout_not_candidate_validation'
        $different=Resolve-A3DReadEvidence @scope -ClaimedEventIds @('A7P-FORGED')
        Assert-A7Live ($different.status -ceq 'unattributed' -and
            $different.reasons -contains 'origin.event_not_observed') 'fabricated_receipt_rejected'
        $badToken=$scope.Clone();$badToken.SourceToken='A7different_generated_source'
        $cross=Resolve-A3DReadEvidence @badToken -ClaimedEventIds $ids
        Assert-A7Live ($cross.status -ceq 'unattributed' -and
            $cross.reasons -contains 'origin.wrong_source') 'cross_source_rejected'
        $reversed=$scope.Clone()
        $reversed.CandidateId=('3mf:{0}+{1},{2}+{3}' -f
            $spans[1].offsetBytes,$spans[1].lengthBytes,
            $spans[0].offsetBytes,$spans[0].lengthBytes)
        $order=Resolve-A3DReadEvidence @reversed -ClaimedEventIds $ids
        Assert-A7Live ($order.status -ceq 'unattributed' -and
            $order.reasons -contains 'origin.not_candidate_validation') 'reversed_fragments_not_same_candidate'
        # A physical coverage says nothing about structural CRC or original SHA.
        Assert-A7Live ($c.status -ceq $(if($case -eq 'P02'){'format_rejected'}else{'format_consistent'})) 'C_actual_structural_validation_separate'
        if($c.status -eq 'format_consistent'){
            $exact=($c.candidateSha256 -ceq $originalSha)
            Assert-A7Live ($exact -eq ($case -ne 'P02')) 'scorer_original_sha_only'
        }
        Assert-A7Live ((Get-A3DSha256 $fixture.image) -ceq $imageHash) 'input_unchanged'
        Write-Host ('A7 LIVE C case={0} A_source_total={1} scout={2} candidate_reads={3} A_receipts={4} sourceObserved={5} originalIdentity={6}' -f
            $case,$meter.BytesRead,$scoutBytes,$sum,$ids.Count,$resolved.status,$resolved.originalIdentity)
    }finally{$source.Dispose()}
}
# Negative A/B: two independently created, byte-identical *synthetic* images
# can yield exactly the same physical offsets and bytes. Event IDs must not
# collide, and receipt attribution must never cross an A-owned source token.
$fixtureOne=New-ChappyA3DDamagedFixture -Seed 202611 -Case M00
$fixtureTwo=New-ChappyA3DDamagedFixture -Seed 202611 -Case M00
$shaOne=Get-A3DSha256 $fixtureOne.image
$shaTwo=Get-A3DSha256 $fixtureTwo.image
Assert-A7Live ($shaOne -ceq $shaTwo) 'independent_synthetic_sources_have_equal_bytes'
$rawOne=[IO.MemoryStream]::new($fixtureOne.image,$false)
$rawTwo=[IO.MemoryStream]::new($fixtureTwo.image,$false)
$tokenOne='A7_independent_synthetic_one'
$tokenTwo='A7_independent_synthetic_two'
$meterOne=[ChappyA7CandidateMeter]::new($rawOne,$tokenOne,4096L)
$meterTwo=[ChappyA7CandidateMeter]::new($rawTwo,$tokenTwo,4096L)
$candidateKey='3mf:256+64,512+16'
$sourceExtents=@(
    [pscustomobject]@{offsetBytes=[long]256;lengthBytes=[long]64},
    [pscustomobject]@{offsetBytes=[long]512;lengthBytes=[long]16}
)
try{
    foreach($meterItem in @($meterOne,$meterTwo)){
        $meterItem.BeginPhase('candidate_validation',$candidateKey)
        foreach($extent in $sourceExtents){
            [void]$meterItem.Seek([long]$extent.offsetBytes,[IO.SeekOrigin]::Begin)
            [byte[]]$buffer=[byte[]]::new([int]$extent.lengthBytes)
            $count=$meterItem.Read($buffer,0,$buffer.Length)
            Assert-A7Live ($count -eq $buffer.Length) 'actual_test_only_candidate_read'
        }
        Assert-A7Live (-not $meterItem.CanWrite -and $meterItem.BytesRead -eq 80) 'independently_metered_readonly_source'
    }
    $eventsOne=@($meterOne.GetEvents())
    $eventsTwo=@($meterTwo.GetEvents())
    $idsOne=@($eventsOne|ForEach-Object{$_.EvidenceId})
    $idsTwo=@($eventsTwo|ForEach-Object{$_.EvidenceId})
    Assert-A7Live ($eventsOne.Count -eq 2 -and $eventsTwo.Count -eq 2 -and
        $idsOne[0] -cne $idsTwo[0] -and $idsOne[1] -cne $idsTwo[1]) 'a_issued_receipts_do_not_collide_across_sources'
    $allMeterEvents=@($eventsOne)+@($eventsTwo)
    $base=@{
        ImageLengthBytes=[long]$fixtureOne.image.Length
        SourceToken=$tokenOne
        CandidateId=$candidateKey
        CandidateExtents=$sourceExtents
        MeterEvents=$allMeterEvents
        MaxPhysicalReadBytes=4096L
    }
    $first=Resolve-A3DReadEvidence @base -ClaimedEventIds $idsOne
    Assert-A7Live ($first.status -ceq 'source_observed' -and
        $first.candidateReadBytes -eq 80 -and
        $first.sourceActualReadBytes -eq 80 -and
        $first.originalIdentity -ceq 'unknown') 'first_artificial_source_receipts_scoped'
    $other=$base.Clone();$other.SourceToken=$tokenTwo
    $second=Resolve-A3DReadEvidence @other -ClaimedEventIds $idsTwo
    Assert-A7Live ($second.status -ceq 'source_observed' -and
        $second.candidateReadBytes -eq 80 -and
        $second.sourceActualReadBytes -eq 80 -and
        $second.originalIdentity -ceq 'unknown') 'second_artificial_source_receipts_scoped'
    $cross=Resolve-A3DReadEvidence @base -ClaimedEventIds @($idsOne[0],$idsTwo[1])
    Assert-A7Live ($cross.status -ceq 'unattributed' -and
        $cross.candidateReadBytes -eq 64 -and
        $cross.reasons -contains 'origin.wrong_source' -and
        $cross.reasons -contains 'coverage.candidate_bytes_not_fully_read') 'identical_bytes_wrong_source_cannot_complete_candidate'
    $wrongSource=Resolve-A3DReadEvidence @base -ClaimedEventIds $idsTwo
    Assert-A7Live ($wrongSource.status -ceq 'unattributed' -and
        $wrongSource.candidateReadBytes -eq 0 -and
        $wrongSource.reasons -contains 'origin.wrong_source') 'other_image_receipts_cannot_authenticate_first'
    $cap=$base.Clone();$cap.MaxPhysicalReadBytes=64L
    $quota=Resolve-A3DReadEvidence @cap -ClaimedEventIds $idsOne
    Assert-A7Live ($quota.status -ceq 'unattributed' -and
        $quota.reasons -contains 'budget.physical_read_limit') 'actual_source_quota_enforced_for_same_image'
    Assert-A7Live ((Get-A3DSha256 $fixtureOne.image) -ceq $shaOne -and
        (Get-A3DSha256 $fixtureTwo.image) -ceq $shaTwo) 'both_generated_sources_unchanged'
    Write-Host ('A7 DUAL SOURCES source1={0} source2={1} actual_each=80 distinct_receipts=4 cross_source=unattributed originalIdentity=unknown' -f $tokenOne,$tokenTwo)
}finally{
    $rawOne.Dispose()
    $rawTwo.Dispose()
}
Write-Host 'PASS: A7 actual independent synthetic sources never share A event IDs or cross-attest identical physical offsets.'

Write-Host 'PASS: A7 independent A Stream.Read receipt IDs reconcile actual C test-only candidate validation, not scans or original identity.'
