# Team B handoff (2026-11-11) — R1 draft PR #7

| Item | State | Evidence |
| --- | --- | --- |
| FAT-chain-free geometry and cluster reading | implemented | Windows PS 5.1 synthetic PASS |
| 8.3 + Japanese UTF-16LE LFN checksum and fallback | implemented | Windows PS 5.1 synthetic PASS |
| Root, nested subfolder, orphan directory discovery | implemented | Windows PS 5.1 synthetic PASS; candidate linkage unproven |
| Metadata-only JSON, explicit name opt-in, bounded scan | implemented | Windows PS 5.1 synthetic PASS |
| CLI refuses overwrite, source collision, device paths | implemented | Windows PS 5.1 synthetic PASS |
| Source image SHA-256 unchanged | verified on synthetic fixture | Windows PS 5.1 synthetic PASS |
| Full synthetic regression suite | **22/22 PASS** | GitHub Actions run [42967286265](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42967286265) |
| Repository privacy gate | PASS | GitHub Actions run 42966996061 |
| Real ~31GB IMG | **NOT SCANNED** | User-local only, pending review |
| Data extraction, fragmented chains, verified folder tree | unimplemented | Out of scope B R1 |

**Safety:** Input opened FileAccess.Read only; JSON output is CreateNew only, so no overwrite. No original device access. Names are redacted unless `-IncludeNames`. Output records are probabilistic metadata candidates, never verified original file data.

**Next:** A should review code and Windows CI. Later follow-up: additional malformed metadata tests, safe bounded local user diagnostic, false-positive ranking, potentially more targeted scanning. No PR integration until A approves. Do not upload real IMG, names, or unredacted JSON to the public repository.
