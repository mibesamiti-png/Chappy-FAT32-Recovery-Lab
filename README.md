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

## 同一プロンプトによるABCD並列開発

既存のチームA/B/C/Dチャットに、**[共通起動プロンプト](docs/UNIVERSAL_BOOTSTRAP_PROMPT.md)** をそのまま貼り付ける。全チャットで同一文面を使用できる。

指示の正本は [共通運用ルール](docs/UNIVERSAL_WORK_INSTRUCTION.md) と [チーム担当表](docs/TEAM_DISPATCH.md)。担当は各チャットの既存の役割を維持する。新規チャットで担当が未設定の場合は初回だけ担当指定が必要。

## 既存アルゴリズム調査・比較開発（2026-11-11から）

次のB/C/Dラウンドは、[既存手法の調査・A/B比較ルール](docs/ALGORITHM_RESEARCH_PROTOCOL.md)に従い、公式仕様・論文・既存実装の**出典とライセンス**を確認してから、人工データで旧方式と新方式を比較する。研究記録は[共通テンプレート](docs/ALGORITHM_RESEARCH_TEMPLATE.md)を使い、[参考資料集](docs/ALGORITHM_RESEARCH_STARTER_REFERENCES.md)を調査の出発点にする。

従来のB #45、C #46、D #47の担当Issue・ブランチはそのまま。各チームの既存チャットでは、上記の**同じ共通起動プロンプトを引き続き使える**。Aだけが比較結果を審査して採否・統合を判断し、人工ベンチマークの結果を実データの復旧率とは呼ばない。
