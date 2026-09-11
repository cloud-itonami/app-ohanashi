# operator-quickstart

**この repo で今日実際にできることを、上から順に踏める形で書く。**
所要 5 分。AWS アカウントも資格情報も要らない（要る手順は §3 で、
なぜ踏めないかも含めて書く）。

書いてある出力はすべて、**push 済みブランチの fresh clone を実際に
walk した結果**である。手元の worktree の出力ではない。

## 0. 前提

| 要るもの | 確認 | この walk で使った版 |
|---|---|---|
| git | `git --version` | 2.51.0 |
| Python | `python3 -V` | 3.14.5 |
| nbb | `npx --yes nbb --version` | v1.4.208 |

**`boto3` は要らない**（§2 でスタブを置く）。**AWS CLI は使わない。**

## 1. 取得して、書いてあることが本当か検査する

```bash
git clone git@github.com:cloud-itonami/app-ohanashi.git
cd app-ohanashi
REPO=$PWD            # §2 と §3 でこれを使う
npx --yes nbb scripts/verify-docs-claims.cljk .
```

期待する出力（末尾）:

```
SCANNED	17
PASS	tracked-files	expected=17	actual=17
PASS	inherited-bytes	expected=28044	actual=28044
PASS	preserved-files-unchanged	expected=[]	actual=[]
...
OK	every claim in README.md and docs/operator-quickstart.md holds
```

`OK` なら、README の数値・存在・不在は tree と一致している。
**exit 2（UNDETERMINED）は 0 ではない** —— tree を読み切れなかったという
別の答えで、「検査して問題なし」と混ぜない。

## 2. 唯一の実行コードを走らせる —— ここがこの repo で一番大事な 5 分

`aws/connect/lex-lambda/lambda_function.py` が、この repo で唯一
実行できるコードである。Amazon Lex V2 の code hook として呼ばれ、
Bedrock に問い合わせて返答を作る。

`boto3` が要るが、**スタブを置けば AWS 無しで挙動を全部観測できる**。
scratch ディレクトリを作る（repo は汚さない）:

```bash
mkdir -p /tmp/ohanashi-walk && cd /tmp/ohanashi-walk
cp "$REPO/aws/connect/lex-lambda/lambda_function.py" .

cat > boto3.py <<'PY'
CALLS = []
FAIL = False

class _Bedrock:
    def converse(self, **kw):
        CALLS.append(kw)
        if FAIL:
            raise RuntimeError("simulated Bedrock failure")
        return {"output": {"message": {"content": [{"text": "お薬は決まった時間に飲みましょう。"}]}}}

def client(name):
    CALLS.append(("client", name))
    return _Bedrock()
PY

python3 - <<'PY'
import boto3, lambda_function as L
def run(label, event):
    before = len(boto3.CALLS)
    out = L.lambda_handler(event, None)
    print("---", label)
    print("  converse calls:", sum(1 for c in boto3.CALLS[before:] if isinstance(c, dict)))
    print("  reply:", out["messages"][0]["content"])
    print("  dialogAction:", out["sessionState"]["dialogAction"]["type"])
    print("  history:", out["sessionState"]["sessionAttributes"]["history"][:60])

run("1. 無言（inputTranscript 空）", {"inputTranscript": "", "sessionState": {"sessionAttributes": {}}})
run("2. 普通のターン", {"inputTranscript": "薬を飲む時間がわからない", "sessionState": {"sessionAttributes": {}}})
boto3.FAIL = True
run("3. Bedrock が落ちる", {"inputTranscript": "胸が苦しい", "sessionState": {"sessionAttributes": {}}})
print("import 時に作られた client:", [c for c in boto3.CALLS if isinstance(c, tuple)])
PY
```

実際の出力:

```
--- 1. 無言（inputTranscript 空）
  converse calls: 0
  reply: こんにちは。おはなしです。今日はどんなことを相談したいですか？
  dialogAction: ElicitIntent
  history: ユーザー:
AI:こんにちは。おはなしです。今日はどんなことを相談したいですか？
--- 2. 普通のターン
  converse calls: 1
  reply: お薬は決まった時間に飲みましょう。
  dialogAction: ElicitIntent
  history: ユーザー:薬を飲む時間がわからない
AI:お薬は決まった時間に飲みましょう。
--- 3. Bedrock が落ちる
  converse calls: 1
  reply: いま少しつながりにくいです。もう一度ゆっくり話してみてください。
  dialogAction: ElicitIntent
  history: ユーザー:胸が苦しい
AI:いま少しつながりにくいです。もう一度ゆっくり話してみてください。
import 時に作られた client: [('client', 'bedrock-runtime')]
```

**ケース 3 を読むこと。** 「胸が苦しい」という発話に対してモデル呼び出しが
失敗したが、返るのは:

- ケース 2 と**同じ形の成功応答**（`messages` + `ElicitIntent`）
- 履歴には **AI が答えたことにされた 1 ターン**が追記される
- ログもメトリクスも risk 信号も**出ない**

呼び出し側（Lex → Connect → 通話）からは、**モデルが答えられなかったことと
問題なしと答えたことが区別できない**。`docs/260225-implementation-backlog.md`
の OHN-010／OHN-011 は critical 判定と即時転送を要求しているが、
ここにその経路は無い（`risk` という文字列がコードに 0 回）。

もう 1 つ観測できること: `boto3.client("bedrock-runtime")` は
**import 時**に実行される。だから単体テストを書くにも、まずこの副作用を
どうにかする必要がある（テストが 0 本である理由の一部でもある）。

## 3. デプロイは踏めない —— 実際に確かめる

`docs/260225-connect-lex-ai-deploy.md` が案内するデプロイは、
**この repo からは実行できない**。AWS 資格情報の問題ではない。

```bash
cd "$REPO"
sed -n '25p' scripts/260225-deploy-connect-lex-ai.sh
test -e projects/etzhayyim-project-ohanashi/aws/connect/lex-lambda/lambda_function.py \
  && echo "存在する" || echo "この tree に無い"
```

出力:

```
cp projects/etzhayyim-project-ohanashi/aws/connect/lex-lambda/lambda_function.py "$WORKDIR/"
この tree に無い
```

script は `set -euo pipefail` で、この `cp` は資格情報チェックの直後・
**AWS API 呼び出しより前**にある。したがってダミーの資格情報で走らせても、
AWS には 1 回も触れずに exit 1 する。AWS CLI を PATH から外して確認した:

```bash
cd "$REPO"
env -i PATH=/usr/bin:/bin HOME="$HOME" \
  AWS_ACCESS_KEY_ID=dummy AWS_SECRET_ACCESS_KEY=dummy \
  bash scripts/260225-deploy-connect-lex-ai.sh; echo "exit=$?"
```

```
cp: projects/etzhayyim-project-ohanashi/aws/connect/lex-lambda/lambda_function.py: No such file or directory
exit=1
```

**この walk は AWS を一切呼んでいない**（`aws` バイナリが PATH に無い状態で
走らせ、その手前で落ちることを確かめている）。実体は `aws/connect/lex-lambda/`
に在るので 1 行直せば進むが、**直していない** —— この repo が自己完結するのか
monorepo を参照し続けるのかという境界の決定が先だからである（README の
「既知の欠陥」1・2）。

`docs/` が案内する `60-apps/…/70-tools/70-tools/70-tools/scripts/…` も
同じ理由で踏めない（`70-tools` の 3 重は抽出前からの誤り）。

## 4. ここに無いもの

- **テスト 0 本**、`src/` 無し、CI 無し
- 設計文書が定める 4 コンポーネント（phone-gateway-adapter /
  voice-orchestrator / summary-worker / family-portal）の実装
- リスク分類・エスカレーション・家族通知・監査ログ・PII マスキング・TTL
- `ohanashi.etzhayyim.com`（この walk では名前解決しない）

**この repo を「動くサービス」として扱わない。** 設計文書 5 本と、
Lex code hook 1 本と、踏めないデプロイ script が在る、という状態である。
