# B R8-P4 — standalone Windows handle-bound *preflight* of disposable output root

**Owner:** existing Team B chat, [ACTIVE Issue #198](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/198). **Pre-code frozen R0/R1:** [Issue comment #6883178740](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/198#issuecomment-6883178740). **Base main:** `9e21f9aa758dbf0582846151823ad657a19db605`. **Files exclusively owned by B:** `core/Chappy.R8RootHandleGuard.psm1`, `tests/Test-BR8RootHandleGuard.ps1`, this document. A alone can edit `core/Chappy.SyntheticSeparateExportV1.psm1`, R8 bridge, shared CI/runner, and authorize integration.

## What is implemented

Minimal Windows PowerShell **5.1** module using only first-party C# compiled in-process by `Add-Type` (Win32 DLLs provided by Windows; no third-party code). This module **never writes or removes files**, never reads a source device, and never grants file creation authority. Public, versioned entrypoints:

```powershell
Import-Module .\core\Chappy.R8RootHandleGuard.psm1
# Enabled only for a fresh, pre-existing, disposable root *directly* under
# the current OS temp directory (name ChappyR8Synthetic-<lower-hex-guid>).
$g = Open-ChappyR8SyntheticRootLeaseV1 -OutputRoot $generatedTestRoot -EnableSyntheticRootGuard
try {
    if ($g.status -ne 'handle_observed') { throw 'UNSAFE_ROOT' }
    $check = Test-ChappyR8SyntheticRootLeaseV1 -GuardResult $g
    # ONLY a preflight. Always $check.canAuthorizeWrite = $false.
    # No CreateNew should be permitted merely because $check was positive.
} finally {
    $closed = Close-ChappyR8SyntheticRootLeaseV1 -GuardResult $g
}
```

Default without `-EnableSyntheticRootGuard`: fixed `disabled/not_requested`, **zero source I/O** and no root path or API access. Enabled but unsupported OS/PowerShell or malformed path → fixed `unsafe_root/UNKNOWN`. Handle observations → `handle_observed/HANDLE_OBSERVED_PREFLIGHT_ONLY` with `handleIdentityVerified=true` **only for the lifetime of the opaque disposable lease**; **still `canAuthorizeWrite=false`** on every outcome. For all results: `schemaVersion=b_r8_root_handle_guard_v1`, `sourceAuthenticity=not_proven`, `originalIdentity=unknown`, `canExportOriginal=false`, zero source/output/write/delete metrics, and **no raw path/handle identifier in public fields**. Never serialize the `.lease` object; it is a private native-handle resource to close in `finally`.

## Bounded checks and exactly what they prove

1. Parse strictly local drive-letter absolute path with no traversal (`..`/`.`), UNC, extended `\\?\` device namespace, ADS colon, relative name or nested destination. Require canonical root to be an existing **direct child of `Path.GetTempPath()`** with exact `ChappyR8Synthetic-[0-9a-f]{32}` basename. Traverse at most 64 existing ancestors and reject **any** file attribute `ReparsePoint` or non-directory. No path of the actual microSD or unique original IMG is ever accepted or consulted.
2. Use `CreateFileW` with `FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT`, `OPEN_EXISTING`, **FILE_READ_ATTRIBUTES**, and FILE_SHARE_READ|FILE_SHARE_WRITE (intentionally **no FILE_SHARE_DELETE**) to open both the OS temporary *parent* and the generated leaf *root*. Thus an **ordinary** concurrent root rename/removal that needs delete-sharing should be refused while both handles remain alive. On any failure, return UNKNOWN. There is no data read and no write handle.
3. Call `GetFileInformationByHandle` on each **same open handle**: verify `Directory` present, `ReparsePoint` absent, and record *private* volume serial+file index. Independently obtain final DOS paths using `GetFinalPathNameByHandleW` and reject mismatches/unsupported volume namespace (including unexpected reparse resolution). Reopen the same canonical parent and root by name while lease is held; compare both new handle IDs to stored same-object identities. Revalidation tests both original handle IDs and freshly reopened path IDs.
4. Close/dispose root and parent handles. Re-validation after closure returns `unsafe_root/UNKNOWN`. A later distinct directory substituted at the same path must have a different stored file identity and cannot reuse the previous lease. A mere string name or GUID-shaped folder is never an identity certificate.

**Explicit residual and tradeoff:** These checks provide a **native same-object, limited-lifetime *preflight*** that is stronger than a FileAttributes-only string check, and a no-delete-share lease that ordinarily blocks root rename. They **do not** make future absolute-path `FileMode.CreateNew` race-proof. Opening the initial OS-temp ancestor chain can itself race privileged substitutions; hostile elevated processes may bypass sharing protections, mount-level path meanings can change, filesystem/OS semantics can differ, and the B lease expires at close. Moreover A's existing R8 exporter does not yet use this lease at all. A **must** independently implement/review a handle-relative child creation mechanism (or fail closed), bind lease and output handle identity through write/readback/cleanup, and decide whether its design genuinely meets full R8. The Win32 `CreateFileW` path-based creation alone **cannot** be authorized from this result. The native `NtCreateFile` RootDirectory-relative method is possible but has difficult trust/interop details and is **not implemented** here. No root safety is guaranteed against a privileged hostile race. **If A cannot prove write-under-bound-root, A must reject the operation**.

## Synthetic acceptance tests — intended native WinPS5.1 only

`tests/Test-BR8RootHandleGuard.ps1` is standalone, uses an invented nonwritable 887-byte MemoryStream and only randomly named test-owned disposable OS-temp directories. Assert:
- disabled → zero IO even for missing path; positive normal root yields native handle lease with `canAuthorizeWrite=false` and revalidation same-object.
- invalid relative/traversal/UNC/device/ADS/nonconforming/nested path all UNKNOWN without file creation.
- root rename attempt while a no-delete-share handle is held: ordinary rename denied and same-object stable; if unexpectedly succeeds, the lease must reject changed path (UNKNOWN). After close, replace the root with a different owned directory at the **same path**, proving stored root identities differ; old closed lease must reject.
- actual NTFS junction and actual directory symbolic-link root **if OS permits creation**; reject and preserve independently owned target sentinel. Report `NOT TESTED` rather than PASS when unavailable. Artificial nested ancestor root rejected by direct-child policy; **no test attempts to replace an actual OS-temp ancestor**.
- all test-owned sentinels are unmodified, no source bytes read by guard, output files written by guard=0, no cleanup/deletion by guard=0, generated source-array SHA unchanged.
- Any false authorization (`canAuthorizeWrite=true`) is an immediate test failure. This test cannot prove resistance to arbitrary privileged kernel/mount races or that A already performs handle-relative child creation.

**Critical CI ownership blocker:** A's current `runner/Invoke-ChappySyntheticRegression.ps1` has a **fixed** script list and does NOT include this new script, and `.github/workflows/team-b-synthetic.yml` only triggers on `modules/directory/**` and the old B runner. B is **not authorized** to modify A-owned runner/workflow, so a green standard privacy/central PR CI **does not demonstrate that `Test-BR8RootHandleGuard.ps1` executed**. Team A must add this new exact script to its isolated native Windows 5.1 CI runner or provide an equivalent direct Windows job, execute it on the FINAL PR HEAD, review logs (including `NOT TESTED` for junction/symlink), then re-run merged-main CI. Until that occurs, mark B R8-P4 **NATIVE TEST UNVERIFIED** rather than certifying PASS.

## Primary-source reasoning and license decision

- Microsoft `CreateFileW` for directory handles, `BACKUP_SEMANTICS` and `OPEN_REPARSE_POINT`: https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew
- Microsoft `GetFileInformationByHandle` volume serial and file index, same-object comparison: https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfileinformationbyhandle
- Microsoft `GetFinalPathNameByHandleW` resolved DOS path limitations: https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfinalpathnamebyhandlew
- Microsoft `NtCreateFile` `RootDirectory` relative child option **considered, not blindly shipped**: https://learn.microsoft.com/en-us/windows/win32/api/winternl/nf-winternl-ntcreatefile

These URLs are conceptual API documentation, **not reused source code**. No imported third-party code, no external DLL or package. When Windows APIs are unsupported or the proof boundary is insufficient, deny write authorization; never relax safety to satisfy a progress metric.

## Formal stage and physical-media firewall

Original synthetic engineering R0–R7 **84% A-signed**. R8 whole stage **NOT_ACCEPTED, 0/9 points**; R9 0/5, R10 0/2. B/C/D newly delegated parallel R8 P4/P5/P6 are **slices**, not percentage points. Narrow B5/C6/D5/A6 previous R4–R7 22/22 synthetic subchecks passed, **NOT any percentage of real recovered files**. All genuine original identities/source ownership/hashes remain UNKNOWN. The real microSD and sole original ~31GB master IMG are **absolutely not approved for reading, hashing, scanning, copying, extracting, modifying, repairing, exporting or uploading**, including via copies disguised as synthetic. B test and module have no input path capable of addressing them.
