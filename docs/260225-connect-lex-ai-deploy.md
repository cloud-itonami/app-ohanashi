# Amazon Connect 実会話化 (Lex V2 + Lambda + Bedrock)

この手順で `etzhayyim-project-ohanashi` の Amazon Connect 通話を AI 会話に接続する。

## 1. 実行

```bash
AWS_ID=<access-key-id> \
AWS_SECRET=<secret-access-key> \
AWS_REGION=ap-northeast-1 \
INSTANCE_ID=6294ff1a-c6aa-418d-9ea2-188081951579 \
PHONE_NUMBER_ID=1070476c-7e3c-49bd-af7b-dd4951a7f97e \
60-apps/etzhayyim-project-ohanashi/70-tools/70-tools/70-tools/scripts/260225-deploy-connect-lex-ai.sh
```

## 2. 生成されるもの

- Lambda: `ohanashi-lex-bedrock-handler`
- Lex Bot: `ohanashi-voice-bot` (ja_JP)
- Lex Alias: `ohanashi-prod`
- Connect Contact Flow: `ohanashi-ai-inbound-flow`
- 指定電話番号への flow 紐付け

## 3. 動作

- 電話着信 -> Connect inbound flow
- `ConnectParticipantWithLexBot` で Lex V2 呼び出し
- Lex code hook Lambda が Bedrock に問い合わせて応答生成

## 4. 注意

- Bedrock モデルIDは Lambda環境変数 `BEDROCK_MODEL_ID` で調整可能。
- 公開済み AWS キーはローテーションすること。
