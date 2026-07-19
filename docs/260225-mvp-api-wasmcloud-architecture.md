# etzhayyim-project-ohanashi MVP API / App Architecture

## 1. Logical Components

- `phone-gateway-adapter`
: SIP/Telco 連携。着信・切断・DTMF・音声ストリームイベントを正規化。
- `ohanashi-voice-orchestrator` (App)
: セッション状態管理、対話制御、ガードレール、エスカレーション。
- `ohanashi-summary-worker`
: 通話終了後の要約生成と通知投入。
- `ohanashi-family-portal` (`ohanashi.etzhayyim.com`)
: 同意・通知先設定・履歴閲覧。

## 2. API Contract (MVP)

### `POST /api/voice/session/start`
- Request:
```json
{
  "call_id": "telco-uuid",
  "caller": "+81xxxxxxxxxx",
  "started_at": "2026-02-25T10:00:00Z"
}
```
- Response:
```json
{
  "session_id": "ohn_xxxxx",
  "status": "started"
}
```

### `POST /api/voice/session/{session_id}/turn`
- Request:
```json
{
  "turn_id": "1",
  "audio_ref": "gateway://chunk/abc",
  "transcript_hint": "optional"
}
```
- Response:
```json
{
  "assistant_text": "...",
  "tts_ref": "tts://chunk/xyz",
  "risk_level": "low"
}
```

### `POST /api/voice/session/{session_id}/end`
- Request:
```json
{
  "ended_at": "2026-02-25T10:15:00Z",
  "reason": "caller_hangup"
}
```
- Response:
```json
{
  "status": "closed",
  "summary_job_id": "job_xxx"
}
```

## 3. Data Model (MVP)

- `voice_sessions`
: session_id, call_id, caller_hash, started_at, ended_at, status
- `voice_turns`
: session_id, turn_id, user_text, assistant_text, risk_level, created_at
- `voice_summaries`
: session_id, summary, action_items, family_notified_at
- `consents`
: person_id, guardian_id, scope, granted_at, revoked_at

## 4. App Deploy Layout

- system providers: `kotodama-system`
- app resources: `kotodama-runtime`
- `default` namespace は使用禁止

Deploy command:
```bash
MAGE_ENFORCE_SINGLE_WRITER=1 \
MAGE_DEPLOY_WRITER_ID=ohanashi-release \
MAGE_WRITER_ID=ohanashi-release \
mage Deploy
```

Post deploy checks:
```bash
kubectl get mga ohanashi-voice-orchestrator -n kotodama-runtime
curl -fsS https://ohanashi.etzhayyim.com/_app/version.json
```

## 5. Routing

- Primary host: `ohanashi.etzhayyim.com`
- MCP endpoint: `https://ohanashi.etzhayyim.com/api/mcp`
- Legacy path-based routing は追加しない

## 6. Safety Guardrails

- 医療/法律の確定判断は禁止
- 緊急時は AI 応答を継続しつつ人間窓口へ即時転送
- 会話冒頭で AI であることを必ず明示
- 危険判定理由は監査ログへ保存
