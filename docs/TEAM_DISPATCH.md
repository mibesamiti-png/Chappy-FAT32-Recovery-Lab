# Team Dispatch — authoritative live roster

**Read this on every universal bootstrap.** These are **existing, already-assigned** chats; do not overwrite, duplicate or claim their roles from a fresh chat.

| Role | Owner of work | GitHub Issue | Current branch | Module scope | Startup state |
| --- | --- | --- | --- | --- | --- |
| A | Coordinator (this original conversation) | [#1](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/1) | `main` / `integration/*` | integration, QA, runner | active |
| B | Existing Team B chat | [#2](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/2) closed; [PR #7](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/7) merged | `feature/b-directory-r1-20261111` (merged) | `modules/directory/` | **R1 complete; await new Issue** |
| C | Existing Team C chat | [#3](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/3); [Draft PR #5](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/5) | `feature/c-carving-r1-20261111` | `modules/carving/` | **A requested P1 bounds/privacy fixes; continue PR #5** |
| D | Existing Team D chat | [#4](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/4) closed; [PR #6](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/6) merged | `research/d-fat-r1` (merged) | `modules/fat-analysis/` | **R1/R2 complete; await new Issue** |

The **authoritative** current task list is in each Issue and any linked Draft PR, not a static checklist in this file. Before starting, inspect the branch and open PRs to avoid reimplementing finished work.

## How identical prompts preserve independent roles

The same short message is pasted into all chats. Each chat **must retain its explicitly assigned A/B/C/D identity from its conversation history**, then load the corresponding row above. It must NOT select a role only based on GitHub Issue status; identical messages do not give a unique identity.

For a completely new chat without a known role, do not change the repository until the user assigns a role once; then the same universal prompt works for every future iteration.

## Integration checkpoint (Team A, 2026-11-11)

- B merged into main from PR #7 at `96d1a785`; do not re-implement its already delivered R1 Issue #2.
- D merged into main from PR #6 at `512ca380`; synthetic memory-only simulation is **not** an actual IMG repair.
- C remains Draft PR #5 at reviewed SHA `48f2e274`; A review comment requests global I/O/probe budget, dense-false-positive stress case, stronger export path controls and report sanitization.
- Combined main Windows synthetic regression (QuickProbe+B+D R1+R2+privacy) passed: [Actions #42968506751](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42968506751).
- B/D on an unqualified "continue" should report their round complete and wait for A's next Issue; do **not** silently invent work. C should address A's PR #5 review first.

## Coordination updates

A changes this roster when rounds or branches change. B/C/D must not edit this roster, `AGENTS.md` or shared `docs/STATE.md` concurrently. Suggest changes in their own Issue/PR, A applies after review.

## Known constraints

- Repository is public. **No actual disk IMG, raw data, recovered files, actual filenames or unredacted diagnostics ever in commits, GitHub Issues or PR comments.**
- Windows GitHub Actions currently tests synthetic fixtures only.
- `legacy/Chappy_FAT32_QuickProbe_v0.5.1.ps1` is available; main v0.5 code is still local-only pending safe import.
- No actual recovered-file success has been verified.
