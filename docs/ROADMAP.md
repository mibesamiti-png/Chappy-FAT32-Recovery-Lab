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

## Next parallel round (A-issued 2026-11-11)

| Team | Next deliverable | Assigned Issue | Status |
| --- | --- | --- | --- |
| B R2 | Confidence-aware directory hierarchy candidate reconstruction, reduced false positives, synthetic adversarial tests | [#8](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/8) | **assigned, open** |
| C R2 | Fix cumulative ZIP/G-code probe read budgets and privacy/path issues before A merges Draft PR #5 | [#3](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/3) | **review changes requested** |
| D R3 | Bounded FAT1/FAT2 regional comparison, EB-58 distribution and chain anomaly statistics | [#9](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/9) | **assigned, open** |
| A | Complete C safety review/integration and isolated read-only local runner | [#1](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/1) | **in progress** |

These are planning milestones, not actual recovery percentages. Do not test or change the real IMG inside public CI.

 
## Second integration round checkpoint — 2026-11-11

| Team / stage | Latest outcome | Remaining |
| --- | --- | --- |
| B R2 P1 | [PR #10 merged](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/10), lower directory false-positive risk, synthetic CI PASS | Issue #8 hierarchy edge inference, ambiguity/cycle tests, no true paths claimed |
| C | [PR #5 Draft](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/5), cumulative I/O / probe budget and synthetic stress cases CI PASS | P1 path/device/export guards, strict JSON reason-code allowlist, structural-only integrity clarity |
| D R3 P1 | [PR #11 merged](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/11), bounded mirror windows, synthetic 31/31 PASS | Issue #9 EB-58 distribution + chain anomalies + metadata conflict summaries |
| A | [PR #12 merged](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/12), isolated synthetic runner, [main CI PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42972326019) | Full combined local read-only diagnosis runner with explicit opt-in and safety review |

**Current planning pulse:** B/D/A delivered 3/4 scoped current-round increments; C is unfinished. Overall recovery project and actual recovery percentage cannot be inferred from this.
