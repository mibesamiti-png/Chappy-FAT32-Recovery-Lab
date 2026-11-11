# Team A integration review — R1, 2026-11-11

## Summary (verified GitHub state, not real recovery)

| Team | PR | Head reviewed | Main integration | Acceptance |
| --- | --- | --- | --- | --- |
| B | [#7](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/7) | `253a7079e50e77eadef02f87b7c9bd8f2d69e6de` | `96d1a7855bbbd6675a382cdb22fde47668813469` | Read-only metadata candidate parser, synthetic Windows tests 22/22 |
| C | [#5](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/5) | `48f2e2745e5d3c4d08431f021ad81a349176f614` | **Not merged; Draft** | Synthetic tests pass, but unbounded amplification of I/O/probes across candidates needs correction |
| D | [#6](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/6) | `80700788c0ece54e1fdc3fe85b8f68ca254e58df` | `512ca3806905c253a422e950eaddd2035559e63d` | Read-only forensics + synthetic-only byte-array simulation; R1 25/25, R2 29/29 |

Combined Windows synthetic/privacy CI for `main` after B/D integration: **[SUCCESS run 42968506751](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/42968506751)**. The central gate executes QuickProbe, B directory test, D R1 + R2 synthetic suites, plus the tracked-file privacy check. Tests run on artificial inputs and do not inspect the 31GB master IMG.

## Reviewed safeguards for B and D

- B: bounded root-first, independent directory-candidate parsing; FAT-independent, UTF-16 LFN checksum; source FileAccess.Read; reports CreateNew; default filenames redacted; supports truncation and false-positive testing.
- D: FAT/MBR/BPB independent parsing with bounded probes and redaction by default; source FileAccess.Read; report CreateNew; only proposes evidence-backed hypotheses.
- D simulation: 4 KiB .. 8 MiB **marked synthetic byte array**; 1..32 explicit patch proposals, whole-buffer SHA guard, cloned array and inverse plan. **No file writer exists**.

These precautions were reviewed for the stated interfaces and tests; they are not a formal security proof. Unknown disk corruption could still cause parsing errors or false candidate data.

## C P1 merge blocker (Draft PR #5)

Review comment posted to PR #5 requesting:
1. A GLOBAL budget counting signature searches, ZIP/EOCD validation, G-code line scanning, and extracted candidate probes; `MaxScanBytes` only bounds the initial search currently, not cumulative I/O.
2. Dense-fake-signature and malformed ZIP adversarial synthetic tests for finite memory / CPU / reads and accurate `metrics.bytesRead`.
3. Raw device and output alias/path checks in optional export, with no input writes and no overwrites.
4. Sanitize free-form evidence/warnings/errors in optional JSON reports (avoid accidental private text leakage).
5. Clarify structurally verified ZIP vs unverified CRC/content; do not represent this as fully restored file integrity.

Re-review new PR head and CI before merge. **Do not merge C merely because its current CI is green.**

## What is NOT proven

- No new B/C/D module has scanned the user's real 31GB IMG.
- No actual file extraction or original-name recovery verified.
- SHA-256 on bytes copied from an IMG does not prove the original files were intact.
- The FAT repair simulator is not a way to repair the real microSD and must not be used for that purpose.
- Master IMG integrity is not independently verified.

## Next A tasks

1. Re-review C after P1 corrections; integrate only after synthetic CI and source safety gates.
2. Add local-only interactive diagnostic runner with opt-in image path; strong read-only and no-upload protections.
3. Test combined B/D/C modules on fully synthetic FAT32 fixtures and later only locally on the user's IMG after explicit user review of the intended commands.
4. Update `docs/TEAM_DISPATCH.md`, `docs/STATE.md`, and Issue #1 after each merge. Avoid reassigning completed B/D work by accident.