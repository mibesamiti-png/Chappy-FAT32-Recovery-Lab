# Team A R8-P2 — disposable synthetic junction and concurrent CreateNew guard (2026-11-14)

**Not original R8 acceptance.** R8 is only partially implemented. A previously accepted R0–R7 bounded synthetic stage evidence totaling **84%**; 16% R8–R10 uncredited. This PR must NOT change any formal stage acceptance or allow use of the actual microSD or only ~31GB original master IMG. No original media may be read, hashed, scanned, copied, extracted, repaired, written or uploaded.

## P2 implementation

The default-OFF R8 prototype `core/Chappy.SyntheticSeparateExportV1.psm1` still only accepts explicitly synthetic in-memory `byte[]` source (at most 128 KiB), two validated ordered nonoverlapping 3MF spans, and one unique disposable directory **directly beneath OS temp**, not arbitrary Windows output paths. It uses `FileMode.CreateNew` with a deterministic generated basename, SHA-256 after actual disk readback and independent artificial source-array SHA unchanged.

P2 hardening adds **`Test-ChappyR8NoReparseAncestors`**, which checks `FileAttributes.ReparsePoint` on every parent of the destination, not just the leaf root. The candidate export now checks the entire path chain before `CreateNew`, again after writing before output verification and before attempting cleanup of an **owned** output on failure. UNC/device/ADS/traversal/untrusted root, source/output declared overlap and arbitrary file name remain rejected. The parent chain check is a **best-effort preflight**, not an OS handle-bound guarantee against a privileged process changing a path between check and use. Failed cleanup never deletes an output if its root chain now has a reparse point; that can leave a partial *synthetic* file, and must remain documented.

## P2 53rd isolated Windows PowerShell 5.1 test

`tests/Test-A3DR8ConcurrentJunctionSafety.ps1` uses generated compact synthetic 3MF bytes only, all outputs under a newly created unique disposable temp directory; no user source paths. It launches **five separate Windows PowerShell child processes**, each importing the real R8 module with the same source and candidate metadata. A ready-file barrier confirms all five are loaded before a common release signal, then they compete for one `CreateNew` destination. Exactly **one** may succeed, exactly **four** must fail without overwrite; the winning output SHA must equal the private generated oracle and source SHA remain unchanged. The helper/ready/barrier files belong to the disposable directory and are not counted as candidate outputs.

The test also attempts a real Windows NTFS **junction to another newly created disposable synthetic target directory**, naming the link as if it were an authorized output root. If the OS permits junction creation, the exporter MUST fail with no candidate output, leaving the target's sentinel unchanged. If junction creation is denied by runner policy, the test explicitly prints **NOT TESTED**, not PASS for junction coverage; this condition remains unverified. The test deletes the link entry non-recursively and then deletes only its own disposable target. No real source or external directory is touched.

## Remaining formal R8 original acceptance gaps

This slice does **not** prove race-free Windows reparse/junction identity, source authenticity, or a general-purpose safe exporter. The artificial source fixture tag and optional source root are caller-declared and cannot authenticate a real IMG. There is not yet a versioned link from the R7 source-bound candidate to R8's byte-array input; full R3 standard SPC1/SPC2 candidate and multi-hypothesis ambiguity must be tested with no original-winner selection. Disk full/permissions, readback mutation and arbitrary write interruption also require independent negative evidence.

Original R8 milestone text requires a strict explicit separate local root, true source/output disjointness, Windows traversal/UNC/device/ADS/reparse safety, concurrent collisions, create-new, cleanup only owned outputs, export SHA/test-only independent oracle and source SHA before/after. It is **not** satisfied by this P2 PR alone, and the original +9 points remain uncredited. R9 quality and R10 release are likewise separate.

**Acceptance conditions:** exact final PR-head Windows PS5.1 + central privacy **53/53**, then A independent diff review, merge and post-main **53/53**; report actual result including junction created or skipped. If the test fails on any case, do not merge or advance weight. A should write the next bounded R8-P3 plan after reviewing the CI and keeping all real media forbidden.
