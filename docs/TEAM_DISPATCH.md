# Team Dispatch — authoritative live roster

**Read this on every universal bootstrap.** These are **existing, already-assigned** chats; do not overwrite, duplicate or claim their roles from a fresh chat.

| Role | Owner of work | GitHub Issue | Current branch | Module scope | Startup state |
| --- | --- | --- | --- | --- | --- |
| A | Coordinator (this original conversation) | [#1](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/1) | `main` / `integration/*` | integration, QA, runner | active |
| B | Existing Team B chat | [#19](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/19) **R3 OPEN**; [#8](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/8) R2 closed | `feature/b-directory-r3-validation-20261111` | `modules/directory/` | **NEXT: synthetic candidate-confidence calibration and bounded scan stress; Draft PR** |
| C | Existing Team C chat | [#3](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/3); [Draft PR #5](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/5) | `feature/c-carving-r1-20261111` | `modules/carving/` | **A requested P1 bounds/privacy fixes; continue PR #5** |
| D | Existing Team D chat | [#9](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/9) **R3 OPEN**; [PR #16](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/16) merged | `research/d-fat-r3-consistency-20261111` | `modules/fat-analysis/` | **NEXT: R3 read-only directory/FAT numeric consistency summaries; Draft PR** |

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

## Coordination updates

A changes this roster when rounds or branches change. B/C/D must not edit this roster, `AGENTS.md` or shared `docs/STATE.md` concurrently. Suggest changes in their own Issue/PR, A applies after review.

## Known constraints

- Repository is public. **No actual disk IMG, raw data, recovered files, actual filenames or unredacted diagnostics ever in commits, GitHub Issues or PR comments.**
- Windows GitHub Actions currently tests synthetic fixtures only.
- `legacy/Chappy_FAT32_QuickProbe_v0.5.1.ps1` is available; main v0.5 code is still local-only pending safe import.
- No actual recovered-file success has been verified.
