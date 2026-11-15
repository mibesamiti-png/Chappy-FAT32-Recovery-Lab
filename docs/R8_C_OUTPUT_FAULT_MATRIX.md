# R8-P5 Team C — synthetic write/readback faults and owned-only cleanup

**ACTIVE Issue #199.** Standalone Team C production API and artificial Windows test; NOT shared exporter integration, NOT an approved real file recovery or R8 whole-stage pass. Only generated synthetic 3MF candidate bytes and a test-owned disposable OS TEMP root. Real physical microSD and only original ~31GB master IMG, including any copy in memory, are NOT APPROVED for any read/hash/scan/copy/extract/repair/write/upload.

## Contract

The module core/Chappy.R8FaultSafeWriter.psm1 exports Invoke-ChappyR8SyntheticFaultWriterV1 and reports schemaVersion=c_r8_synthetic_fault_writer_v1. No output without explicit EnableSyntheticFaultWriter. Only artificial fixture tags matching A3D-clean-123456 or A3D-standard-123456 and candidate byte arrays at most 128KiB; default MaxOutputBytes=4096 with hard max 8192. A tag is NOT proof of artificial source authenticity. OutputRoot must be a preexisting direct-child OS temp directory named ChappyR8Synthetic- plus exactly 32 lowercase hex chars; deny relative/UNC paths, ADS/colon traversal, missing directories and reparse ancestors. A root preflight is NOT B's handle-bound TOCTOU guarantee.

Deterministic destination is candidate- plus first 32 hex SHA256 of SYNTHETIC candidate bytes plus .3mf. Write using FileMode.CreateNew and FileAccess.ReadWrite (NEVER overwrite). Keep the original created file handle open for at most 127B-write-chunk loop, Flush(true), Seek(0), SAME-HANDLE independent readback SHA. Output digest refers to candidate bytes, never original SHA. A successful FileStream.Write returns void: successfulWriteBytes counts only completed calls, NOT durable physical bytes and cannot measure partial bytes if Windows throws mid-write.

On failure, keep the original FileMode.CreateNew handle open, repeat root no-reparse preflight, and use Win32 DELETE+FILE_READ_ATTRIBUTES CreateFileW with FILE_FLAG_OPEN_REPARSE_POINT to obtain a second handle to the exact candidate filename. GetFileInformationByHandle volume serial + file index must equal the still-open original created handle. Only if both identities match, and neither reports reparse, call SetFileInformationByHandle(FileDispositionInfo) on the verified opened object. No path-only File.Delete in the module. If proof cannot be established, leave the file unchanged and report unverified_handle_left_intact or unverified_root_left_intact. NEVER delete a directory, collision target, or arbitrary caller file. This does NOT defend every privileged ancestor/root swap; A must reconcile with B root guard before integration. Win32 specific, native Windows PS5.1 validation required.

All outcomes return sanitized stable codes without OS exceptions/paths. Every outcome has originalIdentity=unknown, sourceAuthenticity=not_proven, originalShaVerified=false, canSelectOriginal=false, canExportOriginal=false, canRepairOriginal=false. No automatic original selection or export.

## Frozen test matrix

tests/Test-CR8FaultSafeWriter.ps1 creates a new artificial 3MF using first-party New-ChappyA3DCleanFixture Seed 202611, with original extents and original full SHA used ONLY in the independent test fixture assembly/scorer. The writer receives only candidate bytes. The test creates one uniquely test-owned disposable temp root and sentinel.keep, and validates that all inputs and sentinel SHA remain unchanged.

| Fault mode | Point | Successful Write bytes | Readback bytes | Expected owned-only cleanup |
| --- | --- | ---: | ---: | --- |
| disabled | no opt-in | 0 | 0 | no file |
| None | normal CreateNew, readback SHA | candidate length | candidate length | keep success |
| collision | second CreateNew, same filename | 0 | 0 | preserve previously existing candidate |
| BeforeWrite | after create, before write | 0 | 0 | delete verified owned handle |
| AfterPartialWrite | after first 127B | 127 | 0 | delete verified owned handle |
| AfterFullWrite | after Flush | full | 0 | delete verified owned handle |
| BeforeReadback | before readback | full | 0 | delete verified owned handle |
| DuringReadback | after first 127B returned | full | 127 | delete verified owned handle |
| DigestMismatch | full readback with simulated wrong comparison | full | full | delete verified owned handle |
| DiskFullBefore | artificial IOException before writing | 0 | 0 | delete verified owned handle |
| DiskFullPartial | artificial IOException after first chunk | 127 | 0 | delete verified owned handle |
| PermissionDeniedBefore | simulated access denial before CreateNew | 0 | 0 | nothing created |
| PermissionDeniedAfterCreate | simulated access denial after CreateNew | 0 | 0 | delete verified owned handle |
| Quota, invalid root, wrong fixture label | preflight | 0 | 0 | nothing created |

Disk-full and access errors are **simulated** — do not fill actual disk or adjust permissions. Tests assert no unknown-file deletion, atomic collision preserves preexisting output SHA, independent readback SHA for success, source and generated full fixture SHA unchanged, zero-output exception sanitization, and exact result counters. The test harness removes only the independently SHA-verified artifact it created and its own sentinel; removes its exact created root only if empty, never recursively deletes unexpected children.

## Native PS5.1 CI and A integration boundary

A independently merged [native B/C/D test selector #204](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/204) on main `b052c3b7c15d54558d6961b49927c395f9967b27`: after this C module + test pair appears, the central Windows PS5.1 runner **automatically executes** this standalone test as the 56th generated-only script (55 base + C). A owns that runner; C did not alter it.

The first actual new-test run [#43698483027](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43698483027) was **FAIL** at PR HEAD `582b746d35a47cc2aa61ecbde6e87fa57a281fe7`. Import, generated 887-byte candidate success, collision guard, and all **ten** injected fault modes **ran successfully** and logged `owned_handle_delete_marked` for nine owned created files while preserving synthetic input and sentinel. The **last invalid-fixture-tag test** then threw `ParameterAlreadyBound`: the test itself supplied SyntheticFixtureTag via a splatted hashtable and a second explicit parameter. The production native file-ID cleanup did NOT fail in that run. The C-owned test was repaired by constructing a separate invalid tag hashtable; a new exact-head CI is mandatory. No old 54/54 suite is interchangeable with this new R8-P5 validation.

The new native test and all central/privacy tests must **PASS on the exact final PR HEAD**; provide job logs and line-by-line fault outcomes in the PR/Issue. Do not claim acceptance before that. A alone reviews/merges, integrates B root-handle guard and D adversarial tests into its shared exporter/bridge, checks post-main CI, and signs original complete R8. This synthetic test cannot prove privileged ancestor-swap/TOCTOU immunity or original-data integrity.

Current formally accepted bounded synthetic engineering 84% R0–R7; R8 stage uncredited 0/9, R9 0/5, R10 0/2. B5/C6/D5/A6=22/22 old indexed research rows signed, not a real-data recovery rate.


## Native Windows ABI references and verification boundary

Primary Microsoft Win32 documents reviewed for the owned-file helper (API information only, **no external source code copied**):
- https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-setfileinformationbyhandle — FileDispositionInfo value 4, DELETE access required on the disposition handle.
- https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfileinformationbyhandle — compare VolumeSerialNumber with FileIndexHigh and FileIndexLow for same opened file.
- https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_disposition_info — FILE_DISPOSITION_INFO.DeleteFile is native **BOOLEAN = one byte** (not 4-byte BOOL); the C# P/Invoke structure explicitly uses byte with DeleteFile=1.
These API contracts support the design; the initial native Windows run exercised file-ID disposition successfully in ten injected cases, but its full test suite failed a separate duplicate test-parameter binding and must be rerun at the latest exact HEAD. No synthetic-only test establishes security against privileged root replacement.
