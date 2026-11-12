#requires -Version 5.1
# Team C Issue #72. Synthetic research-only, never exported to production.
function Assert-CMulti([bool]$Okay,[string]$Code) {
    if(-not $Okay){throw ('C_MULTIFORMAT_FAIL: '+$Code)}
}
function Test-CMultiNumber([string]$Word) {
    try {$v=[double]::Parse($Word,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture)}
    catch {return $false}
    return (-not [double]::IsNaN($v) -and -not [double]::IsInfinity($v))
}
function Get-CBinaryStlLen([byte[]]$Block) {
    if($Block.Length -ne 512){return 0}
    # Restrict to printable-or-zero headers; valid binary STL may be excluded.
    for($i=0;$i -lt 80;$i++){
        $c=$Block[$i]
        if($c -ne 0 -and ($c -lt 32 -or $c -gt 126)){return 0}
    }
    $n=[BitConverter]::ToUInt32($Block,80)
    if($n -lt 1 -or $n -gt 8){return 0}
    $len=[int](84+50*$n)
    if($len -gt 512){return 0}
    $hasNonzeroVertex=$false
    for($i=0;$i -lt $n;$i++){
        $at=84+50*$i
        for($j=0;$j -lt 12;$j++){
            $v=[BitConverter]::ToSingle($Block,($at+4*$j))
            if([single]::IsNaN($v) -or [single]::IsInfinity($v)){return 0}
            if($j -ge 3 -and $v -ne 0){$hasNonzeroVertex=$true}
        }
        if([BitConverter]::ToUInt16($Block,($at+48)) -ne 0){return 0}
    }
    if(-not $hasNonzeroVertex){return 0}
    return $len
}
function Get-CAsciiStlLen([byte[]]$Block) {
    if($Block.Length -ne 512){return 0}
    $end=[Array]::IndexOf($Block,[byte]0)
    if($end -lt 0){$end=512}
    if($end -lt 30){return 0}
    $raw=[Text.Encoding]::ASCII.GetString($Block,0,$end)
    if($raw -match '[^\x09\x0A\x0D\x20-\x7E]'){return 0}
    $lines=@($raw -split '\r?\n' | ForEach-Object {$_.Trim()} | Where-Object {$_.Length -gt 0})
    # Only a strict one-facet profile; not the full STL language.
    if($lines.Count -ne 9){return 0}
    if($lines[0] -cnotmatch '^solid(?: .*)?$' -or $lines[8] -cnotmatch '^endsolid(?: .*)?$'){return 0}
    if($lines[0].Substring(5).Trim() -cne $lines[8].Substring(8).Trim()){return 0}
    if($lines[2] -cne 'outer loop' -or $lines[6] -cne 'endloop' -or $lines[7] -cne 'endfacet'){return 0}
    foreach($idx in @(1,3,4,5)){
        $words=@($lines[$idx] -split '\s+')
        if($idx -eq 1){
            if($words.Count -ne 5 -or $words[0] -cne 'facet' -or $words[1] -cne 'normal'){return 0}
            $values=@($words[2],$words[3],$words[4])
        }else{
            if($words.Count -ne 4 -or $words[0] -cne 'vertex'){return 0}
            $values=@($words[1],$words[2],$words[3])
        }
        foreach($value in $values){if(-not (Test-CMultiNumber $value)){return 0}}
    }
    return $end
}
function Get-CMultiFormatEvidence {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][IO.Stream]$Source,
        [ValidateRange(512,65536)][int]$WindowBytes=65536,
        [ValidateRange(0,65536)][long]$MaxSourceBytes=65536,
        [ValidateRange(1,128)][int]$MaxSectorProbes=128,
        [ValidateRange(1,16)][int]$MaxCandidates=16,
        [ValidateRange(1,32768)][long]$MaxValidatorBytes=32768,
        [ValidateRange(100,30000)][int]$MaxMilliseconds=30000
    )
    if(-not $Source.CanRead -or -not $Source.CanSeek -or $Source.CanWrite){
        throw 'CMultiFormat requires non-writable seekable input'
    }
    if($WindowBytes%512 -ne 0){throw 'CMultiFormat requires 512B grid'}
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $found=New-Object 'System.Collections.Generic.List[object]'
    $readBytes=0L;$readCalls=0;$probes=0;$validation=0L;$zipSig=0;$zipRejected=0
    $partial=$false;$stop='none'
    if($Source.Length -lt $WindowBytes -or $MaxSourceBytes -lt $WindowBytes -or $MaxSectorProbes -lt $WindowBytes/512){
        $partial=$true;$stop='research.window_not_reserved'
    }else{
        for($at=0;$at -lt $WindowBytes;$at+=512){
            if($clock.ElapsedMilliseconds -ge $MaxMilliseconds){$partial=$true;$stop='research.time_limit';break}
            if($readBytes+512L -gt $MaxSourceBytes){$partial=$true;$stop='research.source_limit';break}
            [byte[]]$buf=New-Object byte[] 512
            [void]$Source.Seek($at,[IO.SeekOrigin]::Begin)
            $done=0
            while($done -lt 512){
                $got=$Source.Read($buf,$done,(512-$done));$readCalls++
                if($got -le 0){$partial=$true;$stop='research.short_read';break}
                $done+=$got;$readBytes+=[long]$got
            }
            if($partial){break}
            $probes++
            $binary=Get-CBinaryStlLen $buf
            $ascii=Get-CAsciiStlLen $buf
            if($binary -gt 0){
                $found.Add([pscustomobject]@{format='stl_binary';offsetBytes=[long]$at;lengthBytes=$binary;reason='stl.binary_bounded_facets';integrityScope='structural_only_not_original_file_integrity';originalIdentity='unknown'})
            }
            if($ascii -gt 0){
                $found.Add([pscustomobject]@{format='stl_ascii';offsetBytes=[long]$at;lengthBytes=$ascii;reason='stl.ascii_one_facet_syntax';integrityScope='structural_only_not_original_file_integrity';originalIdentity='unknown'})
            }
            if($buf[0] -eq 0x50 -and $buf[1] -eq 0x4b -and $buf[2] -eq 3 -and $buf[3] -eq 4){
                $zipSig++
                # Existing C bounded parser may consume at most 512+8192 bytes.
                if($validation+8704L -gt $MaxValidatorBytes){$partial=$true;$stop='research.validation_limit';break}
                $memory=[IO.MemoryStream]::new($buf,$false)
                try{
                    $check=Get-ChappyCarvingCandidates -Stream $memory -MaxScanBytes 512 -MaxFileBytes 4096 -MaxCandidates 4 -MaxProbes 4 -MaxProbeBytes 4096 -ExtraValidationReadBytes 8192 -MaxWorkMilliseconds 4000 -EnableSmallDeflateCrc
                    $validation += [long]$check.metrics.bytesRead
                }finally{$memory.Dispose()}
                if($validation -gt $MaxValidatorBytes){throw 'CMultiFormat validator accounting invariant'}
                $z=@($check.items | Where-Object {
                    $_.format -eq 'zip' -and $_.offsetBytes -eq 0 -and $_.lengthBytes -gt 0 -and $_.lengthBytes -le 512 -and
                    $_.confidence -eq 'verified' -and $_.crc32Status -eq 'match' -and
                    $_.integrityScope -eq 'structural_only_not_original_file_integrity'
                })
                if($z.Count -eq 1){
                    $found.Add([pscustomobject]@{format='zip_plain';offsetBytes=[long]$at;lengthBytes=[int]$z[0].lengthBytes;reason='zip.bounded_crc_consistent';integrityScope='structural_only_not_original_file_integrity';originalIdentity='unknown'})
                }else{$zipRejected++}
            }
            if($found.Count -gt $MaxCandidates){$partial=$true;$stop='research.candidate_limit';break}
        }
    }
    $clock.Stop()
    return [pscustomobject]@{
        status=$(if($partial){'partial'}else{'ok'})
        decision=$(if($partial){'incomplete'}else{'bounded_evidence'})
        items=$(if($partial){@()}else{@($found.ToArray())})
        metrics=[pscustomobject]@{sourceBytesRead=$readBytes;readRequests=$readCalls;sectorProbes=$probes;validatorBytesRead=$validation;zipSignatures=$zipSig;zipRejected=$zipRejected;elapsedMilliseconds=$clock.ElapsedMilliseconds;stopCode=$stop}
    }
}
