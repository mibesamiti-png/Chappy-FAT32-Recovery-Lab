# Team C R5 — 560B first-fragment bounded hypothesis ablation

**Issue:** [#72](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72) · **Draft PR:** [#121](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/121) · **A dispatch:** [comment #6822698980](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72#issuecomment-6822698980) · **assigned branch:** `feature/c-r5-560byte-firstpiece-20261112`. Reviewed starting main `6a2049d18a05c53a57987a8efe3ee9982a1a093b`; main `2011fbd19f4fede078c16af50b640d45dc81ea92` was one A-only update newer at start; no overlapping C edits. Earlier #116 was A-merged `adopt_experimental` only for the test-only +2 phase flag. **R0/R1 provenance was posted before code in [Issue comment #6823128640](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72#issuecomment-6823128640).**

## R0 — original technical evidence, limitations, reuse rights

| Primary source | Relevant mechanism and failure conditions | Rights and implementation choice |
| --- | --- | --- |
| [PKWARE ZIP APPNOTE](https://support.pkware.com/pkzip/appnote), [official format reference](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT) | Separate local ZIP headers, central directory and EOCD give format-constrained joins. A first piece can have arbitrary byte length; valid CRC does NOT authenticate an original ZIP when alternate metadata tails are possible. ZIP64, multi-volume, large embedded OPC/XML, encrypted files and arbitrary fragmentation remain outside this method | Published format reference; NO vendor specification text or source copied. Any third-party implementation reuse requires independent license review |
| Garfinkel (2007), [*Carving contiguous and fragmented files with fast object validation*](https://www.sciencedirect.com/science/article/pii/S1742287607000369), DOI 10.1016/j.diin.2007.06.017 | Small finite first/tail hypotheses plus fast container validation allow a controlled sensitivity test; each added size increases pair trials and can trigger candidate flood. Does not independently establish source or original identity | Paper concept only, independently written PS5.1 research. No published code/figure/assets copied; external code reuse **review_required** |
| [Microsoft .NET `Stream.Read`](https://learn.microsoft.com/en-us/dotnet/api/system.io.stream.read) | Actual returned bytes, not requested length, must be measured under 17B partial-read and EOF. Missing tail, short window, exhausting source/memory/pair budgets all remain incomplete or unknown | Built-in Windows PS5.1/.NET; no new package, vendor library or redistributed dependency |

## R1 — frozen reproducible synthetic comparison

- **Corpus:** `New-Chappy3DCleanFixture.ps1` blob SHA `c08fe5c5b7806d2eb9ed05b5ca6a9ffa51a4cdba`, `New-CVariableSyntheticCase`, seed `202611`, 2MiB FAT32-*like* byte image. Scored cases: `M01_control`, `non512_offgrid_tail`, `offgrid_first`, `offgrid_plus_two`, `nonlisted_first_560`, `alternate_zip_metadata`, `fake_eocd`, `missing_tail`. All scorer assertions are synthetic; not a mountable/fully standard FAT32 volume claim. The SAME case bytes feed each test arm using independent strictly nonwritable in-memory `Stream`s. SHA-256 of every source checked before and after.
- **Separation of truth:** `R5First560AblationRegression.ps1` alone reconstructs planted original bytes from separate generator oracle and evaluates original SHA, offsets and case labels. `Test-CVariableZipPairs`, the guard and the in-memory ZIP/3MF checker receive **no original offsets, true first length, SHA, FAT chain, winner labels or A source receipts**. A candidate SHA computed from observed reassembly is not an original-file authentication claim.
- **Fixed 4 arms:** standard phases ZIP-first `{0,+1}`, sizes `{512,544}`; prior opt-in `+2` first-phase `{0,+1,+2}` same sizes; new opt-in `560` first sizes `{512,544,560}` at phases `{0,+1}`; both flags combined. All use *unchanged* EOCD tail phases `{0,+1}`, exactly 2 ordered disjoint pieces and no true-tail-length hint.
- **Same absolute per-case caps for every arm:** <=65,536B initial scan (128 × 512B sectors), <=4 first starts, <=8 EOCD tails, <=16 pair attempts, <=**81,920 actual physical source-read bytes**, <=**98,304 separately counted in-memory format-validator read bytes**, <=30 seconds cooperative. Max joined candidate size **1056B**; no broader candidate size/pair cap. Candidate floods return `incomplete`, not one selected possible original. Code is *test-only*, default-off in `modules/carving/tests`, no production/extraction/shared-interface change.

## R2 — one bounded default-OFF size option and compatible safety gate

- `R5VariableZipPairResearch.ps1` adds `-IncludeFirstPiece560`. Its sole search-space change is adding **560** to allowed first-piece lengths. The already approved `-IncludeStartPhasePlusTwo` flag continues unchanged. With both flags absent, legacy scanner semantics and test cases stay unchanged.
- Existing `R5AmbiguousFalseJoinGuard.ps1` deliberately rejected any first span >544B. Its default threshold is **preserved**; a new separately explicit **`-AllowFirstPiece560`** opt-in accepts first spans <=560B only for this research evaluation. Without it, the *same newly structurally valid 560B scan result* is **still rejected as `guard.invalid_physical_spans` and `incomplete`**. No silent trust widening, original selection, or production adoption.
- New independent test-only scorer `R5First560AblationRegression.ps1` and C test entrypoint wire four arms on identical case bytes and exercise source/memory/pair/flood/early EOF negatives. No Team A/B/D or production files changed. No `evidenceId`, `sourceToken` or A-approved provenance minted by C.

## R3 — actual first successful code-head native Windows PS5.1 A/B measurements

**Windows synthetic suite SUCCESS [run #43215678318](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43215678318) at code HEAD `d05ac5e6908a57e65cad859ea52a730304a26802`. Matching privacy gate [#43215678319](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43215678319) SUCCESS. Additional strong negative controls and this document were committed **after** these runs, so the **FINAL SHA must independently pass BOTH CI gates** before A merges.

| Eight selected invented cases, per 8-case arm | Default | +2 phase only | New 560B only | Both opt-ins |
| --- | ---: | ---: | ---: | ---: |
| Original artificial SHA-exact accepted pairs TP | **5** | **6** | **6** | **7** |
| CRC-consistent but byte-wrong accepted pairs FP | **1** | **1** | **1** | **1** |
| Rejected evaluated candidate pairs TN | 26 | 29 | 41 | 46 |
| Physically present original cases missed FN | 2 | 1 | 1 | **0** |
| Cases `unknown` | 3 | 2 | 2 | **1** |
| `one_possible` / `ambiguous` / `incomplete` cases | 4 / 1 / 0 | 5 / 1 / 0 | 5 / 1 / 0 | 6 / 1 / 0 |
| Actual physical source `Stream.Read` bytes | **551,164** | **554,774** | **565,114** | **570,593** |
| In-memory C ZIP/CRC validator read bytes | **87,908** | **99,814** | **134,586** | **152,870** |
| Source read requests | 1,088 | 1,096 | 1,120 | 1,132 |
| Evaluated candidate pairs | 32 | 36 | 48 | 54 |
| Local first-start hypotheses | 7 | 8 | 7 | 8 |
| EOCD tail hypotheses | 18 | 18 | 18 | 18 |
| Windows elapsed summed on one runner, ms | 586 | 642 | 777 | 806 |
| False original identity claims / chosen original | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

**Why both improve:** the `+2` option rescues only `offgrid_plus_two`, and the 560B option rescues only `nonlisted_first_560`; combined rescue both. The missing-tail case always remains `unknown`. A physically different CRC-consistent but byte-wrong ZIP metadata tail remains separately accepted, so the ambiguous case is **never** reduced to a guessed winner. TP/FP/TN are *tested-pair units*, FN is *present-original case units*, and the pair denominators vary with work; do not compute a single real-world confusion matrix or recovery success rate.

**Measured cost of 560B alone over default:** +**13,950 actual source bytes**, +**46,678 separate memory-validator bytes**, +16 evaluated pairs and 32 source read requests across these 8 artificial cases, for exactly one extra SHA-exact positive. Both opt-ins versus default cost +**19,429 actual source bytes**, +**64,962 separate memory-validator bytes**, +22 pair attempts. Elapsed time varies across CI runners: larger fixture samples are needed before drawing speed conclusions. No overall speedup demonstrated.

**Fail-closed negatives:** fake extra PK local header at +2 and `MaxStarts=1` => `incomplete` with zero accepted outputs; deliberately restrict MaxPairs=1 on two-CRC-tail fixture => `incomplete`; CRC-consistent wrong metadata tail => `ambiguous`; missing tail => unknown; short 17B actually returned then EOF => incomplete; physically truncated `<65536B` image => incomplete before reads; physical source quota `1024B` => incomplete before reads; memory validator quota `6144B` => incomplete and no accepted partial candidate; writable source refused; SHA invariants hold. Separate last-added regression performs **actual reverse physical-span-order format validation** and a false-EOCD tail-storm => fail closed (these last two MUST pass on final HEAD). No A-issued trusted receipt or original identity claim.

## R4 — Team A disposition request and remaining issues

**Proposed `research_only` or `adopt_experimental` only with explicit default-OFF guard, at A's discretion.** The first-piece 560B addition finds exactly one planted artificial true pair at increased budget cost but does not generalize to unknown first lengths, arbitrary byte offsets, larger sources, three or more fragments, wrong FAT chains, ZIP64/full 3MF OPC/XML validation or independently authenticated original SHA. Production scanner/exporter never modified. A's test-only physical source meter has its own separate event/token trust contract; C's self-reported diagnostic reads must not become A-issued receipts. A owns any future R7 integration and quality gate; Team C never merges its own PR.

**Safety:** physical microSD and the sole unique ~31GB master IMG were NOT accessed/read/hashed/scanned/copied/written/repaired/extracted/exported/uploaded. Only tiny invented nonwritable memory streams. No real private filenames/recovered data/unredacted logs committed. Real-image approval stays **NOT APPROVED**.