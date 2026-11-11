# Windows setup

The repository is created as PRIVATE at:
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