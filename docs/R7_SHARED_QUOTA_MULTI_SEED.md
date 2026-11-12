# A R7 — multi-seed shared physical read quota on B/C/D

**Scope:** Team A Issue #1, synthetic-only research. Reviewed starting main `59525c560399b61f6668d321b1fb26c30ca24a84`. A reviewed and merged B #118, C #116, D #117 with exact final-HEAD Windows PS5.1 and privacy successes. The new A branch starts from merged main `1b1812874d9961f0735866f4210a3441daf40a48`.

## What this A-owned integration regression does

`tests/Test-A3DSharedMultiSeedQuota.ps1` reuses the already reviewed A synthetic `ChappyA7SharedSource` outer nonwritable `Stream.Read` meter, and runs actual B directory, C carving and D sampled FAT analysis APIs one after another on the **same** physical generated source. Frozen research matrix: seeds 202611, 202612, 202613 × M00 healthy, M01 valid fragmentation, M02 FAT1-link fault, P02 structurally plausible payload fault = **12 artificial 2MiB inputs**. The generator's oracle/truth is NOT passed to any B/C/D parser.

Every individual fixture uses **ONE shared cumulative 120000 actual returned-byte limit** across geometry+B+C+D; the meter records consumer, physical offset and returned byte count per successful source operation. The test independently reconstructs a byte-coordinate union from actual A source events, asserting `total=distinct+duplicates`, source events and B/D bytes are consistent, bounds and read request counts hold, all inputs remain SHA-unchanged, B/C/D sources are nonwritable, and D never selects an authentic FAT mirror or repair action. C `verified` is interpreted only as structural-format validation, **NOT** original file integrity.

After completing all four parsers, each run attempts one **additional** physical read strictly larger than its *remaining* shared quota. The A wrapper must throw its exact source-budget exception without any actual byte read or fabricated EOF, and without changing event history or source SHA. The independent scorer maintains case IDs and seed truth; per-case coverage unions are never combined into one image's unique byte count.

Also adds D's research-only fixed 0/128/256 vs 0/256/512 remote FAT-sampling tradeoff regression (#117) to A's isolated native Windows PowerShell 5.1 runner. Expected **32→34 scripts**. This is a broadening of tiny FAT32-like artificial evidence, **not** standards-wide FAT32 restore verification and not a real-data benchmark.

## Adoption and remaining stage gates

- B #118 research_only: 3 seeds, 12 scored size records, legacy TP3 FP6 FN0 TN3 vs conservative TN3 UNKNOWN9 including three damaged; no false original-size attribution.
- C #116 adopt_experimental/default OFF within test-only +2-byte local ZIP start phase. Selected 8 cases pair TP5→6, FP1→1, but 560B first piece still missed; work increases. No automatic original SHA/CRC winner.
- D #117 research_only: equal physical sample caps, schedule choice shifts missed remote FAT anomalies (old and new each TP5 FP0 FN1 TN2 on selected 8 anomaly cases; entry768 unknown); no FAT-copy winner.

R7 still incomplete: A must run standards-shaped larger volumes, broaden actual multi-format and candidate-specific source receipts under one B/C/D cap with real partial source EOF, and test false confidence adversarially. R8 separate-root export not enabled. Official R0–R3 full milestone acceptance **39%**, R4–R7 partial. Tests/production never touch real media. User's sole 31GB master IMG and microSD have never been accessed, read, hashed, copied, scanned, written, repaired, extracted or uploaded; local real-data approval **NOT APPROVED**.

**Verification:** link exact-head Windows 34/34 isolated suites + privacy CI and post-merge main CI only AFTER they actually complete; if this test fails, repair code and rerun exact final HEAD before A merge.
