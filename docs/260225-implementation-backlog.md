# etzhayyim-project-ohanashi Implementation Backlog

## 進め方

- 1 Issue = 1 目的に限定して小さく実装
- `default` namespace への作成禁止
- App system は `kotodama-system`、アプリは `kotodama-runtime`
- deploy は `mage deploy` を利用

## Epic A: Voice Core

### OHN-001 電話着信セッション開始 API 実装
- Goal: 電話ゲートウェイからセッション開始イベントを受ける
- Output: `POST /api/voice/session/start`
- Acceptance:
1. call-id 単位で idempotent
2. 監査ログに caller-id hash を保存
3. 失敗時は再試行可能なエラーコード

### OHN-002 対話ターン処理パイプライン
- Goal: 音声入力 -> STT -> LLM -> TTS の1ターンを成立
- Output: `POST /api/voice/session/{id}/turn`
- Acceptance:
1. p95 2.0 秒以下
2. 通信障害時に前ターンへロールバックしない
3. turn-level trace id を保存

### OHN-003 会話終了と要約生成
- Goal: 通話終了時に要約とアクション提案を生成
- Output: `POST /api/voice/session/{id}/end`
- Acceptance:
1. summary, risk-level, follow-up-action を保存
2. 失敗時は非同期リトライキューへ移送

## Epic B: Safety / Escalation

### OHN-010 リスク分類ルールエンジン
- Goal: 緊急・高リスク会話を判定
- Acceptance:
1. `none|low|medium|high|critical` を返却
2. ルール判定理由を監査ログに保存

### OHN-011 緊急エスカレーション
- Goal: critical 判定時に人間窓口へ即時移送
- Acceptance:
1. 転送失敗時は callback queue 自動登録
2. 家族通知を高優先で送信

## Epic C: Family Portal (`ohanashi.etzhayyim.com`)

### OHN-020 家族アカウントと同意管理
- Goal: 通話要約共有の同意フローを実装
- Acceptance:
1. 本人同意フラグのない共有は禁止
2. 同意撤回を即時反映

### OHN-021 通知設定 UI
- Goal: 通知先（メール/SMS）と通知レベル設定
- Acceptance:
1. 重要通知のみフィルタ可能
2. 44px 以上のタップ領域（iPad優先）

### OHN-022 履歴閲覧 UI
- Goal: 相談履歴・要約・ステータス閲覧
- Acceptance:
1. `md/lg/xl` の4段階レスポンシブ
2. iPad portrait で sidebar overlay

## Epic D: Data / Governance

### OHN-030 PII マスキング
- Goal: 保存前に個人情報をマスク
- Acceptance:
1. 電話番号、生年月日、住所の基本マスク
2. 原文保存は監査目的の最小範囲のみ

### OHN-031 保存期間ポリシー
- Goal: 会話データの TTL 管理
- Acceptance:
1. セッション本文は 90 日
2. 監査ログは 365 日

## Epic E: Release / Operations

### OHN-040 App deploy manifest 作成
- Goal: `ohanashi-voice-orchestrator` の deploy manifest を定義
- Acceptance:
1. namespace は `kotodama-runtime`
2. image は `ghcr.io/etzhayyim/*`

### OHN-041 HTTPRoute 作成
- Goal: `ohanashi.etzhayyim.com` で `api/mcp` を公開
- Acceptance:
1. path-based legacy endpoint を使わない
2. health endpoint `/_app/version.json` で疎通確認

### OHN-042 Deploy 手順書
- Goal: 単一 writer 前提のデプロイ手順を文書化
- Acceptance:
1. `MAGE_ENFORCE_SINGLE_WRITER=1` を利用
2. deploy 後に `kubectl get mga -n kotodama-runtime` + health check 実施

## 実装順（推奨）
1. OHN-001
2. OHN-002
3. OHN-010
4. OHN-003
5. OHN-011
6. OHN-020
7. OHN-021
8. OHN-022
9. OHN-030
10. OHN-031
11. OHN-040
12. OHN-041
13. OHN-042
