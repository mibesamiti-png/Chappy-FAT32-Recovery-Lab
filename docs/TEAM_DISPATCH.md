# Team Dispatch — authoritative live roster

**Read this on every universal bootstrap.** These are **existing, already-assigned** chats; do not overwrite, duplicate or claim their roles from a fresh chat.

| Role | Owner of work | GitHub Issue | Current branch | Module scope | Startup state |
| --- | --- | --- | --- | --- | --- |
| A | Coordinator (this original conversation) | [#1](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/1) | `main` / `integration/*` | integration, QA, runner | active |
| B | Existing Team B chat | [#38](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/38) **R6 OPEN**; [#31](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/31) R5 closed | `feature/b-hierarchy-confidence-r6-20261111` | `modules/directory/` | **NEXT: propagate weak candidate confidence through hierarchy evidence; Draft PR** |
| C | Existing Team C chat | [#39](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/39) **R4 OPEN**; [#32](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/32) R3 closed | `feature/c-fragment-candidates-r4-20261111` | `modules/carving/` | **NEXT: synthetic fragmented G-code/3MF candidate and incomplete-evidence QA; Draft PR** |
| D | Existing Team D chat | [#40](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/40) **R6 OPEN**; [#33](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/33) R5 closed | `research/d-mirror-vbr-crosscheck-r6-20261111` | `modules/fat-analysis/` | **NEXT: bounded VBR hypothesis/FAT mirror cross-evidence without choosing repair; Draft PR** |

The **authoritative** current task list is in each Issue and any linked Draft PR, not a static checklist in this file. Before starting, inspect the branch and open PRs to avoid reimplementing finished work.

## How identical prompts preserve independent roles

The same short message is pasted into all chats. Each chat **must retain its explicitly assigned A/B/C/D identity from its conversation history**, then load the corresponding row above. It must NOT select a role only based on GitHub Issue status; identical messages do not give a unique identity.

For a completely new chat without a known role, do not change the repository until the user assigns a role once; then the same universal prompt works for every future iteration.

## Integration checkpoint (Team A, 2026-11-11)

- B merged into main from PR #7 at `96d1a785`; do not re-implement its already delivered R1 Issue #2.
- D merged into main from PR #6 at `512ca380`; synthetic memory-only simulation is **not** an actual IMG repair.
- C remains Draft PR #5 at reviewed SHA `48f2e274`; A review comment requests global I/O/probe budget, dense-false-positive stress case, stronger export path controls and report sanitization.
- Combined main Windows synthetic regression (QuickProbe+B+D R1+R2+privacy) passed: [Actions #42968506751](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42968506751).
- Initial R1 B/D milestones are complete, but **A has now assigned new independent rounds**. B should continue Issue #8; D should continue Issue #9; C should address A's PR #5 review first.

## Active new assignments from Team A (2026-11-11, after initial integration)

- **B R2:** [Issue #8](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/8), branch `feature/b-directory-r2-20261111`, based on `main` HEAD `c7ff118acf9f667aef45cdc2b784269f666d174c` at creation. Improve metadata hierarchy candidate evidence, false-positive rejection, malformed LFN tests; no file extraction or edits to D/C.
- **D R3:** [Issue #9](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/9), branch `research/d-fat-r3-20261111`, same main baseline. Quantify FAT mirror mismatches, EB-58 range distribution, FAT-chain anomaly density with strictly bounded read-only testing; no patch writer or edits to B/C.
- **C remains on existing [Issue #3](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/3) / [Draft PR #5](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/5)**; do not create a duplicate C branch or Issue.
- Use the **identical existing universal bootstrap prompt** in each existing team chat; the role persists from its chat. On every continuation, read the **current dispatch** before the older static default table in the universal instruction. B and D may begin their new assigned work immediately.
- No synthetic code in GitHub may access actual user data, original microSD or 31GB master IMG. No actual recovery has been verified.

## A second integration checkpoint (Team A — 2026-11-11)

- **B R2 P1**: [PR #10](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/10) merged (`00a1bba6`): guarded dot/dotdot pair, reduced one-entry false positives, structured rejection reasons; Issue #8 remains OPEN for confidence-aware hierarchy reconstruction.
- **D R3 P1**: [PR #11](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/11) merged (`98cafeb4`): bounded FAT1/FAT2 read-only regional comparison; Issue #9 remains OPEN for EB-58 mapping, chain anomaly density and directory/FAT conflict summaries.
- **A integrated synthetic regression**: [PR #12](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/12) merged (`7094e780`); [post-merge Windows CI PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42972326019). This only tests artificial data and does not validate any real IMG.
- **C**: [Draft PR #5](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/5) remains open at reviewed head `6b4b3ab`. Global read/probe budgets added and synthetic CI passed; A still requires secure export destination / device path handling, strict report string sanitization, and explicit structural-only ZIP integrity semantics.
- B next branch `feature/b-directory-r2-hierarchy-20261111`, D next branch `research/d-fat-r3-eb58-20261111` created from A-integrated `main` HEAD `7094e7809239b1efc721b2d05db9507b4c256f38`. Branches may fall behind later doc commits; fetch latest main and reconcile before work.
- Do **not** open a second PR for completed B R2 P1 or D R3 P1. Continue the still-open Issues #8 and #9 with one scoped task at a time. C continues same Draft PR #5.
- No actual 31GB IMG scans, repair, recovery validation or public private-data uploads have occurred.

## Team A current integration checkpoint (2026-11-11, most recent)

- **B hierarchy** [PR #14](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/14) was merged (squash `5077d38f`); it adds candidate-only directory parent-child evidence and contradictory/cyclic link classification. Issue #8 remains open.
- **D EB58** [PR #13](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/13) was merged (squash `9fd8c9aa`); it adds bounded read-only `EB 58` mapping and possible FAT/boot offset hypotheses. Issue #9 remains open.
- **A local read-only preflight** [PR #15](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/15) was merged (squash `5fbb7be4`): explicit opt-in regular local IMG read-only stream, numerical B/D aggregate summary and **zero output files/repairs/extraction**. Both branch and [post-merge Windows synthetic CI](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42975361336) passed. **NOT AUTHORIZED against the actual 31GB IMG** until `docs/LOCAL_READONLY_APPROVAL_GATE.md` is fulfilled and reviewed.
- **C carving** [Draft PR #5](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/5) remains unmerged, last reviewed `03786895` with synthetic CI PASS. C fixed bounded reads and report free-text handling, but A still requires safe export path/device/reparse guard and ZIP structural-only semantics before merging.
- **Next B task:** within existing [Issue #8](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/8), add adversarial malformed LFN ordering/checksum/surrogate/cluster boundary tests, fixed-code evidence and reproducible A/B false-positive synthetic baseline. Avoid changing hierarchy semantics without regression evidence. New branch `feature/b-directory-r2-lfn-qa-20261111`.
- **Next D task:** within existing [Issue #9](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/9), implement strict read-only bounded FAT chain anomaly counts (cycle/free/EOC/reserved/out-of-range) and incomplete coverage reporting, synthetic-only tests. New branch `research/d-fat-r3-chain-stats-20261111`.
- Continue using the identical universal bootstrap text. Read this newest checkpoint and the active rows first; older assignments retained below are history. Never run real IMG experiments in public CI, upload real reports, or make source writes.

## Latest A integration checkpoint — 2026-11-11, fourth round

- **B PR #17** merged (`232056a1`): LFN malformed ordinal/terminator/surrogate rejection and synthetic A/B false-positive matrix, final Windows synthetic/Privacy CI PASS. **Issue #8 closed** as R2 milestone. B next starts **new Issue #19** on `feature/b-directory-r3-validation-20261111` (synthetic calibration, budget/geometry regression, no FAT path or carving).
- **D PR #16** merged (`e9fca567`): readonly, cumulative-budget FAT chain anomaly classification for caller-selected clusters. Windows D R1/R2/R3-P1..P3 + Privacy CI PASS. D continues **Issue #9** on `research/d-fat-r3-consistency-20261111`, numeric directory/FAT consistency summaries with no B module imports.
- **A PR #18** merged (`6ac7e8a4`): central CI includes D chain stats and local experimental read-only numeric preflight samples root FAT chain from both copies. [Post-merge Windows CI PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42979036878).
- **C PR #5** remains Draft at last reviewed `467f0534`, synthetic C/Privacy CI PASS. Opt-in path safeguards and report sanitization improved. **Remaining C P1:** mark ZIP/3MF structural-only validation explicitly in candidate and report semantics, add CRC-skipped and mismatch tests. No actual source-file recovery claims and **no real IMG extraction approval**.
- A local real-master IMG trial **NOT AUTHORIZED**. Source microSD/master IMG never modified or scanned by CI; `docs/LOCAL_READONLY_APPROVAL_GATE.md` remains mandatory. All new developer work stays synthetic-only.
- The newest B/D Issue and branch rows above supersede historic assignments elsewhere in this document. Use the same universal bootstrap prompt, keep each chat's pre-existing role.

## Team A synthetic-damage benchmark dispatch — 2026-11-11 (latest)

- B R3 artificial-confidence QA [PR #20](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/20) merged (`6d147814`), R3 Issue #19 closed. B R4 is **Issue #24**, `feature/b-directory-r4-fragmented-qa-20261111`: non-contiguous/orphaned metadata candidate stress tests with known artificial ground truth, no C/D overlap.
- D R3 final directory/FAT consistency [PR #21](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/21) merged (`0e825f82`); Issue #9 closed after all P1..P4. D R4 is **Issue #25**, `research/d-fat-r4-geometry-guards-20261111`: artificial malformed BPB/MBR/backup VBR/FSInfo plausibility guards; does NOT authorize real IMG scanning.
- C initial carving [PR #5](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/5) merged (`110ebbda`) as **experimental only**. Opt-in extraction remains disabled by default; real IMG extraction is forbidden pending separate A safety approval.
- Team A **Draft [PR #22](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/22)** creates a deterministic 2MiB *FAT32-like* artificial IMG with G-code and 3MF and seven corruption scenarios. The initial Windows CI is **RED**, correctly exposing a previously undetected C scanning bug: later ZIP at offset 58880 causes earlier G-code at 58368 to be skipped. Reproduced in [run 42986062061](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42986062061). Do NOT lower test assertions merely to make CI green.
- C's **new Issue #23** and `feature/c-carving-order-r2-20261111` are dedicated to fixing this overlap/order bug. C's new PR must pass its synthetic CI; A then re-verifies PR #22. B/C/D each continue using identical universal bootstrap messages, retaining existing chat roles.
- **A central consistency quality gate** [PR #26](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/26) merged (`7b03a755`): ninth isolated synthetic PowerShell 5.1 suite now includes D R3-P4 directory/FAT consistency. [Post-merge main CI PASS run 42987347212](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42987347212). This is independent from blocked A Draft PR #22; no real IMG accessed.
- All B/C/D new branches were created from `main` at `110ebbdaa29045cda7935061308f85c70ca3692f`. Main baseline synthetic Windows CI PASS [run 42985195170](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42985195170).
- **Never run against or modify original microSD / 31GB master IMG, upload real data, or claim actual recovered-file correctness.** The A real-IMG local safety gate remains explicitly NOT APPROVED.

## A fifth integration checkpoint — 2026-11-11 (newest)

- **BCD accepted + merged:** [B PR #27](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/27) (`1f5144cc`, synthetic discontiguous/orphan candidate QA); [C PR #29](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/29) (`4ff0f1d3`, fix source-offset-ordered ZIP/G-code scanning); [D PR #28](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/28) (`b0da9141`, MBR/BPB/backup VBR/FSInfo bounded read-only evidence). All three final-head Windows + Privacy CI checks PASS.
- **A benchmark regression fixed and merged:** [A PR #22](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/22) (`b6fa5438`). 7 entirely artificial 2 MiB FAT32-*like* damaged/clean IMG cases, 14 invented file-instances; **expected 10/14 original byte-identical candidate extents and observed 10/14 (zero mismatches)** on [exact-head Windows CI 42990769921](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42990769921). C's earlier real code-level missing-G-code regression was fixed; no intact source bytes are inferred from ZIP structural checks. This is **NOT actual file recovery rate**.
- **A central quality gate:** [PR #30](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/30) (`481878b2`) adds C carving suite and D R4 geometry suite to existing 10 synthetic entry scripts. **12/12 isolated Windows PowerShell 5.1 synthetic suites PASS** on [main CI 42991261004](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42991261004).
- Completed B [Issue #24](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/24), C [Issue #23](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/23) and D [Issue #25](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/25) **closed**. Next independent tasks: **B [#31](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/31)** fake-directory false-positive precision; **C [#32](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/32)** strictly capped DEFLATE CRC validation; **D [#33](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/33)** primary/backup VBR disagreement. These new B/C/D branches were created from main `481878b2420f6b3852f16681ca8c6565813b004c`; refresh latest main before any edit.
- **Safety gates unchanged:** actual microSD and unique 31GB master IMG have NEVER been read/written by public CI or this agent; real-image use of experimental preflight and real extraction remain **NOT APPROVED**. No verified recovered files, no actual recovery percentage. Only artificial specimens in GitHub and CI. Use the identical bootstrap in existing role-assigned B/C/D chats.

## Latest Team A integration checkpoint — 2026-11-11 18:xx JST (R5/R3 completed)

- Reviewed exact-head B [PR #34](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/34) and merged as `cf6eed98`: two-entry+end-marker non-root weak containers now retain candidates at `partial` evidence confidence, not automatically discarded or elevated to recovered paths. Chosen 32 artificial truth cases retain TP13/FP8/FN0/TN11; probable-only TP8/FP0 but five real-in-fixture orphan candidates are partial. These fixture results are NOT real-world precision/recall.
- Reviewed exact-head D [PR #35](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/35) and merged as `01a3001a`: read-only MBR-anchored primary and primary-declared backup VBR candidate disagreement with max 2048 byte read cap. Always `selectedCandidate=null`; no authentic geometry or repair claims. D synthetic 356/356 and privacy exact-head CI PASS.
- Reviewed exact-head C [PR #36](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/36) and merged as `6c78664b`: default-OFF opt-in small DEFLATE CRC checks with 32KiB compressed/64KiB expanded, 16 attempts global cap, fixed redacted evidence and no source write. This is synthetic-only; .NET inflation call is not forcibly interruptible mid-call, and original file integrity remains unverified.
- **A integration** [PR #37](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/37) merged `b19f45ac`: central Windows PowerShell 5.1 synthetic runner now **13 isolated suites**, including D R5; existing B R5 and C R3 covered by their standalone entries. [Exact-head PR CI PASS #42997711549](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42997711549), [postmerge main CI PASS #42997918561](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42997918561). A seven-case artificial benchmark still expected/observed 10/14 byte-identical candidate slices, NOT actual recovery.
- Previous B [#31](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/31), C [#32](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/32), D [#33](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/33) completed/closed. **New B #38** hierarchy evidence confidence, **C #39** fragmented candidate/incomplete QA, **D #40** FAT mirror/VBR cross-evidence. Branches created from integrated `main` `b19f45ac130634fb86aa0eb7ac514cecd089afe0`; refresh latest before edits.
- **Safety:** only artificial data in public repo/CI. Unique 31GB master IMG and actual microSD never accessed/written by this integration; real IMG run/extraction still NOT APPROVED in `docs/LOCAL_READONLY_APPROVAL_GATE.md`. Do not claim file recoveries or real success rate. Use unchanged common bootstrap in each pre-assigned B/C/D chat.

## Coordination updates

A changes this roster when rounds or branches change. B/C/D must not edit this roster, `AGENTS.md` or shared `docs/STATE.md` concurrently. Suggest changes in their own Issue/PR, A applies after review.

## Known constraints

- Repository is public. **No actual disk IMG, raw data, recovered files, actual filenames or unredacted diagnostics ever in commits, GitHub Issues or PR comments.**
- Windows GitHub Actions currently tests synthetic fixtures only.
- `legacy/Chappy_FAT32_QuickProbe_v0.5.1.ps1` is available; main v0.5 code is still local-only pending safe import.
- No actual recovered-file success has been verified.
