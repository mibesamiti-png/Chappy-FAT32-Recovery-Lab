# 3D-File Synthetic FAT32 Damage & Recovery Benchmark — Team A Plan v1

**Status:** proposed research/QA roadmap only (2026-11-12 JST). **Not a claim of implementation, test pass, recovery success, or permission for real-IMG access.**

Owner: **Team A (Issue #1)**; next-round scope for A-runner and B/C/D after their existing R9 PRs complete. Starting `main` baseline: `bc2fa20d4123400a2b8e9f77bc20ea5212a64dfc`. Current A legacy benchmark `tests/Test-SyntheticDamageBenchmark.ps1` is seven **2MiB FAT32-like** artificial scenarios with 10/14 byte-identical *selected* candidate slices; this is not full format-conformant FAT32 and NOT a physical-media recovery percentage.

## 1. Goal and non-goals

Goal: independently generate normal artificial 3MF, STL and G-code contents, place them as files within a deterministic invented FAT32(-like) image with known extent mappings, **then** apply controlled filesystem/contents damage. Evaluate B directory evidence, C carving/validation and D FAT hypotheses independently and in combination, without granting stronger trust than the evidence supports.

Non-goals: no user data, real filenames, original microSD, unique ~31GB master IMG, real scans, public raw/unsanitized logs, repair, live extraction, FAT winner selection, guessed original bytes or actual reconstruction success claims. `docs/LOCAL_READONLY_APPROVAL_GATE.md` remains **NOT APPROVED**.

## 2. Ground-truth-first fixture pipeline (Team A owns tests/runner)

1. Deterministic `seed`, generator revision, image-layout mode, FAT cluster and sector geometry, and artificial file identifiers (e.g. `test_model_01.3mf`) are versioned before running algorithms.
2. Generate **valid original artificial files** first: byte arrays, lengths, SHA-256 and independently verified format expectations. Keep an out-of-band **oracle manifest** of each original SHA-256, original file length and original cluster/byte extents. The test oracle is never available to a candidate algorithm.
3. Construct a clean image with valid directory entries, start clusters, LFN/short-name variants, file sizes, two FAT copies, and possibly deliberately fragmented but *logically valid* chains. Verify clean-read round trip and exact byte hashes **before** creating corruption.
4. Apply exactly one named mutation first, then defined combinations, to a **disposable copy**, recording mutated byte offsets, category, damage seed and affected file IDs only in synthetic-test metadata. The clean original is immutable.
5. Run the **same corrupted fixture** through baseline and candidate under identical explicit read/probe/candidate/CPU/memory limits, with both code revision and flags recorded. If actual reads differ, report both, never imply matched work from matching caps alone.
6. Score output *outside* B/C/D code against oracle. Preserve original and mutated artificial image hashes before/after all scans to prove no writes, report failure to terminate and budget exhaustion.

The oracle must not leak into inferred file starts, lengths, fragment positions, continuation selection or expected format when the particular trial is designated **unknown-hint**. If any hint remains (format, length, alignment, file extents), label the experiment as hinted and report the remaining privileged information.

## 3. File-format corpus

| Corpus ID | Clean artificial contents | Positive checks | Deliberate negatives / limitations |
| --- | --- | --- | --- |
| F01 | Valid minimal **3MF** ZIP/OPC with `[Content_Types].xml`, root `_rels/.rels`, a referenced 3D model part with valid XML, finite triangle(s) and `build` | ZIP local+central+EOCD consistency, actual member offsets, content relationships/XML, known original SHA | Generic ZIP masquerading as 3MF, altered EOCD, missing member, malicious nested paths, corrupt size/CRC, valid *different* package |
| F02 | 3MF with `STORED` and `DEFLATE` small members; optionally thumbnail or synthetic slicer-like custom part | Bounded CRC where implemented, model XML/relationship validation when separately implemented | ZIP structure alone/CRC from mutable archive does **not** verify original content; ZIP64/encryption/unsupported extensions reported unknown |
| F03 | **Binary STL**: 80-byte arbitrary header, little-endian uint32 triangle count, 50 bytes per facet, finite generated geometry | Length = 84 + 50N with overflow-safe arithmetic, finite coordinates, plausible count; oracle byte SHA | Arbitrary non-magic header, random fake 84+50N, `solid` string in binary header, huge counts, invalid floats, zero normals that may be tolerated |
| F04 | **ASCII STL** with `solid`/`facet`/`vertex`/`endsolid` and deterministic whitespace variations | Bounded token/record parsing and known original SHA | Truncation, misleading `solid` in random text, incomplete `endfacet`, binary STL containing `solid` |
| F05 | Synthetic **G-code** with invented harmless commands/comments and known byte boundaries | Bounded signature/text evidence and artificial exact-byte check | Similar text, clipped lines, incorrect ending, decoy comments, wrong continuation |
| F06 | Ordinary ZIP, random binary, accidental PK signatures, STL-shaped random bytes, unrelated text | Classify as negatives if not supported original 3D file | Ensure no false `verified original`/high-confidence filenames or unproven fragment joins |

**Format grounding:** 3MF Consortium Core Specification (ZIP + OPC relationships/parts, source concepts only): https://github.com/3MFConsortium/spec_core/blob/master/3MF%20Core%20Specification.md . Library of Congress binary STL description (80+4+50N): https://www.loc.gov/preservation/digital/formats/fdd/fdd000505.shtml ; ASCII STL: https://www.loc.gov/preservation/digital/formats/fdd/fdd000506.shtml . Windows FAT format-classification boundaries in Microsoft FAT32 v1.03 document: https://www.cs.fsu.edu/~cop4610t/assignments/project3/spec/fatspec.pdf . No third-party implementation code/assets may be imported without exact license review per `docs/ALGORITHM_RESEARCH_PROTOCOL.md`.

## 4. Corruption matrix: separate metadata damage from content damage

| ID | Layer / corruption after clean layout | Required observation / scoring |
| --- | --- | --- |
| M00 | No corruption, contiguous files | Positive controls; exact original bytes obtainable only if read/export algorithm actually proposes them |
| M01 | No corruption, **fragmented valid FAT chain** (two/three extents) | Ground-truth fragmentation; contiguous scan may be partial, must not be called exact |
| M02 | FAT1 only damaged; FAT2 remains clean | D identifies disagreement, never automatically chooses mirror |
| M03 | FAT1 and FAT2 identically damaged (cycle, bad entry, out-of-range, break) | No false clean classification or phantom reconstruction |
| M04 | LFN checksum/ordinal errors, deleted entry, wrong size/start-cluster, conflicting parent | B preserves unknown/orphan candidate evidence; no invented path |
| M05 | Cluster-chain cross-link or missing extent | Explicit conflict/unknown; no inferred original data from missing bytes |
| P01 | 3MF ZIP EOCD/central directory missing; 3MF model/OPC relationship missing | Separate partial structural evidence from original identity |
| P02 | 3MF compressed payload bit-flip or changed CRC metadata; valid *different* ZIP with internally matching CRC | CRC may corroborate internal consistency but never original SHA |
| P03 | Binary STL truncated; triangle count/float/attribute corruption; ASCII STL ending cut | Overflow, malformed geometry, weak identifier, false positives |
| P04 | G-code text segment/terminator clipped or overwritten | Partial/incomplete is permitted, phantom continuation not |
| X01 | Two physically separated file fragments plus decoys/interleaved unrelated bytes | Bounded candidate enumeration, correct/ambiguous/unknown, exact fragment order via oracle only at scoring |
| X02 | Truncated image / short reads / tiny global quota / dense false signatures | Hard upper limits and explicit incomplete, not healthy or absent |

Each scenario includes both **recoverable metadata-only** and **unrecoverable destroyed-content** controls with objective truth. Multi-fault cases must state every injected fault, run only after single-fault baselines, and avoid assuming all combinations are recoverable.

## 5. Two fidelity tracks (do not label tiny pseudo-volumes standards-compliant)

- **Track T — quick 2MiB FAT32-like laboratory vectors:** preserve the current fast tests for algorithms, adversarial bytes and malformed layouts. It is explicitly **not an interchangeably formatted FAT32 volume** and must not be presented as such.
- **Track S — standards-shaped FAT32 generated on demand:** test a sufficiently large *real* FAT32 volume geometry (FAT type determined from cluster count, FAT32 at >=65,525 data clusters per Microsoft FAT32 spec). Generate disposable images at test time, **not checked-in binary blobs**; include valid boot sector, FSInfo, backup VBR, two FATs, LFN and directory chains. A 512-byte/cluster layout requires >32MiB of data clusters plus FAT/overhead; require image generation, streaming and CI disk caps. Use bounded, optional CI matrix and report actual size/runtime. Future 16KiB/cluster geometry can be a separate large/sparse local artificial test; do not allocate a huge file in main CI blindly.
- Both tracks keep file-content truth and manifest identical where practical; record expected differences in data region/cluster geometry and algorithm coverage. Add one **format-independent content generator** shared by T/S to avoid conflating filesystem geometry with 3MF/STL validation.

## 6. Scores and acceptance gates

Measure separately **(a) discovery** file-start/type candidate TP/FP/FN/TN, **(b) structural validity** ZIP/OPC/XML/STL plausibility, **(c) original byte-for-byte identity** using independent test oracle for full files or explicitly delimited extents, **(d) ambiguity** unique/multiple/unknown/incomplete, **(e) source read bytes, unique source ranges, duplicate reads, candidate combinations, peak memory and elapsed time**. No byte-identical full-file claim if only one slice matches.

Required safety: false `verified original`/false high-confidence source claims **0** on destructive/decoy cases, unchanged SHA for input, strict readable/seekable/**non-writable** stream, no path/writer/device, no unbounded allocations or decompression, Windows PowerShell 5.1, privacy CI. No fixed synthetic ratio is a user recovery percentage. A must review experiment fairness, licenses and final-head CI.

## 7. Milestones, ownership and acceptance (planned, not done)

| Order | Owner | Bounded deliverable | Completion gate |
| --- | --- | --- | --- |
| P0.0 | **A #1** | This docs-only strategy; freeze source links, matrix, IDs, safety constraints and R9 compatibility | Draft PR reviewed, no algorithm claims |
| P0.1 | **A #1 / integration/** | Deterministic byte-generator and oracle manifest for one small valid 3MF, one binary STL and G-code + explicit decoy; clean image writer only to disposable artificial temp path | Independently validate each format; clean round-trip original SHA; fixed-seed tests; no B/C/D edits |
| P0.2 | **A #1 / integration/** | Mutation engine: first M00/M01/M02/M04/P01/X02, each isolated with a reproducible mutation manifest; runner budget matrix | SHA before/after scan, known affected byte ranges, no user data, Windows synthetic+privacy CI |
| P1.0 | **C, new issue after active #61 done** | STL recognizer and 3MF package validation with false positives/CRC caveats, then bounded independent two-fragment trial | R0 sources/licenses -> R1 frozen A oracle -> R2 default-OFF tiny candidate -> R3 A/B -> A R4 |
| P1.1 | **B, new issue after active #60 done** | Link directory size/start/LFN partial evidence against A's invented fragmented files without choosing paths | Same-corpus truth, no fabricated full original path |
| P1.2 | **D, new issue after active #62 done** | Compare FAT1/2 mirror/cycle/cross-link evidence on A's identical corrupted fixtures | Same caps, no FAT winner, safe incomplete status |
| P2.0 | **A integration/** | Cross-evidence join, metrics dashboard/JSON numerical summary and standards-shaped Track S generator | Test T and S separately; 3-module cross-evidence must not double-count dependent inputs |
| P3.0 | **A** | Larger representative artificial 3D print-job corpus and bounded fragmented reconstruction research if A/B proves worthwhile | Candidate bytes and original oracle independently checked; leave actual real-IMG approval gate unchanged |

**Coordination:** The live B #60 / C #61 / D #62 Draft PRs are NOT superseded or modified by this strategy. Do not assign their implementation tasks until Team A finishes their R9 review, documents decisions and creates non-overlapping next-round issues/branches. The existing research-first R0–R4 process still applies in full. Future updates must modify authoritative GitHub docs, not rely solely on chat history.

## 8. Proposed initial pass/fail policy

1. A clean **valid 3MF, binary STL, G-code** generated file is byte-exact after healthy-image round-trip.
2. Single injected metadata-only corruption never changes the oracle original file bytes; if extraction fails, report missing/incomplete without claiming corruption of content.
3. Any injected content overwrite/bit flip is independently detected as a mismatch where observable, or declared unknown—not automatically repaired.
4. A decoy cannot be labeled as a known original file solely due to signature, CRC or 84+50N STL length.
5. If a test permits original start/size/fragment hints, label the hint explicitly; unknown-hint tests must not read oracle fields.
6. All experiments must stop within bounded reads/allocations/time, handle truncation, keep non-writable sources, expose unchanged artificial SHA and redact names by default.
7. Merge only with exact-head Windows PowerShell 5.1, privacy CI, explicit review; do not extend permission to real original media.

**Next concrete implementation choice:** A P0.1 **format-neutral clean deterministic byte generator + independent 3MF/STL/G-code oracle manifest**, NOT a production file recovery or repairs change.
