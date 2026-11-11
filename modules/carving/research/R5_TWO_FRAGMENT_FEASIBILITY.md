# Team C R5 — Two-fragment finite-candidate feasibility (research only)

**Issue:** #46 | **Baseline:** main `8fd97ce7306d7296f203c4561ff730b046e0c9ce` | **Windows runtime:** PowerShell 5.1 / built-in .NET | **Mode:** synthetic-only, test-private, no production helper

## R0 source and license provenance

| Existing approach | Primary source | Applicability / failure | Source/license status |
|---|---|---|---|
| Garfinkel 2007, object validation / bifragment gap carving | https://www.sciencedirect.com/science/article/pii/S1742287607000369 DOI:10.1016/j.diin.2007.06.017 | Finite two-fragment trials with fast file-format filters; ambiguous text and candidate explosion remain major risks | Paper open access Creative Commons notice; exact downstream code rights not assumed; **ideas only, no copied code/text** |
| CGSecurity PhotoRec content carving | https://www.cgsecurity.org/wiki/PhotoRec_Data_Carving and https://github.com/cgsecurity/testdisk | File header/footer and format-specific validation; text starts unreliable, fragmentation remains difficult | **GPL-2.0** upstream code; **no source copied** |
| 3MF Consortium Core Specification v1.4.0 (2025) | https://3mf.io/spec/ and https://github.com/3MFConsortium/spec_core | ZIP/OPC container structure; intact ZIP/CRC is not proof that these were original bytes | Official `spec_core` source **BSD-2-Clause** (https://raw.githubusercontent.com/3MFConsortium/spec_core/master/LICENSE); no spec source/text/code copied; essential-patent royalty-free claim does not itself waive copyright |

These are independent research inspirations. No third-party C source or implementation is imported. The project has no assumed public code license, and Team A reviews any later reuse/redistribution obligations.

## R1 frozen fixture and baseline

- Deterministic tiny **128KiB FAT32-like** synthetic arithmetic model from C R4 tests, **not a standards-compliant mountable FAT32 volume**. Artificial 512B clusters; invented G-code first part at byte 20,480 and continuation at 40,960, plus 3MF first part at byte 61,440 and continuation at 90,112. First fragment exactly 512B; second <=512B.
- Independently generated original artificial byte arrays are held ONLY inside `modules/carving/tests/Test-ChappyCarving.ps1`; no actual user names, file data, disk bytes, master IMG or physical SD used. Full input files and known original SHA-256 remain test-private; artificial source SHA invariance checked.
- **Baseline:** `Get-ChappyCarvingCandidates` on the unchanged physically discontiguous artificial image, default parameters in R4 test (`Scan` helper) and `-EnableSmallDeflateCrc` OFF. No FAT chain inference, no fragment reassembly. Expected no byte-complete original candidates at fragmented start offsets.
- **Candidate method:** test-only `Test-R5FiniteSyntheticPairs` with one first slice and at most 8 **explicitly provided** second offsets. Each slice <=512B; total source byte budget <=8192B; pair validator uses at most 1024B joined in-memory bytes with C's existing G-code/3MF classification under bounded 4096B validation window, extra validation reads <=8192B, `MaxProbes=8`, `MaxWorkMilliseconds=1500` per pair, 3000ms cooperative loop bound. The candidate stream is non-writable; no file path, export, filesystem access or production API changes.
- Critical fairness limitation: the candidate experiment receives an **oracle-like short list of possible second offsets supplied by the test**; the baseline scanner is not supplied those offsets. Therefore a higher byte-match count illustrates **conditional feasibility only**, not improved search accuracy on a real 31GB source. Physical file-fragment discovery is a separate, unimplemented problem.

## R2/R3 controlled cases and scoring policy

Five predetermined invented two-fragment evaluations; the initial two-fragment lookup window is the same artificial input bytes for each baseline and candidate comparison, with one deliberately modified decoy version. Baseline and candidate differ in access to *enumerated tail-offset hints*; do **not** compare CPU costs as if both performed equal search.

| Case | Expected outcome | Independent original-byte truth |
|---|---|---|
| G-code + valid tail and zero decoy | one_possible, 1 accepted | true candidate byte-identical |
| G-code + true tail and syntactically plausible altered tail | ambiguous, 2 accepted | one true; one **false positive** |
| 3MF + correct ZIP tail and zero decoy | one_possible, 1 accepted | true candidate byte-identical |
| 3MF + true tail and altered *central-directory metadata* tail | ambiguous, 2 structurally accepted | one true; one **false original-byte match** despite structurally valid ZIP |
| 3MF + zero tail only | unknown, 0 accepted | true fragment not in candidate list, **false negative** |

Observed Windows PowerShell 5.1 synthetic result ([Actions #43029961046](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43029961046), tested head `6a04168d5de03c148ea0f0eae95739bdd4127401`): across **9 candidate-pair trials** in **5 selected two-fragment scenarios**, **TP4 / FP2 / FN1 / TN3**, pair acceptance precision 4/6 and known-case recall 4/5. Candidate method found **4** byte-identical original artificial pairs, but only **2** cases had one unambiguous format-consistent choice; 2 cases remain ambiguous and 1 case unknown. The contiguous-only baseline had **0/5** byte-complete originals on those fragmented scenarios. Logged total artificial source reads **4,070 bytes**, independent **in-memory validator reads 17,638 bytes**, sum of per-case elapsed time **107ms** (Windows runner-specific; not a latency guarantee). Non-writable inputs; candidate pair cap and source byte guard passed. **Different supplied candidate-offset hints mean this is conditional pairing feasibility, not a general runtime/detection A/B improvement.** These hand-picked cases are not real recovery statistics.

- A plausible candidate is deliberately labeled only `pair.format_consistent`; one possible result remains `one_possible`, NOT a verified original. Two possible results become `ambiguous` and are NEVER auto-selected. No replacement of production scanner and no export output.
- Negative cases reject writable source, >8 pair offsets, outside-stream offsets and over-budget source bytes. Actual bytes read/validation bytes and elapsed time are recorded independently; core C read/probe caps and existing R4 synthetic regressions stay unchanged.
- G-code grammar is only a weak heuristic. Valid ZIP structure, valid CRC against ZIP metadata, or a matching SHA of artificial candidate bytes never certifies unobserved real original-file provenance.

## R4 adoption request

Recommendation **research_only** unless Team A independently finds additional metadata evidence to restrict real fragment offsets and rule out ambiguous but structurally valid decoys. No automatic fragment reassembly, no new default-on switch, no real-image approval. Team A alone decides adoption, pending final-head Windows C and privacy CI.
