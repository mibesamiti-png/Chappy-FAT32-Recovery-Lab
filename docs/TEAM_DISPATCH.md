# Team Dispatch — authoritative live roster

**Read this on every universal bootstrap.** These are **existing, already-assigned** chats; do not overwrite, duplicate or claim their roles from a fresh chat.

| Role | Owner of work | GitHub Issue | Current branch | Module scope | Startup state |
| --- | --- | --- | --- | --- | --- |
| A | Coordinator (this original conversation) | [#1](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/1) | `main` / `integration/*` | integration, QA, runner | active |
| B | Existing Team B chat | [#8](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/8) **R2 OPEN**; former [#2](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/2) closed | `feature/b-directory-r2-20261111` | `modules/directory/` | **ACTIVE: R2 hierarchy/false-positive reduction; draft PR** |
| C | Existing Team C chat | [#3](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/3); [Draft PR #5](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/5) | `feature/c-carving-r1-20261111` | `modules/carving/` | **A requested P1 bounds/privacy fixes; continue PR #5** |
| D | Existing Team D chat | [#9](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/9) **R3 OPEN**; former [#4](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/4) closed | `research/d-fat-r3-20261111` | `modules/fat-analysis/` | **ACTIVE: R3 FAT mirror/pattern corruption diagnostics; draft PR** |

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

## Coordination updates

A changes this roster when rounds or branches change. B/C/D must not edit this roster, `AGENTS.md` or shared `docs/STATE.md` concurrently. Suggest changes in their own Issue/PR, A applies after review.

## Known constraints

- Repository is public. **No actual disk IMG, raw data, recovered files, actual filenames or unredacted diagnostics ever in commits, GitHub Issues or PR comments.**
- Windows GitHub Actions currently tests synthetic fixtures only.
- `legacy/Chappy_FAT32_QuickProbe_v0.5.1.ps1` is available; main v0.5 code is still local-only pending safe import.
- No actual recovered-file success has been verified.
