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

## R4: fragmented-cluster evidence (synthetic QA only)

This round adds **tests and documentation only**, not a guessed FAT chain
reconstructor or a new default-on scanner option. It builds a deliberately tiny
128 KiB FAT32-like arithmetic model, **not a mountable standards-compliant FAT32 volume**.
Both synthetic FAT copies map two file beginnings to remote continuation clusters
(512-byte clusters, G-code 18 -> 58; 3MF/ZIP 98 -> 154). Original
artificial G-code and 3MF each occupy more than one cluster. Ground truth
assembles their two clusters **inside the test only** and compares exact bytes.

- **Contiguous positive control:** compare scanner candidate offset/length and
  independently known original G-code and 3MF byte slices; both should match.
- **Discontiguous G-code:** a deliberately invalid intervening line yields
  `fragmentationSuspected=true`, `confidence=partial`, and just the first
  contiguous valid text portion. No claim that the remaining file was restored.
- **Discontiguous 3MF:** the local header is present, but EOCD and central
  directory have moved to a physically remote cluster. The starting candidate
  must remain `lengthBytes=0`, `confidence=partial`,
  `integrityScope=signature_only_not_validated`, not a recovered 3MF file.
- **Negative cases:** a standalone fake `PK` local-header signature and a ZIP
  with a damaged EOCD must never be promoted to structurally verified content.
  The test also checks source SHA invariance and counting-stream byte/probe caps.
- `scanIncomplete` means **scan coverage was limited** (e.g. MaxScanBytes or
  budget), not that every candidate in an otherwise complete scan is intact.
  A complete-window scan may return `scanIncomplete=false` while individual
  ZIP or G-code candidates remain `partial`. This distinction is intentional.

Fragmentation is **not** reconstruction. The scanner never follows these
artificial FAT links, does not locate the correct remote cluster by itself,
does not fill missing data, and never certifies provenance or restored bytes.
One favorable exact-byte synthetic case is not a real recovery probability.
Original microSD and the unique 31 GB master IMG remain out of scope.

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

- `verified`: ZIP *container structure* (EOCD, central directory and local-header bounds/references) passed the checks; **never** means proven original-file integrity. ZIP method 8 (DEFLATE) remains **unchecked by default**; explicit synthetic-only `-EnableSmallDeflateCrc` allows strict small-payload CRC checks. STORED (method 0) CRC-32 checks use a 64 KiB total budget. Always inspect separate `integrityScope` and `crc32Status` fields.
- `probable`: G-code ASCII commands/comments form a plausible continuous segment; file start/end and completeness remain uncertain.
- `partial`: ZIP local header without a validated central directory (length 0; extraction blocked), a structurally present ZIP whose checked STORED CRC mismatches, or bounded/truncated/discontinuous G-code.
- `fragmentationSuspected`: optional heuristic for suspicious non-text break in G-code; does not reconstruct fragments.

A 3MF is classified from three conventional ZIP entry names: `[Content_Types].xml`, `_rels/.rels`, and `3D/*.model`. ZIP validation **does not** validate OPC/XML contents, relationships, ZIP64, encryption, or fragments. It targets single-disk ZIPs with STORED/DEFLATE entries. Small method 0 payloads get bounded CRC checks by default; method 8 payload checks are available *only* under the explicit experimental `-EnableSmallDeflateCrc` switch.

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
- `partial` CRC status means some entries checked and others deliberately skipped, or an attempted DEFLATE stream could not be decoded; `not_checked` means zero entries checked. **DEFLATE remains unchecked unless `-EnableSmallDeflateCrc` is explicitly supplied.**
- `match` means all considered entries were STORED and verified against the central-directory CRC under the budget. This still does not validate 3MF model XML or guarantee pre-corruption filesystem data.

## R3: bounded, opt-in DEFLATE CRC (synthetic-only)

To evaluate only **artificial small ZIP/3MF test fixtures**, explicitly pass the optional `-EnableSmallDeflateCrc` switch to `Get-ChappyCarvingCandidates`. This changes validation behavior but **never exports or writes an output file**. Default is OFF, preserving existing structural-only scanning and previous method 0 checks.

Strict *hardcoded* limits in Windows PowerShell 5.1 / built-in .NET:

- Per method 8 entry: at most **32 KiB compressed input**, **64 KiB declared decompressed output**, expansion ratio at most **64:1**, and no encrypted/unsupported methods.
- Across **all ZIP candidates in one scan**: at most **16 attempted DEFLATE entries**, **128 KiB total reserved compressed bytes** and **64 KiB total reserved decompressed bytes**. The per-archive 64 KiB CRC budget is shared by method 0 and 8 entries; all other entries remain `crc32UncheckedEntries`.
- Compressed bytes are loaded with the existing globally bounded `Read-CBytes` stream operation, never an unaccounted read. A 4 KiB output buffer is used for streaming inflation; output beyond the ZIP header's declared size is rejected immediately, and no file contents, entry names or inflated buffers are exposed by the API.
- Cooperative elapsed-time checks run on every output read. Underlying .NET decompression calls themselves cannot be forcibly interrupted in mid-call; this is a **bounded research verifier**, not hardened parsing of arbitrary attacker-controlled ZIP bombs.
- A checked CRC mismatch yields `crc32Status=mismatch`, `confidence=partial` and `zip.deflate_crc_mismatch`. Invalid inflation/incorrect declared output size yields `crc32Status=partial`, `confidence=partial` and `zip.deflate_inflate_failed`. Skipped entries do **not** get a false-positive content claim. For a fully checked small ZIP, `crc32Status=match` remains a claim only about CRC against ZIP metadata, **never about the original undamaged file**.
- Report `checks` and `evidence` use strict allowlists with new DEFLATE-specific reason codes and **do not include filenames or decompressed bytes**. `integrityScope='structural_only_not_original_file_integrity'` is unchanged, even for CRC matches.

Synthetic negative tests cover CRC tampering, invalid DEFLATE, ZIP truncation, high declared expansion ratio, forged underdeclared output size, 18 independent ZIPs with a global 16-entry limit, and previous nested-signature cases. The entire suite retains global source I/O, probe, time and candidate bounds.

**Not authorized for the real 31GB IMG.** Opt-in export remains separately disabled by default and is never invoked during real-media testing.

## Safe JSON reporting (Team A privacy review P1)

- `Write-ChappyCarvingReport` is **explicit opt-in** and writes a new file only (`FileMode.CreateNew`). It produces a fixed `schemaVersion=1`/`team=C` schema; it never serializes arbitrary caller object properties.
- `format`, `confidence`, `integrityScope`, `checks`, `crc32Status` and root `status` use strict, bounded string allowlists (including opt-in DEFLATE checks); unexpected values become `unknown`, `not_validated`, `not_applicable`, or `error` respectively.
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

## R5 C5-02: bounded opt-in STL format evidence (gate review pending)

This is a **guarded C module**, not a general STL recovery engine, FAT-aware reconstruction or export. The main ZIP/3MF/G-code scanner and its defaults are **unchanged**.

```powershell
Import-Module .\modules\carving\Chappy.StlEvidence.psm1 -Force
# Synthetic, generated, strictly non-writable stream supplied by a trusted caller.
$result = Get-ChappyStlCandidates -Stream $syntheticReadOnlyStream -EnableStlEvidence -StartOffset 0 -MaxScanBytes 65536 -MaxSourceBytes 65536
```

Without `-EnableStlEvidence` this function returns `status=disabled` and performs **zero source reads**. The caller owns the stream: the module never opens a path or creates an output file. Accepted input is readable, seekable, and **CanWrite=false**. This finite **512-byte aligned** profile recognizes only binary STL with **1–8 facets** within one sector, printable/zero 80-byte header, finite numeric coordinates, and zero attribute bytes, or ASCII STL with **one facet**, well-formed `solid/facet/outer loop/3 vertex/endloop/endfacet/endsolid` and finite coordinates. Other valid but larger, shifted, uncommon-header, or multi-facet STL files remain **UNKNOWN**, not rejected as absent.

The module reserves `MaxScanBytes` (default 65,536 returned bytes) and the identical validator-work ceiling before any reads; at most 128 sector probes, 16 candidates and 30 s cooperative wall-clock work. One fixed 512-byte scratch buffer per probe; `validatorBytesRead` measures bytes inspected in memory, **not peak process memory**. Source `bytesRead` and `readRequests` count actual `Stream.Read` returns/calls. Early EOF, quota/candidate/time exhaustion or unavailable window returns `partial` **with no retained early winner**, while coverage outside the window is always UNKNOWN. An observed STL candidate is `probable` **structural-only**, never authentic original bytes, and is not compatible with the C file exporter; this module has no export API or A-issued source receipts.

Artificial regression: `modules/carving/tests/R5StlModuleGateRegression.ps1` invoked by the Team C Windows PowerShell 5.1 suite. Negative controls include malformed count, ASCII grammar/number, nonfinite triangle float, all-zero vertices, 17B then real EOF, underquota/short window, writable stream and dense structural signature flood. Independent scorer checks exact generated-original SHA, not returned as candidate confidence. User physical microSD and only 31GB master IMG remain **NOT APPROVED for any access**.

## R5 C5-01: optional bounded 3MF ZIP/OPC/XML consistency evidence

This is an **extra validation step on a caller-selected candidate extent**; it is not a candidate finder, recovery engine or original-file authenticator. The existing C ZIP/3MF/G-code signature scanner and exporter stay unchanged. Enable explicitly in **generated synthetic tests** only:

```powershell
Import-Module .\modules\carving\Chappy.OpcEvidence.psm1 -Force
$result = Get-Chappy3MfOpcEvidence -Stream $syntheticReadOnlyStream -EnableOpcXmlEvidence -OffsetBytes 0 -LengthBytes 2048
```

The `LengthBytes` parameter above is merely illustrative: pass the actual bounded proposed ZIP candidate length (128–8192B). The module does not discover this length, any file's original extent or a FAT chain. With `-EnableOpcXmlEvidence` absent it returns `disabled` and reads **zero bytes**. The caller's source must be **non-writable, readable and seekable**; there is no path open, original-file export or payload in the result.

The module reads at most **8192 actual source bytes**, in one bounded in-memory copy, then reuses the existing C ZIP local/central/EOCD + opt-in small CRC check on those bytes. A conservative three-part 3MF OPC profile checks `[Content_Types].xml`, `_rels/.rels` and `3D/3dmodel.model`, expected namespaces, model MIME override, one internal StartPart relationship to `/3D/3dmodel.model`, XML root and `resources/build` elements. **This does not prove full 3MF mesh/resource/build semantics or authentic original bytes**. Other valid 3MF configurations, named parts or format extensions may remain UNKNOWN rather than disproven.

XML is parsed with `XmlReaderSettings.DtdProcessing=Prohibit`, no external resolver and a character limit. ZIP has at most 8 entries and <=32768 B declared total uncompressed; required XML parts each <=8192 actual inflated bytes, <=16384 total XML bytes, max 8192 physical source buffer; remaining in-memory parsing is bounded. Limits/timeouts are cooperative, not an uninterruptible real-time guarantee. Invalid ZIP/CRC, XML/OPC references, short returned source read, quota failure and disallowed XML lead to `partial/unknown` without a winner, A provenance token, filesystem path, or extraction.

See `modules/carving/tests/R5OpcXmlGateRegression.ps1` (12 wholly artificial cases, including corrupted CRC, external DTD, wrong StartPart, missing/duplicate parts, valid-but-byte-changed model and early 17B then EOF); synthetic original SHA is kept in an independent scorer. Original physical microSD and unique master ~31GB IMG remain **NOT APPROVED for access of any kind**. This feature provides C5-01 review evidence but does **not** by itself make the whole R5 formal stage PASS.

## R5 C5-03: strictly bounded non-oracle two-piece 3MF candidate evidence

The default-OFF **`Chappy.FragmentEvidence.psm1`** exports `Get-ChappyFragmentCandidates`. It promotes the project's already tested bounded C research helper into a reusable C module. This is an *experimental artificial-source candidate finder*, **not** a general recovery/repair/export workflow or original-file authenticator.

```powershell
Import-Module .\modules\carving\Chappy.FragmentEvidence.psm1 -Force
# Only a generated, read-only, seekable synthetic Stream, not original media.
$trial = Get-ChappyFragmentCandidates -Source $syntheticReadOnlyStream -EnableFragmentEvidence
```

Without `-EnableFragmentEvidence`, the method emits `disabled` and performs **zero** source reads. With it, the source must be nonwritable/seekable/readable and **no larger than 2 MiB**. The fixed default research assumptions remain intentionally explicit: 65,536B full scout from source offset zero on **512B sectors**, ZIP local header start at offsets `sector + 0/1`, ZIP EOCD in a sector with derived suffix length, only two hypothesized first-piece sizes **512 or 544B**, tail <=512B, at most 4 start signatures / 8 tails / 16 assembled pairs. Optional `-IncludeStartPhasePlusTwo` and `-IncludeFirstPiece560` are experimental hypotheses **OFF by default**; these are not correctness guarantees.

Budgets: <=81,920 **actual returned physical source B**, <=98,304 separate **in-memory ZIP validator reads**, <=16 physical pair attempts, <=30s cooperative search (not a hard interrupt of stalled I/O). A full scout has 128 512B sectors. A pair is assembled in a maximum 1,056B in-memory buffer and checked using the existing bounded C ZIP/CRC validator; only structurally consistent 3MF pairs are returned. `sourceBytesRead` and `readRequests` report physically returned bytes and number of `Stream.Read` calls, not nominal scan extent. `validatorBytesRead` is distinct *in-memory* work; it is **not process peak memory**. Independent synthetic test-only stream meters additionally audit actual unique physical bytes, without minting A read receipts.

The result contains **ordered, disjoint source-relative spans**, numeric candidateKey, an explicit `one_possible|ambiguous|unknown|incomplete` decision, and all possible physical hypotheses when ambiguous; **never** an automatic original winner. All accepted hypotheses use `confidence=probable`, `integrityScope=structural_only_not_original_file_integrity`, `originalIdentity=unknown`, `sourceOrigin=unattributed_without_A_meter`. The module **does not** compute or accept known-original SHA, any FAT link, original filename, original fragment positions, file length or oracle manifest. It never exports bytes or creates files. `scanIncomplete=true` for a smaller-than-source scout; missed off-grid signatures and lengths must remain UNKNOWN, not reported as proven absence. Missing tails and CRC-consistent wrong metadata can create no or multiple plausible joins: those never prove true original identity. Source short read, inaccessible window, quota/time/signature/pair overflow must fail closed with `partial/incomplete` and no promoted candidate.

Review matrix: `modules/carving/tests/R5FragmentModuleGateRegression.ps1` uses **only generated 2 MiB artificial seed 202611** with 9 withheld-truth cases: healthy two-piece, off-grid tail/start, false EOCD, CRC-consistent different metadata tail, missing tail, unsupported +2/560 variants, and reversed physical fragment placement. The test's **independent** scorer joins returned candidate spans in logical order and compares the generated original SHA; format evidence does not receive that truth. Wrong *logical* assembly order, true 17B+EOF, insufficient quota, candidate flood and writable source are separate negative controls. All normal C/ZIP/G-code/STL/OPC scanner and exporter defaults are unchanged.

C5-03 still requires A review for large/standards-sized and less restricted fragment search, unique physical-read trust, alternate file formats, genuine ambiguity and byte-exact provenance. Do **not** treat test accuracy or SHA as real-media recovery probability. The physical microSD and the unique ~31GB master IMG remain NOT APPROVED for any read/hash/scan/copy/write/repair/extract/upload.

## C5-04: independent SHA/UNKNOWN scorer on both artificial corpus tracks

This C-only **regression/scorer** does not change any production algorithm, candidate visibility, scan schedule or default state. See `modules/carving/tests/R5CrossTrackOriginalScorerGate.ps1`, invoked by the native Windows PowerShell 5.1 C suite. A pre-code frozen baseline and exact artificial case definitions are recorded in [Issue #72](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72).

**Compact 2MiB track:** seeds 202611/202612, eight targeted 3MF two-piece synthetic cases per seed. Reuse the guarded `Get-ChappyFragmentCandidates` with default finite 512/544 first-piece hypotheses, 65,536B sector scout, <=81,920 actual source-return B, <=98,304 in-memory format-validation B and 16 pair attempts. The independent scorer joins returned ordered source-relative spans and hashes candidate bytes; **the C candidate function never receives the original SHA, file extents, seed, case label, fragment order or original file length**. A physically reversed start/tail pair is assembled in logical ZIP order. Missing tail is an absent target-slot negative; unsupported +2 and first-piece 560 patterns are `UNKNOWN`, **not** file-level false negatives. Deliberately CRC-consistent but SHA-different alternate metadata is counted separately as a structural false join and remains ambiguous.

**Standards-shaped FAT32 track:** fresh generated 65,541-cluster images with 512B or 1,024B clusters and seeded 202611/202612, plus synthetic CRC-corruption controls. The existing B parser supplies numeric geometry from the **same generated source**, then the unchanged C contiguous ZIP/3MF scanner reads one bounded 65,536B data-start window (<=98,304 physical-return B including validation). An independent offset-zero comparator uses the same C settings. The generator's true original 3MF SHA and extents stay exclusively in the test scorer. A file fragmented beyond the first contiguous cluster is `UNKNOWN` for this bounded contiguous procedure; **this is not proof that the file is absent**. An unrelated fake local ZIP marker is placed in synthetic FAT slack, outside B's parsed data area. The two tracks use different algorithms/caps and are **not** pooled into one claimed accuracy or performance gain.

Metrics are per-*defined synthetic target file slot*: TP/FP/FN/TN and UNKNOWN reported separately, along with original-byte SHA exact and format-only wrong-original candidates. Source meters count **actual returned bytes, unique physical offsets and actual Read calls**, separately from any in-memory validator or B geometry reads; probes, pair counts and elapsed ms are printed. No reliable peak process RAM measurement is available; bounded temporary buffers are **not** the same as measured peak memory. Short-return 17B then true EOF cannot be certified original. An artificial original SHA match is only scored externally; it is **not** an authenticated original user's file.

The physical microSD and unique master ~31GB IMG remain **NOT APPROVED** for any read/hash/scan/copy/write/repair/extract/upload. No real-media recovery rate, automatic extraction, A-issued physical read receipt or full C5-04 formal PASS is claimed without A review.

## C5-05: bounded physical returned/unique source coverage (C-unattested)

`modules/carving/Chappy.CoverageEvidence.psm1` exports **`Get-ChappyCarvingCoverageEvidence`** as a **default-OFF, no-file-path, opt-in** diagnostics wrapper around the *existing* C 3MF two-fragment or C contiguous ZIP/3MF/G-code scanner. It does **not change either format algorithm**.

```powershell
Import-Module .\modules\carving\Chappy.CoverageEvidence.psm1 -Force
# $generatedReadOnlyStream is a disposable, generated artificial MemoryStream.
$r = Get-ChappyCarvingCoverageEvidence -Source $generatedReadOnlyStream -EnableCoverageEvidence -Mode Fragment
# Window mode: StartOffsetBytes must be independently parsed from the SAME
# generated source's numeric FAT32 data geometry, never from oracle extent.
```

With `-EnableCoverageEvidence` omitted it returns `disabled`, **zero Stream.Read calls and no Stream.Length/Position inspection**. Active input must be a **nonwritable, readable, seekable Stream**. The wrapper opens no source path or device and creates no output. Fragment mode uses the existing 2MiB artificial-source limit, 65,536B/128-sector scout, 4 starts, 8 EOCD tails, 16 pairs, <=81,920 actual source B (bounded C module still applies) and <=98,304 *in-memory* C ZIP parser B. Window mode uses only an explicit 65,536B source region, <=16 format probes/candidates, <=98,304 physical returned B including source rereads, and a 128MiB source-length envelope. Explicit wrapper `MaxReadCalls` has a maximum 4,096 and actual-return ceiling `MaxSourceBytes` <=98,304B. Both are enforced while intercepting `Read`; attempts beyond the cap return `partial/incomplete`, with **no retained candidate**. Timeouts are cooperative; actual Stream.Read I/O may block beyond the requested wall clock, not a hard thread cancellation.

The C meter records **only successful Stream.Read return intervals** (not requested-but-unreturned bytes) and internally merges overlapping intervals to calculate `uniqueReturnedBytes`. It separately provides `actualReturnedBytes`, `repeatedReturnedBytes`, `readCalls` (including a zero-byte EOF attempt), `positiveReadCalls`, `zeroByteReadCalls`, `sectorProbes` or `formatProbes`, `pairAttempts`, `candidateCount`, `elapsedMilliseconds`. Fragment `validatorMemoryReadBytes` counts a *separate in-memory* ZIP parser and is **not a physical read**; window scanner doesn't offer a separate parser memory tally and reports `not_separately_instrumented`. `maxPairBufferBytes=1056`, `maxSectorScratchBytes=512` or `maxScannerChunkBytes=16384` describe fixed local working-buffer sizes, **NOT measured process peak RAM**. The module reports `peakProcessMemoryStatus=not_measured` and `peakProcessMemoryBytes=null`: it would be dishonest to invent a peak measurement.

All statuses acknowledge `scanIncomplete=true` for sources larger than the bounded window. A partial **window-only** observation can retain numeric format candidates only after exactly the entire 65,536B source window has been scanned, with `scan.bounds_reached` as the **sole** warning. Incomplete source reads, invalid/short EOF, internal validator cap, candidate overflow or extra warning => `partial/incomplete` and no candidates. `one_possible` or `ambiguous` refers only to CRC/structural support, not original bytes. Returned candidate fields are strictly numeric/redacted and `originalIdentity=unknown`; there is no source token, image name, SHA, export or selected original. Most importantly, **`sourceReadAttestation=C_unattested_A_outer_receipt_required`**: a C-owned meter cannot authenticate physical origin, forge a trusted A receipt or satisfy A7 by itself.

`modules/carving/tests/R5SourceCoverageGate.ps1` uses only seed 202611 generated 2MiB compact cases (control, CRC-consistent false tail, missing tail) and standards-shaped generated SPC1 fragmented / SPC2 contiguous cases. A second **independent** test-only returned/unique byte meter wraps the module and compares every `Read` return, duplicate offset and call count; true 17B then 0 EOF, micro-read call flood, insufficient budget, writable source, artificial original SHA before/after and unknown-scope remain separately checked. Do not interpret the narrow artificial findings as a real-media recovery rate, measured peak RAM or A-authenticated receipts.

Real physical microSD and the sole master ~31GB IMG are strictly **NOT APPROVED** for any reading, hashing, scanning, copying, writing, repairing, exporting or uploading. None is involved in the C gate.

## C5-01: bounded OPC primary model StartPart target breadth (2026-11-14)

The **existing** default-OFF `Get-Chappy3MfOpcEvidence` in `Chappy.OpcEvidence.psm1` now resolves a bounded package-root 3MF StartPart relationship rather than assuming all 3MF packages must name their model `3D/3dmodel.model`. The only supported model name profile is **one safe segment below `3D/` ending in `.model`**, e.g. `/3D/build.model` or `3D/build.model` in package-root relationship Target. This root-relative support and alternative safe model part name are legitimate OPC/3MF structures, but **do not** constitute full OPC/3MF compliance or general mesh/assembly validation.

The model ZIP part **must be present under the exact referenced name**. The effective XML MIME `application/vnd.ms-package.3dmanufacturing-3dmodel+xml` may come from a unique `Override PartName` declaration or a unique `Default Extension="model"`; a part-specific Override takes precedence. Duplicate ZIP entry names, duplicate/conflicting part-specific overrides, duplicate Default extension mappings, repeated StartPart relationships/Ids, fake nested Relationship elements, external StartPart targets, traversal, URL-encoded names or any unrecognized target form produce **UNKNOWN**, not accepted evidence. This is a strict supported subset; unfamiliar or valid extension profiles may be conservatively UNKNOWN.

The original source constraints remain: **opt-in switch required**, otherwise source access is zero; caller-supplied **nonwritable readable seekable Stream**, <=8,192 physical source returned bytes, max 8 archive entries, <=32,768 ZIP memory-validator read bytes, XML <=8,192 bytes per part and <=16,384 total, DTD disallowed and no XML resolver, no file I/O, no extraction. Both ZIP CRC and target model/XML structure are checked; they **do not prove original file identity**. Results retain `originalIdentity=unknown`, `integrityScope=structural_only_not_original_file_integrity` and no candidate SHA, A source receipt or chosen original.

New C-only regression `R5OpcStartPartBreadthGate.ps1` uses 27 deterministic invented ZIP/OPC packages with root-absolute/relative StartPart, alternative names, Override/Default precedence, optional noncritical part, XML namespace prefix, duplicate and forged XML/ZIP metadata, corrupted CRC and DTD controls. It compares the older structural ZIP-only baseline against the improved OPC/XML evidence on the exact same sources; an **independent** test scorer checks artificial ZIP SHA (canonical versus structurally valid but different payload) only **after** validation. The previous 12 canonical C5-01 fixtures remain unchanged and still run. Real microSD and the sole ~31GB IMG stay **NOT APPROVED** for any read/hash/scan/copy/write/repair/export/upload.


## C5-02 gate: bounded multi-facet STL and default-OFF strict G-code syntax evidence

**STL:** Existing Get-ChappyStlCandidates -EnableStlEvidence keeps one 512B physical read per sector, 64KiB source and validator budgets, 128 probes/16 candidate caps, and fail-closed EOF. ASCII now checks 1–4 complete facets *within one sector*, with matching solid/endsolid, correct facet/loop nesting, finite normals and vertices. Binary retains its narrow 1–8 little-endian facet subset, finite floats, zero attributes and printable header; a binary header beginning with "solid" does not by itself make ASCII STL. Count overrun, absent terminator, control bytes and nonfinite coordinates are UNKNOWN for this subset. Other valid multi-sector STL and custom attributes may remain UNKNOWN, not invalid.

**G-code:** New exported Get-ChappyGcodeEvidence takes one **caller-proposed offset and exact length 48–8192B**: it validates that candidate span but **does not discover offsets, know true source extents or original SHA**, follow FAT, or execute printer commands. -EnableGcodeEvidence is mandatory and defaults OFF (zero source reads/seek/length access). On enable, input must be readable, seekable and non-writable. Preflight rejects overquota/out-of-bounds before any read, counts actual returned Stream.Read and calls, and fails closed on 17 actual B then zero-byte true EOF. Conservative syntax subset: 7-bit printable ASCII, <=128 lines, <=160B/line, newline-terminated, recognized G0/G1/G28/G90/G91/G92 and M73/M82/M83/M84/M104/M106/M107/M109/M140/M190, at least 4 commands, XYZ motion and G28. Comments after semicolons never count as commands. Unrecognized codes and vendor dialects (including numbered command lines), non-ASCII text, incomplete content and ambiguous syntax remain UNKNOWN; *legitimate G-code may be unsupported*. This is not a general G-code parser and **not a guarantee that a program is safe to execute on any printer**. Existing broad discovery Get-ChappyCarvingCandidates is unchanged; this is supplementary and default OFF.

Successful evidence carries confidence=probable, integrityScope=heuristic_text_only_not_original_file_integrity, originalIdentity=unknown and sourceOrigin=unattributed_without_A_meter. No A-origin token, recovered filename, path, payload, SHA, export or printer execution. Returned numeric scratch bounds are not measured process peak RAM; peakProcessMemoryStatus=not_measured. Time enforcement is cooperative, not a hard timeout of a stalled I/O call.

**Artificial test:** tests/R5FormatBreadthGateRegression.ps1 contributes **20 synthetic STL source cases plus 20 G-code supplied-span cases** to Team C's native Windows PowerShell 5.1 suite. An independent scorer, not any C module, owns generated original SHA. Controlled positives and negatives cover ASCII facet count/nesting, binary count/floats/solid shadow header, G-code comments vs real commands, dialect/unsafe-sounding command codes, numeric/length/encoding constraints, 17B+true EOF, writable input and budget denials. Count TP/FP/FN/TN/UNKNOWN separately for each tiny declared format profile, distinguish structurally consistent vs generated-original byte-exact, and count physical source returned B and actual calls. Real card and sole ~31GB IMG are NOT APPROVED for any read/hash/scan/copy/write/repair/extract/upload; none is touched.


## C5-03: generated R3 FAT32 bounded non-oracle 2-piece data window

Exported Get-ChappyFragmentCandidates in Chappy.FragmentEvidence.psm1 now supports an explicit StartOffsetBytes, **the beginning of a physical search window, NOT the known start or tail of any file**. It must be 512B-aligned, fit the readable seekable non-writable source, and is always labeled windowHintOrigin=caller_unattested. The C code does **NOT** derive BPB geometry itself; the caller must separately derive/validate geometry from source bytes, with A owning any future authoritative source read receipt. This branch tests B first-party Get-ChappyFat32Geometry on generated R3 FAT32 source bytes. The correct original extent, ordered fragment locations, first-part size and SHA stay **only in an independent artificial test scorer** and are NEVER passed to C.

The new option EnableStandardsShapedSource allows source lengths up to 128MiB **only when explicitly enabled**. Default guard still refuses sources over 2MiB; source opening, physical-card access, path handling, extraction, write and export are not added. Even in large-source mode the module still examines only a caller-bounded 512–65,536B window; actual source-returned bytes stay <=81,920B across sector scout + full physical pair rereads; <=98,304B separate in-memory ZIP/CRC validator I/O; <=4 starts/8 tails/16 pair hypotheses; <=30s **cooperative** elapsed-time checks. Large source size is NOT permission to scan the real microSD or sole original master IMG. Real-media test permission remains **NOT APPROVED for any access (even reading or hashing)**.

The unchanged existing options IncludeStartPhasePlusTwo and IncludeFirstPiece560 widen fixed start-phase and first-part-length hypotheses *equally for every case*, with no access to the correct candidate shape. They remain OFF unless explicitly requested. StartOffsetBytes defaults zero so the old 2MiB/first-64KiB behavior and every original C test remain unchanged. When invalid/misaligned/out-of-range search window or quota is supplied, the result is partial/incomplete with zero physical source reads and **no candidate**. True 17B then zero EOF, dense decoys and failed pair/probe budgets remain fail closed. Returned physical ordered spans are absolute source-relative offsets, not window-local guesses. Scan coverage outside the physical window stays UNKNOWN; even a single CRC-consistent ZIP candidate is only probable structural evidence, originalIdentity=unknown, selectedOriginal=null, canAutoSelectOriginal=false, no A-issued source token, original SHA, file path, automatic file selection or extraction.

C synthetic Windows gate tests/R5R3FragmentDataWindowGate.ps1 evaluates both R2 compact 2MiB cases (9 different first/second placement, 512/544/560 length, +2 local phase, fake EOCD, CRC-consistent alternate metadata tail and missing tail) and two separately generated R3 65,541-cluster FAT32 tracks (SPC1 true fragmented physical order, SPC2 contiguous physical control). It scans both fixed root window (0) and independently B-derived data-start search window on **exact same synthetic source image** with identical C byte/call/probe/pair caps. Only AFTER C returns hypotheses does the test independently join candidate physical spans and calculate byte-exact generated-original SHA. Physical returned source bytes, independently counted unique source offsets, Stream.Read calls, C in-memory validator bytes, candidate counts, resource limits, UNKNOWN and input SHA before/after are separately reported. The zero-source-I/O default, >2MiB refusal without opt-in, no real identity and no source-token minting are asserted. This is not a claim of generalized FAT32 file recovery or of genuine original filename/path reconstruction. Full R5 needs A independent review of C5-03 and C5-05/06.


## R5 C5-06: guarded C-only versioned candidate evidence

The experimental C-only module Chappy.CandidateEvidenceV1.psm1 exports Get-ChappyCarvingCandidateEvidenceV1. It calls the actual C production two-piece fragment finder and C physical-return/unique-byte meter from Chappy.CoverageEvidence.psm1. This is **not** a new scheduler and **not** the shared Team A R7 B/C/D interface. No source path/device, original SHA, raw candidate bytes, inferred owner/FAT winner or extraction is involved.

With no EnableCandidateEvidence flag the API is disabled, with **zero** reads, seeks and source-property access. On enable, the source must be a non-writable, seekable, readable **MemoryStream with generated artificial bytes**. An in-memory object does NOT authenticate its origin: caller must not pass or load real user data. Default deny for >2MiB; explicit EnableStandardsShapedSource opt-in permits at most 128MiB. The 512B-aligned WindowStartBytes is an **untrusted search window hint**, not a correct original extent or FAT chain. A 65,536B default window or a bounded 32,768B R3 window is inspected; optional EnableExpandedFiniteHypotheses enables fixed +2-byte ZIP local phase and 560B first-segment size on all cases, never oracle-specific.

Hard quotas: <=81,920 successful returned source bytes **including rescans**, <=512 Stream.Read calls, <=4 ZIP start signatures, <=8 EOCD tails, <=16 pair attempts, <=98,304 distinct in-memory ZIP parser returned bytes, <=30s *cooperative* timer. C's in-memory source meter counts actual returned/unique/repeated physical source offsets, Read calls, zero-length EOF, probes, pairs and candidate count. Only A may issue authenticated, same-session source receipts; C's counts remain **unattested**. Buffers of max 512B for a sector and 1056B for pair assembly are stated as bounds, never a measured process-wide RAM peak: processPeakMemoryStatus=not_measured.

Returned schemaVersion=c_candidate_evidence_v1 includes decision one_possible|ambiguous|unknown|incomplete, window coverage and caller-unattested hint, source-relative ordered two-span numeric hypotheses keyed by extents, sourceAuthenticity=not_proven and originalIdentity=unknown. Even one structural 3MF ZIP/CRC candidate is **not** an original file authentication. All candidates set canSelectOriginal=false and canExport=false; top-level canRepair=false, canExport=false, canSelectOriginal=false, originalShaVerified=false and selectedOriginal=null. An untrusted source-relative candidateKey is NOT an A-scoped candidate ID. Multiple CRC-consistent candidates, including one byte-different from original, stay ambiguous. Entire unobserved source outside the search window remains UNKNOWN. Short EOF, overquota, invalid spans, unaligned hint, source type mismatch and returned-byte vs C scanner counter disagreement fail closed without promoting early candidates.

The C-only R5CandidateEvidenceV1Gate.ps1 regression uses generated 2MiB seed 202611 compact clean/false-tail/off-grid/560B/reverse-order/missing-tail tests and 65,541-cluster R3 SPC1/SPC2 standards-shaped FAT32 buffers. Independent external synthetic SHA scorer does not supply correct original extents or hashes to the C API. A separate test MemoryStream subclass counts actual source byte offsets and Read calls and compares against C's returned/unique measurements; true 17B then zero EOF, disabled zero I/O, synthetic-only nonwritable policy, exhausted quotas and wrong root data-window controls are negative. Tests distinguish candidate structure from byte-exact original artificial file, no real restoration claims.

Real physical microSD and the sole ~31GB master IMG are **NOT APPROVED FOR ANY ACCESS**: read/hash/scan/copy/write/repair/export/upload all prohibited. They must not be loaded into a MemoryStream. Team A alone reviews and merges and decides narrow C5-06 acceptance; C5-05 A-attested source proof and process peak RAM measurement are a different remaining issue. R5 full stage not accepted and R8 export blocked.
