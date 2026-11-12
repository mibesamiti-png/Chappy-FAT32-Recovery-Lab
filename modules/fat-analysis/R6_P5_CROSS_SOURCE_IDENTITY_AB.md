# Team D Issue #73 — R6-P5 independent-source FAT read identity A/B (research only)

**Tracking:** [Issue #73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73), [Draft PR #101](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/101). Team A assigned `research/d-r6-observed-source-identity-20261112` from reviewed main `9be7bb6d5f67d5a88074f085ea0ea417de570944`. Main was `edd2045fec610a04b4184d56ea63c0239c4431ac` at startup, one unrelated commit ahead. Existing D #94 integrated `research_only`; no duplicate implementation.

## R0 — reference methods, source attribution, licensing

R0/R1 research registration was posted to [Issue #73 comment 6813752305](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6813752305) **before writing source**.

| Primary publication / publisher | Applicable principle and limitations | License/status |
| --- | --- | --- |
| Karen Kent et al., NIST *SP 800-86 Guide to Integrating Forensic Techniques into Incident Response* (2006), https://csrc.nist.gov/pubs/sp/800/86/final | Identify the acquisition source and verify integrity; matching volume-relative offsets do not identify an image. NIST forensic guidance is not an oracle for a damaged file's original contents | Published reference guidance, **no text/code imported or copied**; related publication terms are not an automatic code-reuse grant |
| Brian Carrier / Sleuth Kit Labs, https://www.sleuthkit.org/sleuthkit/ ; official code https://github.com/sleuthkit/sleuthkit ; license notes https://www.sleuthkit.org/sleuthkit/licenses.php | Multiple independent disk images can have identical file system geometry; source identity must be external to a FAT-offset event | Mixed file/component licenses (IBM/CPL, GPL, MIT/BSD): `license_review_required` if reusing, **none reused** |
| Microsoft Corporation, *FAT32 File System Specification v1.03* (2000), reference archive https://www.osdever.net/documents/fatgen103.pdf | FAT1/FAT2 numeric coordinates, copy agreement and a source image's provenance are different facts | Copyrighted spec; no implementation/text copied, rights review needed for reuse |

The proposed test-only interpretation and external scorer were independently authored, using only bundled PowerShell 5.1/.NET and the already accepted Team D read-only module.

## R1 — frozen synthetic baseline and paired truth

- **No production D algorithm change.** Baseline: `Get-ChappyFatObservedIoEvidence` from D PR #90, merged and default OFF. A's source identity boundary in #97 remains A-owned. Do not forge A-issued receipts.
- Existing A fixture helper `tests/helpers/New-Chappy3DDamagedFixture.ps1`, blob `58fedb62d76f15ebb003e4440d5f9c90feba25c5`, seed **202611**. Generated two-megabyte FAT32-**like** M00 clean, M02 mismatched copy and M03 same-broken-mirror images. Separately regenerate M03 twice; their **synthetic bytes and SHA are equal**, but the scorer defines two distinct externally managed source identities. The analyzer never sees these external source identities, SHA, case IDs, mutations, original file ownership, or any real user data.
- Nine deterministic **pairs of already-open strictly non-writable seekable Streams**: 4 scorer-attested same source, 3 scorer-attested different sources, 2 unattested/unknown. Two distinct source images use overlapping numeric FAT offsets (including a byte-identical pair). Same physical source may be independently wrapped. The scorer's mocked `external_synthetic_*` labels are **not authenticated A receipt IDs and must not be accepted in production**.
- Each independent D call has the same max **2,048 returned physical bytes** (one deliberately tightened to 32 bytes). Each pair therefore has hard sum cap **4,096** bytes, except the 32B subcase. This is NOT the A-owned 120,000B cross-team shared-meter gate.
- Short returning source: 7-byte chunks and cutoff after **1,150 actual bytes**, preserving advertised source Length. Existing geometric `trustDecision=reject` for readable but synthetic untrusted MBR/VBR; `insufficient_evidence` for 32B truncated geometry. Even with same outer source token, incomplete FAT observation stays partial.
- The **source-identity scorer** owns true pair identity and separate synthetic SHA only. TP/FP/FN/TN count *wrong source joins*, **not FAT corruption detection or original-file recovery**. Unattested pairs are unknown/excluded, never TN.

## R2 — one test-only alternative and negative controls

`tests/Run-TeamD-R6-SourceIdentity.Tests.ps1` calls unchanged D instrumented read-only FAT module on the paired synthetic streams. It compares:

1. **Naïve baseline:** any overlapping numeric FAT/geometry byte positions means the two reports came from one source; known unsafe.
2. **Test-only source-scoped union:** numeric read-event coordinates are namespaced **only by external scorer-attested source label**, not by D report IDs or matching hashes. Different outer sources must have separate physical-byte unions even if their contents and offsets are equal; untrusted or missing outer identity returns `unknown` with no combined source-unique count. The event-derived union is cross-checked against an independently rebuilt source-local *range-derived* union. This is a test boundary, not a new production model.

Controls include M00/M02 source mismatch with identical geometry, byte-identical M03 regenerated independently, real same-source repeated wrappers, premature 1,150B return with 7B chunks, 32B source cap, and two unknowns with missing/untrusted identity. Reports retain `sourceDecision=not_selected`, `selectedCandidate=null`, `writePermitted=false`, `originalIdentity=unknown` (join-only), and untrusted or insufficient FAT geometry. SHA on every generated in-memory source is checked before/after. No directory owner or recovered file contents are asserted.

## R3 — measured Windows PowerShell 5.1 synthetic A/B

**Code HEAD `00f059e1fdbc1439506924fdb1241b2d9ed2b194`:** [native Windows synthetic Team D CI #43151421974 — SUCCESS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43151421974), **new P5 106/106 assertions PASS**, previous D suite steps PASS. Matching code-head privacy CI [#43151421984](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43151421984) is separately verified before final handoff. The final documentation-only PR HEAD must be checked again.

| Same exactly nine synthetic pairs | Naïve overlapping-offset baseline | Externally source-scoped test alternative |
| --- | ---: | ---: |
| TP: correctly same external source | **4** | **4** |
| FP: *different* external source incorrectly joined | **3** | **0** |
| FN: same source missed | **0** | **0** |
| TN: correctly different source | **0** | **3** |
| Unattested and unscored pair identities | 2 | 2 (held unknown) |
| Actual bytes returned across 18 independent calls | **27,714** | Same underlying calls, not an extra scan |
| Sum of local unique source bytes *per call* | **26,782** | Same reports |
| Repeated physical reads within calls | **932** | 27,714 − 26,782; not global distinct across all pairs |
| Underlying Stream.Read() calls | **480** | Same reports |
| Original file byte-identical recovery | not evaluated | not evaluated |
| New source content authenticity guarantee | none | none |
| Writer/FAT winner/file owner assertions | 0 | 0 |

All selected pairs share some numeric FAT/geometry offsets, including different independent images. The naïve baseline therefore falsely joins all 3 different-source pairs, while source scoping leaves them separate. One pair's two synthetic images have the **same complete byte contents and SHA**, yet separate *scorer-tracked* source identities. Two missing/untrusted-label pairs have no authorized source join even if numeric offsets match. This experiment does **not** authenticate an external label merely because the label is present; production must use an A-controlled source meter and receipt chain.

The 32-byte negative originally failed a **test assumption**: the existing geometry function returns `insufficient_evidence` when it has only an incomplete MBR, not `reject` or `unknown`. The test was corrected to assert this **actual expected, safer state**, while keeping source bytes, labels, limits and the implementation unchanged. Initial CI had 105/106 pass, final corrected code CI 106/106 pass. Timings, memory peaks and actual real-file recovery remain **unmeasured**.

## R4 — handoff and limits for Team A

Recommend **`research_only` / tests-and-docs-only**, no change to the current opt-in D module. A should review/test physical source-ID issuance and receipt correlation in its R7 candidate-specific validation pipeline. Only an A-issued, independently verified meter identity can justify a *source* join; D's local event IDs or offset equality are not identities. Even a correct source join does **not** validate FAT-chain semantics, file ownership, original file byte equality or repair eligibility. Partial reads, unobserved FAT entries and global budget cutoffs stay unverified.

No real microSD/sole ~31GB master IMG access, read, hash, copy, write, upload, scan, repair, extraction or persistent raw logging. All tests use disposable artificial memory data. Real-media gate **NOT APPROVED**; only Team A may review/merge.
