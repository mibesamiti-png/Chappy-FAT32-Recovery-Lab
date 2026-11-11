#requires -Version 5.1
# R6 experimental non-oracle tail search. This file is dot-sourced by the
# synthetic Team C suite, never exported by the production module.
function Test-R6NonOracleSyntheticTailSearch {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][IO.Stream]$Source,
        [ValidateRange(0,9223372036854775806)][long]$FirstOffset,
        [ValidateRange(1,512)][int]$FirstBytes,
        [ValidateRange(1,512)][int]$SecondBytes,
        [ValidateSet('gcode','3mf')][string]$ExpectedFormat,
        [ValidateRange(0,9223372036854775806)][long]$SearchStart=0,
        [ValidateRange(512,131072)][int]$SearchBytes=131072,
        [ValidateRange(1,256)][int]$MaxOffsets=256,
        [ValidateRange(1,8)][int]$MaxPairs=8,
        [ValidateRange(1024,135168)][long]$MaxSourceBytes=135168,
        [ValidateRange(9216,73728)][long]$MaxValidationBytes=73728,
        [ValidateRange(100,60000)][int]$MaxMilliseconds=30000
    )
    if (-not $Source.CanRead -or -not $Source.CanSeek -or $Source.CanWrite) {
        throw 'R6 research accepts only nonwritable readable seekable synthetic streams'
    }
    if ($SearchBytes % 512 -ne 0 -or $SearchStart % 512 -ne 0) {
        throw 'R6 uses fixed aligned 512-byte artificial grid'
    }
    if ($SearchStart -gt $Source.Length-$SearchBytes -or $FirstOffset -gt $Source.Length-$FirstBytes) {
        throw 'R6 synthetic scan or first fragment outside stream'
    }
    if ($MaxValidationBytes -lt (9216L*$MaxPairs)) {
        throw 'R6 memory validator read budget must reserve worst case for every pair'
    }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $sampled=0
    $bytesRead=0L
    $incomplete=$false
    $stop='none'
    $candidateOffsets=New-Object 'System.Collections.Generic.List[long]'
    $gridCount=[int]($SearchBytes/512)
    for($k=0;$k -lt $gridCount;$k++) {
        if($watch.ElapsedMilliseconds -ge $MaxMilliseconds) {
            $incomplete=$true; $stop='search.time_limit'; break
        }
        if($sampled -ge $MaxOffsets) {
            $incomplete=$true; $stop='search.offset_limit'; break
        }
        $at=$SearchStart+512L*$k
        if ($at -ge $FirstOffset -and $at -lt ($FirstOffset+$FirstBytes)) {continue}
        if ($at -gt $Source.Length-$SecondBytes) {
            $incomplete=$true; $stop='search.window_limit'; break
        }
        if ($bytesRead+$SecondBytes -gt $MaxSourceBytes) {
            $incomplete=$true; $stop='search.source_byte_limit'; break
        }
        $probe=New-Object byte[] $SecondBytes
        [void]$Source.Seek($at,[IO.SeekOrigin]::Begin)
        $n=0
        while($n -lt $SecondBytes) {
            $got=$Source.Read($probe,$n,$SecondBytes-$n)
            if($got -le 0){$incomplete=$true;$stop='search.short_read';break}
            $n+=$got
            $bytesRead+=[long]$got
        }
        if($incomplete){break}
        $sampled++
        $text=[Text.Encoding]::ASCII.GetString($probe)
        $signal=$false
        if($ExpectedFormat -eq 'gcode'){
            $signal=($text -match '^(?:G|M|T)\d+(?:\s|$)' -and $text.Contains([char]10))
        } else {
            $signal=$text.Contains(('PK'+[char]5+[char]6))
        }
        if($signal){
            if($candidateOffsets.Count -ge $MaxPairs){
                $incomplete=$true;$stop='search.pair_limit';break
            }
            $candidateOffsets.Add([long]$at)
        }
    }
    $results=@()
    $validationBytes=0L
    if(-not $incomplete -and $candidateOffsets.Count -gt 0){
        if ($bytesRead+($candidateOffsets.Count*$SecondBytes)+$FirstBytes -gt $MaxSourceBytes) {
            $incomplete=$true;$stop='search.source_byte_limit'
        } else {
            # The existing R5 pair validator is reused only AFTER independent
            # unhinted grid discovery. Its offsets were discovered, not provided.
            $validated=Test-R5FiniteSyntheticPairs -Source $Source -FirstOffset $FirstOffset -FirstBytes $FirstBytes -SecondBytes $SecondBytes -SecondOffsets $candidateOffsets.ToArray() -ExpectedFormat $ExpectedFormat -MaxPairs $MaxPairs -MaxSourceBytes 8192 -MaxMilliseconds 3000
            $results=@($validated.items)
            $bytesRead += [long]$validated.metrics.sourceBytesRead
            $validationBytes=[long]$validated.metrics.validationBytesRead
            if ($bytesRead -gt $MaxSourceBytes -or $validationBytes -gt $MaxValidationBytes) {
                throw 'R6 experimental budget invariant failed'
            }
        }
    }
    $positive=@($results | Where-Object {$_.possible}).Count
    $decision=if($incomplete){'incomplete'}elseif($positive -eq 0){'unknown'}elseif($positive -eq 1){'one_possible'}else{'ambiguous'}
    $watch.Stop()
    return [pscustomobject]@{
        status=$(if($incomplete){'partial'}else{'ok'})
        decision=$decision
        candidates=$results
        metrics=[pscustomobject]@{
            sampledOffsets=$sampled
            prefilteredCandidates=$candidateOffsets.Count
            evaluatedPairs=$results.Count
            sourceBytesRead=$bytesRead
            formatValidationBytesRead=$validationBytes
            elapsedMilliseconds=$watch.ElapsedMilliseconds
            stopCode=$stop
        }
    }
}

# All these invented arrays originate in the deterministic R4/R5 fixture;
# no known true second offset is supplied to the R6 search.
$r6Cases=@(
    [pscustomobject]@{name='gcode_unique';bytes=$split;first=$gStart;tailBytes=$r5GRest;kind='gcode';searchBytes=131072;expected='one_possible';originalHash=$r5GOriginalHash;truthInWindow=$true},
    [pscustomobject]@{name='gcode_decoy';bytes=$r5AmbiguousG;first=$gStart;tailBytes=$r5GRest;kind='gcode';searchBytes=131072;expected='ambiguous';originalHash=$r5GOriginalHash;truthInWindow=$true},
    [pscustomobject]@{name='3mf_unique';bytes=$split;first=$zStart;tailBytes=$r5ZRest;kind='3mf';searchBytes=131072;expected='one_possible';originalHash=$r5ZOriginalHash;truthInWindow=$true},
    [pscustomobject]@{name='3mf_structural_decoy';bytes=$r5AmbiguousZ;first=$zStart;tailBytes=$r5ZRest;kind='3mf';searchBytes=131072;expected='ambiguous';originalHash=$r5ZOriginalHash;truthInWindow=$true},
    [pscustomobject]@{name='3mf_true_tail_outside_scan';bytes=$split;first=$zStart;tailBytes=$r5ZRest;kind='3mf';searchBytes=65536;expected='unknown';originalHash=$r5ZOriginalHash;truthInWindow=$false}
)
$r6TP=0;$r6FP=0;$r6FN=0;$r6TN=0;$r6Unique=0;$r6Ambiguous=0;$r6Unknown=0
$r6Source=0L;$r6Validation=0L;$r6BaselineSource=0L;$r6Sampled=0;$r6Pairs=0
foreach($case in $r6Cases){
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$before=[BitConverter]::ToString($hash.ComputeHash($case.bytes)).Replace('-','')}
    finally{$hash.Dispose()}
    $baselineRead=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($case.bytes,$false))
    try{
        $baseline=Get-ChappyCarvingCandidates -Stream $baselineRead -MaxScanBytes $case.searchBytes -ExtraValidationReadBytes 4096 -MaxFileBytes 1048576 -MaxProbes 256 -MaxCandidates 8 -MaxWorkMilliseconds 30000
        Assert ($baseline.metrics.bytesRead -eq $baselineRead.BytesRead -and $baselineRead.BytesRead -le 135168) ($case.name+': fair source-byte ceiling for baseline')
        $r6BaselineSource+=$baselineRead.BytesRead
        $complete=@($baseline.items | Where-Object {$_.offsetBytes -eq $case.first -and $_.format -eq $case.kind -and $_.lengthBytes -eq (512+$case.tailBytes)})
        Assert ($complete.Count -eq 0) ($case.name+': old scanner cannot join physically separated original')
    }finally{$baselineRead.Dispose()}
    $read=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($case.bytes,$false))
    try{
        $result=Test-R6NonOracleSyntheticTailSearch -Source $read -FirstOffset $case.first -FirstBytes 512 -SecondBytes $case.tailBytes -ExpectedFormat $case.kind -SearchBytes $case.searchBytes -MaxOffsets 256 -MaxPairs 8 -MaxSourceBytes 135168 -MaxValidationBytes 73728 -MaxMilliseconds 30000
        Assert ($result.status -eq 'ok' -and $result.decision -eq $case.expected) ($case.name+': non-oracle classification expected')
        Assert ($read.BytesRead -eq $result.metrics.sourceBytesRead -and $read.BytesRead -le 135168) ($case.name+': R6 actual source bytes match budget')
        Assert ($result.metrics.sampledOffsets -le 256 -and $result.metrics.evaluatedPairs -le 8) ($case.name+': R6 candidate/offset cap')
        Assert ($result.metrics.formatValidationBytesRead -le 73728 -and -not $read.CanWrite) ($case.name+': R6 readonly and validator budget')
        $r6Source+=$read.BytesRead
        $r6Validation+=$result.metrics.formatValidationBytesRead
        $r6Sampled+=$result.metrics.sampledOffsets
        $r6Pairs+=$result.metrics.evaluatedPairs
        $possible=@($result.candidates | Where-Object {$_.possible})
        $trueAccepted=@($possible | Where-Object {$_.sha256 -eq $case.originalHash}).Count
        $falseAccepted=$possible.Count-$trueAccepted
        $r6TP+=$trueAccepted;$r6FP+=$falseAccepted
        if($case.truthInWindow -and $trueAccepted -eq 0){$r6FN++}
        if(-not $case.truthInWindow){$r6FN++}
        $r6TN+=($result.metrics.sampledOffsets-$trueAccepted-$falseAccepted)
        if($result.decision -eq 'one_possible'){$r6Unique++}
        elseif($result.decision -eq 'ambiguous'){$r6Ambiguous++}
        elseif($result.decision -eq 'unknown'){$r6Unknown++}
    }finally{$read.Dispose()}
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$after=[BitConverter]::ToString($hash.ComputeHash($case.bytes)).Replace('-','')}
    finally{$hash.Dispose()}
    Assert ($before -eq $after) ($case.name+': invented source SHA unchanged')
}
Assert ($r6TP -eq 4 -and $r6FP -eq 2 -and $r6FN -eq 1) 'R6 non-oracle TP4 FP2 FN1 in hand-selected synthetic cases'
Assert ($r6Unique -eq 2 -and $r6Ambiguous -eq 2 -and $r6Unknown -eq 1) 'R6 ambiguity and unknown not auto-selected'
Assert ($r6Pairs -eq 6) 'R6 format prefilter passes only six artificial continuation pairs'
Write-Host ("R6 SYNTHETIC NONORACLE METRICS cases=5 sampled_offsets={0} pair_trials={1} TP={2} FP={3} FN={4} TN={5} unique={6} ambiguous={7} unknown={8} source_bytes={9} validator_bytes={10} baseline_source_bytes={11} baseline_full_originals=0" -f $r6Sampled,$r6Pairs,$r6TP,$r6FP,$r6FN,$r6TN,$r6Unique,$r6Ambiguous,$r6Unknown,$r6Source,$r6Validation,$r6BaselineSource)
Write-Host 'PASS: R6 unhinted bounded grid discovery with same artificial source and byte ceilings'

$r6Writable=[IO.MemoryStream]::new($split,$true)
try{
    $rejected=$false
    try{Test-R6NonOracleSyntheticTailSearch -Source $r6Writable -FirstOffset $gStart -FirstBytes 512 -SecondBytes $r5GRest -ExpectedFormat gcode | Out-Null}
    catch{$rejected=$true}
    Assert $rejected 'R6 refuses writable input stream'
}finally{$r6Writable.Dispose()}
$r6ProbeLimited=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($split,$false))
try{
    $partial=Test-R6NonOracleSyntheticTailSearch -Source $r6ProbeLimited -FirstOffset $gStart -FirstBytes 512 -SecondBytes $r5GRest -ExpectedFormat gcode -MaxOffsets 4
    Assert ($partial.status -eq 'partial' -and $partial.decision -eq 'incomplete' -and $partial.metrics.stopCode -eq 'search.offset_limit') 'R6 incomplete grid never called a unique source'
    Assert ($partial.metrics.sampledOffsets -eq 4 -and $partial.metrics.evaluatedPairs -eq 0) 'R6 offset guard stops before extra validations'
}finally{$r6ProbeLimited.Dispose()}
# Nine printable artificial decoy command starts exceed the eight-pair cap.
# Search must not return a spurious unique decision after dropping the rest.
$r6Flood=[byte[]]$split.Clone()
$r6FloodToken=[Text.Encoding]::ASCII.GetBytes(('G1 X0'+[char]10))
for($j=0;$j -lt 9;$j++){
    [Array]::Copy($r6FloodToken,0,$r6Flood,(49152+$j*512),$r6FloodToken.Length)
}
$r6FloodRead=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($r6Flood,$false))
try {
    $flood=Test-R6NonOracleSyntheticTailSearch -Source $r6FloodRead -FirstOffset $gStart -FirstBytes 512 -SecondBytes $r5GRest -ExpectedFormat gcode -MaxPairs 8
    Assert ($flood.status -eq 'partial' -and $flood.decision -eq 'incomplete' -and $flood.metrics.stopCode -eq 'search.pair_limit') 'R6 >8 plausible tails fail closed with no original claim'
    Assert ($flood.metrics.prefilteredCandidates -eq 8 -and $flood.metrics.evaluatedPairs -eq 0) 'R6 candidate flood never silently trims and validates as unique'
    Assert ($flood.metrics.sourceBytesRead -eq $r6FloodRead.BytesRead -and $r6FloodRead.BytesRead -le 135168) 'R6 flood stays within actual stream read budget'
} finally {$r6FloodRead.Dispose()}
$r6TinyBudget=[ChappyCountingReadStream]::new([IO.MemoryStream]::new($split,$false))
try {
    $tiny=Test-R6NonOracleSyntheticTailSearch -Source $r6TinyBudget -FirstOffset $gStart -FirstBytes 512 -SecondBytes $r5GRest -ExpectedFormat gcode -MaxSourceBytes 1024
    Assert ($tiny.decision -eq 'incomplete' -and $tiny.metrics.stopCode -eq 'search.source_byte_limit') 'R6 exhausted source budget returns incomplete'
    Assert ($tiny.metrics.sourceBytesRead -eq $r6TinyBudget.BytesRead -and $r6TinyBudget.BytesRead -le 1024) 'R6 1024B source guard independently measured'
} finally {$r6TinyBudget.Dispose()}
Write-Host 'PASS: R6 writable input, truncated coverage, nine decoy tails and tiny source-byte limit fail closed'
