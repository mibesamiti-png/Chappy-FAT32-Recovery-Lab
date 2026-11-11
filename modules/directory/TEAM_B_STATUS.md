# Team B handoff (2026-11-11)

| Item | State | Evidence |
| --- | --- | --- |
| FAT-chain-free geometry/cluster reading | implemented | Source review only |
| 8.3 + Unicode LFN validation and short fallback | implemented | Source review only |
| Root candidate + independent subfolder/orphan scan | implemented | Source review only |
| Metadata JSON with bounds and privacy opt-in | implemented | Source review only |
| Synthetic fixture and regression tests | authored | Windows PowerShell 5.1 NOT executed |
| Real 31 GB IMG | not scanned | Local only, requires A review |
| End-to-end recovery, fragmentation handling | unimplemented | Out of scope Team B R1 |

**Safety:** no source writes; output JSON is `CreateNew` only. All names redacted unless `-IncludeNames`. Explicit result fields differentiate probable structure from confirmed recovery.

**Next:** Windows PowerShell 5.1 synthetic run, manual review of any failures, CI with synthetic only, integrator A review, then user-local bounded diagnostic. No PR integration until review.
