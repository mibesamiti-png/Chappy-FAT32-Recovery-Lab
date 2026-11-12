# Team C R5 — finite variable first-slice / off-grid ZIP pair negatives

**Issue:** [#72](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72) · **Assigned branch:** `feature/c-r5-variable-fragment-negative-20261112` · **Frozen A-reviewed main:** `4a9b9151c6f6c23d9a88685b7487f206c38ce0e9` · **Newer checked main at start:** `32fb0e9a3e36401435113375e092cae327bd147c` (one A-owned update ahead, no C module overlap). Team A current scope was posted in Issue comment #6812713208; R0/R1 pre-code freeze and licenses in comment [#6812897711](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72#issuecomment-6812897711).

## R0 — source review, applicable rights and assumptions

| Original source | Mechanism and limits | Source/license treatment |
| --- | --- | --- |
| [PKWARE ZIP APPNOTE](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT) (official ZIP specification) | ZIP local header PK0304 and EOCD PK0506 may bound a tiny two-piece candidate; relative directory offsets and comment size must agree. False headers/EOCD, ZIP64, encrypted/multipart, signatures crossing sector boundaries and arbitrary truncation remain unsupported | Published format specification; no implementation/text asset/code copied. Separate external source licensing would require review |
| [3MF Consortium Core specification](https://3mf.io/spec/) and [spec_core](https://github.com/3MFConsortium/spec_core) | 3MF is an OPC ZIP package; complete ZIP central directory and CRC alone do not verify full OPC/XML or independent original bytes | Original spec source repository BSD-2-Clause; no source code/spec text imported, no license inferred for unrelated libraries |
| [Garfinkel, *Carving contiguous and fragmented files with fast object validation* (2007)](https://www.sciencedirect.com/science/article/pii/S1742287607000369), DOI 10.1016/j.diin.2007.06.017 | Finite ordered fragment hypotheses plus fast object validation. Candidate floods and plausible wrong joins remain real failure modes | Academic algorithm concept only; no paper figure or third-party implementation copied. Code reuse license review required |

Background official [PhotoRec carving guide](https://www.cgsecurity.org/wiki/PhotoRec_Data_Carving), upstream GPL-2.0 source deliberately NOT used. Windows PowerShell 5.1/.NET built-ins only; no new package or license claims.

## R1 — frozen scope and same-corpus baseline

- Generated **2MiB FAT32-like** (not standards-mountable) synthetic image from `tests/helpers/New-Chappy3DCleanFixture.ps1`, seed **202611**. The independent scorer reconstructs the generated 3MF bytes from known original oracle extents and hashes them. It then constructs byte-level discontiguous layouts by clearing the originally contiguous ZIP area and relocating first/tail bytes. **These variants are carving-only byte fixtures; they do NOT claim coherent FAT chain/directory metadata**. No real image or downloaded user content used.
- Previous **baseline** `Test-CM01FiniteZipPairs`: 512B-aligned first fragment exactly 512B; 512B grid EOCD, <=128 sectors, <=4 starts, <=8 tails, <=8 pairs, 73,728 actual source read B and separate <=40,960 in-memory validation B, 30s cooperative. It receives no original offsets or SHA; its fixed first length is a privileged assumption.
- **Only one alternative**, tests-only `Test-CVariableZipPairs`: predeclared **first length candidates {512, 544}**, ZIP first-header and EOCD phase offsets **{0, +1}** from each 512B grid block. Infer end of candidate second fragment from the EOCD offset/comment. Enumerate all start×tail×length pairs up to 16, reject overlapping physical spans, join only in nonwritable memory, check using the existing bounded CRC-enabled C 3MF/ZIP validator. No original positions, clean SHA, correct first-piece length, true tail length or FAT links supplied to search. These candidate sets and known 3MF/two-piece assumptions remain privileged search restrictions.
- Fixed window **65,536B**, **128 sector probes**, <=4 start anchors, <=8 EOCD tail phase candidates, <=16 pairs, <=**81,920B total actual source reads**, <=**98,304B separate in-memory validator reads**, <=30s cooperative time, <=**1056B** assembled bytes. Nonwritable seekable stream. An over-budget flood, smaller window, too-small source budget or truncated source produces `incomplete` without picked results. The baseline has a stricter internal cap; comparing physical reads/time is indicative **not equivalent work**.
- Only external scorer sees original 3MF SHA, true first/suffix lengths/offsets and whether a tail was removed. Algorithm output always `originalIdentity=unknown` with `integrityScope=structural_only_not_original_file_integrity`; internal candidate SHA is NOT automatically the original byte identity.

## R2/R3 — six predeclared synthetic A/B cases

| Artificial case | Invented physical layout | Expected independent truth and uncertainty |
| --- | --- | --- |
| `M01_control` | 512B first fragment, aligned tail elsewhere | one byte-exact candidate; old/new reference control |
| `non512_offgrid_tail` | 544B first fragment + suffix at sector+1 | one byte-exact candidate; original fixed-512 misses |
| `offgrid_first` | 512B fragment beginning at sector+1, aligned suffix | one byte-exact candidate; original aligned-anchor search misses |
| `fake_eocd` | 544B first and +1 tail, plus a fake PK0506 signature | true pair survives; false EOCD candidates remain rejected |
| `alternate_zip_metadata` | As above, plus another candidate suffix with altered ZIP central-directory version-made-by | **two structurally acceptable pairs**, only one byte-equal to independent original SHA; return ambiguous, never auto-pick |
| `missing_tail` | 544B first fragment, no tail sector bytes | unknown, no original claim |

Additional **unscored** negative controls: a true first start at sector+2 (outside sampled phase set) and a true first piece of 560B (outside length set) must remain `unknown`, rather than claiming recovery. A fake-EOCD case with MaxPairs=1 must yield `incomplete` before validation; read cap 4096B, writable input and physically truncated window fail safely. Clean input and each mutated artificial image is SHA-checked before/after.

### Initial successful Windows PowerShell 5.1 run (pre-negative-controls HEAD)

[Team C Actions #43144844608](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43144844608) succeeded on code HEAD `8b607fcf002329f33da895203448c6f22a178e56`. Measurements below are observed in those logs. **New off-hypothesis negatives were committed afterward; exact final-head Windows and privacy CI must be checked separately.**

| Metric across six selected cases | Previous fixed helper | Variable/off-grid test-only helper |
| --- | ---: | ---: |
| Byte-identical original candidate pairs TP | **1** | **5** |
| Structurally accepted but wrong original bytes FP | 0 | **1** |
| Missed present original cases FN | **4** | **0** |
| Rejected evaluated false pairs TN | **5** | **22** |
| Unique / ambiguous / unknown cases | Reference varies | **4 / 1 / 1** |
| Physical source Stream.Read bytes, aggregate | **398,085** | **416,674** |
| Separate in-memory ZIP/C validator read bytes | **15,844** | **76,432** |
| Evaluated candidate pairs | **6** | **28** |
| Sector probes, across six cases | 128 × 6 expected from completed scans | **768** |
| Source sample elapsed, summed 6 scenarios | **217ms** | **576ms** |
| False original identity claims | 0 | **0** |

**Unit caveat:** TP and FP count accepted *pair candidates*; TN counts rejected tested pair hypotheses. FN counts cases with a physically present true pair that was not accepted. The missing-tail case has NO recoverable true pair and is not counted as FN. Different denominators must not be passed off as a population precision estimate. Elapsed times depend on one Windows runner; the broader method costs more source and in-memory reads, not a general performance optimization.

Initial case measurements: M01 source 69,146 B, 4 pair trials; non-512+1 source 69,022 B, 4 pair trials; off-grid start source 69,146 B, 4; fake EOCD source 71,316 B, 8; plausible metadata alternative source 72,508 B, 8; missing tail source 65,536 B, 0. In the ambiguous case, external original SHA matches one pair, not the altered metadata alternative. A fake EOCD is enumerated and rejected, not silently filtered using truth.

## R4 — requested adoption gate

**Team C proposes `research_only`**. Testing finite first-piece lengths and offset phases on small chosen synthetic files is a useful conditional improvement over fixed-512/sector-aligned assumptions. It is **not** general fragment recovery: arbitrary length/offset, wrong order, G-code/STL, >2 pieces, full 3MF OPC/XML, EoCD across sectors, ZIP64 or noisy false patterns remain unproven. New helper stays in `modules/carving/tests`, production scanner/extractor unchanged. Team A alone reviews test evidence and merges.

Absolutely no physical microSD or sole 31GB master IMG accessed/read/hashed/copied/repaired/written/exported/uploaded; no actual filenames/recovered user data/raw logs published. Real-image local approval gate **NOT APPROVED**.