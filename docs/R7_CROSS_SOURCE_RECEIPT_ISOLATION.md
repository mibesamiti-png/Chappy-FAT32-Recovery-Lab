# Team A R7: isolate read receipts from two independently generated sources

Issue A #1. Research-only / synthetic-only test addition following B #105, C #106 and D #104 reviewed merges. Starting main: `5b31812da9ddf985fa15c21bd92c370c36bd71d8`. Real microSD and unique ~31GB master IMG remain off limits; local real-media gate **NOT APPROVED**.

## Failure mode and correction

The earlier A-owned **test-only** `ChappyA7CandidateMeter` created event IDs as `A7P-0000`, `A7P-0001`, ... separately for every source Stream. When events from two independent images were pooled, unrelated events could collide even if the files were byte-identical and used the same absolute offsets. A's conservative `Resolve-A3DReadEvidence` already rejects duplicate IDs, but event collisions prevent a useful multi-image evidence union, and careless adapter code could attribute the wrong event if it used the ID without a source scope.

The test harness now namespaces the A-minted event ID under the **A-issued source token** (`sourceToken#sequence`) and bounds token length to 48 characters so the existing 64-character receipt-ID limit still holds. This is only a test-local identifier design; it is **not** a cryptographically authenticated immutable source identity, a stable persisted unique ID or a new production API. The A caller must supply distinct trusted source tokens and control each stream's purpose/candidate phase. C never mints them.

## New independent artificial negatives

The new negative portion of `tests/Test-A3DLiveCCandidateReceipts.ps1` generates **two separate MemoryStreams** for independently generated but byte-identical M00 artificial images. A physically reads the same ordered candidate extents (64 bytes at offset 256 and 16 at offset 512) through each source-specific nonwritable meter:

- Per-source physical read IDs are distinct even when offsets and source content are identical.
- The existing A resolver can separately mark observed bytes for each source, but always returns `originalIdentity=unknown`.
- Mixed source-A fragment 1 / source-B fragment 2 cannot complete a source-A candidate: `origin.wrong_source` and `coverage.candidate_bytes_not_fully_read`.
- Entirely cross-source evidence is unattributed even if every numerical offset matches.
- A low physical-read quota refuses promotion and input SHA remains unchanged.

This is layered on the previous actual C validator + A meter M00/M01/P02 regression; it does not imply the production carver offers this interface. No original files, raw image bytes, paths or binary objects are checked in or printed. The only new CI entry also adds D's R6-P6 standalone artificial ambiguity regression from #104 to the central isolated Windows PowerShell 5.1 runner. Expected regression count **28 → 29 isolated scripts**, with exact final-head Windows 5.1 + privacy and post-merge main CI required.

## Remaining R7 acceptance gates

1. A-owned source token issuance must be tied to a concrete stream lifecycle (not arbitrary caller claims), including multiple source streams and short-return behavior.
2. The evidence resolver must reject candidate-specific validation purpose spoofing and overlapping source intervals from multi-candidate cases, not merely label strings.
3. Test both ambiguous but CRC-consistent 3MF candidate orders under the same shared cumulative source limit, with A-minted read receipts and independent synthetic SHA scorer.
4. Cover wider artificial standards-shaped FAT32 and truncated/budget-exhausted cases before R8's synthetic-only separate-root export; never promote structure matching to original-file proof.

R0–R3 only fully gated = **39%** weighted development milestones; R4–R7 partial, R8–R10 incomplete. All reported CI scores refer solely to artificial data and are not a real-media recovery rate.
