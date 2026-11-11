# Team D R1 — FAT32 management-structure diagnosis (read-only)

**Scope:** independent diagnosis of the observed `EB 58` pattern, image-offset mistakes, FAT1/FAT2 agreement, boot field validation, root chain anomalies, and cautious candidate generation. **No repair writes and no automatic changes.**

## Preliminary finding: EB 58 is not independently proof of damage

- A FAT32 *volume boot record* often begins `EB 58 90` (jump instruction).
- The *start of a FAT* should instead contain the FAT reserved entries (`FAT[0]` media and `FAT[1]` state). `EB 58` repeated at the predicted FAT location conflicts with a healthy reserved entry, **if the offset/geometry are correct**.
- FAT1 == FAT2 only establishes agreement, not correctness. An imaging mistake, shared damage, or wrong base offset may affect both.
- Distinguish **16 consecutive `EB 58` pairs** from a single boot `EB 58 90` prefix. Inspect the 512-byte context before concluding anything about root causes.
- R1 probes volume offsets 0, MBR partition starts, and conventional 512/32256/1048576/2097152/4194304 byte candidates. Candidate byte offsets near each expected FAT start are probed within +/-4096 bytes and selected small shifts; this is *not* an exhaustive scan.

## Procedure (Windows PowerShell 5.1)

```powershell
Import-Module .\modules\fat-analysis\Fat32ReadOnly.psm1 -Force
$r = Get-TeamDFat32Diagnostic -ImagePath 'C:\path\to\master.img'
$r.SelectedBoot | Format-List
$r.FatHeaders | Format-List
$r.NearbyOffsets | Format-List
$r.Findings | Format-Table -AutoSize
$r.RepairCandidates | Format-List

# Writes a report file only; opens the IMG read-only.
Export-TeamDFat32Diagnostic -ImagePath 'C:\path\to\master.img' -ReportPath 'C:\path\to\teamD_report.json' | Out-Null

# Explicit override only if volume start is independently verified (in bytes):
Get-TeamDFat32Diagnostic -ImagePath 'C:\path\to\master.img' -VolumeOffset 1048576

# Self-contained synthetic fixtures; do NOT point tests at real images:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\modules\fat-analysis\tests\Run-TeamD.Tests.ps1
```

## Report interpretation

| Field | Meaning |
|---|---|
| `Image.FirstSampleSha256/LastSampleSha256` | Partial image fingerprints **only**, not whole-file SHA256 |
| `BootProbes` | Candidate geometries; invalid candidates are retained as evidence |
| `SelectedBoot` | Geometry that passed plausibility checks; NOT proof of authenticity |
| `FatHeaders` | Reserved-entry checks and explicit `EB58PairRepeated16Times` and `LooksLikeBootSector` flags |
| `NearbyOffsets` | Nearby plausible FAT headers or boot headers, for **manual review** |
| `FatComparison` | Compared bytes, difference count and samples, whether comparison reached the full FAT size |
| `RootChains` | Independently traced root chain on each of first two FATs; capped at 4096 entries |
| `RootDirectory` | First 32 entries in first root cluster, **not** complete directory recovery |
| `RepairCandidates` | Hypotheses / manual-investigation next steps; **all** `WritePermitted=false` |

**Confidence is qualitative:** low = insufficient independent evidence, medium = plausible diagnostic next step; no confidence category certifies data correctness. A mismatching FAT is not necessarily the incorrect one, and mirroring may be disabled.

### Evidence required before proposing any byte changes

1. Compare MBR/VBR offsets against acquisition logs and independently captured source sectors.
2. Validate BPB geometry, backup BPB, FAT copies, root directory contents, and file data together.
3. Establish why the proposed bytes are correct; never infer that from a matching FAT copy alone.
4. Record the exact input hash (whole image), source provenance, proposed range-level changes and expected before-bytes in a separately approved manifest.

## R2 — synthetic-only in-memory patch and rollback experiment

**Implemented in** \`Fat32SyntheticSimulation.psm1\` with tests \`tests/Run-TeamD-R2.Tests.ps1\`.
This is **not** a repair tool for a disk, a 31 GB master IMG, or even a user-provided working IMG.
It accepts only a small artificial \`byte[]\` (4 KiB .. 8 MiB) with a deliberately stamped
\`CHAPPY-SYNTH-R2\` marker at byte 480, a valid test VBR signature,
512 B/sector, and exactly two FAT regions within the synthetic buffer.
The marker is a **test guard, not a cryptographic authenticity proof**. No file-path
parameter, file-opening API, physical-disk API, or file-writing API exists in this module.

A proposal explicitly specifies \`FatIndex\`, \`EntryIndex\`, \`ExpectedValue\`,
and \`ProposedValue\`. Up to 32 non-overlapping 4-byte aligned FAT-entry patches are
allowed. Proposal creation verifies all old bytes, checks the geometry and computes the
entire artificial input SHA-256. Invocation validates the same hash, all expected bytes,
their computed offsets, and the manifest hex **before** modifying a cloned byte array.

The result contains before/after whole-buffer SHA-256, per-entry byte diff, changed-byte
count, cloned simulated byte array, and a reverse (rollback) plan constrained to the
resulting hash. The original input remains unchanged. Rollback is itself an in-memory
simulation and returns a second clone; tests confirm the original SHA-256 is restored.

\`\`\`powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\modules\fat-analysis\tests\Run-TeamD-R2.Tests.ps1
\`\`\`

**Explicit non-goals:** no real image patching, no work-copy writes, no automatic
repair inference, no private IMG access, no recovery-success claim. The old R1
\`RepairCandidates\` remain investigative hypotheses and are **never converted
automatically** into byte patches. The R2 before/after manifest may be exported
to JSON only after selecting report fields that exclude \`SimulatedImageBytes\`.
A separate approved design would be required before any work-copy disk simulation.

## Limits

- No inference of exact failure cause from `EB 58` alone, no physical microSD access, no automatic repair or source mutation.
- MBR heuristic only; GPT, extended partitions, unusual sector layouts, and exhaustive offsets are not covered.
- Directory scan is limited to first root cluster; LFN and deleted entries are not reconstructed by Team D R1 (Team B handles recovery).
- FAT mirror diff compares at most 64 MiB by default. Inspect `Complete` before claiming the entire FAT matched.
- Large IMG file length checked, but no full image hash; obtaining full hash on a 32 GB IMG is a separate read-only operation.
- FAT32 reserved-state bits are accepted, but cluster graph validation is focused on root chain.
- Native Windows PowerShell 5.1 runtime tests should be run via the Windows CI workflow before merging.

## References

- libyal libfsfat format reference: https://github.com/libyal/libfsfat/blob/main/documentation/File%20Allocation%20Table%20%28FAT%29%20format.asciidoc
- ChaN, FAT filesystem structures: https://elm-chan.org/docs/fat.html

Local-only opt-in: `-IncludePrivateMetadata` reveals image path and directory names in local output; do not upload such reports.