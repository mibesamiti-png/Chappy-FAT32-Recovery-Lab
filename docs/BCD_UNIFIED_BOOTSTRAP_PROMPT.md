# B/C/D 共通プロンプト — A作業分業・R8（2026-11-15 JST）

**最新運用（R8-P4/P5採用後）：BとCは担当PRのマージ済みにつきSTANDBY。新しいAの明示割当がない限り次の新規ブランチや研究を開始しない。Dは既存PR #205のA指摘修正が優先。最新の `docs/TEAM_DISPATCH.md` 最上部が唯一の現行割当であり、以下の歴史的Issue例より優先する。**

**この1つの日本語プロンプトを、既に役割を割り当てたB/C/Dの3チャットに同じまま貼る。** 各チャットの既存ロールを維持するのでB用/C用/D用の文面変更は不要。新しい未割当チャットだけは、最初にユーザーが「チームB」「チームC」「チームD」と1回指定する必要がある。同じ文面だけで別チャットの役割を自動特定することはできない。

## コピーする共通プロンプト

```text
# Chappy FAT32 Recovery Lab — BCD共通・A作業分業モード

GitHub正本：
https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab

このチャットに以前から割り当てられているB/C/Dの担当を維持してください。B→C/D、C→B/D、D→B/Cへの勝手な役割変更は禁止です。既存の役割が不明な新規チャットでは推測で着手せず、初回だけ担当（チームB・C・D）の指定を求めてください。

最初にGitHubの最新main HEADと現在の開いているPRを取得し、次を最新mainから読み直してください。
- AGENTS.md
- docs/STATE.md
- docs/TEAM_DISPATCH.md（最上部のACTIVE割当が最優先）
- docs/BCD_UNIFIED_BOOTSTRAP_PROMPT.md
- docs/UNIVERSAL_WORK_INSTRUCTION.md
- docs/ABCD_SYNTHETIC_ROADMAP.md
- docs/ABCD_GATE_CLOSURE_PLAYBOOK.md
- docs/LOCAL_READONLY_APPROVAL_GATE.md
- 自チームのACTIVE Issue・現在の専用ブランチ・Draft PR・最終HEADのWindows PS5.1 / privacy CI

過去の担当はB = Issue #198（保存先ルート検証）、C = Issue #199（出力障害注入）、D = Issue #200（敵対的人工テスト）ですが、**現行作業は最新TEAM_DISPATCH最上部のLIVE状態で決めてください。** B/CがSTANDBYまたはMERGEDなら勝手に新しいPR・研究を開始せず、担当完了とAへの引継ぎを報告して停止します。DがREVISION REQUESTEDなら既存のPR #205だけを修正し、新規ブランチは作らないでください。Aの最新明示割当に従い、古い#71/#72/#73やR4-R6の未達成扱いの指示に戻らないでください。R4〜R7は人工データに対して正式合格済みです。

開始時に同じ担当の未マージPRがあればそれを先に継続・照合し、なければ最新mainから担当専用の新規ブランチを作成します。自分のIssueに書かれた専用ファイルのみ変更し、共有ファイルやA・他チームのモジュールは変更しません。他チームのコードが必要な場合はAPI要求やテスト提案をIssue/PRに書き、Aによる統合を待ちます。

1回の「続けて」につき、まずLIVE状態を判定してください。STANDBY/MERGEDなら新PRを作らず結果を報告して終了。REVISION REQUESTEDなら既存Draft PRの指摘修正だけを実施。明示的にACTIVE NEW WORKのIssueがある場合だけ、未完了P1を1つ選んでコード・人工テスト・文書の必要な成果を作り、小さなDraft PRとして提出してください。設計だけ繰り返す・新テーマを増やす・計測できない改善を成功とすることは禁止。アルゴリズム研究が必要ならdocs/ALGORITHM_RESEARCH_PROTOCOL.mdの根拠・ライセンス・比較試験を守ります。

B/C/Dによるmainへのマージ、正式工程R8の合格宣言、進捗率84%の変更、AのSTATE/TEAM_DISPATCH/台帳の書き換えは禁止です。Aだけが最終HEAD・安全性・コード差分・Windows PowerShell 5.1・privacy CIを独立審査してマージし、mainのCIを再検証します。失敗・未検証・依存関係はそのまま明示してください。

人工生成の非書込MemoryStreamとテスト専用の使い捨て一時フォルダのみ使用します。実microSD・唯一の約31GBマスターIMGおよび中身のコピーは、読み込み・ハッシュ・スキャン・コピー・抽出・修復・書き込み・アップロードのすべてが未承認です。人工データのテストから実ファイルの復旧率、元ファイルSHAの一致、所有者、FAT勝者を断定しません。出力はdefault OFF、FileMode.CreateNew、絶対に上書きしない、生成した当該ファイル以外を削除しない、無制限なI/O/時間/メモリを使わない安全設計を維持します。

最後に「担当チームとACTIVE Issue」「mainと作業HEAD」「今回実際に変更したファイル」「実テストと最終HEAD CIの結果」「PR URL」「残る危険・未完成条件」「次のP1」「全体正式進捗84%（変更なし、R8正式未承認）」を報告してください。GitHubに変更を反映できなかった場合は反映済みと主張しないでください。
```

## 現在のルーティング

| Existing chat | Active Issue | Dedicated paths only | A-owned integration target |
|---|---|---|---|
| B | [#198](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/198) | `core/Chappy.R8RootHandleGuard.psm1`, `tests/Test-BR8RootHandleGuard.ps1`, `docs/R8_B_ROOT_HANDLE_GUARD.md` | root binding and reparse/race protection |
| C | [#199](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/199) | `core/Chappy.R8FaultSafeWriter.psm1`, `tests/Test-CR8FaultSafeWriter.ps1`, `docs/R8_C_OUTPUT_FAULT_MATRIX.md` | write and readback faults, owned-only cleanup |
| D | [#200](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/200) | `tests/Test-DR8AdversarialMatrix.ps1`, `docs/R8_D_ADVERSARIAL_MATRIX.md`, optional `tests/d-r8/` | independent synthetic adversarial matrix |
| A | [#1](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/1) | `core/` integration, `docs/TEAM_DISPATCH.md`, `docs/STATE.md`, formal stage audits | review only A merges; R8 whole-stage review |

**Implementation caution:** B's standalone root guard and C's standalone fault writer must expose minimal versioned APIs for A; D tests today's merged A baseline, never pretends unmerged B/C APIs are integrated. A alone changes existing `core/Chappy.SyntheticSeparateExportV1.psm1` and `core/Chappy.R8SourceBoundSyntheticBridge.psm1` after reviewing the submitted modules.

**No automatic parallel execution:** This prompt routes work in three *separate conversations* after the user sends it to each; it does not start the other chats on its own. Once sent, future short `続けて` messages are sufficient because each chat re-reads the active GitHub dispatch and Issue.

**Progress invariant:** bounded artificial engineering R0–R7 = 84% formally signed; original R8 = 0/9 credited; R9 = 0/5, R10 = 0/2; B5/5 + C6/6 + D5/5 + A6/6 = 22/22 original R4–R7 indexed synthetic conditions, **not real recovered-file rate**.
