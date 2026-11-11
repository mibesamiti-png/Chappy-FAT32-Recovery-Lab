# Team C: FAT-independent carving (experimental)

Only Windows PowerShell 5.1 and built-in .NET are used. The module opens no source file by itself during scanning: its caller passes a **readable, seekable stream**. Scan operations never write to that stream. Extraction uses `FileAccess.Read` for the IMG and `CreateNew` for output files.

## Local synthetic tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\modules\carving\tests\Test-ChappyCarving.ps1
```

The above is for **synthetic fixtures only**. Do not use the master IMG until Team A's review and Windows test gate pass.

## Read-only scan (small, bounded region)

```powershell
Import-Module .\modules\carving\Chappy.Carving.psm1 -Force
$stream = [IO.File]::Open('X:\local\backup.img', [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    $found = Get-ChappyCarvingCandidates -Stream $stream -StartOffset 0 -MaxScanBytes 67108864 -MaxFileBytes 134217728
} finally { $stream.Dispose() }
$found | Select-Object status,scanIncomplete,metrics
# Opt-in local-only report, new file only:
# Write-ChappyCarvingReport -Result $found -ReportPath 'D:\local-output\scan-0001.json'
```

The IMG path above is *illustrative only*, not a user path; **do not execute this example on the 31GB master IMG until Team A approves a local-only test plan**. By default the scanner stays inside its `StartOffset + MaxScanBytes` read window. **All nested ZIP/CRC/G-code reads count toward the same cumulative byte budget**, including rereads; `metrics.bytesRead` is measured source-stream I/O, not nominal scan length. As a consequence, a default-limited scan can stop before covering the whole window and return `status=partial`, with a bounded reason code.

## Global work budgets (Team A review P1)

- `MaxScanBytes`: scan window and **default cumulative byte-read cap**. ZIP/CRC/G-code validators may not read outside this logical window, even when `MaxFileBytes` is larger.
- `ExtraValidationReadBytes=0` by default: a **separately named opt-in** allowance for *rereading within the same scan window*, not permission to read outside it. Choose deliberately on synthetic data only.
- `MaxProbes=128` and `MaxCandidates=128` defaults: explicit combined cap on ZIP/G-code signature probes and returned candidates; dense fake signatures cannot multiply validation indefinitely.
- `MaxProbeBytes=16777216` (16 MiB) default: caps read-ahead per ZIP/G-code candidate even when the scan window is much larger. Can be explicitly raised (up to 256 MiB) for large synthetic 3MF fixtures, but all rereads still consume the global byte/time limits.
- `MaxWorkMilliseconds=30000` default: elapsed-time **cooperative** stop check (not a real-time guarantee for stalled I/O). ZIP/G-code validation uses the bounded `MaxProbeBytes` per candidate and ZIP STORED CRC-32 uses up to 64 KiB of payload per candidate.
- The single 16 KiB chunk scanner searches ZIP and G-code anchors together. Result `metrics.bytesRead` counts **actual** bytes read, `readRequests` counts .NET Stream.Read calls, `entriesChecked` counts attempted candidate probes, `scannedBytes` counts bytes traversed by the first-pass scanner, and `scanWindowBytes` is the logical requested range.
- On caps/time/window-limited validation, return `status=partial` and `scanIncomplete=true` with codes such as `scan.read_budget_exhausted`, `scan.probe_budget_exhausted`, `scan.time_budget_exhausted`, `scan.validation_window_limit`, and `scan.bounds_reached`. A partial candidate is **not** evidence of intact original file data.
- CI uses synthetic dense ZIP local headers and malformed ZIP EOCD scans with a separate counting stream, verifying that cumulative I/O metrics match actual Read calls and stay within the default byte limit.

## R2: source-offset-ordered multi-file candidate scanning (Issue #23)

The 16 KiB scanner collects ZIP-local-header and G-code anchors from the same chunk
(with a 256-byte overlap tail), then **probes them in ascending input offset order**.
Previously a later valid ZIP could wrongly exclude an earlier, separate G-code because
the ZIP family was processed first. Now skipZip / skipGcode only suppress anchors
inside **earlier recognized candidate intervals**, not unrelated earlier files.

- Synthetic order tests cover **G-code → 3MF** and **3MF → G-code** in one chunk,
  candidates spanning 16 KiB boundaries, and immediately adjacent non-overlapping files.
- A synthetic STORED ZIP containing literal G-code and PK signatures still produces
  **only its enclosing ZIP candidate**; nested signatures are not promoted to recovered files.
- A one-candidate limit selects the earliest candidate by source byte offset, not ZIP-first.
  Tail overlaps are deduplicated. Probe, byte-read, work-time and result-count budgets remain
  global and may stop scanning early with status=partial and scanIncomplete=true.
- All validation uses fabricated buffers and synthetic Windows CI only; positive classification
  remains a **candidate**, not proof that a real corrupted disk's original bytes survived.
  The separate Team A damage benchmark in Draft PR #22 is independently reviewed.

## Opt-in extraction

`Export-ChappyCarvingCandidate` is **disabled by default** and throws without the explicit `-EnableFileExport` switch. It is for synthetic fixtures only until Team A independently approves a safe local recovery workflow. Only existing absolute local drive-letter source files and destination directories are accepted. Device/volume namespaces, UNC/drive-relative paths, alternate data streams and paths under reparse-point/symlink/junction ancestors are rejected. Output must be in a **separate directory tree** (not the source folder or its ancestor/descendant). No filename from source content is trusted: output names derive from offsets. The function writes into `structurally_verified`, `probable`, or `partial` subfolders with `FileMode.CreateNew`; no overwrite is allowed.

```powershell
# Only AFTER manual review of the candidate and source constraints:
# $candidate = @($found.items | Where-Object { $_.lengthBytes -gt 0 })[0]
# Export-ChappyCarvingCandidate -ImagePath 'X:\local\backup.img' -Candidate $candidate -OutputDirectory 'D:\local-output' -EnableFileExport
```

### Path-security validation and limitations

- Windows PowerShell 5.1 synthetic CI checks positive extraction, read-only source SHA-256, `CreateNew` refusal to overwrite, default-disabled export, rejection of raw-device/UNC/drive-relative/ADS pseudo-paths, and ancestor/descendant overlap.
- The test creates temporary **Windows directory junctions** representing a source-directory alias and an output-directory alias; both are rejected. Source files and directory ancestors must be existing non-reparse filesystem entries; the generated subdirectory is rechecked.
- Path checks are conservative, but **not a proof against malicious local concurrent filesystem changes (TOCTOU), NTFS short-name aliases, SUBST drive mappings or Windows path/volume alias edge cases**. There is no claim of a fully secured general-purpose extractor. Do not run this writer on the real IMG or restored personal files without Team A review and a separately approved local-only workflow.
- Source opened with `FileAccess.Read` / output with `FileMode.CreateNew`; failure means no pre-existing output is overwritten. These are artificial-data tests only.

## Confidence semantics

- `verified`: ZIP *container structure* (EOCD, central directory and local-header bounds/references) passed the checks; **never** means fully validated payloads or original file integrity. ZIP method 8 (DEFLATE) is not inflated or CRC-checked. STORED (method 0) CRC-32 checks use a 64 KiB total budget. Always read the separate `integrityScope` and `crc32Status` fields.
- `probable`: G-code ASCII commands/comments form a plausible continuous segment; file start/end and completeness remain uncertain.
- `partial`: ZIP local header without a validated central directory (length 0; extraction blocked), a structurally present ZIP whose checked STORED CRC mismatches, or bounded/truncated/discontinuous G-code.
- `fragmentationSuspected`: optional heuristic for suspicious non-text break in G-code; does not reconstruct fragments.

A 3MF is classified from three conventional ZIP entry names: `[Content_Types].xml`, `_rels/.rels`, and `3D/*.model`. ZIP validation **does not** validate OPC/XML contents, relationships, ZIP64, encryption, deflate (method 8) decompression/CRC, or fragments. It targets single-disk ZIPs with stored/deflate entries; only small method 0 payloads receive CRC-32 checking.

## Integrity scope: never mistake ZIP structure for recovered content

Every returned candidate has a **fixed, non-sensitive** `integrityScope` field; the opt-in JSON report includes the same field with a strict enum allowlist:

- `structural_only_not_original_file_integrity`: ZIP/3MF EOCD + central-directory + local-entry references passed bounded structural checks. It is used even if `confidence='verified'` or `crc32Status='match'`, and also for a structurally present ZIP with a STORED CRC mismatch (whose confidence is downgraded to `partial`). A ZIP may have unchecked DEFLATE payloads, unchecked large STORED payloads, and unvalidated 3MF OPC/XML.
- `signature_only_not_validated`: ZIP local-header signature found but archive structure and end not established; extraction remains unavailable when length is 0.
- `heuristic_text_only_not_original_file_integrity`: G-code printable-text and command-sequence heuristics only; not proof of complete G-code or original pre-corruption data.
- `unknown` is used **only by the sanitized report** when a caller supplies an unrecognized/missing scope; never upgrade to a positive integrity assertion.

`confidence` answers how strong a *candidate classification* is, not whether original file data is valid. The `structurally_verified` opt-in export **folder name describes ZIP container structure only**, not content integrity. Opt-in export returns `integrityScope='copied_bytes_sha256_only_not_original_file_integrity'`: its SHA-256 checks only what was copied to the new output file, not the original file on the corrupted card. There is **no** full-file-content-verified state in this module.

## CRC-32 result fields (R2)

- ZIP candidate fields: `crc32Status` is `match`, `mismatch`, `partial`, or `not_checked`; `crc32CheckedEntries` and `crc32UncheckedEntries` give anonymous counts. These fields are also included in redacted JSON reports, without entry names or content.
- A STORED entry can be CRC-checked only when its compressed/uncompressed lengths match and the remaining **64 KiB per-ZIP budget** permits. CRC-32 uses constant-size streaming buffers, not whole-file memory reads.
- `mismatch` means at least one checked entry does not match its central-directory CRC. The candidate is downgraded to `confidence=partial` with evidence `zip.stored_crc_mismatch`. `truncated=false` is possible for corrupt-but-complete ZIPs.
- `partial` CRC status means some entries checked and others deliberately skipped. `not_checked` means zero entries checked. **Deflate entries are never CRC-checked in this round**, even though structural classification may still be `verified`.
- `match` means all considered entries were STORED and verified against the central-directory CRC under the budget. This still does not validate 3MF model XML or guarantee pre-corruption filesystem data.

## Safe JSON reporting (Team A privacy review P1)

- `Write-ChappyCarvingReport` is **explicit opt-in** and writes a new file only (`FileMode.CreateNew`). It produces a fixed `schemaVersion=1`/`team=C` schema; it never serializes arbitrary caller object properties.
- `format`, `confidence`, `integrityScope`, `checks`, `crc32Status` and root `status` use strict, bounded string allowlists; unexpected values become `unknown`, `not_validated`, `not_applicable`, or `error` respectively.
- `evidence`, `warnings`, and `errors` preserve only defined diagnostic reason codes (at most 32 per list). `gcode.command_count_N` is accepted only for bounded nonnegative numeric `N` up to 200000. Unknown strings, paths, filenames and free-form error messages are **dropped**.
- Candidate byte offsets, lengths, CRC counts and six known metric fields accept nonnegative bounded decimal integers only; unexpected or malformed values become zero. Unknown metric keys are never serialized. Candidate results are capped at 10000 items.
- Privacy regression deliberately injects synthetic Windows paths, sentinel filenames, arbitrary strings and invalid numbers into all report field categories. The synthetic CI confirms the private sentinel and extra keys are absent from the JSON output.
- This is **output content sanitization**, not complete filesystem path security. The report path remains caller-controlled; optional extraction has conservative drive/reparse/junction guards but remains unapproved for real images until Team A independently reviews the broader path/alias and race limitations.

## Known limitations and safety

- G-code start anchors require a recognized command/header at the beginning of a block or after a newline/zero byte; some valid G-code may be missed. Encodings other than printable ASCII are not supported yet.
- A ZIP containing internal `PK\x03\x04` strings may create additional `partial` candidates. A valid ZIP's subsequent local headers are skipped once the archive is recognized.
- Validation probes stay within the current scan window and its shared read/probe budget. Under dense adversarial input, the scanner may stop early and **not** find later files. This is intentional, and callers must not infer absence of files from partial results.
- Returned offsets are logical offsets in the input stream, not clusters or partition-relative addresses.
- Never send real recovered files, unredacted reports, or source IMG data to GitHub.