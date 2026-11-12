# A R7 live multi-candidate read receipt and common-budget negative gate

**Scope:** Team A Issue #1, synthetic research only. Frozen main baseline: `0ded7b8f215405648d8f147c6cde8447b8d0615f`. The original microSD and unique ~31GB master IMG remain out of scope for reading, hashing, copying, scanning, modifying, outputting or uploading. Real-data authorization: **NOT APPROVED**.

## Integration question

A previously demonstrated a *single* test-only two-fragment 3MF candidate whose real C structural revalidation issued A-owned physical Stream.Read receipts, plus cross-source ID isolation. That does not establish that independent competing candidates on the **same generated source** cannot steal each other's evidence, or that budget failures leave partial results untrusted.

The new isolated test `tests/Test-A3DLiveMultiCandidateBoundary.ps1` runs existing A+C actual C synthetic scout and validator functions on nonwritable MemoryStream sources, then adds three bounded cases:

1. A valid ordered two-part synthetic 3MF candidate, plus a deliberate reversed-order competitor using **the same two physically observed extents**. The real C validator reads both separately, and A issues separate candidate-keyed receipts. Expected: first structural format-consistent; reversed format-rejected. Both can be `source_observed` without ever becoming `originalIdentity=verified`. Cross-attributing competitor receipt IDs fails as `unattributed`.
2. Deliberately mislabeled source phase: C truly rereads the candidate but A meter labels it `scan` instead of `candidate_validation`. Reads alone are not attributable candidate validator receipts, despite structure being otherwise valid.
3. Deliberate **single source-wide 1,024B quota**, first consuming 300B scouting then trying to validate the original 3MF candidate. First 512B is observed; second fragment cannot be read because the A wrapper refuses to return bytes that exceed remaining budget. C reports partial and A refuses full candidate coverage. No EOF or original-file recovery can be inferred.

Every claim uses A's actual physical event IDs, ordered candidate keys, source tokens and independent numeric returned-byte accounting. The test checks generated image SHA before/after and input `CanWrite=false`. The oracle stays outside the C analyzer. No input paths or export operations.

## Constraints and remaining R7 gates

- This is a **test-only** boundary on one intentionally small synthetic two-fragment M00 file; the competitor is constructed deliberately by A as a negative control rather than discovered by the C scanner.
- C still has a limited fixed-size/grid research search and no generalized production candidate attribution.
- Resource bounds follow the existing 120,000B A meter (or the 1,024B negative), strict C 2,048B candidate reread and bounded in-memory validator. Current C has no production self-issued A receipt authority.
- A future R7 gate must test real ambiguity from C's candidate discovery, true short-return/EOF (not just budget refusal), independent standards-shaped artificial volumes, and cross-team B/C/D cumulative caps. Until full R7 and predecessor stage gates pass, R8 separate-root export remains blocked.
- Official weighted R0–R10 engineering milestone completion remains **39%** (R0–R3 only). This is not recovery success.

This change adds the new test to the central Windows PowerShell 5.1 isolated regression runner: **29 to 30 scripts expected**. Do not claim completion until exact PR-head and post-merge main privacy/Windows CI pass.
