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


## Third integration checkpoint — 2026-11-11

| Workstream | Completed and verified | Next bounded task |
| --- | --- | --- |
| B R2 | PR #14 merged: candidate-only hierarchy nodes/edges, cycle and ambiguity evidence; synthetic Windows CI passed | Issue #8: LFN adversarial and false-positive A/B baseline |
| C | PR #5 draft: synthetic carving+I/O budget/report sanitization pass | Export path/physical-device/reparse defense; ZIP structural-only semantics; final A review |
| D R3 | PR #13 merged: read-only EB58 repeated-pattern mapping and FAT/boot offset hypotheses; synthetic CI passed | Issue #9: bounded cluster chain anomaly statistics |
| A | PR #15 merged: opt-in, no-write/no-extraction, numeric-only read-only preflight; 7-suite synthetic Windows CI passed | Review `docs/LOCAL_READONLY_APPROVAL_GATE.md`, further malformed BPB/alias negative tests, later explicit local-only real IMG trial |

**Safety state:** synthetic and local-logic code only; real user master IMG never read by this workflow and **not approved** for diagnostic execution yet. No recovered file count, original filename correctness, or data recovery percentage has been verified.

 
## Fourth integration checkpoint (2026-11-11) — scoped engineering progress, not recovery %

| Role | Newly accepted artifact | Next separately bounded work |
| --- | --- | --- |
| B | [PR #17 merged](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/17); R2 Issue #8 closed | [R3 Issue #19](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/19) synthetic confidence calibration/scan bounds |
| C | [Draft PR #5](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/5); opt-in output safety and free-text report sanitization CI PASS | ZIP/3MF structural-only confidence vs CRC/content tests; A re-review before merge |
| D | [PR #16 merged](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/16) bounded FAT chain terminals, Windows D 165/165 synthetic assertions PASS | [Issue #9](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/9) D-owned read-only numeric directory/FAT consistency |
| A | [PR #18 merged](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/18), root-chain aggregate in experimental local preflight and 8-suite central CI, [main PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42979036878) | Strengthen BPB/Windows-alias safety before any real master IMG trial |

**Do not interpret passing synthetic assertions, calculated candidate counts or this roadmap as actual recovered-file percentages.** The user's 31GB master IMG has not been tested with the new integration runner.


## Latest A checkpoint — synthetic damage evaluation R1 (2026-11-11)

| Track | Latest completed delivery | Current remaining gate |
| --- | --- | --- |
| B | [PR #20](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/20) merged; synthetic directory 23-case confidence QA | New [Issue #24](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/24) noncontiguous/orphaned directory tests |
| C | [PR #5](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/5) merged **experimental only**; bounded ZIP/3MF/G-code candidate scanning, default-off export | [Issue #23](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/23) fixes ZIP-after-Gcode ordering bug (synthetic Windows CI reproducible) |
| D | [PR #21](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/21) merged; 211/211 artificial FAT+directory consistency assertions PASS | New [Issue #25](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/25) BPB/MBR/backup-VBR bounded trust checks |
| A | Three module families in main; latest previous main synthetic Windows CI [42985195170](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42985195170) PASS; new [Draft PR #22](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/22) produces 7-case artificial damage corpus | **PR #22 CI failing**, correctly identifies C #23 bug; do not lower assertions, re-run after C fix |

**Experimental corpus:** 2MiB FAT32-like research image with two invented contiguous sample files, no real media, no reconstruction of missing bytes. Expected 10/14 original-byte-identical candidate slices across the seven predetermined scenarios is a **target**, not an observed recovery rate. The initial clean-case scan missed a G-code candidate, so the new benchmark cannot be accepted yet. Real IMG and recovery percentage remain unverified.


## Team A quality-gate status — synthetic damage benchmark branch

**Complete and integrated:** [A PR #26](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/26) added D R3-P4 to central Windows PowerShell 5.1 integration CI, now 9 isolated artificial suites; main [CI success](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42987347212).

**In progress, intentionally not merged:** [A Draft PR #22](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/22) tests seven artificial FAT32-like IMG damage scenarios and independently compares known original G-code / 3MF bytes. Current measured artificial result is **6/14 exact candidate slices**, target **10/14**, due to the C candidate scanning order bug [Issue #23](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/23). This is not a real user file recovery rate; do not expand inference beyond the tiny synthetic corpus. C fix -> A review/merge -> re-run A CI -> only then consider merging PR #22.

Future corpus work: correctly formatted full-size synthetic FAT32 volumes, genuine fragmentation and reconstruction, controlled bit rot and metadata/data damage, size-bound performance and byte-for-byte verification. Real IMG remains local-only, read-only and NOT APPROVED for this experimental runner yet.
