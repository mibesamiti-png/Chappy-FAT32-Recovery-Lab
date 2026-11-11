# Team C R7 — ablate the privileged first-fragment offset (synthetic research)

**Assigned Issue:** [#61](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/61) · **Branch:** `feature/c-r7-fragment-hint-ablation-20261111` · **Frozen main baseline:** `bc2fa20d4123400a2b8e9f77bc20ea5212a64dfc` · **Status:** research only, never part of normal file recovery.

## R0 — primary research and rights (recorded in Issue before code)

| Prior method | Primary original source | Strength / failure | Upstream source/license treatment |
| --- | --- | --- | --- |
| Garfinkel, *Carving contiguous and fragmented files with fast object validation* (2007) | https://www.sciencedirect.com/science/article/pii/S1742287607000369 DOI 10.1016/j.diin.2007.06.017 | Motivates finite fragment/gap candidate search and staged format checks. Search grows with start and tail combinations; plausible false positives | Academic method described publicly; no permission inferred for separate implementation code, figures or text. **No imported/copy-pasted code**; code reuse would require license review |
| CGSecurity PhotoRec | https://www.cgsecurity.org/wiki/PhotoRec_Data_Carving and https://github.com/cgsecurity/testdisk | Carving by headers and validators; false PK headers and weak G-code beginnings remain possible; fragmentation is not automatically solved | Repository metadata **GPL-2.0**. Do not import GPL files into this project; **no source reused** |
| 3MF Consortium Core ZIP/OPC spec | https://3mf.io/spec/ and https://github.com/3MFConsortium/spec_core | ZIP local headers are candidate starts, EOCD/central-directory evidence is not original-file proof, OPC/XML unvalidated | Spec repository **BSD-2-Clause**, license at https://raw.githubusercontent.com/3MFConsortium/spec_core/master/LICENSE ; no spec text/code copied. Redistribution notices apply only if reused |

Selection: independently written, test-private, 512-byte-grid **raw signature-only first-offset discovery**, followed by the unchanged R6 non-oracle grid **tail-offset** discovery and R5 bounded format validator. Initial attempt to use the full production C carver as the scout was intentionally rejected: its conservative incomplete-coverage flags prevented all five artificial cases from reaching the pairing step. This failure was logged in Issue #61 before the smaller independent raw-anchor scout replaced it.

## R1 — baseline, retained hints, ground truth and bounds

- Source is the existing **128KiB synthetic FAT32-like** bytes in C R4/R5/R6 tests, *not* a mountable full FAT32 filesystem, not a download and not user data. Deterministic 512B first slice with independent original invented bytes for G-code and ZIP/3MF. Source SHA-256 checked unchanged by every test.
- Exactly **one** formerly privileged hint removed: **first-fragment offset**. R6 reference receives the known first offset from the artificial scorer, whereas new R7 code receives no first offset, no actual tail offset and no hidden original SHA. The scorer alone knows ground-truth start and original bytes.
- **Remaining privileged information:** expected format (`gcode` or `3mf`), exact second-slice length, first-slice length of 512B, 512B alignment, known 64/128KiB synthetic bounded search region. Do not describe this as autonomous real-disk recovery.
- Five common scenarios are R6's prior exact artificial corpus: G-code unique tail, G-code altered but syntactically plausible alternative, 3MF valid tail, 3MF altered structurally plausible ZIP directory tail, and a true 3MF tail outside the permitted 64KiB scan. Negative tests add a third fake ZIP first signature and a genuine G-code first fragment **one byte off the assumed alignment**.
- The signature-only R7 start scout checks exactly one 512B chunk per grid location for ZIP `PK` local-header magic or a small G-code start family; **fake header evidence is retained** and never accepted as original provenance. It tests at most 2 starts before returning `incomplete`; for each it uses R6's bounded tail search and existing ZIP/G-code validator. No exports, no production-module changes, no FAT chain traversal, no decompression.
- Source stream is readable/seekable **non-writable** memory only. Per-case R7 worst-case cap **401,408 bytes** (one 131,072B signature scout + two pre-reserved R6 attempts of 135,168B), at most 2 starts, 512 sampled tail offsets, 16 pairs, 147,456B in-memory format checks and 30s cooperative wall time; R6 test-reference uses its stricter existing 135,168B cap. **These are not equal internal probe costs**, even though both fall under the same outer 401,408B ceiling. The experiment logs actual work rather than claiming identical workloads.

## R2 — independent prototype

- `modules/carving/tests/R7HintAblationResearch.ps1`: a test-only helper called through C's existing Windows test, not exported from `Chappy.Carving.psm1` and never default-enabled. At most 512B probe buffers, 1,024B joined validation buffers, no output files or original-media handles.
- On a signature flood (more than two possible starts), read-budget shortage or insufficient remaining time, return `status=partial` and `decision=incomplete` **without selecting an arbitrary first fragment**. A single type-consistent candidate is called only `one_possible` (not verified original). Two remain `ambiguous`; no candidate is `unknown`.

## R3 — actual synthetic A/B (first successful Windows run)

Source: [Windows PS5.1 Team C Actions #43046853187](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43046853187), code HEAD `682c907059f72f3d9b661fd4f7c6d1e1366dadda`. The final HEAD also adds negative tests and this note; **final-head Windows + privacy CI must pass before A review**.

| Measure (five hand-selected artificial cases) | R6 reference: known first offset | R7: no first-offset hint |
| --- | ---: | ---: |
| True-byte-equal accepted pairs (TP) | 4 | **4** |
| Format-consistent but not original (FP) | 2 | **2** |
| Known originals missed (FN) | 1 out of allowed scan | **1** |
| Rejected paired format candidates (TN) | Not measured at this granularity in R6; old report counts grid negatives | **3** |
| Unambiguous cases | 2 | **2** |
| Ambiguous cases | 2 | **2** |
| Unknown cases | 1 | **1** |
| Proposed candidate first offsets | Given, not measured | **7 across 5 cases** |
| Tail grid samples | 1,147 | **1,657** |
| Format-validated pairs | 6 | **9** |
| Actual aggregate source Stream.Read bytes | **195,343** | **934,961** |
| Of R7 reads: first-anchor signature scan | n/a | **589,824** |
| R7 additional in-memory validator source reads | Earlier R6 report 9,366 | **14,529** |
| False assertion of original file byte integrity | 0 | **0**: method never labels any candidate original/verified |

Observed R7 source reads are about **4.79×** the R6 reference on this tiny chosen corpus, while unambiguous decisions do not increase. TP4/FP2/FN1 reflect known artificial originals, **not** real-world accuracy. Discriminators still accept two byte-wrong candidates. Pair-trial TN counts and prior R6 grid-slot TN are **not directly comparable**; do not compute a misleading precision/recall delta from different denominators. Equal outer byte ceilings do not imply equal probes/time.

## R4 — proposed adoption and unresolved work

**Team C recommends `research_only`.** Removing one privileged offset is feasible on these aligned toy cases but increases work substantially, does not solve provenance ambiguity and still requires a known format and exact artificial tail size. The deliberately off-grid true start should be missed; extra false PK starts must trigger incomplete rather than picking the true one. Both are reasons not to publish a production/real-file reconstruction feature.

Team A must review source/license provenance, final exact-head Windows/Privacy CI, budget guards and any A/B mismatches before a merge. No original microSD or unique ~31GB master IMG accessed, scanned, hashed, written, extracted, copied or uploaded. Real IMG local run remains **NOT APPROVED** and there is **no verified restored original file count or recovery percentage**.