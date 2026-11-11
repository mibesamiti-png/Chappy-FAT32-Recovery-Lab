# Chappy FAT32 Recovery Lab

FAT32破損解析・ファイル救出を研究する **Windows PowerShell 5.1** プロジェクト。**実験段階であり、復旧成功・安全性を保証しません。**

## 最優先の安全ルール

- 元のmicroSDと唯一のマスターIMGには**絶対に修復書き込みをしない**。
- 実IMG・復旧したファイル・実際のファイル名/内容・未匿名化ログはGitHubへアップロードしない。
- GitHub上のテストは**人工的に生成した小容量データだけ**で行う。
- 診断は読み取り専用。ファイル抽出は明示された別保存先にだけ行い、既存ファイルは上書きしない。
- 既存のv0.5/QuickProbe v0.5.1は**未検証の試作**。実データへの自動修復を認めない。
- GitHubで取得した未知のスクリプトを31GBの実IMGに直接実行しない。

## 並列開発体制

| チーム | 担当 | 領域 |
| --- | --- | --- |
| A | 司令塔・統合・品質ゲート・ローカル検証ランナー | `core/`, `runner/`, `docs/` |
| B | FAT非依存ディレクトリ・長いファイル名復元 | `modules/directory/` |
| C | G-code / 3MF / ZIPカービングと検証 | `modules/carving/` |
| D | FAT異常の独立診断・修復候補研究 | `modules/fat-analysis/` |

必ず `AGENTS.md` と `docs/TEAM_PROTOCOL.md`、`docs/STATE.md` を読む。PRは各チームの独立ブランチで作成し、Aが安全性を確認するまで統合しない。

## 現状

実カードはWindowsでRAWと認識され、FAT32ブートレコードの基本構造は読めている。FAT先頭領域に異常な繰り返しパターンがあり、従来のチェーン追跡は失敗した。原因がメディア障害かファイルシステム破損かを引き続き調査する。**救出できたデータ数はまだ確認していない。**

## プライバシー

画像・G-code・3MFを含めた実ユーザーデータは **PC内のみ** に保管する。31GBのIMGそのものはGitHubには置かない。人工テスト用データだけをコミットする。

See: [State](docs/STATE.md) · [Team protocol](docs/TEAM_PROTOCOL.md) · [Test policy](docs/TEST_POLICY.md).