# Recovery Lab roadmap (as of 2026-11-11)

**Important:** Development progress percentages are planning estimates, **not recovered-data percentages** or guarantees. Actual recovery rate unknown until real files are recovered and verified.

| Stage | Deliverable | State |
| --- | --- | --- |
| 0 | Local raw image backup, no writes to source | Image exists locally; copy integrity not independently proven |
| 1 | Read-only FAT32 geometry and QuickProbe | Prototype; synthetic Windows tests passed |
| 2 | Independent FAT anomaly diagnosis (D) | **R1 merged via PR #6**; synthetic 25/25 Windows tests passed |
| 3 | FAT-independent directory candidates (B) | **R1 merged via PR #7**; synthetic 22/22 Windows tests passed |
| 4 | G-code / 3MF content carving (C) | **Draft PR #5, CI passed; A blocked merge pending global I/O bounds and privacy hardening** |
| 5 | A integration runner + privacy gate | **Combined Windows CI QuickProbe+B+D R1/R2 PASS**; standalone local runner pending |
| 6 | Controlled local validation against master IMG | Pending; do not run unreveiwed code |
| 7 | Restore candidates into separate output folder | Pending |
| 8 | Optional repair-plan research on disposable copies | **D synthetic in-memory only simulation merged**; disk/work-copy repair not authorized |

## Current priority

B and D delivered their assigned initial modules and A merged them. C must address A's review on PR #5 (global byte/probe budget, adversarial signature density, output path and report sanitization). A maintains combined synthetic CI and designs local-only gated verification of the original IMG. No real IMG scan with these new modules yet.

Current baseline v0.5 remains a **legacy experiment**, not approved for recovery/repair against user data. **A integration round: 2 of 3 B/C/D PRs merged; C under review.** QuickProbe v0.5.1 is available as read-only reference.

## Success criteria

- CI green for synthetic valid and malformed images
- Modules terminate on malformed input and remain bounded
- No source writes and no recovery file overwrite
- Sensitive filenames/report contents never reach public repository
- Actual real-image tests conducted locally only after code review, and their sanitized summary is recorded
- Every claim distinguishes test evidence from hypothesis.