# STATE — 2026-11-11

## Incident (coarse, technical facts; no user files uploaded)
- 32GB microSD used in a 3D printer; Windows shows RAW after removal while powered.
- Raw backup image length reported by local PowerShell: **31,267,487,744 bytes**. Length equality is not integrity proof.
- FAT32 partition offset: **4,194,304** bytes; nominal cluster size: **16,384** bytes.
- FAT1 offset: **5,713,920**; FAT2: **13,342,720**; root data: **20,971,520** bytes.
- Boot records plausibly FAT32. FAT1/FAT2 first 32 bytes match and show repetitive `EB-58` pattern; root cluster's FAT entry is out-of-range.
- Root directory begins with plausible entry bytes; **data integrity, original filenames, and recovery success are not established**.
- The source card and the local master IMG MUST NEVER be modified.

## Development status
- R1 FAT32 diagnostics: prototype; not fully validated in Windows
- R2 Directory tree recovery: prototype; broken FAT links cause failures
- R3 File extraction: prototype, high safety/testing priority
- R4 Repair: analysis-only, work-copy/synthetic experiments only
- QA: synthetic checks reported, incomplete independent Windows validation
- Previously stated development progress was about 67% (subjective; not a recovery probability).

## Immediate priorities
1. D: independently verify FAT geometry, reserved entries, repeated bytes, false-offset hypothesis.
2. B: reconstruct directory entries without relying on FAT chains; synthetic LFN tests.
3. C: bounded G-code/3MF signature-based extraction; validation for fragmented files.
4. A: create shared interfaces, synthetic CI, review and privacy gates.

## Current work status
Repository is PUBLIC. Teams assigned in Issues #1-#4 and independent B/C/D branches created.
- Windows GitHub Actions privacy gate PASS (run 42962302965, attempt 2).
- Synthetic valid FAT and repeated EB-58-pattern FAT QuickProbe tests PASS on Windows PowerShell 5.1 (run 42963673830).
- Draft interface: docs/INTERFACE_V1.md; roadmap: docs/ROADMAP.md.
- Main v0.5 legacy program and test script are NOT YET imported into the repo. Do not claim otherwise.
- No real IMG or real reports committed. Recovery success remains unconfirmed.

## Universal continuation / team dispatch
- Shared prompt: `docs/UNIVERSAL_BOOTSTRAP_PROMPT.md`
- Canonical work policy: `docs/UNIVERSAL_WORK_INSTRUCTION.md`
- Role/branch roster: `docs/TEAM_DISPATCH.md`
- Existing B/C/D chats use identical prompts while preserving their prior team identity. New chat without role requires one-time explicit assignment.
- Actual 31GB image remains local; synthetic-only CI verified separately from real recovery.
