# Team D D6-02 original FAT anomaly acceptance — fixed sampling, generated sources only

**Canonical:** Issue #73; [D draft PR #158](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/158). A owns review, merging and the ledger. Team D continues in a separate existing ChatGPT conversation, not Work. This test does **not** attempt to open or recover real media.

## R0 / R1 preregistered before code

[Issue #73 R0/R1 freeze](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6858634391). Start-of-task verified main a6aa8c137ccc5561ca23624fcdeee3c65755ecfb. A's latest assignment [comment 6858029660](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6858029660). A-signed D6-01 and D6-05 PASS, D6-02/03/04 PARTIAL at start.

Source references and reuse decision: Microsoft FAT32 File System Specification v1.03 (copyrighted technical standard, facts only); CGSecurity TestDisk (upstream GPL-2.0 source, not copied); Sleuth Kit docs/source (mixed licensing, not copied). Native PS5.1 test logic and generated artificial source observer are independently authored; no external runtime dependency or new FAT sampling algorithm.

Frozen existing unchanged modules:
- Fat32GuardedResult.psm1: explicitly enabled read-only v1 geometry-first guarded fixed MirrorOnly, max 4096 physically returned bytes / 512 source calls. 2048B independent primary-vs-backup VBR preflight plus <=2048B existing fixed FAT observation, 128/65664 physically complete paired FAT entries in these generated sources; full FAT **not** verified.
- Fat32SharedChainEvidence.psm1: existing bounded numeric-only two-hint shared FAT node/terminal reader under max 256 physically returned bytes / 128 Read calls and max 8 links per trace, two FAT copies separately, starts [4,8] fixed **before** scorer labels were chosen; numeric hints are never file owners.
- Fat32PhysicalPairCoverage.psm1: existing D6-04 coverage uses actual returned 4-byte pairs only; remote FAT region untouched => UNKNOWN, not healthy.
- A-generated New-ChappyA3DStandardFixture.ps1: seeds 202617/202618/202619, FAT32 65541 data clusters, sectors/cluster1 or2, 65664 FAT entry slots per copy.

No production D module edited. Only one D-owned synthetic acceptance test and one dedicated D Windows PowerShell5.1 workflow step were added.

## Scoring design and what was actually observed

The test creates ten in-memory standards-shaped artificial FAT32 volumes with carefully assigned fixed chain 4->6->EOC and 8->9->EOC in both copies. The generator seed, injected corruption locations, expected classes and SHA256 live **only in the test-side scorer**; they are not fed to the fixed FAT or shared-chain detectors. The two caller start hints 4 and 8 are **unchanging for every case**, including the remote anomaly, and are not independent proof of genuine original file ownership.

| Scenario | Mirror comparison | Numeric hinted chain observation | Scorer status |
| --- | --- | --- | --- |
| Clean SPC1 | matching sampled entries | EOC, disjoint | Negative for invalid-link and shared-node |
| Healthy fragmented SPC2 | matching sampled entries | EOC, disjoint | Negative, no fragmentation false alarm |
| Only FAT2 loses link4 | 1 paired mismatch observed | FAT2 start4 terminal free | Invalid link positive |
| Both FATs lose link4 | matching mirrors | Both start4 terminal free | Invalid link positive despite matching mirrors |
| Both FATs contain cycle4->6->4 | matching mirrors | Both start4 terminal cycle | Invalid link positive |
| Both FATs contain bad-cluster4 marker | matching mirrors | Both start4 terminal bad_cluster | Invalid link positive |
| Both start8 chains converge into cluster6 | matching mirrors | Both FAT copies observe one shared numeric node | **Numeric shared-node positive**; invalid-link negative; **no file-owner proof** |
| FAT2 link4 points to data cluster70000 | 1 paired mismatch observed | FAT2 terminal out_of_range, never follows target | Invalid link positive |
| Distant FAT2 index60000 changed | matching 128 pairs | Fixed hints do not reach remote index; actual physical source observer confirms not returned | **UNKNOWN abstention**, not a false healthy TN or FN |
| Real source read returns early zero after1100B | FAT phase forbidden by D6-05 | No chain phase allowed | **UNKNOWN abstention**, not a false negative |

**Two separate, independently scored artificial observation units:**
1. *Observed abnormal chain terminal or observed mirror mismatch*: TP 5, FP 0, FN 0, TN 3, UNKNOWN 2, with denominator 8 scored **in-window** cases. These are not recovered files or entire FAT health labels.
2. *Physically observed shared numeric cluster in both copies along two caller-fixed hints*: TP 1, FP 0, FN 0, TN 7, UNKNOWN 2, also 8 scored cases. Convergence does **not** show any original directory entry, actual two distinct file owners or correct owner path; cannot establish that a specific real file is crosslinked.

The planted remote entry60000 is explicitly excluded from both scored denominators because no 4-byte value from that position was physically returned. It is an honest **coverage miss/UNKNOWN**; it is NOT TP, TN or a recovered-file false negative. A competing unobserved corruption could exist anywhere in the other 65536 FAT entry indices. Any apparent mirror agreement is strictly local. Source authenticity and true original-file integrity remain UNKNOWN for every case.

## Actual physical source returns, not requested bytes

The independent source-side D602IndependentMemorySource meters actual successful Stream.Read byte positions, source-local unique/repeated offset union, physical Read attempts, true early zero and separately timed guarded/chain phases. A different wrapper in the D modules meters its internal reads. New test rejects disagreement across wrappers and checks both local quotas plus shared external source cap <=8192 physical returned bytes / <=640 delegated calls across both operations.

**Measured initial native Windows PowerShell5.1 on code-head, prior to this report-only commit:** [CI #43462850671](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43462850671) **SUCCESS, 78/78 acceptance assertions PASS**, other D CI suites PASS.

Across **ten independent generated source invocations**:
- Actually returned physical source bytes **38,228 B**.
- Sum of unique physically returned source offsets *within each source* **28,748 B**.
- Repeated physical bytes across the ten independent source runs **9,480 B**, where overlap within one source counts as repeat, not a new FAT slot.
- Delegated physical Stream.Read calls **299**.
- Guard-phase physically returned bytes **37,964 B**; additional bounded hinted-chain phase **264 B**.
- Each source SHA256 before/after diagnostic reads remained **byte-for-byte unchanged**.
- On fully observed valid BPBs fixed D6-05 paired coverage was **128/65,664** complete FAT entries, **65,536 unobserved (99.80506823%)**. The short-source case has null physically paired coverage and never calls shared-chain reader. Neither sampled entry count nor mirror equality authenticates the original FAT copies.

## R4 and residual gap for A

**Proposed D6-02 narrow acceptance increment:** synthetic test now covers paired/one-sided missing links, same-copy cycles, mirror discrepancies, bad cluster markers, out-of-range link refusals, numeric shared-node intersections, distant unobserved faults and true physical EOF under the existing *fixed* accepted sampling path. No optional adaptive algorithm promoted; tests and documentation only, no source production behavior changed.

**Still unresolved even with green CI:** D6-02 row includes cross-link/source ownership. Two hinted numeric chains sharing a physically observed node do not prove two original files own that node, even in the synthetic scenario unless independent directory/candidate owner evidence is crosschecked. A7 source-scoped authoritative receipts and B directory owner binding remain A-owned. If full row requires end-to-end original-owner proof, A should keep D6-02 PARTIAL with this specific blocker rather than sign a false PASS. D6-03 real BPB authenticity and D6-04 A external-source attestation also remain PARTIAL; no FAT copy winner or repair. No R6 full stage credit and official project weighted progress stays **39%**, latest verified ledger 7 PASS/11 PARTIAL/4 AUDIT_NEEDED of22.

**R4 A adoption:** A independently checks the exact final PR HEAD native Windows PS5.1 and privacy regression, then chooses D6-02 PASS/PARTIAL and whether to integrate; Team D does not self-merge or update shared ledger.

**Absolute safety:** real physical microSD and sole ~31GB master IMG are NOT APPROVED for *any* read, hash, scan, copy, extraction, repair, write or upload. Only generated synthetic memory. R8 export stays blocked.
