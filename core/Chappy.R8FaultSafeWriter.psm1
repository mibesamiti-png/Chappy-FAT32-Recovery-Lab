#Requires -Version 5.1
# Team C / ACTIVE Issue #199, R8-P5. Standalone artificial-output fault adapter.
# Never run with real media/IMG bytes. A owns exporter/bridge integration.
Set-StrictMode -Version Latest
# Lazy native helper: disabled mode must not invoke Add-Type or touch temp compiler files.
function Initialize-ChappyCR8OwnedFileDispositionV1 {
if (-not ('ChappyCR8OwnedFileDispositionV1' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class ChappyCR8OwnedFileDispositionV1 {
 [StructLayout(LayoutKind.Sequential)]
 private struct FileInfo {
  public uint Attributes, CreationLo, CreationHi, AccessLo, AccessHi, WriteLo, WriteHi;
  public uint Volume, SizeHi, SizeLo, Links, IndexHi, IndexLo;
 }
 [StructLayout(LayoutKind.Sequential)]
 private struct Disposition { public byte DeleteFile; } // Win32 BOOLEAN = 1B, not BOOL = 4B
 [DllImport("kernel32.dll", SetLastError=true)]
 private static extern bool GetFileInformationByHandle(SafeFileHandle h,out FileInfo info);
 [DllImport("kernel32.dll", EntryPoint="CreateFileW", CharSet=CharSet.Unicode,SetLastError=true)]
 private static extern SafeFileHandle CreateFile(string name,uint access,uint share,IntPtr security,
  uint creation,uint flags,IntPtr templateFile);
 [DllImport("kernel32.dll",SetLastError=true)]
 private static extern bool SetFileInformationByHandle(SafeFileHandle h,int infoClass,
  ref Disposition info,uint size);
 // Requires a still-open FileMode.CreateNew owner handle. Never delete via a
 // path-only File.Delete; mark the independently opened SAME FILE handle.
 // No guarantee if an attacker controls ancestor mounts; Team B must bind root.
 public static bool MarkExactOwnedForDeletion(FileStream created,string path) {
  if(created==null || String.IsNullOrEmpty(path))return false;
  FileInfo original;
  if(!GetFileInformationByHandle(created.SafeFileHandle,out original))return false;
  if((original.Attributes & 0x400u)!=0u)return false; // reparse point
  using(var opened=CreateFile(path,0x00010080u,7u,IntPtr.Zero,3u,
      0x00200000u,IntPtr.Zero)) {
   if(opened==null || opened.IsInvalid)return false;
   FileInfo check;
   if(!GetFileInformationByHandle(opened,out check))return false;
   if((check.Attributes & 0x400u)!=0u || check.Volume!=original.Volume ||
      check.IndexHi!=original.IndexHi || check.IndexLo!=original.IndexLo)return false;
   Disposition disposition=new Disposition{DeleteFile=1};
   return SetFileInformationByHandle(opened,4,ref disposition,
      (uint)Marshal.SizeOf(typeof(Disposition)));
  }
 }
}
'@ -ErrorAction Stop
}
}
function Test-ChappyCR8DisposableRoot {
 [CmdletBinding()]param([string]$Path)
 try {
  if([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path) -or
     $Path -match '[/\\]\.\.?([/\\]|$)' -or $Path -match '^(\\\\|//)' -or
     ($Path.Length -gt 2 -and $Path.Substring(2).Contains(':'))) {return $null}
  $full=[IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\','/'))
  $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/'))
  $parent=[IO.Path]::GetDirectoryName($full).TrimEnd([char[]]@('\','/'))
  $leaf=[IO.Path]::GetFileName($full)
  if(-not [string]::Equals($parent,$temp,[StringComparison]::OrdinalIgnoreCase) -or
     $leaf -cnotmatch '^ChappyR8Synthetic-[0-9a-f]{32}$' -or
     -not [IO.Directory]::Exists($full)){return $null}
  $cursor=[IO.DirectoryInfo]::new($full);$depth=0
  while($null -ne $cursor) {
   if(++$depth -gt 64){return $null}
   $attrs=[IO.File]::GetAttributes($cursor.FullName)
   if(($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
      ($attrs -band [IO.FileAttributes]::Directory) -eq 0){return $null}
   $cursor=$cursor.Parent
  }
  return $full
 }catch{return $null}
}
function Get-ChappyCR8Hash {
 param([Parameter(Mandatory=$true)][byte[]]$Bytes)
 $sha=[Security.Cryptography.SHA256]::Create()
 try { [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') }
 finally { $sha.Dispose() }
}
function Invoke-ChappyR8SyntheticFaultWriterV1 {
 [CmdletBinding(PositionalBinding=$false)]param(
  [Parameter(Mandatory=$true)][byte[]]$SyntheticCandidateBytes,
  [Parameter(Mandatory=$true)][string]$OutputRoot,
  [Parameter(Mandatory=$true)][string]$SyntheticFixtureTag,
  [switch]$EnableSyntheticFaultWriter,
  [ValidateRange(1,8192)][int]$MaxOutputBytes=4096,
  [ValidateSet('None','BeforeWrite','AfterPartialWrite','AfterFullWrite',
   'BeforeReadback','DuringReadback','DigestMismatch','DiskFullBefore',
   'DiskFullPartial','PermissionDeniedBefore','PermissionDeniedAfterCreate')]
  [string]$FaultMode='None'
 )
 $m=[pscustomobject][ordered]@{
  plannedCandidateBytes=0;successfulWriteBytes=0;readbackReturnedBytes=0
  writeCalls=0;readCalls=0
  createdThisCall=$false;ownedHandleMatchedForCleanup=$false
  cleanupStatus='not_needed';failureStage='none'
  maxOutputBytes=$MaxOutputBytes
 }
 $out=[ordered]@{
  schemaVersion='c_r8_synthetic_fault_writer_v1';team='C'
  status='disabled';decision='not_requested';faultMode=$FaultMode
  syntheticOnly=$true;sourceAuthenticity='not_proven';originalIdentity='unknown'
  originalShaVerified=$false;canSelectOriginal=$false
  canExportOriginal=$false;canRepairOriginal=$false
  outputName=$null;outputBytes=0;outputSha256=$null;outputVerified=$false
  sourceUnchanged=$null;warningCodes=@('r8c.default_off');metrics=$m
 }
 # No input content hash, source.Length, filesystem checks or output on disabled.
 if(-not $EnableSyntheticFaultWriter){return [pscustomobject]$out}
 $out.status='rejected';$out.decision='synthetic_output_preflight_denied_UNKNOWN'
 $out.warningCodes=@('r8c.synthetic_disposable_input_required')
 $n=$SyntheticCandidateBytes.Length
 if($n -lt 1 -or $n -gt 131072 -or $n -gt $MaxOutputBytes -or
    $SyntheticFixtureTag -cnotmatch '^A3D-(clean|standard)-[0-9]{1,6}$'){
  $m.failureStage='preflight'
  return [pscustomobject]$out
 }
 $root=Test-ChappyCR8DisposableRoot -Path $OutputRoot
 if($null -eq $root){
  $m.failureStage='root_preflight'
  return [pscustomobject]$out
 }
 $m.plannedCandidateBytes=$n
 $initialSha=Get-ChappyCR8Hash $SyntheticCandidateBytes
 $fileName=('candidate-'+$initialSha.Substring(0,32)+'.3mf')
 $destination=[IO.Path]::Combine($root,$fileName)
 if(-not [string]::Equals([IO.Path]::GetDirectoryName($destination),$root,
      [StringComparison]::OrdinalIgnoreCase)){
  $m.failureStage='destination_preflight'
  return [pscustomobject]$out
 }
 $owned=$null;$created=$false;$complete=$false;$cleanupMarked=$false
 $m.cleanupStatus='not_needed'
 # Add-Type compiles only in explicitly enabled, fully preflighted synthetic mode.
 try { Initialize-ChappyCR8OwnedFileDispositionV1 }
 catch { $m.failureStage='native_helper_unavailable';$out.status='partial';$out.decision='synthetic_native_guard_unavailable_UNKNOWN';$out.warningCodes=@('r8c.native_guard_unavailable');return [pscustomobject]$out }
 try {
  if($FaultMode -eq 'PermissionDeniedBefore'){
   $m.failureStage='simulated_access_denied_before'
   throw [UnauthorizedAccessException]::new('r8c.synthetic_fault')
  }
  if($null -eq (Test-ChappyCR8DisposableRoot -Path $root)){
   $m.failureStage='root_changed_before_create'
   throw [IO.IOException]::new('r8c.synthetic_root_changed')
  }
  # CreateNew is atomic collision rejection. Keep original handle open until
  # verified output or HANDLE-IDENTITY-based fail cleanup.
  $owned=[IO.FileStream]::new($destination,[IO.FileMode]::CreateNew,
     [IO.FileAccess]::ReadWrite,
     ([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
  $created=$true;$m.createdThisCall=$true
  if($FaultMode -eq 'PermissionDeniedAfterCreate'){
   $m.failureStage='simulated_access_denied_after_create'
   throw [UnauthorizedAccessException]::new('r8c.synthetic_fault')
  }
  if($FaultMode -in @('BeforeWrite','DiskFullBefore')){
   $m.failureStage=if($FaultMode -eq 'BeforeWrite'){'injected_before_write'}else{'simulated_disk_full_before'}
   throw [IO.IOException]::new('r8c.synthetic_fault')
  }
  $written=0
  while($written -lt $n){
   $take=[int][Math]::Min(127,$n-$written)
   # This method has no partial-return contract; counts only successful
   # completed FileStream.Write calls. If OS raises I/O error mid-call, actual
   # committed bytes may be unknown; never claim precise physical disk bytes.
   $owned.Write($SyntheticCandidateBytes,$written,$take)
   $written+=$take;$m.writeCalls++;$m.successfulWriteBytes=$written
   if($FaultMode -in @('AfterPartialWrite','DiskFullPartial')){
    $m.failureStage=if($FaultMode -eq 'AfterPartialWrite'){'injected_after_partial_write'}else{'simulated_disk_full_partial'}
    throw [IO.IOException]::new('r8c.synthetic_fault')
   }
  }
  $owned.Flush($true)
  if($FaultMode -in @('AfterFullWrite','BeforeReadback')){
   $m.failureStage='injected_full_write_before_verify'
   throw [IO.IOException]::new('r8c.synthetic_fault')
  }
  [void]$owned.Seek(0,[IO.SeekOrigin]::Begin)
  [byte[]]$readback=[byte[]]::new($n)
  $gotTotal=0
  while($gotTotal -lt $n){
   $got=$owned.Read($readback,$gotTotal,[Math]::Min(127,$n-$gotTotal))
   $m.readCalls++
   if($got -le 0){$m.failureStage='readback_eof';throw [IO.IOException]::new('r8c.synthetic_readback_eof')}
   $gotTotal+=$got;$m.readbackReturnedBytes=$gotTotal
   if($FaultMode -eq 'DuringReadback'){
    $m.failureStage='injected_mid_readback'
    throw [IO.IOException]::new('r8c.synthetic_fault')
   }
  }
  $verifiedSha=Get-ChappyCR8Hash $readback
  if($FaultMode -eq 'DigestMismatch'){
   # Corrupt ONLY the test verification claim, never intentionally alter disk.
   $verifiedSha=('0'+$verifiedSha.Substring(1))
   if($verifiedSha -ceq $initialSha){$verifiedSha=('1'+$verifiedSha.Substring(1))}
  }
  if($verifiedSha -cne $initialSha){
   $m.failureStage='synthetic_digest_mismatch'
   throw [IO.IOException]::new('r8c.synthetic_digest_mismatch')
  }
  if((Get-ChappyCR8Hash $SyntheticCandidateBytes) -cne $initialSha){
   $m.failureStage='candidate_modified'
   throw [IO.IOException]::new('r8c.synthetic_source_changed')
  }
  if($null -eq (Test-ChappyCR8DisposableRoot -Path $root)){
   $m.failureStage='root_changed_before_completion'
   throw [IO.IOException]::new('r8c.synthetic_root_changed_before_completion')
  }
  $complete=$true
  $out.status='complete';$out.decision='synthetic_candidate_readback_verified_original_UNKNOWN'
  $out.outputName=$fileName;$out.outputBytes=$n;$out.outputSha256=$initialSha
  $out.outputVerified=$true;$out.sourceUnchanged=$true
  $out.warningCodes=@('r8c.synthetic_candidate_digest_not_original_identity')
 }catch {
  # Sanitized stable codes only: never leak exception text, paths or byte data.
  if($m.failureStage -eq 'none'){$m.failureStage='write_or_collision_unknown'}
  $out.status='partial';$out.decision='synthetic_write_or_readback_failed_UNKNOWN'
  $out.warningCodes=@('r8c.output_failure_or_collision_UNKNOWN')
  $out.sourceUnchanged=((Get-ChappyCR8Hash $SyntheticCandidateBytes) -ceq $initialSha)
 }finally {
  if($created -and -not $complete -and $null -ne $owned){
   if($null -eq (Test-ChappyCR8DisposableRoot -Path $root)){
    $m.cleanupStatus='unverified_root_left_intact'
   }else{
    try{
     $cleanupMarked=[ChappyCR8OwnedFileDispositionV1]::MarkExactOwnedForDeletion($owned,$destination)
     $m.ownedHandleMatchedForCleanup=$cleanupMarked
     $m.cleanupStatus=if($cleanupMarked){'owned_handle_delete_marked'}else{'unverified_handle_left_intact'}
    }catch{$m.cleanupStatus='unverified_handle_left_intact'}
   }
  }
  if($null -ne $owned){$owned.Dispose()}
 }
 return [pscustomobject]$out
}
Export-ModuleMember -Function Invoke-ChappyR8SyntheticFaultWriterV1
