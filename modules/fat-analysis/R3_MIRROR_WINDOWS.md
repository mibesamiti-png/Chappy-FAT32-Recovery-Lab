# Team D R3-P1 — bounded FAT mirror regional comparison

Status: **research, Draft PR review pending**. No real image testing or restoration success is claimed.

## Purpose

`Fat32MirrorWindows.psm1` adds `Get-ChappyFatMirrorWindows`, a separate
Windows PowerShell 5.1 read-only stream analyzer. It measures exact differences
within the windows that were actually read from caller-provided FAT1/FAT2
regions. Both mirror copies may share the *same corruption*; equal bytes are
**not** a FAT health verdict.

This is the first, deliberately bounded R3 task from Issue #9. EB-58 contiguous
region mapping, cluster-chain density and directory/FAT consistency remain
**open** for independent later increments.

## Scope / privacy / no writes

- Input: a readable, seekable, **non-writable** `System.IO.Stream`.
- Caller specifies offsets and FAT length **in bytes**. This module does not
  discover MBR/BPB or verify that any offset belongs to FAT. It rejects negative,
  unaligned, overflowing and overlapping regions; aligned but false offsets
  remain possible and must be verified independently.
- No file paths, disk handles, filesystem writes, raw byte samples, source SHA
  digests, file/directory names or private content emitted. In the public repo
  tests construct small artificial byte arrays in memory.
- The module never calls the synthetic patch simulator or a repair candidate
  function and never authorizes changing media.

## Example: synthetic-only test command

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\modules\fat-analysis\tests\Run-TeamD-R3-Mirror.Tests.ps1
```

Function parameters:
- `-Stream`: strictly read-only.
- `-Fat1OffsetBytes`, `-Fat2OffsetBytes`, `-FatLengthBytes`:
  independently supplied, **not automatically verified** geometry.
- `-StartEntry`: first FAT32 4-byte entry (default 0).
- `-WindowEntries`: entries per window, 1..1024 (default 128).
- `-MaxWindows`: 1..64 (default 8).
- `-StrideEntries`: at least `WindowEntries` (default equal to window size),
  so no entry is counted twice. Larger strides sample disjoint regions.
- `-MaxReadBytes`: cumulative bytes read across **both** mirrors, 8..1,048,576;
  default 65,536. No single operation reads more than 4,096 bytes.

Output follows the interface-v1 envelope with `schemaVersion`, `team`,
`status`, `scanIncomplete`, `items`, `warnings`, `errors`, `metrics`.
Every window exposes:
- `startEntry`, `endEntryExclusive`, `requestedEntries`, `comparedEntries`;
- `equalEntries`, `differentEntries`, `differingBytes`;
- bytes actually read on FAT1 and FAT2 separately;
- `scanIncomplete`, `confidence`, and non-sensitive `evidence` reason codes.

The comparison never invents unread values. A truncated window stops the scan
and marks it partial. Intentional sparse sampling, start offset >0, insufficient
read budget, exhausted window budget, or truncated source means
`scanIncomplete=true` and `wholeFatCompared=false`, even if every observed
entry matches. `status=ok` means the **requested full FAT region** was
exhaustively compared; it does not mean any contents are correct. A mismatch
proves only disagreement between observed bytes, not which FAT copy is right.

`metrics.comparisonCoveragePercent` is the proportion of declared FAT entries
actually compared, not a statistical confidence or integrity probability.
`geometryProvenance=caller_supplied_unverified` is always explicit.

## Acceptance test matrix (artificial only)

- exact full agreement across all 64 synthetic FAT entries;
- two distant entry mismatches and exact differing-byte count;
- deceptive equality of the first 32 bytes (only 12.5% coverage);
- cumulative budget stopping mid-window; non-overlapping sparse sampling;
- truncation at mirror boundary;
- writable input rejection, false aligned/unaligned offsets, overlap,
  out-of-range start, huge declared FAT, Int64 overflow and invalid caps;
- source-array before/after SHA-256 equality and sanitized JSON output.

The suite must pass via Windows PowerShell 5.1 CI before this PR can be accepted.
**No real IMG or personal data is included in any test.**

## Follow-up

The next separate bounded R3 task should map repetitive EB-58 regions in small
read-only windows, correlating only the *observed* pattern with candidate VBR
and FAT boundaries. Continue to reject a diagnosis of hardware failure or
successful repair without independent source evidence.
