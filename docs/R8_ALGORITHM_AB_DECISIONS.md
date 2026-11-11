# Team A R8 / C R6 research adoption decisions — 2026-11-11

**Scope:** decisions by Team A for three reviewed experimental contributions on completely artificial FAT32-like data. This document does not authorize access to the user's physical microSD or unique ~31GB master IMG. The original-image local read-only gate remains **NOT APPROVED**.

## Mandatory final-head gates

| Team | PR and exact final reviewed HEAD | Native Windows PS5.1 artificial CI | Privacy/safety CI | A decision |
| --- | --- | --- | --- | --- |
| B R8 | [#56](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/56), `c395d6f119ebe0dde7366178883fce17d06d1e8e` | [PASS 43038770909](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43038770909) | [PASS 43038770737](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43038770737) | **adopt_experimental**, opt-in, default OFF |
| C R6 | [#58](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/58), `3440275ef505d0c8cae3bd37902c31e70c17c4b2` | [PASS 43039332977](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43039332977) | [PASS 43039332676](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43039332676) | **research_only**, no production carving API changed |
| D R8 | [#57](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/57), `1f1f8fe8a59fec5c2de9efb9563295047d6af94f` | [PASS 43039542329](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43039542329) | [PASS 43039542356](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43039542356) | **research_only**, standalone default OFF; keep R6 default |

R0 primary-source references and licensing assessments were entered in [B Issue #53](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/53), [C Issue #54](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/54) and [D Issue #55](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/55) before code edits. No upstream GPL/mixed-license source was copied. Algorithm concepts and source-code permissions must remain distinct.

## B R8 — hierarchy coverage: experimental opt-in

New switch `-RequireCompleteClusterCoverageEvidence` conservatively prevents a partial/missing/contradictory *numeric* scanner report from promoting artificial parent-child edges to probable. No new source reads, writes, FAT traversal, reconstructed real paths or user-name exposure. The scanner's `scanIncomplete=false` alone is no longer sufficient **when the opt-in switch is enabled**.

On 14 chosen artificial structural-confidence scenarios with independent limited truth labels:

| Synthetic A/B | TP | FP | FN | TN |
| --- | ---: | ---: | ---: | ---: |
| R7 baseline (conflict detection opt-in) | 2 | 8 | 0 | 4 |
| R8 plus numeric coverage guard opt-in | 2 | **1** | 0 | **11** |

**Known blocking caveat for stronger promotion:** a fabricated report can claim full byte count/geometry while omitting true contradictions, giving a residual false probable edge (FP1). Scanner byte count is **not a proof of distinct cluster coverage, completeness, authentic filesystem metadata or genuine parent paths**. Keep the guard optional; follow up with independent coverage provenance rather than a 'verified' label.

## C R6 — synthetic-only non-oracle two-fragment tail discovery: research_only

A synthetic test helper checks a uniform 512-byte-aligned tail grid, instead of receiving the correct tail-offset list. At most 256 offset probes and eight candidate pairs, limited source reads/validation bytes. It then reuses an existing bounded in-memory format validator. **No production scanner or export change**.

On five selected artificial G-code/3MF fragment scenarios: 1,147 sample-grid positions, six plausible validated pairs, TP4 FP2 FN1 with two unique, two ambiguous, one missing true tail beyond scan range. Four of five artificial originals had one byte-identical **possible** pair, not four reliable final restorations. The algorithm still receives artificially privileged **first offset, expected format and second slice size**. Its 195,343 actual source bytes over five cases versus 458,872 baseline source bytes do not demonstrate fair general performance: the signature-probe work differs. Two false-valid combinations mean no general-purpose original-file integrity or autonomous restoration is established. Keep research-only, test-helper scope.

## D R8 — additive root-cycle plus distant FAT anomaly evidence: research_only

The independently callable module reserves 16 FAT entries / 64 bytes for an R6 small root-chain subpass and 24 entries / 96 bytes for an R7 stratified subpass, normally 40 entries / 160 bytes combined, with **hard 40 entry / 256 byte request limits**. It rejects writable source streams; repeated reads are charged again. Its output explicitly refuses to select a FAT/geometry or a repair action, leaves unknown entries unknown, and does not claim the original file is healthy. No new default invocation.

| Eight selected artificial FAT cases | TP | FP | FN | TN | Total actually read |
| --- | ---: | ---: | ---: | ---: | ---: |
| R6 root-focused baseline | 3 | 0 | 3 | 2 | 1,280 B |
| R7 stratified research | 5 | 0 | 1 | 2 | **768 B** |
| R8 additive research | **6** | 0 | **0** | 2 | 1,280 B |

R8 retained detection of a two-link root cycle even when both FAT mirrors were identically corrupt while observing distant synthetic bad/out-of-range markers. **This is a hand-selected eight-case benchmark and not a recovery probability.** R8 uses more source reads than R7 and is more computationally expensive. Overlapping windows reduce *unique coverage*, and several longer/fragmented chains remain untested. Keep existing R6 unmodified as default; broaden tests before further consideration.

## A central integration gate

The new A integration branch adds `modules/fat-analysis/tests/Run-TeamD-R8-AdditiveAB.Tests.ps1` to `runner/Invoke-ChappySyntheticRegression.ps1`, increasing independent Windows PowerShell 5.1 **synthetic script suites from 15 to 16**. B R8 and C R6 new tests are already called by their existing dedicated B and C script entries. This change does not run an actual IMG, export content, alter the format scanner or select a repair.

**Only mark this gate passed after Windows CI confirms the exact final A PR HEAD and post-merge main HEAD.** Expected: full synthetic runner/Privacy CI, source read-only invariance, no real data. Passing a suite is not proof of real recovery.

## Remaining safety gates

- [ ] Independent fully formatted FAT32 artificial volumes with true directory and file fragmentation, not just FAT32-*like* byte fixtures.
- [ ] Stronger non-spoofable scan-coverage evidence and adversarial false-parent tests.
- [ ] C fragment discovery with fewer artificial privileged hints, multiple plausible tails, and bounded realistic source budgets.
- [ ] D root-cycle vs remote-anomaly larger A/B and honest duplicate-read/unique coverage under identical *actual* work.
- [ ] Hardening of Windows alias/reparse path and geometry trust on artificial files before a separately reviewed local-only real-IMG command.
- [ ] Explicit Team A approval for one exact revision if/when all conditions in `docs/LOCAL_READONLY_APPROVAL_GATE.md` are satisfied.

No real recovered file, user file checksum, authentic parent path, or real success rate has been verified.
