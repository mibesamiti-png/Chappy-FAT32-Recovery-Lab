# Team C R5 — separate physical validation of two CRC-consistent 3MF hypotheses

**Tracking:** Issue [#72](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72), Team C, assigned branch `feature/c-r5-multi-candidate-validation-20261112`, frozen reviewed `main` `9393fce2b9651b478a6861f7c44c26636acbfb86`, latest `main` observed at R0 `30b800f0a9c127164e5f22db3306250edf64b969`. Branch was 3 commits behind only in A-owned docs/runner/tests, **no conflicting `modules/carving/` files**. A's bounded task is Issue comment [#6815078389](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72#issuecomment-6815078389), with R0/R1 pre-code research comment [#6816649758](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72#issuecomment-6816649758). Prior C #106 merged by A `research_only`.

## R0 sources, prior-art limitations and licensing

| Approach | Original source | Positive principle and failure mode | Licensing / code import |
| --- | --- | --- | --- |
| ZIP container integrity | [PKWARE APPNOTE](https://support.pkware.com/pkzip/appnote), [official reference](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT) | Validate local headers, central directory, EOCD, member CRC independently on candidate bytes. CRC consistency is *not* evidence of byte-identical original; ZIP metadata can change while package still passes. ZIP64/multipart/full OPC not covered | Published format reference only; third-party implementation code rights not assumed; **NO upstream implementation/spec text copied**, license_review_required for any future reuse |
| Physical read observation | [Microsoft .NET Stream.Read](https://learn.microsoft.com/en-us/dotnet/api/system.io.stream.read) | Requested vs actual returned bytes differ on short reads; maintain precise source-relative intervals for the exact candidate. C self-report is *not* independently authenticated A meter evidence | Built-in Windows PowerShell 5.1/.NET, no redistributed third-party source |
| A-owned source receipt trust | [Team A R7 trust-boundary document](../../../docs/R7_CANDIDATE_READ_TRUST_BOUNDARY.md), `tests/helpers/Resolve-A3DReadEvidence.ps1` | A-issued physical event IDs and source-token binding are required to claim source-observed coverage. Cross-source, scan-only and spoofed candidate IDs fail | Existing project code; A owns integration and resolver. No A code edited or event ID minted by C |

## R1 frozen baseline and experiment design

- Identical deterministic **artificial 2MiB FAT32-like** source per method, generated from `tests/helpers/New-Chappy3DCleanFixture.ps1` blob `c08fe5c5b7806d2eb9ed05b5ca6a9ffa51a4cdba`, seed `202611`. Test-only `New-CVariableSyntheticCase` constructs M01_control, alternate_zip_metadata (one byte-exact original + one physically distinct, CRC-consistent wrong ZIP central metadata), fake_eocd, missing_tail, offgrid_plus_two. These byte fixture fragments do not claim a valid FAT chain or standards-certified FAT32 volume. Every input SHA-256 checked unchanged.
- **Baseline:** existing `Test-CVariableZipPairs` enumerates at most 4 starts, 8 tails, 16 pair trials, 65,536 source scout bytes/128 sectors, max 81,920 physical source bytes, 98,304 separate in-memory validator bytes, 30s cooperative. Existing `Resolve-CFragmentFalseJoinEvidence` preserves ordered physical hypotheses and rejects automatic winners, but does **not** perform independent per-hypothesis physical validation.
- **Exactly one alternative:** `Test-CMultiCandidateValidation` receives only an *already completed scanner result*, uses its bounded ambiguity guard, **re-reads all distinct two-span structurally possible physical hypotheses** separately with the previously test-only `Test-CObservedCandidateValidation`, and reruns the existing bounded C ZIP/3MF CRC validator on each reassembled byte stream. No true first/tail positions, original SHA, valid FAT chain, file path, candidate origin source token or A receipt fed to analyzer. The independent external scorer alone compares candidate SHA to generated original SHA.
- **Bounded expanded test-only first piece:** original validator's max first/second span 512B was adjusted to <=544B/span and <=1056B joined so it can measure the already existing 544B first-piece case. New wrapper caps accepted candidate count <=2, total additional physical Source.Read bytes <=2048 **across both candidates**, total separate validator-memory bytes <=16384, max 10s cooperative, and no writable stream. Each individual re-read remains <=2048 source, <=8192 validator memory and <=5s. No change to production `Chappy.Carving.psm1`, real file reading, file export, A/B/D or shared schema.
- **Exact physical identity:** `3mf:offset+length,offset+length` in fragment order. No SHA deduplication or sorting physical pair roles, no picking one based on format/CRC. Out-of-cap/partial second recheck => `status=partial`, `decision=incomplete`; missing candidate => `unknown`; exactly two independently confirmed candidates => `ambiguous`. All results retain `originalIdentity=unknown`, `selectedOriginal=null`, `canAutoSelectOriginal=false`, `originStatus=unattributed_pending_A_meter_receipt`. C does not create even *one* trusted `evidenceId` or `sourceToken`.

## R3 actual Windows PowerShell 5.1 synthetic A/B

**Initial exact-code-head Team C Windows CI PASS:** https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43169906613 (commit `31a0db60c8ab5413a8eba239f14df26826a9f120`). These are measured logs; **final research-doc HEAD CI must separately pass before Team A review**.

| Metric; five selected artificial cases | Existing scan/guard baseline | Same scan + new per-hypothesis physical validation |
| --- | ---: | ---: |
| Pair hypotheses actually enumerated | 20 | 20, same scan bytes |
| Structural true pairs matching independent original SHA (TP) | 3 | **3**, reread/CRC rechecked |
| Structurally accepted, byte-wrong (FP) | 1 | **1**, kept distinct |
| Rejected tested pair hypotheses (TN) | 16 | **16**, no new scan |
| Cases with present original missed (FN, case unit) | 1 (offgrid +2) | **1** |
| Case decisions | 2 one_possible, 1 ambiguous, 2 unknown | **Same** (no automatic original winner) |
| Physical source bytes in initial discovery | **344,042B** | **344,042B**, identical scanner cost |
| Additional actual physical source byte returns | **0B** | **3,548B** (four accepted hypotheses across five cases) |
| In-memory format-validator read bytes from scan | **53,116B** | **53,116B** |
| Additional per-candidate validator-memory reads | **0B** | **10,644B** |
| Additional physical read requests / intervals | Not candidate-specific | **8 requests / 8 returned intervals** |
| Measured summed Windows time | 396ms scan | 356ms independent scan + 78ms second-pass validation |
| False 'verified original' or automatic selections | **0** | **0** |
| C-minted A trustworthy receipt IDs | **0** | **0** |

Pair-level TP/FP/TN count only the **20 enumerated** hypotheses; case-level FN counts one original physically present but outside predefined phase hypothesis set. These denominators are different; computing global file-recovery recall or real-world precision from them would be misleading. A positive ZIP/CRC structure remains a *possible* file hypothesis; even a candidate SHA value is not a verified independent original unless the external artificial scorer matches it. Windows timings vary between runs and this method intentionally adds I/O; no claim of improved detection or speed.

Per-case new physical reread: M01_control **887B** (one accepted), alternate ZIP metadata **1774B** (two physically different and independently CRC-consistent), fake EOCD **887B** (one accepted), missing tail **0B**, and +2 offgrid start **0B**. In the ambiguous case, the *external scorer only* finds exactly one original-byte-equal and one byte-different candidate. Both remain returned as separate hypotheses, `ambiguous`, with no auto-selection.

**Negative controls (Windows PASS):** budget set to the first candidate's exact read bytes completes first but refuses second with `multi.shared_physical_budget` and no picked winner; strictly nonwritable artificial stream returning 17B of the second candidate then zero yields `multi.candidate_partial`, correct actual returned bytes, no full coverage; reversed physical fragment order has different identity and fails ZIP validation; fake EOCD yields rejected pair and no original promotion; missing tail/unsupported +2 offset remain unknown, writable input rejected. All source SHA invariants hold.

## R4 proposed Team A decision and handoff

**Recommend `research_only`**, tests/doc only; this demonstrates feasibility and extra cost of separate physical observation of two CRC-valid artificial hypotheses. It does NOT solve original provenance, generic recovery of unknown-sized/off-grid fragments, 3+ fragments, ZIP64/OPC/XML or R7 source trust. Only A may mint actual source meter receipts and reconcile candidate-specific physical read IDs/token/order to its trusted resolver. C's `observedPhysicalReads` remain *untrusted diagnostic self-reports*. Even independent A observed source bytes cannot establish original SHA. Any adaptation to A-owned runner/schema requires explicit separate A review.

**Absolute safety:** physical microSD and sole unique ~31GB master IMG never accessed, read, scanned, hashed, copied, repaired, written, extracted, exported or uploaded. No real user filenames, content or raw logs. Real-media gate remains **NOT APPROVED**.