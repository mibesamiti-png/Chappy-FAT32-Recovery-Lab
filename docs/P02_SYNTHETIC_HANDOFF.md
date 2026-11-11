# Team A handoff for the next synthetic benchmark round

Refs #1 and Draft PR #68. The current B #60, C #61 and D #62 assignments are active. Activate each follow-up only after Team A records its R4 decision for the active submission and closes out that round. Pin a reviewed, integrated fixture commit and record it in each follow-up issue.

## Shared fixture contract

Use Windows PowerShell 5.1 and seed `202611` with `New-ChappyA3DDamagedFixture` in `tests/helpers/New-Chappy3DDamagedFixture.ps1`. Record fixture versions, case IDs, baseline and candidate commits, flags and observed resource use. Use the same image and explicit limits for each baseline/candidate pair. Pass only a readable, seekable, non-writable memory stream to the analysis under test. The A scorer holds the clean SHA-256, fixture extents and mutation manifest separately.

| Case | Synthetic observation |
| --- | --- |
| M00 | Healthy contiguous control |
| M01 | Valid fragmented 3MF, both FATs link cluster 4 to 7, original files match |
| M02 | FAT1 3MF link cleared, FAT2 and all payloads intact |
| M04 | 3MF directory size set to zero, all payloads intact at known clean extents |
| P01 | 3MF ZIP end record erased, ZIP parser rejects the package |
| P02 / P03 | 3MF compressed model or binary STL vertex changed, affected full-file SHA differs |
| X02 | EOF at byte 59520 inside 3MF payload, truncation range recorded |

The A test reader rejects a 512-byte payload cap for the generated 3MF. At 2048 bytes it reads the full clean and fragmented 3MF and rejects the truncated extent. These caps describe the A fixture check. Each team records its own source-read and candidate limits and actual counts.

## Follow-up instructions for the existing teams

| Team and current submission | First bounded follow-up | Acceptance evidence |
| --- | --- | --- |
| B #60 / PR #64 | Compare existing directory evidence against one candidate on M00, M01, M04 and X02. | Preserve the zero-size and missing-coverage uncertainty. Report any false high-confidence hierarchy or path claim and how many known directory observations are retained. Additional LFN cases require a separately generated fixture. |
| C #61 / PR #63 | Use M00 and P01/P02/P03 to measure package or STL evidence against original SHA, with M01 as a later bounded fragmentation control. | Report structural validity separately from exact file identity. Include read/validation counts and false original claims. State every search hint and cap. |
| D #62 / PR #65 | Use M00, M01, M02 and X02 to compare bounded FAT evidence and behavior on incomplete reads. | Distinguish healthy fragmentation from FAT disagreement, report actual and unique read bytes, and preserve uncertainty when samples are incomplete. Cycle and cross-link truth require separate generated cases. |

Start with an R0 source and license note, freeze the R1 baseline, and submit one bounded R2 candidate with R3 measurements in a Draft PR for A's R4 review. Use the current privacy and Windows checks and record input SHA before and after. Public work uses generated data only.
