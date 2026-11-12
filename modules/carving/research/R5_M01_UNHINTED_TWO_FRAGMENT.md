# Team C R5 — synthetic M01 two-fragment 3MF, bounded no-oracle pairing

**Tracking:** [Issue #72](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72), after merged PR #80. Follow-up branch `feature/c-r5-m01-unhinted-two-fragments-20261112`, frozen `main` `d0138ffd7d94e308332a30fe7c364fa9979e0d80`. Research-first Issue [R0/R1 comment](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72#issuecomment-6803410463) recorded **before editing code**. Test-only, never exported to production.

## R0 provenance and license constraints

| Existing source | Principle/risks | Rights / treatment |
| --- | --- | --- |
| PKWARE ZIP APPNOTE https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT | Local ZIP `PK0304` header and EOCD `PK0506` with trailing comment length allow bounded *candidate* fragment-end inference. Fake signatures, ZIP64, EOCD spanning sectors, overwritten/truncated central directory remain risks | Specification only; no source code, text or assets imported |
| 3MF Consortium Core https://3mf.io/spec/ and source repo https://github.com/3MFConsortium/spec_core | ZIP container/OPC relationships/3D model parts; ZIP/CRC validation is narrower than original-file integrity or full 3MF conformance | Official spec repository BSD-2-Clause; no code or spec text copied; license status remains code-reuse-free |
| Garfinkel 2007 bifragment gap carving https://www.sciencedirect.com/science/article/pii/S1742287607000369 | Bounded first×tail candidates with format rejection; may become combinatorial or select structurally valid false originals | Paper ideas independently implemented; paper is not blanket code-reuse license; no implementation copied |

Background PhotoRec guide https://www.cgsecurity.org/wiki/PhotoRec_Data_Carving and GPL-2.0 source https://github.com/cgsecurity/testdisk were read as conceptual limitations only; **no GPL implementation imported**. Repository's own license status is not inferred from upstream sources.

## R1 frozen baseline / exact input / remaining hints

- **Only generated artifacts:** `tests/helpers/New-Chappy3DCleanFixture.ps1` and `New-Chappy3DDamagedFixture.ps1`, **seed 202611**; M00 contiguous 3MF and M01 synthetically valid 2-cluster physically split 3MF. 2MiB fast FAT32-like artificial image, **not** a standards-sized FAT32 volume. The original 3MF SHA and extents are available only to an independent scorer, not the research search function.
- Baseline: existing `Get-ChappyCarvingCandidates` with scan 65,536B; `MaxFileBytes=4096`, 16 candidates/probes, 8,192 probe bytes and 32,768B explicitly allowed validation re-reads (98,304 source B max). Existing scanner does **not** follow FAT and does not assemble physical M01 clusters.
- Experimental: one read-only `Test-CM01FiniteZipPairs` (test script only), 128 × 512B probe slots in the *same* first 65,536B. First fragments are proposed only by aligned `PK0304`; tail fragments by any in-sector `PK0506`; derive candidate second-slice byte length from EOCD offset/ZIP comment length **without supplying oracle length or tail position**. Order used for logical assembly = ZIP header slice followed by ZIP EOCD slice, regardless of source physical order. For each possible 2-part join, call the unchanged C ZIP validator with *opt-in* small-DEFLATE CRC explicitly enabled on in-memory candidate; default scanner unchanged.
- The candidate helper receives **no known file byte length, FAT link, correct first/second offset, original SHA, or original file name**. Remaining restrictive hints: format is 3MF, file requires exactly **two parts**, first part exactly 512B, both physical starts aligned to 512B, EOCD wholly inside a 512B second slice, 64KiB scout window, each assembled candidate <=1024B; ZIP64/encrypted/multi-part formats unsupported. Search cap 4 first anchors, 8 tail anchors, 8 pair validations.
- Candidate source reads: <=73,728B/trial (65,536B full-grid scout + at most 8×1,024B pair reads); separately at most 40,960B in-memory ZIP validator reads/trial, max 30s cooperative. Baseline gets a **different 98,304B** source cap; do **not** claim equal work or generic speed superiority. Max 2MiB input accepted as a test safety guard; non-writable readable/seekable Stream required. No external path, extraction, output or physical device.
- Candidate evidence records two ordered source-relative spans, reason, ZIP-CRC consistency, source-read counts, scanned sectors and validator bytes. `originalIdentity=unknown` and `integrityScope=structural_only_not_original_file_integrity` even when SHA computed; oracle equality is scored **outside** the helper.

## R2/R3 artificial A/B observations

Initial GitHub Windows PS5.1 CI [#43074956090](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43074956090) **PASS** on initial head `285fc94a9c3aafcf191d0142083972bbc010c2b8`; corresponding [privacy CI #43074955983](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43074955983) PASS. Later negative controls and pair-scoped scoring have been added, so **final exact-head CI must be rechecked before A approval**.

| Case (all seed 202611) | Contiguous-only baseline source reads | Candidate source reads | Separate memory validation reads | Scorer result |
| --- | ---: | ---: | ---: | --- |
| M00 contiguous control | 74,070 B | 66,423 B | 2,661 B | One ZIP/3MF CRC-consistent pair; independently byte-identical to clean 3MF |
| M01 physical 2-fragment split | 81,986 B | 66,423 B | 2,661 B | Baseline no full 3MF; candidate finds one CRC-consistent pair and matches clean 3MF SHA |
| M01 + false EOCD in empty synthetic cluster | not separately measured | 66,981 B | 4,344 B | Two tail candidates; true one accepted, fake EOCD pair rejected |

**Sample-unit discipline:** normal two-slice generated candidate pairs, not whole-device files. Pair-level TP3/FP0/FN0/TN1 across the three selected M00/M01/decoy runs (4 candidate pairs total). The **reversed assembled order** was tested separately, rejected, and is NOT included in candidate-pair TN. No case represents automatic recovery without the remaining restrictive hints, and sample counts are too small for real recovery rates. CRC only compares data against archive metadata; structural valid is not proof that bytes came from an original user file.

Expected additional negative regressions: a third/fourth/fifth fake local ZIP start crosses MaxStarts and must become `incomplete` without cherry-picking the truth; a fully covered smaller window without any start remains `unknown`; 1-pair cap with 2 alternatives becomes `incomplete`; under-sized source returns partial before any scan; no unbounded source reads, no original-verified claims and generated source SHA unchanged. **These are assertions, pending final-head CI confirmation.**

## R4 adoption and unimplemented scope

**Recommended Team A disposition: `research_only`.** This is a tiny proof of conditional bounded pairing on an unusually small artificial package with known alignment and two-fragment structure, not a safe production or real-image restore algorithm. It does not support binary STL, ASCII STL, arbitrary ZIP/OPC/XML conformance, multiple correct/false segment orders, unknown fragment sizes beyond EOCD, missing EOCD, >2 fragments or genuine noisy cluster backgrounds. Do not change production defaults or enable export.

Potential follow-up for Issue #72 after A review: add R2 format-control corpus (ASCII STL, binary STL, plain ZIP, PK decoy), independent per-format negative validators, non-aligned/short-read checks and remaining ambiguous segment orders. Request any cross-team source-extent schema adaptations from Team A, not by editing its runner or docs.

Original microSD and sole ~31GB master IMG were **not** read, scanned, hashed, copied, repaired, written, extracted or uploaded. All public CI/PR contents are artificial or coarse numeric; `docs/LOCAL_READONLY_APPROVAL_GATE.md` remains **NOT APPROVED**.