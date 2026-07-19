import json
import os
from typing import Dict, Any

import boto3

BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "openai.gpt-oss-20b-1:0")
MAX_HISTORY_CHARS = int(os.getenv("MAX_HISTORY_CHARS", "3000"))

bedrock = boto3.client("bedrock-runtime")

SYSTEM_PROMPT = (
    "あなたは高齢者向けの電話相談AI『おはなし』です。"
    "短く、やさしい日本語で返答してください。"
    "医療・法律の確定判断は行わず、必要時は専門窓口への相談を促してください。"
)


def _safe_get(d: Dict[str, Any], *keys: str, default=None):
    cur = d
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur


def _invoke_bedrock(user_text: str, history: str) -> str:
    prompt = (
        f"会話履歴:\n{history}\n\n"
        f"ユーザー発話: {user_text}\n"
        "回答(120文字以内):"
    )

    resp = bedrock.converse(
        modelId=BEDROCK_MODEL_ID,
        system=[{"text": SYSTEM_PROMPT}],
        messages=[{"role": "user", "content": [{"text": prompt}]}],
        inferenceConfig={
            "maxTokens": 300,
            "temperature": 0.4,
            "topP": 0.9,
        },
    )

    output = resp.get("output", {})
    message = output.get("message", {})
    content = message.get("content", [])
    for item in content:
        txt = item.get("text", "").strip()
        if txt:
            return txt

    return "ご相談ありがとうございます。もう少しくわしく教えてください。"


def lambda_handler(event, _context):
    session_attributes = _safe_get(event, "sessionState", "sessionAttributes", default={}) or {}
    user_text = event.get("inputTranscript", "").strip()

    history = session_attributes.get("history", "")
    if len(history) > MAX_HISTORY_CHARS:
        history = history[-MAX_HISTORY_CHARS:]

    if not user_text:
        reply = "こんにちは。おはなしです。今日はどんなことを相談したいですか？"
    else:
        try:
            reply = _invoke_bedrock(user_text=user_text, history=history)
        except Exception:
            reply = "いま少しつながりにくいです。もう一度ゆっくり話してみてください。"

    new_history = (history + f"\nユーザー:{user_text}\nAI:{reply}").strip()
    if len(new_history) > MAX_HISTORY_CHARS:
        new_history = new_history[-MAX_HISTORY_CHARS:]

    return {
        "sessionState": {
            "dialogAction": {"type": "ElicitIntent"},
            "sessionAttributes": {
                **session_attributes,
                "history": new_history,
            },
        },
        "messages": [
            {
                "contentType": "PlainText",
                "content": reply,
            }
        ],
    }
