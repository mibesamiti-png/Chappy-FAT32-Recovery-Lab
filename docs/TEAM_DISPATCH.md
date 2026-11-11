# Team Dispatch — authoritative live roster

**Read this on every universal bootstrap.** These are **existing, already-assigned** chats; do not overwrite, duplicate or claim their roles from a fresh chat.

| Role | Owner of work | GitHub Issue | Current branch | Module scope | Startup state |
| --- | --- | --- | --- | --- | --- |
| A | Coordinator (this original conversation) | [#1](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/1) | `main` / `integration/*` | integration, QA, runner | active |
| B | Existing Team B chat | [#2](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/2) | `feature/b-directory-r1` | `modules/directory/` | assigned |
| C | Existing Team C chat | [#3](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/3) | `feature/c-carving-r1` | `modules/carving/` | assigned |
| D | Existing Team D chat | [#4](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/4) | `research/d-fat-r1` | `modules/fat-analysis/` | assigned |

The **authoritative** current task list is in each Issue and any linked Draft PR, not a static checklist in this file. Before starting, inspect the branch and open PRs to avoid reimplementing finished work.

## How identical prompts preserve independent roles

The same short message is pasted into all chats. Each chat **must retain its explicitly assigned A/B/C/D identity from its conversation history**, then load the corresponding row above. It must NOT select a role only based on GitHub Issue status; identical messages do not give a unique identity.

For a completely new chat without a known role, do not change the repository until the user assigns a role once; then the same universal prompt works for every future iteration.

## Coordination updates

A changes this roster when rounds or branches change. B/C/D must not edit this roster, `AGENTS.md` or shared `docs/STATE.md` concurrently. Suggest changes in their own Issue/PR, A applies after review.

## Known constraints

- Repository is public. **No actual disk IMG, raw data, recovered files, actual filenames or unredacted diagnostics ever in commits, GitHub Issues or PR comments.**
- Windows GitHub Actions currently tests synthetic fixtures only.
- `legacy/Chappy_FAT32_QuickProbe_v0.5.1.ps1` is available; main v0.5 code is still local-only pending safe import.
- No actual recovered-file success has been verified.
