# Team D R5-P1 — primary versus backup FAT32 VBR disagreement evidence

**Issue:** [#33](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/33). **Research only, artificial fixtures, Team A Draft PR review required.**

## Read-only API and strict bounds

`Fat32VbrDisagreement.psm1` exports `Get-ChappyFatVbrDisagreement`, accepting an **already-open, seekable, readable, strictly nonwritable** `System.IO.Stream`. It does not open file paths, access physical devices, write, repair, extract, suggest repair bytes, or select a FAT32 geometry.

- MBR partition index: 0..3 (default 0); MBR fixed 512-byte LBA units.
- Global max read budget: 512..2048 bytes, default 2048; **never more than four 512-byte sector probes** (MBR, primary VBR, backup VBR at the primary-declared sector, FSInfo at the primary-declared sector).
- Uses an actual byte count including partial reads and loops to complete fragmented 7-byte synthetic stream reads. No scan of full FATs or arbitrary sectors, no recursion and no unbounded allocations.
- If the MBR anchor is invalid (signature/partition type/boot flag/length/stream bounds), no speculative VBR scanning is attempted.
- The backup location comes only from the **primary's unverified backup-sector field**. A shifted offset can lead to an unrelated, fake or empty sector; this module never searches for alternative backup signatures.
- The FSInfo location also comes from primary. It is **not** used to validate a backup candidate that declares a *different* FSInfo sector; that candidate is marked `insufficient_evidence`.

## Independent evidence per candidate

Each observed 512-byte BPB candidate is evaluated separately against the same declared MBR partition boundary and real stream length:

- FAT32 signature and jump structure (not just `EB 58 90`), conservative 512-byte BPB sectors, power-of-two cluster size and 32 KiB policy cap, two FATs, reserved sector count, nonzero volume and FAT sector counts, FAT32 legacy field and filesystem version constraints.
- FAT1/FAT2 derived offset, FAT entry capacity, data-cluster count and root cluster bounds **independently computed for each BPB**, no reuse of a prior candidate's derived geometry.
- FSInfo lead/structure/trailer signatures and free/next hint ranges compared against each candidate's own cluster count **only when its FSInfo location was actually probed**.
- Candidate statuses: `plausible_unverified`, `contradicted`, `insufficient_evidence`. Plausible means **no contradiction detected among this tiny sampled numeric/structural feature set**, not authenticated filesystem geometry.
- `agreement=agree|disagree|insufficient_evidence`; `differingFields` uses fixed `bpb.*` codes, including root cluster, FAT length, volume length, FSInfo and backup sector, signature/jump, and reserved fields.
- **No winner selection** even when one candidate is contradicted or both candidates are plausible but inconsistent: `selectedCandidate=null`, `sourceDecision=not_selected`, `writePermitted=false` always.

## Caveats and safety

- MBR, partition entry and both BPB copies can all be syntactically plausible but malicious, corrupted, mutually inconsistent or physically wrong. A checksum/CRC of real source contents is not computed.
- If primary is unreadable, backup location generally cannot be inferred safely; this is `insufficient_evidence`, not a justification for probing other sectors.
- A missing backup or insufficient byte budget is **not** an agreement result and sets `scanIncomplete=true`.
- Only numeric offsets and fixed reason codes are returned; no raw records, file paths, names, hash digests, user contents, filenames or actual backup images are written or logged.
- **Actual microSD / unique 31GB master IMG are OFF-LIMITS for this research code.** The real local preflight approval checklist remains NOT APPROVED, even if GitHub synthetic CI is green.
- Synthetic 2MiB fixtures use a simplified FAT32-like layout; they do not demonstrate FAT32 conformance or real recovery.

## Windows PowerShell 5.1 synthetic test

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\modules\fat-analysis\tests\Run-TeamD-R5-Disagreement.Tests.ps1
```

Cases include identical candidate control, two independently plausible but different root cluster or sector counts, a huge/malicious primary and backup total size, forged `EB 58 90` at FAT start, shifted backup locator, signature/jump tampering, mismatched FSInfo candidate locations, shared invalid FSInfo, MBR corruption, truncation, exact 512/1024/1536/2048 byte budgets, seven-byte fragmented stream reads, no writable stream and synthetic source SHA-256 preservation. Only synthetic test data and fixed test labels are committed.

## Handoff

R4 Issue #25 and PR #28 were merged by Team A. This R5 increment stays in its own newly dispatched branch, with a small Draft PR targeting main. Team A verifies exact-head Windows CI and privacy gate, inspects trust semantics, and decides integration. No automatic follow-on research is started without a new assignment.
