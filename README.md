# app-ohanashi

**おはなし — 高齢者が「電話だけで」AI に相談できるサービスの設計と、その
Amazon Connect 実装の断片。** 名前が機能を示さないので先に名乗る（この
workspace の規約）。`ohanashi` は「お話」であって、repo の中身は
**電話相談（voice consultation）** である。

この repo は `etzhayyim/root` の `60-apps/etzhayyim-project-ohanashi` から
抽出された。**抽出物であって、動くサービスではない。** 何が在って何が無いかを
数えたものが以下で、数字はすべて `scripts/verify-docs-claims.cljs` が
tree から再計算して検査している（食い違ったら CI ではなく検証器が落ちる）。

## いま在るもの — 13 ファイル / 28,044 バイト

| 面 | ファイル | バイト |
|---|---|---|
| **実行できるコード** | `aws/connect/lex-lambda/lambda_function.py` | 2,844 |
| 設計文書 | `docs/260225-project-plan.md` | 2,675 |
| 〃 | `docs/260225-mvp-api-wasmcloud-architecture.md` | 2,452 |
| 〃 | `docs/260225-implementation-backlog.md` | 3,453 |
| 手順メモ | `docs/260225-amazon-connect-tokyo.md` | 795 |
| 〃 | `docs/260225-connect-lex-ai-deploy.md` | 1,057 |
| デプロイ script | `scripts/260225-deploy-connect-lex-ai.sh` | 10,837 |
| 疎通確認 script | `scripts/260225-amazon-connect-tokyo-check.sh` | 584 |
| 由来・権利・識別 | `NOTICE` / `OWNERS` / `PROJECT.jsonld` / `README.edn` / `migration.edn` | 3,347 |

**テストは 0 本。`src/` は無い。** 実行できるのは Lambda ハンドラ 1 本だけで、
それは `docs/` が設計した 4 コンポーネント（phone-gateway-adapter /
voice-orchestrator / summary-worker / family-portal）の**どれでもない**。

## ⚠ 安全上の現在地 — 設計された安全装置は 1 つも実装されていない

これは高齢者からの電話を受ける設計の repo なので、最初に書く。

`docs/260225-mvp-api-wasmcloud-architecture.md` と
`docs/260225-implementation-backlog.md` は次を定めている:

- リスク分類 `none|low|medium|high|critical` を返すこと（OHN-010）
- `critical` なら人間窓口へ即時転送、失敗時は callback queue（OHN-011）
- 判定理由を監査ログへ保存すること
- 家族への要約通知（OHN-020/021）

**実装されているコードにこれらは 1 つも無い。** `lambda_function.py` に
`risk` という文字列は **0 回**しか出てこない（検証器が数えている）。在るのは
system prompt の「医療・法律の確定判断は行わない」という*お願い*だけで、
分類も転送も監査もしない。

さらに悪い性質が 1 つある。ハンドラは Bedrock 呼び出しを
`except Exception` で丸ごと飲み込み、**失敗を成功と同じ形で返す**:

```
入力「胸が苦しい」 + Bedrock が例外 →
  返答「いま少しつながりにくいです。もう一度ゆっくり話してみてください。」
  dialogAction: ElicitIntent（通話は普通に継続）
  history: 「ユーザー:胸が苦しい／AI:いま少しつながりにくいです…」と記録
  ログ・メトリクス・risk 信号: いずれも出ない
```

**モデルが答えられなかったことと、モデルが問題なしと答えたことが、
呼び出し側から区別できない。** しかも履歴には AI が応答したことにされ、
次のターンのプロンプトにその捏造ターンが載る。これは 10 秒で再現できる
（[`docs/operator-quickstart.md`](docs/operator-quickstart.md) §2）。

この repo を動かす判断をするなら、**まずここを直す**。詳細は
[`docs/adr/0001-what-this-repository-actually-contains.edn`](docs/adr/0001-what-this-repository-actually-contains.edn)。

## 互換しない 2 つの基盤が同居している

| 出典 | 基盤 | デプロイ | ホスト |
|---|---|---|---|
| `docs/260225-mvp-api-wasmcloud-architecture.md` | wasmCloud / kotodama | `mage Deploy` + `kubectl get mga -n kotodama-runtime` | `ohanashi.etzhayyim.com` |
| `docs/260225-connect-lex-ai-deploy.md` + `aws/` + `scripts/` | Amazon Connect + Lex V2 + Lambda + **Bedrock** | `scripts/260225-deploy-connect-lex-ai.sh` | `ccetzhayyimai.my.connect.aws` |

**どちらが正本かはこの repo からは決まらない。** 唯一の実行コードは下の行
（AWS 経路）に属し、上の行には実装が 1 バイトも無い。

なお AWS 経路は **Bedrock（外部 LLM）** を呼ぶ。この workspace の他の actor は
Murakumo-only を不変条件に持つものがあり、`NOTICE` が宣言する Charter
Compliance Rider v3.1 との関係は**未解決**である。ここでは事実として記録する
に留める（憲章解釈はこの repo の判断ではない）。

## 由来（custody）

`migration.edn` は出所を `etzhayyim/root` の tree `aca35b2c` と宣言している。
GitHub 上のその tree を実際に引いて突き合わせた結果:

- 元の **11 ファイル / 27,393 バイトが 1 バイトも変わらずに保存されている**
  （sha256 を `scripts/verify-docs-claims.cljs` に固定してある）
- 追加は `README.edn` と `migration.edn` の 2 件だけ（抽出メタデータ）
- 11 + 2 = 13 ファイル、27,393 + 651 = 28,044 バイト

`migration.edn` の `:tracked-files 11` は**出所側の数**であって、この repo の
ファイル数ではない。13 と 11 の差はこの 2 件である。

## 既知の欠陥（測定済み・直していない）

1. **デプロイ script が存在しないパスから copy する。**
   `scripts/260225-deploy-connect-lex-ai.sh:25` は
   `projects/etzhayyim-project-ohanashi/aws/connect/lex-lambda/lambda_function.py`
   を copy するが、この tree にそのパスは無い（実体は `aws/…`）。
   `set -euo pipefail` なので、**AWS を 1 回も呼ばずに exit 1 する**。
2. **3 通りのパス規約が混在している。** 上記の `projects/…` に加えて、
   `docs/` は `60-apps/etzhayyim-project-ohanashi/70-tools/70-tools/70-tools/scripts/…`
   を 3 箇所で案内する（`70-tools` が 3 重になっているのは抽出前からの誤り）。
   実際の場所は `scripts/` である。合計 4 箇所（検証器が数えている）。
3. **リスク分類・エスカレーション・家族通知が未実装**（上記「安全上の現在地」）。
4. **モデル失敗が成功と区別できない**（同上）。
5. **稼働中の AWS 資源 ID が commit されている** — Connect インスタンス
   `6294ff1a-…`、電話番号 `1070476c-…`、IAM role ARN（account `808985…`）。
   資格情報ではないが、`docs/` 自身が「公開済み AWS キーはローテーションする」と
   書いており、鍵が一度露出した経緯があることを示唆する。

**どれも直していない。** 1 と 2 は「この repo が自己完結するのか、monorepo を
引き続き参照するのか」という境界の決定を先に要し、3 と 4 は設計の決定を要し、
5 は運用側の判断だからである。直す前に、まず読める形にした。

## 検証

```bash
nbb scripts/verify-docs-claims.cljs .     # <dir> は先頭に置く
```

この README と `docs/operator-quickstart.md` が述べる数値・存在・不在を
tree から再計算して照合する。exit 0 = 全一致 / 1 = 食い違い /
**2 = 判定できなかった**（tree を読めない場合。0 と区別する）。
