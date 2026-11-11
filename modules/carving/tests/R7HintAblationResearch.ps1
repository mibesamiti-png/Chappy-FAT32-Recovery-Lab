#requires -Version 5.1
# Team C R7, Issue #61: research-only first-offset ablation, synthetic tests.
# Not an exported or default-enabled production API.
function Test-R7NoFirstOffsetSynthetic {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][IO.Stream]$Source,
        [ValidateSet('gcode','3mf')][string]$ExpectedFormat,
        [ValidateRange(1,512)][int]$SecondBytes,
        [ValidateRange(512,131072)][int]$SearchBytes=131072,
        [ValidateRange(1,2)][int]$MaxStarts=2,
        [ValidateRange(1024,401408)][long]$MaxSourceBytes=401408,
        [ValidateRange(9216,147456)][long]$MaxValidationBytes=147456,
        [ValidateRange(100,60000)][int]$MaxMilliseconds=30000
    )
    if (-not $Source.CanRead -or -not $Source.CanSeek -or $Source.CanWrite) {
        throw 'R7 research requires non-writable readable seekable synthetic Stream'
    }
    if ($SearchBytes % 512 -ne 0 -or $SearchBytes -gt $Source.Length) {
        throw 'R7 artificial grid window outside stream or unaligned'
    }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $all=New-Object 'System.Collections.Generic.List[object]'
    $sourceBytes=0L;$validationBytes=0L;$grid=0;$pairs=0;$evaluated=0
    $status='ok';$code='none'
    # R0 correction: production carver correctly reports incomplete
    # full-file/ZIP validation on fragmented objects. Start-location research
    # must only discover raw file anchors and NOT upgrade them to full files.
    # Scan every synthetic 512B boundary without privileged original offsets.
    if ([long]$SearchBytes -gt $MaxSourceBytes) {
        $watch.Stop()
        return [pscustomobject]@{
            status='partial';decision='incomplete';candidates=@()
            metrics=[pscustomobject]@{
                startsProposed=0;startsEvaluated=0;scoutBytesRead=0L
                sourceBytesRead=0L;validationBytesRead=0L;gridProbes=0
                pairsEvaluated=0;elapsedMilliseconds=$watch.ElapsedMilliseconds
                stopCode='search.source_budget_not_reserved'
            }
        }
    }
    $starts=New-Object 'System.Collections.Generic.List[long]'
    $seen=New-Object 'System.Collections.Generic.HashSet[long]'
    $scoutOffsets=0
    $scoutBytes=0L
    for($at=0L;$at -lt [long]$SearchBytes;$at+=512L) {
        if($watch.ElapsedMilliseconds -ge ($MaxMilliseconds-100)){
            $status='partial';$code='search.time_budget_exhausted';break
        }
        if($sourceBytes+512L -gt $MaxSourceBytes){
            $status='partial';$code='search.source_limit';break
        }
        $chunk=New-Object byte[] 512
        [void]$Source.Seek($at,[IO.SeekOrigin]::Begin)
        $n=0
        while($n -lt 512){
            $read=$Source.Read($chunk,$n,512-$n)
            if($read -le 0){$status='partial';$code='search.short_read';break}
            $n+=$read;$sourceBytes += [long]$read
        }
        if($status -ne 'ok'){break}
        $scoutOffsets++
        $signal=$false
        if($ExpectedFormat -eq '3mf'){
            $signal=($chunk[0] -eq 0x50 -and $chunk[1] -eq 0x4b -and
                     $chunk[2] -eq 0x03 -and $chunk[3] -eq 0x04)
        } else {
            $head=[Text.Encoding]::ASCII.GetString($chunk,0,64)
            # Same broad semantic start families as C's scanner, independently
            # implemented solely for bounded artificial-grid discovery.
            $signal=($head -match '^(?:;\s*(?:FLAVOR:|generated|HEADER_START|BambuStudio)|G28\b|M104\b|M140\b|M73\b)')
        }
        if($signal -and $seen.Add([long]$at)){$starts.Add([long]$at)}
        if($starts.Count -gt $MaxStarts){
            $status='partial';$code='search.start_limit';break
        }
    }
    $scoutBytes=$sourceBytes
    if($status -ne 'ok'){
        # Do not validate a truncated/cherry-picked prefix of candidate starts.
    }elseif($starts.Count -gt $MaxStarts){
        $status='partial';$code='search.start_limit'
    }else{
        foreach($first in $starts){
            if($watch.ElapsedMilliseconds -ge $MaxMilliseconds-100){
                $status='partial';$code='search.time_budget_exhausted';break
            }
            # Every R6 scan can consume at most 135168B of source data.
            if($sourceBytes+135168L -gt $MaxSourceBytes){
                $status='partial';$code='search.source_limit';break
            }
            $remaining=[int]($MaxMilliseconds-$watch.ElapsedMilliseconds)
            $trial=Test-R6NonOracleSyntheticTailSearch -Source $Source -FirstOffset $first -FirstBytes 512 -SecondBytes $SecondBytes -ExpectedFormat $ExpectedFormat -SearchStart 0 -SearchBytes $SearchBytes -MaxOffsets 256 -MaxPairs 8 -MaxSourceBytes 135168 -MaxValidationBytes 73728 -MaxMilliseconds ([int][Math]::Max(100,[Math]::Min(30000,$remaining)))
            $evaluated++
            $sourceBytes += [long]$trial.metrics.sourceBytesRead
            $validationBytes += [long]$trial.metrics.formatValidationBytesRead
            $grid += [int]$trial.metrics.sampledOffsets
            $pairs += [int]$trial.metrics.evaluatedPairs
            if($sourceBytes -gt $MaxSourceBytes -or $validationBytes -gt $MaxValidationBytes){
                throw 'R7 aggregate byte accounting invariant failed'
            }
            foreach($p in $trial.candidates){
                $all.Add([pscustomobject]@{
                    firstOffset=$first;secondOffset=$p.offset
                    possible=[bool]$p.possible;sha256=$p.sha256;code=$p.code
                })
            }
            if($trial.status -ne 'ok'){
                $status='partial';$code='search.tail_incomplete';break
            }
        }
    }
    $count=@($all.ToArray() | Where-Object {$_.possible}).Count
    $decision=if($status -ne 'ok'){'incomplete'}elseif($count -eq 0){'unknown'}elseif($count -eq 1){'one_possible'}else{'ambiguous'}
    $watch.Stop()
    return [pscustomobject]@{
        status=$status;decision=$decision;candidates=@($all.ToArray())
        metrics=[pscustomobject]@{
            startsProposed=$starts.Count;startsEvaluated=$evaluated
            scoutBytesRead=$scoutBytes
            sourceBytesRead=$sourceBytes;validationBytesRead=$validationBytes
            gridProbes=$grid;pairsEvaluated=$pairs
            elapsedMilliseconds=$watch.ElapsedMilliseconds;stopCode=$code
        }
    }
}

# The reference method receives a true first offset. R7 does NOT.
# Ground truth is accessed only in scoring, never in the R7 search function.
$r7TP=0;$r7FP=0;$r7FN=0;$r7TN=0
$r7Unique=0;$r7Ambiguous=0;$r7Unknown=0;$r7Incomplete=0
$r7Source=0L;$r7ScoutRead=0L;$r7MemoryRead=0L;$r7Grid=0;$r7Pairs=0;$r7Starts=0
$r7ReferenceReads=0L
foreach($case in $r6Cases){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$before=[BitConverter]::ToString($sha.ComputeHash($case.bytes)).Replace('-','')}
    finally{$sha.Dispose()}
    $reference=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($case.bytes,$false))
    try{
        $originalR6=Test-R6NonOracleSyntheticTailSearch -Source $reference -FirstOffset $case.first -FirstBytes 512 -SecondBytes $case.tailBytes -ExpectedFormat $case.kind -SearchBytes $case.searchBytes -MaxOffsets 256 -MaxPairs 8 -MaxSourceBytes 135168 -MaxValidationBytes 73728 -MaxMilliseconds 30000
        Assert ($reference.BytesRead -eq $originalR6.metrics.sourceBytesRead -and $reference.BytesRead -le 401408) ($case.name+': R6 known-first-offset reference is counted')
        $r7ReferenceReads += $reference.BytesRead
    }finally{$reference.Dispose()}
    $input=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($case.bytes,$false))
    try{
        $result=Test-R7NoFirstOffsetSynthetic -Source $input -ExpectedFormat $case.kind -SecondBytes $case.tailBytes -SearchBytes $case.searchBytes -MaxStarts 2 -MaxSourceBytes 401408 -MaxValidationBytes 147456
        Assert ($input.BytesRead -eq $result.metrics.sourceBytesRead -and $input.BytesRead -le 401408) ($case.name+': R7 bytes independently measured')
        Assert ($result.metrics.gridProbes -le 512 -and $result.metrics.pairsEvaluated -le 16) ($case.name+': R7 bounded grid and pairs')
        Assert ($result.metrics.validationBytesRead -le 147456 -and -not $input.CanWrite) ($case.name+': R7 bounded memory validator and source nonwritable')
        $r7Source += $input.BytesRead
        $r7ScoutRead += [long]$result.metrics.scoutBytesRead
        $r7MemoryRead += [long]$result.metrics.validationBytesRead
        $r7Grid += [int]$result.metrics.gridProbes
        $r7Pairs += [int]$result.metrics.pairsEvaluated
        $r7Starts += [int]$result.metrics.startsProposed
        $accepted=@($result.candidates | Where-Object {$_.possible})
        $correct=@($accepted | Where-Object {$_.sha256 -eq $case.originalHash -and $_.firstOffset -eq $case.first}).Count
        $r7TP += $correct
        $r7FP += ($accepted.Count-$correct)
        if($correct -eq 0){$r7FN++}
        $r7TN += @($result.candidates | Where-Object {-not $_.possible}).Count
        switch($result.decision){
            'unknown' {$r7Unknown++}
            'ambiguous' {$r7Ambiguous++}
            'one_possible' {$r7Unique++}
            'incomplete' {$r7Incomplete++}
        }
        Write-Host ("R7 CASE {0} starts={1} decision={2} accepted={3} correct={4} source_bytes={5}" -f $case.name,$result.metrics.startsProposed,$result.decision,$accepted.Count,$correct,$result.metrics.sourceBytesRead)
    }finally{$input.Dispose()}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$after=[BitConverter]::ToString($sha.ComputeHash($case.bytes)).Replace('-','')}
    finally{$sha.Dispose()}
    Assert ($before -eq $after) ($case.name+': artificial bytes unchanged')
}
Assert ($r7TP -le 4 -and $r7FP -ge 0 -and $r7FN -ge 1) 'R7 cannot exceed known candidate truth'
Write-Host ("R7 SYNTHETIC ABLATION METRICS cases=5 TP={0} FP={1} FN={2} TN={3} unique={4} ambiguous={5} unknown={6} incomplete={7} start_proposals={8} pair_trials={9} grid_probes={10} scout_bytes={11} source_bytes={12} in_memory_bytes={13} r6_reference_bytes={14}" -f $r7TP,$r7FP,$r7FN,$r7TN,$r7Unique,$r7Ambiguous,$r7Unknown,$r7Incomplete,$r7Starts,$r7Pairs,$r7Grid,$r7ScoutRead,$r7Source,$r7MemoryRead,$r7ReferenceReads)
Write-Host 'PASS: R7 synthetic first-offset ablation, measured reference, bounded starts and independent truth'

$writable=[IO.MemoryStream]::new($split,$true)
try{
    $blocked=$false
    try{Test-R7NoFirstOffsetSynthetic -Source $writable -ExpectedFormat gcode -SecondBytes $r5GRest | Out-Null}
    catch{$blocked=$true}
    Assert $blocked 'R7 refuses writable input'
}finally{$writable.Dispose()}
$tiny=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($split,$false))
try{
    $partial=Test-R7NoFirstOffsetSynthetic -Source $tiny -ExpectedFormat gcode -SecondBytes $r5GRest -MaxSourceBytes 1024
    Assert ($partial.decision -eq 'incomplete' -and $partial.metrics.sourceBytesRead -eq 0 -and $tiny.BytesRead -eq 0) 'R7 tiny scout budget fails closed before reads'
}finally{$tiny.Dispose()}
Write-Host 'PASS: R7 writable source rejected and scout budget exhaustion is incomplete'
