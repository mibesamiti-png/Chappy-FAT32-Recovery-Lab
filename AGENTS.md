# Instructions for every A/B/C/D developer or AI

1. Read `README.md`, `docs/STATE.md`, and `docs/TEAM_PROTOCOL.md` before working.
2. Never upload, request, commit or paste the user's 31GB raw IMG, recovered files, private log files, sensitive file names, or raw data excerpts.
3. The Windows image file is local-only: AI chats and GitHub Actions cannot directly access it.
4. All code is experimental. Distinguish clearly between source inspection, synthetic tests, Windows tests, and real-image tests.
5. Default operations are read-only analyses. Extraction requires a separate explicit destination; no overwrites or path traversal. Never repair original microSD or master IMG.
6. Test synthetic fixtures for malformed FAT, out-of-range clusters, huge sizes, traversal, cycles, corrupt LFN, and truncated images. Constrain memory/time and recursion.
7. B owns `modules/directory/`, C `modules/carving/`, D `modules/fat-analysis/`. A owns integration and quality gates.
8. Use a distinct branch and draft PR; do not modify other teams' modules without coordinating.
9. Every PR reports changes, safety implications, tests actually executed, limitations, next actions, and progress as estimates not proof.
10. Never merge unreviewed destructive actions or publish real user content.
11. For newly studied algorithms in B/C/D, follow `docs/ALGORITHM_RESEARCH_PROTOCOL.md`: find primary sources, check licenses, freeze a baseline, compare one default-off experimental alternative on identical artificial fixtures, and have A decide. Use `docs/ALGORITHM_RESEARCH_TEMPLATE.md`. Never copy third-party code before license clearance.

## Universal bootstrap behavior

The authoritative shared startup / continuation instructions are `docs/UNIVERSAL_WORK_INSTRUCTION.md`; the copy/paste message is `docs/UNIVERSAL_BOOTSTRAP_PROMPT.md`. Teams must consult `docs/TEAM_DISPATCH.md` and **keep the role already assigned to their conversation**. A fresh unassigned conversation cannot safely infer a unique team from the same generic prompt; require an explicit one-time role assignment. Read current GitHub state on each continuation; do not trust old branch/Issue summaries.

## Current operating priority — 2026-11-13 four existing chats

Read `docs/ABCD_GATE_CLOSURE_PLAYBOOK.md` and `docs/ABCD_GATE_LEDGER.md` together with the *top* of `docs/TEAM_DISPATCH.md`. The original A/B/C/D ChatGPT conversations remain separate; no Work single-session orchestration. Prioritize closing a cited formal R4/R5/R6/R7 acceptance row, not maximizing research-only PRs. Preserve independent branches, final-HEAD Windows PowerShell 5.1 + privacy CI, A-only merges, and official whole-stage weighted progress. The real microSD and sole master IMG are **NOT APPROVED for reading/hash/scan/copy as well as any mutation or upload**. This line does not replace the older safety policies.
