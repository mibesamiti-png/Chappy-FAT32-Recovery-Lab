# Team A R7 — standards-shaped generated FAT32, shared B/C/D source meter

**Source:** A Issue #1. Reviewed main before this branch: `5eba2e46ed8f8d50f8f124c8ff4442945bde8ccf`, after accepting C #121 and D #122 with final exact-head Windows PowerShell 5.1/privacy CI. Original physical microSD and unique ~31GB master IMG remain excluded from read/hash/copy/scan/write/repair/export/upload. Real-media preflight: **NOT APPROVED**.

## Bounded question

Earlier A shared-source tests used **2MiB FAT32-like** artificial media. This step tests whether actual B directory, C carving and D FAT observed-I/O analyzers can share **one nonwritable physical source stream and one cumulative read-byte quota** on larger FAT32-classification-sized synthetic volumes. The generated standards-shaped FAT32 fixture has >=65,525 data clusters and includes MBR, boot/backup VBR, FSInfo, two FATs, directory entries and three invented file payloads. The existing independent standard fixture test still verifies full synthetic FAT chains and original SHA against its external oracle; this integration test does NOT pass oracle data to B/C/D.

## New A integration test

`tests/Test-A3DStandardSharedSourceGate.ps1` uses only in-memory artificial arrays from the existing `New-ChappyA3DStandardFixture` generator, not local file paths or real media. Predeclared 5 artificial inputs:

- seed 202611: cluster size 512B and 1024B, clean FAT mirrors
- seed 202612: cluster size 512B and 1024B, clean FAT mirrors
- seed 202613: cluster size 512B, **artificial FAT2 entry4 byte modified**, source SHA tracked

Each generated source is **about 34–68MiB**, independently allocated, wrapped in a strictly nonwritable `MemoryStream`. A calls B geometry, B root-directory scanner, C's 64KiB capped image-prefix signature scanner, then D bounded FAT mirror/chain observations on a **single A source meter with 120,000 actual returned-byte cumulative cap**. Check actual outer Stream.Read event offsets and lengths, independently reconstruct distinct-byte union and duplicate byte counts, cross-check B root cluster and D FAT physical bytes against A's source trace, reject write-capable sources and confirm input SHA unchanged. After all parser calls, deliberately request **one byte more than remaining overall quota** and require hard failure with zero extra bytes/events (no fake EOF).

The test checks the artificial independent scorer's three file payload SHA values from the generated oracle only **outside** B/C/D. It never marks a B/C/D candidate as authentic original. Crucially, the current C scanner's 64KiB image-prefix bounded scan **does not automatically search the standards-shaped data region**, because `dataOffsetBytes > 65536`. Therefore *no returned C candidate must be interpreted as an absence of real file content*; the independent scorer's original file matches do NOT become C recovery hits. This is a concrete future R5/R7 integration dependency, not a failure to search the entire 34–68MiB volume.

## Safety and acceptance interpretation

- Research/test-only; no production algorithm or default flags, no extraction/export path, and no FAT mirror winner/repair.
- The artificial read-meter enforces a **per-image** returned-byte limit, not a global sum across different generated image sources; distinct-byte unions are never merged across sources.
- The independent standard fixture test is already on the A runner. The new test is **a different proof**: shared measured B/C/D read budgets and evidence on standards-shaped rather than tiny IMG layout.
- R7 still needs candidate-specific true C validation receipts on these larger layouts, wider short-read/EOF faults, multiple actual anomalous FAT32-classification shapes, and overall R4/R5/R6 acceptance before R8 separate-root export. Do not claim real recovery success from synthetic 3/3 original scorer SHA.
- Expected regression count **34 -> 35 isolated Windows PS5.1 synthetic scripts**. Final exact-head and post-merge main Windows/privacy CI evidence must be checked before declaring success. Fully gated R0–R3 synthetic engineering weighted roadmap **39%**; R4–R7 remain partial.
