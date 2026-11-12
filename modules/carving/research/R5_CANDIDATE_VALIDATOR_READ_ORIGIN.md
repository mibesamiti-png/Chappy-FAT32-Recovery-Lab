# Team C R5 — candidate-specific physical validation reads, untrusted until A receipt

**Scope:** Issue [#72](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72), existing Team C; assigned branch `feature/c-r5-candidate-validator-origin-20261112`; frozen A-reviewed main `9be7bb6d5f67d5a88074f085ea0ea417de570944` and next main at start `edd2045fec610a04b4184d56ea63c0239c4431ac` (one A-owned commit ahead). R0/R1 research card recorded first in Issue comment [#6813749548](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72#issuecomment-6813749548). Previous Team C #96 was merged `research_only`, and no other C PR was open at start.

## R0 primary sources and code rights

| Primary source | Applicable principle, limitations and failure cases | License / code use |
| --- | --- | --- |
| Microsoft .NET [`Stream.Read` API](https://learn.microsoft.com/en-us/dotnet/api/system.io.stream.read) | Actual returned byte count, including partial/zero, not requested length, measures physical bytes accessed by the specific client stream. A caller may still lie about provenance of returned values; the outer owner must witness read events | Windows PS5.1/.NET system API, no external code copied or redistributed |
| PKWARE official [`APPNOTE`](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT) | A ZIP central-directory/EOCD and CRC consistency check is conditional structure; forged metadata, fake EOCD and changed original bytes are still possible | Format reference only, no copied implementation or specification text; external source-code license unspecified and no code import |
| Team A original [`R7_CANDIDATE_READ_TRUST_BOUNDARY.md`](../../../../docs/R7_CANDIDATE_READ_TRUST_BOUNDARY.md), and `tests/helpers/Resolve-A3DReadEvidence.ps1` | Accept only **A-issued outer physical meter event IDs** tied to the source token, precise ordered candidate identity, purpose=candidate_validation and full read coverage. Whole-window scans and C self-asserted events are insufficient | Existing project source; A retains ownership of trust gate. C has **not** copied/modified A's resolver and does not issue event IDs |

## R1 immutable baseline and experiment definition

- **Identical generated source bytes:** `New-ChappyA3DDamagedFixture -Seed 202611` for M00 (contiguous 3MF), M01 (physically split 3MF) and P02 (synthetically altered 3MF compressed payload); a separate M01 clone has only an invented fake EOCD. The source is a **2MiB FAT32-like synthetic byte image**, not a mountable standards-guaranteed FAT32 volume. Its SHA is checked before and after the research test.
- **Baseline** `Test-CM01FiniteZipPairs`: bounded scan <=65,536B, <=4 ZIP starts, <=8 EOCD tails, <=8 join attempts, <=73,728B **physical source read cap** and <=40,960B separately counted in-memory ZIP validation. Returns candidate source spans, but no actually witnessed A physical read receipts **for a particular candidate**. No scanner bytes may be automatically upgraded to validation evidence.
- **Experimental path:** keep baseline candidate discovery unchanged, then (only for each discovered candidate, with no scorer oracle) call the new test-only `Test-CObservedCandidateValidation`. It physically rereads the two **ordered physical spans** on the same non-writable synthetic stream, recording **offset, requested and actual returned length for every `Read` call** and an ordered deterministic candidate key. The exact reread assembled bytes are passed to the unchanged C CRC-enabled bounded 3MF structural checker in a separate **in-memory** stream.
- **Hard caps per candidate:** 2 nonoverlapping spans, each <=512B, <=1024B joined, <=2,048 actual physical read bytes, <=8,192 separate in-memory checker bytes, <=5s cooperative. The first read may return fewer bytes than requested and zero terminates validation as partial. Source must be readable/seekable/non-writable and <=2MiB. Discovery and candidate second-pass reads stay separated in the metrics. No writes, paths, repair, extraction, or production scanner changes.
- **Absolutely no original truth in the method:** candidate spans come from baseline proposals; original source SHA/true extents are only read by the external scorer. Even a CRC match yields `originalIdentity=unknown` and `integrityScope=structural_only_not_original_file_integrity`.

## R2 and R3 measured artificial result (first complete code CI)

Windows PowerShell 5.1 [Team C Actions #43150631792](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43150631792) **PASS** at implementation HEAD `f63fbc43c9243e162c3234c1c7be9d8c14e73683`. Additional separate elapsed-time counters and this research document were committed afterward, so **final exact HEAD CI must pass separately**.

| Measure | Discovery only (existing baseline) | C physical candidate reread + same format validator |
| --- | ---: | ---: |
| Invented images | 4 | Same 4 |
| Candidate proposal hypotheses | 5 | Same 5 (no newly discovered candidates) |
| CRC/3MF structural matches | 3 | 3, independently rechecked |
| Rejected / inconsistent pairs | 2 | 2 |
| Byte-identical known artificial originals (external scorer) | No candidate-bound read proof | 3 across positive pairs |
| Physical source bytes, aggregate | **266,250B** | **+4,106B** (extra real `Stream.Read`, 5 candidate rechecks) |
| Candidate-bound actual physical read calls / intervals | **not measured** | **10**, ordered, 2 per candidate |
| Additional in-memory C validator read bytes | Already recorded aggregate but not A-attributable | **12,327B**, separately |
| A-issued trusted event IDs / attached source tokens | **0** | **0** (C is not permitted to mint them) |
| Original byte identity claims | **0** | **0** |

Individual artificial cases: M00 1 proposal/1 structurally consistent, 66,423 discovery source bytes and 67,310 total with reread; M01 1/1 and same totals; P02 1/0 and 67,310 total; M01+fake EOCD 2 proposals/1 consistent, 66,981 discovery and 68,426 total. The added physical validation reads were actual observed per candidate but remain **C diagnostic self-report**, not an A-signed independent meter receipt. No performance improvement is claimed: the second pass costs more work by design.

Negative tests: deliberately return **17 actual bytes then 0** from a short-read synthetic stream; output remains partial/unknown, 17 reported bytes, no validation success; stop at 512B source quota after partial first span; physical full reads followed by insufficient in-memory validation budget stay incomplete; reverse physical fragment order has a distinct key and cannot validate as same file; writable source is refused. No forged A event IDs are generated. Missing/invalid proposed ranges and overlapping spans fail closed in helper; full source SHA unchanged.

### A contract proposal — request, not a claim of completed binding

Only A should wrap or otherwise own the physical `Stream.Read` meter. The C phase would emit: ordered `candidateKey=3mf:offset+length,offset+length`, two `sourceSpans` with source-relative byte ranges, diagnostic `observedPhysicalReads[]` records (actual offset, requested count, actual returned count, purpose and candidateKey), status (partial/format_consistent/format_rejected), separately budgeted physical/memory read totals. **None is an A receipt until A witnesses the same reads**. A may mint fresh `evidenceId` values with its `sourceToken`, consumer `carving`, purpose `candidate_validation` and *exact* `candidateId` from the outer meter; thereafter A's own resolver may compute coverage. Never upgrade a scan event or C-supplied event ID to `source_observed`. Even full A coverage must keep `originalIdentity=unknown` and cannot prove CRC-original SHA.

## R4 adoption gate and unresolved issues

**Team C proposes `research_only`**. Measuring actual candidate-specific physical rereads is possible on tiny artificial data, but C has no authority to issue A trusted meter receipts or change the shared resolver. This is NOT completed R7 source attribution. Pending A-only adapter work: bind outer meter receipt IDs to the exact phase, handle multi-source and repeated candidates, total shared budget and short-read distinctions. Team C makes no changes to A runner, shared helpers, B/D modules, production carver or exporter.

The user's physical microSD and sole ~31GB master IMG were NOT accessed, scanned, hashed, copied, written, exported, repaired or uploaded. Only generated synthetic source; real-media gate **NOT APPROVED**. Structural acceptance figures are not actual recovery statistics.