# Synthetic-only tests and private local validation

GitHub Actions and contributor tests use ONLY artificial fixtures. Never commit the physical IMG, extracted real files, real filenames, or unredacted reports.

Required synthetic cases: valid boot records; invalid BPB; FAT reserved entries; in-range/out-of-range root links; cycles; matching/diverging FAT; corrupt long-file-name checksum; nested directories; path traversal; truncated images; deceptive file signatures; invalid ZIP EOCD / central directory.

Before any real-image *diagnosis*, run local Windows synthetic tests, review the script for unintended writes, and confirm the IMG opens with `[IO.FileAccess]::Read`. Keep extraction and repair disabled by default. GitHub does not need real IMG access.

Never interpret file-size equality or SHA-256 consistency of extracted bytes as proof that original content is intact.