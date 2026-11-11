# Source Starting Points — B/C/D independent algorithm research

Starter bibliography verified by Team A on 2026-11-11. These are **leads, not permission to copy source code**, and teams should look for stronger/more directly applicable primary material. Check current release and **file-level license** before any reuse.

## B — FAT-independent directory metadata and hierarchy evidence

1. **The Sleuth Kit (TSK)**: https://github.com/sleuthkit/sleuthkit — filesystem forensic analysis toolkit with FAT/exFAT support. Compare its metadata interpretation concepts, invalid/deleted directory handling and ambiguity models. **License note:** TSK is explicitly mixed-license at component level (e.g., IBM/CPL, GPL, MIT and BSD materials); never assume a repo-wide license permits copying selected code.
2. TSK official project overview: https://github.com/sleuthkit/sleuthkit/wiki/The-Sleuth-Kit — identify which techniques are for metadata evidence versus proof of recovered original paths.
3. Independent research searches: FAT32 directory entry / 8.3 and LFN ordinal + checksum validity; graph constraint reconciliation under conflicting parent hints; data-vs-directory false signatures. B must find and cite the exact primary specification or paper it selects. Beware private filenames in output.

**Candidate hypotheses:** confidence propagation as a monotonic lower bound; conflict graphs and cycles; explicit unknown under missing scan coverage. Keep orphan candidates rather than erasing weak evidence.

## C — bounded two-fragment carving and format-aware validators

1. **Garfinkel, 'Carving contiguous and fragmented files with fast object validation' (2007)**: https://www.sciencedirect.com/science/article/pii/S1742287607000369 — paper discussing fragment validation and Bifragment Gap Carving. Study finite-gap candidate ordering, validation cost and false positives; cite the original paper. Publication access does NOT license copying arbitrary implementation code.
2. **PhotoRec official Data Carving guide**: https://www.cgsecurity.org/wiki/PhotoRec_Data_Carving — signature + file-type checks, limitations for fragmented/text files. Use as an algorithmic comparison, not a claim that generic file carving reconstructs G-code/3MF fragments.
3. **3MF Consortium official spec**: https://3mf.io/spec/ and https://github.com/3MFConsortium/spec_core — formal packaging and 3MF part/relationship requirements; the archive container is ZIP-based. Observe specification version; avoid assuming all vendor-specific 3MF extensions are validated.
4. **TestDisk/PhotoRec code repository**, background only: https://github.com/cgsecurity/testdisk — **GPL** (repository GPL-2.0); do not copy code into this project without explicit license compatibility and notice review.

**Candidate hypotheses:** bounded two-fragment gap/ordering enumeration, fast negative syntax/ZIP/CRC filters, independent known-original byte comparison. CRC and structural checks alone cannot certify original file bytes.

## D — VBR / FAT mirror evidence, suspicious damage pattern statistics

1. **TestDisk official project feature list**: https://www.cgsecurity.org/wiki/TestDisk — FAT32 backup boot and FAT checks are relevant prior work. The actual repair commands are **OUT OF SCOPE**; this lab only evaluates unverified evidence on disposable artificial bytes.
2. **TestDisk official filesystem repair discussion**: https://github.com/cgsecurity/testdisk_documentation/blob/master/repairing_filesystem.rst — primary-vs-backup boot behavior; read for uncertainty and conservative diagnostics, never execute its write/repair instructions on user's media.
3. **The Sleuth Kit official repository**: https://github.com/sleuthkit/sleuthkit — independently analyze FAT layout and volume metadata evidence; component licenses vary.

**Candidate hypotheses:** compare primary and backup VBR-derived tiny FAT windows; conservative anomaly evidence aggregation and mirror-disagreement detection; both copies matching is **not** authenticity or content-integrity proof. Never select a write target.

## Questions every team must answer before deciding

- Does the source actually describe this algorithm rather than a similarly named technique?
- Can it run using a fixed, tiny, non-writable Stream window in Windows PowerShell 5.1, without external executables or elevated privileges?
- Is the approach materially different from what our current main already does? What **reproducible failing artificial case** justifies it?
- Is source code from a GPL/mixed-license repository being copied? If so, stop and require legal/license decision; prefer a clean independent experimental implementation based on properly cited ideas/specifications.
- How will true positives, false positives, false claims of original byte identity, time and read quota change versus the same baseline?

**Research does not change real-image approval.** Actual 31GB master IMG remains inaccessible to public development/CI and local real-image trial is NOT APPROVED.
