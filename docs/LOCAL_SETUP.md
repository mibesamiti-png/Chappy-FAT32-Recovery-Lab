# Windows setup

The repository is PUBLIC. The data is local-only. Repository URL:
https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab

Use a working copy **outside** `C:\SD_Backups`. Do not copy the 31GB master IMG or recovery output into the repo directory.

```powershell
git clone https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab.git
cd Chappy-FAT32-Recovery-Lab
git status --short
```

For new changes, run a safety review before committing and pushing:

```powershell
powershell -NoProfile -File .\tools\Check-RepoSafety.ps1 -CheckTracked
git status --short
git diff --cached --name-only
```

No `git add -f` and no `git push --force`. Never place the real IMG under Git control.

For local-only diagnosis use a separately reviewed script outside the repo. Do NOT publish any generated JSON/report without inspecting for identifying data.

## Import existing v0.5 baseline (optional but recommended before integrated development)

The existing v0.5 PS1 is still local. This repository intentionally starts with the tiny QuickProbe reference rather than a 31GB image.

Copy the two known scripts from your **extracted** local v0.5 folder with a SHA-256 guard:

~~~powershell
# In the local Chappy-FAT32-Recovery-Lab clone:
.\tools\Import-Legacy-v0.5.ps1
git status --short
~~~

The importer checks the exact original v0.5 / test-script hashes. It only copies two specified .ps1 files into the Git working directory and never stages, commits, pushes or reads the IMG.

After reviewing the source, explicitly stage and commit **only** those two files:

~~~powershell
git add -- legacy/Chappy_FAT32_Recovery_Lab_v0.5.ps1 tests/legacy/Test_Chappy_FAT32_v0.5.ps1
git diff --cached --stat
git commit -m "chore: import experimental v0.5 baseline"
git push origin main
~~~

If the existing scripts have changed, the importer intentionally refuses them. Do not disable the checksums until you have reviewed and reconciled those changes.

Do not use \`git add -A\` or \`git add .\` near the backup directory. Never put real IMG, real extracted files or raw reports into Git.