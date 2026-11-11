# Module interface v1 — initial agreement

**Status:** DRAFT; A will review before integration.

## General rules

- Windows PowerShell 5.1, built-in .NET only. No admin or physical device required.
- Consume a **read-only** `[System.IO.Stream]` (or a path opened strictly FileAccess.Read).
- Accept caller-provided bounds and stop when exceeded; no unbounded traversal/recursion.
- Never assume input or filenames are trustworthy; do not automatically extract/overwrite anything.
- Results must not include full local IMG paths, private file names, or sample contents by default.
- Each module should be independently testable with synthetic inputs and emit structured objects.

## Exported functions (proposed)

| Team | Function | Read-only inputs | Outputs |
| --- | --- | --- | --- |
| B | `Get-ChappyDirectoryCandidates` | `Stream`, geometry, scan bounds | directory and file metadata candidates |
| C | `Get-ChappyCarvingCandidates` | `Stream`, offset and maximum scan bytes | signature hits, size and integrity assessments |
| D | `Get-ChappyFatDiagnostics` | `Stream`, partition bounds | BPB/FAT offsets, anomalies and hypotheses |

## Common result shape

Use `[pscustomobject]` (not bare text) with:

```json
{
  "schemaVersion": "1",
  "team": "B",
  "status": "ok|partial|error",
  "scanIncomplete": false,
  "items": [],
  "warnings": [],
  "errors": [],
  "metrics": {
    "bytesRead": 0,
    "entriesChecked": 0
  }
}
```

For individual candidates include `offsetBytes` where known, `confidence` in `verified|probable|partial|unknown`, and `evidence` as **non-sensitive reason codes**. `verified` means the checks stated in the module passed, NOT that the original data is necessarily intact.

Do not include recovered private filenames in checked-in reports. In local opt-in mode metadata may be displayed but must not be uploaded.

## Shared quality gate

Use synthetic fixtures only for GitHub Actions. Check read-only SHA consistency, boundedness, error handling, precision of offsets, and path sanitization. Any proposed repair bytes require separate explicit review and disposable synthetic/workcopy only.

This is an initial coordination contract; change via small PR with cross-team review.