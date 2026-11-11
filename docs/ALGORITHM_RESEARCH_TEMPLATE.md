# Algorithm Research Card — copy for each Team B/C/D P1

**Use this template as an Issue comment or a documentation-only Draft PR before implementing a new method.** Fill unknown fields with `unknown` and state why; never fabricate results, sources, licensing, test execution or recovery rates.

## 1. Tracking

- Team / Issue / assigned branch:
- Baseline main commit (full SHA):
- Research card revision / date:
- Exact input mode: generated memory/temporary synthetic fixture; original image access is forbidden.
- Research gate: R0 survey / R1 baseline / R2 experiment / R3 comparison / R4 A review.

## 2. Prior approaches (target 3 when credible)

| ID | Primary paper/spec/official repository URL | Author / year / version | Principle and input assumptions | Failure modes | Exact code license / publication rights | License status | Integration difficulty |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ALG-1 | | | | | | clear / review_required / no_reuse | low / medium / high |
| ALG-2 | | | | | | clear / review_required / no_reuse | low / medium / high |
| ALG-3 | | | | | | clear / review_required / no_reuse | low / medium / high |

Source text must be paraphrased, not pasted wholesale. **Code reuse is a separate permission/review question:** no copying GPL/mixed-license files into this repository merely because the underlying algorithm was published. Keep exact upstream source URL and any notice/attribution obligations.

## 3. Selection / prior hypothesis

- Selected approach and justification; why not alternatives:
- Specific P1 already authorized in current GitHub Issue:
- Expected measurable gain (positive and negative controls):
- Worst-case time/read/memory and artificial sample sizes:
- Known failure modes, e.g. broken FAT, false positives, truncated ZIP, unknown LFN:
- Fallback state if unresolved: partial / unknown / research_only.

## 4. Reproducible baseline and variant

- Original main SHA and legacy algorithm settings:
- Candidate branch/HEAD and experimental flag (default OFF):
- Fixture generator, seed and fixture SHA (artificial bytes only):
- Exactly equal corpus, conditions, PowerShell/.NET version, limits and scoring?
- Enumerated **known original artificial bytes** and independent ground truth:
- Resource budgets (max source bytes / probes / candidates / decompression / time):

## 5. Actual A/B findings

| Metric | Baseline measured | Proposed measured | Sample size/condition |
| --- | ---: | ---: | --- |
| True positives TP | | | |
| False positives FP | | | |
| False negatives FN | | | |
| True negatives TN | | | |
| Precision TP/(TP+FP) | | | |
| Recall TP/(TP+FN) | | | |
| Original artificial byte-identical candidates | | | |
| Incorrectly claimed verified/complete originals | | | Must be 0 |
| Partial/unknown coverage | | | |
| Actual total bytes read | | | |
| Maximum candidates / pair attempts | | | |
| Elapsed time | | | |
| Memory peak if measured reliably | | | |
| Source SHA unchanged? | | | Must be yes |
| Windows PowerShell 5.1 CI result/link | | | final HEAD |
| Privacy CI result/link | | | final HEAD |

State `not measured` or `undefined` rather than assigning 0 to unmeasured values or zero-denominator ratios. Include any regressions and mismatch explanations. Same-corpus comparisons cannot establish success on real storage.

## 6. Security and legal gates

- [ ] Only generated/artificial fixtures; no real IMG, recovered content, actual paths/names or unredacted logs
- [ ] All input streams are non-writable; no repair, output path, full-media read, or public data transfer
- [ ] Hard source byte / probe / candidate / memory / CPU / iteration bounds, including negative tests
- [ ] Fail closed on unknown format/geometry/partial evidence; no false original-integrity proof
- [ ] Third-party source provenance and applicable licenses reviewed; unapproved code reuse blocked
- [ ] Final exact branch HEAD Windows synthetic + privacy CI actually passed
- [ ] A reviewed baseline fairness, negative cases, implementation diff and impact on old behavior

## 7. Adoption decision (Team A only)

- Decision: adopt_experimental / research_only / revise / reject:
- Rationale, which artificial scenarios improved, any regressions and remaining blind spots:
- Merge PR and squash commit, test links:
- Release control: default-OFF experimental / no production integration:
- Next bounded independent task, if separately dispatched:

**Never infer real-file recovery percentage or authorize local trial from this research card.**
