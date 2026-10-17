# Rebuilding Feasibility Validation

## Current Status and Scope

**v2 の結果評価後の停止指示：** 保存済み日時の確認も完了し、small の6曲に1秒の差があると分かりました。全曲の追加日時の完全一致という条件は未達です。[日時の完了条件の評価](reports/rebuild-timestamp-gate.md)を参照してください。以下の本測定や日時の読み取りを再実行せず、scale も始めません。次は本人による方針判断で、追加の Mac 操作は不要です。以下は今回使用した手順として保持します。

初回の small と scale は、最初の追加後の保存場所確認で停止しました。`EMPTY` と表示順の質問は、その先の段階にあるため表示されていません。入力を飛ばしたわけではありません。[初回の評価](reports/rebuild-feasibility-results.md)は保存しています。

本人の指示により、今回は **v2 の新しい検証一式と、新しい空のライブラリ**で診断と本測定をまとめて行います。以前の検証一式・ライブラリ・結果は残します。Music から場所を取得する書き方を既存の追加コマンドと揃え、旧方式との違いも記録します。初回停止の原因がこれで解消するかは未確認です。比較条件を緩めたり、違う場所を正しいものとして扱ったりはしません。

測定するのは 6 曲・3 アルバムと 300 曲・20 アルバムです。最後に **結果を一つにまとめて1回報告**します。全曲の追加日時の完全一致と画面上の順序は、実際の結果で判定します。成功を保証するものではありません。

**普段のユーザーと実ライブラリでは実行しません。** 合成ファイルの保存用コピーは同じ物理ディスク上の読み取り専用イメージです。実ライブラリ用の独立したバックアップの検証にはなりません。

## Step 1: Transfer Version 2

普段のユーザーのターミナルで、次のブロックを実行します。新しい ZIP と照合用ファイルだけを共有場所へコピーします。

```sh
cd ~/ilibrary
cp -n artifacts/m10-preparation-v2/ilibrary-m10-v2.zip /Users/Shared/ilibrary-m10-v2.zip
cp -n artifacts/m10-preparation-v2/ilibrary-m10-v2.zip.sha256 /Users/Shared/ilibrary-m10-v2.zip.sha256
cd /Users/Shared
shasum -a 256 -c ilibrary-m10-v2.zip.sha256
```

`ilibrary-m10-v2.zip: OK` が出れば次へ進みます。エラーなら止めて、その表示を報告してください。既存の ZIP や旧版を削除しません。

## Step 2: Open the Separate Test User

普段のユーザーからログアウトし、前回使用した `ilibrarytest` などの検証用ユーザーでログインします。Apple Account にはサインインしません。以前の検証ユーザーを作り直す必要はありません。

検証用ユーザーのターミナルで実行します。

```sh
cd /Users/Shared
shasum -a 256 -c ilibrary-m10-v2.zip.sha256
cd ~
test ! -e ilibrary-m10-v2 && unzip -q /Users/Shared/ilibrary-m10-v2.zip
cd ~/ilibrary-m10-v2
python3 rebuild_probe.py verify .
```

最後に `PASS: bundle verification; Music not accessed` が出ることを確認します。`ilibrary-m10-v2` が既にあった場合やエラーの場合は、上書きや削除をせず止めてください。旧版の `ilibrary-m10` フォルダはそのまま残します。

## Step 3: Create the Small Library

1. 検証用ユーザーで Music を終了します。
2. **Option キーを押しながら Music を開き、「ライブラリを作成」を選びます。** 今回は旧ライブラリを選び直す手順ではありません。
3. このユーザーの「ミュージック」フォルダ内に、**`M10-v2-small`** という新しい名前で保存します。同名のものが既にある場合は上書きせず止めます。
4. Music の「設定」→「ファイル」でメディアの場所を確認します。このケース専用の **`~/Music/M10-v2-small/Media`** を選びます。必要なら選択画面で `Media` フォルダを作成します。旧ケースや scale と同じ場所にはしません。
5. この新しいライブラリで「メディアフォルダを整理」と「ライブラリへの追加時にファイルをメディアフォルダへコピー」の項目をオンにします。設定画面を閉じます。
6. Apple Account に未サインイン、同期なしであることと、「曲」「最近追加した項目」が空であることを確認します。Music は開いたままにします。

新規ライブラリとファイル設定の操作は、Apple の[複数ライブラリの案内](https://support.apple.com/guide/music/use-multiple-libraries-mus7663a920a/mac)と[ファイル設定の案内](https://support.apple.com/guide/music/files-settings-mus0f5accea/1.7/mac/27)に沿っています。画面上の日本語表記が多少異なる場合は、メディアの場所・整理・コピーの各項目で確認してください。

## Step 4: Measure the Small Case

まず予定だけを表示します。

```sh
cd ~/ilibrary-m10-v2
python3 rebuild_probe.py run --case small --dry-run
```

エラーがなければ、本測定を実行します。

```sh
python3 rebuild_probe.py run --case small
```

自分で入力するのは、**質問が表示されたときだけ**です。

| 表示された質問 | 行うこと |
| --- | --- |
| 最初の `TEST` | 検証用ユーザー・未サインイン・同期なし・新しい空のライブラリを確認して入力します。Music 操作の許可が出たら許可します |
| `EMPTY` | 合成曲の登録削除後、Music の「曲」と「最近追加した項目」が両方空になったことを見てから入力します |
| `EXPECTED` / `DIFFERENT` / `UNKNOWN` | 再登録後、最近追加した項目を新しい側から確認します。**M10 Album 03 → 02 → 01** なら `EXPECTED`、違えば `DIFFERENT`、全体を確認できなければ `UNKNOWN` と入力します |

処理中に Music を自分で終了・起動したり、曲を移動・削除したりしません。`EMPTY` に答えた後の終了・タグ編集・再起動はスクリプトが行います。GUI が空にならず答えられない場合はターミナルで Control-C を押し、その状態を報告します。

`PHASE:` は現在の段階です。`case gate:` まで出てシェルの入力待ちに戻れば、そのケースの実行は終わっています。

- **`STOP` が出た場合**：質問がまだ出なくても入力する必要はありません。同じコマンドを再実行せず、scale へも進まず、Step 6 で結果をまとめてください。
- **日時や順序の `FAIL` はあるが `STOP` がない場合**：測定は完了しています。結果を残して scale に進みます。
- **`PASS` の場合**：scale に進みます。

## Step 5: Measure the Scale Case

small が `STOP` なしで最後まで進んだ場合だけ行います。

Music を終了し、Step 3 と同じ方法で新しいライブラリ **`M10-v2-scale`** を作ります。メディアの場所は **`~/Music/M10-v2-scale/Media`** にし、整理・コピーの項目をオンにします。small のライブラリとファイルは残します。

空の状態を確認したら、次を実行します。

```sh
cd ~/ilibrary-m10-v2
python3 rebuild_probe.py run --case scale --dry-run
python3 rebuild_probe.py run --case scale
```

質問への答え方は small と同じです。表示順の期待値は、新しい側から **M10 Album 20 → 19 → … → 01** です。見えている範囲だけで成功とせず、全体を確認できなければ `UNKNOWN` と答えます。300 曲なので small より時間がかかります。

`STOP` が出た場合はそのまま Step 6 に進みます。登録やファイルを自分で元に戻しません。

## Step 6: Return One Combined Report

成功・失敗・途中停止のどの場合でも、検証用ユーザーで以下を実行します。これは保存済みの結果をまとめるだけで、Music にアクセスしません。

```sh
cd ~/ilibrary-m10-v2
mkdir -p reference-private
python3 rebuild_probe.py report > reference-private/ilibrary-m10-v2-report.txt
cat reference-private/ilibrary-m10-v2-report.txt
```

**表示された全文を1回、この会話へ貼り付けてください。** scale を実行しなかった場合も `NOT RUN` と記録されるため、結果ファイルを個別に探す必要はありません。内容は段階・件数・停止理由・場所の比較分類・追加日時の差・目視の回答で、個人パスや曲の ID は含みません。

ファイルの場所を渡す方法を使う場合は、続けて以下を実行します。

```sh
cp -n reference-private/ilibrary-m10-v2-report.txt /Users/Shared/ilibrary-m10-v2-report.txt
cmp -s reference-private/ilibrary-m10-v2-report.txt /Users/Shared/ilibrary-m10-v2-report.txt && echo '報告用ファイルのコピー: OK'
```

`OK` が出たら、普段のユーザーに戻って、この会話へ `/Users/Shared/ilibrary-m10-v2-report.txt` と送れば十分です。`OK` が出ない場合は上書きせず、先ほどの `cat` の表示を貼り付けます。

`diagnostics.jsonl`、`initial-registration.json`、`commands.log`、音声、ディスクイメージは貼り付けません。詳細な比較情報は検証用ユーザーの `reference-private/` に残ります。確認が終わるまで、新旧両方の一式とライブラリを保持します。

Step 1〜3 や `--dry-run` で止まり、まだ結果がない場合は、その Step 番号と最後のエラー表示だけを報告してください。推測で操作を続けません。

## Evidence Limits and Preparation

v2 は停止箇所・取得方式の違い・失敗した比較を残し、1回の報告に必要な情報を増やすものです。Mac や Music の未知の挙動によって追加確認が必要になる可能性まではなくせません。追加日時の不一致を成功扱いにしたり、安全条件を省略して最後まで進めたりはしません。

開発側の準備は `sh scripts/validation/prepare-rebuild-probe.sh --prepare`、予定表示は `--dry-run` です。ガード試験は `python3 -m unittest discover -s scripts/validation -p 'test_rebuild_probe.py'` で実行します。エージェントは別ユーザーの Music を操作する直前で停止し、本人の結果を待ちます。

## Recommended Models and Effort

結果の評価と必要な修正は、Claude Code：Claude Opus 5.5／xhigh、Codex：GPT-6-Astra／xhigh を推奨します。
