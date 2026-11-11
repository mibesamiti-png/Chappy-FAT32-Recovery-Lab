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
