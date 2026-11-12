# A R7 standard-FAT32 C candidate-specific read receipts — 2026-11-12

Owner: Team A Issue #1. Frozen starting main: `6996537cb7e17909e8f696a82d5b4044a4ddb331` after A-reviewed B #131, C #130, D #132 **research_only** merges.

## Scope and trust boundary

New synthetic-only test `tests/Test-A3DStandardCCandidateReceipts.ps1` uses two independently generated but byte-identical 64.5MiB FAT32-classified (seed202611, SPC2) nonwritable in-memory images. Actual B BPB parsing and root observation, opt-in C data-region discovery and a second bounded C parser check at a C-discovered 3MF candidate start, and actual D FAT observation share one A-owned `ChappyA7SharedSource` **120,000 physical returned-byte cap per image**.

An A-controlled read-only wrapper *inside* the outer physical source meter records every C read with the A-issued source token, physical offset/returned bytes and phase (scan or specific candidate validation) and mints IDs distinct across separate identical sources. Every wrapper event must match A outer source-returned event offsets and sizes, one-to-one. A performs one **bounded re-read of the entire C-selected candidate**, because a C structural parser scan may not by itself physically reread every byte. The A resolver `Resolve-A3DReadEvidence` then checks candidate-specific full byte-range coverage, source token, candidate ID, phase and actual total returned budget.

Negative assertions: scan-phase IDs cannot prove candidate-specific validation; fabricated IDs, different candidate ID, limited A budget and ID replay from a byte-identical different source must remain `unattributed`. The candidate comes from actual C scan **without any generator oracle locations or original SHA**. An independent artificial scorer is consulted only after the physical reread, never by B/C/D.

## What this does NOT prove

- A source-observed receipt proves only that these specific bytes were physically returned by the **test-time A stream** for the candidate-scoped phase. It does NOT prove original data authenticity, FAT ownership, original filename/path, file reconstruction or a cryptographically authenticated external source.
- The C data-region helper is a **test-only/default-OFF** research helper and its numeric B geometry may be ambiguous/forged on malformed or malicious sources. This gate does not solve independent geometry attestation.
- C's second bounded structural check and A's full-candidate reread are distinct. Do not advertise either as a general-purpose production validator or original-file SHA verification.
- No real device, original image, source path, export destination, repair operation or file writes are used. R7 is still **PARTIAL**, R8 output is BLOCKED; real ~31GB sole IMG and microSD access/read/hash/copy/repair/extract/upload remain **NOT APPROVED**.

The A central native Windows PowerShell 5.1 isolated runner now expects **38 scripts** (was 37). CI green at exact PR HEAD plus post-main privacy/Windows green are mandatory before claims of completion or integration. Only completed full-gate roadmap R0–R3 = **39% official weighted synthetic engineering**, not real-world data recovery probability.

Next A: malformed/synthetic ambiguous geometry and genuine physical short-return EOF negative under candidate validation, plus cross-candidate source extent ambiguity. B/C/D own their modules and retain separate roles/branches.


## Backing stream early EOF control — 2026-11-13

A third generated source runs the same discovery under the same cap. After discovery, its backing stream returns a 17-byte prefix and then zero bytes during A's candidate reread. The declared length stays constant, so range checks alone cannot cover this case. Both meters must agree on the returned prefix, and the resolver must preserve incomplete coverage and unknown identity. The two full-read controls and central script count are unchanged. This tests source observation only. Malformed and ambiguous geometry remain separate work.
