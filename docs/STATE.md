# STATE — 2026-11-11

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
