# Parallel team protocol

## Ownership
- A: specification, integrations, QA gates; `core/`, `runner/`, `docs/`.
- B: `modules/directory/` — FAT-independent directory / LFN scanning.
- C: `modules/carving/` — bounded file carving, G-code and 3MF checks.
- D: `modules/fat-analysis/` — FAT geometry and non-destructive repair candidate research.

Branches: `integration/*`, `feature/b-directory-*`, `feature/c-carving-*`, `research/d-fat-*`.

## Mandatory safety
1. No write handle to any original disk or master IMG.
2. No automatic repair on the real data. Test hypothetical fixes only on synthetic/disposable copies.
3. Extraction only to an explicitly designated different directory, no overwrite or path traversal.
4. Sanitize all issue text and logs; GitHub is NOT a destination for original data.
5. Limit file sizes, iterations, recursive depth and directory walks. Handle malformed filesystem entries gracefully.
6. Keep functions composable: read-only input stream + structured result; no hardcoded personal Windows paths.
7. Distinguish actual test results from planned tests. A can reject an unsafe PR.

## A integration checklist
- [ ] Scoped module change
- [ ] Privacy check; no real data
- [ ] PowerShell syntax / static review
- [ ] Synthetic normal and corrupt case tests
- [ ] Source IMG readonly; output path/overwrite checks
- [ ] Review and PR handoff documented