# STATE — 2026-11-11

## ABCD synthetic program checkpoint — 2026-11-12 JST

[Formal roadmap](ABCD_SYNTHETIC_ROADMAP.md), Issue #1. Verified weighted progress is **39%**. R0–R3 passed their full gates. Real-media gate remains **NOT APPROVED**.

| Stage | Implementation | Test | Integration | Documentation |
| --- | --- | --- | --- | --- |
| R0 | Passed | Passed | Passed | Passed |
| R1 | Passed | Passed | Passed | Passed |
| R2 | Passed | Passed | #70 and #75 | Corpus and mutation manifests |
| R3 | Passed | Passed | #76 | Two FAT32 geometries and independent verifier |
| R4 B / R5 C / R6 D | Assigned | Pending | Pending | New issues #71/#72/#73 |
| R7 | Baseline regression | Four shared cases | #77 | [Evidence baseline](R7_EVIDENCE_BASELINE.md) |
| R8–R10 | Pending | Pending | Pending | Planned |

- [#68](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/68) adopt_experimental, main `42a09a75`, [Privacy and repository safety gate](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43062628074) passed.
- [#64](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/64) adopt_experimental, main `6dc16cf2`, [Privacy and repository safety gate](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43062739217) passed.
- [#63](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/63) research_only, main `14a0b97d`, [Privacy and repository safety gate](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43062763606) passed.
- [#65](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/65) research_only, main `f24f384a`, [Privacy and repository safety gate](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43062786297) and [Team D Windows PowerShell 5.1 synthetic tests](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43062786194) passed.

The next assignments use the fixture contract from #68 pinned at `f24f384acd83c0d1dadbbc0bbd8c5acc7b926da5`. B starts with corrupted directory evidence, C with format-vs-identity evidence, D with bounded mirror/short-read observations. R2 and R3 passed [main CI](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43064528318) at `30f9951e`. The R7 baseline is preparatory. Final adapters depend on reviewed #71/#72/#73 submissions. No source or output work uses real media.

## Incident (coarse, technical facts; no user files uploaded)
- 32GB microSD used in a 3D printer; Windows shows RAW after removal while powered.
- Raw backup image length reported by local PowerShell: **31,267,487,744 bytes**. Length equality is not integrity proof.
- FAT32 partition offset: **4,194,304** bytes; nominal cluster size: **16,384** bytes.
- FAT1 offset: **5,713,920**; FAT2: **13,342,720**; root data: **20,971,520** bytes.
- Boot records plausibly FAT32. FAT1/FAT2 first 32 bytes match and show repetitive `EB-58` pattern; root cluster's FAT entry is out-of-range.
- Root directory begins with plausible entry bytes; **data integrity, original filenames, and recovery success are not established**.
- The source card and the local master IMG MUST NEVER be modified.

## Development status
- R1 FAT32 diagnostics: prototype; not fully validated in Windows
- R2 Directory tree recovery: prototype; broken FAT links cause failures
- R3 File extraction: prototype, high safety/testing priority
- R4 Repair: analysis-only, work-copy/synthetic experiments only
- QA: synthetic checks reported, incomplete independent Windows validation
- Previously stated development progress was about 67% (subjective; not a recovery probability).

## Immediate priorities
1. D: independently verify FAT geometry, reserved entries, repeated bytes, false-offset hypothesis.
2. B: reconstruct directory entries without relying on FAT chains; synthetic LFN tests.
3. C: bounded G-code/3MF signature-based extraction; validation for fragmented files.
4. A: create shared interfaces, synthetic CI, review and privacy gates.

## Current work status
Repository is PUBLIC. Teams assigned in Issues #1-#4 and independent B/C/D branches created.
- Windows GitHub Actions privacy gate PASS (run 42962302965, attempt 2).
- Synthetic valid FAT and repeated EB-58-pattern FAT QuickProbe tests PASS on Windows PowerShell 5.1 (run 42963673830).
- Draft interface: docs/INTERFACE_V1.md; roadmap: docs/ROADMAP.md.
- Main v0.5 legacy program and test script are NOT YET imported into the repo. Do not claim otherwise.
- No real IMG or real reports committed. Recovery success remains unconfirmed.

## Universal continuation / team dispatch
- Shared prompt: `docs/UNIVERSAL_BOOTSTRAP_PROMPT.md`
- Canonical work policy: `docs/UNIVERSAL_WORK_INSTRUCTION.md`
- Role/branch roster: `docs/TEAM_DISPATCH.md`
- Existing B/C/D chats use identical prompts while preserving their prior team identity. New chat without role requires one-time explicit assignment.
- Actual 31GB image remains local; synthetic-only CI verified separately from real recovery.


## Team A integration checkpoint — 2026-11-11 (latest)

- B FAT-independent directory/LFN metadata-only R1: **merged**, PR #7, main squash `96d1a785`. Issue #2 closed. 22/22 synthetic Windows tests had passed on B's PR.
- D read-only FAT32 independent diagnostics and synthetic in-memory patch/rollback simulation: **merged**, PR #6, main squash `512ca380`. Issue #4 closed. R1 25/25 and R2 29/29 synthetic Windows tests had passed on D's PR.
- A combined GitHub Actions Windows PowerShell 5.1 suite (QuickProbe + B + D R1/R2 + privacy scan): **PASS** https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42968506751
- C G-code/ZIP/3MF candidate carving: **Draft PR #5 NOT MERGED**. CI passed on C's head, but A requested P1 cumulative I/O/probe budget, dense malformed-signature stress tests, path/privacy hardening. See PR #5 review and Issue #3 update.
- Full review record: `docs/INTEGRATION_REVIEW_R1.md`. Live ownership and branches: `docs/TEAM_DISPATCH.md`.
- **Main integration state: 2/3 team PRs merged; C is pending**.
- No real 31GB IMG was accessed by these GitHub tests; no recovery success or original file validation has been established. Do not use the new modules on the real IMG until A's local safety-validation workflow is reviewed.
- Standalone A local runner remains pending. Import of legacy v0.5 is also pending and must not be assumed complete.


## Team A new dispatch — 2026-11-11 (supersedes previous B/D waiting status)

- **Team B R2 assigned:** [Issue #8](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/8), branch `feature/b-directory-r2-20261111`. Scoped work: false-positive reduction, confidence-aware directory hierarchy candidates, malformed LFN robustness, synthetic Windows tests. Original B R1 remains merged.
- **Team D R3 assigned:** [Issue #9](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/9), branch `research/d-fat-r3-20261111`. Scoped work: FAT1/FAT2 bounded range differences, EB-58 distribution, cluster-chain anomaly statistics with explicit uncertainty and budgets. Original D R1/R2 remains merged.
- Both new branches were created from `main` SHA `c7ff118acf9f667aef45cdc2b784269f666d174c`, and neither new issue is completed at assignment.
- **Team C** remains on existing Draft PR #5, Issue #3, awaiting its A review fixes; no change in ownership.
- Latest live roster: `docs/TEAM_DISPATCH.md`. The **same universal prompt** may now be pasted into B, C and D chat sessions without rewriting.
- All teams work on synthetic fixtures only, report PR+CI evidence, and may not use or upload the real 31GB master IMG; confirmed recovery count remains unknown.

 
## Latest Team A checkpoint — 2026-11-11, second B/D integration

- B R2 P1 [PR #10](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/10) merged, squash `00a1bba6a59b7a24a1291b0a31f6e052e90573b4`. R2 Issue #8 remains OPEN for confidence-aware hierarchy and malformed/ambiguous graph tests.
- D R3 P1 [PR #11](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/11) merged, squash `98cafeb423c70bb04502f33238f24b4a866c6753`. R3 Issue #9 remains OPEN for EB-58 mapping and bounded chain anomaly summaries.
- A synthetic regression runner `runner/Invoke-ChappySyntheticRegression.ps1` merged via [PR #12](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/12), squash `7094e7809239b1efc721b2d05db9507b4c256f38`. Runs QuickProbe, B directory, D R1, D R2 and D R3 synthetic Windows PS5.1 suites in isolated processes.
- **Post-merge integrated Windows CI PASS:** https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42972326019 .
- C [Draft PR #5](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/5) is still UNMERGED at last reviewed `6b4b3ab`; cumulative I/O safeguards now pass synthetic CI, but output alias/physical device path and free-form report sanitization and ZIP integrity semantics remain A blockers.
- New B/D continuation branches and exact next tasks: `docs/TEAM_DISPATCH.md`. **Three of four current parallel stream deliverables integrated** (B/D/A); C is pending review hardening. That ratio is NOT a recovered data rate.
- User's real 31GB microSD master IMG has not been scanned by this GitHub workflow and must never be modified or uploaded. Actual restored files verified: none confirmed. Legacy v0.5 import remains pending.


## Current Team A checkpoint — 2026-11-11 (B14/D13/A15 integrated)

- **B PR #14** hierarchy evidence graph merged into `main`, squash `5077d38f6a90013546b916b9aabac23ae7ac0fc9`. Exact-head B PowerShell 5.1 + privacy CI passed. It produces candidate graph metadata, not verified paths. Issue #8 still open.
- **D PR #13** EB58-pattern mapping and FAT-offset hypotheses merged into `main`, squash `9fd8c9aa0e4fb4df937553c8679f220effbeb06f`. Exact-head D PowerShell 5.1 R1/R2/R3 P1/P2 and privacy CI passed. No cause of corruption established. Issue #9 still open.
- **A PR #15** opt-in regular-local-IMG read-only *aggregate preflight* merged, squash `5fbb7be40e6cdd304806974f6b0526f667feb47d`. New synthetic FAT32 test fixture, explicit consent and source path/device/reparse checks, no extraction/writes/reports/private names. 7-suite isolated synthetic runner now covers B/D/A. Exact-head branch Windows CI and [main post-merge CI](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42975361336) PASS.
- **C PR #5 still DRAFT/UNMERGED**, last A-reviewed `03786895`: global I/O bound and report sanitization fixed, but secure export path/device/reparse validation and explicit structural-only ZIP integrity caveats are P1 merge blockers.
- **Real 31GB IMG must NOT be scanned yet**; local trial approval checklist: `docs/LOCAL_READONLY_APPROVAL_GATE.md`. No actual original user data has been accessed via GitHub, recovered or validated.
- Next B/D continuation tasks and new branches in `docs/TEAM_DISPATCH.md`; A retains Issue #1 for local safety acceptance and integration; B #8 and D #9 remain open.

 
## Latest Team A handoff — fourth integration round (2026-11-11)

- B PR #17 (malformed LFN validation + 160 fixed-seed artificial mutations + modeled historical acceptance A/B) MERGED, squash `232056a11dc159399c910763f2c9ae7267513ccc`; synthetic Windows 5.1/Privacy CI PASS on exact PR head. B R2 Issue #8 closed. B next new R3 Issue #19 (`feature/b-directory-r3-validation-20261111`), synthetic-confidence calibration and bounded adversarial scan tests.
- D PR #16 (read-only FAT chain sample anomaly classification: free/reserved/bad/out-of-range/cycle/EOC/budgets) MERGED, squash `e9fca56779264ca46e793f2406b919e4b92234d4`; D 165/165 artificial test assertions and privacy CI PASS. D Issue #9 remains open, next numeric directory/FAT consistency task (`research/d-fat-r3-consistency-20261111`).
- A PR #18 (central synthetic CI + read-only local experimental preflight root-chain sample) MERGED, squash `6ac7e8a4a912c8a273e49969a0d8287acd110f43`. Branch synthetic Windows CI PASS, post-merge main [CI PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42979036878). No original media scan.
- C Draft PR #5 remains unmerged, latest reviewed `467f0534`: C fixed output-path opt-in and Windows device/UNC/reparse blocking; synthetic/Privacy CI passed. C still needs explicit ZIP structural-only integrity semantics and adversarial tests. No live extraction authorized.
- **Actual 31GB master IMG access remains NOT APPROVED** and no original user data may enter public CI/Issues. No verified file recovery, original name or repair success. See `docs/LOCAL_READONLY_APPROVAL_GATE.md` for the independent local-review checklist.
- Live assignments/branches: `docs/TEAM_DISPATCH.md`. Older sections are historical snapshots; this is the most recent checkpoint.


## Team A damage-benchmark checkpoint — 2026-11-11 (latest)

- **B PR #20** merged `6d147814aeba204f0b547b649b344d2d69b8ebbc` (23 artificial directory confidence cases, 10 chosen positives / 13 negatives, matching exact-head Windows B/Privacy CI). R3 Issue #19 closed; next B **Issue #24** `feature/b-directory-r4-fragmented-qa-20261111`.
- **D PR #21** merged `0e825f8298b688dbca8a706d45d37ad6112b73b3` (bounded anonymous directory/FAT consistency with 211/211 total D artificial test assertions, matching exact-head Windows D/Privacy CI). R3 Issue #9 closed; next D **Issue #25** `research/d-fat-r4-geometry-guards-20261111`.
- **C PR #5** merged `110ebbdaa29045cda7935061308f85c70ca3692f` as an **experimental** bounded G-code/ZIP/3MF scanner, source-read-only by usage, ZIP structural-only integrity semantics, opt-in extraction default OFF, redacted reports. Exact-head Windows/Privacy CI PASS. Initial Issue #3 closed; next C **Issue #23** `feature/c-carving-order-r2-20261111` fixes a newly found multi-file ordering bug. **Real IMG extraction remains forbidden**.
- **A new Draft PR #22** `integration/a-synthetic-damage-benchmark-r1-20261111` creates a *disposable artificial 2 MiB FAT32-like IMG*, two invented G-code/3MF bodies and 7 clean/FAT-root-corrupt/ZIP-payload-modified/truncated/missing scenarios, byte-for-byte comparison with original artificial content. 10/14 is a **fixture expectation only, not measured recovery success**.
- **A QA discovered a real source-code logic bug** on artificial clean IMG: C scanning ZIP first at offset 58880 sets a lower-bound `skipZip` that suppresses earlier G-code at offset 58368. Exact-window Windows CI [42986062061](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42986062061) **FAILED** (clean case found 3MF but not G-code). The failure is preserved in Draft PR #22; C owns fix in Issue #23. This is an engineering bug on artificial data, **not an assertion about real user files**.
- All actual user microSD/master IMG data remain untouched, unscanned and unuploaded. Local preflight against 31GB IMG **NOT APPROVED**. No real recovered file integrity verified.
- Live assignments: `docs/TEAM_DISPATCH.md`. The earlier snapshots above are historical.


## Team A QA infrastructure follow-up — 2026-11-11 (after benchmark defect)

- [A PR #26](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/26) **merged** `7b03a75528f902f85c2a96d12ea64b5679587983`: the central Windows PowerShell 5.1 privacy/integration job now runs **nine independently isolated artificial suites**, including D's new R3-P4 directory/FAT consistency checks. [Exact-head branch CI PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42987218221) and [post-merge main CI PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42987347212).
- The separate [A damage-benchmark Draft PR #22](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/22) remains RED on a deliberate 7-case synthetic regression: **observed 6/14 byte-identical candidate slices vs expected 10/14 under known artificial corruption**. [CI evidence](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42986714746), with exact scanner ordering bug explained in [Team C Issue #23](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/23).
- Do not force-green or merge Draft PR #22. After Team C fixes the order bug and A merges its reviewed PR, re-run A benchmark against current main and investigate residual mismatches. **No real 31GB IMG access or actual file recovery occurred**.


## Latest Team A checkpoint — 2026-11-11 (BCD and synthetic benchmark integrated)

- Reviewed and merged **B R4 PR #27** `1f5144cc331a012a42bb5e54e368249c167a7f63` (discontiguous/orphan/false-positive directory synthetic QA), **C R2 PR #29** `4ff0f1d369c2f7774b4df7dbae4ca473bcaa2b72` (source-offset-ordered G-code/3MF candidate scanning), and **D R4 PR #28** `b0da9141ac566bce13b4dccd6db8090454bc0b38` (bounded MBR/BPB/backup-VBR/FSInfo geometry trust evidence). All exact-head Windows PowerShell 5.1+privacy CI passed.
- Independently re-ran A's original damage-regression Draft PR #22 on all new B/C/D code **without weakening the artificial fixture expectations**. [Windows CI #42990769921](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42990769921) reports 7 artificial 2MiB FAT32-*like* scenarios with **10/14 byte-for-byte original artificial candidate matches, expected 10/14**, zero mismatches, including previously skipped 85-byte G-code before 414-byte 3MF. **A PR #22 merged** as `b6fa5438d21a2dc054030f8f004bf0668ceea7f2`. This is **not a real recovery rate**; 4 fixture file-instances are intentionally modified/missing.
- **A PR #30** expanded central Windows/Privacy integration CI to **12 independent artificial test scripts**, including Team C and Team D R4 dedicated suites. Merged `481878b2420f6b3852f16681ca8c6565813b004c`. [Latest post-merge main CI #42991261004 PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42991261004).
- B Issue #24, C Issue #23 and D Issue #25 have been closed as completed *scoped milestones*. New assignments and branches from main `481878b2`: B Issue #31 `feature/b-directory-r5-false-positive-20261111`, C Issue #32 `feature/c-zip-deflate-integrity-r3-20261111`, D Issue #33 `research/d-geometry-disagreement-r5-20261111`. Refer to `docs/TEAM_DISPATCH.md` for live ownership.
- **No user's real microSD or 31GB master IMG read/written/tested, repaired, extracted or published**. Experimental local preflight and real-file export remain not authorized under `docs/LOCAL_READONLY_APPROVAL_GATE.md`. No genuine restored file count, provenance, checksum, or success rate verified. Any 'verified' ZIP confidence is structural only unless independently content-verified.


## Team A latest checkpoint — 2026-11-11 (B R5 / C R3 / D R5 integration)

- **B PR #34** merged `cf6eed983489908adb6f7f471dc7b15939bd2b5a` after exact-head B PowerShell 5.1 + privacy CI PASS. Adds weak two-entry directory **partial confidence** without removing accepted orphans. Chosen artificial 32-case classification still TP13/FP8/FN0/TN11; probable-only TP8/FP0 in that small controlled corpus, NOT real precision.
- **C PR #36** merged `6c78664b818bea064066aee2c72546048461cfc6`, exact-head C/Privacy synthetic CI PASS. Optional `-EnableSmallDeflateCrc` off by default, strict compressed/decompressed/global quota, malformed DEFLATE/CRC-negative tests and allowlisted redacted reports. **CRC match against ZIP metadata never proves original file integrity**. Built-in .NET decompression is not forcibly interruptible mid-call.
- **D PR #35** merged `01a3001a75355042a563857842317178647a9628`, exact-head D 356/356 synthetic assertions and privacy CI PASS. Read-only primary/backup VBR disagreement under MBR/FSInfo evidence with max 2048 bytes read. No automatic winner, repair or trusted original FAT32 diagnosis.
- **A PR #37** merged `b19f45ac130634fb86aa0eb7ac514cecd089afe0`: extended Windows synthetic/privacy gate to **13 isolated synthetic suites** (including D R5). Exact-head [branch CI PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42997711549) and [post-merge main CI PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42997918561). A seven-case 2MiB artificial IMG candidate-byte match unchanged at **10/14 as expected**, NOT a real recovery percentage.
- Closed completed B Issue #31, C Issue #32, D Issue #33. Opened new independent assignments B Issue #38 `feature/b-hierarchy-confidence-r6-20261111`, C Issue #39 `feature/c-fragment-candidates-r4-20261111`, D Issue #40 `research/d-mirror-vbr-crosscheck-r6-20261111`. Refer to newest `docs/TEAM_DISPATCH.md` for authoritative ownership.
- **Original microSD/31GB master IMG not accessed, scanned, repaired, copied or uploaded.** Local real-image diagnostics and any real-file extraction remain **NOT APPROVED** under `docs/LOCAL_READONLY_APPROVAL_GATE.md`. Genuine restored-file count and integrity unknown. Earlier progress sections above are historical snapshots.

 
## Latest Team A sixth integration — 2026-11-11

- **B R6 [PR #41](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/41)** merged `769e2148dd3668b82a0760d001dcdbb8d16efd65`: confidence propagated to hierarchy edge claims from accepted parent/child container and directory entry; weak, ungraded, ambiguous/cyclic, deleted or incomplete evidence cannot become probable. No original path/file identified. Synthetic tests B exact-head Windows/Privacy CI PASS.
- **C R4 [PR #42](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/42)** merged `117d667e8cd90f835458c30a14aca6d6303553b8`: tests/docs only. 128KiB artificial fragmented G-code/3MF images check that contiguous carving outputs remain partial/incomplete when file pieces are discontiguous; no production fragment reconstruction. Exact-head Windows C/Privacy CI PASS.
- **D R6 [PR #43](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/43)** merged `661e669e1607550651ec5734307663af35ea5a4b`: bounded primary/backup VBR hypothesis x FAT mirror tiny entry cross-evidence, strictly nonwritable Stream, <=256 bytes/40 entries, no geometry/FAT winner or repair claim. Exact-head Windows D 414/414 synthetic assertions and privacy CI PASS.
- **A [PR #44](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/44)** merged `6d33eac626f2337ab7dfcb0fa2b4b9dc6ba712ce`: central Windows PowerShell 5.1 privacy/integration runner includes D R6 and now executes **14/14 isolated artificial suites successfully**, exact-head [CI PASS #43005143817](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43005143817); [post-merge main CI PASS #43005467944](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43005467944). Selected seven-case artificial damage benchmark still **10/14 expected original-byte-identical candidate slices, 10/14 observed**, not real recovery accuracy.
- Closed completed B [#38](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/38), C [#39](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/39), D [#40](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/40). New separate B [#45](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/45) `feature/b-hierarchy-evidence-r7-20261111`, C [#46](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/46) `feature/c-fragment-groundtruth-r5-20261111`, D [#47](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/47) `research/d-mirror-evidence-r7-20261111`. See `docs/TEAM_DISPATCH.md` for live ownership and explicit scope.
- **Original physical microSD and unique ~31GB master IMG never accessed or tested through these integrations**; no source writes, extraction, repair, public real-data upload, recovered file proof or genuine success rate. The local read-only gate `docs/LOCAL_READONLY_APPROVAL_GATE.md` is still NOT APPROVED.

## Team A algorithm-research workflow preparation — 2026-11-11

- **Only the workflow is changing**: previously assigned B Issue #45, C Issue #46, D Issue #47 and their existing branches/scopes are retained. Current main baseline before the docs-only A PR was `4fcf0227f1c57d78f3e2a4166d5ea5c0b558baf4`; previous central synthetic Windows CI 14/14 PASS [run 43005908277](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43005908277).
- New authoritative `docs/ALGORITHM_RESEARCH_PROTOCOL.md`: cited prior-art survey, code-license safety, same-fixture baseline, bounded independent experiment/default-OFF, measurable TP/FP/FN/TN and original artificial byte-identity, A-only go/no-go adoption. `docs/ALGORITHM_RESEARCH_TEMPLATE.md` is the reusable evidence card; `docs/ALGORITHM_RESEARCH_STARTER_REFERENCES.md` lists original sources (not code-import permissions).
- `docs/UNIVERSAL_WORK_INSTRUCTION.md`, `AGENTS.md` and `docs/TEAM_DISPATCH.md` require B/C/D to publish R0 research in their already assigned Issue before altering the production algorithm. A owns coordinating/merging only.
- **No B/C/D research or A/B trials are reported as executed merely by these documentation changes.** No new recovery algorithm is claimed implemented by this setup. Real original microSD/31GB master IMG not accessed, written, extracted or uploaded; local real-image diagnostics remain NOT APPROVED.


## Latest Team A R4 research adoption and integration checkpoint — 2026-11-11

- **B R7 [PR #49](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/49) merged** `b7a323a8662d8e6781d1590ed2f751019fd15ce3`, A decision **adopt_experimental/default OFF**. Fixed 13 artificial structural-link test cases, baseline TP2 FP3 FN0 TN8 to opt-in conflict-aware candidate TP2 FP0 FN0 TN11. Only structural probable evidence, **NOT true original path**. R0 original research sources (Microsoft FAT32 spec, TSK, Linux GPL VFAT), licensing cautions documented before coding.
- **C R5 [PR #51](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/51) merged** `60da0ffed552754e2805453f3c425ed7c62c120c`, A decision **research_only**. Test helper pairs two short inventoried fragments, 5 artificial scenarios/9 candidate pairs TP4 FP2 FN1 TN3; four artificial original-byte-identical pairs but only two unambiguous. Candidate gets **oracle-provided second offsets** absent from baseline; no fair generalized file recovery improvement or new production API. R0 Garfinkel/PhotoRec/3MF sources and license reviews on Issue #46.
- **D R7 [PR #50](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/50) merged** `411c3af2a60e02b5661fd0e03eea980a06f8c467`, A decision **research_only/default OFF standalone**. Same 8 entirely artificial FAT cases at identical 768 bytes total read: baseline R6 TP3 FP0 FN3 TN2, experimental stratified R7 TP5 FP0 FN1 TN2. **R7 misses a mirrored root-cycle detected by R6**, so must not replace the baseline. R0 TestDisk/TSK/FAT32 formatting source and license cautions recorded in Issue #47.
- **A [PR #52](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/52) merged** `53e10fd0733b8bbceabcdcf0858e7fa376ec0cb5`, adding D R7 A/B tests to central Windows PowerShell 5.1 privacy/integration gate; B/C new tests run through existing entries, now **15/15 independent synthetic script suites PASS** exact head [CI #43033862184](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43033862184) and post-merge main [CI #43034313752](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43034313752). Old A seven-case deliberately corrupted synthetic IMG benchmark still observed **10/14** known original-byte-identical candidate slices, matching its expected 10/14; **NOT real file recovery rate**.
- A decisions and original-source / experimental limits: `docs/R7_ALGORITHM_AB_DECISIONS.md`. All B/C/D final-HEAD independent Windows synthetic + privacy CI successful, all three milestones B Issue #45, C #46, D #47 closed. **New research-first assignments** B [Issue #53](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/53) `feature/b-r8-conflict-coverage-20261111`, C [#54](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/54) `feature/c-r6-nonoracle-tail-search-20261111`, D [#55](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/55) `research/d-r8-additive-anomaly-evidence-20261111`; see live roster `docs/TEAM_DISPATCH.md`.
- **Safety:** Original physical microSD and sole ~31GB master IMG not read, scanned, repaired, recovered or uploaded in this work. All public tests synthetic and redacted. `docs/LOCAL_READONLY_APPROVAL_GATE.md` remains **NOT APPROVED**. No proven actual original file integrity, restoration count or real-world success rate.


## Team A latest review checkpoint — R8 / C R6 integration, 2026-11-11

- **B [PR #56](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/56)** merged `e51a288b135cf8cb4b63c41c6c91eea7da35bbe1` with A decision **adopt_experimental, default OFF**. B R8 14 chosen artificial structural-confidence cases R7 baseline TP2 FP8 FN0 TN4 vs opt-in numeric coverage guard TP2 FP1 FN0 TN11. **Spoofed full byte counter FP1 remains**; numeric coverage cannot authenticate unobserved paths or complete original filesystem.
- **C [PR #58](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/58)** merged `3849842a6c0317fb4aa3047196a48ed18cf6eba2` A decision **research_only/tests-only**. Five artificial two-fragment cases 1147 grid positions, TP4 FP2 FN1, two unique/two ambiguous/one unknown; privileged first fragment offset, tail byte size and format remain, no generic original reconstruction.
- **D [PR #57](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/57)** merged `82c59c5db9071a3a060867e03d785f2e1f656b6e` A decision **research_only/default OFF**, original R6 remains default. Eight selected artificial cases R6 TP3 FP0 FN3 TN2, R7 TP5 FP0 FN1 TN2, R8 TP6 FP0 FN0 TN2; R8 costs 1280B actual total vs R7 768B and does not establish unique cross-pass coverage.
- B/C/D exact-head Windows PS5.1 and Privacy CI PASS, research source-license cards present in Issues #53/#54/#55 before code changes, no upstream restricted code copied.
- **A [PR #59](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/59)** merged `58df3c6dd2d9bdf9d67c3ed9e9d03a930b7f13b3`, adding standalone D R8 A/B synthetic test and R8 adoption decision document. [PR-head Windows CI #43043058113](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43043058113) **16/16 isolated synthetic scripts PASS**, original artificial damaged-IMG benchmark expected/observed 10/14 byte-identical candidate extents; [post-merge main CI #43043449530](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43043449530) PASS. Research decisions recorded in `docs/R8_ALGORITHM_AB_DECISIONS.md`.
- Finished B [Issue #53](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/53), C [#54](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/54), D [#55](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/55) closed. Next B [#60](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/60) real observation coverage vs fake counters, C [#61](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/61) privileged hint ablation, D [#62](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/62) longer root cycles/remote anomaly quota tradeoff. See live `docs/TEAM_DISPATCH.md`.
- **Real 31GB IMG and physical microSD not read/scanned, written, exported or uploaded**; only disposable artificial data in public CI. A's local real-master-img read-only approval gate remains **NOT APPROVED**. No original user files verified, no real recovery rate.

## Current Team A research review — 2026-11-12 JST (post B/C/D P2)

- A exact-head reviewed and merged B [#84](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/84) `04dc24ef` (`research_only`: legitimate empty-record FP1 on selected artificial negative controls), C [#86](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/86) `579027d6` (`research_only`: restricted 512B-aligned two-fragment M01 3MF candidate without oracle locations), and D [#85](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/85) `f39bdfe0` (`research_only`: bounded mirror+cycle observation, M05/X02 unknown).
- Each exact submitted HEAD's dedicated Windows PowerShell 5.1 and privacy CI passed. A's central runner adds the D R6 P2 isolated test via an integration PR; its final-head and post-merge checks must be independently verified.
- See [latest evidence and next acceptance criteria](ABCD_LIVE_CHECKPOINT.md). R0-R3 only are fully gated (**39%**); R4-R7 partly done. B #71/C #72/D #73 remain open, no production inference promoted and no extraction from user data.
- Hard safety remains: no access to real physical microSD or sole 31GB master IMG; local real-image test gate **NOT APPROVED**.

## Active continuation handoff — 2026-11-12 JST

- B #71, C #72, D #73 next independent branch assignments published in [TEAM_DISPATCH](TEAM_DISPATCH.md) and linked Issue comments. Branches begin at A-reviewed `main 77743db19048c5e00601aa80e61a67ca41fdaac0` after reviewed PRs #84/#86/#85 and A #87.
- A post-main [Windows PS5.1 22/22 synthetic plus privacy CI #43137106907](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43137106907) SUCCESS. No user/master IMG accessed, and live recovery rate is unknown. Only 39% fully gated R0-R3 engineering milestones.
- A next separate R7 task: actual candidate source-read provenance, conservative evidence union and one shared I/O limit; R8 output awaits R7 gate.

## A live integration milestone — 2026-11-12 JST

- A reviewed/merged B #89 `39b407c1` (default-off observed directory read ranges), C #91 `c69a4234` (test-only STL/ZIP negative controls) and D #90 `91346381` (default-off FAT physical read provenance). Formal reviews are on the PRs.
- A #92 merged `4a9b9151`: one nonwritable, shared 120,000B physical source budget for B/C/D on invented M00/P02; dedicated R7 test and documentation, [branch Windows 23/23 + privacy CI PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43142165708), [post-main CI PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43142388964). This is synthetic integration, not real-file restoration or full R7.
- B #71 / C #72 / D #73 remain open; next bounded branches and Issue assignments are in [live dispatch](TEAM_DISPATCH.md). A's subsequent runner PR includes D's own observed-I/O suite, with final-head and post-merge CI pending until executed.
- R0–R3 fully accepted => **39%** weighted roadmap; R4–R7 partial, R8–R10 incomplete. Real microSD and sole 31GB IMG not read/hashed/copied/written/repaired. **NOT APPROVED** remains the local trial gate.

## A R7 candidate-origin trust and next round — 2026-11-12 JST

- Reviewed and merged B #95 (adopt_experimental/default OFF), C #96 (research_only) and D #94 (research_only). Final-head Windows PS5.1/privacy CI PASS for all three.
- A [#97](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/97) merged 9be7bb6d; A test-only candidate-specific read receipt boundary and D P4 regression. [Exact-head 26/26 PASS CI](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43147376900), [post-main CI PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43147583478). Proves only measured read coverage on invented data, not original integrity or actual file recovery.
- B #71, C #72, D #73 continue on new branches described in [live dispatch](TEAM_DISPATCH.md); A next gate is to attach REAL C validator-specific physical reads to A-issued receipts, without trusting unverified module-provided evidence IDs. Older team branches preserved.
- R0-R3 full acceptance = **39%** weighted engineering milestones. R4/R5/R6/R7 partial, R8–R10 incomplete. Physical microSD and sole 31GB real IMG not read/hashed/copied/scanned/written/repaired/uploaded, real test gate **NOT APPROVED**.

## Team A R7 live candidate validation evidence and handoff — 2026-11-12 JST

- A reviewed/merged B [#99](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/99) `52caaa09` (opt-in/default-OFF directory partial physical Stream.Read returns), C [#100](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/100) `4d53f587` (test-only actual 3MF candidate revalidation) and D [#101](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/101) `47e63e56` (test-only cross-source identity checks). Exact final-head Windows PowerShell 5.1 and privacy CI succeeded; limits and false/unknown cases in PR review comments.
- Team A [#102](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/102) merged `e420369bb6de79e33de009cbce570315880a589f`, test-only A-issued Stream.Read events for the **actual C candidate validator**, plus D P5 standalone gate. [PR-head 28/28 Windows+privacy CI](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43152990724) and [post-main 28/28 Windows+privacy CI](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43153238957) PASS. Three generated M00/M01/P02 streams each read 67,310 total source bytes (66,423 scout + 887 physical candidate validation); only an A-issued receipt can attribute per-candidate coverage. Original identity remains unknown; these results do not guarantee real recovery.
- B #71 / C #72 / D #73 remain open with newly created separate work branches/next P1 comments; see [current live dispatch](TEAM_DISPATCH.md). A next task: mixed-source and ambiguous-fragment negative receipts, broader standards-shaped artificial corpus and shared read budget. No R8 extraction before R7 full acceptance.
- Weighted full-gate R0–R3 = **39%**; R4–R7 partial, R8–R10 pending. Physical microSD and only ~31GB master IMG never accessed/read/hashed/copied/scanned/repaired/extracted/uploaded. Local real-media gate **NOT APPROVED**.

## A cross-source read-receipt integration and next BCD handoff — 2026-11-12 JST

- A reviewed/merged B [#105](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/105) `25581577` (opt-in conservative UNKNOWN file-size record, reduces false alerts at expense of M04 genuine detection), C [#106](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/106) `dd9aa01f` (test-only ambiguous structurally valid two-fragment 3MF), D [#104](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/104) `5b31812d` (test-only dual-mirror/common FAT corruption research). All exact-head Windows PowerShell 5.1 and privacy CI PASS; limited artificial TP/FP/FN/TN findings and unscored unknown cases described in PR reviews and [ABCD checkpoint](ABCD_LIVE_CHECKPOINT.md).
- A [#107](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/107) merged `9393fce2`: A-only test source-token namespaced receipt IDs fix collision when different generated IMG streams have identical numeric read offsets/bytes. D P6 regression included in central runner. [Exact PR-head 29/29 Windows+privacy PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43158007893) and [post-main 29/29 Windows+privacy PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43158227444). Source-observed remains `originalIdentity=unknown`; this is synthetic-only test code, not product extraction.
- B #71, C #72, D #73 remain open; new branches and bounded P1 task comments were created at main `9393fce2`, see current [TEAM_DISPATCH](TEAM_DISPATCH.md). A next stage: live multi-candidate validation receipts and short-read/phase abuse with shared budget; R8 extraction/export not yet approved.
- Weighted fully gated R0–R3 = **39%** engineering roadmap. R4–R7 partial and R8–R10 pending. Real microSD/sole ~31GB IMG never accessed/read/hashed/copied/scanned/written/repaired/extracted/uploaded, real-media authorization **NOT APPROVED**.

## Team A R7 bounded live multi-candidate and global source quota — 2026-11-12 JST

- **Starting main:** `0ded7b8f215405648d8f147c6cde8447b8d0615f`, with current B #71 / C #72 / D #73 next P1 research branches already assigned in the live roster; **no B/C/D PR was open at start of this A turn**. Those existing branches/Issue scopes are unchanged and must not be overwritten.
- **A [PR #109](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/109)** reviewed and merged `c79835402b67c16a7b2d6034ea933072c0bf49f2`: A-only isolated synthetic test `tests/Test-A3DLiveMultiCandidateBoundary.ps1` invokes real C test-only 3MF scout/validation and the A-owned read meter. Adds an explicitly constructed competing *reversed* two-fragment hypothesis on the SAME synthetic input; the first candidate is format_consistent and the reverse is format_rejected, while both can be `source_observed` and neither is `originalIdentity=verified`. Event IDs are candidate-specific; cross-use is refused. A mislabeled `scan` cannot attest actual candidate validation. With one 1,024B physical quota after 300B scouting, first 512B candidate fragment is read but the second is refused, so C=`partial` and A=`unattributed` rather than fabricated EOF/recovery.
- **Exact PR-head Windows PowerShell 5.1/privacy [CI #43162996293](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43162996293)** SUCCESS: **30/30** isolated artificial scripts. Selected additional source facts: across two candidate validations + mislabeled phase, 69,084 returned source bytes; truncated global-budget case 812 returned bytes with 512 actual candidate bytes and partial C/A verdict. Same artificial SHA before/after, strict nonwritable memory source. [Post-merge main CI #43163217455](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43163217455) was queued/in-progress when this checkpoint was authored; **verify status independently before asserting post-main success**.
- **Remaining A R7 gates:** independently discovered ambiguous C candidates rather than A-constructed reverse, genuine short-return EOF negative beyond budget exhaustion, broader multi-seed standards-shaped artificial FAT32 fixtures, one shared B/C/D physical source quota and candidate-specific actual C evidence join. A has not promoted an experimental algorithm or authorized R8 export.
- **Progress and safety:** fully gated R0–R3 only = **39% weighted synthetic engineering roadmap**. R4/R5/R6/R7 remain partial; R8–R10 incomplete. This is **not** actual data recovery percentage. Physical microSD and unique ~31GB master IMG were not accessed/read/hashed/copied/scanned/written/repaired/extracted/uploaded. Real-media approval gate **NOT APPROVED**.

## A next-round checkpoint — 2026-11-12 JST, after PR #114

- B #112 merged c98b8b8d, C #111 merged 1522022e, D #113 merged dab6aee7, each **research_only** after exact-head Windows PS5.1 and privacy CI passed. Observationally identical size records, physically distinct CRC-consistent 3MF candidates, and FAT sample entry512 blindspots remain honest UNKNOWN rather than authenticated originals.
- A [#114](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/114) merged `4a378fc32cfd6603e20b5acbbfa0328a6a718770`. A-owned R7 C-discovered two-candidate physical receipts and 17-byte true short-return EOF regression; D P7 standalone included. [Final PR-head 32/32 + privacy CI #43201583750](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43201583750) PASS, [post-main 32/32 + privacy CI #43201973968](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43201973968) PASS. A-only receipt-ID cap 32→128, event-total limit 256 and physical source budget unchanged. Two CRC-consistent synthetic candidates both observed; scorer alone knows exactly one true SHA; second candidate short-EOF is C partial / A unattributed.
- Current B #71 / C #72 / D #73 next independent research branches and bounded P1 Issue notes in [TEAM_DISPATCH](TEAM_DISPATCH.md). R0-R3 fully gated **39%** weighted roadmap; R4-R7 partial, R8-R10 pending. No real IMG/card access and no actual original recovery verification; local 31GB master IMG approval gate NOT APPROVED.


## A R7 multi-seed BCD shared-source quota and next dispatch — 2026-11-12 JST

- B [#118](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/118) research_only, C [#116](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/116) test-only experimental/default OFF, D [#117](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/117) research_only, all reviewed by A and merged after exact-head Windows PS5.1/privacy CI SUCCESS. B healthy vs corrupt zero-size remains observationally ambiguous, C gains only selected invented +2-byte phase candidate with extra work, D sampling schedules exchange one remote FAT miss for another.
- A [#119](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/119) merged `6a2049d18a05c53a57987a8efe3ee9982a1a093b`. 3 seeds × M00/M01/M02/P02 = **12 invented 2MiB cases**, B/C/D share exactly one source-read budget of 120000 actual returned bytes per case; independent read-event union reconciled: 950208 actual, 786432 unique-across-each-source summed, 163776 duplicates, 507 calls, 12/12 deliberately excessive requests refused without physical reads. No original recovery/identity claims. New D P8 standalone in A central runner. [PR-head Windows+privacy #43211154908](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43211154908) **SUCCESS 34/34**; [post-merge main #43211580567](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43211580567) **SUCCESS 34/34**.
- Fresh independent B #71/C #72/D #73 research branches and bounded P1 assignments created from A-reviewed 6a2049d1, current details in [TEAM_DISPATCH](TEAM_DISPATCH.md). Next A research needs standards-shaped volumes, currently only tiny FAT32-like multi-seed tested. R0–R3 full-gate weighted **39%**, R4–R7 partial; R8–R10 not finished. Original sole 31GB IMG/physical microSD excluded from all access; real-image gate NOT APPROVED.

## Team A R7 standards-shaped shared-source gate — 2026-11-12 JST

A accepted exact-head Windows/Privacy-green C [#121](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/121) as **test-only opt-in 560B adopt_experimental** and D [#122](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/122) as **research_only, rotating schedule NOT promoted due worse measured FN count**. Formal reviews and R0/R1 evidence remain on the PRs. B #71 is still researching LFN/parent edges with NO submitted PR at A start; B branch and Issue assignment are preserved.

A [PR #123](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/123) merged `99562004d9aeee74d059c9ace85c10a89f79449d`. Added `tests/Test-A3DStandardSharedSourceGate.ps1` and `docs/R7_STANDARD_SHARED_METER.md`: actual B geometry/root, C image-prefix carving and D FAT observed IoEvidence on same A-owned nonwritable stream over five standards-shaped artificial FAT32 inputs (~32.5/64.5MiB), two sector-per-cluster configurations and one invented FAT2-only link mutation. Each has a hard A source cap of **120000 actual returned bytes**, no per-module reset. Independently reconstructed numeric physical read-span unions match A meter; **344368 total actual bytes, 332544 sum of independent per-source unique bytes, 11824 repeated bytes, 136 Read calls**; 5/5 deliberately oversized requests fail closed with zero additional physical read/event. External synthetic scorer verifies 3 original file SHA-256 per case **15/15**, but **C current bounded 64KiB image-prefix scan detects 0/15 candidate files**; because generated standards-shaped FAT32's data area starts past that scan, do NOT infer file absence or original recovery. No source input changed, no mirror winner or repair.

[Final exact PR-head Windows PS5.1 + privacy CI #43223172758](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43223172758) **SUCCESS 35/35 isolated artificial scripts** and [post-merge main #43223693030](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43223693030) **SUCCESS 35/35**. This qualifies one narrow A R7 standards-shaped source/accounting P1, NOT full R7 pass. C #72 next data-region P1 and D #73 actual observed FAT coverage next P1 on fresh A-reviewed main; B #71 previous LFN task unchanged. See [live dispatch](TEAM_DISPATCH.md).

Official weighted engineering roadmap remains **R0–R3 fully accepted = 39%**. R4–R7 still partial and R8 recovery export blocked. This is **not** a real-world data restoration rate. User's sole 31GB master IMG and physical microSD have NOT been accessed/read/hashed/copied/scanned/written/repaired/extracted/uploaded; local real-media gate stays **NOT APPROVED**.
