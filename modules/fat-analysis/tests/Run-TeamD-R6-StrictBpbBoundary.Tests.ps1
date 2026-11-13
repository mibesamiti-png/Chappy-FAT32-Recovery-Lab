#Requires -Version 5.1
# D6-03 original strict BPB boundary acceptance. Generated nonwritable bytes only.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $root 'tests\helpers\New-ChappyA3DStandardFixture.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Fat32VbrDisagreement.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32GeometryHypothesisGate.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\Fat32GuardedResult.psm1') -Force
$script:Pass=0;$script:Fail=0
function Assert-D603B([bool]$Test,[string]$Message){
 if($Test){$script:Pass++;Write-Host ('PASS '+$Message)}
 else{$script:Fail++;Write-Host ('FAIL '+$Message)}
}
function Put-D603B16([byte[]]$Data,[int]$At,[uint16]$Value){
 [Array]::Copy([BitConverter]::GetBytes($Value),0,$Data,$At,2)
}
function Put-D603B32([byte[]]$Data,[int]$At,[uint32]$Value){
 [Array]::Copy([BitConverter]::GetBytes($Value),0,$Data,$At,4)
}
function Hash-D603B([byte[]]$Data){
 $s=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($s.ComputeHash($Data)).Replace('-','')}
 finally{$s.Dispose()}
}
if(-not ('D603BIndependentSource' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class D603BIndependentSource:Stream {
 readonly MemoryStream input;
 readonly HashSet<long> seen=new HashSet<long>();
 readonly long stop;
 readonly int chunk;
 long returned=0,calls=0,zeros=0,fatCalls=0;
 public D603BIndependentSource(byte[] bytes,long stopAfter,int maxChunk) {
  if(bytes==null||stopAfter<0||maxChunk<1||maxChunk>4096)throw new ArgumentException("Bad artificial source bounds");
  input=new MemoryStream(bytes,false);stop=stopAfter;chunk=maxChunk;
 }
 public long Returned{get{return returned;}}
 public long Unique{get{return seen.Count;}}
 public long Repeated{get{return returned-seen.Count;}}
 public long Calls{get{return calls;}}
 public long EarlyZeros{get{return zeros;}}
 public long FatCalls{get{return fatCalls;}}
 public override bool CanRead{get{return true;}}
 public override bool CanSeek{get{return true;}}
 public override bool CanWrite{get{return false;}}
 public override long Length{get{return input.Length;}}
 public override long Position{get{return input.Position;}set{throw new NotSupportedException();}}
 public override long Seek(long n,SeekOrigin origin){return input.Seek(n,origin);}
 public override int Read(byte[] buffer,int at,int count){
  if(buffer==null||at<0||count<0||at>buffer.Length-count)throw new ArgumentException("Bad Read");
  if(calls>=640||count>8192-returned)throw new IOException("D603B.external_hard_source_cap");
  calls++;
  long pos=input.Position;
  // Every structural sector of these synthetic sources is before byte 8192.
  // No untrusted VBR hypothesis can authorize a nonstructural FAT read.
  if(pos>=8192)fatCalls++;
  if(returned>=stop){if(pos<input.Length)zeros++;return 0;}
  int n=input.Read(buffer,at,(int)Math.Min((long)count,Math.Min((long)chunk,stop-returned)));
  if(n==0&&pos<input.Length)zeros++;
  for(int i=0;i<n;i++)seen.Add(pos+i);
  returned+=n;
  return n;
 }
 public override void Flush(){}
 public override void SetLength(long n){throw new NotSupportedException();}
 public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
 protected override void Dispose(bool disposing){if(disposing)input.Dispose();base.Dispose(disposing);}
}
'@
}
function Observe-D603B{
 param([byte[]]$Image,[switch]$Guarded,[long]$Stop=[long]::MaxValue,[int]$Chunk=512)
 $src=[D603BIndependentSource]::new($Image,$Stop,$Chunk)
 try{
  if($Guarded){$out=Get-ChappyFatGuardedResult -Stream $src -EnableGuardedDiagnostics}
  else{$out=Get-ChappyFatGeometryHypothesisGate -Stream $src}
  return [pscustomobject]@{
   result=$out;actual=$src.Returned;unique=$src.Unique
   repeated=$src.Repeated;calls=$src.Calls;zeros=$src.EarlyZeros
   fatCalls=$src.FatCalls
  }
 }finally{$src.Dispose()}
}
$cases=@(
 [pscustomobject]@{id='clean_spc1';seed=202620;spc=1;mut='none';expect='candidate_geometry_unverified';truth=$false;codes=@();stop=[long]::MaxValue;chunk=512},
 [pscustomobject]@{id='clean_spc2';seed=202621;spc=2;mut='none';expect='candidate_geometry_unverified';truth=$false;codes=@();stop=[long]::MaxValue;chunk=512},
 [pscustomobject]@{id='backup_reserved31';seed=202620;spc=1;mut='reserve31';expect='blocked_conflicting_geometry';truth=$true;codes=@();stop=[long]::MaxValue;chunk=512},
 [pscustomobject]@{id='backup_reserved33';seed=202620;spc=1;mut='reserve33';expect='blocked_conflicting_geometry';truth=$true;codes=@();stop=[long]::MaxValue;chunk=512},
 [pscustomobject]@{id='both_extflags_nonmirror';seed=202620;spc=1;mut='ext80';expect='blocked_contradicted_geometry';truth=$true;codes=@('bpb.extended_flags_not_mirrored_fixed_compatible');stop=[long]::MaxValue;chunk=512},
 [pscustomobject]@{id='both_extflags_reserved';seed=202621;spc=2;mut='ext100';expect='blocked_contradicted_geometry';truth=$true;codes=@('bpb.extended_flags_not_mirrored_fixed_compatible');stop=[long]::MaxValue;chunk=512},
 [pscustomobject]@{id='both_hidden_sector2';seed=202620;spc=1;mut='both_hidden';expect='blocked_contradicted_geometry';truth=$true;codes=@('bpb.hidden_sectors_disagrees_with_mbr');stop=[long]::MaxValue;chunk=512},
 [pscustomobject]@{id='primary_hidden_sector2';seed=202620;spc=1;mut='primary_hidden';expect='blocked_contradicted_geometry';truth=$true;codes=@('bpb.hidden_sectors_disagrees_with_mbr');stop=[long]::MaxValue;chunk=512},
 [pscustomobject]@{id='backup_hidden_sector2';seed=202620;spc=1;mut='backup_hidden';expect='blocked_contradicted_geometry';truth=$true;codes=@('bpb.hidden_sectors_disagrees_with_mbr');stop=[long]::MaxValue;chunk=512},
 [pscustomobject]@{id='tiny_below_fat32_threshold';seed=202620;spc=1;mut='tiny';expect='blocked_contradicted_geometry';truth=$true;codes=@('geometry.below_fat32_cluster_threshold');stop=[long]::MaxValue;chunk=512},
 [pscustomobject]@{id='backup_fat_capacity_minus1';seed=202620;spc=1;mut='backup_fat_short';expect='blocked_contradicted_geometry';truth=$true;codes=@('geometry.fat_entry_capacity_insufficient');stop=[long]::MaxValue;chunk=512},
 [pscustomobject]@{id='both_spc0';seed=202621;spc=2;mut='spc0';expect='blocked_contradicted_geometry';truth=$true;codes=@('bpb.cluster_sectors_invalid');stop=[long]::MaxValue;chunk=512},
 [pscustomobject]@{id='matching_inrange_shifted_candidate';seed=202620;spc=1;mut='both_reserved33';expect='candidate_geometry_unverified';truth=$null;codes=@();stop=[long]::MaxValue;chunk=512},
 [pscustomobject]@{id='true_short_source_1100';seed=202621;spc=2;mut='none';expect='blocked_insufficient_evidence';truth=$null;codes=@();stop=1100L;chunk=7}
)
$TP=0;$FP=0;$FN=0;$TN=0;$UNKNOWN=0
$sumActual=0L;$sumUnique=0L;$sumCalls=0L;$sumFatCalls=0L
foreach($c in $cases){
 $fixture=New-ChappyA3DStandardFixture -Seed $c.seed -SectorsPerCluster $c.spc
 [byte[]]$image=$fixture.image
 $boot=512;$backup=3584
 switch($c.mut){
  'reserve31' {Put-D603B16 $image ($backup+14) 31}
  'reserve33' {Put-D603B16 $image ($backup+14) 33}
  'ext80' {foreach($at in @($boot,$backup)){Put-D603B16 $image ($at+40) 0x0080}}
  'ext100' {foreach($at in @($boot,$backup)){Put-D603B16 $image ($at+40) 0x0100}}
  'both_hidden' {foreach($at in @($boot,$backup)){Put-D603B32 $image ($at+28) 2}}
  'primary_hidden' {Put-D603B32 $image ($boot+28) 2}
  'backup_hidden' {Put-D603B32 $image ($backup+28) 2}
  'backup_fat_short' {Put-D603B32 $image ($backup+36) 512}
  'spc0' {foreach($at in @($boot,$backup)){$image[$at+13]=0}}
  'both_reserved33' {foreach($at in @($boot,$backup)){Put-D603B16 $image ($at+14) 33}}
  'tiny' {
    # A standards-shaped source becomes a structurally consistent tiny
    # FAT32-lookalike: 200 data clusters, reserved32, 2 FATs x 8 sectors.
    # The scorer NEVER passes that intended cluster count to D.
    $smaller=[byte[]]::new(249*512)
    [Array]::Copy($image,0,$smaller,0,$smaller.Length)
    $image=$smaller
    Put-D603B32 $image 458 248
    foreach($at in @($boot,$backup)){
     Put-D603B32 $image ($at+32) 248
     Put-D603B32 $image ($at+36) 8
    }
    Put-D603B32 $image (1024+488) 198
    Put-D603B32 $image (1024+492) 6
  }
 }
 $before=Hash-D603B $image
 $g=Observe-D603B -Image $image -Stop $c.stop -Chunk $c.chunk
 $d=Observe-D603B -Image $image -Guarded -Stop $c.stop -Chunk $c.chunk
 $r=$g.result;$v=$d.result
 Assert-D603B ((Hash-D603B $image) -ceq $before) ($c.id+' synthetic source byte-identical after two independent reads')
 Assert-D603B ($g.actual -eq $r.metrics.actualReturnedBytes -and
  $g.unique -eq $r.metrics.uniqueReturnedBytes -and
  $g.repeated -eq $r.metrics.repeatedReturnedBytes -and
  $g.calls -eq $r.metrics.physicalReadCalls -and
  $g.actual -le 2048 -and $g.calls -le 256) ($c.id+' D6-03 actual/unique/repeated returned byte and call caps independently metered')
 Assert-D603B ($d.actual -eq $v.metrics.actualReturnedBytes -and
  $d.unique -eq $v.metrics.uniqueReturnedBytes -and
  $d.repeated -eq $v.metrics.repeatedReturnedBytes -and
  $d.calls -eq $v.metrics.physicalReadCalls -and
  $d.actual -le 4096 -and $d.calls -le 512) ($c.id+' D6-05 entire source metered independently and globally bounded')
 Assert-D603B ($r.gateDecision -ceq $c.expect -and
  @($r.hypotheses).Count -eq 2 -and
  $r.hypotheses[0].sourceRole -ceq 'primary' -and
  $r.hypotheses[1].sourceRole -ceq 'backup') ($c.id+' correct independent VBR hypothesis classification with both role slots')
 Assert-D603B ($r.fatRegionProbeCount -eq 0 -and $g.fatCalls -eq 0 -and
  $r.sourceDecision -ceq 'not_selected' -and
  $null -eq $r.selectedCandidate -and -not $r.fatReadAllowed -and
  -not $r.writePermitted -and $r.geometryAuthenticity -ceq 'unknown') ($c.id+' only structural sectors in D6-03, no FAT winner/write')
 Assert-D603B ($v.guardDecision -ceq $c.expect -and
  $v.fatCopyWinner -ceq 'not_selected' -and
  $v.geometryAuthenticity -ceq 'unknown' -and
  $v.fileOwner -ceq 'unknown' -and
  -not $v.canRepair -and -not $v.canExport -and
  -not $v.writePermitted -and @($v.copies).Count -eq 2) ($c.id+' D6-05 live consumer refuses winner/owner/repair under same geometry decision')
 if($c.expect -cne 'candidate_geometry_unverified'){
  Assert-D603B ($d.fatCalls -eq 0 -and
   $v.metrics.fatFixedReturnedBytes -eq 0 -and
   $null -eq $v.evidence.pairedCoveragePercent -and
   $null -eq $v.copies[0].fullyObservedEntries -and
   $null -eq $v.copies[1].fullyObservedEntries) ($c.id+' fail-closed ZERO physical FAT reads when BPB contradicted/conflicting/EOF')
 }else{
  Assert-D603B ($r.matchedNumericHypotheses -and
   $r.geometryAuthenticity -ceq 'unknown' -and
   $v.fatProbeState -ceq 'fixed_baseline_sampled' -and
   $d.fatCalls -gt 0 -and
   $v.evidence.unobservedPairedEntryIndices -gt 65000) ($c.id+' matching BPB remains numeric UNVERIFIED, only explicit fixed bounded sample')
 }
 foreach($code in $c.codes){
  Assert-D603B (@($r.hypotheses|Where-Object {
   $_.contradictionCodes -contains $code
  }).Count -ge 1) ($c.id+' explicit code '+$code)
 }
 if($c.id -eq 'backup_reserved31' -or $c.id -eq 'backup_reserved33'){
  Assert-D603B ($r.hypotheses[0].plausibility -ceq 'plausible_unverified' -and
   $r.hypotheses[1].plausibility -ceq 'plausible_unverified' -and
   $r.hypotheses[0].numericGeometry.fat1OffsetBytes -ne
   $r.hypotheses[1].numericGeometry.fat1OffsetBytes) ($c.id+' both plausible but physical FAT offsets numerically differ by one sector')
 }
 if($c.id -eq 'tiny_below_fat32_threshold'){
  Assert-D603B ($r.agreement -ceq 'agree' -and
   $r.hypotheses[0].numericGeometry.dataClusterCount -eq 200 -and
   $r.hypotheses[1].numericGeometry.dataClusterCount -eq 200) 'Tiny 200-data-cluster FAT32-lookalike cannot be promoted despite matching in-range BPBs'
 }
 if($c.id -eq 'both_hidden_sector2'){
  Assert-D603B ($r.agreement -ceq 'agree' -and
   $r.hypotheses[0].plausibility -ceq 'contradicted' -and
   $r.hypotheses[1].plausibility -ceq 'contradicted') 'Two identical HiddenSectors=2 fields cannot override actual MBR partition start=1'
 }
 if($c.id -eq 'both_extflags_nonmirror'){
  Assert-D603B ($r.agreement -ceq 'agree' -and
   @($r.hypotheses|Where-Object {
    $_.numericGeometry.extendedFlags -eq 128 -and $_.plausibility -ceq 'contradicted'
   }).Count -eq 2) 'Both identical BPB_ExtFlags mirroring-disabled cannot authorize two-copy mirrored FAT inference'
 }
 if($c.id -eq 'matching_inrange_shifted_candidate'){
  Assert-D603B ($r.hypotheses[0].numericGeometry.fat1OffsetBytes -eq 17408 -and
   $v.evidence.pairedFullyObservedEntries -ge 1 -and
   -not $v.wholeFatVerified) 'Two matching shifted FAT positions remain only UNAUTHENTICATED numeric candidates, not known-good location'
 }
 if($c.id -eq 'true_short_source_1100'){
  Assert-D603B ($g.zeros -gt 0 -and $d.zeros -gt 0 -and
   $g.actual -eq 1100 -and $d.actual -eq 1100 -and
   $r.scanIncomplete -and $null -eq $v.evidence.pairedFullyObservedEntries) 'True physical premature zero yields UNKNOWN, no fabricated complete geometry'
 }
 if($null -eq $c.truth){$UNKNOWN++}
 else{
  $detected=($r.gateDecision -ceq 'blocked_contradicted_geometry' -or
             $r.gateDecision -ceq 'blocked_conflicting_geometry')
  if($c.truth){if($detected){$TP++}else{$FN++}}
  else{if($detected){$FP++}else{$TN++}}
 }
 $sumActual+=$g.actual+$d.actual
 $sumUnique+=$g.unique+$d.unique
 $sumCalls+=$g.calls+$d.calls
 $sumFatCalls+=$g.fatCalls+$d.fatCalls
 Write-Host ('D6-03 strict fixture={0}, gate={1}, agreement={2}, actual/unique={3}/{4} B, calls={5}, FATreads={6}, originalOwner=UNKNOWN' -f
  $c.id,$r.gateDecision,$r.agreement,($g.actual+$d.actual),($g.unique+$d.unique),($g.calls+$d.calls),($g.fatCalls+$d.fatCalls))
 $image=$null;$fixture=$null;[GC]::Collect()
}
Assert-D603B ($TP -eq 10 -and $FP -eq 0 -and $FN -eq 0 -and
 $TN -eq 2 -and $UNKNOWN -eq 2) 'Structural BPB contradiction scored TP10 FP0 FN0 TN2, matching-but-unverified/EOF UNKNOWN2'
Write-Host ('D6-03 stricter VBR 14 generated inputs; source physical returned={0}, summed per-source unique={1}, repeated={2}, calls={3}, bounded-FAT calls={4}' -f
 $sumActual,$sumUnique,($sumActual-$sumUnique),$sumCalls,$sumFatCalls)
Write-Host ('Team D D6-03 strict mirror/MBR/FAT32 boundary: {0} PASS / {1} FAIL' -f $script:Pass,$script:Fail)
if($script:Fail -gt 0){exit 1}
