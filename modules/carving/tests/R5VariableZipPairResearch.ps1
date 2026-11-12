#requires -Version 5.1
# Team C R5 Issue #72: bounded variable-first-slice candidate experiment.
# TEST ONLY. No original SHA, FAT chain, correct locations or file length input.
function Test-CVariableZipPairs {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][IO.Stream]$Source,
        [ValidateRange(512,65536)][int]$WindowBytes=65536,
        [ValidateRange(1,4)][int]$MaxStarts=4,
        [ValidateRange(1,8)][int]$MaxTails=8,
        [ValidateRange(1,16)][int]$MaxPairs=16,
        [ValidateRange(512,81920)][long]$MaxSourceBytes=81920,
        [ValidateRange(6144,98304)][long]$MaxValidationBytes=98304,
        [ValidateRange(100,30000)][int]$MaxMilliseconds=30000,
        [switch]$IncludeStartPhasePlusTwo
    )
    if(-not $Source.CanRead -or -not $Source.CanSeek -or $Source.CanWrite) {
        throw 'CVariable requires non-writable readable seekable artificial stream'
    }
    if($Source.Length -gt 2097152L) {throw 'CVariable tiny source exceeds 2MiB'}
    # Same finite hypotheses are tried for EVERY case, not passed as truth.
    [int[]]$tailPhases=@(0,1)
    # Default-OFF research ablation: expand only local PK-start phase,
    # never alter EOCD phase or the predeclared first-piece lengths.
    [int[]]$startPhases=if($IncludeStartPhasePlusTwo){@(0,1,2)}else{@(0,1)}
    [int[]]$firstSizes=@(512,544)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $starts=New-Object 'System.Collections.Generic.List[long]'
    $tails=New-Object 'System.Collections.Generic.List[object]'
    $records=New-Object 'System.Collections.Generic.List[object]'
    $physical=0L;$requests=0;$sectors=0;$pairs=0;$memoryBytes=0L
    $status='ok';$stop='none'
    if($WindowBytes%512 -ne 0 -or $WindowBytes -gt $Source.Length){
        $status='partial';$stop='search.window_unavailable'
    }elseif($MaxSourceBytes -lt $WindowBytes){
        $status='partial';$stop='search.scout_budget_unavailable'
    }
    if($status -eq 'ok'){
        for($sector=0L;$sector -lt $WindowBytes;$sector+=512L){
            if($watch.ElapsedMilliseconds -ge $MaxMilliseconds){$status='partial';$stop='search.time_limit';break}
            [byte[]]$block=New-Object byte[] 512
            [void]$Source.Seek($sector,[IO.SeekOrigin]::Begin)
            $done=0
            while($done -lt 512){
                if($physical+512-$done -gt $MaxSourceBytes){$status='partial';$stop='search.source_limit';break}
                $n=$Source.Read($block,$done,512-$done);$requests++
                if($n -le 0){$status='partial';$stop='search.short_read';break}
                $physical+=[long]$n;$done+=$n
            }
            if($status -ne 'ok'){break}
            $sectors++
            foreach($phase in $startPhases){
                if($block[$phase] -eq 0x50 -and $block[$phase+1] -eq 0x4b -and $block[$phase+2] -eq 3 -and $block[$phase+3] -eq 4){
                    $starts.Add([long]($sector+$phase))
                    if($starts.Count -gt $MaxStarts){$status='partial';$stop='search.start_limit';break}
                }
            }
            if($status -ne 'ok'){break}
            for($k=0;$k -le 490;$k++){
                if($block[$k] -ne 0x50 -or $block[$k+1] -ne 0x4b -or $block[$k+2] -ne 5 -or $block[$k+3] -ne 6){continue}
                $comment=[int][BitConverter]::ToUInt16($block,$k+20)
                foreach($phase in $tailPhases){
                    if($k -lt $phase){continue}
                    $suffix=[int]($k+22+$comment-$phase)
                    if($suffix -lt 22 -or $suffix -gt 512){continue}
                    if($sector+$phase+$suffix -gt $Source.Length){continue}
                    $tails.Add([pscustomobject]@{offsetBytes=[long]($sector+$phase);lengthBytes=$suffix})
                    if($tails.Count -gt $MaxTails){$status='partial';$stop='search.tail_limit';break}
                }
                if($status -ne 'ok'){break}
            }
            if($status -ne 'ok'){break}
        }
    }
    if($status -eq 'ok' -and $starts.Count*$tails.Count*$firstSizes.Count -gt $MaxPairs){
        $status='partial';$stop='search.pair_limit'
    }
    if($status -eq 'ok'){
        foreach($first in $starts){
            foreach($tail in $tails){
                foreach($firstLen in $firstSizes){
                    if($watch.ElapsedMilliseconds -ge $MaxMilliseconds){$status='partial';$stop='search.time_limit';break}
                    $second=[long]$tail.offsetBytes
                    $secondLen=[int]$tail.lengthBytes
                    if($second -lt ($first+$firstLen) -and $first -lt ($second+$secondLen)){continue}
                    $total=$firstLen+$secondLen
                    if($total -gt 1056 -or $first+$firstLen -gt $Source.Length){continue}
                    if($physical+$total -gt $MaxSourceBytes){$status='partial';$stop='search.source_limit';break}
                    if($memoryBytes+6144L -gt $MaxValidationBytes){$status='partial';$stop='search.validation_limit';break}
                    [byte[]]$combined=New-Object byte[] $total
                    foreach($part in @(
                        [pscustomobject]@{at=$first;count=$firstLen;dest=0},
                        [pscustomobject]@{at=$second;count=$secondLen;dest=$firstLen}
                    )){
                        [void]$Source.Seek([long]$part.at,[IO.SeekOrigin]::Begin)
                        $done=0
                        while($done -lt $part.count){
                            $n=$Source.Read($combined,($part.dest+$done),($part.count-$done));$requests++
                            if($n -le 0){$status='partial';$stop='search.short_pair_read';break}
                            $physical+=[long]$n;$done+=$n
                        }
                        if($status -ne 'ok'){break}
                    }
                    if($status -ne 'ok'){break}
                    $mem=[IO.MemoryStream]::new($combined,$false)
                    try{
                        $check=Get-ChappyCarvingCandidates -Stream $mem -StartOffset 0 -MaxScanBytes $total -MaxFileBytes 4096 -MaxCandidates 4 -MaxProbes 8 -MaxProbeBytes 4096 -ExtraValidationReadBytes 4096 -MaxWorkMilliseconds 5000 -EnableSmallDeflateCrc
                        $memoryBytes += [long]$check.metrics.bytesRead
                    }finally{$mem.Dispose()}
                    if($memoryBytes -gt $MaxValidationBytes){throw 'CVariable memory read quota accounting invariant'}
                    $pairs++
                    $hits=@($check.items | Where-Object {$_.format -eq '3mf' -and $_.offsetBytes -eq 0 -and $_.lengthBytes -eq $total -and $_.crc32Status -eq 'match' -and $_.confidence -eq 'verified' -and $_.integrityScope -eq 'structural_only_not_original_file_integrity'})
                    $possible=($hits.Count -eq 1 -and $check.status -eq 'ok' -and -not $check.scanIncomplete)
                    $sha=$null
                    if($possible){
                        $h=[Security.Cryptography.SHA256]::Create()
                        try{$sha=[BitConverter]::ToString($h.ComputeHash($combined)).Replace('-','')}
                        finally{$h.Dispose()}
                    }
                    $records.Add([pscustomobject]@{
                        firstOffset=[long]$first;secondOffset=$second
                        firstBytes=$firstLen;secondBytes=$secondLen
                        possible=$possible
                        reason=$(if($possible){'pair.zip_crc_consistent'}else{'pair.format_rejected'})
                        candidateSha256=$sha
                        originalIdentity='unknown'
                        integrityScope='structural_only_not_original_file_integrity'
                        sourceSpans=@(
                            [pscustomobject]@{offsetBytes=[long]$first;lengthBytes=$firstLen;origin='observed_synthetic_source'},
                            [pscustomobject]@{offsetBytes=$second;lengthBytes=$secondLen;origin='observed_synthetic_source'}
                        )
                    })
                }
                if($status -ne 'ok'){break}
            }
            if($status -ne 'ok'){break}
        }
    }
    $positive=@($records.ToArray() | Where-Object {$_.possible}).Count
    $decision=if($status -ne 'ok'){'incomplete'}elseif($positive -eq 0){'unknown'}elseif($positive -eq 1){'one_possible'}else{'ambiguous'}
    $watch.Stop()
    return [pscustomobject]@{
        status=$status;decision=$decision
        items=$(if($status -eq 'ok'){@($records.ToArray())}else{@()})
        metrics=[pscustomobject]@{
            sectorProbes=$sectors;startCandidates=$starts.Count;tailCandidates=$tails.Count
            pairAttempts=$pairs;sourceBytesRead=$physical;readRequests=$requests
            validatorBytesRead=$memoryBytes;elapsedMilliseconds=$watch.ElapsedMilliseconds;stopCode=$stop
        }
    }
}
