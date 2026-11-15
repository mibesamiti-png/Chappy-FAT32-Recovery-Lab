# Team D R8-P6 independent adversarial matrix — Issue #200

## Frozen scope and safety
- Base main: b052c3b7c15d54558d6961b49927c395f9967b27 (2026-11-15 JST).
- D owns ONLY tests/Test-DR8AdversarialMatrix.ps1 and this document. A owns R7/R8 bridge, exporter, central CI runner, review, merge and formal stage signoff.
- Generate FAT32 using tests/helpers/New-ChappyA3DStandardFixture.ps1 seed 202611, SPC1 fragmented and SPC2 contiguous. The source is a non-writable MemoryStream. Private test scorer oracle is NEVER passed to A candidate selection.
- Only fresh direct OS-TEMP child roots named ChappyR8Synthetic-<32 lowercase hex>, bounded synthetic files and verified owned-root cleanup. No file path input, actual IMG, device, actual user file or real source used. No test changes B/C production.
- Existing unmerged B PR #203 and C PR #202 are not assumed integrated.

## P1 behavioral matrix (each row independently exercised with SPC1 and SPC2)

| Group | Artificial condition | Required result |
| --- | --- | --- |
| 1 | Default OFF on standard generated source | 0 physical source reads; no output |
| 2 | One structural candidate | 887B test-only output; independent R7 + R8 source sessions; scorer SHA match; original identity UNKNOWN |
| 3 | Same candidate twice in same output root | CreateNew collision; first owned output unchanged |
| 4 | Destroy 4 bytes of local artificial ZIP header | Zero structural candidates; no R8 reread and no output |
| 5 | Duplicate generated 512-byte valid tail sector to another bounded location | At least 2 hypotheses; no auto winner, R8 reread or output |
| 6 | R7 max returned bytes = 1024 | No output; actual returned bytes bounded at 1024 |
| 7 | R8 candidate read-call cap = 1 | Partial/UNKNOWN; no output |
| 8 | Real MemoryStream.Read returns 3 bytes then 0 | Actual short-return evidence 3B; no output |
| 9 | A synthetic-only injected write failure | No completed output and no surviving file in owned test root |

**Test denominator:** 9 condition groups * 2 synthetic SPC layouts = 18 group-scenario combinations, plus explicit source/receipt bounds, immutability and cleanup assertions. This is test-case coverage, not recovery rate. Actual measured checks, source returned bytes and call counts must be taken from the executed native log, never invented.

## Evidence status and CI
- At authoring: NEW D standalone test NOT RUN. Code presence does not prove PASS.
- A PR #204 already wired exact allowlisted D test script into isolated native Windows PowerShell 5.1 central synthetic CI. A's standard 55-script baseline is not evidence of D results if this D file was absent.
- Standalone command: powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\tests\Test-DR8AdversarialMatrix.ps1
- Required for signoff: exact D PR HEAD, native Windows 5.1 test and privacy gate results, explicit PASS/FAIL/UNKNOWN denominator, then independent A diff/security review and post-main CI. CI failure is a real blocker, not a PASS.
- Generated oracle SHA is checked privately in D and never provided to candidate selection or reported as actual restored file integrity.

## OUTSTANDING — UNKNOWN, not tested
1. Forged/reused candidate receipt IDs and source metadata, phase mislabeling, FAT remote UNKNOWN/competing mirror claims need an isolated stable A public input seam or later D-only read-only test helper. Do not alter A core or claim coverage.
2. Malicious root/ancestor replacement and privileged TOCTOU need A integration of B handle guard #203. Path-string guards do not prove handle-relative safety.
3. Actual fault-writer disk-full/short-write/readback and identity-bound cleanup require A review/integration of C #202. Existing A test injection exercises only the narrow synthetic failure case above.
4. Wrong-order or overlapping R7 candidate injection is not exposed by the current public bridge; lower-level A tests exist, but this D bridge test does not claim it exercised them.
5. R2 controls cannot be assumed to satisfy R8 standard-only bridge source contract (minimum 2 MiB; synthetic fixture tag is not provenance). Their separate execution is pending.
6. No real-media read/hash/scan/copy/extract/repair/write/upload is authorized, even via derived or disguised sources. Real owner, original SHA, FAT winner, actual recovered bytes, restored-file rate: UNKNOWN.
7. R9 formal acceptance is NOT STARTED; D matrix contributes only independent regression evidence.

## Stage accounting
R0-R7 formally A-signed generated-only engineering = 84%. R8 = 0/9, R9 = 0/5, R10 = 0/2. Historical narrow B5 + C6 + D5 + A6 = 22/22 PASS is not real recovery.

## Next bounded D P1
After exact new native CI run, fix D-owned test errors without modifying A/B/C. Then select one receipt/phase adversarial seam compatible with the latest merged A API. Escalate unavailable seams on Issue #200 for A's decision. D never merges its own PR.
