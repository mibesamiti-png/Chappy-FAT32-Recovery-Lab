# ABCD Four-Chat Gate-Closure Playbook (2026-11-13 JST)

**Status: proposed operating design by Team A.** This playbook governs how the existing **four independent ChatGPT conversations** should prioritize the next work. It does NOT imply four concurrent agents inside a single Work session. A is the integration/QA owner in its original chat; B, C and D continue in their **existing chats**. It supersedes older per-team next-P1 instructions only once A has merged this document and posted new Issue assignments. Canonical sources: [formal roadmap](ABCD_SYNTHETIC_ROADMAP.md), [live roster](TEAM_DISPATCH.md), [research protocol](ALGORITHM_RESEARCH_PROTOCOL.md), [real-media approval gate](LOCAL_READONLY_APPROVAL_GATE.md).

## 0. The bottleneck and the invariant

Current reviewed main baseline: `5482ab2791993472ba0bd863c87a655586cee148` (B/C/D and A PRs #133–#138 accepted on 2026-11-13 JST). Post-main CI: [central synthetic Windows PowerShell 5.1 / privacy 38/38, 188 tracked paths](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43250814240), [D 351/351](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43250814318). This is a snapshot, not a permanently pinned HEAD; ALWAYS fetch fresh GitHub.

The official engineering roadmap is an all-or-nothing weighted completion measure: R0=5%, R1=10%, R2=12%, R3=12% are fully gated = **39%**. R4=10%, R5=15%, R6=10%, R7=10% are 45 pending points; R8=9%, R9=5%, R10=2% are later 16 points. Multiple merged `research_only` PRs can improve confidence without changing that percentage. **Never award weighted points for partial rows, and never change thresholds merely to improve progress reporting.**

The issue is not lack of PR throughput. It is that exploratory research and synthetic negative cases are repeatedly merged without a **mapped stage-gate blocker** or production-facing, guarded capability. A now optimizes **closure of existing requirements**, not number of PRs or experiments.

## 1. Execution model: 4 conversations, one shared GitHub

| Conversation | Role | GitHub Issue | Owned scope | Current immediate goal |
| --- | --- | --- | --- | --- |
| A (existing coordinating chat) | Specify, review, integrate, gate audit; A-only code | [#1](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/1) | `runner/`, `core/`, shared integration tests, `docs/TEAM_DISPATCH.md`, roadmap, central CI | First audit the gate matrix, then R7 live B/C/D evidence contract and candidate extent/ID conflict |
| B (existing B chat) | Directory evidence / LFN / parent graph | [#71](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/71) | `modules/directory/`, B-owned tests (including `tests/Test-Directory*.ps1`) | Close R4 through source-observed (but NOT self-attested) structural parent evidence with clean/damaged/adversarial corpus |
| C (existing C chat) | File formats, bounded candidate/fragment reconstruction | [#72](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72) | `modules/carving/`, C-owned tests | Close R5's format/fragment breadth: ZIP/OPC/XML, binary+ASCII STL, G-code, two-fragment withheld-hint cases, exact artificial bytes |
| D (existing D chat) | Geometry/FAT observations | [#73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73) | `modules/fat-analysis/`, D-only tests/CI | Close R6 with existing bounded fixed-sample baseline, anomalous FAT chain cases and honest physical coverage/UNKNOWN; no FAT winner |

**No Work orchestration is required.** Each team reads latest main, AGENTS, this playbook, live dispatch, its Issue/comments, current PR and CI at every continuation. A alone merges into `main`. B/C/D NEVER self-merge; don't edit shared state/dispatch/another module or overwrite another live branch. Each new scope uses one new branch from freshly verified main and one small Draft PR. Do not invent or assign team identity in a new unassigned chat.

## 2. Gate closure checklist — derived from the existing roadmap, not replacements for it

The rows below are **operational subchecks** mapping to the formal roadmap clauses. `Evidence candidate` means a likely location to audit, **not proof of PASS**. Do not call a row passed until its exact code path, synthetic cases, CI and limitations are linked in the gate ledger. All original roadmap requirements still apply, even if not abbreviated below.

| Row | Formal stage | Evidence required for acceptance | Owner | Existing evidence candidate / gap |
| --- | --- | --- | --- | --- |
| B4-01 | R4 | Clean baseline and M00/M01/M04/X02 damaged R2 fixtures with independently scored candidate/edge TP/FP/FN/TN and UNKNOWN | B | Existing B synthetic suites; needs consolidated matrix |
| B4-02 | R4 | Corrupted and valid LFN/short aliases, deletion and orphan candidates; keep uncertain candidates visible | B | #125, #131 and older B tests; audit breadth |
| B4-03 | R4 | False parent edges, competing links, hidden windows, cycles, forged ledgers; no original-path assertions | B | #131, #136 and historical tests, forged-ledger trust issue unresolved by B alone |
| B4-04 | R4 | Source physical returned-byte coverage and incomplete/early EOF evidence, honest UNKNOWN, cost bounds | B+A | B independent test transcript #136, A shared meter #133–#135; **A controls receipt trust** |
| B4-05 | R4 | Versioned, reviewable B candidate/edge result used by A; tests against malformed input and repeatable CI | B+A | Current B module and R7 adapters; exact contract audit needed |
| C5-01 | R5 | Positive/negative ZIP and 3MF OPC/XML, corrupt/CRC and decoy controls, no original integrity overclaim | C | Existing ZIP/3MF parser tests, #130/#137 only narrow windows |
| C5-02 | R5 | Binary **and** ASCII STL, G-code positive/negative/bounded parser cases | C | Need comprehensive format coverage evidence |
| C5-03 | R5 | Non-oracle two-fragment search with hidden start/tail, opposite order, fragmented and decoy fixtures | C | Older two-fragment tests; restrictions/assumptions need exposure |
| C5-04 | R5 | Full generated-original SHA scoring vs structure-only checks, explicit TP/FP/FN/TN/UNKNOWN | C+A | #137 showed deliberately quarter-aligned 0/2/6 and off-grid UNKNOWN6; not general recovery |
| C5-05 | R5 | Physical returned bytes / unique reads / probes / candidates / time and bounded memory, no false success at EOF | C+A | Existing C quota and A #133/#134; audit shared costs |
| C5-06 | R5 | Reviewed bounded opt-in feature usable as an actual module or clearly specified adapter, not just `tests/` trial | C+A | Current sparse windows research_only, other data-region test-only; feature bridge missing or unproven |
| D6-01 | R6 | Baseline M00/M01/M02/X02 and clean FAT/geometry fixtures, explicit unchanged SHA | D | Existing D synthetic regression |
| D6-02 | R6 | Mirrored identical corruption, missing/out-of-bounds links, remote anomaly, cycles and cross-link cases | D | #126, #132, #138 plus existing D cases; consolidated coverage missing |
| D6-03 | R6 | Separate BPB/VBR/FAT geometry hypotheses; malformed and conflicting boot/backup, no auto winner | D+A | A #135 conflict test; D numeric hypothesis audit |
| D6-04 | R6 | Actual and unique physical returned source bytes, partial/UNKNOWN far-away FAT entries and short read | D+A | #126 and A shared meter, ~0.07% paired sampled entries not a whole-FAT verdict |
| D6-05 | R6 | Stable bounded module contract, no automatic FAT1/FAT2 repair/copy selection; regression CI | D+A | Production D module exists, adaptive prototypes #132/#138 research_only; **no obligation** to promote a worse sampler |
| A7-01 | R7 | Versioned adapters consume **actual** B/C/D result shapes on a shared nonwritable source | A | Shared B/C/D gates #123/#128; integration readiness audit |
| A7-02 | R7 | Source-scoped candidate ID, ordered nonoverlapping bounded extents, candidate-ID/extent conflicts | A | Existing evidence merger and A #133; next: same ID with different extents |
| A7-03 | R7 | Physical returned source/validation receipt binding, dedup repeated reads and proper shared budget | A | A #133/#134 verified synthetic scoped source reads; not real authenticity |
| A7-04 | R7 | Missing/disagreeing evidence, fake geometry, wrong token, reordered input, premature EOF return UNKNOWN/partial | A | A #134/#135 and previous A synthetic gates; audited matrix needed |
| A7-05 | R7 | Distinct states: discovered / structurally consistent / partial / ambiguous / scorer byte-identical / unknown; **no original identity claim from source reads** | A | A synthetic oracle separate; ensure cross-module output preserves distinctions |
| A7-06 | R7 | Final finite public-safe result schema with numerical physical costs, reproducible shared Windows CI and docs | A | `docs/INTERFACE_V1.md` remains DRAFT; finalize reviewed adapter contract |

**Audit step:** create `docs/ABCD_GATE_LEDGER.md` owned by A, one row per ID above, status `PASS|PARTIAL|MISSING|BLOCKED`, precise test/code/CI links, remaining failure, next smallest PR. This is a working evidence index. A must add/expand rows if full original formal gate requires them; don't game the count by silently dropping requirements. First publish audit with honestly evidenced statuses, not fabricated completion counts.

## 3. Task-selection algorithm (applies to A/B/C/D)

At each continuation:

1. Fetch fresh main, branch, live Draft PR, own Issue, formal roadmap, this playbook and gate ledger. Check current concurrent authors before editing.
2. Select the **highest-priority unresolved acceptance row within your scope**, then state its exact ID, current evidence and one bounded deliverable. Finish the previous assigned work if already in flight; never discard a half-finished PR silently.
3. Prefer a measured **small production-facing guarded capability** and integrated synthetic positive/negative tests that closes the row. Existing implementation may already pass; document proof instead of rewriting code.
4. Experimental algorithm A/B only when an existing row is otherwise blocked or a concrete false-positive/unsafe case is proven. **No more fixed/midpoint/quarter window or adaptive FAT scheduling iterations merely because another hypothesis is imaginable.** Never remove legitimate negative controls to raise a metric.
5. Create Draft PR with section `Gate rows targeted`, `Previously missing`, `What changed`, `Exact Windows PS5.1/Privacy CI`, `Resource/Trust limits`, `What remains`. Mark `research_only` when test-only and do not imply a shipping feature.
6. A reviews exact final HEAD, safety, source provenance, license, comparable tests, CI; merges eligible PR only. After merge, A checks post-main CI, updates stage evidence and the authoritative top-of-file roster, and **assigns next smallest missing gate**.
7. If acceptance rows for a stage really all pass, A signs off implementation + tests + integration + documentation, records exact SHA/CI, and only THEN awards its official 10/15/10/10 weighted points.

**Research stop rule:** If one alternative fails to improve the target gate under a pre-registered comparable corpus, retain as `research_only` and return to missing acceptance rows. Further studies require a concrete new blocker or evidence deficiency, not novelty alone.

## 4. Measurements in every round

Report three separate numbers:

- **Official weighted stage completion:** currently **39%**, only full-gate PASS counts. Not user recovery success.
- **Acceptance checklist closure:** `verified PASS rows / all registered rows` plus per-stage missing/blocking list. Count only inspected evidence; otherwise explicitly `not yet audited`.
- **Production/usable capability readiness:** `usable guarded module|test-only|research_only|blocked`. B/C/D former informal 81/79/86% are older estimates, not formal completion or recovered-file percentages.

For each PR: exact HEAD and code path; source fixture/seed; actual and unique returned B; physical Read calls; probes/candidates; boundedness/time/memory where reliable; TP/FP/FN/TN/**UNKNOWN** with denominators; original SHA only in independent synthetic scorer; Windows PowerShell 5.1 + privacy CI and post-merge result. Do not count external oracle full-SHA as a source-authenticated real recovery.

## 5. Stage order and release/safety barriers

B R4 and D R6 may close independently in their own chats while C R5 implements the critical format/fragment workflow. A simultaneously prepares R7 adapters and checks those dependencies; R7 cannot fully pass until required R4/R5/R6 interfaces are accepted. A advances to R8 **only after all R7 original formal gate requirements are passed**. R8 uses synthetic/disposable **separate output only** and still requires strict path, reparse, create-new/overwrite, size, failure cleanup and independently verified SHA controls. Then R9 end-to-end and R10 handoff.

**Absolute safety:** GitHub and CI may access generated/deterministic artificial images only. The user's actual microSD and **sole ~31GB master IMG are NOT APPROVED for any read, hash, scan, copy, upload, repair, extraction, write or diagnostics**, regardless of how much artificial CI passes. No real-world recovery percentage. No physical-device handles, CHKDSK, auto-repair, unbounded scan, overwrite or automatic FAT winner/original-path selection.

## 6. Four-chat common continuation phrase

After this design is on main, the same prompt may be sent to each **existing, already-role-assigned** chat:

> 「Chappy FAT32 Recovery Lab の既存担当A/B/C/Dを維持。GitHub最新main、AGENTS.md、UNIVERSAL_WORK_INSTRUCTION、TEAM_DISPATCH、ABCD_GATE_CLOSURE_PLAYBOOK、ABCD_GATE_LEDGER、担当Issue/PR/CIを確認。研究PR数ではなく担当R4/R5/R6/R7の未達成ゲートを最優先し、最高優先の一行を選んで小さく実装・人工テスト・Draft PRまで進める。Aだけが最終HEAD Windows CI審査・統合・公式進捗更新。実microSDと唯一のマスターIMGは一切アクセス禁止。最後に対象ゲートID、変更、CI、次の不足条件、公式39%（変更時は合格根拠）を報告して。」

If a new conversation does not yet have a verified explicit role, give a **one-time assignment**; generic text does not infer B/C/D. Existing B/C/D chats keep their identity automatically.

## 7. A immediate dispatch after approval

A first checks this PR's exact-head CI, merges and checks post-main CI. Then **A creates the gate ledger / completes the first source-level evidence audit** and records current top-of-file live roster (not historical lines). A posts superseding P1 notes to Issues #71/#72/#73 **after** merging, so B/C/D can proceed independently without conflicting with older Work round instructions. New branches are created by their owning chats on continuation; A does not preemptively alter their in-progress branches.
