# Team B R4 — B4-03 parent graph conflict / forged-ledger evidence

**Owner:** Team B, Issue [#71](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/71). **Pre-code R0/R1 freeze:** [Issue comment #6853758753](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/71#issuecomment-6853758753). **Base main:** `c52b2b6ef987f211b8a881f6708eeb342d866ee7`. This is a B-owned gate evidence proposal, not A ledger signoff.

## Gap actually addressed

Existing production `DirectoryHierarchy.ps1` flags duplicate same-parent entries, competing parents, conflicting `..` hints, cycles, root references, unobserved child clusters, limits, and missing/duplicate scan coverage; it does not reconstruct paths. However the caller can forge `scanIncomplete`, numeric coverage counters, and `coverageProvenance` intervals. Those fields do **not** authenticate a physical read, yet existing graph behavior can upgrade a structurally corroborated parent candidate to `probable` based on the forged scan-complete report.

**New default-OFF B production switch:** `Get-ChappyDirectoryHierarchyEvidence -NeverPromoteUnattestedParentEdges`. With this option, any `probable` parent edge is kept as a **`partial` candidate**, with `independent_source_attestation_required` evidence. Counter `metrics.unattestedProbableSuppressed` records count. Warning `hierarchy_independent_source_receipt_not_provided` records the suppression. The switch does **not** accept any caller-provided 'attested' bit or token. It performs zero extra Stream.Read calls, never asserts original names or paths, and never upgrades confidence based on its own output.

**Boundary:** default graph behavior is unchanged for compatibility. This opt-in conservative policy is suitable for A's future R7 adapter when A **lacks** independently verified physical source-receipt mapping; only Team A can establish a real receipt trust protocol (B4-04). This code does not fix source forgery in the old default mode and cannot authenticate actual media. Prior full-source positive structural evidence will also be downgraded in strict mode, reducing structural 'probable' recall; do not claim improved reconstruction sensitivity.

## Frozen regression coverage / review matrix

| Existing B source/tests | Real test unit / scope | Baseline observation | Strict mode expected | Trust limitation |
| --- | --- | --- | --- | --- |
| `tests/Test-DirectoryR4HiddenParentIndistinguishability.ps1`, 3 seeds x supported/contradicted remote-hidden parent | 6 **self-forged** complete coverage scan results, original-parent truth supported3/contradicted3 from external scorer | 6 apparent probable edges despite physically returned bounded bytes | 0 probable, **6 retained partial**; `UNKNOWN6` (not TN) | Identical actual positive/zero-offset-and-SHA source traces across each twin, different hidden full-image SHA |
| `tests/Test-DirectoryR4ObservedParentPositiveControl.ps1`, 3 seeds x four cases | 12 physically metered positive/competing/EOF/orphan tests | True observed complete parent in 3 cases structurally probable, competing/EOF uncertain | 3 structural positives deliberately become **UNKNOWN3**, 0 probable; count/relationships remain | No A-issued physical read receipt in B; valid source events alone do not prove original media |
| `tests/Test-DirectoryScanner.ps1` fixed graph fixture | 2 competing edges, 2 duplicate references, three cyclic/self references, one contrary dotdot hint, one unobserved target | Reason-coded candidates; no reconstructed original path | Identical node/edge counts and ordered relation statuses, no verified name/path | Synthetic metadata-only fixture; this subtest doesn't perform physical reads |
| `tests/Test-DirectoryR9CoverageProvenance.ps1` (historical) | 17 artificial numeric coverage hypotheses | R9 TP2 FP1 FN0 TN14, one **known** fabricated-ledger false positive | Strict opt-in blocks high confidence even on forged report | Original R9 metrics remain historical default-OFF comparator, do not overwrite them |

## Cost and safety report

All new B4-03 validations re-use existing 3-seed generated input and its test-side independent returned-byte transcript. Strict graph is **metadata-only and does not re-read any sources**. The existing #131 source suite logs across 12 scans **40038 successful synthetic source-return bytes**, 27750 B-directory-returned bytes with 102 bytes of incomplete early read and 90 read calls. The distinct #136 parent suite logs **15411 successful source-return bytes** and 15360 completed B-directory bytes over 12 scans. Never sum them as one trial/one source. New tests preserve full synthetic SHA before/after and do not leak names.

**Release condition:** final-head Windows PowerShell 5.1 and privacy CI SUCCESS must be inspected before A can sign `B4-03`. Research-only and default-OFF, no unreviewed promotion. Any remaining B4-04 receipt matching or B4-05 versioned envelope acceptance is A-coordinated work, not solved by this opt-in guard. R4 full-stage formal 10% remains unsigned; official overall completed stage progress **39%**.

**Safety:** Never touch original microSD or sole ~31GB master IMG for read/hash/scan/copy/repair/extract/write/upload; approval remains **NOT APPROVED**. Only deterministic generated artificial bytes and readonly B source streams. No third-party FAT/GPL/TSK implementation imported; Microsoft FAT specification, .NET Stream.Read and TSK notes cited in pre-code R0 with code reuse forbidden pending licensing review.
