# Team D — R6 gate closure audit and D6-02 observable shared-node increment

**Issue:** [#73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73) · **Draft PR:** [#142](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/142) · **Target:** D6-02 (primary). A's [superseding assignment](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6829139395) and [D preregistered row audit](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6849804809). Branch from main `a59be9f85f58081fa964fa028d31eeb3de5ea4ba`. No Work orchestration, only the pre-existing independent Team D chat. R6 formal weight remains **10 percentage points, NOT awarded**. Overall formally gated engineering progress remains **39% (R0–R3 only)**, NOT file recovery.

## R6 gate-ledger five-row audit: D proposals, NOT A-signed PASS

`docs/ABCD_GATE_LEDGER.md` remains A-owned and marks every row `AUDIT_NEEDED` until A confirms. We do not edit or assign PASS here. The statuses below describe Team D's inspected support and remaining evidence, not official stage-credit.

| Row | D assessment (not official) | Observed code/test evidence | Gap before A can close |
| --- | --- | --- | --- |
| **D6-01** | strong existing coverage; audit pending | `modules/fat-analysis/tests/Run-TeamD-P02Evidence.Tests.ps1` M00/M01/M02/X02, synthetic SHA; `Run-TeamD-R6-FixtureChainAB.Tests.ps1` M03/M05 clean/fracture/EOF evidence | A inspect exact current-main test/CI evidence; X02 retained FAT cannot establish intact payload |
| **D6-02** | **PARTIAL, meaningful new guarded capability in #142** | `Fat32ChainStats.psm1` already detects free/reserved/out-of-range/cycle; `Run-TeamD-R6-DualFatAmbiguity.Tests.ps1`, #126/#132/#138 sampled remote unknown; new `Fat32SharedChainEvidence.psm1` and `Run-TeamD-R6-GateSharedChain.Tests.ps1` | A verify complete R2 + standards-sized corpus, actual independent owner proof from B/A not in D; remote unsampled positions stay unknown |
| **D6-03** | PARTIAL; cross-team audit | `Fat32GeometryTrust.psm1`, `Fat32VbrDisagreement.psm1` and A #135 contrasting geometry case | A reconcile primary/backup/numeric alternate geometries under a single source receipt; no true geometry winner |
| **D6-04** | PARTIAL; physical meter validity limited | `Fat32ObservedIoEvidence.psm1`; `Run-TeamD-R6-StandardFatCoverage.Tests.ps1` reports 64/65664 FAT pairs, >99.9% unobserved and short EOF UNKNOWN | A-issued cross-team source-scoped receipts must validate D events; D internal reads alone are not independently authenticated |
| **D6-05** | PARTIAL pending formal contract review | Current read-only bounded D modules; existing `MirrorOnly` / `MirrorAndChain`; fixed-sample retained; #138 adaptive worse, research_only | A verify actual consumer interface, numeric reason-code and malformed-input regression; no unsafe auto-selection or repair |

The official gate ledger has **0 signed-off / 22 rows** as of initialization; the D five-row proposal does not change it. This is *not* a claim that zero capabilities exist. The new module adds evidence toward D6-02, not enough by itself to award the R6 10% stage weight or assert a PASS row.

## Previously missing / why implementation rather than new sampler research

The reviewed `Get-ChappyFatChainAnomalyStats` reports terminal categories for finite chains but **does not return intersections of two fully observed chain-node sets**. A mirror may agree even if both copies contain an identical shared-cluster pointer. Historic M05 was explicitly UNKNOWN to the basic mirror/cycle-only analyzer; whether chains share observed FAT nodes is independently measurable with caller numeric starts, but **file ownership cannot be inferred** without independently grounded directory evidence.

A new production-facing, separately invoked D-only `Get-ChappyFatSharedChainEvidence` was therefore introduced; it does not change existing default scan behavior. It accepts exactly two distinct **untrusted** numeric chain starts and valid-sized non-overlapping FAT1/FAT2 caller geometry, one readable/seekable/strictly nonwritable Stream. It samples up to two FAT copies × two starts × 16 chain steps, with max **1,024 actual returned source bytes** and **256 physical Read attempts** (user-callable caps); each FAT gets a separate fixed return-byte quota. No file handles, raw content, source path, filenames, automatic repair, FAT copy winner or original-identity assertion.

Per-copy evidence includes actual fully observed shared FAT cluster indices/count, finite EOC/free/reserved/bad/out-of-range/cycle/partial terminal reasons. Returned-byte metrics count **actual physical successful source bytes**, unique offsets and repeats. Early 0-byte returns, partial 4-byte entries and exhausted step/byte/call budgets create `partial` outcomes. `scanIncomplete=true` always because a bounded chain sample does not inspect all FAT entries; source and start provenance explicitly remain caller-supplied / non-A-attested. Even when two chains converge on the same observed numeric node, `fileOwner=unknown`, `fatCopyWinner=not_selected`, `originalIdentity=unknown`, `writePermitted=false`.

## Synthetic test observations and scope

Fixture generator: `tests/helpers/New-Chappy3DDamagedFixture.ps1` blob `58fedb62d76f15ebb003e4440d5f9c90feba25c5`, seed 202611; clean FAT32-like 2MiB track and altered M00/M01/M02/M03/M05/X02. External scorer alone holds manifest/expected labels; the module sees only its nonwritable stream and two fixed numeric start hints, clusters 4 and 8. Synthetic source SHA before/after unchanged in all six.

The **scored unit is a numeric shared-chain observation**, not a recovered file, verified owner or original byte identity:

| R2 artificial case | Observed sharing among 2 FAT copies | Interpretation |
| --- | ---: | --- |
| M00 clean | 0 | No shared node in two observed starts, no whole-FAT health claim |
| M01 healthy fragmentation | 0 | Legitimate fragmentation not misclassified |
| M02 FAT1 free-link disagreement | 0 | FAT1 terminates at free, FAT2 EOC; no winner |
| M03 identical-copy cyclic FAT | 0 | Two cycles observed, independently of sharing |
| M05 intentionally convergent FAT chains | **2** | Shared cluster 8 observed in both copies; **file owner UNKNOWN** |
| X02 truncated payload | 0 | No shared FAT node in sampled region; payload/original integrity UNKNOWN |

External scorer-only synthetic shared-node presence: **TP1 FP0 FN0 TN4, UNKNOWN1** (X02 excluded), with no real-file classification. Six independent invocations: **140 actual returned bytes**, **132 summed source-local unique bytes**, **8 repeated bytes**, **35 physical Read calls**. Each source separately capped at 256 returned bytes; totals above sum independent sources, not one global IMG union. In M05 alone, actual/unique **24/16B**, 6 calls. Returned-source evidence cannot establish actual FAT file owners.

Additional 8KiB generated numeric FAT controls demonstrate independent healthy chains, one-copy-only convergence (no copy winner), free/missing and reserved links, out-of-range link150 under max100, common-mode cycle, physical 7-byte early stop with 2-byte chunks, exact small byte cap, max-step and physical Read-call caps, writable source rejection, duplicate starts and overlapping/overflow geometry rejection.

Independent A-approved standards-shaped FAT32 fixture `New-ChappyA3DStandardFixture.ps1`, seed202614 with **65,541 data clusters** (~32.5MiB), was also tested. Its ordinary generated FAT chains gave no sharing. In a scorer-only clone, FAT1/FAT2 cluster4 pointed to cluster8, and the new module observed **one shared cluster per FAT copy**, while keeping ownership UNKNOWN. Positive standard case physical actual/unique **24/16B**, source SHA of both controls unchanged.

Native Windows PowerShell 5.1 **code-head** CI [#43407430038](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43407430038) **SUCCESS; new D6-02 dedicated suite 72/72 PASS** plus prior Team D suites. The initial six-case suite at [#43406960143](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43406960143) was 65/65 PASS. These are not the yet-to-be-tested final report-document commit. Final-head Windows and privacy results must be verified on the exact last PR HEAD and recorded in PR and Issue.

## Residual risks and A decision request

No source-authenticated B directory file-owner proof, no authenticated VBR/FAT winner, no full FAT scan, no validated original recovered-file bytes, and no automatic repair/export. Callers could provide synthetic numeric starts that converge even for legitimate alias chains; report only a potential shared cluster *observation* and preserve UNKNOWN. Remote unobserved faults (e.g. FAT2 entry60000 in #126) remain outside this new helper's observed chains.

**Request A review as a gate-closing functional increment toward D6-02**, not a discretionary sampling research study. A alone may accept/merge and audit 5 R6 rows with actual code/CI/gap evidence; shared ledger and stage-weight remain unchanged until A verifies every original requirement. Real microSD and sole ~31GB master IMG use remains **NOT APPROVED** for reading, hashing, copying, scanning, repairing, writing, extraction or upload. R8 remains blocked.
