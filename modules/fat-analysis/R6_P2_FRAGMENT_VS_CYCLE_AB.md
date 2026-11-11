# Team D Issue #73 — P2 synthetic fragmentation versus identical-mirror cycle

**Scope:** Team D, [Issue #73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73). Original assigned branch `research/d-r6-synthetic-fat-evidence-20261112` was 2 commits ahead and 3 behind current main after prior PR #82 was merged; this additive P2 is based on frozen main `d0138ffd7d94e308332a30fe7c364fa9979e0d80` using non-overwriting continuation branch `research/d-r6-synthetic-fat-evidence-20261112-p2`. Only `modules/fat-analysis` and D workflow are changed.

## R0. Primary sources, license and clean-room boundary

| Prior approach | Source / publisher | Relevance and limitation | Source-code license / reuse |
| --- | --- | --- | --- |
| FAT32 specification v1.03 (December 2000) | Microsoft Corporation, publicly archived text https://www.osdever.net/documents/fatgen103.pdf | FAT chain clusters can point to a nonadjacent cluster legitimately. FAT copies matching each other does not establish that a chain is acyclic or files are authentic. | Specification/document terms do not constitute permissive code license; only independently authored code already in this repository used. No copied code/text. |
| FAT32 evidence and repair concepts | Christophe Grenier / CGSecurity, https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html and https://github.com/cgsecurity/testdisk | Mirror comparison useful but not proof; selecting and writing a repaired FAT copy is disallowed. | TestDisk source GPL-2.0; **no code imported/copied**, no executable or repair invoked. |
| Forensic verification and provenance | Brian Carrier / Sleuth Kit, https://github.com/sleuthkit/sleuthkit and https://www.sleuthkit.org/sleuthkit/licenses.php | Partial chain evidence cannot establish original-file validity or ownership/cross-links without independent directory evidence. | Mixed file/component licenses (e.g. IBM/CPL, GPL, MIT, BSD); **license_review_required** for copying, none performed. |

This P2 **does not implement a new production algorithm**. The tested candidate combines two existing independent Team D read-only functions in a synthetic research evaluator. Both default module APIs remain untouched; no outside libraries imported.

## R1. Frozen, reproducible fair comparison

- Source main at start: `d0138ffd7d94e308332a30fe7c364fa9979e0d80`.
- A synthetic fixture helper: `tests/helpers/New-Chappy3DDamagedFixture.ps1`, frozen blob `58fedb62d76f15ebb003e4440d5f9c90feba25c5`; deterministic seed **202611**, exactly six generated cases `M00`, `M01`, `M02`, `M03`, `M05`, `X02`. It is a **2MiB FAT32-like, not standards-sized FAT32** fixture.
- The **test's external scorer**, not the tested D functions, sees case IDs, mutation manifests, generated expected hashes and interpretation labels. Each tested pipeline receives only an already-open **strictly non-writable** seekable memory Stream and numeric FAT1/FAT2 offsets, FAT length, cluster count **from the same `Get-ChappyFatGeometryTrust` parser**, plus a predetermined fixed start-index sweep 2..8 for the candidate. The sweep is identical across all cases; no user file metadata, oracle positions, root filenames, extracted file bytes or ground-truth hash are passed.
- Same total hard cap **2048 actual bytes per independent pipeline** and same source+geometry parser:
  - Baseline mirror-only: at most 1024 parser bytes + 1024 mirror bytes (128 entries across both copies).
  - Candidate mirror+chain: at most 1024 parser bytes + 512 mirror bytes (64 entries across both copies) + 512 chain budget (32 charged entries maximum, up to 16 steps per start). One pipeline, not independently added results from two full-budget runs.
- The candidate may use fewer bytes than the baseline; report **actual** and **unique physical** byte reads separately rather than asserting equal consumption. It detects only observed **mirror disagreement OR a traced FAT cycle**.
- Four independently scorable artificial cases: M00 and M01 negatives; M02 one-mirror-link disagreement and M03 identical both-mirror cycle positives. **M05 cross-link** is a known injected file ownership conflict but **not decidable from FAT alone without independent directory ownership evidence**; **X02 payload truncation** is not a FAT-cycle/mirror mismatch and is excluded from that confusion matrix. Both must remain unknown for this subtask, not TN/false healthy.

## R2–R3. One tests-only A/B research slice

`tests/Run-TeamD-R6-FixtureChainAB.Tests.ps1` compares unchanged `Get-ChappyFatMirrorWindows` with a bounded independent pipeline using the same mirror comparison plus unchanged `Get-ChappyFatChainAnomalyStats` on fixed generic numeric starts 2..8. The script generates artificial cases in memory; verifies SHA-256 before and after each test, the upstream untrusted BPB/geometry reason, equal hard source budget, total/unique physical read bytes and read calls, partial-returning stream behavior, plus write-handle rejection. M01's noncontiguous chain must not become a cycle. M03's same-corrupted FAT copies must still produce cycles while mirror differences remain zero.

**Planned scoring (not results until exact-head Windows CI):** mirror-only expected TP1 FP0 FN1 TN2; mirror+cycle expected TP2 FP0 FN0 TN2; two out-of-scope cases remain unknown. Any other observed result or false positive must be reported, **not silently relabeled to pass**. No original-file byte reconstruction is attempted; so exact recovered-file bytes and real-media recovery rates are **not applicable**.

**Measurement status:** CI, actual bytes/unique bytes, TP/FP/FN/TN and final-head privacy gate pending. Same-corpus resource fairness and implementation correctness to be independently checked by Team A.

## R4. Team A acceptance and limitations

Research-only candidate, not a replacement of existing FAT diagnostics or an automatic recovery tool. `Get-ChappyFatChainAnomalyStats` may label **observed FAT-link termination** `verified`; that field does **not** certify an original file or volume. The fixed synthetic starts include unallocated entries, whose `free` terminations **cannot** be scored as corrupt files; only objectively observed cycles are counted. Cross-link ownership, fragments longer than the finite sample, both-corrupted mirrors and X02's payload EOF remain unverified. No winner, copy selection or write recommendation. No physical microSD or sole ~31GB master IMG access, hashing, reading, copying or repair. The real-data gate remains **NOT APPROVED**.

Recommended adoption: `research_only`; a cross-link diagnosis would require independent bounded directory-owner provenance under Team A's R7 interface review.
