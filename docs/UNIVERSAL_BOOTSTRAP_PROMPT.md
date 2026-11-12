# Universal Copy/Paste Prompt — FOUR-CHAT GATE-CLOSURE MODE

Paste the **same Japanese block** below into the existing A, B, C and D ChatGPT conversations. **Do not use a single Work session to replace the four chats.** Each existing conversation keeps its previously assigned role. A fresh unassigned chat still requires one explicit assignment.

```text
# Chappy FAT32 Recovery Lab — ABCD既存4チャット・完成優先モード

GitHub正本：
https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab

このチャットに以前から割り当てられたA/B/C/D担当を絶対に維持してください。Work一括運用ではなく、各チャットが独立したチームです。

毎回、最新main HEAD、AGENTS.md、以下の文書、自チームのIssue・現在のブランチ・開いているPR・最終HEADのCIを取得してから作業してください。
- docs/UNIVERSAL_WORK_INSTRUCTION.md
- docs/TEAM_DISPATCH.md（最上部の最新担当表を優先）
- docs/ABCD_GATE_CLOSURE_PLAYBOOK.md（新しい4チャット完成優先設計）
- docs/ABCD_GATE_LEDGER.md（R4〜R7の未達成合格条件）
- docs/ABCD_SYNTHETIC_ROADMAP.md（正式な進捗採点）
- docs/ALGORITHM_RESEARCH_PROTOCOL.md
- docs/LOCAL_READONLY_APPROVAL_GATE.md

「次の研究テーマを増やす」より「既存の正式合格条件で未完了の1行を達成する」を優先してください。
AはIssue #1でゲート監査・R7統合・PR審査・main統合・進捗更新。BはIssue #71でR4ディレクトリ、CはIssue #72でR5フォーマットと分断候補、DはIssue #73でR6 FAT診断を担当します。
B/C/Dは自分の範囲だけを小さく実装・人工テストし、新しい専用ブランチとDraft PRを作成。自己マージ禁止。Aは最終PR HEADのWindows PowerShell 5.1 CIとプライバシーを確認してからマージし、main CIを再検証します。B/C/DのIssueの旧P1割り当てと新設計が衝突した場合は、最新のAによる新設計の割り当てを優先してください。

すべてのPRで狙うゲートID、追加機能・実際の未達成条件、実測した人工データの結果とコスト、残る不足を記録。研究限定PRは機能完成扱いしないでください。

現時点の公式進捗39%は全合格工程R0〜R3のみ。検証していないゲートの進捗を水増ししないでください。各チームの内部目安と実ファイル復元率は別物です。

実microSDおよび唯一の約31GBマスターIMGは読み込み・ハッシュ・スキャン・コピー・書き込み・修復・抽出・アップロードすべて未承認。公開GitHub/CIは人工データ限定。R7完全合格までR8の出力はブロック。

作業を実際に進め、最後に担当、狙ったゲートID、変更したファイル、ブランチ/PR、最終HEADのCI、ゲート台帳上の状態、次の未完了ゲート、公式進捗を報告してください。GitHub操作に失敗したら成功したふりをせずに報告してください。
```

## Operating notes

- Paste exactly the same block into all **already assigned** team chats. Chat-specific identity is maintained by conversation context plus current GitHub Issue and current live roster; the text is deliberately role-neutral.
- Follow current GitHub pointers and current A Issue assignment rather than old dates and branches in archived dispatch sections.
- A may review/merge multiple independent PRs in sequence; no B/C/D chat may merge itself or edit another team's files.
- The first goal of this new mode is to **audit** the ledger and close real R4/R5/R6/R7 gaps. Do not reclassify legacy test-only research as complete automatically.
