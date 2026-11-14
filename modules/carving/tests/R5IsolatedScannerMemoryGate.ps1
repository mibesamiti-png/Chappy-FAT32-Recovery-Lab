#requires -Version 5.1
# Team C C5-05: ONE generated-only isolated Windows PowerShell scanner per worker.
# Worker creates in-memory artificial fixture, then measures the scanner window
# in an otherwise idle child PowerShell process. It NEVER consumes a path/image.
[CmdletBinding()]param(
 [ValidateSet('none','r2_control','r2_crc_decoy','r3_spc1','r3_spc2')]
 [string]$WorkerMode='none'
)
$ErrorActionPreference='Stop'
function Assert-C5Mem([bool]$Ok,[string]$Reason){
 if(-not $Ok){throw ('C5_05_MEM_FAIL: '+$Reason)}
}
# .NET Framework 4.8-compatible independent managed-live / private-byte
# sampler, based only on documented process/GC APIs. Sampling is NOT exact
# scanner allocation ownership or process peak including missed millisecond
# spikes. Caller constructs *all* fixtures and imports before Begin().
function Initialize-C5MemoryMonitor {
 if('ChappyC5IsolatedScannerWindowV1' -as [type]){return}
 Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Reflection;
public sealed class ChappyC5IsolatedScannerWindowV1 : IDisposable {
 private readonly Process process=Process.GetCurrentProcess();
 private Thread thread;
 private volatile bool alive;
 private long baselineManaged,baselinePrivate,peakManaged,peakPrivate,samples;
 private long startAlloc;
 private Stopwatch stopwatch=new Stopwatch();
 public long BaselineManaged {get{return baselineManaged;}}
 public long BaselinePrivate {get{return baselinePrivate;}}
 public long PeakManaged {get{return Interlocked.Read(ref peakManaged);}}
 public long PeakPrivate {get{return Interlocked.Read(ref peakPrivate);}}
 public long Samples {get{return Interlocked.Read(ref samples);}}
 public long ElapsedMs {get{return stopwatch.ElapsedMilliseconds;}}
 public long AllocatedByInvokingThread {get;private set;}
 private static long ThreadAllocation(){
   MethodInfo method=typeof(GC).GetMethod("GetAllocatedBytesForCurrentThread",BindingFlags.Public|BindingFlags.Static);
   if(method==null)return -1;
   return (long)method.Invoke(null,null);
 }
 private static void Raise(ref long target,long value){
   long old;
   do {old=Interlocked.Read(ref target);if(old>=value)return;}
   while(Interlocked.CompareExchange(ref target,value,old)!=old);
 }
 private void Sample(){
   long managed=GC.GetTotalMemory(false);
   process.Refresh();
   long privateBytes=process.PrivateMemorySize64;
   Raise(ref peakManaged,managed);
   Raise(ref peakPrivate,privateBytes);
   Interlocked.Increment(ref samples);
 }
 private void SampleLoop(){
   while(alive){try{Sample();}catch{}Thread.Sleep(1);}
   try{Sample();}catch{}
 }
 public void Begin(){
   if(thread!=null)throw new InvalidOperationException("single start only");
   GC.Collect();GC.WaitForPendingFinalizers();GC.Collect();
   baselineManaged=GC.GetTotalMemory(false);
   process.Refresh();baselinePrivate=process.PrivateMemorySize64;
   peakManaged=baselineManaged;peakPrivate=baselinePrivate;
   samples=0;startAlloc=ThreadAllocation();alive=true;
   thread=new Thread(SampleLoop);
   thread.IsBackground=true;
   stopwatch.Start();thread.Start();
 }
 public void Stop(){
   if(thread==null)throw new InvalidOperationException("not started");
   alive=false;
   if(!thread.Join(5000))throw new InvalidOperationException("sampler thread stuck");
   try{Sample();}catch{}
   stopwatch.Stop();
   long lastAlloc=ThreadAllocation();
   AllocatedByInvokingThread=(startAlloc>=0&&lastAlloc>=startAlloc)?lastAlloc-startAlloc:-1;
 }
 public void Dispose(){alive=false;if(thread!=null&&thread.IsAlive)thread.Join(5000);process.Dispose();}
}
public sealed class ChappyC5IndependentMemorySourceV1 : MemoryStream {
 private struct Span{public long start; public long end;}
 private readonly List<Span> positions=new List<Span>();
 public long Returned{get;private set;}
 public int ReadCalls{get;private set;}
 public int ZeroCalls{get;private set;}
 public ChappyC5IndependentMemorySourceV1(byte[] bytes):base(bytes,false){}
 public override int Read(byte[] target,int offset,int count){
   long at=Position;
   int n=base.Read(target,offset,count);
   ReadCalls++;
   if(n==0){ZeroCalls++;return 0;}
   Returned+=n;
   positions.Add(new Span{start=at,end=at+n});
   return n;
 }
 public long UniqueReturned {
  get {
   if(positions.Count==0)return 0;
   var list=new List<Span>(positions);
   list.Sort((a,b)=>a.start.CompareTo(b.start));
   long total=0,lo=list[0].start,hi=list[0].end;
   for(int i=1;i<list.Count;i++){
    if(list[i].start>hi){total+=hi-lo;lo=list[i].start;hi=list[i].end;}
    else if(list[i].end>hi)hi=list[i].end;
   }
   return total+hi-lo;
  }
 }
}
'@
}
function Invoke-C5MemWorker([string]$Mode){
 try{
  # Only allowlisted synthetic mode strings. No files to open, no card/image
  # path, no original SHA or physical extents ever passed to scanner.
  $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
  . (Join-Path $root 'tests\helpers\New-Chappy3DCleanFixture.ps1')
  . (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
  . (Join-Path $PSScriptRoot 'R5VariableZipPairRegression.ps1')
  . (Join-Path $root 'modules\directory\DirectoryScanner.ps1')
  Import-Module (Join-Path $root 'modules\carving\Chappy.CandidateEvidenceV1.psm1') -Force
  Initialize-C5MemoryMonitor
  $large=$Mode.StartsWith('r3_')
  $window=if($large){32768}else{65536}
  $start=0L
  if($large){
   $spc=if($Mode -eq 'r3_spc1'){1}else{2}
   $fixture=New-ChappyA3DStandardFixture -Seed 202611 -SectorsPerCluster $spc -Fragment3Mf:($spc -eq 1)
   [byte[]]$image=$fixture.image
   $geometryStream=[IO.MemoryStream]::new($image,$false)
   try{$geo=Get-ChappyFat32Geometry -Stream $geometryStream}finally{$geometryStream.Dispose()}
   Assert-C5Mem ($geo.clusterCount -eq 65541 -and
    $geo.dataOffsetBytes -gt 65536 -and $geo.dataOffsetBytes%512 -eq 0) 'standard_geometry_untrusted_B_hint'
   $start=[long]$geo.dataOffsetBytes
   $truth=@($fixture.oracle|Where-Object {$_.shortName -ceq 'MODEL   3MF'})[0]
  }else{
   $clean=New-ChappyA3DCleanFixture -Seed 202611
   $truth=@($clean.oracle|Where-Object {$_.shortName -ceq 'MODEL   3MF'})[0]
   [byte[]]$original=[byte[]]::new([int]$truth.lengthBytes)
   $copied=0
   foreach($span in $truth.extents){
    [Array]::Copy($clean.image,[int]$span.offsetBytes,$original,$copied,[int]$span.lengthBytes)
    $copied+=[int]$span.lengthBytes
   }
   Assert-C5Mem ($copied -eq $original.Length -and
    (Get-A3DSha256 $original) -ceq $truth.sha256) 'external_test_truth_SHA'
   $kind=if($Mode -eq 'r2_crc_decoy'){'alternate_zip_metadata'}else{'M01_control'}
   $fixture=New-CVariableSyntheticCase -CleanImage $clean.image -Original $original -Kind $kind
   [byte[]]$image=$fixture.image
  }
  $before=Get-A3DSha256 $image
  $input=[ChappyC5IndependentMemorySourceV1]::new($image)
  $probe=[ChappyC5IsolatedScannerWindowV1]::new()
  try{
   # Source is artificial and caller-owned; scanner receives no oracle truth.
   $params=@{Source=$input;EnableCandidateEvidence=$true
    WindowStartBytes=$start;WindowBytes=$window
    EnableStandardsShapedSource=$large;EnableExpandedFiniteHypotheses=$true
    MaxSourceReturnedBytes=81920;MaxPhysicalReadCalls=512;MaxWorkMilliseconds=30000}
   $probe.Begin()
   try{$result=Get-ChappyCarvingCandidateEvidenceV1 @params}finally{$probe.Stop()}
   $profile=[pscustomobject]@{
    baselineManaged=[long]$probe.BaselineManaged
    peakManaged=[long]$probe.PeakManaged
    baselinePrivate=[long]$probe.BaselinePrivate
    peakPrivate=[long]$probe.PeakPrivate
    managedSampledGrowth=[long][Math]::Max(0L,$probe.PeakManaged-$probe.BaselineManaged)
    privateSampledGrowth=[long][Math]::Max(0L,$probe.PeakPrivate-$probe.BaselinePrivate)
    invokingThreadCumulativeAllocated=[long]$probe.AllocatedByInvokingThread
    sampleCount=[long]$probe.Samples
    isolatedInvocationMs=[long]$probe.ElapsedMs
    sourceReturnedB=[long]$input.Returned
    sourceUniqueB=[long]$input.UniqueReturned
    sourceCalls=[int]$input.ReadCalls
    sourceZeroCalls=[int]$input.ZeroCalls
   }
   $m=$result.metrics
   Assert-C5Mem ($result.status -eq 'partial' -and
    $result.originalIdentity -eq 'unknown' -and
    $result.sourceAuthenticity -eq 'not_proven' -and
    -not $result.canExport -and -not $result.canRepair -and
    $null -eq $result.selectedOriginal -and
    $m.sourceReturnedBytes -eq $profile.sourceReturnedB -and
    $m.sourceUniqueReturnedBytes -eq $profile.sourceUniqueB -and
    $m.sourceReadCalls -eq $profile.sourceCalls -and
    $m.sourceReturnedBytes -le 81920 -and $m.sourceReadCalls -le 512 -and
    $m.sectorProbes -eq $window/512 -and $m.pairAttempts -le 16 -and
    $m.inMemoryZipValidatorBytes -le 98304 -and
    $m.processPeakMemoryStatus -eq 'not_measured' -and
    $profile.baselineManaged -gt 0 -and $profile.baselinePrivate -gt 0 -and
    $profile.peakManaged -ge $profile.baselineManaged -and
    $profile.peakPrivate -ge $profile.baselinePrivate -and
    $profile.sampleCount -ge 2 -and
    $profile.managedSampledGrowth -le 134217728L -and
    $profile.privateSampledGrowth -le 201326592L -and
    $profile.isolatedInvocationMs -lt 30000) 'independent_memory_probes_and_C_source_metrics'
   # The oracle is available only to this independent WORKER SCORER after
   # scanner completion, outside the memory observation interval.
   $exact=0;$different=0
   foreach($item in @($result.candidateDefinitions)){
    Assert-C5Mem (@($item.sourceSpans).Count -eq 2 -and
     $item.originalIdentity -eq 'unknown' -and -not $item.canExport) 'candidate_untested_original_identity'
    [byte[]]$joined=[byte[]]::new([int]$item.lengthBytes)
    $cursor=0
    foreach($span in @($item.sourceSpans)){
     [Array]::Copy($image,[int]$span.offsetBytes,$joined,$cursor,[int]$span.lengthBytes)
     $cursor+=[int]$span.lengthBytes
    }
    if((Get-A3DSha256 $joined) -ceq $truth.sha256){$exact++}else{$different++}
   }
   $expectedDecision=if($Mode -eq 'r2_crc_decoy'){'ambiguous'}else{'one_possible'}
   Assert-C5Mem ($result.decision -eq $expectedDecision -and
    $exact -eq 1 -and $different -eq $(if($Mode -eq 'r2_crc_decoy'){1}else{0})) 'external_SHA_expected_only_for_artificial'
   Assert-C5Mem ((Get-A3DSha256 $image) -ceq $before) 'source_SHA_unchanged'
   # Single allowlisted JSON summary, never original SHA/path/payload.
   $report=[ordered]@{
    schemaVersion='c5_isolated_scanner_mem_v1';case=$Mode
    measurementScope='isolated_child_scan_invocation_sampled_process_memory'
    completeness='sampled_not_proven_exact_scanner_peak'
    hardReadDeadline='not_enforced_by_C_Stream_Read'
    sourceAuthenticity='not_proven'
    status=$result.status;decision=$result.decision
    candidates=$result.candidateCount;originalShaExactCount=$exact
    structurallyPossibleButOriginalShaDifferent=$different
    falseOriginalClaims=0;AReadReceipts=0
    windowStart=$start;windowBytes=$window
    parserBytes=[long]$m.inMemoryZipValidatorBytes
    sectorProbes=[int]$m.sectorProbes;pairAttempts=[int]$m.pairAttempts
    CReportedElapsedMs=[long]$m.elapsedMilliseconds
    memory=$profile
    sourceUnmodified=$true
   }
   [Console]::Out.WriteLine(($report|ConvertTo-Json -Compress -Depth 4))
  }finally{$probe.Dispose();$input.Dispose()}
 }catch{
  # Do not log exception.ToString() which could leak a runner-local path.
  [Console]::Error.WriteLine('C5_05_ISOLATED_WORKER_FAILURE')
  exit 1
 }
}
function Invoke-C5IsolatedScannerMemoryGate {
 $scriptPath=Join-Path $PSScriptRoot 'R5IsolatedScannerMemoryGate.ps1'
 Assert-C5Mem ([IO.File]::Exists($scriptPath) -and
  $scriptPath -like '*modules*carving*tests*') 'C_owned_script_is_local'
 $expected=@(
  [pscustomobject]@{name='r2_control';decision='one_possible';candidates=1;exact=1;wrong=0;returned=71015;unique=65536;calls=140;pairs=6;window=65536},
  [pscustomobject]@{name='r2_crc_decoy';decision='ambiguous';candidates=2;exact=1;wrong=1;returned=76122;unique=65536;calls=152;pairs=12;window=65536},
  [pscustomobject]@{name='r3_spc1';decision='one_possible';candidates=1;exact=1;wrong=0;returned=38247;unique=32768;calls=76;pairs=6;window=32768},
  [pscustomobject]@{name='r3_spc2';decision='one_possible';candidates=1;exact=1;wrong=0;returned=34541;unique=32768;calls=68;pairs=2;window=32768}
 )
 $n=0;$returned=0L;$unique=0L;$calls=0;$exact=0;$wrong=0
 foreach($case in $expected){
  # This child can ONLY build deterministic invented in-memory data; no
  # reader path to microSD or sole master IMG is provided or even accepted.
  $exe=[IO.Path]::Combine($PSHOME,'powershell.exe')
  $start=New-Object Diagnostics.ProcessStartInfo
  $start.FileName=$exe
  $start.Arguments=('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -WorkerMode {1}' -f $scriptPath,$case.name)
  $start.UseShellExecute=$false;$start.CreateNoWindow=$true
  $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  $start.WorkingDirectory=$PSScriptRoot
  $child=[Diagnostics.Process]::Start($start)
  Assert-C5Mem ($null -ne $child) ($case.name+':child_started')
  try{
   if(-not $child.WaitForExit(60000)){
    # Outer test harness can terminate stuck SYNTHETIC subprocess. This
    # DOES NOT add a hard deadline to C production Stream.Read.
    $child.Kill();[void]$child.WaitForExit(5000)
    throw 'C5_05_MEM_FAIL: isolated_worker_watchdog_exhausted'
   }
   $stdout=$child.StandardOutput.ReadToEnd()
   $stderr=$child.StandardError.ReadToEnd()
   Assert-C5Mem ($child.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($stderr) -and
    $stdout.Length -lt 4096 -and $stdout.Trim().StartsWith('{')) ($case.name+':one_sanitized_JSON_report')
   $r=$stdout.Trim()|ConvertFrom-Json
   Assert-C5Mem ($r.schemaVersion -eq 'c5_isolated_scanner_mem_v1' -and
    $r.case -ceq $case.name -and
    $r.status -eq 'partial' -and
    $r.decision -eq $case.decision -and
    $r.candidates -eq $case.candidates -and
    $r.originalShaExactCount -eq $case.exact -and
    $r.structurallyPossibleButOriginalShaDifferent -eq $case.wrong -and
    $r.falseOriginalClaims -eq 0 -and $r.AReadReceipts -eq 0 -and
    $r.windowBytes -eq $case.window -and
    $r.memory.sourceReturnedB -eq $case.returned -and
    $r.memory.sourceUniqueB -eq $case.unique -and
    $r.memory.sourceCalls -eq $case.calls -and
    $r.pairAttempts -eq $case.pairs -and
    $r.parserBytes -le 98304 -and
    $r.sourceUnmodified -and
    $r.sourceAuthenticity -eq 'not_proven' -and
    $r.memory.sampleCount -ge 2 -and
    $r.memory.baselineManaged -gt 0 -and
    $r.memory.peakManaged -ge $r.memory.baselineManaged -and
    $r.memory.managedSampledGrowth -le 134217728 -and
    $r.memory.privateSampledGrowth -le 201326592 -and
    $r.completeness -eq 'sampled_not_proven_exact_scanner_peak' -and
    $r.hardReadDeadline -eq 'not_enforced_by_C_Stream_Read') ($case.name+':frozen_isolated_memory_source_and_outcomes')
   $n++;$returned+=[long]$r.memory.sourceReturnedB
   $unique+=[long]$r.memory.sourceUniqueB
   $calls+=[int]$r.memory.sourceCalls
   $exact+=[int]$r.originalShaExactCount
   $wrong+=[int]$r.structurallyPossibleButOriginalShaDifferent
   Write-Host ('C5-05 ISOLATED case={0} decision={1} exact={2} original_SHA_wrong={3} returnedB={4} uniqueB={5} calls={6} parserB={7} probe={8} pairs={9} elapsedMs={10}/{11} baselineHeapB={12} sampledHeapPeakB={13} growthHeapB={14} baselinePrivateB={15} sampledPrivatePeakB={16} growthPrivateB={17} samples={18} cumulativeThreadAllocB={19} sourceAuthenticity=not_proven' -f
    $r.case,$r.decision,$r.originalShaExactCount,$r.structurallyPossibleButOriginalShaDifferent,
    $r.memory.sourceReturnedB,$r.memory.sourceUniqueB,$r.memory.sourceCalls,$r.parserBytes,
    $r.sectorProbes,$r.pairAttempts,$r.CReportedElapsedMs,$r.memory.isolatedInvocationMs,
    $r.memory.baselineManaged,$r.memory.peakManaged,$r.memory.managedSampledGrowth,
    $r.memory.baselinePrivate,$r.memory.peakPrivate,$r.memory.privateSampledGrowth,
    $r.memory.sampleCount,$r.memory.invokingThreadCumulativeAllocated)
  }finally{$child.Dispose()}
 }
 Assert-C5Mem ($n -eq 4 -and $exact -eq 4 -and $wrong -eq 1 -and
  $returned -eq 219925 -and $unique -eq 196608 -and $calls -eq 436) '4_frozen_isolated_cases_source_totals'
 Write-Host ('C5-05 ISOLATED SUMMARY cases={0} artificialOriginal_SHA_exact={1} structure_SHA_wrong={2} actualSourceB={3} uniqueB={4} repeatedB={5} calls={6} sourceAuthenticity=not_proven scannerPeakAttribution=sampled_isolated_process_not_exact originalClaims=0 AReceipts=0' -f
  $n,$exact,$wrong,$returned,$unique,($returned-$unique),$calls)
 Write-Host 'PASS: C5-05 four fresh child-process artificial scanner invocation memory high-water observations and external source I/O'
}
if($WorkerMode -ne 'none'){Invoke-C5MemWorker $WorkerMode}
