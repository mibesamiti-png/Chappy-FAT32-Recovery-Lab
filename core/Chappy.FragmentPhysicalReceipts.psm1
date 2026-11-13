#Requires -Version 5.1
# Team A / A7-02/A7-04 — actual C two-piece candidate, A-scoped physical reread.
# Strictly generated nonwritable MemoryStream; NO real IMG/device/path or bytes export.
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Chappy.LiveBcdEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Chappy.CandidateDefinitionBoundary.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\modules\carving\Chappy.FragmentEvidence.psm1') -Force
# B supplies candidate geometry; A witnesses every physical return. Geometry is not authentic volume truth.
. (Join-Path $PSScriptRoot '..\modules\directory\DirectoryScanner.ps1')

function Invoke-ChappyA7FragmentPhysicalReceipts {
 [CmdletBinding(PositionalBinding=$false)]
 param(
  [Parameter(Mandatory)][IO.Stream]$Source,
  [switch]$EnableA7FragmentReceipts,
  # Default legacy compact behavior remains unchanged; opt-in standards-shaped synthetic FAT32 data window.
  [switch]$EnableStandardFAT32DataWindow,
  [ValidateRange(1024,120000)][long]$MaxPhysicalReadBytes=120000,
  [ValidateRange(1,512)][int]$MaxReadCalls=512
 )
 $metrics=[pscustomobject][ordered]@{
  actualReturnedBytes=0L;uniqueReturnedBytes=0L;repeatedReturnedBytes=0L
  physicalReadCalls=0L;geometryReturnedBytes=0L;scanReturnedBytes=0L;validationReturnedBytes=0L
  sourceReadEvents=0;maxPhysicalBytes=$MaxPhysicalReadBytes
 }
 $result=[ordered]@{
  schemaVersion='a7_fragment_physical_receipts_v1';status='disabled'
  mode='synthetic_memory_only_explicit_optin'
  sourceAuthority='A_in_process_successful_return_not_real_media_authentication'
  originalIdentity='unknown';originalShaVerified=$false
  canSelectOriginal=$false;canExport=$false;canRepair=$false
  sourceToken=$null;sourceReadScope='none'
  dataWindowOrigin='not_requested';dataWindowStartBytes=$null
  cStatus='not_run';cDecision='unknown';cScanIncomplete=$true
  candidateDefinitions=@();candidateCount=0
  sourceObservedCandidateCount=0;incompleteCandidateCount=0
  warnings=@('a7.fragment_receipts_optin_required')
  metrics=$metrics
 }
 if(-not $EnableA7FragmentReceipts){return [pscustomobject]$result}
 $result.status='partial'
 $result.warnings=@('a7.real_original_identity_unknown')
 if($Source -isnot [IO.MemoryStream] -or -not $Source.CanRead -or
    -not $Source.CanSeek -or $Source.CanWrite -or
    $Source.Length -lt 65536 -or
    ($EnableStandardFAT32DataWindow -and $Source.Length -gt 100MB) -or
    (-not $EnableStandardFAT32DataWindow -and $Source.Length -gt 2097152)) {
  $result.warnings=@('a7.strict_nonwritable_synthetic_memory_required')
  return [pscustomobject]$result
 }
 $meter=[ChappyA7LiveMeterV1]::new($Source,$MaxPhysicalReadBytes,$MaxReadCalls)
 $token='A7F_'+[guid]::NewGuid().ToString('N')
 $result.sourceToken=$token
 try {
  [long]$dataStart=0
  [int]$windowBytes=65536
  if($EnableStandardFAT32DataWindow){
   # B BPB-derived data-region window, NOT the actual original fragment location.
   # All geometry source reads pass through this same protected A memory Stream.
   $meter.BeginConsumer('geometry')
   $bGeometry=Get-ChappyFat32Geometry -Stream $meter
   if($null -eq $bGeometry -or
      [long]$bGeometry.clusterCount -lt 65525L -or
      [int]$bGeometry.fatCount -ne 2 -or
      [long]$bGeometry.dataOffsetBytes -le 65536L -or
      ([long]$bGeometry.dataOffsetBytes % 512L) -ne 0L -or
      [long]$bGeometry.dataOffsetBytes -gt $Source.Length - 32768L){
      throw 'A7.B_numeric_data_window_geometry_unknown'
   }
   $dataStart=[long]$bGeometry.dataOffsetBytes
   $windowBytes=32768
   $result.dataWindowOrigin='A_in_process_B_numeric_geometry_unverified'
   $result.dataWindowStartBytes=$dataStart
   $metrics.geometryReturnedBytes=[long]$meter.Returned
  }
  $meter.BeginConsumer('carving')
  [long]$beforeC=$meter.Returned
  $scanArgs=@{Source=$meter;EnableFragmentEvidence=$true;WindowBytes=$windowBytes
   MaxPairs=16;MaxStarts=4;MaxTails=8;MaxSourceBytes=81920;MaxValidationBytes=98304}
  if($EnableStandardFAT32DataWindow){
   $scanArgs.StartOffsetBytes=$dataStart
   $scanArgs.EnableStandardsShapedSource=$true
   # Fixed bounded hypotheses applied equally, never selected from oracle start/tail.
   $scanArgs.IncludeStartPhasePlusTwo=$true
   $scanArgs.IncludeFirstPiece560=$true
  }
  $scan=Get-ChappyFragmentCandidates @scanArgs
  $result.cStatus=[string]$scan.status
  $result.cDecision=[string]$scan.decision
  $result.cScanIncomplete=[bool]$scan.scanIncomplete
  $scanReturned=[long]($meter.Returned-$beforeC)
  if([long]$scan.metrics.sourceBytesRead -ne $scanReturned){
   throw 'A7.C_scanner_returned_read_disagrees_with_A_meter'
  }
  if($scan.status -cne 'ok' -or @($scan.items).Count -gt 16){
   $result.warnings=@('a7.C_source_incomplete_all_candidates_UNKNOWN')
  }else{
   $found=@($scan.items)
   $proposals=New-Object 'System.Collections.Generic.List[object]'
   foreach($item in $found){
    if($item.originalIdentity -cne 'unknown' -or
       $item.integrityScope -cne 'structural_only_not_original_file_integrity' -or
       @($item.sourceSpans).Count -ne 2){
     throw 'A7.C_candidate_untrusted_or_malformed'
    }
    $proposals.Add([pscustomobject]@{
     candidateId=[string]$item.candidateKey
     format='3mf';sourceToken=$token;extents=@($item.sourceSpans|ForEach-Object{
      [pscustomobject]@{offsetBytes=[long]$_.offsetBytes;lengthBytes=[long]$_.lengthBytes}
     })
    })
   }
   $guard=Resolve-ChappyCandidateDefinitionBoundary -ImageLengthBytes ([long]$Source.Length) -SourceToken $token -Proposals @($proposals.ToArray())
   if($guard.uniqueCandidateIds -gt 16 -or $guard.conflictingCandidateIds -gt 0){
    throw 'A7.C_candidate_definitions_conflict'
   }
   $meter.BeginConsumer('candidate_validation')
   $entries=New-Object 'System.Collections.Generic.List[object]'
   foreach($item in @($guard.candidates)){
    if(-not $item.independentPhysicalReceiptEligible -or
       $item.status -cne 'consistent_definition_only'){
     throw 'A7.C_candidate_definition_not_eligible'
    }
    [long]$expected=0
    [long]$observed=0
    [int]$events=0
    $complete=$true
    foreach($extent in @($item.orderedExtents)){
     [long]$at=[long]$extent.offsetBytes
     [long]$length=[long]$extent.lengthBytes
     $expected+=$length
     [void]$meter.Seek($at,[IO.SeekOrigin]::Begin)
     [long]$cursor=$at
     [long]$remain=$length
     while($remain -gt 0){
      [byte[]]$buffer=[byte[]]::new([int][Math]::Min(512L,$remain))
      $previous=@($meter.Events).Count
      $got=$meter.Read($buffer,0,$buffer.Length)
      if($got -le 0){$complete=$false;break}
      $actual=@($meter.Events)
      if($actual.Count -ne $previous+1 -or
         $actual[$previous].Consumer -cne 'candidate_validation' -or
         [long]$actual[$previous].OffsetBytes -ne $cursor -or
         [long]$actual[$previous].ReturnedBytes -ne $got){
       throw 'A7.candidate_validation_event_not_A_return'
      }
      $cursor+=$got;$remain-=$got;$observed+=$got;$events++
     }
     if(-not $complete){break}
    }
    $valid=($complete -and $observed -eq $expected -and $events -gt 0)
    $entries.Add([pscustomobject]@{
     candidateId=$item.candidateId;format='3mf'
     orderedExtents=@($item.orderedExtents)
     validationScope='A_in_process_candidate_specific_successful_Read'
     readEvidenceStatus=$(if($valid){'source_observed'}else{'unattributed'})
     readReturnedBytes=$observed;expectedExtentBytes=$expected
     candidateValidationReadEvents=$events
     originalIdentity='unknown';originalShaVerified=$false
     canSelectOriginal=$false;canExport=$false
    })
    if(-not $valid){break}
   }
   $result.candidateDefinitions=@($entries.ToArray())
   $result.candidateCount=$entries.Count
   $result.sourceObservedCandidateCount=@($entries|Where-Object{$_.readEvidenceStatus -ceq 'source_observed'}).Count
   $result.incompleteCandidateCount=@($entries|Where-Object{$_.readEvidenceStatus -cne 'source_observed'}).Count
   $result.sourceReadScope='A_candidate_specific_returned_bytes_only'
   $result.warnings=@('a7.original_integrity_not_proven_by_physical_reread',
                      'a7.C_candidate_source_windows_incomplete')
  }
  $metrics.scanReturnedBytes=$scanReturned
  $metrics.validationReturnedBytes=$meter.Returned-$beforeC-$scanReturned
  if($metrics.validationReturnedBytes -lt 0 -or
     $metrics.geometryReturnedBytes+$metrics.scanReturnedBytes+$metrics.validationReturnedBytes -ne $meter.Returned){
   throw 'A7.meter_phase_sum_mismatch'
  }
 }catch{
  $result.candidateDefinitions=@();$result.candidateCount=0
  $result.sourceObservedCandidateCount=0;$result.incompleteCandidateCount=0
  $result.sourceReadScope='unattributed'
  $result.warnings=@('a7.candidate_validation_or_source_unknown')
 }
 $metrics.actualReturnedBytes=$meter.Returned
 $metrics.uniqueReturnedBytes=$meter.Unique
 $metrics.repeatedReturnedBytes=$meter.Repeated
 $metrics.physicalReadCalls=$meter.Calls
 $metrics.sourceReadEvents=@($meter.Events).Count
 return [pscustomobject]$result
}
Export-ModuleMember -Function Invoke-ChappyA7FragmentPhysicalReceipts