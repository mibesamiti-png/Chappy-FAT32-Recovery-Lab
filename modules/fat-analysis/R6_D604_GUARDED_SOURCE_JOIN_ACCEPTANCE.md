# Team D D6-04 — Guarded FAT source-return event join acceptance evidence

**Role:** existing standalone Team D chat; Task Issue #73; Draft PR #166. **Baseline main:** 5133b1f335e319844136732790d5a9e7768a826a. Never use Work to orchestrate A/B/C/D. A alone reviews, merges, and signs the ledger. No real-media approval.

## R0/R1 preregistration and legal provenance

R0/R1 frozen **before** new code at https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6863334230.

- Format facts: Microsoft FAT32 Specification v1.03 (copyrighted specification, no code incorporated). TestDisk (CGSecurity, GPL-2.0) and Sleuth Kit (component-specific licensing) for conceptual comparison only. No outside implementation or dependency imported.
- Baseline D6-05 main module Fat32GuardedResult.psm1 blob 6cfdd6b6bd78dbf5ca7cad35ab21bfdee85b9486, previous D6-04 numeric coverage Fat32PhysicalPairCoverage.psm1 blob 0516f28ed64a6e3af228e3391f5b3f7f3b630829, A live source meter core/Chappy.LiveBcdEvidence.psm1 blob f4cb2e6a36d5b8ea6a2f6e6206a7b37f14917512 (A-owned, not modified).
- **Previously missing functional binding:** D6-05 reported actual/unique byte totals and a 128/65,664 paired FAT sample but did not expose the sequence of **successful actual physical returned offsets and lengths**. A's existing independent in-process source meter saw its own fat-consumer events, but was limited to total-byte equality and could not verify which physical FAT entry indices were observed.

## R2/R3 minimal bounded code change

1. Additive public numeric sourceReturnedEvents property on Get-ChappyFatGuardedResult v1 (no version change or default enable): complete ordered successful-return offsets, length, endExclusive and D subphase (geometry_gate or fat_fixed). Always returns empty list when default-off or invalid stream. On bounded errors it keeps only actual successful returned physical spans. This is **D internal provenance, not A-authenticated evidence**; no source bytes, identities, private paths, owner or output file access. At most D's 512 actual source-read calls and 4,096 returned bytes. Existing geometry-first deny-first behavior and the fixed sampler are unchanged.
2. New opt-in pure read-free D helper Compare-ChappyFatGuardedReturnedSourceEvents in Fat32GuardedReturnedSourceJoin.psm1. Accepts a D6-05 result, caller-supplied external **actual successful returned Stream.Read events**, source length and optional independent physical call/early-zero counts. Never performs physical I/O or imports A-owned code. Requires exact **ordered offset/length, consumer phase fat, D phase order, phase returned-byte totals, actual/unique/repeated union, physical source budget and optional delegated Read-call** equality. Rejects forged/reordered/shifted/dropped/replayed/other-consumer returned-event lists.
3. For matching **numeric candidate-only** primary and backup BPBs, independently recompute complete returned **four-byte FAT entries in each copy** from external fat_fixed source events (not D self-reported event count) and intersect their numeric entry indices. It must match D guarded evidence's FAT1, FAT2, paired, total, unobserved and rounded percentages. One to three returned bytes cannot form a complete entry. Contradictory BPBs permit **zero fat_fixed read events** and output consistent_blocked_unattested without inventing paired counts. Premature physical zero or exceeded budget yields UNKNOWN with null pair metrics. No FAT-copy winner, file owner, original SHA or repair claim can be returned.

**Trust boundary:** OuterReturnedEvents are supplied by the caller of this D helper; a malicious caller can forge both lists. Therefore even a perfect match is explicitly consistent_numeric_candidate_unattested / sourceAuthenticity=not_proven, **NOT an A-issued or independently authenticated receipt**. Only Team A can attach actual in-process source-scoped physical meter events and adjudicate D6-04. Team D does not edit A/B/C integration files or canonical gate ledger.

## R3 independent generated-source Windows tests

New Run-TeamD-R6-GuardedReturnJoin.Tests.ps1 uses an entirely separate in-memory nonwritable .NET Stream.Read meter, with independent 8,192-byte/640-call physical caps and actual event offsets. Runs A-approved standards-sized 65,541-data-cluster FAT32 SPC1/SPC2 source generator seeds 202621/202622; only synthetic snapshots, no user data. Ground-truth mutations and original SHA remain inside test scorer, not supplied as analyzer hints.

| Frozen artificial case | D behavior | Source event join |
| --- | --- | --- |
| Clean SPC1, clean SPC2 | Guarded fixed sample | Numerically consistent, NOT A-attested |
| FAT2-only missing/free link | Observed copy disagreement, no winner | Numerically consistent, no owner claim |
| Both FAT copies identical cyclic link | Mirror may agree but still not healthy proof | Numerically consistent, no integrity promotion |
| Planted remote FAT2 entry 60000 | Outside returned windows | 65,536 paired indices not physically observed, UNKNOWN |
| Repeated 32B short physical Read chunks | Full FAT entries ultimately returned | Correct unique physical union, no double counting |
| Primary/backup BPB conflict; equal unsupported flags; invalid SPC | Guard denies FAT reads | Consistent structural-only, paired counts null |
| Genuine physical zero after 1,100 returned B | Source incomplete | UNKNOWN/null pairs |
| Genuine physical zero after 3 FAT-return bytes in the fixed phase | Partial 4-byte entry + source incomplete | UNKNOWN/null pairs |

Test-side adversarial controls: delete, replay, offset-shift, reorder or cross-consumer outer read events; change outer physical Read-call count; forge D numeric paired entries or unique byte totals. All must refuse numeric coverage. Test also verifies writable input refusal, default-off zero events, per-source SHA-256 byte identity.

**Code-head native Windows PowerShell 5.1 CI #43497445892:** https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43497445892 — new suite **66 PASS /0 FAIL**, previous D suites PASS. Full report-only commit not yet present in that run; A must still verify **exact final PR HEAD Windows+privacy CI**.

Observed exact per clean/valid source: **128/65,664 complete paired 4B FAT indices**, **65,536 unobserved pairs = 99.80506823%**. All clean/valid cases had 4,096 physically returned B / 3,072 source-local unique B / 1,024 duplicate B under 8 or 128 actual physical Read calls depending artificial short-chunk pattern. Blocked source cases: 2,048B actual/unique, 0 FAT bytes. True early-zero 1,100B and 3,075B cases UNKNOWN. These source-level values **are not file-recovery rates or a claim of whole FAT integrity**. Full independent totals are in final Windows test log.

## R4 Team A acceptance requested

- D now offers the missing **bounded numeric D6-05 event trace and pure source event join** for A to bind its own Stream.Read source-events, not just byte counts. Validate exact final-head Windows PS5.1 and privacy CI and decide D6-04 PASS or PARTIAL honestly, identifying A7-01/A7-06 source-scoped receipt binding as a separate A-only residual if needed.
- Other R6 subchecks D6-01/02/03/05 already A-signed PASS; D6-04 PARTIAL until A independent review; **R6 full stage uncredited**, official weighted project completion **39%** R0–R3 only. Latest pre-work A-ledger: **12 PASS, 10 PARTIAL, 0 AUDIT_NEEDED of 22**, not real recovery success.
- **No real access:** physical microSD and sole ~31GB master IMG NOT APPROVED for reading, hashing, scanning, copying, modifying, repairing, extracting or uploading. R8 separate-destination output blocked. No actual user artifact, payload, source identity, original SHA or path handled.