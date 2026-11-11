# Copy/paste start instructions for parallel ChatGPT teams

The GitHub repository is PUBLIC. Code and synthetic fixtures only: https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab

Every team must read README.md, AGENTS.md, docs/STATE.md and docs/TEAM_PROTOCOL.md first. The user's original 31GB IMG and unredacted data are strictly local; never request or publish them. Only synthetic data in GitHub. No real-image writes, no auto-repair, and no claims of passing Windows tests without actual evidence.

## Team B — send to separate chat

You are Team B, directory metadata specialist. Work on Issue #2 on branch `feature/b-directory-r1`. Implement a PowerShell 5.1 module under `modules/directory/` for bounded FAT-independent directory entry scanning, 8.3 and LFN parsing, checksums, root/subfolder recovery candidates, and metadata-only JSON output. Test only synthetic data and create a DRAFT PR to main. Do not edit C/D code. Record actual tests and residual risks.

## Team C — send to separate chat

You are Team C, file carving and validation specialist. Work on Issue #3 on branch `feature/c-carving-r1`. Implement a PowerShell 5.1 module under `modules/carving/` for bounded streaming G-code and 3MF/ZIP signature detection, EOCD/central-directory validation, and uncertainty classification. Use artificial test files only, no real IMG, no automatic extraction or overwriting. Create a DRAFT PR to main with real test evidence and limitations.

## Team D — send to separate chat

You are Team D, independent FAT forensics specialist. Work on Issue #4 on branch `research/d-fat-r1`. Independently validate FAT32 offsets, BPB calculations, reserved-entry semantics, plausible repeated EB-58 pattern causes, and root chain out-of-range behavior. Research repair proposals but NEVER write to the original/mirror IMG; test only synthetic/disposable data. Keep code under `modules/fat-analysis/`. Create DRAFT PR to main, explicitly separating observations from hypotheses.

## A integration protocol

Team A monitors Issues and draft PRs, reviews safety and tests first, and only merges after gates pass. Keep versions in docs/STATE.md. Reconcile other changes before updating the same file. No direct commits to main by B/C/D.

## Deliverables / acceptance

Each team must report: commit/PR link, changed files, test commands and actual results, safety implications, remaining defects, and progress estimates. Prefer small well-tested PRs to large unverified changes.