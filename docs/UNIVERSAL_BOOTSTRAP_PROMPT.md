# Universal Copy/Paste Prompt

This is the **same** text for existing A/B/C/D ChatGPT conversations. Paste it into each chat without editing. Each chat retains its previously assigned team. No separate B/C/D prompts need to be maintained.

```text
Chappy FAT32 Recovery Lab の開発を続けてください。

GitHub（正本）:
https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab

まず毎回、main の最新版と次の共通指示書を読み直してください。
https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/blob/main/docs/UNIVERSAL_WORK_INSTRUCTION.md

このチャットに既に割り当てられているチーム（A/B/C/D）を維持し、GitHub の TEAM_DISPATCH・自チームIssue・作業ブランチ・PR・CI・最新HEADを確認して、担当の未完了タスクを安全に1つ進めてください。担当が未設定なら勝手に重複担当を選ばないでください。

実microSDと31GBのマスターIMGへの書き込みは禁止。実データ・復旧ファイル・未匿名化ログは公開GitHubに送らず、人工テストデータのみ使用。既存の変更と競合しないように、小さなDraft PRと検証結果を残してください。

最後に担当チーム、実装内容、コミット/PR、テスト結果、全体ロードマップの進捗、次の仕事を報告してください。GitHubの参照・更新ができなかった場合は、その事実を明記してください。
```

## How it works

- User sends the exact same text to each existing team chat.
- The team loads `docs/UNIVERSAL_WORK_INSTRUCTION.md`, `docs/TEAM_DISPATCH.md`, and its latest Issue/branch/PR/CI.
- Each team keeps its already established identity. A new chat without a team assignment cannot safely auto-choose a role: assign it once before using this universal prompt.
- Future changes go in GitHub documents. Do not extend the pasted text unless the repository URL changes.
- The link does not grant the chat GitHub write access. When a chat cannot access GitHub, it must say so; when it cannot write, it should present a patch rather than claim it committed anything.