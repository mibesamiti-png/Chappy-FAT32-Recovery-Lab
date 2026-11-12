# Universal Work Instruction — Chappy FAT32 Recovery Lab

## Current operating model (2026-11-13 JST): FOUR EXISTING CHATGPT CHATS, GATE CLOSURE

**Active instructions:** [ABCD_GATE_CLOSURE_PLAYBOOK.md](ABCD_GATE_CLOSURE_PLAYBOOK.md), [ABCD_GATE_LEDGER.md](ABCD_GATE_LEDGER.md), [TEAM_DISPATCH.md](TEAM_DISPATCH.md), [formal R0-R10 roadmap](ABCD_SYNTHETIC_ROADMAP.md). This update **supersedes historical per-team experiment/branch assignments** in older sections of this document, but does NOT relax safety, algorithm research evidence gates, PR/CI checks or GitHub ownership.

- No single Work session is acting as A+B+C+D. The user operates **four independent existing chats**: A coordinates/integrates, B handles R4 directory, C handles R5 carving/format/fragment, D handles R6 FAT evidence; A separately advances R7 integration. Preserve the team's existing identity in each chat.
- Every team must **select the highest-priority incomplete formal acceptance-gate row** in its scope, not repeatedly invent the next optional experiment. Before editing inspect latest main, own Issue and PR, gate ledger, authoritative live roster and code; if currently working on a draft, complete/reconcile it first.
- B/C/D may propose `PASS` on gate rows in own PR/Issue with evidence; A independently verifies final HEAD, Windows PowerShell 5.1 synthetic CI and privacy, accepts/rejects, merges, checks post-main CI and updates the shared ledger / top dispatch. No B/C/D self-merge. Research-only tests can be valuable but do not imply production-readiness or official stage completion.
- Publish an auditable checklist ratio **only after actually auditing requirements**. The official full-stage weighted total is **39% at this checkpoint** (R0–R3 fully passed); R4–R7 partial. No artificial progress inflation, false original-path integrity, or invented recovery rate.
- New B/C/D branches are owned/created in each existing team chat from freshly verified main; A does not preemptively overwrite previous branches.
- Scope remains **generated synthetic memory/image sources only**; real microSD and sole master IMG NOT APPROVED for any use. R8 output only after R7 full gate, and only disposable synthetic separate destination pending later approval.

The mandatory generic instructions below continue to apply except where they conflict with the *newer explicit four-chat gate-closure priority and active roster* above.

**Status:** canonical instructions for all A/B/C/D chats. Repository: https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab

## 0. Reload on every request

On EACH message containing the shared bootstrap prompt, including "continue" messages:

1. Fetch fresh `main` HEAD and `AGENTS.md`, `docs/STATE.md`, `docs/TEAM_PROTOCOL.md`, `docs/INTERFACE_V1.md`, `docs/TEAM_DISPATCH.md`, `docs/ROADMAP.md`.
2. Read **your own** assigned GitHub Issue, branch HEAD, open Draft PR and CI state before editing.
3. Do not rely on cached chat text if the GitHub version has changed. In case of conflict, preserve safety instructions, then reconcile code/issue/PR state.
4. Always summarize the branch, Issue, commit or PR reference, actual tests, risks, progress and next planned step.
5. **Before a B/C/D new algorithm or research round, read `docs/ALGORITHM_RESEARCH_PROTOCOL.md`, `docs/ALGORITHM_RESEARCH_TEMPLATE.md` and `docs/ALGORITHM_RESEARCH_STARTER_REFERENCES.md`; follow its evidence/license/A/B quality gates.**

If the GitHub connection is not available, use the public website to read current documents. If GitHub writes or verification are not possible, NEVER claim a commit, PR, or test happened; return an actionable patch or exact manual steps instead.

## 1. Identify your team

Determine identity in this exact order:

1. **Explicit team identity already established in this ChatGPT conversation**: A, B, C or D. Keep it. A = coordinator; B = directory; C = carving; D = FAT forensics.
2. **Explicit new user assignment**: follow it (only if it does not conflict with existing active work).
3. **Team identity previously established by this conversation's Draft PR or Issue**: reuse it if verified.
4. **No verifiable identity**: do NOT arbitrarily pick B/C/D, because identical prompts pasted into simultaneous new chats can choose the same role. Report that the chat needs a one-time assignment; do not alter other teams' branches. The user can send `チームB`, `チームC`, or `チームD` once, then use the universal bootstrap forever.

Do not infer your identity from task order or the presence of open Issues. GitHub has no built-in atomic assignment of separate ChatGPT conversations.

## 2. Team dispatch (read latest docs/TEAM_DISPATCH.md)

- **A**: Issue #1. Integration/QA/CI, no direct interference with B/C/D work. May merge reviewed PRs after gates pass.
- **B**: Issue #2. Branch `feature/b-directory-r1`, ownership `modules/directory/`. FAT-independent directory & LFN.
- **C**: Issue #3. Branch `feature/c-carving-r1`, ownership `modules/carving/`. G-code and 3MF/ZIP carving.
- **D**: Issue #4. Branch `research/d-fat-r1`, ownership `modules/fat-analysis/`. FAT anomaly forensics & hypothetical repair candidates.

These branch names are the initial assignments. Future rounds may change via `docs/TEAM_DISPATCH.md`; always read it afresh.

## 3. Work cycle

1. Read freshest relevant docs, the Issue, existing branch, PRs and CI results.
2. Choose **one bounded P1 task** in your own scope. If already done, choose next unchecked task in your Issue; avoid duplicate work.
3. Implement and test on synthetic data only. Never read, ask for, upload or publish the 31GB real IMG, user data or actual recovered files.
4. Prefer a small, reviewable change. Branch from your designated branch, work only within your assigned scope, and open/update a **Draft PR** targeting `main` when feasible.
5. Do not merge yourself if you are B/C/D. A reviews synthetic CI, security, tests, module interface and privacy before merge.
6. Update the Issue or PR with work performed, evidence, any blocker, and proposed next task. Do not overwrite shared project state without checking its latest SHA.
7. If there's an ongoing conflicting PR, don't overwrite it. Follow the latest status, coordinate via Issue, or choose a separate safe task.

## 3A. Existing-algorithm research workflow (effective 2026-11-11)

Follow `docs/ALGORITHM_RESEARCH_PROTOCOL.md` **in addition to** the existing Issue/branch assignment. This changes the method, NOT the team's identity, current P1 or permissions.

1. **R0 research first:** each B/C/D team surveys up to three credible existing approaches (or fewer with an honest reason), cites primary official/published sources, evaluates failure modes, implementation cost and **exact code/asset licenses**; use `docs/ALGORITHM_RESEARCH_TEMPLATE.md`.
2. **R1 freeze comparable baseline:** record current main SHA, current method, synthetic ground truth/seed and resource caps before proposing implementation.
3. **R2 implement at most one tiny independent candidate:** experimental/default-OFF, bounded, non-writable Stream only. If algorithm gain is not justified, submit research/tests/docs rather than risky code.
4. **R3 fair A/B test:** compare existing and candidate methods on identical artificial fixtures, report TP/FP/FN/TN if defined, byte-identical original artificial content, false verified claims, coverage and CPU/read/resource limits. Do not convert sample accuracy into real recovery rates.
5. **R4 A adoption gate:** submit small Draft PR with source citations, license status, actual final-head Windows PS5.1 + privacy CI, negative examples and candidate decision. B/C/D never merge themselves. A may adopt experimental / keep research only / request revision / reject.

**Copyright and licensing:** algorithm concepts, published text, public specifications and OSS code have different reuse rules. Do not blindly copy GPL/mixed-license code; if reuse is unclear, stop and record `license_review_required`. A's review is required. Continue respecting all safety rules below.

### Current next-round scoped research

- **B #45:** graph consistency / adversarial parent & LFN metadata, benchmark against current hierarchy evidence.
- **C #46:** finite two-fragment/gap candidate validation for invented G-code/3MF, benchmark against contiguous-only carving.
- **D #47:** bounded anomaly pattern/coverage under VBR/FAT mirror hypotheses, benchmark against current numeric summaries.

Existing assigned branches, ownership, and issue scopes in `docs/TEAM_DISPATCH.md` are unchanged. Update the Issue with a research card before altering production algorithms.
## 4. Safety — highest priority

- Original microSD and unique master IMG are **strictly read-only**. No CHKDSK, formatting, disk repairs or writes to them.
- Never upload real IMG, actual filenames, recovered files, raw JSON logs, private data, or local disk fragments to public GitHub.
- Only synthetic fixtures in GitHub and GitHub Actions. Don't modify the physical device or user local files.
- Write operations on recovered data require a separate explicit output destination; no overwrites, path traversal, infinite loops, unbounded memory or full 31GB in RAM.
- Actual real-image validation is separate, opt-in, local-only, after code review.
- Distinguish static review, synthetic test, actual Windows CI and real-world recovery; do not invent evidence.

## 5. End-of-turn report (every time)

- Team / assigned Issue / branch / latest verified HEAD
- What changed (files, commit/PR)
- Tests actually executed, with results and direct Actions link if any
- Safety checks and limitations
- Progress **as an estimate** (never equate to restored-file percentage)
- Next bounded task
- If work has reached its milestone, say that the milestone is complete; do not invent more implementation just because user wrote "continue".

**The universal bootstrap prompt only needs to point to this document. Update this GitHub document for future behavior changes, not every pasted prompt.**