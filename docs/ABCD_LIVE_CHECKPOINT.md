# ABCD live continuation

At the start of this round, main was `ba55aea41e8d747589482de06b4ac6e0430ce61c`. [Baseline CI](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43066910836) passed 20 synthetic Windows PowerShell 5.1 suites and the privacy scan of 104 paths. R0–R3 passed their full gates, totaling 39% of the [roadmap](ABCD_SYNTHETIC_ROADMAP.md). The R7 grouping experiment is on main via #78. The live B/C/D adapters are pending.

The parallel work uses existing assignments #71 (directory), #72 (file format) and #73 (FAT). Their scopes and branches are in [TEAM_DISPATCH.md](TEAM_DISPATCH.md). Review the current draft heads, experiment evidence, and matching CI before deciding what to integrate. Then pin accepted schemas and connect the R7 adapters. R8–R10 are pending. Real-media testing remains NOT APPROVED.

## Parallel B/C/D round

| Team | Integration and disposition | Measured result |
| --- | --- | --- |
| B | #81, adopt_experimental, default off | TP1/FP0/FN0/TN2. X02 unevaluated. 4,096 directory-data bytes including the extra deleted-entry control. Geometry reads excluded. |
| C | #80, research_only | CRC found the P02 mismatch. Default and opt-in runs each yielded 2/4 exact 3MF matches. Five verified observations carried scoped integrity labels. |
| D | #82, research_only | M02 had one sampled difference. Four cases read 2,048 actual and unique bytes each. An injected short read returned 176 FAT bytes and stayed incomplete. |

The team PRs contain the reviewed heads, Windows PowerShell 5.1 and privacy CI links. Issues #71, #72 and #73 remain open for hierarchy controls, withheld-location fragment trials and broader FAT damage experiments, respectively. Only R0–R3 have passed every milestone gate, so weighted progress is **39%**.

## R7 synthetic live adapter

The first adapter maps the bounded C byte proposals into candidate grouping. It keeps B's declared size and D's partial FAT sample as independent observations. The P01 signatures with unknown lengths are counted outside byte proposals. In P02, the structural check stays separate from the scorer's original SHA mismatch. The adapter leaves candidate read spans empty where C does not report them. The central runner now also invokes D's standalone short-read test.

Next, bind actual read spans to candidates where modules can substantiate provenance, evaluate competing fragment orders using non-oracle inputs, and test a shared budget. R8 separate-destination export depends on those R7 gates.

## Team A R4-R6 research acceptance and R7 integration checkpoint — 2026-11-12 JST

**Source main before A review:** `d0138ffd7d94e308332a30fe7c364fa9979e0d80`. Team A inspected exact final-head diffs, source/license cards, synthetic A/B results and Windows PowerShell 5.1 + privacy CI, then left reviews and squash-merged:

| Track | Research-only merge and exact-head CI | What it establishes, and what remains unresolved |
| --- | --- | --- |
| B #71 | [PR #84](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/84) merged `04dc24ef`, [B Windows CI](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43074253483) + [privacy](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43074253464) PASS | 194/194 B assertions; new legitimate zero-size/start-cluster=9 counterexample produces **FP1** (TP1 FP1 FN0 TN1 selected warning records). The default-OFF metadata flag is **not** proof of corruption or FAT ownership; corrupted LFN falls back to partial short alias. |
| C #72 | [PR #86](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/86) merged `579027d6`, [C Windows CI](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43075507333) + [privacy](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43075507313) PASS | Synthetic two-part 3MF ZIP candidate without oracle start/tail offsets: TP3 FP0 FN0 TN1 **over four enumerated pairs only**; source layout still assumes known format, two pieces, fixed 512-byte first part, sector-aligned locations, in-sector EOCD and bounded 64KiB window. Not default extraction or generic recovery. |
| D #73 | [PR #85](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/85) merged `f39bdfe0`, [D Windows CI](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43074979262) + [privacy](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43074979314) PASS | One bounded mirror+chain synthetic candidate catches identical-mirror FAT cycles missed by mirror-only. Four scorable selected cases baseline TP1 FP0 FN1 TN2 vs candidate TP2 FP0 FN0 TN2; M05 crosslink and X02 payload truncation remain **unknown**. More physical read calls, no automatic FAT winner or repair. |

A **central Windows isolated regression** now adds D's R6 P2 test as a standalone child process; B and C additions are already invoked through their owned test entrypoints. That central test must pass at final A PR head and post-merge main; record links when available rather than assuming success.

**Release gate status:** only R0-R3 pass fully = **39% weighted milestone completion**. R4/R5/R6/R7 each gained tested research evidence, but their complete acceptance gates have **not** passed. Issues #71/#72/#73 remain open. R7 still needs observable source read-span provenance, independent fragment-order evidence, and a single shared resource budget before R8 can begin. The local real-media gate remains **NOT APPROVED**; sole 31GB master IMG/physical microSD untouched by this work.
