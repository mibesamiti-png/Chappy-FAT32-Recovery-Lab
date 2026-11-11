# Existing Algorithm Research & A/B Adoption Protocol — Team A

**Effective on next B/C/D continuation (2026-11-11).** Canonical cross-team process. Existing assignments B #45, C #46 and D #47 are retained; this document changes **how** their work is executed, not ownership, branch or issue scope.

## Purpose

Use prior published data-recovery algorithms, standards and independently analyzed OSS designs to improve the experimental FAT32 Recovery Lab. Record provenance, limitations and license risk; compare a proposed algorithm against the **same current-main baseline** on exactly the same deterministic **artificial** fixtures. Promote only measurable, reviewed improvements.

**Absolute constraints:** Never read, write, repair, hash, export or upload the user's physical microSD or unique approximately 31GB master IMG. Public repository/CI contains only generated artificial fixtures and redacted aggregate numbers. Real-image preflight remains **NOT APPROVED** under docs/LOCAL_READONLY_APPROVAL_GATE.md. This research process does not grant new permissions.

## Roles / independent boundaries

| Team | Scope | Research focus | Existing Issue |
| --- | --- | --- | --- |
| A | docs/, runner/, CI and reviews | Define baselines, fixture fairness, gate decisions, integration only | #1 |
| B | modules/directory/ | Evidence-graded hierarchy, graph constraints, FAT-independent metadata, LFN failures | #45 |
| C | modules/carving/ | File-format validators, two-fragment carving, bounded gap search and structural checks | #46 |
| D | modules/fat-analysis/ | VBR and FAT mirror hypotheses, independent consistency evidence, sampled anomaly statistics | #47 |

B/C/D must never edit A's central runner, dispatch, shared state or another team's module directly. If a cross-team interface is needed, open an Issue/comment for A instead. Keep each branch assigned in docs/TEAM_DISPATCH.md; check fresh main/branch/PR/CI at start.

## Five gates, in order

### R0 — Survey and provenance (before production algorithm edits)

1. Find **three distinct relevant approaches** when credible sources exist; do not invent names or pad weak sources. Prioritize specifications, peer-reviewed papers, official project documentation and original repositories.
2. For every candidate record: title, author/maintainer, primary exact URL, version/publication date where known, input requirements, core mechanism, known failure modes, Windows PowerShell 5.1/.NET suitability, expected benefit, expected worst-case computation, and license/source-code attribution status.
3. Distinguish a concept described by a paper, a public specification, an independently written algorithm, and reuse of third-party software/source code. Copying text/code from GPL or mixed-license projects is **not automatically acceptable**. Confirm applicable license and any notice/redistribution duties before code reuse; if unclear, mark **license review required**, do not import/copy it. Independent implementations must still respect applicable rights and dependencies. Repository has no declared project license as of this checkpoint: do not invent one.
4. Select one feasible bounded P1 approach **within the already assigned Issue**, explaining why it beats alternatives in expected measurable tests. Publish an Issue research-note or Draft PR docs checkpoint first; use docs/ALGORITHM_RESEARCH_TEMPLATE.md.

### R1 — Freeze comparable baseline

- Record the exact existing **main SHA**, current implementation flag/settings, fixture generator SHA/seed and expected ground truth before changing the algorithm.
- Use the identical artificial test vectors, read/probe/time/memory quotas, PowerShell 5.1 runtime and scoring rules for baseline versus proposed algorithm. If constraints change, report the difference, do **not** imply directly comparable scores.
- Keep a baseline path/test callable; **no replacement, silent default-on or deletion of old algorithm** while unverified.

### R2 — Independent research prototype

- Build one tiny and reviewable experimental helper, guarded by a default-OFF flag if production-facing. A tests/docs-only feasibility result is valid and preferable when no sound implementation exists.
- Readable, seekable **non-writable Stream** only; no physical device handles; no external programs or remote API; no unbounded RAM, file-size scans, recursive search, decompression or cross-product fragment combinations.
- Every tentative result must be evidence-coded: possible/partial/unknown. Never infer a real recovered path, original-file byte integrity, or automatically choose one FAT/VBR/repair action.
- Restrict logs, tests and reports to invented filenames, artificial bytes and fixed/redacted aggregate reason codes.

### R3 — Same-corpus A/B measurement

Required measurements when ground truth exists:

| Class | Metrics and disqualifying errors |
| --- | --- |
| Detection | TP, FP, FN, TN; precision TP/(TP+FP), recall TP/(TP+FN), and sample count (mark undefined if denominator=0) |
| Content integrity | Known original **byte-identical** artificial file/candidate count, proposed fragment-order correctness; report structurally valid but bytes-changed separately |
| Trust | False 'verified' or 'complete' claims for corrupted/unknown ground truth must be **zero**, incomplete/unknown coverage reported explicitly |
| Resources | Total actual bytes read, read requests, probes, max candidate pairs/entries, elapsed time, memory high-water where reliable |
| Safety | Non-writable source, unchanged artificial input SHA-256, no outside output, no private strings, no path/device escapes, no quota overruns |

Use both clean positive controls and negative/adversarial examples: false signatures, LFN corruption, bad/out-of-range FAT entries, identical corruption across both mirrors, truncated ZIP/3MF, non-contiguous fragments, unknown/ambiguous evidence and tight budgets. Record seed, expected/observed cases and any missing categories. Never claim a broad recovery probability from small selected fixtures.

### R4 — Team A acceptance (not automatic)

Submit one small **Draft PR** against main with research table, baseline SHA, fixtures/method, executable tests, observed A/B table, license notes, known regressions, no-reconstruction limitations and next hypothesis. Team A verifies final HEAD Windows 5.1 CI + privacy gate, reads the diff for safety, and checks regression suite.

**Mandatory blocks:** any real-data exposure; writable source/repair; non-disclosed third-party code or unclear licensing; unchecked allocation/loop; an increase in false original-integrity/verified claims; CI failure or untested final HEAD; or missing comparable baseline/ground truth for claimed gains. Zero measured improvement is allowed as **research-only tests/docs**, but does not justify replacing the old behavior.

Decision codes: **adopt_experimental**, **research_only**, **revise**, **reject**, with evidence and caveats. Even adopted work stays experimental/default-OFF if a new reconstruction or integrity inference is involved, until separately reviewed. A alone merges and updates dispatch/STATE/ROADMAP.

## Suggested study ladder / next-round interpretation

- Team B #45: survey FAT directory parsing/LFN reconstruction and constraint-based graph reconciliation; first strengthen conflicting parent + cross-window false-path tests, then compare evidence grades.
- Team C #46: survey bounded file carving and bifragment gap carving plus format-specific G-code/3MF/ZIP validation; first show finite two-fragment pair order A/B against independent known bytes (do not guess actual FAT chains).
- Team D #47: survey FAT geometry/mirror consistency and filesystem forensics cross-evidence; first quantify local anomaly distribution under tiny read budgets with no winner/repair.

These are research directions, **not instructions to copy another project's code**. See docs/ALGORITHM_RESEARCH_STARTER_REFERENCES.md for source entry points.

## Progress reporting

At the end of each B/C/D continuation state current research gate R0–R4; investigated algorithms (or none); selected method and why; branch/Issue/PR/latest HEAD; synthetic actual CI; baseline and candidate results; safety/license state; remaining uncertainty; next bounded step. If the assigned P1 already completed, report completion rather than autonomously starting another team round.
