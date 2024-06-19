# ChIP-Atlas EC2 インスタンス起動スクリプト

## 必要なもの

- `awscli` がインストールされていること
  - `aws configure` で設定が完了していること
- `launch-chip-atlas.conf` に必要な環境変数をセットしておく
  - AWS_EC2_LAUNCH_TEMPLATE_ID
  - CHIP_ATLAS_AWS_ACCOUNT_ID

## 使い方

### 新規に起動する

```bash
$ ./launch-chip-atlas.sh --launch
```

ちょっと時間がかかります。起動に成功すると `temporalInstance-<起動日時>_info.json` というファイルが作成される。停止・再起動の際はこれを入力に与える必要があるので消さないこと。

### 停止する

```bash
$ ./launch-chip-atlas.sh --stop <temporalInstance-XXXXXXXX-XXXXXX_info.json>
```

### 再起動する

```bash
$ ./launch-chip-atlas.sh --start <temporalInstance-XXXXXXXX-XXXXXX_info.json>
```

## 注意すること

- `aws configure` で設定する access key と access secret は外部に漏らさないこと。漏れたかも？と思ったら即座に失効させる必要があるので担当者に連絡すること。
- 起動した EC2 インスタンスは必要な作業が終わったら停止すること。停止している間は課金されないが、起動している間は課金されるので注意すること。
- インスタンスを完全に削除することはこのスクリプトではできない。削除する場合は担当者に連絡すること。
