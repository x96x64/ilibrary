# Retained Rebuilding Bundle Diagnostics

## Purpose and Boundaries

display-v2はメディアフォルダの確認を通過しましたが、以前の`ilibrary-m10-v2`のファイル一覧が保存済みの一覧と一致せず停止しました。足りないファイルと増えたファイルを区別するため、**Musicを操作しない確認だけ**を行います。表示順の検証はまだ再開しません。

この確認は、旧一式を読み取り、差分の記録だけを共有場所の`reference-private`内に新規作成します。旧一式、音声、以前の結果を編集・移動・削除しません。Musicの起動、終了、設定変更、ライブラリの選択は不要です。同期やApple Accountの操作も不要です。

## Step 1: Use the Existing Test User

1. 普段のユーザーで作業中の文書を保存し、前回と同じ`ilibrarytest`に切り替えます。新しいユーザーは作りません。
2. ターミナルを開きます。旧フォルダを開いて整理したり、ファイルを消したりしないでください。
3. 以下を一つのブロックとして実行します。

```sh
cd /Users/Shared &&
shasum -a 256 -c ilibrary-m10-inspect-bundle.py.sha256 &&
python3 -B /Users/Shared/ilibrary-m10-inspect-bundle.py
```

スクリプトと照合ファイルは転送済みです。最初に`OK`、最後に「確認完了」と報告先が表示されれば、差分の記録ができています。一覧が不一致でも、それを記録できればこの確認は完了です。M10の合格を意味しません。

予定だけを見る場合は、最後のコマンドに`--dry-run`を付けられます。その場合は旧一式を読まず、報告ファイルも作りません。

## Step 2: Return One Report

普段のユーザーに戻り、この一文を送ってください。

> M10の検証一式の差分を確認してください：`/Users/Shared/reference-private/m10-display-inventory/inventory.json`

追加ファイルの名前などは私的な記録にだけ保存しています。JSONの全文や音声を公開場所へ貼る必要はありません。

`STOP`が出た場合や、最後の報告先が出なかった場合は、そのターミナル表示だけを送ってください。同じコマンドを繰り返したり、既存の報告ファイルを消したりしないでください。

## Preservation and Next Action

差分を確認するまでは、display-v2も以前の測定も再実行しません。Musicのメディアフォルダは変更せず、すべての一式、停止記録、ライブラリ、バックアップを保持してください。

診断は原因を絞るためのもので、自動修復は行いません。対象ファイルの種類と必要な内容の一致を評価してから、限定的な修正が必要か判断します。

## Recommended Models and Effort

次の差分評価は、Claude Code：Claude Opus 5.5／xhigh、Codex：GPT-6-Astra／xhighを推奨します。
