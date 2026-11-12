# Team C R5 — bounded +2-byte 3MF/ZIP header-phase coverage research

**Tracking:** [Issue #72](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72) · assigned branch `feature/c-r5-offgrid-twofragment-coverage-20261112` · [Draft PR #116](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/116). Team A assigned the task in [Issue comment #6821364610](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72#issuecomment-6821364610). The **R0/R1 note was posted before code** in [comment #6821635864](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72#issuecomment-6821635864). Frozen A-reviewed branch baseline `4a378fc32cfd6603e20b5acbbfa0328a6a718770`; main observed at start `59525c560399b61f6668d321b1fb26c30ca24a84` one A-only docs/runner update later. C changes do not overlap A/B/D scope.

## R0 — original sources and code licensing

| Approach | Primary source | Assumptions, failure modes and PS5.1 suitability | Rights / code reuse |
| --- | --- | --- | --- |
| ZIP/3MF byte structures | [PKWARE APPNOTE](https://support.pkware.com/pkzip/appnote), [format reference](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT) | ZIP local PK header can begin at any byte, not just sector boundaries; EOCD/CRC/central directory are structural validation only, not original-file identity. False headers and incomplete ZIP64/OPC/multipart defeat simple detection. A finite phase expansion is cheap; full archive conformance is not | Published format description only. No vendor source/text/code imported. Third-party implementation reuse requires separate license review |
| Finite bifragment hypotheses | Garfinkel (2007), [*Carving contiguous and fragmented files with fast object validation*](https://www.sciencedirect.com/science/article/pii/S1742287607000369), DOI 10.1016/j.diin.2007.06.017 | Ordered two-part hypotheses and format validation; more offset phases increase search and false-positive work, arbitrary fragmentation remains unsolved | Academic concepts only; no copyrighted code/figure/paper text copied; third-party source license review required before reuse |
| Exact read cost / early EOF | Microsoft [.NET `Stream.Read`](https://learn.microsoft.com/en-us/dotnet/api/system.io.stream.read) | Measure actual returned bytes, not request lengths; 17B then EOF, byte-cap shortages and writable streams must fail closed. Supported by native PS5.1 built-in .NET | No third-party library imported or redistributed |

Background [3MF official Core/OPC specification](https://3mf.io/spec/) and [spec repository](https://github.com/3MFConsortium/spec_core) are referenced for format context only. No third-party ZIP parser, GPL PhotoRec source, specimens or real user file content copied. Source release license for the project as a whole is not assumed.

## R1 — frozen baseline and independent scorer

- **Artificial corpus:** existing 2MiB FAT32-*like* images created from `tests/helpers/New-Chappy3DCleanFixture.ps1` SHA(blob) `c08fe5c5b7806d2eb9ed05b5ca6a9ffa51a4cdba` and `New-CVariableSyntheticCase`, seed `202611`. These are not proven valid standards-shaped FAT32 volumes. Identical bytes and all predeclared scenario truth are held outside the algorithm in `R5OffgridTwoFragmentRegression.ps1`. Independent original SHA, planted source offsets/lengths and missing-tail labels are read only by that **external scorer**.
- **Unchanged baseline:** existing C **test-only** `Test-CVariableZipPairs`, ZIP local-header first-anchor sector phases `{0,+1}` and EOCD phase hypotheses `{0,+1}`, first-slice sizes `{512,544}`. Fixed scan window **65,536B / 128 512B sectors**, <=4 starts, <=8 tails, <=16 ordered pair attempts, <=**81,920B physical source bytes** and <=**98,304B separately counted memory-validator bytes** per case; <=30 seconds cooperative. Both baseline and experiment receive precisely these same caps and read independently from the SAME generated case bytes. Full provenance/original SHA not supplied to scanner. `Resolve-CFragmentFalseJoinEvidence` preserves two accepted ordered hypotheses and no automatic original winner.
- **Eight cases predeclared before code:** `M01_control`, `non512_offgrid_tail`, `offgrid_first`, `offgrid_plus_two`, `nonlisted_first_560`, `alternate_zip_metadata`, `fake_eocd`, `missing_tail`. The *same case set and labels* are evaluated in baseline and alternative; nonlisted 560B is a required failure control, not newly included in size hypotheses.

## R2 — single opt-in alternative, only C research tests

- Add **default-OFF** `-IncludeStartPhasePlusTwo` to `modules/carving/tests/R5VariableZipPairResearch.ps1`. When ON, **only** the ZIP *local-header start* phase set becomes `{0,+1,+2}`. The EOCD tail phases remain `{0,+1}` and supported first-slice lengths remain `{512,544}`; no other search algorithm, source budget, validator semantics or production exports change.
- New scorer-only `modules/carving/tests/R5OffgridTwoFragmentRegression.ps1` runs both modes on identical 8-case artificial source streams. Existing `Test-ChappyCarving.ps1` wires it into native Windows tests. No A runner, B/D files, public shared interface, production ZIP carver, export or source write is modified.
- Each candidate remains `originalIdentity=unknown`, `integrityScope=structural_only_not_original_file_integrity`. CRC-valid but byte-different ZIP directory alternatives stay `ambiguous`. `Resolve-CFragmentFalseJoinEvidence` confirms `selectedOriginal=null` and `canAutoSelectOriginal=false`. No trusted A source receipts minted; source span observations are diagnostics, not real provenance.
- Negative controls include a **false PK local header in a sector+2 position** exceeding `MaxStarts=1`, forcing `incomplete` without selecting any early true candidate; synthetic stream returns **17 actual source bytes then early EOF** (partial/incomplete); too-small 1,024B source budget returns incomplete before reads; reversing ordered fragments cannot validate the original; ZIP false EOCD is rejected; missing tail and genuine 560B first slice stay unknown; writable source is refused. All original synthetic source SHA checks unchanged.

## R3 — actual measured Windows PS5.1 artificial A/B

**Windows C test on implementation HEAD `a07a8b4be39c4b3df380889cff9f572dab8f9693` [SUCCESS #43204894233](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43204894233)**. The privacy CI [#43204894450](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43204894450) had not finished at first check. **The final research-document HEAD must have its own two passing CI runs before A merges.**

| Metric across 8 fixed invented cases | Existing 0/+1 baseline | +2 first-header research option |
| --- | ---: | ---: |
| Byte-identical original pairs TP (pair hypotheses) | **5** | **6** |
| CRC-consistent but byte-different pairs FP | **1** | **1** |
| Rejected pair hypotheses TN | **26** | **29** |
| Physically present original case missed FN (different unit) | **2** | **1** |
| Unknown cases | **3** | **2** |
| One possible / ambiguous / incomplete cases | **4 / 1 / 0** | **5 / 1 / 0** |
| Physical `Source.Read` returned bytes, aggregate | **551,164B** | **554,774B** |
| Source read requests, aggregate | **1,088** | **1,096** |
| In-memory C ZIP/3MF validator bytes | **87,908B** | **99,814B** |
| Candidate pair trials | **32** | **36** |
| ZIP local-start hypotheses | **7** | **8** |
| EOCD tail hypotheses (unchanged phase) | **18** | **18** |
| Windows elapsed total (one CI runner sample) | **227ms** | **214ms** |
| Automatic original-file selections / false original claims | **0 / 0** | **0 / 0** |

**One demonstrable added coverage:** `offgrid_plus_two` baseline `unknown` with no original SHA match; option `one_possible` with one independent SHA-exact artificial match. The option adds **3,610B physical reads**, **11,906B validator-memory reads**, 4 pair trials and 8 source read requests in this fixed test. The 560B true first piece remains missed/unknown. CRC-consistent wrong metadata tail remains separately plausible alongside the actual synthetic original (ambiguous). Fake EOCD is enumerated then rejected; missing tail unknown.

**Comparability caveats:** TP/FP/TN are *evaluated candidate-pair* units, while FN and UNKNOWN are *case* units; they do not form a single population confusion matrix or a real recovery success rate. Both algorithms share fixed read caps; adding a header phase naturally increases possible pair attempts and can cause an `incomplete` result under denser fake signatures. This one Windows run does **not** establish a runtime speedup: 227ms vs 214ms is noise-level timing, only the I/O/probe delta is repeatable on this deterministic fixture.

## R4 — A-only adoption decision, unresolved limitations

Recommend **`research_only` / default OFF** pending A review and exact final-head C Windows/privacy checks. This controlled extension demonstrates sensitivity to a known +2 phase but still fails on 560B first fragments, arbitrary first offsets, arbitrary sizes, missing blocks, unknown fragment counts, ZIP64/full 3MF OPC/XML and more numerous false PK candidates. It cannot decide which CRC-valid candidate is the independent original. Future work should use larger/balanced artificial scenarios and account for total B/C/D read budgets; changes to A-owned physical receipt resolver require a separate A task.

**Safety:** physical microSD and the sole unique ~31GB master IMG have NOT been accessed/read/scanned/hashed/copied/extracted/written/repaired/uploaded. Only generated non-writable synthetic memory streams were used. No raw user paths, filenames, recovered user files or private logs committed. Real-media gate **NOT APPROVED**.