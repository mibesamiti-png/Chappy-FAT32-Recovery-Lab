# Team B R4 B4-03 — independently returned parent/dotdot structural observations

**Owner:** Team B, [Issue #71](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/71). **Pre-code R0/R1 freeze:** [#6859804356](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/71#issuecomment-6859804356). **Base main:** `1f4bf2cd94b7c41ba71bcd99f4bc12bcb10381d4`. This evidence package addresses one B4-03 remaining subrequirement; it does not change A's signed ledger, authenticate an original filesystem, or make R4 complete.

## Existing missing acceptance, now addressed with a bounded B adapter

B4-03 #148 default-OFF strict graph suppresses all probable parent confidence when **B's own** read ledger is unauthenticated. B4-05 #154 exposes numeric redacted `parentEdges[]`, `nodes[]`, `parentHints[]`, `geometry` and completed directory spans, without original filenames. B4-04 #156 has a pure `Compare-ChappyBDirectoryReturnedEvidenceV1` that checks B directory spans against **separately supplied** A-shaped physical-return intervals, with no source authenticity guarantee.

New `modules/directory/DirectoryParentObservationJoin.ps1` dot-source entry `Get-ChappyBParentObservationV1` consumes exactly those existing B4-05 and B4-04 shapes without additional source reads.

For one parent link to be reported as **`observed_pair_unattested`**, all of these must be true:
- B4-04 interval comparison is `consistent_unattested`; no duplicate outer-source returns, contradictory B spans or partial EOF.
- One parent candidate edge with `relationStatus=parent_hint_corroborated`, exactly one parent assertion for that child, exactly one matching child dotdot hint, one non-root child node `referenced_candidate`.
- Parent and child cluster indices and numerical geometry are valid, the 32-byte parent entry is aligned and inside its parent cluster, and the child dotdot entry is inside its own cluster at offset `+32`.
- **Both 32-byte records** fit a fully completed B directory-cluster span **and** the separately supplied outer `Consumer=directory` returned-byte interval union. Distinct consumer phases are never substituted.
- B edge confidence is `partial`, B source attestation `unattested`, and original identity `unknown`; any contradictory/cyclic/duplicate/absent-hint relation remains ambiguous even if source bytes were physically returned.

The output `b_parent_observation_v1` distinguishes `observed_pair_unattested`, `ambiguous_structural`, `unobserved_unknown`, `contradicted_read_ledger`, and `no_parent_assertion` (represented by zero rows). All outcomes retain `originalIdentity=unknown`, `originalParent=unknown`, `originalPath=not_reconstructed`, `parentConfidence=partial`, `sourceAuthenticity=not_proven`, `canExport=false`, `additionalStreamReads=0`. There is **no receipt token issued by B**; an untrusted caller supplying fabricated matching B + outer arrays could deceive interval consistency. The returned `observed_pair_unattested` is only a *record-interval consistency* label, **not** a correct original parent/path, complete content proof, actual physical-media authenticity or elevated graph confidence. A has to enforce the provenance/owner of its own meter events in the A R7 adapter.

Default B graph confidence and existing B4-05 envelope semantics are **unchanged**. No new FAT chain inference, no new directory scoring heuristic, no file/path reading or exporting.

## Fixed artificial corpus and evaluation denominators

The executable `tests/Test-DirectoryR4GateParentPhysicalPair.ps1` invokes the actual B4-05 production envelope, then the new B4-03 join with independent test-side `MeteredStream` events reshaped to A's event model. A generator supplies **three seeds (202611–202613) × four cases**, from existing `New-BR4ParentImage` in B #136:
- `matched_parent`: genuinely returned parent link entry + child `..` 32-byte records, `observed_pair_unattested` (3 structural observations; original parent still UNKNOWN).
- `duplicate_parent`: both actual parent source records returned but two competing parent links, classified `ambiguous_structural` (3 fixture-level UNKNOWN cases, 6 candidate edges; neither guessed a winner).
- `short_child`: child returns only **17 of 512 bytes** beyond a completed root block, cannot complete the child's `..` record and stays unknown (3 cases).
- `orphan`: child has `..` root marker, but lacks actual parent assertion; **no inferred path** (3 cases, no-parent/UNKNOWN).

**Pre-registered resource expectation:** 12 scans, **15,411 source returned bytes**, **15,360 completed directory bytes**, **186 Stream.Read calls**, 0 added join IO; source bytes and each returned SHA verified by the *external synthetic scorer*, full generator SHA preserved. These totals are separate from prior #131 hidden-parent twin corpus, which already proved **supported3/contradicted3 hidden original-parent truth cannot be distinguished** from identical actual returned transcripts; never pool its TP/FP and LFN rates with the 12-case structural decision matrix.

**Additional B-only adversarial metadata comparisons** reuse the same real positive-source events with no new reads: forged wrong child target, missing dotdot hint, fabricated duplicate edge, cyclic relation status, parent-entry offset shifted from parent to child, forged completed B read span, and omitted outer return event. Each must fail closed. A caller-supplied `callerSaysAttested=true` is explicitly ignored; even if numeric intervals agree, the outcome remains *unattested* and no original-path/file status changes. A B self-ledger with **zero** independent outer events cannot claim physical observation.

## A review/acceptance boundary

This B4-03 change is **testable production-facing metadata** rather than new experimental inferred original path. A owns the trusted source stream, candidate/source-phase receipts and review of final PR HEAD Windows PowerShell 5.1+privacy CI. A may use the new B join to present structural evidence without silently discarding genuinely observed positives; A **must not** treat the join's output as source authentication merely because the records' extents match caller-supplied arrays. A controls the official `docs/ABCD_GATE_LEDGER.md` B4-03/B4-04 status and sole merger authority.

As of baseline: B R4 **3 PASS/2 PARTIAL/0 AUDIT_NEEDED**; ABCD **8 PASS/14 PARTIAL of 22**, official weighted fully gated project **39%**, not actual recoverability. Real microSD and unique ~31GB original master IMG **NOT APPROVED** for any read/hash/scan/copy/repair/extract/write/upload. This project change uses generated in-memory synthetic arrays only. No third-party source code copied (Microsoft FAT file spec and official .NET `Stream.Read` semantics used as concepts; TSK mixed-license and Linux GPL source excluded).
