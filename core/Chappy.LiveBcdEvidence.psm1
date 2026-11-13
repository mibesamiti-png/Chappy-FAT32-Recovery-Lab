#Requires -Version 5.1
# A7-01: ONE real B/C/D module path, ONE bounded in-process memory Stream.
# Artificial sources only; never handles a FileStream, device or IMG path.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\modules\directory\DirectoryScanner.ps1')
. (Join-Path $PSScriptRoot '..\modules\directory\DirectoryHierarchy.ps1')
Import-Module (Join-Path $PSScriptRoot '..\modules\carving\Chappy.Carving.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\modules\fat-analysis\Fat32ObservedIoEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Chappy.CandidateDefinitionBoundary.psm1') -Force
. (Join-Path $PSScriptRoot '..\modules\directory\DirectoryEvidenceEnvelope.ps1')
. (Join-Path $PSScriptRoot '..\modules\directory\DirectoryReadReconciliation.ps1')
. (Join-Path $PSScriptRoot '..\modules\directory\DirectoryParentObservationJoin.ps1')
Import-Module (Join-Path $PSScriptRoot '..\modules\fat-analysis\Fat32GuardedResult.psm1') -Force

if(-not ('ChappyA7LiveMeterV1' -as [type])){
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public sealed class ChappyA7LiveReadV1 {
 public string Consumer {get;set;}
 public long OffsetBytes {get;set;}
 public int ReturnedBytes {get;set;}
}
public sealed class ChappyA7LiveMeterV1:Stream{
 readonly Stream s;readonly long quota;readonly int cap;
 readonly HashSet<long> unique=new HashSet<long>();
 readonly List<ChappyA7LiveReadV1> records=new List<ChappyA7LiveReadV1>();
 string consumer="";long used=0,calls=0;
 public ChappyA7LiveMeterV1(Stream source,long bytes,int readCap){
  if(source==null||!source.CanRead||!source.CanSeek||source.CanWrite)
   throw new ArgumentException("Read-only seekable source required");
  if(bytes<1024||bytes>120000||readCap<1||readCap>512)
   throw new ArgumentException("Invalid bounded source quota");
  s=source;quota=bytes;cap=readCap;
 }
 public void BeginConsumer(string c){
  if(c!="geometry"&&c!="directory"&&c!="carving"&&c!="fat"&&c!="candidate_validation")
   throw new ArgumentException("Invalid consumer label");
  consumer=c;
 }
 public ChappyA7LiveReadV1[] Events {get{return records.ToArray();}}
 public long Returned {get{return used;}}
 public long Unique {get{return unique.Count;}}
 public long Repeated {get{return used-unique.Count;}}
 public long Calls {get{return calls;}}
 public override bool CanRead{get{return true;}}
 public override bool CanWrite{get{return false;}}
 public override bool CanSeek{get{return true;}}
 public override long Length{get{return s.Length;}}
 public override long Position{get{return s.Position;}set{throw new NotSupportedException();}}
 public override long Seek(long offset,SeekOrigin origin){return s.Seek(offset,origin);}
 public override int Read(byte[] b,int o,int n){
  if(String.IsNullOrEmpty(consumer))throw new InvalidOperationException("Phase required");
  if(b==null||o<0||n<0||o>b.Length-n)throw new ArgumentException("Invalid read");
  if(calls>=cap||n>quota-used)throw new IOException("A7.physical_budget_exhausted");
  calls++;long at=s.Position;int got=s.Read(b,o,n);
  if(got>0){
   if(at<0||at>s.Length-got)throw new IOException("A7.returned_out_of_bounds");
   used+=got;
   records.Add(new ChappyA7LiveReadV1{Consumer=consumer,OffsetBytes=at,ReturnedBytes=got});
   for(long k=0;k<got;k++)unique.Add(at+k);
  }
  return got;
 }
 public override void Flush(){}
 public override void SetLength(long x){throw new NotSupportedException();}
 public override void Write(byte[] b,int o,int n){throw new NotSupportedException();}
 protected override void Dispose(bool disposing){base.Dispose(disposing);}
}
'@
}
function Invoke-ChappyA7SyntheticLiveBcdEnvelope {
 [CmdletBinding(PositionalBinding=$false)]
 param(
  [Parameter(Mandatory)][IO.Stream]$Source,
  [switch]$EnableSyntheticLiveBcd,
  # Preserves old A contract unless explicitly selected.
  [switch]$UseVersionedBDContracts,
  # Requires versioned B and actual A-owned meter; not a caller event array.
  [switch]$BindAObservedDirectoryReceipts,
  [ValidateRange(1024,120000)][long]$MaxPhysicalReadBytes=120000,
  [ValidateRange(1,512)][int]$MaxReadCalls=512
 )
 $result=[ordered]@{
  schemaVersion='a7_live_bcd_envelope_v1';team='A'
  status='disabled';mode='synthetic_memory_only_optin'
  originalIdentity='unknown';recoveredOriginalFiles=0
  canExport=$false;canSelectFatCopy=$false
  sourceAuthority='A_in_process_returned_bytes_not_real_media_authenticity'
  sourceReadEvidence='none';candidateIntegrity='not_original_file_integrity'
  b=[pscustomobject]@{status='unknown';candidateCount=0;edgeCount=0;probableParentEdges=0}
  c=[pscustomobject]@{status='unknown';candidateCount=0;scanIncomplete=$true}
  d=[pscustomobject]@{status='unknown';fatWinner='not_selected';writePermitted=$false}
  candidateDefinitions=@()
  bPhysicalReceipt=[pscustomobject]@{schemaVersion='a7_directory_source_receipt_v1';decision='not_requested';outerEventOrigin='none';sourceAuthenticity='not_proven';observedCompletedSpans=0;observedStructuralPairs=0;originalParent='unknown';canExport=$false}
  warnings=@('a7.optin_required')
  metrics=[pscustomobject]@{
   actualReturnedBytes=0L;uniqueReturnedBytes=0L;repeatedReturnedBytes=0L
   physicalReadCalls=0L;maxPhysicalBytes=$MaxPhysicalReadBytes
   geometryReturnedBytes=0L;directoryReturnedBytes=0L
   carvingReturnedBytes=0L;fatReturnedBytes=0L;sourceReadEvents=0
  }
 }
 if(-not $EnableSyntheticLiveBcd){return [pscustomobject]$result}
 $result.status='partial'
 if($BindAObservedDirectoryReceipts -and -not $UseVersionedBDContracts){
  $result.warnings=@('a7.directory_receipt_requires_versioned_B')
  return [pscustomobject]$result
 }
 $result.warnings=@('a7.unobserved_data_remains_unknown')
 if($Source -isnot [IO.MemoryStream] -or -not $Source.CanRead -or
    -not $Source.CanSeek -or $Source.CanWrite -or
    $Source.Length -lt 2MB -or $Source.Length -gt 100MB){
    $result.warnings=@('a7.strict_nonwritable_synthetic_memory_required')
    return [pscustomobject]$result
 }
 $meter=[ChappyA7LiveMeterV1]::new($Source,$MaxPhysicalReadBytes,$MaxReadCalls)
 try {
  $meter.BeginConsumer('geometry')
  $geo=Get-ChappyFat32Geometry -Stream $meter
  if($null -eq $geo -or $geo.fatCount -ne 2){throw 'A7.geometry_unresolved'}
  $meter.BeginConsumer('directory')
  if($UseVersionedBDContracts){
   $directory=Get-ChappyBDirectoryEvidenceV1 -Stream $meter -Geometry $geo -EnableDirectoryEvidenceV1 -MaxScanBytes ([long][Math]::Min(1024,[long]$geo.clusterSizeBytes)) -MaxCandidates 16 -MaxDirectories 4 -MaxReadSpans 8 -MaxNodes 16 -MaxEdges 16
   if($directory.schemaVersion -cne 'b_directory_evidence_v1' -or $directory.status -ceq 'error' -or [string]$directory.metrics.sourceReadAttestation -cne 'unattested'){throw 'A7.versioned_B_contract_unknown_or_invalid'}
   $probable=@($directory.parentEdges|Where-Object {$_.confidence -ceq 'probable'}).Count
   $result.b=[pscustomobject]@{status=[string]$directory.status;schemaVersion='b_directory_evidence_v1';candidateCount=@($directory.candidates).Count;edgeCount=@($directory.parentEdges).Count;probableParentEdges=$probable;sourceReadAttestation='B_unattested_A_checks_outer_source'}
  }else{
   $dirArgs=@{Stream=$meter;Geometry=$geo;MaxScanBytes=[int][Math]::Min(1024,[long]$geo.clusterSizeBytes);MaxCandidates=16;MaxDirectories=4;RecordDirectoryReadSpans=$true;MaxDirectoryReadSpans=8}
   $directory=Get-ChappyDirectoryCandidates @dirArgs
   $hierarchy=Get-ChappyDirectoryHierarchyEvidence -DirectoryResult $directory -MaxNodes 256 -MaxEdges 256 -NeverPromoteUnattestedParentEdges
   $probable=@($hierarchy.edges|Where-Object {$_.confidence -ceq 'probable'}).Count
   $result.b=[pscustomobject]@{status=[string]$directory.status;candidateCount=@($directory.items).Count;edgeCount=@($hierarchy.edges).Count;probableParentEdges=$probable}
  }
  if($probable -ne 0){throw 'A7.unattested_parent_confidence'}
  if($BindAObservedDirectoryReceipts){
   # Actual positive Stream.Read returns from THIS live A meter only.
   $aEvents=@($meter.Events | ForEach-Object {
    [pscustomobject]@{Consumer=[string]$_.Consumer;OffsetBytes=[long]$_.OffsetBytes;ReturnedBytes=[int]$_.ReturnedBytes}
   })
   $match=Compare-ChappyBDirectoryReturnedEvidenceV1 -DirectoryEnvelope $directory -OuterReadEvents @($aEvents) -SourceLengthBytes ([long]$Source.Length) -MaxEvents 512 -MaxSpans 8
   $parent=Get-ChappyBParentObservationV1 -DirectoryEnvelope $directory -OuterReadEvents @($aEvents) -SourceLengthBytes ([long]$Source.Length) -MaxEvents 512 -MaxSpans 8 -MaxEdges 16
   if($match.decision -ceq 'contradicted' -or
      $parent.intervalJoin -ceq 'contradicted'){
    throw 'A7.directory_A_meter_vs_B_source_ledger_contradicted'
   }
   $sourceDecision=$(if($match.decision -ceq 'consistent_unattested'){
     'A_in_process_returned_intervals_consistent'
    }else{'partial_unknown'})
   $result.bPhysicalReceipt=[pscustomobject]@{
    schemaVersion='a7_directory_source_receipt_v1'
    decision=$sourceDecision
    outerEventOrigin='A_in_process_live_Stream_Read_only'
    sourceAuthenticity='not_real_media_authenticated'
    observedCompletedSpans=[int]$match.metrics.matchingCompletedSpans
    observedStructuralPairs=[int]$parent.metrics.observedPairUnattested
    originalParent='unknown';canExport=$false
   }
  }

  $meter.BeginConsumer('carving')
  $cArgs=@{Stream=$meter;MaxScanBytes=65536;ExtraValidationReadBytes=32768;MaxFileBytes=4096;MaxCandidates=16;MaxProbes=16;MaxProbeBytes=8192}
  $carving=Get-ChappyCarvingCandidates @cArgs
  $result.c=[pscustomobject]@{status=[string]$carving.status;candidateCount=@($carving.items).Count;scanIncomplete=[bool]$carving.scanIncomplete}
  $token='A7_memory_'+[guid]::NewGuid().ToString('N')
  $proposals=New-Object 'System.Collections.Generic.List[object]'
  foreach($item in @($carving.items)){
   $format=[string]$item.format
   [long]$offset=$item.offsetBytes
   [long]$length=$item.lengthBytes
   if($format -cnotin @('3mf','zip','stl','stl_ascii','stl_binary','gcode','unknown') -or
      $offset -lt 0 -or $length -le 0 -or $offset -gt $Source.Length-$length){continue}
   $extent=[pscustomobject]@{offsetBytes=$offset;lengthBytes=$length}
   $proposals.Add([pscustomobject]@{candidateId=($format+':'+$offset+'+'+$length);sourceToken=$token;format=$format;extents=@($extent)})
  }
  $defined=Resolve-ChappyCandidateDefinitionBoundary -ImageLengthBytes ([long]$Source.Length) -SourceToken $token -Proposals @($proposals.ToArray())
  $result.candidateDefinitions=@($defined.candidates|ForEach-Object{
   [pscustomobject]@{candidateId=$_.candidateId;format=$_.format;orderedExtents=@($_.orderedExtents);status=$_.status;physicalCandidateValidation='not_performed';originalIdentity='unknown'}
  })
  $meter.BeginConsumer('fat')
  if($UseVersionedBDContracts){
   # D guard checks competing VBRs BEFORE any optional fixed FAT reads.
   $fat=Get-ChappyFatGuardedResult -Stream $meter -EnableGuardedDiagnostics -MaxPhysicalReadBytes 4096 -MaxPhysicalReadCalls 256
   if($fat.contractVersion -cne 'd6_guarded_fat_result_v1' -or $fat.writePermitted -or $fat.fatCopyWinner -cne 'not_selected'){throw 'A7.versioned_D_contract_invalid'}
   $result.d=[pscustomobject]@{status=[string]$fat.status;contractVersion='d6_guarded_fat_result_v1';guardDecision=[string]$fat.guardDecision;fatProbeState=[string]$fat.fatProbeState;fatFixedReturnedBytes=$(if($null -eq $fat.metrics.fatFixedReturnedBytes){$null}else{[long]$fat.metrics.fatFixedReturnedBytes});fatWinner='not_selected';writePermitted=$false;sourceReadAttestation='D_unattested_A_checks_outer_source'}
  }else{
   $fat=Get-ChappyFatObservedIoEvidence -Stream $meter -Mode MirrorAndChain -MaxReadBytes 2048
   $result.d=[pscustomobject]@{status=[string]$fat.status;fatWinner='not_selected';writePermitted=$false}
  }
  $total=@{geometry=0L;directory=0L;carving=0L;fat=0L}
  $events=@($meter.Events)
  foreach($event in $events){
   if(-not $total.ContainsKey([string]$event.Consumer)){throw 'A7.unrecognized_consumer'}
   $total[[string]$event.Consumer]+=[long]$event.ReturnedBytes
  }
  $bExpected=$(if($UseVersionedBDContracts){[long]$directory.metrics.bReturnedDirectoryBytes}else{[long]$directory.metrics.bytesRead})
  $dExpected=$(if($UseVersionedBDContracts){[long]$fat.metrics.actualReturnedBytes}else{[long]$fat.metrics.bytesRead})
  if($total.directory -ne $bExpected -or
     $total.carving -ne [long]$carving.metrics.bytesRead -or
     $total.fat -ne $dExpected -or
     ($total.geometry+$total.directory+$total.carving+$total.fat) -ne $meter.Returned){
      throw 'A7.source_meter_and_module_counts_disagree'
  }
  $result.sourceReadEvidence='in_process_source_reads_reconciled_not_candidate_receipts'
  $result.warnings=@('a7.no_candidate_validation_receipts','a7.original_identity_unknown','a7.no_fat_owner_or_winner')
  $result.metrics=[pscustomobject]@{
   actualReturnedBytes=$meter.Returned;uniqueReturnedBytes=$meter.Unique
   repeatedReturnedBytes=$meter.Repeated;physicalReadCalls=$meter.Calls
   maxPhysicalBytes=$MaxPhysicalReadBytes
   geometryReturnedBytes=$total.geometry;directoryReturnedBytes=$total.directory
   carvingReturnedBytes=$total.carving;fatReturnedBytes=$total.fat
   sourceReadEvents=$events.Count
  }
 }catch{
  # Under unknown/early EOF/budget or module errors disclose no candidate winner.
  $result.status='partial'
  $result.b=[pscustomobject]@{status='unknown';candidateCount=0;edgeCount=0;probableParentEdges=0}
  $result.c=[pscustomobject]@{status='unknown';candidateCount=0;scanIncomplete=$true}
  $result.d=[pscustomobject]@{status='unknown';fatWinner='not_selected';writePermitted=$false}
  $result.candidateDefinitions=@()
  $result.bPhysicalReceipt=[pscustomobject]@{schemaVersion='a7_directory_source_receipt_v1';decision='unattributed';outerEventOrigin='A_in_process_live_Stream_Read_only';sourceAuthenticity='not_proven';observedCompletedSpans=0;observedStructuralPairs=0;originalParent='unknown';canExport=$false}
  $result.sourceReadEvidence='unattributed'
  $result.warnings=@('a7.source_or_module_incomplete_unknown')
  $result.metrics=[pscustomobject]@{
   actualReturnedBytes=$meter.Returned;uniqueReturnedBytes=$meter.Unique
   repeatedReturnedBytes=$meter.Repeated;physicalReadCalls=$meter.Calls
   maxPhysicalBytes=$MaxPhysicalReadBytes
   geometryReturnedBytes=$null;directoryReturnedBytes=$null
   carvingReturnedBytes=$null;fatReturnedBytes=$null
   sourceReadEvents=@($meter.Events).Count
  }
 }
 return [pscustomobject]$result
}
Export-ModuleMember -Function Invoke-ChappyA7SyntheticLiveBcdEnvelope