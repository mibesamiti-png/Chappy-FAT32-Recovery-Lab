# Synthetic damage benchmark R1 — Team A

**Status:** experimental CI fixture, artificial data only. Never run against the original microSD or the user's 31GB master IMG. The percentages in this document are **known-case synthetic byte comparison**, not real recovery success rates.

## Goal

Measure two different outcomes that are commonly confused:

1. **Candidate located** — the FAT-independent C scanner finds a plausible G-code or ZIP/3MF start offset and length.
2. **Original bytes matched** — reading the returned candidate extent from a disposable artificial IMG yields bytes identical to the *known originally generated artificial content*, compared individually byte-for-byte.

Structural ZIP/3MF validation, a plausible FAT chain or a matching copied-file SHA alone do **not** prove the original file is intact.

## Fixture

The test creates a disposable **2 MiB FAT32-like research IMG** under the Windows TEMP directory; it is not a fully standards-formatted FAT32 card. It includes a minimal artificial MBR/BPB, two FAT arrays, a root directory with two 8.3 artificial records and contiguous original G-code + a three-part DEFLATE 3MF/ZIP generated in memory.

For each scenario the test clones the bytes, mutates only predetermined regions, writes a new artificial IMG in TEMP and opens that IMG with `FileAccess.Read`. It calls B's FAT-independent candidate scanner, D's independent root FAT chain and directory/FAT numeric checks, and C's bounded carving candidate scanner. The test reads candidate slices **in memory**, compares them against the original clean content, checks source SHA-256 unchanged, and deletes all fixtures at the end.

No real image, real filename, original file content, extraction, optional export API, or repair mechanism is used.

## Seven deterministic damage scenarios

| Case | Deliberate synthetic change | Expected originally byte-identical slices, out of 2 |
| --- | --- | ---: |
| clean | No damage | 2 |
| both_fats_bad | Both FAT copies' root chain set to `EB 58 EB 58` pattern | 2 |
| fat1_bad | Only FAT1 root chain corrupted, FAT2 remains plausible | 2 |
| gcode_body_modified | Replace one ASCII command value, still syntactically plausible | 1 |
| 3mf_deflate_modified | Flip a DEFLATE payload byte while retaining intact ZIP headers | 1 |
| 3mf_eocd_missing | Remove end-of-central-directory record without removing payload | 1 |
| gcode_missing | Zero-out G-code bytes while leaving directory metadata intact | 1 |

**Expected synthetic fixture total: 10/14 original-byte-identical candidate slices (71.43%)**. This number is *not a recovery rate*: the intentionally corrupted content is not reconstructed, the chosen corpus is tiny and deterministic, and candidate copying is not an export/recovery of arbitrary files. The test fails CI if the known-case result changes unexpectedly.

The DEFLATE mutation proves why a ZIP can remain **structurally verified** while its byte content differs from the known original: CRC/decompression was not verified by the scanner. FAT-corruption-only cases test whether FAT-independent carving can still find intact contiguous content. D's compatible FAT/directory evidence is intentionally not treated as content-integrity proof.

## Windows synthetic CI

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SyntheticDamageBenchmark.ps1
```

The central `runner/Invoke-ChappySyntheticRegression.ps1` includes the benchmark alongside QuickProbe/B/D/A synthetic tests. **Only use actual matching Windows CI as evidence that it passed**; merely committing the test does not establish success.

## Next validation steps

- Add a separately scoped fragmentation / non-contiguous cluster corpus and compare known source-body reconstruction with carving-only slices (which should often fail).
- Test generated 3MF containers with valid ZIP structure but payload decompression or per-entry CRC failure; avoid treating CRC32 as a guarantee.
- Consider large randomized artificial geometry/failure combinations with deterministic seeds, aggregate failure classifications and clear CI resource caps.
- Before any user-owned IMG is read, complete and review `docs/LOCAL_READONLY_APPROVAL_GATE.md`; no synthetic benchmark result grants permission.

## Actual CI observation — current Draft PR #22 (NOT ACCEPTED)

A Windows PowerShell 5.1 CI run of the seven artificial scenarios on benchmark head `3ba48ac1e338aff33dfee53fc6d866db837ae3f1` **failed as intended**, because the combined C scan misses earlier G-code when a later valid 3MF is found in the same scan block: [Actions #42986714746](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42986714746).

| Metric | Expected from known fixture | Observed before C repair |
| --- | ---: | ---: |
| Known artificial file instances | 14 | 14 |
| Candidate slices byte-identical to clean source | 10 | **6** |
| Artificial scenario count | 7 | 7 |
| Scenarios with unexpectedly low original-byte matches | 0 | **4** |

Missing matches occurred on the clean, both-FAT-corrupted, FAT1-corrupted, and DEFLATE-content-modified cases. The latter case found a structurally verified ZIP with changed payload bytes; neither a structure check nor matching copied-file SHA can establish original file correctness. The 3MF-without-EOCD test found its G-code again, because the valid later ZIP interval no longer suppressed earlier G-code.

**Reproduction and fix are owned by Team C [Issue #23](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/23).** This A PR stays Draft/red; never lower strict expected values to make it green. Only after C's independently reviewed fix is merged may A re-run this benchmark against current main and promote it if tests pass.

Even the expected 10/14 result is a selected corruption-corpus figure, **not** the user's microSD recovery rate, and no full reconstruction of damaged bytes is provided.
