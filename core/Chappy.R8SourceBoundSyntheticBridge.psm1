#Requires -Version 5.1
# Team A R8-P3. Bounded synthetic-only read-only MemoryStream input; no
# physical card, IMG paths, auto original winner, or real media extraction.
# R7 and R8 are TWO A-meter sessions on the same artificial source, never
# an invented single-session proof or authentic original-byte claim.
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Chappy.PublicEvidenceV1.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Chappy.SyntheticSeparateExportV1.psm1') -Force

function Export-ChappyR8SourceBoundSyntheticCandidateV1 {
 [CmdletBinding(PositionalBinding=$false)]
 param(
  [Parameter(Mandatory)][IO.Stream]$Source,
  [Parameter(Mandatory)][string]$OutputRoot,
  [Parameter(Mandatory)][string]$SyntheticFixtureTag,
  [switch]$EnableSyntheticR7SourceBindingAndExport,
  [ValidateRange(1024,120000)][long]$MaxR7ReturnedBytes=120000,
  [ValidateRange(1024,8192)][long]$MaxCandidateReturnedBytes=4096,
  [ValidateRange(1,512)][int]$MaxCandidateReadCalls=16,
  [switch]$InjectSyntheticWriteFailure
 )
 $m=[pscustomobject][ordered]@{
  r7ActualReturnedBytes=0L;r7UniqueReturnedBytes=0L;r7RepeatedReturnedBytes=0L
  r7PhysicalReadCalls=0L;r8CandidateActualReturnedBytes=0L
  r8CandidateUniqueReturnedBytes=0L;r8CandidateRepeatedReturnedBytes=0L
  r8CandidatePhysicalReadCalls=0L;projectedCandidateBytes=0L
 }
 $result=[ordered]@{
  schemaVersion='r8_synthetic_r7_source_binding_v1';team='A'
  status='disabled';decision='not_requested'
  evidenceScope='artificial_readonly_memory_only_default_off'
  sourceAuthenticity='not_proven';originalIdentity='unknown'
  originalShaVerified=$false;canSelectOriginal=$false
  canExportOriginal=$false;canRepairOriginal=$false
  r7SourceSessionCount=0;r8CandidateRereadSessionCount=0
  sourcePhaseAccounting='no_sessions'
  r7CandidateId=$null;candidateCount=0
  numericDataWindowTrust='B_numeric_BPB_unverified'
  outputBytes=0;outputName=$null;outputPath=$null;outputSha256=$null
  outputVerified=$false;syntheticProjectionOnly=$true
  warningCodes=@('r8.synthetic_source_binding_optin_required')
  metrics=$m
 }
 if(-not $EnableSyntheticR7SourceBindingAndExport){return [pscustomobject]$result}
 $result.status='rejected';$result.decision='synthetic_input_or_output_contract_UNKNOWN'
 $result.warningCodes=@('r8.generated_input_and_disposable_output_only')
 if($Source -isnot [IO.MemoryStream] -or -not $Source.CanRead -or
    -not $Source.CanSeek -or $Source.CanWrite -or
    [long]$Source.Length -lt 2MB -or [long]$Source.Length -gt 100MB -or
    $SyntheticFixtureTag -cnotmatch '^A3D-standard-[0-9]{1,6}$'){
  return [pscustomobject]$result
 }
 $result.status='partial';$result.decision='source_binding_incomplete_UNKNOWN'
 $result.warningCodes=@('r8.original_identity_and_unscanned_source_UNKNOWN')
 try {
  # Actual R7 report came from the real A protected B/C/D/C-candidate meter.
  # That source meter is PRIVATE to R7. A later R8 reread is a SEPARATE meter.
  $r7=Get-ChappyA7PublicEvidenceV1 -Source $Source -EnableSyntheticPublicEvidence -MaxPhysicalReadBytes $MaxR7ReturnedBytes
  $result.r7SourceSessionCount=1
  $result.sourcePhaseAccounting='two_separate_A_source_sessions_do_not_pool_unique_bytes'
  $m.r7ActualReturnedBytes=[long]$r7.metrics.actualReturnedBytes
  $m.r7UniqueReturnedBytes=[long]$r7.metrics.uniqueReturnedBytes
  $m.r7RepeatedReturnedBytes=[long]$r7.metrics.repeatedReturnedBytes
  $m.r7PhysicalReadCalls=[long]$r7.metrics.physicalReadCalls
  $hypotheses=@($r7.candidateDefinitions)
  $result.candidateCount=$hypotheses.Count
  if($r7.schemaVersion -cne 'a7_public_evidence_v1' -or
     $r7.decision -cne 'source_observed_structural_candidates_only' -or
     $r7.sourceAuthority -cne 'A_same_invocation_protected_Stream_Read' -or
     $r7.sourceAuthenticity -cne 'not_real_media_authenticated' -or
     $r7.originalIdentity -cne 'unknown' -or
     $r7.originalShaVerified -or $r7.canExport -or $r7.canSelectOriginal -or
     $r7.outcome.oracleByteIdentity -cne 'test_only_not_evaluated' -or
     $hypotheses.Count -ne 1){
   $result.warningCodes=@('r8.R7_missing_or_multiple_hypotheses_UNKNOWN')
   return [pscustomobject]$result
  }
  $candidate=$hypotheses[0]
  $extents=@($candidate.orderedPhysicalExtents)
  if($extents.Count -ne 2 -or $candidate.format -cne '3mf' -or
     $candidate.integrityScope -cne 'structural_only_not_original_file_integrity' -or
     $candidate.readEvidenceStatus -cne 'A_in_process_source_observed' -or
     $candidate.originalIdentity -cne 'unknown' -or
     $candidate.originalShaVerified -or
     $candidate.canSelectOriginal -or $candidate.canExport -or $candidate.canRepair){
   $result.warningCodes=@('r8.R7_candidate_contract_inconsistent_UNKNOWN')
   return [pscustomobject]$result
  }
  [long]$total=0L
  [int]$sequence=0
  foreach($e in $extents){
   if($null -eq $e.PSObject.Properties['offsetBytes'] -or
      $null -eq $e.PSObject.Properties['lengthBytes'] -or
      $null -eq $e.PSObject.Properties['sequence']){
    throw 'r8.missing_ordered_extent'
   }
   [long]$at=[long]$e.offsetBytes
   [long]$len=[long]$e.lengthBytes
   if($at -lt 0 -or $len -le 0 -or $len -gt 4096L -or
      $at -gt ([long]$Source.Length-$len) -or
      [int]$e.sequence -ne $sequence){
    throw 'r8.candidate_extent_invalid'
   }
   $total+=$len
   if($total -gt 4096L){throw 'r8.candidate_bytes_cap'}
   $sequence++
  }
  [long]$f=[long]$extents[0].offsetBytes
  [long]$flen=[long]$extents[0].lengthBytes
  [long]$t=[long]$extents[1].offsetBytes
  [long]$tlen=[long]$extents[1].lengthBytes
  if(($f -lt ($t+$tlen) -and $t -lt ($f+$flen)) -or
     [string]$candidate.candidateId -cne ('3mf:{0}+{1},{2}+{3}' -f $f,$flen,$t,$tlen) -or
     [long]$candidate.sourceObservedReturnedBytes -ne $total -or
     $total -lt 1L -or $total -gt $MaxCandidateReturnedBytes){
   $result.warningCodes=@('r8.candidate_id_length_or_overlap_UNKNOWN')
   return [pscustomobject]$result
  }
  # SECOND independently counted A meter; never conflate its returned-byte
  # intervals or unique-byte union with R7's separate invocation.
  $meter=[ChappyA7LiveMeterV1]::new($Source,$MaxCandidateReturnedBytes,$MaxCandidateReadCalls)
  $meter.BeginConsumer('candidate_validation')
  $result.r8CandidateRereadSessionCount=1
  # Legacy R8 exporter accepts only <=128KiB tiny synthetic byte[] input.
  # Compact reproject the two source extents, padding to its minimum 1024B.
  [byte[]]$projection=[byte[]]::new([int][Math]::Max(1024L,$total))
  [long]$written=0L
  foreach($extent in $extents){
   [long]$position=[long]$extent.offsetBytes
   [long]$remain=[long]$extent.lengthBytes
   [void]$meter.Seek($position,[IO.SeekOrigin]::Begin)
   while($remain -gt 0L){
    $next=[int][Math]::Min(512L,$remain)
    $pre=@($meter.Events).Count
    $got=$meter.Read($projection,[int]$written,$next)
    if($got -le 0){throw 'r8.physical_candidate_source_early_zero_UNKNOWN'}
    $actual=@($meter.Events)
    if($actual.Count -ne ($pre+1) -or
       $actual[$pre].Consumer -cne 'candidate_validation' -or
       [long]$actual[$pre].OffsetBytes -ne $position -or
       [long]$actual[$pre].ReturnedBytes -ne $got){
     throw 'r8.candidate_physical_event_mismatch'
    }
    $written+=$got;$remain-=$got;$position+=$got
   }
  }
  $m.r8CandidateActualReturnedBytes=$meter.Returned
  $m.r8CandidateUniqueReturnedBytes=$meter.Unique
  $m.r8CandidateRepeatedReturnedBytes=$meter.Repeated
  $m.r8CandidatePhysicalReadCalls=$meter.Calls
  $m.projectedCandidateBytes=$written
  if($written -ne $total -or $meter.Returned -ne $total -or
     $meter.Unique -gt $meter.Returned -or $meter.ZeroReads -ne 0L){
   throw 'r8.physical_candidate_incomplete_UNKNOWN'
  }
  $compactExtents=@(
   [pscustomobject]@{offsetBytes=0L;lengthBytes=$flen},
   [pscustomobject]@{offsetBytes=$flen;lengthBytes=$tlen}
  )
  $compactId=('3mf:{0}+{1},{2}+{3}' -f 0,$flen,$flen,$tlen)
  $result.r7CandidateId=[string]$candidate.candidateId
  $exportArgs=@{
   SourceBytes=$projection;CandidateId=$compactId
   OrderedExtents=$compactExtents;OutputRoot=$OutputRoot
   SyntheticFixtureTag=$SyntheticFixtureTag;EnableSyntheticExport=$true
   MaxOutputBytes=4096
   InjectSyntheticWriteFailure=[bool]$InjectSyntheticWriteFailure
  }
  $out=Export-ChappyR8SyntheticCandidateV1 @exportArgs
  if($out.status -cne 'complete' -or
     $out.decision -cne 'synthetic_output_sha_verified_original_UNKNOWN' -or
     -not $out.outputVerified -or -not $out.sourceUnchanged -or
     $out.originalShaVerified -or $out.canExportOriginal -or
     [long]$out.outputBytes -ne $total){
   $result.warningCodes=@('r8.synthetic_output_failed_or_unverified_UNKNOWN')
   return [pscustomobject]$result
  }
  $result.status='complete'
  $result.decision='synthetic_source_bound_output_verified_original_UNKNOWN'
  $result.outputBytes=[int]$out.outputBytes
  $result.outputName=[string]$out.outputName
  $result.outputPath=[string]$out.outputPath
  $result.outputSha256=[string]$out.outputSha256
  $result.outputVerified=$true
  $result.sourceAuthenticity='not_real_media_authenticated'
  $result.warningCodes=@('r8.synthetic_source_label_not_authenticated',
                         'r8.R7_R8_different_source_meter_sessions',
                         'r8.output_SHA_not_original_oracle_SHA',
                         'r8.real_media_export_not_authorized')
 }catch{
  $result.status='partial';$result.decision='synthetic_source_or_output_failure_UNKNOWN'
  $result.warningCodes=@('r8.source_or_output_incomplete_UNKNOWN')
 }
 return [pscustomobject]$result
}
Export-ModuleMember -Function Export-ChappyR8SourceBoundSyntheticCandidateV1
