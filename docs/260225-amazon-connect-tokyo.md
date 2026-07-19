# Amazon Connect Tokyo 接続メモ

## 実行

```bash
AWS_ID=<access-key-id> \
AWS_SECRET=<secret-access-key> \
60-apps/etzhayyim-project-ohanashi/70-tools/70-tools/70-tools/scripts/260225-amazon-connect-tokyo-check.sh
```

または標準変数:

```bash
AWS_ACCESS_KEY_ID=<access-key-id> \
AWS_SECRET_ACCESS_KEY=<secret-access-key> \
AWS_REGION=ap-northeast-1 \
60-apps/etzhayyim-project-ohanashi/70-tools/70-tools/70-tools/scripts/260225-amazon-connect-tokyo-check.sh
```

## 確認済みインスタンス（2026-02-25）

- Alias: `ccetzhayyimai`
- Region: `ap-northeast-1`
- Status: `ACTIVE`
- Access URL: `https://ccetzhayyimai.my.connect.aws`

## 注意

- 資格情報はリポジトリに保存しない。
- 会話/チケットに公開したキーはローテーションする。
