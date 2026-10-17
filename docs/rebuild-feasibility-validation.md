# Rebuilding Feasibility Validation

## Purpose and Stop Boundary

M10 の測定手順です。**普段のユーザーと実ライブラリでは実行しません。** 合成音声を退避し、その実行で追加した登録だけを自動削除します。Music の画面が空になったら終了し、タグを編集してから、1 アルバムずつ登録し直します。

今回の準備では Music を起動・参照・操作していません。エージェントは検証一式の準備までで停止します。次の手順は、本人が別ユーザーで実施します。

6 曲・3 アルバムの小規模ケースと、300 曲・20 アルバムの規模確認を分けます。**追加日時は日付だけでなく、Music が返す秒単位の値が全曲で完全一致する必要があります。** 最近追加した項目の表示順は別に確認します。両ケースの結果を読むまで M10 は完了しません。

## What the Probe Can Change

- 最初に空であることを確認した Music ライブラリだけを使います。前回の測定の曲が残るライブラリも拒否します。
- この実行が新しく追加した合成曲だけを、記録した ID で 1 件ずつ削除します。別の登録やファイル変更が現れれば停止します。
- 退避先は検証一式の `reference-private/` 内です。Downloads は使いません。
- 合成音声の保存用コピーを読み取り専用ディスクイメージにし、復元を検証して取り外してから削除を測定します。同じ物理ディスク上の模擬保管であり、実ライブラリ用の独立したバックアップを検証したことにはなりません。元の合成ファイルも検証一式に残します。
- GUI が空であることと表示順は、本人が見て報告します。GUI 判定の自動化を測定したとは扱いません。
- Music の内部データベース、Mac の時計、同期設定、既存のライブラリを変更する処理はありません。途中停止後の自動復旧や自動後片付けも行いません。

## Step 1: Transfer the Prepared Bundle

まだ普段のユーザーのままで、ターミナルに次を 1 行ずつ貼り付けます。準備済みの合成データとプログラムだけを、ユーザー間で受け渡す場所へコピーします。

```sh
cd ~/ilibrary
test ! -e /Users/Shared/ilibrary-m10.zip && cp -n artifacts/m10-preparation/ilibrary-m10.zip /Users/Shared/ilibrary-m10.zip
```

同名の ZIP が既にある場合は上書きしません。そのときは既存ファイルを削除せず報告してください。GitHub から取得する手順ではありません。今回のブランチはまだ push していません。

## Step 2: Select a Separate User

**Apple Account にサインインしていない既存の `ilibrarytest` ユーザーがあれば再利用できます。** 今回はその中で新しい Music ライブラリを作り、前回のライブラリを保存します。

新しいユーザーが必要なら、普段のユーザーの「システム設定」→「ユーザとグループ」→「ユーザを追加」で「通常」のユーザーを作り、アカウント名を `ilibrarytest3` などにします。測定用の名前は `ilibrarytest` または `ilibrary-test` で始まる必要があります。

普段のユーザーからログアウトし、検証用ユーザーでログインします。Apple Account の設定はスキップします。音楽ファイルや普段のライブラリは持ち込みません。

検証用ユーザーのターミナルで実行します。

```sh
cd ~
test ! -e ilibrary-m10 && unzip -q /Users/Shared/ilibrary-m10.zip
cd ~/ilibrary-m10
python3 rebuild_probe.py verify .
```

最後に `PASS: bundle verification; Music not accessed` と出れば、ファイルが揃っています。Python の利用に開発用ツールの案内が出た場合は、案内に従ってから同じ確認を行います。エラーが出た場合は実行を続けません。

## Step 3: Create an Empty Library for the Small Case

1. 検証用ユーザーで Music が動いていれば終了します。
2. Option キーを押したまま Music を開き、ライブラリ選択画面で新しいライブラリを作ります。
3. 検証用ユーザーの「ミュージック」フォルダ内へ `M10-small` という専用フォルダを作り、その中に保存します。以前のライブラリは削除しません。
4. Music の設定で、メディアフォルダがこの検証用ユーザーの「ミュージック」フォルダ内にあることを確認します。今回専用の場所にします。ほかのユーザーの場所や共有フォルダは選びません。
5. Apple Account に未サインインで、ライブラリ同期を使用していないことを確認します。「曲」と「最近追加した項目」が空であることを確認します。

最初の画面でサインインやサブスクリプションを求められても進めません。既存の曲が見える場合はその場で止めます。

ライブラリを作成・切り替える方法は [Apple の案内](https://support.apple.com/guide/music/use-multiple-libraries-mus7663a920a/mac)に沿っています。ライブラリごとに固有の名前とメディアフォルダを使います。

## Step 4: Run the Small Case

まず、予定の表示だけを行います。Music の登録はまだ読みません。

```sh
cd ~/ilibrary-m10
python3 rebuild_probe.py run --case small --dry-run
```

次に実際の合成測定を開始します。

```sh
python3 rebuild_probe.py run --case small
```

1. 検証用ユーザー・未サインイン・同期なし・空の新ライブラリを確認し、`TEST` と入力して Return を押します。
2. ターミナルによる Music 操作の許可が表示されたら許可します。拒否した場合は停止結果を報告してください。
3. 合成音声 6 曲が追加されます。保存用コピーの検証後にファイルを退避し、登録が 1 件ずつ削除されます。
4. `EMPTY` を求められたら Music を見ます。「曲」と「最近追加した項目」の両方が空になってから、ターミナルに `EMPTY` と入力します。空にならない場合は入力せず、状況を報告してください。
5. スクリプトが Music を終了し、合成曲の作曲者を変更してから、発売日順に再登録します。途中で自分で Music を起動したり、ファイルを移したりしません。
6. 「最近追加した項目」で、先頭（新しく追加された側）から **M10 Album 03 → 02 → 01** になっているか確認します。合っていれば `EXPECTED`、違えば `DIFFERENT`、表示されず判断できなければ `UNKNOWN` と入力します。
7. 結果は `~/ilibrary-m10/reference-private/small/ilibrary-m10-results.txt` に保存されます。追加日時の不一致も測定結果です。`FAIL` を成功として読み替えません。

`STOP` が出た場合は再実行せず、ファイルとユーザーを残して報告します。ライブラリを自分で空にしてやり直す必要はありません。

## Step 5: Run the Scale Case

小規模ケースが最後まで進み、`STOP` がなかった場合だけ行います。日時や表示順の `FAIL` はそのまま残し、規模による違いを測定します。

Music を終了し、Step 3 と同じ方法で、別の空のライブラリを「ミュージック」内の `M10-scale` フォルダに作成します。メディアフォルダもこのケース専用にします。小規模ケースのライブラリやファイルは削除しません。

```sh
cd ~/ilibrary-m10
python3 rebuild_probe.py run --case scale --dry-run
python3 rebuild_probe.py run --case scale
```

操作は小規模ケースと同じです。今回は 300 曲、20 アルバムなので時間がかかります。表示順は、先頭から **M10 Album 20 → 19 → … → 01** を確認します。見えている範囲だけで成功と判断せず、全体を確認できなければ `UNKNOWN` にします。

結果は `~/ilibrary-m10/reference-private/scale/ilibrary-m10-results.txt` に保存されます。

## Step 6: Report the Results

検証用ユーザーで次を実行し、表示された結果をこの会話へ貼り付けてください。ユーザー名・個人パス・曲の ID は含まれません。

```sh
cat ~/ilibrary-m10/reference-private/small/ilibrary-m10-results.txt
cat ~/ilibrary-m10/reference-private/scale/ilibrary-m10-results.txt
```

片方しか実行できなかった場合は、その結果だけで構いません。結果ファイルがない場合は次の形式で報告してください。

```text
M10 の測定が止まりました。
ケース：small / scale / 開始前
止まった手順：Step の番号
最後の STOP 表示：ここに貼り付け
Music 操作の許可：許可した / 拒否した / 表示されなかった
GUI が空になったか：はい / いいえ / 未実施
```

`commands.log`、`failure.txt`、JSON、ディスクイメージ、合成ファイルは貼り付けません。報告が済んだら検証用ユーザーからログアウトして普段のユーザーへ戻れます。結果確認が終わるまで、検証一式とライブラリを残します。

## Preparation and Evidence Limits

開発側の準備コマンドは `sh scripts/validation/prepare-rebuild-probe.sh --prepare` です。`--dry-run` は予定だけを表示します。準備は通常のユーザーで実行できますが、Music の操作は行いません。

ガード試験は `python3 -m unittest discover -s scripts/validation -p 'test_rebuild_probe.py'` で行います。登録削除の代わりに模擬処理を使用します。準備・ガード試験の成功を、実際の Music の削除、GUI、ディスクイメージの復元、同一追加日時の成功として報告しません。

GUI の目視確認と、スクリプトから取得した件数・日時の測定を区別します。この合成測定は実ライブラリへの許可を意味せず、読み取り専用イメージも独立した物理媒体のバックアップの代用にはなりません。

## Recommended Models and Effort

結果の評価と必要な修正は、Claude Code：Claude Opus 5.5／xhigh、Codex：GPT-6-Astra／xhigh を推奨します。登録削除とファイル保全を検証するため、M5 と同じエフォートです。
