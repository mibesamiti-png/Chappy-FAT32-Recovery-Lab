#requires -Version 5.1
# Team C R5/C5-03: guarded reusable bounded non-oracle two-fragment 3MF
# candidate discovery. Promoted from *this repository's own C research*;
# never receives oracle offsets, original SHA, FAT chain or file lengths.
# NOT a general ZIP/3MF restoration tool and NEVER an original-file winner.
Set-StrictMode -Version Latest
function Get-ChappyFragmentCandidates {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][IO.Stream]$Source,
        [switch]$EnableFragmentEvidence,
        [ValidateRange(512,65536)][int]$WindowBytes=65536,
        [ValidateRange(1,4)][int]$MaxStarts=4,
        [ValidateRange(1,8)][int]$MaxTails=8,
        [ValidateRange(1,16)][int]$MaxPairs=16,
        [ValidateRange(512,81920)][long]$MaxSourceBytes=81920,
        [ValidateRange(6144,98304)][long]$MaxValidationBytes=98304,
        [ValidateRange(100,30000)][int]$MaxMilliseconds=30000,
        [switch]$IncludeStartPhasePlusTwo,
        [switch]$IncludeFirstPiece560
    )
    # Deny-by-default with NO reads/seek/length calls on the supplied stream.
    if(-not $EnableFragmentEvidence){
        return [pscustomobject]@{
            schemaVersion='1';team='C';status='disabled';decision='unknown'
            scanIncomplete=$true;originalIdentity='unknown';selectedOriginal=$null
            canAutoSelectOriginal=$false;items=@();warnings=@('fragment.optin_required')
            metrics=[pscustomobject]@{
                sectorProbes=0;startCandidates=0;tailCandidates=0;pairAttempts=0
                returnedCandidateCount=0;sourceBytesRead=0L;readRequests=0
                validatorBytesRead=0L;elapsedMilliseconds=0;stopCode='fragment.optin_required'
            }
        }
    }
    if(-not $Source.CanRead -or -not $Source.CanSeek -or $Source.CanWrite) {
        throw 'CFragment requires non-writable readable seekable Stream'
    }
    if($Source.Length -gt 2097152L) {throw 'CFragment tiny source exceeds 2MiB'}
    Import-Module (Join-Path $PSScriptRoot 'Chappy.Carving.psm1') -ErrorAction Stop
    # Same finite hypotheses are tried for EVERY case, not passed as truth.
    [int[]]$tailPhases=@(0,1)
    # Default-OFF research ablation: expand only local PK-start phase,
    # never alter EOCD phase or the predeclared first-piece lengths.
    [int[]]$startPhases=if($IncludeStartPhasePlusTwo){@(0,1,2)}else{@(0,1)}
    # Independent default-OFF single-size ablation; every case sees the
    # same non-oracle length hypotheses, never a fixture-specific hint.
    [int[]]$firstSizes=if($IncludeFirstPiece560){@(512,544,560)}else{@(512,544)}
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
                    # Only a separate synthetic scorer may compare original SHA.
                    $records.Add([pscustomobject]@{
                        firstOffset=[long]$first;secondOffset=$second
                        firstBytes=$firstLen;secondBytes=$secondLen
                        possible=$possible
                        reason=$(if($possible){'pair.zip_crc_consistent'}else{'pair.format_rejected'})
                        originalIdentity='unknown'
                        integrityScope='structural_only_not_original_file_integrity'
                        sourceSpans=@(
                            [pscustomobject]@{offsetBytes=[long]$first;lengthBytes=$firstLen;origin='source_observed_unattested'},
                            [pscustomobject]@{offsetBytes=$second;lengthBytes=$secondLen;origin='observed_synthetic_source'}
                        )
                    })
                }
                if($status -ne 'ok'){break}
            }
            if($status -ne 'ok'){break}
        }
    }
    $accepted=New-Object 'System.Collections.Generic.List[object]'
    if($status -eq 'ok'){
        foreach($record in $records){
            if(-not $record.possible){continue}
            $a=$record.sourceSpans[0];$b=$record.sourceSpans[1]
            $key=('3mf:{0}+{1},{2}+{3}' -f $a.offsetBytes,$a.lengthBytes,$b.offsetBytes,$b.lengthBytes)
            $accepted.Add([pscustomobject]@{
                candidateKey=$key;format='3mf';offsetBytes=[long]$a.offsetBytes
                lengthBytes=[long]($a.lengthBytes+$b.lengthBytes)
                confidence='probable';possible=$true;reason='pair.zip_crc_consistent'
                integrityScope='structural_only_not_original_file_integrity'
                originalIdentity='unknown';sourceOrigin='unattributed_without_A_meter'
                firstOffset=[long]$a.offsetBytes;firstBytes=[int]$a.lengthBytes
                secondOffset=[long]$b.offsetBytes;secondBytes=[int]$b.lengthBytes
                sourceSpans=@($a,$b)
                evidence=@('zip.local_header','zip.central_directory','zip.eocd','zip.crc_consistent')
                truncated=$false
            })
        }
    }
    $positive=$accepted.Count
    $decision=if($status -ne 'ok'){'incomplete'}elseif($positive -eq 0){'unknown'}elseif($positive -eq 1){'one_possible'}else{'ambiguous'}
    $watch.Stop()
    return [pscustomobject]@{
        schemaVersion='1';team='C';status=$status;decision=$decision
        scanIncomplete=($WindowBytes -lt $Source.Length -or $status -ne 'ok')
        originalIdentity='unknown';selectedOriginal=$null;canAutoSelectOriginal=$false
        # Never choose a unique "original"; one_possible means a single
        # *format-consistent* physical hypothesis among the bounded trials.
        items=$(if($status -eq 'ok'){@($accepted.ToArray())}else{@()})
        warnings=$(if($status -eq 'ok'){@('fragment.unscanned_source_unknown')}else{@($stop)})
        metrics=[pscustomobject]@{
            sectorProbes=$sectors;startCandidates=$starts.Count;tailCandidates=$tails.Count
            pairAttempts=$pairs;returnedCandidateCount=$positive
            sourceBytesRead=$physical;readRequests=$requests
            validatorBytesRead=$memoryBytes;elapsedMilliseconds=$watch.ElapsedMilliseconds;stopCode=$stop
        }
    }
}
Export-ModuleMember -Function Get-ChappyFragmentCandidates
