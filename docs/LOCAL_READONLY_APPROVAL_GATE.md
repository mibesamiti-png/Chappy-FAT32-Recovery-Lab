# Team A: Real-master-image read-only approval gate

**Status: NOT APPROVED for the user's actual 31GB master IMG.** This document records the acceptance criteria for a future explicit, local-only check. All GitHub Actions use artificial IMG fixtures only.

## Current experimental runner

`runner/Invoke-ChappyLocalReadOnlyPreflight.ps1` exists as a proof of integration between B directory/hierarchy and D FAT mirror/EB58 modules. It accepts a regular local `.img` file only if the user explicitly supplies `-IUnderstandReadOnlyLocal`. Source is opened exclusively with `FileAccess.Read`; the command writes no output files and does no extraction or repair. Output is a numeric-only aggregate, not filenames or private content.

**A passing synthetic CI is not approval to run it on real data.** The tool might be incorrect for corrupted or nonstandard FAT32 geometries. The input file could already be changing for reasons unrelated to the tool. No real recovery success is established.

## Required before A authorizes first real-IMG local-only trial

- [ ] Review latest exact `main` SHA and verified Windows synthetic CI.
- [ ] Independently inspect source for write handles, output file creation, command injection, unmanaged device access, unbounded allocations and unbounded loops.
- [ ] Review `Get-ChappyFat32Geometry` handling of deliberately malformed MBR/BPB / misleading geometry before trusting offsets.
- [ ] Verify `FileAccess.Read`, `FileShare.Read`, and that all downstream modules receive the same non-writable stream.
- [ ] Verify explicit source-file path cannot target a physical device, remote UNC, reparse/junction path or the public repo.
- [ ] Avoid sharing the real IMG path, actual file names, raw directory records or unredacted JSON into GitHub, public CI, issues or PRs.
- [ ] Execute an artificial IMG fixture test **locally on the user's Windows computer** before any real IMG access; compare the fixture SHA-256 before/after.
- [ ] Record approval for one exact SHA, bounded flags and the single specific local diagnostic command. Do not silently expand scanning beyond the approved limits.
- [ ] Confirm the original microSD and the only master IMG remain off-limits for write operations. Do not invoke CHKDSK, format, repair or extraction into the source folder.
- [ ] Collect only a small, manually sanitized numeric summary if the user wishes to share results. Do not copy any raw logs automatically.

## How to check the test harness now

The following command only generates and tests a disposable, artificial FAT32 IMG in the Windows TEMP directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-LocalReadOnlyPreflight.ps1
```

This script verifies rejection of omitted consent, device paths, UNC/relative paths and .img files inside the repository; bounded FAT32 geometry, directory candidate, mirror and EB58 statistics; fixed-schema redaction; and unchanged artificial source SHA-256.

Do **not** treat a partial scan as proof that files are absent. Do **not** run the preflight against the real master IMG just because this document or code exists. The exact local trial command must be reviewed separately after all approval boxes are satisfied.
