# B -> C support transition (A dispatch, 2026-11-14 JST)

**Authority:** Team A / Issue #1. **Execution:** four existing independent A/B/C/D ChatGPT conversations. This is a plan and assignment, not proof that R4 has passed, and does not run chats automatically.

## Current fixed baseline

- Main at dispatch: `fd3fcade5f695c72473cb60ac3fa58516a477dd1`, PR #163 merged, post-main Windows PowerShell 5.1 / privacy **44/44 SUCCESS** ([run](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43481358196)).
- Signed **narrow** rows: B R4 **5/5 PASS**, C R5 **2/6 PASS, 4 PARTIAL**, D R6 **4/5 PASS, 1 PARTIAL**, A R7 **1/6 PASS, 5 PARTIAL**. These are subchecks only; the official completed full-stage weight stays **39%** (R0–R3), not a file recovery rate.
- B's original R4 whole-stage gate is **not yet accepted**. B must not treat 5/5 subrows as a blanket 10% stage credit. R5/R6/R7 remain incomplete; R8 blocked.

## Phase B-1 (NOW): close original formal R4 audit before changing scope

Team B continues under Issue #71 and within `modules/directory/` plus B-owned tests. First task is one independent, evidence-backed R4 acceptance report against the **full original** `docs/ABCD_SYNTHETIC_ROADMAP.md` R4 clause, not only the five ledger row titles:

1. Re-fetch latest main, relevant B code, baseline corpus and B4-01..05 signatures. Build a clause-to-code/test/fixture/final-head CI matrix; identify **any omitted original requirement** and separate PASS, PARTIAL, UNKNOWN and missing evidence.
2. Audit M00/M01/M04/X02; clean and malformed LFN; deletion/orphan; conflicting/hidden/forged complete parent graph; preserved candidate visibility; independent candidate/edge TP/FP/FN/TN + UNKNOWN and scan-coverage denominators. Avoid counting abstentions as true negatives or claiming original parent/path.
3. Distinguish B self-reported receipts from the same-session A `Stream.Read` source meter on main #163. Confirm early EOF, quota, writable-source denial, ambiguous/remote UNKNOWN and original SHA invariant on generated nonwritable fixtures. Do **not** claim real-media attestation.
4. If evidence is complete, submit a bounded **tests/docs-only Draft PR** with an auditable original-R4 acceptance matrix; if a mandatory clause fails, submit the smallest gap-closing B-owned fix or explicitly report BLOCKED/PARTIAL and its minimal needed evidence. Never weaken a gate to improve percentages.
5. A independently checks diff, source, final exact PR-head Windows PowerShell 5.1 + privacy CI, post-main CI, and original roadmap. **Only A** may merge, sign the whole R4 stage and change official weight (39% -> 49% only if the original complete 10-point R4 gate truly passes).

**Transition trigger:** A posts an explicit R4 disposition in Issue #71 / the live dispatch. If A cannot accept all original R4 criteria, B stays on the R4 blocker; C proceeds independently. No automatic role change merely because the indexed 5/5 rows passed.

## Phase B-2 (AFTER explicit A R4 approval): help C without competing ownership

B keeps its identity as **Team B** (not a second C chat). It supplies synthetic independent **directory and fragment evidence** to C in Issue #72 and tests under B's ownership; C continues to own `modules/carving/` and is never blocked waiting for B.

**First candidate assistance package (B -> C):** build a bounded, default-off, **advisory-only** B directory/candidate evidence fixture/contract and negative test matrix for C's C5-03 two-fragment discovery, with A/C review before implementation. Candidate data: observed directory entry, declared size if independently observed, physical returned cluster spans, actual source-read coverage status, and explicit UNKNOWN/conflict; **no inferred original path, no privileged original extent/tail/expected hash and no FAT winner**. Compare C's unassisted search vs the same C search given B's actually observed hints on *identical* generated fixtures and equal caps. Include corrupted size, forged parent/self-ledger, hidden or missing directory evidence, reversed fragments, decoy valid-format-but-wrong-original, early EOF and quota. Label hints unavailable to real recovery; use independent scorer-only original SHA, TP/FP/FN/TN/UNKNOWN by candidate unit, candidate/probe costs, actual + unique bytes and runtime/memory when measured. B evidence must not silently elevate C structure-only checks to recovered-original status.

**Ownership & merge:** B edits `modules/directory/`, B-owned `tests/Test-Directory*.ps1`, and its own report/contract doc only. C edits `modules/carving/`, own tests, and retains priority C5-02 before C5-03 if that is C's current P1. A alone owns `core/`, `runner/`, shared adapter, public result contracts and gate ledger. Proposed cross-owner files or shared fixtures require A/C approval before editing. B publishes a small Draft PR and a concrete Issue #72 handoff describing useful B-observed fields and trust limits; C decides whether/when to consume; A independently validates and merges.

If C does not yet need B hints, B should prepare **independent negative scoring tests and evidence-contract review** rather than invent another research scheduler. Keep B available for R4 regressions.

## Nonnegotiable safety and reporting

- **Only invented synthetic nonwritable MemoryStream/image data.** Physical microSD and unique ~31GB IMG are NOT APPROVED for *any* reading, hashing, scanning, copying, extraction, modification or upload. No real recovered files/logs/private filenames on GitHub.
- Read-only default, bounded memory/reads/calls/probes, no repair/auto-winner, fail closed on gaps. Original-byte equality is external synthetic oracle evidence, not structural-format or real source authenticity.
- Every proposal states exact HEAD, source paths, generator/seed/fixture, actual executed Windows 5.1 and privacy CI URLs, failure modes, and disposition. A review and post-merge CI are mandatory.
- D continues independent D6-04 physical paired FAT coverage; A continues R7 live B/C/D integration. No Work single-session orchestration and no automatic B/C code ownership switch.
