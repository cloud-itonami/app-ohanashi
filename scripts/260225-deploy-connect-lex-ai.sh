#!/usr/bin/env bash
set -euo pipefail

: "${AWS_ACCESS_KEY_ID:=${AWS_ID:-}}"
: "${AWS_SECRET_ACCESS_KEY:=${AWS_SECRET:-}}"
: "${AWS_REGION:=ap-northeast-1}"

INSTANCE_ID="${INSTANCE_ID:-6294ff1a-c6aa-418d-9ea2-188081951579}"
PHONE_NUMBER_ID="${PHONE_NUMBER_ID:-1070476c-7e3c-49bd-af7b-dd4951a7f97e}"
LAMBDA_ROLE_ARN="${LAMBDA_ROLE_ARN:-arn:aws:iam::808985145984:role/etzhayyim-lambda-exec}"
BOT_NAME="${BOT_NAME:-ohanashi-voice-bot}"
LAMBDA_NAME="${LAMBDA_NAME:-ohanashi-lex-bedrock-handler}"
CONTACT_FLOW_NAME="${CONTACT_FLOW_NAME:-ohanashi-ai-inbound-flow}"

if [[ -z "${AWS_ACCESS_KEY_ID}" || -z "${AWS_SECRET_ACCESS_KEY}" ]]; then
  echo "ERROR: AWS creds are required" >&2
  exit 1
fi

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

cp projects/etzhayyim-project-ohanashi/aws/connect/lex-lambda/lambda_function.py "$WORKDIR/"
(
  cd "$WORKDIR"
  zip -q function.zip lambda_function.py
)

if aws lambda get-function --function-name "$LAMBDA_NAME" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$LAMBDA_NAME" --zip-file "fileb://$WORKDIR/function.zip" >/dev/null
  aws lambda wait function-updated --function-name "$LAMBDA_NAME"
  aws lambda update-function-configuration \
    --function-name "$LAMBDA_NAME" \
    --runtime python3.12 \
    --handler lambda_function.lambda_handler \
    --timeout 15 \
    --memory-size 512 \
    --environment "Variables={BEDROCK_MODEL_ID=openai.gpt-oss-20b-1:0,MAX_HISTORY_CHARS=3000}" >/dev/null
else
  aws lambda create-function \
    --function-name "$LAMBDA_NAME" \
    --runtime python3.12 \
    --handler lambda_function.lambda_handler \
    --role "$LAMBDA_ROLE_ARN" \
    --timeout 15 \
    --memory-size 512 \
    --zip-file "fileb://$WORKDIR/function.zip" \
    --environment "Variables={BEDROCK_MODEL_ID=openai.gpt-oss-20b-1:0,MAX_HISTORY_CHARS=3000}" >/dev/null
fi

aws lambda wait function-active-v2 --function-name "$LAMBDA_NAME"

LAMBDA_ARN="$(aws lambda get-function --function-name "$LAMBDA_NAME" --query 'Configuration.FunctionArn' --output text)"

echo "[info] lambda_arn=$LAMBDA_ARN"

aws iam create-service-linked-role --aws-service-name lexv2.amazonaws.com >/dev/null 2>&1 || true
LEX_ROLE_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/aws-service-role/lexv2.amazonaws.com/AWSServiceRoleForLexV2Bots"

BOT_ID="$(aws lexv2-models list-bots --query "botSummaries[?botName=='$BOT_NAME']|[0].botId" --output text)"
if [[ -z "$BOT_ID" || "$BOT_ID" == "None" ]]; then
  BOT_ID="$(aws lexv2-models create-bot \
    --bot-name "$BOT_NAME" \
    --role-arn "$LEX_ROLE_ARN" \
    --data-privacy childDirected=false \
    --idle-session-ttl-in-seconds 300 \
    --query 'botId' --output text)"
fi

echo "[info] bot_id=$BOT_ID"

for _ in $(seq 1 60); do
  BOT_STATUS="$(aws lexv2-models describe-bot --bot-id "$BOT_ID" --query 'botStatus' --output text)"
  [[ "$BOT_STATUS" == "Available" ]] && break
  [[ "$BOT_STATUS" == "Failed" ]] && { echo "ERROR: bot creation failed" >&2; exit 1; }
  sleep 5
done

LOCALE_STATUS="$(aws lexv2-models describe-bot-locale --bot-id "$BOT_ID" --bot-version DRAFT --locale-id ja_JP --query 'botLocaleStatus' --output text 2>/dev/null || true)"
if [[ -z "$LOCALE_STATUS" || "$LOCALE_STATUS" == "None" ]]; then
  aws lexv2-models create-bot-locale \
    --bot-id "$BOT_ID" \
    --bot-version DRAFT \
    --locale-id ja_JP \
    --nlu-intent-confidence-threshold 0.40 \
    --voice-settings voiceId=Takumi >/dev/null
fi

for _ in $(seq 1 60); do
  LOCALE_STATUS_NOW="$(aws lexv2-models describe-bot-locale --bot-id "$BOT_ID" --bot-version DRAFT --locale-id ja_JP --query 'botLocaleStatus' --output text)"
  [[ "$LOCALE_STATUS_NOW" == "NotBuilt" || "$LOCALE_STATUS_NOW" == "Built" || "$LOCALE_STATUS_NOW" == "ReadyExpressTesting" ]] && break
  [[ "$LOCALE_STATUS_NOW" == "Failed" ]] && { echo "ERROR: bot locale create failed" >&2; exit 1; }
  sleep 5
done

INTENT_ID="$(aws lexv2-models list-intents --bot-id "$BOT_ID" --bot-version DRAFT --locale-id ja_JP --query "intentSummaries[?intentName=='OhanashiIntent']|[0].intentId" --output text 2>/dev/null || true)"
if [[ -z "$INTENT_ID" || "$INTENT_ID" == "None" ]]; then
  aws lexv2-models create-intent \
    --bot-id "$BOT_ID" \
    --bot-version DRAFT \
    --locale-id ja_JP \
    --intent-name OhanashiIntent \
    --sample-utterances '[{"utterance":"相談したい"},{"utterance":"話を聞いて"},{"utterance":"困っています"},{"utterance":"助けてください"},{"utterance":"こんにちは"}]' \
    --fulfillment-code-hook enabled=true >/dev/null
fi

FALLBACK_ID="$(aws lexv2-models list-intents --bot-id "$BOT_ID" --bot-version DRAFT --locale-id ja_JP --query "intentSummaries[?intentName=='FallbackIntent']|[0].intentId" --output text 2>/dev/null || true)"
if [[ -z "$FALLBACK_ID" || "$FALLBACK_ID" == "None" ]]; then
  aws lexv2-models create-intent \
    --bot-id "$BOT_ID" \
    --bot-version DRAFT \
    --locale-id ja_JP \
    --intent-name FallbackIntent \
    --parent-intent-signature AMAZON.FallbackIntent \
    --fulfillment-code-hook enabled=true >/dev/null || true
fi

aws lexv2-models build-bot-locale --bot-id "$BOT_ID" --bot-version DRAFT --locale-id ja_JP >/dev/null

for _ in $(seq 1 60); do
  STATUS="$(aws lexv2-models describe-bot-locale --bot-id "$BOT_ID" --bot-version DRAFT --locale-id ja_JP --query 'botLocaleStatus' --output text)"
  [[ "$STATUS" == "Built" ]] && break
  [[ "$STATUS" == "Failed" ]] && { echo "ERROR: bot locale build failed" >&2; exit 1; }
  sleep 5
done

BOT_VERSION="$(aws lexv2-models create-bot-version --bot-id "$BOT_ID" --bot-version-locale-specification '{"ja_JP":{"sourceBotVersion":"DRAFT"}}' --query 'botVersion' --output text)"

echo "[info] bot_version=$BOT_VERSION"

for _ in $(seq 1 60); do
  BOT_STATUS_NOW="$(aws lexv2-models describe-bot --bot-id "$BOT_ID" --query 'botStatus' --output text)"
  [[ "$BOT_STATUS_NOW" == "Available" ]] && break
  [[ "$BOT_STATUS_NOW" == "Failed" ]] && { echo "ERROR: bot version publish failed" >&2; exit 1; }
  sleep 5
done

ALIAS_ID="$(aws lexv2-models list-bot-aliases --bot-id "$BOT_ID" --query "botAliasSummaries[?botAliasName=='ohanashi-prod']|[0].botAliasId" --output text 2>/dev/null || true)"
if [[ -z "$ALIAS_ID" || "$ALIAS_ID" == "None" ]]; then
  ALIAS_ID="$(aws lexv2-models create-bot-alias \
    --bot-id "$BOT_ID" \
    --bot-alias-name ohanashi-prod \
    --bot-version "$BOT_VERSION" \
    --bot-alias-locale-settings "{\"ja_JP\":{\"enabled\":true,\"codeHookSpecification\":{\"lambdaCodeHook\":{\"lambdaARN\":\"$LAMBDA_ARN\",\"codeHookInterfaceVersion\":\"1.0\"}}}}" \
    --query 'botAliasId' --output text)"
else
  aws lexv2-models update-bot-alias \
    --bot-id "$BOT_ID" \
    --bot-alias-id "$ALIAS_ID" \
    --bot-alias-name ohanashi-prod \
    --bot-version "$BOT_VERSION" \
    --bot-alias-locale-settings "{\"ja_JP\":{\"enabled\":true,\"codeHookSpecification\":{\"lambdaCodeHook\":{\"lambdaARN\":\"$LAMBDA_ARN\",\"codeHookInterfaceVersion\":\"1.0\"}}}}" >/dev/null
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ALIAS_ARN="arn:aws:lex:${AWS_REGION}:${ACCOUNT_ID}:bot-alias/${BOT_ID}/${ALIAS_ID}"

echo "[info] alias_arn=$ALIAS_ARN"

aws lambda add-permission \
  --function-name "$LAMBDA_NAME" \
  --statement-id "lexv2-${BOT_ID}-${ALIAS_ID}" \
  --action lambda:InvokeFunction \
  --principal lexv2.amazonaws.com \
  --source-arn "$ALIAS_ARN" >/dev/null 2>&1 || true

aws connect associate-bot \
  --instance-id "$INSTANCE_ID" \
  --lex-v2-bot "AliasArn=$ALIAS_ARN" >/dev/null 2>&1 || true

FLOW_CONTENT_FILE="$WORKDIR/flow.json"
cat > "$FLOW_CONTENT_FILE" <<JSON
{
  "Version": "2019-10-30",
  "StartAction": "msg-welcome",
  "Actions": [
    {
      "Identifier": "msg-welcome",
      "Type": "MessageParticipant",
      "Parameters": {
        "Text": "こんにちは。おはなしAIです。ご相談をどうぞ。"
      },
      "Transitions": {
        "NextAction": "lex-connect",
        "Errors": [],
        "Conditions": []
      }
    },
    {
      "Identifier": "lex-connect",
      "Type": "ConnectParticipantWithLexBot",
      "Parameters": {
        "Text": "お困りごとを話してください。",
        "LexV2Bot": {
          "AliasArn": "$ALIAS_ARN"
        },
        "LexTimeoutSeconds": {
          "Text": "300"
        }
      },
      "Transitions": {
        "NextAction": "msg-end",
        "Errors": [
          {
            "NextAction": "msg-error",
            "ErrorType": "InputTimeLimitExceeded"
          },
          {
            "NextAction": "msg-error",
            "ErrorType": "NoMatchingError"
          },
          {
            "NextAction": "msg-error",
            "ErrorType": "NoMatchingCondition"
          }
        ],
        "Conditions": []
      }
    },
    {
      "Identifier": "msg-end",
      "Type": "MessageParticipant",
      "Parameters": {
        "Text": "ご相談ありがとうございました。いつでもお電話ください。"
      },
      "Transitions": {
        "NextAction": "disconnect",
        "Errors": [],
        "Conditions": []
      }
    },
    {
      "Identifier": "msg-error",
      "Type": "MessageParticipant",
      "Parameters": {
        "Text": "通信エラーが発生しました。もう一度おかけ直しください。"
      },
      "Transitions": {
        "NextAction": "disconnect",
        "Errors": [],
        "Conditions": []
      }
    },
    {
      "Identifier": "disconnect",
      "Type": "DisconnectParticipant",
      "Parameters": {},
      "Transitions": {}
    }
  ]
}
JSON

FLOW_ID="$(aws connect list-contact-flows --instance-id "$INSTANCE_ID" --contact-flow-types CONTACT_FLOW --query "ContactFlowSummaryList[?Name=='$CONTACT_FLOW_NAME']|[0].Id" --output text)"
if [[ -z "$FLOW_ID" || "$FLOW_ID" == "None" ]]; then
  FLOW_ID="$(aws connect create-contact-flow \
    --instance-id "$INSTANCE_ID" \
    --name "$CONTACT_FLOW_NAME" \
    --type CONTACT_FLOW \
    --description "Ohanashi AI inbound flow (LexV2 + Bedrock Lambda)" \
    --content "$(cat "$FLOW_CONTENT_FILE")" \
    --query 'ContactFlowId' --output text)"
else
  aws connect update-contact-flow-content \
    --instance-id "$INSTANCE_ID" \
    --contact-flow-id "$FLOW_ID" \
    --content "$(cat "$FLOW_CONTENT_FILE")" >/dev/null
fi

aws connect associate-phone-number-contact-flow \
  --phone-number-id "$PHONE_NUMBER_ID" \
  --instance-id "$INSTANCE_ID" \
  --contact-flow-id "$FLOW_ID" >/dev/null

echo "[done] conversation-ready setup"
echo "instance_id=$INSTANCE_ID"
echo "phone_number_id=$PHONE_NUMBER_ID"
echo "flow_id=$FLOW_ID"
echo "lex_bot_id=$BOT_ID"
echo "lex_alias_id=$ALIAS_ID"
echo "lex_alias_arn=$ALIAS_ARN"
echo "lambda_name=$LAMBDA_NAME"
