# Team A R7 — C-discovered ambiguous 3MF candidates and actual early EOF

**Scope:** A Issue #1. Frozen pre-review main `30b800f0a9c127164e5f22db3306250edf64b969`. A reviewed B #112 / C #111 / D #113 and accepted them as **research_only** (no production recovery promotion). After merging, A's new isolated synthetic test `tests/Test-A3DDiscoveredAmbiguousReceipts.ps1` and D P7 standalone test are added to the central Windows PowerShell 5.1 regression runner, expected 30 to **32** isolated scripts. No real IMG, device or user file access.

## R7 P1 test objective

Previously A created an intentionally reversed fragment candidate manually. This A test starts with **two actual C-discovered, CRC-consistent, distinct physical hypotheses** from the existing C test-only finite 3MF search on an artificially constructed `alternate_zip_metadata` case, without passing oracle offsets or true SHA to the scanner. C's bounded false-join guard must keep both accepted physical candidates with `decision=ambiguous`. The artificial clean-source SHA is held exclusively by A's external scorer.

A controls the independent nonwritable `ChappyA7CandidateMeter` and mints physical Stream.Read evidence IDs. A runs C's real `Test-CObservedCandidateValidation` separately under each exact ordered candidate key. A records each actual returned physical offset/count and ensures it matches C's diagnostic read intervals, without accepting C-self-issued trusted receipt IDs (none exist). The A receipt resolver must accept that **both different physical candidates were actually reread** as `source_observed`, but neither can claim original identity. The separate scorer expects exactly one candidate to have the invented original SHA. Reusing one candidate's real A receipts for the other must fail as `unattributed`. Scan-phase read IDs cannot masquerade as candidate-validation receipts.

A further artificial negative uses the C test-only independent early-ending stream (17-byte physical return chunks) wrapped by A's meter; the first candidate validates with partial-chunk reads correctly accumulated, while only 17 actual bytes are delivered from the **second** candidate before real EOF. The C validator must return `partial` / `validation.short_read`, and A must keep the second candidate `unattributed` due to absent complete coverage. This negative is not the same as the previously checked A source-quota exception.

## B/C/D research review context

- **B #112:** B-only observationally indistinguishable artificial healthy/damaged size records. On four scorable live records legacy TP1 FP2 FN0 TN1 versus conservative/audit TP0 FP0 FN0 TN1 UNKNOWN3, including one genuinely damaged record. These negatives prohibit fabricated independent size/allocation confidence.
- **C #111:** Existing test-only C helper can separately revalidate two CRC-consistent candidate tails, but zero original winners or A receipts are inferred; the A work here mints *genuine outer-meter* receipts for those C-discovered hypotheses. C observed 3,548 physical bytes over its small five-case research set, in addition to its independent scanner costs.
- **D #113:** Fixed FAT sampling windows 0/128/256 tested against prefix-only sampling under same per-invocation physical byte/call caps. Six scored artificial controls old TP3 FP0 FN1 TN2 vs bounded test-only candidate TP4 FP0 FN0 TN2, but five other cases UNKNOWN including unsampled remote entry512. Adds D P7 standalone regression to A runner. This never selects an authentic FAT copy, owner or repair plan.

## Safety and remaining acceptance

All inputs are generated 2MiB in-memory artificial bytes, passed through strictly nonwritable streams. C/D research tools are test-only, no separate-root output or repair is attempted, no raw fixture bytes or private filenames are committed. The unique ~31GB master IMG and physical microSD were not accessed, copied, hashed, scanned, uploaded, exported, repaired or written to. Real media testing remains **NOT APPROVED**.

The test establishes only structural validity and physical read-origin traceability on a narrow deterministic synthetic case; **CRC does not certify original content**. A must still add broader standards-shaped/multi-seed ambiguous and EOF controls and B/C/D cumulative source budget fault tests before R7 full acceptance. R8 separate-root export remains blocked. The fully gated engineering roadmap is still **39% (R0–R3 only)**; R4–R7 partial, not real recovery success.

**Verification:** exact-head Windows PS5.1 central 32/32 isolated synthetic scripts and privacy CI plus post-merge main CI must be independently checked and linked before claiming success.
