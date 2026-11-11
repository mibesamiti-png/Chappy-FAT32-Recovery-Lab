# Team D P02 handoff — bounded FAT observations

**Tracking:** Team D, [Issue #73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73), branch `research/d-r6-synthetic-fat-evidence-20261112`. **Baseline main:** `ba55aea41e8d747589482de06b4ac6e0430ce61c`. **Scope:** deterministic artificial bytes only; no physical media or user image is read, hashed, copied, written, repaired or uploaded. Real-data approval remains `NOT APPROVED`.

## R0 — sources, provenance and rights

| Source | Relevant idea and limitation | License / reuse decision |
| --- | --- | --- |
| Microsoft, *FAT32 File System Specification* v1.03 (2000), copy at https://www.osdever.net/documents/fatgen103.pdf | FAT entry layout, cluster links and volume geometry. A bounded FAT window can compare only bytes actually observed; agreement cannot prove filesystem or file health. | Specification rights are distinct from software licenses. No text or code copied. |
| CGSecurity, TestDisk filesystem repair documentation: https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html and https://github.com/cgsecurity/testdisk | Primary/backup and FAT evidence are useful diagnostics, but a repair choice is outside this research. | TestDisk source is GPL-2.0. No source copied or imported; no repair command executed. |
| Sleuth Kit Labs, The Sleuth Kit: https://github.com/sleuthkit/sleuthkit and https://www.sleuthkit.org/sleuthkit/licenses.php | Independent forensic observations can corroborate one another; finite samples leave unsampled regions unknown. | Mixed component licenses require file-level review before reuse. No code copied or dependency added. |

These are three distinct primary project/specification sources. They motivate conservative evidence reporting; they do not establish an optimal sampling method. The public repository has no declared project-wide code license.

## R1 — frozen baseline and comparable inputs

- Frozen `main` is `ba55aea41e8d747589482de06b4ac6e0430ce61c`; no production algorithm is replaced.
- Fixture helper: `tests/helpers/New-Chappy3DDamagedFixture.ps1`, generator `A3D-damage-r1`, seed `202611`.
- Cases: M00 clean control, M01 valid 3MF chain fragmentation with both FAT copies updated, M02 one FAT1 3MF link cleared, X02 image truncated inside 3MF payload.
- The analyzer receives a read-only, seekable memory stream and the BPB/MBR-derived geometry record from `Get-ChappyFatGeometryTrust`; it does not receive the fixture manifest, original SHA, file extents, names or mutation offsets. The geometry parser rejects this deliberately FAT32-like fixture because FSInfo/backup VBR metadata is absent; its numeric geometry remains an untrusted observation only.
- Same configured limits for each case: geometry API cap 2048 bytes (1024 bytes observed), one mirror window of 128 entries, mirror read cap 1024 bytes. The scorer independently hashes the generated image before and after analysis and checks the returned report. A separate injected short-read run stops the read-only artificial stream at 1200 aggregate bytes.

## R2 — bounded research-only observation

The existing independent implementation is used without new FAT-selection or repair logic: R4 `Get-ChappyFatGeometryTrust`, then R3 `Get-ChappyFatMirrorWindows` over one 128-entry window per FAT. This is a baseline diagnostic experiment, not a proposed algorithm adoption.

`modules/fat-analysis/tests/Run-TeamD-P02Evidence.Tests.ps1` uses a read-only in-memory counting stream. The mutation manifest and hashes remain scorer-only. Actual returned-byte count and distinct physical offsets are measured independently. The experiment expects mirror equality in M00/M01, one difference in M02, X02 geometry rejection for a stream shorter than its declared volume, and `io.truncated_fat_window` under the separate short-read fault.

Interpretation limits: mirror equality does not establish correct or complete chains. In M01, a matching FAT pair is compatible with valid fragmentation but does not certify or reconstruct that chain. X02 truncates after both FAT windows, so mirror sampling alone can miss payload truncation; the geometry extent rejection must remain visible. A short read must remain partial and cannot be silently treated as equality.

No confusion matrix is claimed: this small diagnostic corpus distinguishes a sampled copy disagreement and geometry/read coverage failures; it does not score recovered files or establish a general FAT anomaly classifier. Any stronger strategy requires a separately bounded same-input A/B study and A review.

