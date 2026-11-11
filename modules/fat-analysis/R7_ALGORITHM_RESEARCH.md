# Team D R7-P1 — source-researched stratified FAT anomaly A/B card

**Tracking:** [Issue #47](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/47), branch `research/d-mirror-evidence-r7-20261111`. **Baseline main SHA: `8fd97ce7306d7296f203c4561ff730b046e0c9ce`.** 2026-11-11. Team A alone decides adoption. All inputs are 64KiB artificial in-memory streams and never actual microSD / 31GB master IMG.

## R0 — Three original-source leads, non-copying license rule

| ID | Original source and attribution | Applicable principle and limitations | Rights/reuse status | Feasibility |
| --- | --- | --- | --- | --- |
| ALG-1 | Christophe Grenier / CGSecurity, TestDisk 7.2 FAT32 repair documentation: https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html and official https://github.com/cgsecurity/testdisk | Distinguish primary vs backup FAT32 boot evidence and FAT consistency; damaged copies/signatures may disagree. Do **not** implement any write/repair commands. | Original software GPL-2.0 per official project; **do not reuse or copy source**. Documentation paraphrased only. | Evidence-only PS5.1, low |
| ALG-2 | Brian Carrier / Sleuth Kit Labs, The Sleuth Kit: https://github.com/sleuthkit/sleuthkit ; rights https://www.sleuthkit.org/sleuthkit/licenses.php | Independent forensic filesystem-layer observations and cross-validation; finite samples cannot prove overall integrity. | Mixed file-level IBM/CPL/GPL/MIT/BSD licenses; no code imports or copying, individual license review would be needed | Full toolkit high; independent numeric summary low |
| ALG-3 | Microsoft, FAT32 Extensible Firmware Initiative FAT format specification v1.03 (2000), original specification reference https://github.com/libyal/libfsfat/blob/main/documentation/File%20Allocation%20Table%20%28FAT%29%20format.asciidoc | FAT32 entry interpretation, sector layout and candidate mirror assumptions; layout rules do not certify recovered data | Microsoft specification terms distinct from source code; **copyright/usage review required before any verbatim spec/code reuse**; no text or code copied | Independent already-known structure reading low |

No third-party source files or algorithms were copied. This R7 sampling design is newly written based on bounded numeric hypotheses. The current public repository has no declared uniform product code license; future import of GPL/mixed-license material must be blocked pending independent legal review.

## R1 — Frozen baseline and artificial corpus

Baseline existing module `Fat32VbrMirrorCrossEvidence.psm1` at main SHA above, called on two unverified BPB candidate geometries with `RootWindowEntries=4`, `MaxReadBytes=128`, `MaxEntries=32`. Each of the **four candidate × mirror copies** reads FAT entries [0,1] plus four near root, yielding 6 entries/copy and **24 entries / 96 bytes** on a normal artificial fixture.

The candidate method `Fat32StratifiedAnomalies.psm1`, **independent and default-OFF**, uses exactly the same four FAT copy candidates, stream and budgets, but samples three two-entry windows: FAT prefix [0,1], root [root,root+1], and midpoint [1+floor(dataClusterCount/2), then +1]. For the fixed 32-data-cluster artificial fixture and primary root 2 these are [0,1], [2,3], [17,18]. Each copy still reads 6 entries / 24 bytes (4 copies × 6 entries = 96 bytes).

Deterministic generator `tests/Run-TeamD-R7-StratifiedAB.Tests.ps1::New-D7Fixture`; fixed 64KiB byte array and constant `D47-R7-20261111` experiment identity; FAT pairs at 4096/4608 and 8192/8704, 512 byte copies, roots 2/3, 32 data clusters and 65536-byte declared volume. Hash each **invented** input internally before/after every paired test, no source/user hash or raw fixture bytes are emitted.

Scoring **only inserted artificial suspicious conditions** (not verified true disk damage): 8 cases, two negatives (clean, legal mid free entry), six positives (both mirrors share a bad marker at midpoint, EB58-like midpoint, root free, two-link root cycle, midpoint out-of-range link, fake EB58 at FAT prefix). The baseline and new sampler are treated as **binary detectors of deliberately injected suspicious synthetic states**: R6 positive if sampled anomalyCount or mirror mismatch positive, R7 positive if suspicious sampled entry or mirror mismatch positive. A negative result is *not* a claim that an entire FAT is healthy.

Expected deliberate tradeoff: R7 finds injected midpoint abnormalities that R6's root-focused sample misses, but R6 detects the two-link root cycle and R7's non-traversing sample does not. **No adoption if important root-chain behavior is silently lost.**

## R2 — Independent experimental implementation

- New `Get-ChappyFatStratifiedAnomalyEvidence -Stream <readable,seekable,non-writable> -Candidates <two unverified geometry records> [-MaxReadBytes 128] [-MaxEntries 32]`.
- Aggregate hard limits **256 bytes**, **40 entries**, **2 candidates × 2 FAT copies × 3 fixed windows**. Fair quota per copy, no quota transfer. Each stream request at most 4 bytes; short reads accurately accounted. No extra root chain traversals, no repair, writer, extraction or file-path APIs.
- Every sample reports numerators and denominators (`observedUniqueEntries`, `unknownDeclaredEntries`, per-window observed/requested entries, suspicious count, EB58-like pair count); suspicious/bad marker classifications are **hypotheses**, not proof of actual corruption. Incomplete/invalid geometry and budget/truncated reads are explicitly reported.
- A/B tests use real R6 baseline API and new R7 API as two separate experiments; the default R6 code and main behavior remain completely unchanged.

## R3 — Measured A/B on native Windows PowerShell 5.1 (artificial only)

**Tested source baseline:** existing R6 module from main `8fd97ce7306d7296f203c4561ff730b046e0c9ce`. A/B measurement uses exactly the same **8 artificial memory fixtures**, both R6 and R7 executed on each input with `MaxReadBytes=128`, `MaxEntries=32`. The 6 injected-positive cases are known synthetic FAT marker/pattern or cycle abnormalities, *not proven physical storage damage*; 2 negative cases are a clean control and a legal free midpoint entry. Fixed input identity `D47-R7-20261111`.

| Metric | R6 baseline | R7 opt-in experimental | Condition |
| --- | ---: | ---: | --- |
| True positives TP | 3 | 5 | 6 known artificial positives |
| False positives FP | 0 | 0 | 2 artificial negatives |
| False negatives FN | 3 | 1 | R7 misses identical root-cycle links, which R6 traces |
| True negatives TN | 2 | 2 | Same invented corpus |
| Precision | 3/3 = 100% | 5/5 = 100% | **Only this tiny selected synthetic set** |
| Recall | 3/6 = 50.0% | 5/6 = 83.3% | **Not a real recovery probability** |
| Incorrect original-file `verified` / auto-selected FAT | 0 | 0 | `sourceDecision=not_selected` always |
| Artificial original file bytes identical | not applicable | not applicable | Neither method reconstructs any files |
| Actual aggregate bytes read | 768 | 768 | 8 fixtures × 96 bytes each |
| Actual aggregate FAT entries read | 192 | 192 | 8 fixtures × 24 entries each |
| Per-copy theoretical coverage | 6 / 128 entries | 6 / 128 entries | **122 unobserved entries/copy** in the full-size artificial control |
| Elapsed CI stopwatch time | 267 ms | 231 ms | Single GitHub-run timing, **not statistically significant** |
| Peak memory | not measured | not measured | 64KiB synthetic arrays, no process high-water capture |
| Artificial source SHA unchanged | yes, 8/8 | yes, 8/8 | Hash is checked only inside synthetic script |
| Exact-code Windows PowerShell 5.1 test | [SUCCESS, 58/58 R7 new assertions](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43029633822) | same Windows run | D R1..R6 414/414 also passed |
| Privacy and integration gate | [SUCCESS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43029633937) | same gate | This is not a comprehensive security audit |

**Negative controls and regression:** The old R6 root-chain walker detected an intentionally created two-link cycle **present identically in both FAT mirrors**. R7's independent stratified sampler does not trace that cycle and did not signal it; explicit FN=1. Conversely, R7 sampled artificial bad/reserved/out-of-range/EB58-like FAT signatures at far midpoint entries, whereas R6's root-focused sample missed those. Both methods can receive matching but corrupted FAT mirrors; no file authenticity or correctness is inferred. Adversarial invalid/huge geometry, quota exhaustion, split/truncated Stream reads, non-writable-only validation and fake-signature/no-private-report checks passed in the new suite.

**Research verdict recommendation to A:** **research_only** unless a future additive method demonstrates no meaningful root-cycle evidence regression; retaining R6 unchanged preserves baseline behavior. R7 is independent **default-OFF** and can be examined as an alternative evidence view only. No adoption by Team D.

## R4 — A review required

Requested decision only after final-head synthetic Windows + privacy gate PASS: **research_only** or **adopt_experimental** under A's discretion; not silently enabled. The synthetic R7 variant deliberately omits the full bounded R6 root-cycle reasoning and is **not** a functional replacement. A should review whether any incremental midpoint evidence warrants a separate *opt-in* diagnostic rather than an algorithm swap. Actual 31GB IMG local-readonly gate remains **NOT APPROVED**.
