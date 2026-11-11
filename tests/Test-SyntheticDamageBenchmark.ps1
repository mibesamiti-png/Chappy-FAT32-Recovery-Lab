#Requires -Version 5.1
# A synthetic-only FAT32-like IMG damage/retrieval benchmark.
# Controlled artificial bytes; NEVER access original SD, master IMG or real files.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'modules\directory\DirectoryScanner.ps1')
Import-Module (Join-Path $repo 'modules\carving\Chappy.Carving.psm1') -Force
Import-Module (Join-Path $repo 'modules\fat-analysis\Fat32ChainStats.psm1') -Force
Import-Module (Join-Path $repo 'modules\fat-analysis\Fat32DirectoryConsistency.psm1') -Force
Add-Type -AssemblyName System.IO.Compression
function Check-A([bool]$OK,[string]$Reason) {if(-not $OK){throw "SYNTHETIC BENCHMARK FAILED: $Reason"}}
function Put16-A([byte[]]$B,[int]$At,[uint16]$N){[Array]::Copy([BitConverter]::GetBytes($N),0,$B,$At,2)}
function Put32-A([byte[]]$B,[int]$At,[uint32]$N){[Array]::Copy([BitConverter]::GetBytes($N),0,$B,$At,4)}
function Copy-A([byte[]]$B,[int]$At,[byte[]]$Data){[Array]::Copy($Data,0,$B,$At,$Data.Length)}
function New-3mfA {
    $ms=New-Object IO.MemoryStream
    $zip=[IO.Compression.ZipArchive]::new($ms,[IO.Compression.ZipArchiveMode]::Create,$true)
    try {
        foreach($name in @('[Content_Types].xml','_rels/.rels','3D/3dmodel.model')) {
            $entry=$zip.CreateEntry($name)
            $entryStream=$entry.Open()
            try{$data=[Text.Encoding]::UTF8.GetBytes('ARTIFICIAL-3MF-CONTENT');$entryStream.Write($data,0,$data.Length)}
            finally{$entryStream.Dispose()}
        }
    } finally {$zip.Dispose()}
    try {return ,$ms.ToArray()} finally {$ms.Dispose()}
}
function Set-RecordA([byte[]]$Bytes,[int]$At,[string]$Alias,[uint16]$Cluster,[uint32]$Size) {
    Check-A ($Alias.Length -eq 11) 'Invalid artificial 8.3 alias'
    Copy-A $Bytes $At ([Text.Encoding]::ASCII.GetBytes($Alias))
    $Bytes[$At+11]=0x20
    Put16-A $Bytes ($At+26) $Cluster
    Put32-A $Bytes ($At+28) $Size
}
function New-BaseA([byte[]]$G,[byte[]]$Z) {
    # 2 MiB controlled FAT32-like image, not a fully standards-formatted card.
    Check-A ($G.Length -lt 512 -and $Z.Length -le 2048) 'Fixture payload allocation overflow'
    [byte[]]$img=New-Object 'byte[]' 2097152
    $img[450]=0x0C;Put32-A $img 454 ([uint32]1);Put32-A $img 458 ([uint32]4095)
    $img[510]=0x55;$img[511]=0xAA
    [byte[]]$boot=New-Object 'byte[]' 512
    $boot[0]=0xEB;$boot[1]=0x58;$boot[2]=0x90
    Put16-A $boot 11 ([uint16]512);$boot[13]=1
    Put16-A $boot 14 ([uint16]32);$boot[16]=2;$boot[21]=0xF8
    Put32-A $boot 32 ([uint32]4095);Put32-A $boot 36 ([uint32]40)
    Put32-A $boot 44 ([uint32]2);$boot[510]=0x55;$boot[511]=0xAA
    Copy-A $img 512 $boot
    [byte[]]$fat=New-Object 'byte[]' 20480
    Put32-A $fat 0 ([uint32]0x0FFFFFF8)
    Put32-A $fat 4 ([uint32]0x0FFFFFFF)
    Put32-A $fat 8 ([uint32]0x0FFFFFFF)
    Put32-A $fat 12 ([uint32]0x0FFFFFFF)
    Put32-A $fat 16 ([uint32]5)
    Put32-A $fat 20 ([uint32]6)
    Put32-A $fat 24 ([uint32]7)
    Put32-A $fat 28 ([uint32]0x0FFFFFFF)
    Copy-A $img 16896 $fat;Copy-A $img 37376 $fat
    Set-RecordA $img 57856 'SAMPLE  GCO' ([uint16]3) ([uint32]$G.Length)
    Set-RecordA $img 57888 'MODEL   3MF' ([uint16]4) ([uint32]$Z.Length)
    Copy-A $img 58368 $G;Copy-A $img 58880 $Z
    return ,$img
}
function Matches-OriginalA([IO.Stream]$Stream,[object]$Candidate,[long]$At,[byte[]]$Expected) {
    if($null -eq $Candidate -or [long]$Candidate.offsetBytes -ne $At -or
        [long]$Candidate.lengthBytes -ne $Expected.Length){return $false}
    [byte[]]$buffer=New-Object 'byte[]' $Expected.Length
    [void]$Stream.Seek($At,[IO.SeekOrigin]::Begin)
    $pos=0
    while($pos -lt $buffer.Length){
        $n=$Stream.Read($buffer,$pos,($buffer.Length-$pos))
        if($n -le 0){return $false}
        $pos+=$n
    }
    for($i=0;$i -lt $Expected.Length;$i++){if($buffer[$i] -ne $Expected[$i]){return $false}}
    return $true
}
$gcodeText=@'
;FLAVOR:Marlin
G28
M104 S200
M140 S55
G1 X10 Y10 F1000
G1 X20 Y20
M73 P10
M84
'@
[byte[]]$gcode=[Text.Encoding]::ASCII.GetBytes($gcodeText+[char]10)
[byte[]]$threeMf=New-3mfA
[byte[]]$baseline=New-BaseA $gcode $threeMf
$gcAt=58368;$zipAt=58880
$zipDataAt=30+[BitConverter]::ToUInt16($threeMf,26)+[BitConverter]::ToUInt16($threeMf,28)+2
Check-A ($zipDataAt -lt ($threeMf.Length-22)) 'ZIP payload offset must precede central directory'
$cases=@(
    [pscustomobject]@{id='clean';kind='clean';exact=2;rootBad=0},
    [pscustomobject]@{id='both_fats_bad';kind='both';exact=2;rootBad=2},
    [pscustomobject]@{id='fat1_bad';kind='one';exact=2;rootBad=1},
    [pscustomobject]@{id='gcode_body_modified';kind='gcode';exact=1;rootBad=0},
    [pscustomobject]@{id='3mf_deflate_modified';kind='zip';exact=1;rootBad=0},
    [pscustomobject]@{id='3mf_eocd_missing';kind='eocd';exact=1;rootBad=0},
    [pscustomobject]@{id='gcode_missing';kind='missing';exact=1;rootBad=0}
)
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ChappyA_Damage_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$exactTotal=0;$foundTotal=0
try {
    foreach($fixture in $cases){
        [byte[]]$bytes=[byte[]]$baseline.Clone()
        switch($fixture.kind){
            'both' {Put32-A $bytes 16904 ([uint32]0x58EB58EB);Put32-A $bytes 37384 ([uint32]0x58EB58EB)}
            'one' {Put32-A $bytes 16904 ([uint32]0x58EB58EB)}
            'gcode' {
                $index=[Text.Encoding]::ASCII.GetString($gcode).IndexOf('X10')
                Check-A ($index -gt 0) 'Missing mutation marker'
                $bytes[$gcAt+$index+1]=[byte][char]'9'
            }
            'zip' {$at=$zipAt+$zipDataAt;$bytes[$at]=[byte]($bytes[$at] -bxor 1)}
            'eocd' {for($i=($threeMf.Length-22);$i -lt $threeMf.Length;$i++){$bytes[$zipAt+$i]=0}}
            'missing' {for($i=0;$i -lt $gcode.Length;$i++){$bytes[$gcAt+$i]=0}}
        }
        $path=Join-Path $temp ($fixture.id+'.img')
        [IO.File]::WriteAllBytes($path,$bytes) # disposable artificial file only
        $before=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $s=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try {
            Check-A ($s.CanRead -and $s.CanSeek -and -not $s.CanWrite) 'Source must be read-only'
            $geo=Get-ChappyFat32Geometry -Stream $s
            $b=Get-ChappyDirectoryCandidates -Stream $s -Geometry $geo -MaxScanBytes 8192 -MaxCandidates 16 -MaxDirectories 4
            Check-A ($b.items.Count -ge 2) 'FAT-independent directory candidates missing'
            $d=Get-ChappyFatChainAnomalyStats -Stream $s -Fat1OffsetBytes 16896 -Fat2OffsetBytes 37376 -FatLengthBytes 20480 -MaxDataCluster ([long]$geo.maxCluster) -StartClusters ([long[]]@(2)) -MaxStepsPerChain 8 -MaxTotalEntries 16 -MaxReadBytes 64
            Check-A ($d.metrics.anomalousResolvedTraces -eq $fixture.rootBad) ('FAT damage mismatch '+$fixture.id)
            $cross=Get-ChappyFatDirectoryConsistency -Stream $s -DirectoryOffsetBytes 57856 -Fat1OffsetBytes 16896 -Fat2OffsetBytes 37376 -FatLengthBytes 20480 -MaxDataCluster ([long]$geo.maxCluster) -DirectorySlots 3 -BytesPerCluster 512 -MaxStepsPerTrace 8 -MaxReadBytes 256
            Check-A ($cross.metrics.compatibleObservations -ge 4) 'Directory/FAT numerical compatibility unexpectedly changed'
            $c=Get-ChappyCarvingCandidates -Stream $s -StartOffset $gcAt -MaxScanBytes 8192 -MaxFileBytes 8192 -MaxProbeBytes 8192 -MaxProbes 32 -MaxCandidates 16 -ExtraValidationReadBytes 65536 -MaxWorkMilliseconds 15000
            Check-A ($c.metrics.bytesRead -le 73728 -and $c.metrics.entriesChecked -le 32) 'Carving scan budget exceeded'
            $g=@($c.items|Where-Object {$_.offsetBytes -eq $gcAt -and $_.format -eq 'gcode'})
            $z=@($c.items|Where-Object {$_.offsetBytes -eq $zipAt -and $_.format -in @('zip','3mf')})
            Check-A ($g.Count -le 1 -and $z.Count -le 1) 'Duplicate candidates'
            $gok=($g.Count -eq 1 -and (Matches-OriginalA $s $g[0] $gcAt $gcode))
            $zok=($z.Count -eq 1 -and (Matches-OriginalA $s $z[0] $zipAt $threeMf))
            Write-Host ("SYNTHETIC DEBUG {0} C_found={1} C_status={2} g_count={3} z_count={4} g_exact={5} z_exact={6} orig_g_len={7} orig_z_len={8}" -f $fixture.id,$c.items.Count,$c.status,$g.Count,$z.Count,$gok,$zok,$gcode.Length,$threeMf.Length)
            foreach($candidate in $c.items){
                Write-Host ("SYNTHETIC DEBUG candidate format={0} offset={1} length={2} confidence={3}" -f $candidate.format,$candidate.offsetBytes,$candidate.lengthBytes,$candidate.confidence)
            }
            $exact=([int]$gok)+([int]$zok)
            Check-A ($exact -eq $fixture.exact) ('Byte-for-byte mismatch '+$fixture.id)
            if($fixture.kind -eq 'zip'){
                Check-A ($z.Count -eq 1 -and -not $zok -and $z[0].integrityScope -eq 'structural_only_not_original_file_integrity') 'ZIP structural-only caveat must survive payload corruption'
            }
            $found=$g.Count+$z.Count
            $foundTotal+=$found;$exactTotal+=$exact
            Write-Host ("SYNTHETIC ONLY {0}: candidates_at_known_offsets={1}/2 byte_identical={2}/2 observed_root_chain_anomalies={3}" -f $fixture.id,$found,$exact,$fixture.rootBad)
        } finally {$s.Dispose()}
        Check-A ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $before) 'Synthetic source IMG changed'
    }
    Check-A ($exactTotal -eq 10 -and $cases.Count -eq 7) 'Unexpected controlled corpus totals'
    Write-Host ("PASS: 7 artificial damage cases; original-byte-identical candidate slices {0}/14, located {1}. This is NOT a real file recovery rate." -f $exactTotal,$foundTotal)
} finally {
    if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
}