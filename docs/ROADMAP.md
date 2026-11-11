# Recovery Lab roadmap (as of 2026-11-11)

**Important:** Development progress percentages are planning estimates, **not recovered-data percentages** or guarantees. Actual recovery rate unknown until real files are recovered and verified.

| Stage | Deliverable | State |
| --- | --- | --- |
| 0 | Local raw image backup, no writes to source | Image exists locally; copy integrity not independently proven |
| 1 | Read-only FAT32 geometry and QuickProbe | Prototype; synthetic Windows tests passed |
| 2 | Independent FAT anomaly diagnosis (D) | Assigned; not started |
| 3 | FAT-independent directory candidates (B) | Assigned; not started |
| 4 | G-code / 3MF content carving (C) | Assigned; not started |
| 5 | A integration runner + privacy gate | Privacy gate + QuickProbe synthetic CI passes; integration pending |
| 6 | Controlled local validation against master IMG | Pending; do not run unreveiwed code |
| 7 | Restore candidates into separate output folder | Pending |
| 8 | Optional repair-plan research on disposable copies | Pending; never auto-repair master |

## Current priority

D investigates repeated FAT bytes independently, B explores metadata when FAT fails, C tests bounded signatures, A ensures safety and integration.

Current baseline v0.5 remains a **legacy experiment**, not approved for recovery/repair against user data. QuickProbe v0.5.1 is available as read-only reference.

## Success criteria

- CI green for synthetic valid and malformed images
- Modules terminate on malformed input and remain bounded
- No source writes and no recovery file overwrite
- Sensitive filenames/report contents never reach public repository
- Actual real-image tests conducted locally only after code review, and their sanitized summary is recorded
- Every claim distinguishes test evidence from hypothesis.