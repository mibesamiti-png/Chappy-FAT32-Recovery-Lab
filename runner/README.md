# Team A — synthetic regression runner

The Windows PowerShell 5.1 script `runner/Invoke-ChappySyntheticRegression.ps1` runs synthetic-only suites separately, including QuickProbe, Team B metadata scanning, Team D FAT diagnosis, Team D synthetic patch rollback, and Team D R3 mirror windows.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\runner\Invoke-ChappySyntheticRegression.ps1
```

- No arguments; **cannot accept a path to a real IMG**.
- Runs exactly five committed test programs; each generates artificial fixtures only.
- Launches a separate Windows PowerShell 5.1 process per suite to avoid leaked globals/functions and misleading pass counts.
- Any nonzero exit code or missing test fails the entire job.
- GitHub Actions uses this runner in the privacy gate.
- Does NOT perform real image analysis, file extraction, recovery, repair or reporting.
- Synthetic tests passing is a quality signal only; it cannot establish success with the original microSD or master IMG.

The standalone **real IMG read-only diagnostic runner** remains a distinct future milestone requiring explicit A safety review, path validation and an opt-in local-only workflow.

## Team A local-only diagnostic preflight — EXPERIMENTAL

New script: runner/Invoke-ChappyLocalReadOnlyPreflight.ps1.

**Do NOT execute against the real 31GB master IMG until the new A Draft PR is reviewed, integrated and an explicit local-only test procedure is approved.** The script is still a prototype.

The command requires an explicit opt-in switch. It accepts a regular local .img file on an absolute drive path, rejects UNC/device/reparse path components and images placed inside this public Git repository. It opens its source only with FileAccess.Read / FileShare.Read. It has no output file argument, no extraction, no repair and no automatic upload.

The script integrates Team B FAT-independent directory candidates and pure metadata hierarchy with Team D FAT mirror-window and EB58 observed-pattern statistics. All reads are bounded. Output is a fixed-schema **numeric-only aggregate**, not original filenames or recovered content. The result is usually partial due to deliberate sampling; it cannot establish file health.

Synthetic regression used in GitHub CI:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-LocalReadOnlyPreflight.ps1

The test constructs a disposable artificial 2 MiB FAT32 IMG in the system TEMP directory, refuses omitted consent/relative/device/UNC/source-in-repo paths, verifies expected FAT32 geometry, directory/mirror/EB58 summaries and unchanged artificial source SHA-256, and deletes the fixture. No actual real IMG is touched.

**Current safety limitations:** FileShare.Read prevents new conflicting write opens while this process holds the read handle but cannot prove the image was never changed by other processes. Absolute-drive validation does not prove an IMG was acquired correctly. Reparse checks are best effort. The code does not test file-content recovery, naming completeness, fragmentation, physical media, private files or original data integrity.
