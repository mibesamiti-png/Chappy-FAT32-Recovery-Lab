# Team D R6 D6-03 — Primary/backup VBR disagreement: explicit no-FAT-read boundary

**Status: D-scoped gated implementation / A acceptance pending.** Issue [#73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73), Draft [PR #146](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/146). This report accompanies a small read-only, separately invoked D module; it is not a general proof of FAT32 volume health, actual file recovery or any authorization to inspect real media. Official engineering progress remains **39%** until whole formal stage gates pass. R6 row D6-01 already A-signed PASS, D6-02 PARTIAL and D6-03 previously AUDIT_NEEDED; A alone updates shared ledger after inspecting this exact PR HEAD.

## Frozen pre-change sources and baseline

R0/R1 [registration before any code](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6851843604):
- Base `main` at task launch: `8ccf4a270c2a514105a30b89f279a87e1e0d07ad`.
- Prior D VBR hypothesis parser `Fat32VbrDisagreement.psm1` SHA `327435db53485b413d581b20513eae174eecf30e`; D primary/backup geometry trust `Fat32GeometryTrust.psm1` SHA `fbfe8f6d7d34bbe7cc67fd1ccd6ec9ac0973e25b`; existing D source-meter `Fat32ObservedIoEvidence.psm1` SHA `b1f6d0ceea222335c16de9532ed49cb35a312aad`.
- Approved artificial standard generator `tests/helpers/New-ChappyA3DStandardFixture.ps1` SHA `6e90e3c1b063ced7a9685f8b20c1437a66527405`, seeds202614/202615, sectors-per-cluster1/2.
- Microsoft FAT32 File System Specification v1.03 (copyrighted document) https://www.osdever.net/documents/fatgen103.pdf; CGSecurity TestDisk docs https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html (source GPL-2.0 https://github.com/cgsecurity/testdisk); Sleuth Kit forensic source https://github.com/sleuthkit/sleuthkit (mixed component license https://www.sleuthkit.org/sleuthkit/licenses.php). **No external code copied or executable dependency added**; any reuse requires independent license review.
- Existing D5 result is a baseline: inspect four 512-byte MBR/VBR/backup/FSInfo structural sectors with source budget 2048, report two candidate-only geometries and `agreement=agree|disagree|insufficient_evidence`. Its outputs do not certify real FAT location or owner; it is not modified by this PR. New adapter comparison invokes this same parser under the same generated source and read cap, adding a stricter **deny-only downstream boundary**, not a new FAT sampling or repair algorithm.

## What implementation adds to D6-03

`Get-ChappyFatGeometryHypothesisGate` in `modules/fat-analysis/Fat32GeometryHypothesisGate.psm1`:
- Accepts only readable, seekable, **strictly nonwritable** streams. No filesystem paths, device handles, source content, names, original SHA, file reconstruction or writes.
- Reuses D5 independent primary-vs-backup candidate calculations; does not automatically re-locate a backup VBR if the primary-declared backup offset is false.
- Returns independent `primary` and `backup` numeric candidates, each labelled `plausible_unverified|insufficient_evidence|contradicted`; their measured offsets are **caller/primary-header hypotheses**, never authenticated source truth.
- `gateDecision=blocked_conflicting_geometry` when the two candidate BPBs disagree; especially when each is independently plausible but implies **different in-bounds FAT offsets**. Contradicted or incomplete cases become `blocked_contradicted_geometry` and `blocked_insufficient_evidence`. Two equal candidates yield only `candidate_geometry_unverified`.
- **Every single result, even agreement, has** `fatReadAllowed=false`, `fatRegionProbeCount=0`, `sourceDecision=not_selected`, `selectedCandidate=null`, `writePermitted=false`, `originalIdentity=unknown`. The wrapper never calls FAT mirror windows/chain walkers, never exports an assumed winner/owner, and cannot authorize real-image or R8 export.
- Distinguishes **complete structurally observed disagreement** (`scanIncomplete=false, geometryUnresolved=true`) from **short, missing or budget-clipped reads** (`scanIncomplete=true`). On a failed physical Read-call budget, two stable UNKNOWN source-role placeholders are returned with **null geometry**, not a fabricated guessed FAT offset.
- Records D-only internal physically **returned/unique/repeated** bytes, actual delegated Stream.Read calls, premature 0 returned before declared end and numeric unique observation ranges. A separate quota wrapper bounds delegated calls to at most **256**; D existing meter caps actually returned bytes to **2048**. These observations are explicitly marked `internal_not_A_attested`: A-issued cross-team/source-scoped physical receipts remain an outstanding D6-04 integration dependency.

## Synthetic scorer matrix and physical read accounting

Frozen 12-case corpus generated in memory, with no mutation coordinate, seed, filename, ground-truth SHA or expected label passed into the guarded analyzer:

| Scorer-only case | Expected guarded outcome | Structural interpretation |
| --- | --- | --- |
| SPC1 clean / SPC2 clean | `candidate_geometry_unverified` | Two matching BPBs; still untrusted; no FAT read |
| Backup reserved sectors 32→33 | `blocked_conflicting_geometry` | Both BPBs independently plausible; different **in-bounds FAT1/FAT2 offsets**; no winner |
| Backup root cluster2→3 | `blocked_conflicting_geometry` | Two plausible root hypotheses; no winner |
| Backup FAT sectors +1 | `blocked_conflicting_geometry` | Two plausible FAT region geometries; no winner |
| Backup FSInfo locator1→2 | `blocked_conflicting_geometry` | Backup FSInfo was not independently observed, never borrowed from primary |
| Backup sector boot signature altered | `blocked_contradicted_geometry` | Invalid candidate not promoted |
| Primary-declared backup location6→7 | `blocked_contradicted_geometry` | Only declared sector7 examined, no fallback search |
| Corrupt MBR signature | `blocked_contradicted_geometry` | MBR anchor invalid; comparison incomplete, scorer unit UNKNOWN |
| 7B chunk reads, physical early 0 after 1100B | `blocked_insufficient_evidence` | Source premature EOF; scorer unit UNKNOWN |
| 1024B total source read budget | `blocked_insufficient_evidence` | MBR+primary cannot certify backup; UNKNOWN |
| One-byte chunks capped after 4 physical Read calls | `blocked_insufficient_evidence` | Bounded source failed; both candidates UNKNOWN with null FAT offsets |

The **explicit scorer unit** is a planted *unsafe conflicting/contradicted BPB metadata condition*, not structural file recovery or authentic FAT health. Six planted positives, two clean negatives, four separate unscored incomplete/anchor-invalid UNKNOWN. Preliminary Windows code-head report on the 12 cases: **TP6, FP0, FN0, TN2, UNKNOWN4**, source-local physical sums **19,024 actual returned B / 19,024 unique B / 0 repeated B / 200 physical Read calls / 0 FAT-region reads**. All artificial inputs remained SHA-256 byte-identical. These counts refer only to independent generated Stream instances and cannot certify cross-source authenticity or recovery probability. Additional low-level writable-stream, byte cap, call cap and invalid partition-slot negative tests are separate from this scorer denominator. New native Windows PS5.1 test script reports exact assertions; final PR HEAD CI, including privacy, must be confirmed separately.

## Explicit residual limitations and A review request

- An apparently matching primary and backup VBR **never proves** the file system's original geometry, either FAT's correctness, file owner/chain integrity or recovered byte identity. A true A-issued physical source token was not generated here; D has only local returned offset evidence.
- A BPB may be internally plausible yet stale, contradictory or malicious. This module refuses automatic FAT dereference but **does not** choose correct source geometry or implement any recovery process.
- Another caller could bypass this new separately invoked adapter and use legacy D FAT APIs with caller geometry; cross-team enforcement requires A integration and source-scoped receipts. D6-03 should be A-signed PASS **only if** the entire required hypothesis/refusal boundary is demonstrated in reviewed consumer integration; otherwise PARTIAL with named dependency. D6-04 external-source trust remains pending; D6-02 owner proof still PARTIAL and D6-05 public consumer contract requires review.
- A alone reviews the exact final PR HEAD, Windows PowerShell5.1 and privacy CI, decides adoption and updates the canonical gate ledger. D does **not** self-merge or change weighted progress.
- The physical microSD and unique ~31GB master IMG remain **NOT APPROVED** for read/hash/scan/copy/write/repair/extraction/upload. Every test is generated artificial memory only; R8 output remains blocked.
