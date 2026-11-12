#requires -Version 5.1
# Team C Issue #72: research-only synthetic 2-piece 3MF candidates.
# The helper receives no oracle offsets, FAT link, true length, or SHA.
function Test-CM01FiniteZipPairs {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][IO.Stream]$Source,
        [ValidateRange(512,65536)][int]$WindowBytes=65536,
        [ValidateRange(1,4)][int]$MaxStarts=4,
        [ValidateRange(1,8)][int]$MaxTails=8,
        [ValidateRange(1,8)][int]$MaxPairs=8,
        [ValidateRange(512,73728)][long]$MaxSourceBytes=73728,
        [ValidateRange(5120,40960)][long]$MaxValidationBytes=40960,
        [ValidateRange(100,30000)][int]$MaxMilliseconds=30000
    )
    if(-not $Source.CanRead -or -not $Source.CanSeek -or $Source.CanWrite) {
        throw 'CM01 requires a non-writable, seekable synthetic Stream'
    }
    if($Source.Length -gt 2097152L) {
        throw 'CM01 experimental source exceeds tiny artificial image cap'
    }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $starts=New-Object 'System.Collections.Generic.List[long]'
    $tails=New-Object 'System.Collections.Generic.List[object]'
    $items=New-Object 'System.Collections.Generic.List[object]'
    $bytes=0L;$validatorBytes=0L;$sectors=0;$pairs=0
    $status='ok';$stop='none'
    if($WindowBytes%512 -ne 0 -or $WindowBytes -gt $Source.Length) {
        $status='partial';$stop='search.window_unavailable'
    } elseif($MaxSourceBytes -lt $WindowBytes) {
        $status='partial';$stop='search.scout_budget_unavailable'
    }
    if($status -eq 'ok') {
        for($at=0L;$at -lt [long]$WindowBytes;$at+=512L) {
            if($watch.ElapsedMilliseconds -ge $MaxMilliseconds){
                $status='partial';$stop='search.time_limit';break
            }
            if($bytes+512L -gt $MaxSourceBytes) {
                $status='partial';$stop='search.source_limit';break
            }
            [byte[]]$chunk=New-Object byte[] 512
            [void]$Source.Seek($at,[IO.SeekOrigin]::Begin)
            $n=0
            while($n -lt 512) {
                $got=$Source.Read($chunk,$n,512-$n)
                if($got -le 0) {$status='partial';$stop='search.short_read';break}
                $bytes+=[long]$got;$n+=$got
            }
            if($status -ne 'ok'){break}
            $sectors++
            if($chunk[0] -eq 0x50 -and $chunk[1] -eq 0x4b -and
               $chunk[2] -eq 0x03 -and $chunk[3] -eq 0x04){
                $starts.Add([long]$at)
                if($starts.Count -gt $MaxStarts){
                    $status='partial';$stop='search.start_limit';break
                }
            }
            for($k=0;$k -le 490;$k++){
                if($chunk[$k] -ne 0x50 -or $chunk[$k+1] -ne 0x4b -or
                   $chunk[$k+2] -ne 0x05 -or $chunk[$k+3] -ne 0x06){continue}
                $comment=[int][BitConverter]::ToUInt16($chunk,$k+20)
                $suffix=[int]($k+22+$comment)
                if($suffix -le 0 -or $suffix -gt 512){
                    $status='partial';$stop='search.eocd_spans_sector';break
                }
                $tails.Add([pscustomobject]@{offsetBytes=[long]$at;lengthBytes=$suffix})
                if($tails.Count -gt $MaxTails){
                    $status='partial';$stop='search.tail_limit';break
                }
            }
            if($status -ne 'ok'){break}
        }
    }
    if($status -eq 'ok' -and $starts.Count*$tails.Count -gt $MaxPairs){
        $status='partial';$stop='search.pair_limit'
    }
    if($status -eq 'ok'){
        foreach($first in $starts){
            foreach($last in $tails){
                if($watch.ElapsedMilliseconds -ge $MaxMilliseconds){
                    $status='partial';$stop='search.time_limit';break
                }
                if($first -eq $last.offsetBytes){continue}
                $length=512+[int]$last.lengthBytes
                if($bytes+$length -gt $MaxSourceBytes){
                    $status='partial';$stop='search.source_limit';break
                }
                # Reserve one 1024B scan plus 4096B named validation rereads.
                if($validatorBytes+5120L -gt $MaxValidationBytes){
                    $status='partial';$stop='search.validation_limit';break
                }
                [byte[]]$joined=New-Object byte[] $length
                foreach($part in @(
                    [pscustomobject]@{offset=[long]$first;size=512;index=0},
                    [pscustomobject]@{offset=[long]$last.offsetBytes;size=[int]$last.lengthBytes;index=512}
                )){
                    [void]$Source.Seek($part.offset,[IO.SeekOrigin]::Begin)
                    $done=0
                    while($done -lt $part.size){
                        $got=$Source.Read($joined,($part.index+$done),($part.size-$done))
                        if($got -le 0){$status='partial';$stop='search.short_pair_read';break}
                        $done+=$got;$bytes+=[long]$got
                    }
                    if($status -ne 'ok'){break}
                }
                if($status -ne 'ok'){break}
                $memory=[IO.MemoryStream]::new($joined,$false)
                try{
                    $check=Get-ChappyCarvingCandidates -Stream $memory -StartOffset 0 -MaxScanBytes $length -MaxFileBytes 4096 -MaxCandidates 4 -MaxProbes 8 -MaxProbeBytes 4096 -ExtraValidationReadBytes 4096 -MaxWorkMilliseconds 5000 -EnableSmallDeflateCrc
                    $validatorBytes+=[long]$check.metrics.bytesRead
                }finally{$memory.Dispose()}
                if($validatorBytes -gt $MaxValidationBytes){
                    throw 'CM01 validator accounting invariant'
                }
                $pairs++
                $match=@($check.items | Where-Object {
                    $_.format -eq '3mf' -and $_.offsetBytes -eq 0 -and
                    $_.lengthBytes -eq $length -and $_.crc32Status -eq 'match' -and
                    $_.confidence -eq 'verified' -and
                    $_.integrityScope -eq 'structural_only_not_original_file_integrity'
                })
                $possible=($match.Count -eq 1 -and $check.status -eq 'ok' -and -not $check.scanIncomplete)
                $hash=$null
                if($possible){
                    $sha=[Security.Cryptography.SHA256]::Create()
                    try{$hash=[BitConverter]::ToString($sha.ComputeHash($joined)).Replace('-','')}
                    finally{$sha.Dispose()}
                }
                $items.Add([pscustomobject]@{
                    firstOffset=[long]$first;secondOffset=[long]$last.offsetBytes
                    firstBytes=512;secondBytes=[int]$last.lengthBytes
                    possible=$possible
                    reason=$(if($possible){'pair.zip_crc_consistent'}else{'pair.format_rejected'})
                    integrityScope='structural_only_not_original_file_integrity'
                    originalIdentity='unknown'
                    candidateSha256=$hash
                    sourceSpans=@(
                        [pscustomobject]@{offsetBytes=[long]$first;lengthBytes=512},
                        [pscustomobject]@{offsetBytes=[long]$last.offsetBytes;lengthBytes=[int]$last.lengthBytes}
                    )
                })
            }
            if($status -ne 'ok'){break}
        }
    }
    $possibleCount=@($items.ToArray() | Where-Object {$_.possible}).Count
    $decision=if($status -ne 'ok'){'incomplete'}elseif($possibleCount -eq 0){'unknown'}elseif($possibleCount -eq 1){'one_possible'}else{'ambiguous'}
    $watch.Stop()
    return [pscustomobject]@{
        status=$status;decision=$decision;items=@($items.ToArray())
        metrics=[pscustomobject]@{
            sampledSectors=$sectors;startCandidates=$starts.Count;tailCandidates=$tails.Count
            pairsEvaluated=$pairs;sourceBytesRead=$bytes;validatorBytesRead=$validatorBytes
            elapsedMilliseconds=$watch.ElapsedMilliseconds;stopCode=$stop
        }
    }
}