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