# Team D R4-P1 — read-only MBR/BPB/backup VBR/FSInfo geometry trust guards

**Scope:** [Issue #25](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/25), synthetic-only. No real disk/image scan is approved. Team A must review the Draft PR before merge.

## API and safety
`Fat32GeometryTrust.psm1` exports `Get-ChappyFatGeometryTrust -Stream <nonwritable-seekable-stream> [-PartitionIndex 0..3] [-MaxReadBytes 512..2048]`.

- Does **not** open paths or disk handles, write, patch, extract, reformat, repair, or authorize any operation against the user's microSD or unique 31GB IMG.
- Reads only the 512-byte MBR at offset 0, the selected MBR FAT32 partition's first 512 VBR bytes, and — only when within the claimed reserved region and partition bounds — at most 512 bytes each from the backup VBR and FSInfo sector.
- A single requested probe is never more than 512 bytes. The sum of actual read bytes is limited by `MaxReadBytes` (default and cap: 2048).
- Supports synthetic memory streams that return short reads. Uses actual observed lengths; truncated and budget-omitted probes set `scanIncomplete`.
- No raw bytes, user filenames, source paths or source hash digests are returned. Only fixed reason/warning codes and numeric derived boundaries.

## Geometry constraints
- MBR signature `55 AA`; non-empty selected partition slot; valid boot flag; FAT32 MBR partition type `0B/0C/1B/1C`; partition interval must lie inside the stream.
- BPB boot-jump structure is checked **in addition to** signature; a fake `EB 58 90` alone is *not proof* of FAT32 or disk authenticity.
- Declared BPB bytes-per-sector one of 512/1024/2048/4096; power-of-two 1..128 sectors/cluster, 32 KiB max cluster size for this conservative experimental policy. MBR sector unit is fixed at 512; differing BPB sector size is explicitly rejected pending further format-aware review.
- FAT32 reserved-sector count, two FAT copies, nonzero FAT32 FAT size / total sectors, zero FAT12/16 legacy root entries and FAT16-length fields.
- Derived FAT1, FAT2, data start and BPB volume end must fit in the selected MBR partition and actual byte stream, leaving a data region.
- Data cluster count must fit FAT32 28-bit number space and the declared FAT must have at least data-clusters+2 four-byte entries; root cluster must be within derived data cluster count.
- Backup VBR and FSInfo positions must be within reserved sectors; FSInfo cannot point at backup VBR. The backup's core FAT32 geometry and boot signature/jump must match primary VBR.
- FSInfo lead, structure and trailer signatures are checked, and known free-count/next-free values must fit the derived data cluster count; `0xFFFFFFFF` denotes unknown.
- If evidence is missing due to I/O, truncation or budget, classification stays incomplete. A contradictory observation is reported via fixed reason code and `trustDecision=reject`.
- No branch outputs `trusted`: the best possible result is `plausible_unverified`. This **does not verify a real filesystem or authorize a real IMG scan**.

## Result schema
The v1 envelope uses `schemaVersion=1`, `team=D`, `status=ok|partial`, `scanIncomplete`, `errors=[]`, `warnings`, `metrics.bytesRead`. Additional fields include:
- `trustDecision=reject|insufficient_evidence|plausible_unverified`
- `mbr`: selected partition index/type and derived numeric byte interval
- `geometry`: predicted FAT1, FAT2, FAT length, data start, volume end, data cluster count (nullable when not computable)
- `backupVbrRead`, `fsInfoRead`, fixed-code `reasons`, fixed `observations`

When using synthetic fixtures, `plausible_unverified` means only that the inspected geometry checks have no detected contradiction; it is **not a proof of full FAT32 conformance or physical-media health**. A signature match at an arbitrary FAT offset is never used to replace the MBR-derived partition start.

## Synthetic Windows PowerShell 5.1 regression

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\modules\fat-analysis\tests\Run-TeamD-R4-Geometry.Tests.ps1
```

Fixture: fully artificial ~2 MiB in-memory MBR with a minimal FAT32-like volume beginning at offset 4096, primary and backup VBR, FSInfo and numeric geometry. Mutated cases cover misleading EB58 at a FAT start, invalid MBR/BPB signatures, partition type and boot flag, zero/oversized partition entries, wrong FAT-copy count and FAT sizing, invalid sectors/cluster, root out-of-range, invalid backup/FSInfo placement, backup VBR mismatch, FSInfo free count and hint mismatch, huge BPB size, broken/truncated MBR/VBR/backup, tight global probe budgets, and rejected writable stream. No real content or local IMG path is bundled.

**Limitations:** 512-byte MBR partition model only; no GPT/extended-partition support, no proof of BPB authenticity, and no live extraction. Additional geometry variants and robustness review belong in a future independently assigned scoped task. This code does not modify Team A's local preflight runner or weaken `docs/LOCAL_READONLY_APPROVAL_GATE.md`.
