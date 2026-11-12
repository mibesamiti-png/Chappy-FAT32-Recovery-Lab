#requires -Version 5.1
# Team C Issue #72: TEST-ONLY instrumented candidate-specific validation.
# This is NOT an A-issued physical meter, event receipt or authenticity proof.
# Only direct nonwritable Stream.Read returns become observed intervals.
function Test-CObservedCandidateValidation {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][IO.Stream]$Source,
        [Parameter(Mandatory=$true)][object]$Candidate,
        [ValidateRange(1,2048)][long]$MaxSourceBytes=2048,
        [ValidateRange(1,8192)][long]$MaxValidatorBytes=8192,
        [ValidateRange(100,5000)][int]$MaxMilliseconds=5000
    )
    if(-not $Source.CanRead -or -not $Source.CanSeek -or $Source.CanWrite){
        throw 'CObservedValidation requires a nonwritable readable seekable stream'
    }
    if($Source.Length -gt 2097152L){throw 'CObservedValidation only accepts tiny synthetic sources'}
    if($null -eq $Candidate.PSObject.Properties['sourceSpans'] -or
       @($Candidate.sourceSpans).Count -ne 2){
        throw 'CObservedValidation requires two observed candidate spans'
    }
    $spans=@($Candidate.sourceSpans)
    $ranges=New-Object 'System.Collections.Generic.List[object]'
    $length=0
    foreach($span in $spans){
        $at=[long]$span.offsetBytes
        $count=[long]$span.lengthBytes
        if($at -lt 0 -or $count -lt 1 -or $count -gt 512 -or
           $at -gt $Source.Length-$count){
            throw 'CObservedValidation candidate span outside stream or size cap'
        }
        $length+=[int]$count
        $ranges.Add([pscustomobject]@{offsetBytes=$at;lengthBytes=[int]$count})
    }
    $a=$ranges[0];$b=$ranges[1]
    if($a.offsetBytes -lt ($b.offsetBytes+$b.lengthBytes) -and
       $b.offsetBytes -lt ($a.offsetBytes+$a.lengthBytes)){
        throw 'CObservedValidation cannot re-read overlapping physical spans'
    }
    if($length -gt 1024){throw 'CObservedValidation joined-byte cap'}
    # Exact ordered candidate identity, never a claim of A-issued event IDs.
    $key=('3mf:{0}+{1},{2}+{3}' -f $a.offsetBytes,$a.lengthBytes,$b.offsetBytes,$b.lengthBytes)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $observed=New-Object 'System.Collections.Generic.List[object]'
    [byte[]]$joined=New-Object byte[] $length
    $physical=0L;$requests=0;$validation=0L;$status='ok';$stop='none'
    $destination=0
    foreach($span in $ranges){
        [void]$Source.Seek([long]$span.offsetBytes,[IO.SeekOrigin]::Begin)
        $done=0
        while($done -lt $span.lengthBytes){
            if($watch.ElapsedMilliseconds -ge $MaxMilliseconds){
                $status='partial';$stop='validation.time_limit';break
            }
            if($physical -ge $MaxSourceBytes){
                $status='partial';$stop='validation.source_byte_limit';break
            }
            $wanted=[int][Math]::Min(($span.lengthBytes-$done),($MaxSourceBytes-$physical))
            if($wanted -le 0){$status='partial';$stop='validation.source_byte_limit';break}
            try{
                $got=$Source.Read($joined,($destination+$done),$wanted)
            }catch{
                $status='partial';$stop='validation.source_read_error';break
            }
            $requests++
            if($got -le 0){
                $status='partial';$stop='validation.short_read';break
            }
            $observed.Add([pscustomobject]@{
                offsetBytes=[long]($span.offsetBytes+$done)
                returnedBytes=[int]$got
                requestedBytes=$wanted
                candidateKey=$key
                consumer='carving'
                purpose='candidate_validation'
            })
            $physical += [long]$got
            $done+=$got
        }
        if($status -ne 'ok'){break}
        $destination += $span.lengthBytes
    }
    $consistent=$false;$candidateSha=$null;$originalIdentity='unknown'
    if($status -eq 'ok'){
        # The production parser's bounded in-memory reads are counted
        # separately. These DO NOT count as additional physical source reads.
        if($MaxValidatorBytes -lt 6144L){
            $status='partial';$stop='validation.memory_quota_not_reserved'
        }elseif($watch.ElapsedMilliseconds -ge $MaxMilliseconds){
            $status='partial';$stop='validation.time_limit'
        }else{
            $memory=[IO.MemoryStream]::new($joined,$false)
            try{
                $check=Get-ChappyCarvingCandidates -Stream $memory -StartOffset 0 -MaxScanBytes $length -MaxFileBytes 4096 -MaxCandidates 4 -MaxProbes 8 -MaxProbeBytes 4096 -ExtraValidationReadBytes 4096 -MaxWorkMilliseconds 2500 -EnableSmallDeflateCrc
                $validation=[long]$check.metrics.bytesRead
            }finally{$memory.Dispose()}
            if($validation -gt $MaxValidatorBytes){throw 'CObservedValidation in-memory accounting invariant'}
            $found=@($check.items | Where-Object {
                $_.format -eq '3mf' -and $_.offsetBytes -eq 0 -and
                $_.lengthBytes -eq $length -and $_.crc32Status -eq 'match' -and
                $_.confidence -eq 'verified' -and
                $_.integrityScope -eq 'structural_only_not_original_file_integrity'
            })
            if($check.status -ne 'ok' -or $check.scanIncomplete){
                $status='partial';$stop='validation.parser_incomplete'
            }else{
                $consistent=($found.Count -eq 1)
                if($consistent){
                    $hasher=[Security.Cryptography.SHA256]::Create()
                    try{$candidateSha=[BitConverter]::ToString($hasher.ComputeHash($joined)).Replace('-','')}
                    finally{$hasher.Dispose()}
                }
            }
        }
    }
    $watch.Stop()
    return [pscustomobject]@{
        status=$(if($status -eq 'ok'){$(if($consistent){'format_consistent'}else{'format_rejected'})}else{'partial'})
        decision=$(if($status -eq 'ok'){$(if($consistent){'possible'}else{'unknown'})}else{'incomplete'})
        reason=$stop
        candidateKey=$key
        candidateSha256=$candidateSha
        sourceSpans=@($ranges.ToArray())
        # No evidenceId or sourceToken exists here: ONLY A mints receipts.
        originStatus='unattributed_pending_A_meter_receipt'
        originalIdentity=$originalIdentity
        integrityScope='structural_only_not_original_file_integrity'
        observedPhysicalReads=@($observed.ToArray())
        metrics=[pscustomobject]@{
            sourceBytesRead=$physical;sourceReadRequests=$requests
            sourceObservedIntervals=$observed.Count
            memoryValidatorBytesRead=$validation
            elapsedMilliseconds=$watch.ElapsedMilliseconds
            stopCode=$stop
        }
    }
}
