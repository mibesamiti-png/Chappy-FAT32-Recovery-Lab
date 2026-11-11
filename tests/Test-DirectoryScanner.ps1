#requires -Version 5.1
# Synthetic fixtures only. Uses standard PowerShell / .NET. No access to real IMG.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path (Join-Path $PSScriptRoot '..\modules\directory') 'DirectoryScanner.ps1')
. (Join-Path (Join-Path $PSScriptRoot '..\modules\directory') 'DirectoryHierarchy.ps1')

function Assert-B([bool]$Pass, [string]$Label) {
    if (-not $Pass) { throw "FAIL: $Label" }
    Write-Host "PASS: $Label"
}
function Set-U16([byte[]]$B,[int]$O,[int]$V) {
    [BitConverter]::GetBytes([uint16]$V).CopyTo($B,$O)
}
function Set-U32([byte[]]$B,[int]$O,[long]$V) {
    [BitConverter]::GetBytes([uint32]$V).CopyTo($B,$O)
}
function Write-B([System.IO.Stream]$S,[long]$At,[byte[]]$Bytes) {
    [void]$S.Seek($At,[IO.SeekOrigin]::Begin)
    $S.Write($Bytes,0,$Bytes.Length)
}
function New-ShortB([string]$Alias11,[int]$Attr,[long]$Cluster,[long]$Size) {
    if ($Alias11.Length -ne 11) { throw 'Synthetic alias must contain exactly 11 characters' }
    [byte[]]$e=New-Object byte[] 32
    [Text.Encoding]::ASCII.GetBytes($Alias11).CopyTo($e,0)
    $e[11]=[byte]$Attr
    Set-U16 $e 20 ([int](($Cluster -shr 16) -band 4095))
    Set-U16 $e 26 ([int]($Cluster -band 65535))
    Set-U32 $e 28 $Size
    return ,$e
}
function New-LfnB([string]$Name,[byte[]]$ShortEntry) {
    [byte[]]$encoded=[Text.Encoding]::Unicode.GetBytes($Name)
    $units = New-Object System.Collections.ArrayList
    for ($i=0;$i -lt $encoded.Length;$i+=2) {
        [void]$units.Add(([int]$encoded[$i]+256*[int]$encoded[$i+1]))
    }
    [void]$units.Add(0)
    $count=[int][Math]::Ceiling($units.Count/13.0)
    $sum=Get-ChappyBShortChecksum $ShortEntry
    $pieces=New-Object System.Collections.ArrayList
    $positions=@(1,3,5,7,9,14,16,18,20,22,24,28,30)
    for ($ord=$count;$ord -ge 1;$ord--) {
        [byte[]]$e=New-Object byte[] 32
        $e[0]=[byte]$(if($ord -eq $count){$ord -bor 0x40}else{$ord})
        $e[11]=0x0F; $e[12]=0; $e[13]=[byte]$sum
        for($i=0;$i -lt 13;$i++) {
            $index=($ord-1)*13+$i
            $u=if($index -lt $units.Count){[int]$units[$index]}else{65535}
            Set-U16 $e $positions[$i] $u
        }
        [void]$pieces.Add($e)
    }
    return ,$pieces.ToArray()
}
function Write-DirectoryB([System.IO.Stream]$S,[long]$At,[System.Collections.IList]$Entries) {
    [byte[]]$cluster=New-Object byte[] 1024
    $offset=0
    $entryIndex=0
    foreach($entry in $Entries) {
        if($offset+32 -gt $cluster.Length){throw 'Fixture directory overflow'}
        [byte[]]$source=[byte[]]$entry
        if($source.Length -ne 32) {
            throw "Fixture entry $entryIndex has length $($source.Length), expected 32 (directory offset $At)"
        }
        [Array]::Copy($source,0,$cluster,$offset,32)
        $offset+=32
        $entryIndex++
    }
    Write-B $S $At $cluster
}
function New-HierarchyContainerB([long]$Cluster,[object]$Hint,[bool]$Root) {
    return [pscustomobject]@{
        cluster = $Cluster
        parentClusterHint = $Hint
        isRoot = $Root
        decisionReason = 'synthetic_container'
    }
}
function New-HierarchyLinkB([long]$Parent,[long]$Child,[long]$At) {
    return [pscustomobject]@{
        containerCluster = $Parent
        startCluster = $Child
        isDirectory = $true
        deleted = $false
        offsetBytes = $At
        name = 'SYNTHETIC_ONLY'
    }
}
function Hash-B([string]$Path) {
    $sha=[Security.Cryptography.SHA256]::Create()
    $s=[IO.File]::OpenRead($Path)
    try {return [BitConverter]::ToString($sha.ComputeHash($s))} finally {$s.Dispose();$sha.Dispose()}
}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('ChappyB-Synthetic-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$imagePath=Join-Path $temp 'generated-test.img'
$copyPath=Join-Path $temp 'generated-truncated.img'
$length=2097152L
$partitionOffset=4096L
$totalSectors=4088L
$reserved=32L
$fatSectors=16L
$dataOffset=$partitionOffset+($reserved+2*$fatSectors)*512L
$clusterBytes=1024L
function ClusterAt([long]$N) {return ($dataOffset+($N-2L)*$clusterBytes)}
try {
    $s=[IO.File]::Open($imagePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $s.SetLength($length)
        [byte[]]$mbr=New-Object byte[] 512
        $mbr[446+4]=0x0C
        Set-U32 $mbr (446+8) 8
        Set-U32 $mbr (446+12) $totalSectors
        $mbr[510]=0x55;$mbr[511]=0xAA
        Write-B $s 0 $mbr
        [byte[]]$bpb=New-Object byte[] 512
        $bpb[0]=0xEB;$bpb[1]=0x58;$bpb[2]=0x90
        Set-U16 $bpb 11 512
        $bpb[13]=2
        Set-U16 $bpb 14 $reserved
        $bpb[16]=2
        Set-U32 $bpb 32 $totalSectors
        Set-U32 $bpb 36 $fatSectors
        Set-U32 $bpb 44 2
        $bpb[510]=0x55;$bpb[511]=0xAA
        Write-B $s $partitionOffset $bpb
        [byte[]]$brokenFat=New-Object byte[] 128
        for ($i=0;$i -lt $brokenFat.Length;$i++) {$brokenFat[$i]=if($i%2 -eq 0){0xEB}else{0x58}}
        Write-B $s ($partitionOffset+$reserved*512L) $brokenFat
        Write-B $s ($partitionOffset+($reserved+$fatSectors)*512L) $brokenFat
        $root=New-Object System.Collections.ArrayList
        $jpn=New-ShortB 'JPTEST~1GCO' 0x20 12 121
        foreach($e in (New-LfnB '日本語テスト.gcode' $jpn)) {[void]$root.Add($e)}
        [void]$root.Add($jpn)
        $longJpn=New-ShortB 'LONGJP~1TXT' 0x20 35 209
        foreach($e in (New-LfnB '復旧候補_機械部品_長いファイル名🌟.gcode' $longJpn)) {[void]$root.Add($e)}
        [void]$root.Add($longJpn)
        [void]$root.Add((New-ShortB 'README  TXT' 0x20 15 24))
        [void]$root.Add((New-ShortB 'PARTS      ' 0x10 7 0))
        [byte[]]$badLfn=(New-LfnB 'FALSE-NAME.TXT' (New-ShortB 'BROKEN  TXT' 0x20 16 300))[0]
        $badLfn[13]=[byte](($badLfn[13]+1) -band 255)
        [void]$root.Add($badLfn)
        [void]$root.Add((New-ShortB 'BROKEN  TXT' 0x20 16 300))
        foreach($e in (New-LfnB '../ESCAPE.txt' (New-ShortB 'ESCAPE~1TXT' 0x20 21 2))) {[void]$root.Add($e)}
        [void]$root.Add((New-ShortB 'ESCAPE~1TXT' 0x20 21 2))
        [byte[]]$deleted=(New-ShortB 'DELETED TXT' 0x20 25 4)
        $deleted[0]=0xE5
        [void]$root.Add($deleted)
        [void]$root.Add((New-ShortB 'BIGFILE BIN' 0x20 40 4294967295L))
        Write-DirectoryB $s (ClusterAt 2) $root
        $sub=New-Object System.Collections.ArrayList
        [void]$sub.Add((New-ShortB '.          ' 0x10 7 0))
        [void]$sub.Add((New-ShortB '..         ' 0x10 2 0))
        [void]$sub.Add((New-ShortB 'CHILD   TXT' 0x20 31 500))
        [void]$sub.Add((New-ShortB 'NEST       ' 0x10 10 0))
        Write-DirectoryB $s (ClusterAt 7) $sub
        $nest=New-Object System.Collections.ArrayList
        [void]$nest.Add((New-ShortB '.          ' 0x10 10 0))
        [void]$nest.Add((New-ShortB '..         ' 0x10 7 0))
        [void]$nest.Add((New-ShortB 'INNER   TXT' 0x20 52 70))
        Write-DirectoryB $s (ClusterAt 10) $nest
        $orphan=New-Object System.Collections.ArrayList
        [void]$orphan.Add((New-ShortB '.          ' 0x10 19 0))
        [void]$orphan.Add((New-ShortB '..         ' 0x10 0 0))
        [void]$orphan.Add((New-ShortB 'ORPHAN  TXT' 0x20 88 60))
        Write-DirectoryB $s (ClusterAt 19) $orphan
        $falsePositive=New-Object System.Collections.ArrayList
        [void]$falsePositive.Add((New-ShortB 'FAKE    TXT' 0x20 77 17))
        Write-DirectoryB $s (ClusterAt 20) $falsePositive # isolated random-like hit

        # Adversarial: R1 trusted a lone dot marker even with an invalid dotdot.
        $badPair=New-Object System.Collections.ArrayList
        [void]$badPair.Add((New-ShortB '.          ' 0x10 21 0))
        [void]$badPair.Add((New-ShortB '..         ' 0x10 99999 0))
        [void]$badPair.Add((New-ShortB 'DOTLURE TXT' 0x20 78 17))
        Write-DirectoryB $s (ClusterAt 21) $badPair

        # Adversarial: a single valid short+LFN sequence is not itself proof
        # that the surrounding arbitrary data is a directory cluster.
        $loneLfn=New-Object System.Collections.ArrayList
        $loneShort=New-ShortB 'ONLYLFN TXT' 0x20 79 15
        foreach($e in (New-LfnB 'Artificial_Lonely_LFN.txt' $loneShort)){[void]$loneLfn.Add($e)}
        [void]$loneLfn.Add($loneShort)
        Write-DirectoryB $s (ClusterAt 22) $loneLfn

        # Positive: a complete ordered dot+dotdot pair supports a directory
        # with exactly one ordinary entry, even when its parent is only a hint.
        $validPair=New-Object System.Collections.ArrayList
        [void]$validPair.Add((New-ShortB '.          ' 0x10 23 0))
        [void]$validPair.Add((New-ShortB '..         ' 0x10 2 0))
        [void]$validPair.Add((New-ShortB 'PAIRED  TXT' 0x20 80 10))
        Write-DirectoryB $s (ClusterAt 23) $validPair
    } finally {$s.Dispose()}
    $before=Hash-B $imagePath
    $read=[IO.File]::Open($imagePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $geo=Get-ChappyFat32Geometry -Stream $read
        Assert-B ($geo.dataOffsetBytes -eq $dataOffset -and $geo.clusterSizeBytes -eq 1024) 'MBR/BPB geometry'
        $all=Get-ChappyDirectoryCandidates -Stream $read -Geometry $geo -MaxScanBytes $length -IncludeNames -IncludeDeleted
        Assert-B ($all.errors.Count -eq 0 -and -not $all.scanIncomplete) 'FAT-independent bounded full scan'
        Assert-B (@($all.items|Where-Object {$_.name -eq '日本語テスト.gcode' -and $_.nameSource -eq 'lfn_validated'}).Count -eq 1) 'Japanese LFN and checksum'
        Assert-B (@($all.items|Where-Object {$_.name -eq '復旧候補_機械部品_長いファイル名🌟.gcode' -and $_.nameSource -eq 'lfn_validated'}).Count -eq 1) 'Multi-entry UTF-16LE Japanese LFN including surrogate pair'
        Assert-B (@($all.items|Where-Object {$_.name -eq 'CHILD.TXT' -and $_.containerCluster -eq 7 -and $_.parentClusterHint -eq 2}).Count -eq 1) 'Subdirectory parent hint'
        Assert-B (@($all.items|Where-Object {$_.name -eq 'INNER.TXT' -and $_.containerCluster -eq 10}).Count -eq 1) 'Nested independent cluster discovery'
        $beforeHierarchyPos = $read.Position
        $hierarchy = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $all
        Assert-B ($hierarchy.status -eq 'ok' -and $hierarchy.metrics.nodes -ge 5 -and
                  $hierarchy.metrics.unresolvedTargetReferences -eq 0) 'Hierarchy uses accepted scanned containers'
        Assert-B (@($hierarchy.edges|Where-Object {
            $_.parentCluster -eq 2 -and $_.childCluster -eq 7 -and
            $_.relationStatus -eq 'parent_hint_corroborated' -and $_.confidence -eq 'probable'
        }).Count -eq 1) 'Parent directory entry and dotdot hint corroborate candidate'
        Assert-B (@($hierarchy.edges|Where-Object {
            $_.parentCluster -eq 7 -and $_.childCluster -eq 10
        }).Count -eq 1) 'Nested edge uses directly observed entry'
        Assert-B (@($hierarchy.nodes|Where-Object {
            $_.cluster -eq 19 -and $_.linkStatus -eq 'orphan_candidate'
        }).Count -eq 1 -and @($hierarchy.parentHints|Where-Object {
            $_.childCluster -eq 19 -and $_.relationStatus -eq 'root_marker_not_path'
        }).Count -eq 1) 'Unreferenced orphan retains separate dotdot marker'
        Assert-B (@($hierarchy.edges|Where-Object {$_.childCluster -eq 23}).Count -eq 0) 'Dotdot hint alone does not fabricate a hierarchy edge'
        Assert-B ($read.Position -eq $beforeHierarchyPos) 'Hierarchy computation does no IMG reads'
        Assert-B ((ConvertTo-Json -InputObject $hierarchy -Depth 8) -notmatch '日本語テスト|SYNTHETIC_ONLY') 'Hierarchy output excludes file names'
        Assert-B (@($all.items|Where-Object {$_.name -eq 'ORPHAN.TXT' -and $_.containerCluster -eq 19}).Count -eq 1) 'Orphan directory discovery'
        Assert-B (@($all.items|Where-Object {$_.name -eq 'BROKEN.TXT' -and $_.confidence -eq 'partial'}).Count -eq 1) 'Broken LFN falls back to short name'
        Assert-B (@($all.items|Where-Object {$_.name -eq '../ESCAPE.txt'}).Count -eq 0) 'Traversal name rejected'
        Assert-B (@($all.items|Where-Object {$_.name -eq 'FAKE.TXT'}).Count -eq 0) 'Single-entry false-positive guarded'
        Assert-B (@($all.items|Where-Object {$_.name -eq 'DOTLURE.TXT'}).Count -eq 0) 'Malformed dotdot cannot justify lone entry'
        Assert-B (@($all.items|Where-Object {$_.name -eq 'ONLYLFN.TXT'}).Count -eq 0) 'Single valid LFN cannot prove orphan directory'
        Assert-B (@($all.items|Where-Object {$_.name -eq 'PAIRED.TXT' -and $_.containerCluster -eq 23 -and $_.parentClusterHint -eq 2 -and $_.evidence -contains 'container_ordered_dot_pair'}).Count -eq 1) 'Ordered dot pair accepts one-entry subdirectory as candidate'
        Assert-B ($all.metrics.directoryRejectReasons.unpaired_or_malformed_dot_header -ge 1 -and $all.metrics.directoryRejectReasons.isolated_lfn_without_directory_header -ge 1) 'Aggregated fixed-code rejection evidence'
        [byte[]]$rootOne=New-Object byte[] 1024
        [Array]::Copy((New-ShortB 'ONEONLY TXT' 0x20 24 12),0,$rootOne,0,32)
        $rootParsed=Read-ChappyBDirectoryCluster -Buffer $rootOne -Cluster 2 -OffsetBytes 0 -MaxCluster $geo.maxCluster -IsRoot $true
        Assert-B ($rootParsed.accepted -and $rootParsed.decisionReason -eq 'root_valid_entry' -and $rootParsed.entries.Count -eq 1) 'Legitimate one-entry root remains accepted'
        Assert-B (@($all.items|Where-Object {$_.deleted -and $_.name -eq '?ELETED.TXT'}).Count -eq 1) 'Deleted first-character marked unknown'
        Assert-B (@($all.items|Where-Object {$_.name -eq 'BIGFILE.BIN' -and $_.confidence -eq 'partial'}).Count -eq 1) 'Huge size warning evidence'
        $redacted=Get-ChappyDirectoryCandidates -Stream $read -Geometry $geo -MaxScanBytes 1024
        Assert-B ($redacted.scanIncomplete -and $redacted.metrics.bytesRead -eq 1024 -and @($redacted.items|Where-Object {$null -ne $_.name}).Count -eq 0) 'Budget stop plus default name redaction'
        Assert-B ((ConvertTo-Json -InputObject $all -Depth 9) -match '"startCluster"') 'JSON metadata serializes'

        # Synthetic metadata graph negatives; no real image or private names.
        $graphFixture = [pscustomobject]@{
            scanIncomplete = $false
            directoryContainers = @(
                (New-HierarchyContainerB 2 $null $true)
                (New-HierarchyContainerB 7 2 $false)
                (New-HierarchyContainerB 25 26 $false)
                (New-HierarchyContainerB 26 25 $false)
                (New-HierarchyContainerB 31 2 $false)
                (New-HierarchyContainerB 32 2 $false)
                (New-HierarchyContainerB 44 7 $false)
                (New-HierarchyContainerB 55 2 $false)
            )
            items = @(
                (New-HierarchyLinkB 2 31 100)
                (New-HierarchyLinkB 7 31 200)
                (New-HierarchyLinkB 2 32 300)
                (New-HierarchyLinkB 2 32 332)
                (New-HierarchyLinkB 25 26 400)
                (New-HierarchyLinkB 26 25 500)
                (New-HierarchyLinkB 2 44 600)
                (New-HierarchyLinkB 2 80 700) # child never accepted as directory
                (New-HierarchyLinkB 7 7 800) # self reference
            )
        }
        $anomalies = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $graphFixture
        Assert-B (@($anomalies.edges|Where-Object {
            $_.childCluster -eq 31 -and $_.relationStatus -eq 'ambiguous_multiple_parents'
        }).Count -eq 2) 'Two parent assertions remain ambiguous'
        Assert-B (@($anomalies.edges|Where-Object {
            $_.childCluster -eq 32 -and $_.relationStatus -eq 'duplicate_parent_assertion'
        }).Count -eq 2) 'Duplicate same-parent entries are not silently deduplicated'
        Assert-B (@($anomalies.edges|Where-Object {
            $_.relationStatus -eq 'cycle_detected' -and $_.childCluster -in @(25,26,7)
        }).Count -eq 3) 'Circular and self-referencing directory entries identified'
        Assert-B (@($anomalies.edges|Where-Object {
            $_.childCluster -eq 44 -and $_.relationStatus -eq 'parent_hint_conflict'
        }).Count -eq 1) 'Conflicting direct parent and dotdot kept separate'
        Assert-B ($anomalies.metrics.unresolvedTargetReferences -eq 1 -and
                  @($anomalies.edges|Where-Object {$_.childCluster -eq 80 -or $_.childCluster -eq 55}).Count -eq 0) 'No fabricated edges to missing child or hint-only orphan'
        $limitedGraph = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $graphFixture -MaxNodes 3 -MaxEdges 1
        Assert-B ($limitedGraph.scanIncomplete -and $limitedGraph.status -eq 'partial' -and
                  $limitedGraph.metrics.nodes -le 3 -and $limitedGraph.metrics.edgeAssertions -le 1) 'Hierarchy node and edge budgets bounded'
        $badLimit = $false
        try { $null=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $graphFixture -MaxAncestorDepth 0 } catch { $badLimit = $true }
        Assert-B $badLimit 'Invalid hierarchy traversal limit rejected'
        $workLimited = Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $graphFixture -MaxAncestorSteps 1
        Assert-B ($workLimited.scanIncomplete -and $workLimited.status -eq 'partial' -and
                  $workLimited.metrics.ancestorSteps -le 1 -and
                  $workLimited.warnings -contains 'hierarchy_ancestor_work_limit') 'Global ancestor work budget enforces safe cutoff'
        Assert-B ((ConvertTo-Json -InputObject $anomalies -Depth 8) -notmatch 'SYNTHETIC_ONLY') 'Graph does not propagate entry names'
    } finally {$read.Dispose()}
    Assert-B ((Hash-B $imagePath) -eq $before) 'Source SHA-256 unchanged'
    [IO.File]::Copy($imagePath,$copyPath)
    $trunc=[IO.File]::Open($copyPath,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$trunc.SetLength(100000)} finally {$trunc.Dispose()}
    $truncRead=[IO.File]::OpenRead($copyPath)
    try {
        $bad=Get-ChappyDirectoryCandidates -Stream $truncRead -MaxScanBytes 4096
        Assert-B ($bad.status -eq 'error' -and $bad.scanIncomplete) 'Truncated IMG reports error'
    } finally {$truncRead.Dispose()}
    # Exercise the standalone metadata-only CLI, including non-overwrite guarantees.
    $cli=Join-Path (Join-Path $PSScriptRoot '..\modules\directory') 'Invoke-ChappyDirectoryScan.ps1'
    $outPath=Join-Path $temp 'synthetic-directory-metadata.json'
    $cliResult=& $cli -ImagePath $imagePath -OutputJsonPath $outPath -MaxScanBytes 1024 -IncludeNames
    Assert-B ([IO.File]::Exists($outPath) -and $cliResult.team -eq 'B') 'CLI produces separate JSON output'
    $parsedJson=[IO.File]::ReadAllText($outPath,[Text.Encoding]::UTF8) | ConvertFrom-Json
    Assert-B ($parsedJson.schemaVersion -eq '1' -and $parsedJson.items.Count -ge 1 -and $parsedJson.items[0].name) 'CLI JSON round-trip with opt-in names'
    $sizeBefore=(Get-Item -LiteralPath $outPath).Length
    $refusedExisting=$false
    try { $null=& $cli -ImagePath $imagePath -OutputJsonPath $outPath -MaxScanBytes 1024 } catch { $refusedExisting=$true }
    Assert-B ($refusedExisting -and (Get-Item -LiteralPath $outPath).Length -eq $sizeBefore) 'CLI refuses overwriting an existing report'
    $refusedSource=$false
    try { $null=& $cli -ImagePath $imagePath -OutputJsonPath $imagePath -MaxScanBytes 1024 } catch { $refusedSource=$true }
    Assert-B ($refusedSource -and (Hash-B $imagePath) -eq $before) 'CLI refuses output equal to source IMG'
    $refusedDevice=$false
    try { $null=& $cli -ImagePath '\\.\PhysicalDrive9' -MaxScanBytes 1024 } catch { $refusedDevice=$true }
    Assert-B $refusedDevice 'CLI refuses raw device path'
    Assert-B ((Hash-B $imagePath) -eq $before) 'CLI source SHA-256 unchanged'
    Write-Host 'ALL TEAM B SYNTHETIC TESTS PASSED'
} finally {
    [IO.Directory]::Delete($temp, $true)
}
