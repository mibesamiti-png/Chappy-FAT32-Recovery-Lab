# Team A synthetic evidence baseline

This regression freezes the current B/C/D observations for R7 preparation. Final adapters depend on the reviewed submissions from #71, #72 and #73. Run `powershell.exe -NoProfile -File tests/Test-A3DEvidenceBaseline.ps1` in the repository.

The test passes the same non-writable generated image to the B directory scan, C carving scan and D mirror sampler. The independent scorer alone sees the oracle. The table shows observed outcomes at seed 202611.

| Case | B declared 3MF size | C structure | D differences in first 128 FAT entries | Full 3MF SHA equals original |
| --- | ---: | --- | ---: | --- |
| M00 | 887 | verified | 0 | yes |
| M02 | 887 | verified | 1 | yes |
| M04 | 0 | verified | 0 | yes |
| P02 | 887 | verified | 0 | no |

B reads the 512-byte root window. C uses a 65,536-byte scan cap plus up to 32,768 bytes of validation rereads and observed 74,070 bytes per case. D compares 1,024 bytes across both copies. These are module-reported counts. Geometry reads and oracle scoring are outside those counts. B and D report incomplete coverage.

## Adapter acceptance checks

- Preserve declared directory size, proposed byte extents, format checks, mirror observations and oracle match as separate facts. Module confidence stays scoped to its check. Preserve contradictory facts on the same candidate and report uncovered regions.
- Bind proposed candidates to one input and ordered, bounded, in-range extents. Equal starts, equal lengths and filenames alone cannot establish that candidates represent the same original. Preserve competing extent orders and lengths.
- Bind observations to the input, physical ranges and the observation they depend on. Repeated observations of the same bytes, including shared BPB reads, provide one origin for confidence. Keep interpretation codes as annotations and retain overlaps for audit. Add separate counters for charged reads and unique bytes only where actual ranges are measured.
- Expose original-byte identity only after an independent full-candidate SHA comparison in the synthetic scorer. Exercise P02 as a regression for structure-only verification, M04 for conflicting length, and M02 for a disagreement with intact payload. After module review, add cases for missing evidence, ambiguous fragment orders, reordered input and tight shared limits.

## Candidate grouping experiment

`tests/helpers/Merge-A3DSyntheticEvidence.ps1` tests a normalized input boundary for one synthetic image. It groups equal format and ordered extents, retains different orders, and returns the set of checks without assigning an overall confidence. Identical observed ranges are grouped and overlapping ranges contribute their union to the unique-byte count. Original identity remains in the independent scorer. The regression covers reordered proposals, conflicting checks, missing observations and rejection of out-of-range or overlapping candidate extents and excess proposals.

The helper uses supplied synthetic observations. The live module baseline above measures each module independently. Connecting module outputs to the grouping boundary requires review of the evidence and provenance available from #71, #72 and #73.
