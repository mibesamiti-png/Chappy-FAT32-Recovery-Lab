# Team A R7 A7-04/05: separate public candidate outcomes and actual source evidence dedup

**Scope:** purely generated nonwritable `MemoryStream` synthetic FAT32; no real microSD or sole ~31GB master IMG read/hash/scan/copy/repair/extract/export/write/upload. This change is **not itself R7 formal full-stage acceptance** or permission for R8 export.

## Source of correctness

The main `core/Chappy.PublicEvidenceV1.psm1` public `a7_public_evidence_v1` was already A-merged and has actual one-invocation A `Stream.Read` B numeric geometry + B directory/parent + C bounded scan + D paired FAT4B + C finite two-piece candidate re-reading and quotas. Strictly default OFF. A #187 [final/pr/main 49/49](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43588407169) SUCCESS for actual source disagreement, foreign/reordered/replayed candidate IDs, contradictory backup BPB, physical FAT3B then zero, and **test-only** oracle match. Main before this PR: `cccbc6c1c9ddac41bc1648f3adf295ad87f7fae5`.

## R7 outcome and provenance semantics

New explicit `outcome` object on the existing public result, with separate axes:
- `discovery`: bounded window found vs unknown
- `structure`: structural 3MF consistency vs unverified
- `sourceObservation`: *same A source session* actual returned bytes vs not observed
- `ambiguity`: other structural hypotheses or unscanned regions remain unresolved
- `oracleByteIdentity`: always `test_only_not_evaluated`, no original file SHA is ever supplied to or verified in production
- `recoverability`: always unknown, `unrecoverable=false` for empty/early EOF/unsupported, because bounded failed discovery doesn't prove irrecoverable original

Each returned candidate also has independent `candidateState` discovery/structure/source/ambiguity/oracle/recoverability fields. Public source limits and `canSelectOriginal=false`, `canSelectFatCopy=false`, `canRepair=false`, `canExport=false` are unchanged.

`evidenceAccounting` explicitly separates **4 distinct phase/reference labels from 1 in-process source session**; `phaseLabelCount=uniquePhaseLabelCount=4`, but `sourceSessionCount=1`, never 4 independent original sources. A actual returned/unique/repeated physical byte metrics must reconcile and repeated bytes are explicitly `repeatedReadsIndependentEvidence=false`. No caller can pass fabricated source event arrays into the public facade. Disabled/incomplete source leaves zero witnessed sessions and zero oracle facts. This bookkeeping does *not* prove external device authenticity, original parent or original file identity.

## New test / CI acceptance

`tests/Test-A3DOutcomeEvidenceAccounting.ps1` is the **50th isolated native Windows PowerShell 5.1/central privacy synthetic test**, run by `runner/Invoke-ChappySyntheticRegression.ps1`. Creates two fresh standard FAT32 artificial sources SPC1 fragmented and SPC2 contiguous; actually executes the public API under default OFF and on, verifies independent candidate outcome axes, public decision stays partial/unknown-original, physical union accounting from exactly one A source (4 phase labels ≠ 4 independent witnesses), independent private **test-only** SHA scoring on the two returned ordered source extents exactly matches generated 3MF oracle and differs from unrelated generated G-code oracle, while public JSON contains neither oracle SHA nor original ID, source bytes unchanged. Also tests true physical 17B then zero: unknown **not irrecoverable**, zero positive candidate, correct actual returned count. Prior A #187 tested contradictory backup BPB and 3B FAT then 0, cross-source/reordered duplicates; those remain central regression tests.

**Acceptance:** exact final PR HEAD native Windows PowerShell5.1/central privacy **50/50**, A source+diff review, then main post-merge **50/50**. This evidence is substantial for A7-04/05, but A must separately audit *all unchanged original R7 wording* (versioned B/C/D source, candidate IDs/extents, evidence reference/unique cost, disagreement/ambiguity/missing/reordered, discovered/structural/partial/external original exact/unknown distinct, default-off guard) before signing those narrow rows and original R7's 10% milestone. Official prior full-stage 74%; indexed 20/22 before further review. Four independent ABCD chats; A alone merges.
