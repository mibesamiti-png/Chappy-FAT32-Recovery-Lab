# A R8 delegated native Windows test wiring — 2026-11-15 JST

## Scope
Team A owns `runner/Invoke-ChappySyntheticRegression.ps1`, `runner/Chappy.R8DelegatedTestSelection.ps1` and `tests/Test-A3DR8DelegatedRunnerManifest.ps1`. This is an A-only CI/quality gate addition. **No B/C/D implementation, A exporter/bridge, synthetic oracle, original IMG, or real filesystem scanning is changed.**

## Why
After A delegated R8 work, B [#203](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/203) and C [#202](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/202) correctly reported that their new standalone PS5.1 scripts were **not executed by the existing 54/54 test runner**. Green central CI was insufficient to approve their native code or original R8 full-stage safety.

## Contract
- Existing fixed 54 isolated synthetic tests plus the NEW A-owned manifest test run in all branches, 55/55 expected while delegated B/C/D files are absent.
- When `core/Chappy.R8RootHandleGuard.psm1` appears, `tests/Test-BR8RootHandleGuard.ps1` MUST appear; vice versa. If paired, execute B native test in an isolated Windows PowerShell 5.1 child process; reject mismatches.
- Identical required pair for C `core/Chappy.R8FaultSafeWriter.psm1` and `tests/Test-CR8FaultSafeWriter.ps1`.
- If D adds `tests/Test-DR8AdversarialMatrix.ps1`, execute it in an isolated PS5.1 process; no production module required.
- No dynamic test selection from arbitrary directories; exact hardcoded B/C/D allowlist only. Windows CI must use the PR merged tree containing this A runner change to execute these tests. **Prior B/C CI remains insufficient**: rebase/refresh B/C PRs after A runner main integration, and read **actual final HEAD** CI logs including the delegated suite.
- Tests themselves must be manually reviewed for generated-only sources, safe owned temp cleanup, resource limits, API correctness and misleading PASS on not-tested junction/symlink cases before A approves individual PRs. A alone merges and tests post-main.
- R8 full formal stage remains NOT ACCEPTED, 0/9 points. R0–R7 original synthetic research 84%; real microSD/sole ~31GB master IMG access (including read/hash/scan/copy) remains not approved. All source authenticity/original SHA/owner/recovery rate UNKNOWN.

## Validation
A's own native manifest test creates only temporary synthetic filenames (no data samples from the user), verifies empty/B/C/D combinations and fails closed on missing module or missing test. Actual Windows PS5.1 central CI and eventual B/C/D test evidence require separate final-head and post-main links; do not claim unrun tests pass.
