# A R7 — standards-shaped C data-region shared-read bridge (synthetic only)

Date: 2026-11-12 JST. Owner: Team A, Issue #1.
Starting reviewed main: `a26c204a4f82fdfaae884344d4a840e629e07fb7`.
New B #125 (research_only), C #127 (adopt_experimental, default OFF, test-only), D #126 (research_only) were reviewed at exact final PR heads and squash-merged individually. Neither production reconstruction nor export is enabled.

## Bounded P1

`tests/Test-A3DStandardDataWindowBridge.ps1` exercises actual B geometry and root, C's **research/test-only** `Invoke-CStandardDataTrial -EnableDataWindow`, and actual D FAT evidence against the same `ChappyA7SharedSource` nonwritable source stream. The test invokes A's existing shared-meter regression in its isolated process. The A runner adds the separate D standard-FAT physical-coverage regression, too.

Two independently generated ~32.5/64.5 MiB standards-shaped FAT32-classified memory sources use seed 202611, sectors-per-cluster 1 and 2, and the existing independent artificial 3MF oracle. The scorer alone owns the correct extents and SHA. Neither the B, C nor D module receives original truth. Every source has one **120,000 actual-returned-byte physical cap**, not a cap reset per module; D additionally retains its own 2,048B scope. The C bounded data window is 65,536B with finite extra validation budget 32,768B. No full-volume search.

A checks physical returned-byte event unions against total/unique/repeated source bytes; the real C returned count against A's `carving` events, and D returned count against A's `fat` events. B root bytes are independently compared with A's `directory` observations. Invalid out-of-bounds data-start hints and intentionally insufficient C subquota must return UNKNOWN without physical reads. Physical global quota refusal must throw without consuming bytes or inventing EOF/events. Inputs are SHA-checked unchanged; no disk paths, output, recovery, or private data.

## Acceptance scope / known gap

This is a **test-only integration gate**, not production provenance or authenticity. The A meter has consumer-labelled numeric offsets; it does **not** mint candidate-specific A source-token receipt IDs for this C data-window path. Geometry comes from a real B parser call observed by A's meter, but a structurally plausible forged metadata object could be substituted by an untrusted caller; independent, non-forgeable per-candidate authority is not yet available. C returns partial/incomplete and originalIdentity=unknown. CRC/ZIP structure is not original-byte identity. External scorer checks one-file byte exactness solely on artificial sources.

Successful PR-head native Windows PowerShell 5.1 and privacy CI are required before Team A merges. After that, post-main CI must be checked. This work does **not** pass full R7. R8 separate-root export stays BLOCKED; real microSD and sole ~31GB master IMG are NOT APPROVED for any read/hash/scan/copy/write/extract/repair/upload. Official weighted synthetic-engineering progress remains **39%**, only R0–R3 fully gated. No real-world recovery rate can be inferred.

Next A P1: candidate-specific **A-issued source/validation read receipts** on the actual C data-window candidate spans, contradictory/unknown BPB controls and independent per-source quota, without making external artificial oracle truth a scanner input. Preserve all B/C/D branch ownership and research-only/default-OFF decisions.
