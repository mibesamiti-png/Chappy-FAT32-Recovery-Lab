#requires -Version 5.1
# Team C Issue #72: independent synthetic scorer for candidate-specific
# actual Source.Read observation. Only the scorer sees original file SHA.
function Assert-COrigin([bool]$Ok,[string]$Why) {
    if(-not $Ok){throw ('C_ORIGIN_FAIL: '+$Why)}
}
# Deliberately short-ending, READ-ONLY stream for a true partial physical
# observation. No third-party library or file/device handle involved.
Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class CArtificialShortValidationStream : Stream {
    private readonly Stream inner;
    private int remaining;
    public CArtificialShortValidationStream(Stream source,int maxReturned) {
        inner=source; remaining=maxReturned;
    }
    public override bool CanRead { get { return inner.CanRead; } }
    public override bool CanSeek { get { return inner.CanSeek; } }
    public override bool CanWrite { get { return false; } }
    public override long Length { get { return inner.Length; } }
    public override long Position { get { return inner.Position; } set { inner.Position=value; } }
    public override long Seek(long offset,SeekOrigin origin) {return inner.Seek(offset,origin);}
    public override int Read(byte[] b,int offset,int count) {
        if(remaining<=0) return 0;
        int got=inner.Read(b,offset,Math.Min(count,Math.Min(17,remaining)));
        remaining-=got;return got;
    }
    public override void Flush() {}
    public override void SetLength(long length) {throw new NotSupportedException();}
    public override void Write(byte[] b,int offset,int count) {throw new NotSupportedException();}
    protected override void Dispose(bool disposing) {if(disposing) inner.Dispose();base.Dispose(disposing);}
}
'@
function Invoke-CObservedCandidateValidationRegression {
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $root 'tests\helpers\New-Chappy3DDamagedFixture.ps1')
    $clean=New-ChappyA3DCleanFixture -Seed 202611
    $truth=$clean.oracle[1]
    $caseNames=@('M00','M01','P02','M01_decoy')
    $discoverySourceBytes=0L;$validationSourceBytes=0L;$memoryBytes=0L
    $readRequests=0;$readIntervals=0;$baselinePairs=0;$validatedPairs=0
    $positive=0;$negative=0;$unknown=0;$originalExact=0;$byteDifferent=0
    $scorerCases=0;$reference=$null;$unchanged=0
    foreach($id in $caseNames) {
        $sourceId=if($id -eq 'M01_decoy'){'M01'}else{$id}
        $fixture=New-ChappyA3DDamagedFixture -Seed 202611 -Case $sourceId
        [byte[]]$data=[byte[]]$fixture.image.Clone()
        if($id -eq 'M01_decoy') {
            [Array]::Copy([byte[]]@(0x50,0x4b,0x05,0x06),0,$data,(61440+24),4)
        }
        $inputHash=Get-A3DSha256 $data
        $meter=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($data,$false))
        try {
            $baseline=Test-CM01FiniteZipPairs -Source $meter
            Assert-COrigin ($meter.BytesRead -eq $baseline.metrics.sourceBytesRead -and
                $meter.BytesRead -le 73728) ($id+': source scout budget and actual I/O equal')
            $discoverySourceBytes += [long]$baseline.metrics.sourceBytesRead
            $proposals=@($baseline.items)
            Assert-COrigin ($proposals.Count -le 8) ($id+': bounded candidate proposals')
            if($id -eq 'M00' -or $id -eq 'M01'){
                Assert-COrigin ($baseline.status -eq 'ok' -and
                    @($proposals | Where-Object {$_.possible}).Count -eq 1) ($id+': original synthetic positive proposal')
            }
            if($id -eq 'M01_decoy'){
                Assert-COrigin ($baseline.status -eq 'ok' -and $proposals.Count -eq 2) 'fake EOCD yields two observed proposals'
            }
            $baselinePairs += $proposals.Count
            $casePositive=0
            foreach($candidate in $proposals){
                $before=[long]$meter.BytesRead
                $observed=Test-CObservedCandidateValidation -Source $meter -Candidate $candidate
                Assert-COrigin (($meter.BytesRead-$before) -eq $observed.metrics.sourceBytesRead) ($id+': candidate validation Source.Read only')
                Assert-COrigin ($observed.metrics.sourceBytesRead -le 2048 -and
                    $observed.metrics.memoryValidatorBytesRead -le 8192) ($id+': bounded candidate validation budget')
                Assert-COrigin ($observed.metrics.sourceBytesRead -gt 0 -and
                    $observed.metrics.sourceObservedIntervals -ge 2) ($id+': physically re-read each candidate span')
                $readSum=0L
                foreach($evt in $observed.observedPhysicalReads){
                    $readSum += [long]$evt.returnedBytes
                    Assert-COrigin ($evt.purpose -ceq 'candidate_validation' -and
                        $evt.consumer -ceq 'carving' -and
                        $evt.candidateKey -ceq $observed.candidateKey) ($id+': ordered candidate read intent')
                    Assert-COrigin ($null -eq $evt.PSObject.Properties['evidenceId'] -and
                        $null -eq $evt.PSObject.Properties['sourceToken']) ($id+': C never mints trusted A receipts')
                }
                Assert-COrigin ($readSum -eq $observed.metrics.sourceBytesRead -and
                    $readSum -eq (($candidate.sourceSpans[0].lengthBytes)+($candidate.sourceSpans[1].lengthBytes))) ($id+': observed physical read coverage')
                Assert-COrigin ($observed.originStatus -ceq 'unattributed_pending_A_meter_receipt' -and
                    $observed.originalIdentity -ceq 'unknown' -and
                    $observed.integrityScope -ceq 'structural_only_not_original_file_integrity') ($id+': untrusted origin and no original-file identity')
                Assert-COrigin ($observed.status -in @('format_consistent','format_rejected')) ($id+': complete bounded format decision')
                Assert-COrigin (($observed.status -eq 'format_consistent') -eq [bool]$candidate.possible) ($id+': re-validation agrees with same artificial proposal')
                $validationSourceBytes += [long]$observed.metrics.sourceBytesRead
                $memoryBytes += [long]$observed.metrics.memoryValidatorBytesRead
                $readRequests += [int]$observed.metrics.sourceReadRequests
                $readIntervals += [int]$observed.metrics.sourceObservedIntervals
                $validatedPairs++
                if($observed.status -eq 'format_consistent'){
                    $positive++;$casePositive++
                    # Scoring ONLY: known artificial original SHA is outside
                    # Test-CObservedCandidateValidation and original remains unknown.
                    if($observed.candidateSha256 -ceq $truth.sha256){$originalExact++}
                    else{$byteDifferent++}
                }else{$negative++}
                if($id -eq 'M00' -and $null -eq $reference){$reference=$candidate}
            }
            if($id -eq 'P02'){
                Assert-COrigin ($casePositive -eq 0) 'P02 altered synthetic payload never accepted as CRC-correct original'
            }
            if($id -eq 'M00' -or $id -eq 'M01'){
                Assert-COrigin ($casePositive -eq 1) ($id+': revalidation yields one structural candidate')
            }
            Assert-COrigin (($meter.BytesRead -le 120000) -and -not $meter.CanWrite) ($id+': combined scout and second-pass under A shared nominal budget')
            $scorerCases++
            Write-Host ('C ORIGIN CASE={0} proposals={1} consistent={2} scout_source_bytes={3} total_source_bytes={4}' -f
                $id,$proposals.Count,$casePositive,$baseline.metrics.sourceBytesRead,$meter.BytesRead)
        }finally{$meter.Dispose()}
        Assert-COrigin ((Get-A3DSha256 $data) -ceq $inputHash) ($id+': original artificial bytes unchanged')
        $unchanged++
    }
    Assert-COrigin ($null -ne $reference) 'M00 observed candidate reference exists for negative controls'
    # Deliberate physical read cap smaller than the candidate: returned
    # partial first extent, no full validation and no trusted receipt.
    $sample=New-ChappyA3DDamagedFixture -Seed 202611 -Case M00
    $budget=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($sample.image,$false))
    try{
        $partial=Test-CObservedCandidateValidation -Source $budget -Candidate $reference -MaxSourceBytes 512
        Assert-COrigin ($partial.status -eq 'partial' -and $partial.decision -eq 'incomplete' -and
            $partial.metrics.sourceBytesRead -eq 512 -and $budget.BytesRead -eq 512 -and
            $partial.metrics.memoryValidatorBytesRead -eq 0 -and
            $partial.metrics.stopCode -eq 'validation.source_byte_limit') 'candidate source budget returns actual partial reads'
    }finally{$budget.Dispose()}
    $short=[ChappyCountingReadStream]::new([CArtificialShortValidationStream]::new([IO.MemoryStream]::new($sample.image,$false),17))
    try{
        $partial=Test-CObservedCandidateValidation -Source $short -Candidate $reference
        Assert-COrigin ($partial.status -eq 'partial' -and $partial.decision -eq 'incomplete' -and
            $short.BytesRead -eq 17 -and $partial.metrics.sourceBytesRead -eq 17 -and
            $partial.metrics.sourceObservedIntervals -eq 1 -and
            $partial.metrics.stopCode -eq 'validation.short_read') 'real short-return data never becomes full candidate coverage'
    }finally{$short.Dispose()}
    $lowMemory=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($sample.image,$false))
    try{
        $partial=Test-CObservedCandidateValidation -Source $lowMemory -Candidate $reference -MaxValidatorBytes 1
        Assert-COrigin ($partial.status -eq 'partial' -and
            $partial.metrics.memoryValidatorBytesRead -eq 0 -and
            $partial.metrics.sourceBytesRead -gt 0 -and
            $partial.metrics.stopCode -eq 'validation.memory_quota_not_reserved') 'memory budget distinguishes source observed from format validated'
    }finally{$lowMemory.Dispose()}
    $backward=[pscustomobject]@{sourceSpans=@($reference.sourceSpans[1],$reference.sourceSpans[0])}
    $reverseStream=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($sample.image,$false))
    try{
        $reverse=Test-CObservedCandidateValidation -Source $reverseStream -Candidate $backward
        Assert-COrigin ($reverse.candidateKey -cne ('3mf:{0}+{1},{2}+{3}' -f
            $reference.sourceSpans[0].offsetBytes,$reference.sourceSpans[0].lengthBytes,
            $reference.sourceSpans[1].offsetBytes,$reference.sourceSpans[1].lengthBytes) -and
            $reverse.originStatus -eq 'unattributed_pending_A_meter_receipt' -and
            $reverse.status -ne 'format_consistent') 'fragment ordering distinguishes candidate identity'
    }finally{$reverseStream.Dispose()}
    $writable=[IO.MemoryStream]::new($sample.image,$true)
    try{
        $denied=$false
        try{Test-CObservedCandidateValidation -Source $writable -Candidate $reference | Out-Null}catch{$denied=$true}
        Assert-COrigin $denied 'writable synthetic source refused'
    }finally{$writable.Dispose()}
    Assert-COrigin ((Get-A3DSha256 $sample.image) -ceq $sample.manifest.imageSha256) 'negative control source SHA invariant'
    Write-Host ('C ORIGIN SYNTHETIC METRICS cases={0} discovered_pairs={1} revalidated_pairs={2} consistent={3} rejected={4} exact_original_sha={5} byte_different={6} scout_source_bytes={7} candidate_validation_source_bytes={8} candidate_validation_memory_bytes={9} candidate_read_requests={10} observed_intervals={11} source_unchanged={12} A_receipt_ids_minted=0' -f
        $scorerCases,$baselinePairs,$validatedPairs,$positive,$negative,$originalExact,$byteDifferent,
        $discoverySourceBytes,$validationSourceBytes,$memoryBytes,$readRequests,$readIntervals,$unchanged)
    Write-Host 'PASS: C R5 candidate-specific physical read traces, A receipt boundary, short-read/budget/ordering negative controls'
}
