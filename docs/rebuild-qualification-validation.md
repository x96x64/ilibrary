# Separated Addition Qualification

## Scope and Stop Boundary

決定36により、アルバムごとに追加時刻を分ける方法をM10の候補方式として採用しました。この手順は、その方式で**残りの4ケース**を確認するためのものです。日時比較v2のsmallは登録削除を含まない3アルバムの成功でした。今回は、新しい空の合成ライブラリごとに、追加・保存用コピー・退避・この実行で登録した曲だけの削除・空の画面の確認・終了中の編集・アルバムごとの再追加・表示順・再起動・再実行の全工程を行います。

| ケース | 内容 | 曲数 | 新しいライブラリ名 | 期待する表示順 |
| --- | --- | --- | --- | --- |
| `scale-release` | 発売日の古い順 | 20アルバム・300曲 | `M10-separated-scale-release` | 20 → 19 → … → 02 → 01 |
| `artist` | アーティスト名・アルバム名の昇順 | 4アルバム・8曲 | `M10-separated-artist` | 03 → 01 → 04 → 02 |
| `artist-desc` | アーティスト名・アルバム名の降順 | 4アルバム・8曲 | `M10-separated-artist-desc` | 02 → 04 → 01 → 03 |
| `artist-release` | アーティスト名、次に発売日の順 | 4アルバム・8曲 | `M10-separated-artist-release` | 01 → 03 → 02 → 04 |

再追加では、1回の`ilibrary add`に1アルバムだけを渡します。前のアルバムの登録を確認してから少なくとも2秒待ち、次のアルバムの全曲の追加日時が、それまでの全曲より後であることをMusicから読み取って確かめます。**アルバム間で同じ秒になった場合は対応範囲外として、次のアルバムを追加せずに停止します。** 追加済みの曲は残します。同じアルバム内で同じ秒になるのは問題ありません。待機の前後の確認が合計120秒を超えた場合も止まります。

**2秒待てば成功するという意味ではありません。** 実際の時刻と画面で判定します。全ケースが成功しても、それだけでM10の完了を宣言するものではありません。自動の空画面判定と、別の物理媒体へのバックアップは未検証のまま残ります。

**普段のmacOSユーザーと実ライブラリでは実行しません。** エージェントは一式の準備・試験・共有場所への転送までで止まります。以下のMusic操作は、本人が既存の検証用ユーザーで行います。Apple Accountにはサインインせず、同期も使いません。旧一式（`ilibrary-m10-timing-v2`、`ilibrary-m10-display-v3`など）、すべてのライブラリ、保存用コピー、記録はそのまま残し、再実行しません。

## Step 1: Open the New Bundle in the Test User

準備完了の報告で、次の2ファイルが共有場所に転送済みか確認してください。

- `/Users/Shared/ilibrary-m10-qualification.zip`
- `/Users/Shared/ilibrary-m10-qualification.zip.sha256`

1. 作業中の文書を保存し、普段のユーザーからログアウトします。
2. 前回の **`ilibrarytest`** など、既存の検証用ユーザーでログインします。新しいユーザーは不要です。
3. Terminalを開き、次をまとめて実行します。ZIPを照合して新しいフォルダに展開するだけで、Musicは操作しません。

```sh
cd /Users/Shared &&
shasum -a 256 -c ilibrary-m10-qualification.zip.sha256 &&
cd ~ &&
test ! -e ilibrary-m10-qualification &&
unzip -q /Users/Shared/ilibrary-m10-qualification.zip &&
cd ~/ilibrary-m10-qualification &&
python3 qualification_probe.py verify .
```

最後に`PASS: 検証一式の照合。Music未操作。`が出れば次へ進みます。同名のフォルダがある場合やエラーの場合は、削除・上書きせず、その表示を報告してください。

手順は一式の`PROCEDURE.md`にも入っています。

```sh
open -a TextEdit ~/ilibrary-m10-qualification/PROCEDURE.md
```

## Step 2: Create a New Library for Each Case

各ケースの前に、表のライブラリ名で**新しいライブラリを1つ作成**します。以前のライブラリを空にして使い回しません。

1. 検証用ユーザーでMusicを終了します。
2. **Optionキーを押したままMusicを開き、「ライブラリを作成」**を選びます。
3. 保存先をホームの「ミュージック」にし、表の名前（最初は **`M10-separated-scale-release`**）で作成します。同名のライブラリがあれば、上書きせず停止します。
4. Musicの「設定」→「ファイル」で、メディアの場所がこの新しいライブラリ直下の`Media`または`Media.localized`であることを確認します。既にその場所なら変更しません。必要な場合だけ、この新しいライブラリ内に空の`Media`フォルダを作って選びます。以前のフォルダを移動・変更しません。
5. この新しいライブラリで、**メディアフォルダの整理**と、**追加時にメディアフォルダへコピー**の設定をオンにします。
6. 未サインイン・同期なしを確認し、「曲」と「最近追加した項目」が空であることを確認します。Musicは開いたままにします。

ライブラリの作成は[Appleの複数ライブラリの案内](https://support.apple.com/guide/music/use-multiple-libraries-mus7663a920a/mac)、メディアの場所は[ファイル設定の案内](https://support.apple.com/guide/music/files-settings-mus0f5accea/mac)に基づきます。

## Step 3: Run the Scale Case

まず予定を確認し、停止表示がなければ本測定を一度だけ実行します。`&&`により、予定表示が失敗した場合は本測定へ進みません。

```sh
cd ~/ilibrary-m10-qualification &&
python3 qualification_probe.py run --case scale-release --dry-run &&
python3 qualification_probe.py run --case scale-release
```

| 表示された質問 | 回答 |
| --- | --- |
| 最初の`TEST` | 検証用ユーザー・未サインイン・同期なし・新しい空のライブラリを確認し、`TEST`と入力します。TerminalからMusicへの操作許可が出たら許可します |
| 空の確認`1 / 2` | 登録削除の後に尋ねます。「曲」と「最近追加した項目」が**両方空なら1**、空ではない・判断できない場合は2です。2では終了と編集へ進まず停止します |
| 表示順の`1 / 2 / 3` | 「最近追加した項目」を開き、先頭から左→右、次の行へ、スクロールして最後まで見ます。**期待どおりなら1**、違えば2、判断できなければ3です |
| `2`を選んだ後の番号入力 | 実際のAlbum番号を`02 03 01`のように空白区切りで入力します。抜け・重複も見たまま入力します。番号で表せなければ`UNKNOWN`です |

スクリプトが合成曲の追加、保存用コピーの作成と復元確認、退避、この実行で登録した曲だけの削除（1曲ずつ）、Musicの終了、作業用ファイルの編集、再起動、アルバムごとの待機と再追加を行います。自分でファイルを移動したり、曲を削除・追加したり、Musicを起動・終了したりせず、質問が出るまで待ちます。300曲の削除と20回の再追加には時間がかかります。`PHASE:`がしばらく変わらなくても、コマンドを重ねて実行しないでください。

表示順は再起動の前後に**2回**尋ねます。アルバムが欠けている、同じアルバムが複数に分かれている、順序が違う場合は`2`です。表示が読み込まれてから確認してください。

## Step 4: Read the Case Result

最後の`case result:`とTerminalの入力待ちが戻れば、そのケースは終了しています。

| 最後の表示 | 次に行うこと |
| --- | --- |
| `PASS` | 次のケースへ進む |
| `FAIL` | 表示の不一致が確認された結果。直そうとせず残し、次の独立したケースへ進む |
| `UNVERIFIED` | 表示を確認しきれなかった結果。成功扱いにせず、次の独立したケースへ進む |
| `STOP`、または最後まで結果が出ない | **同じコマンドを再実行せず、残りのケースも始めず、Step 6で報告する** |

途中で止める必要があればControl-Cを押し、入力待ちに戻ってからStep 6へ進みます。

## Step 5: Run the Three Artist Orders

前のケースが`STOP`なしで終了した場合だけ、次の3つを上から順に行います。**各ケースの前にStep 2で、表の名前の新しいライブラリを作成**します。

```sh
cd ~/ilibrary-m10-qualification &&
python3 qualification_probe.py run --case artist --dry-run &&
python3 qualification_probe.py run --case artist
```

結果を確認し、`M10-separated-artist-desc`を作成してから実行します。

```sh
python3 qualification_probe.py run --case artist-desc --dry-run &&
python3 qualification_probe.py run --case artist-desc
```

結果を確認し、`M10-separated-artist-release`を作成してから実行します。

```sh
python3 qualification_probe.py run --case artist-release --dry-run &&
python3 qualification_probe.py run --case artist-release
```

どのケースも4アルバム・8曲です。2人の合成アーティストと異なる発売日を使うので、3種類の並び順を区別できます。質問と回答はStep 3と同じです。途中の`STOP`では残りを始めず、次の報告へ進みます。

## Step 6: Return One Report

成功・不一致・未確認・途中停止のどの場合も、最後に検証用ユーザーで次を一度実行します。保存した結果を一つの新しい報告にまとめるだけで、Musicにはアクセスしません。実行しなかったケースは`NOT RUN`と記録されます。

```sh
cd ~/ilibrary-m10-qualification &&
python3 qualification_probe.py report --output /Users/Shared/ilibrary-m10-qualification-report.txt
```

`PASS: 共有報告を保存・照合しました。`が出たら完了です。報告先が既にあれば上書きせず止まります。報告自体が止まった場合は、最後の表示をそのまま伝えてください。

普段のユーザーに戻り、次の一文だけを送ってください。

> M10分離追加の検証結果を評価してください：`/Users/Shared/ilibrary-m10-qualification-report.txt`

`diagnostics.jsonl`、登録のJSON、音声、ディスクイメージは送らず、検証用ユーザー内の`reference-private/`に保持してください。展開や一式の検証の段階で止まり、まだ報告を作れない場合は、そのStep番号と最後の表示を送ってください。評価の前に、新旧の一式・ライブラリ・バックアップを削除したり、手動で再追加したりしないでください。

## Evidence Limits and Preparation

報告には、段階、件数、アルバムごとの追加日時の境界と待機時間、日時の差、期待順と観察順、再起動前後の結果、停止理由が含まれ、個人パスや登録IDは含みません。display-v3の不一致と日時比較v2の成功は、それぞれのコミットとSHA-256を添えた履歴として記載し、そのライブラリを読み直すことはありません。

画面の空き状態と表示順は本人による観察で、GUIの自動判定ではありません。同じ物理ディスク上の読み取り専用イメージは合成検証用の模擬であり、実データの別媒体バックアップの代わりにはなりません。今回の待機と日時確認は検証スクリプトだけのもので、公開済みの`ilibrary add`や、まだ未実装の`rebuild`には追加しません。固定の待機時間は適格としません。

準備担当は`sh scripts/validation/prepare-qualification-probe.sh --prepare`を使います。`--dry-run`は作成しません。試験は`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/validation -p 'test_*probe.py'`です。共有場所には新しいZIPと照合用ファイルだけを上書きせず転送し、コピーの一致を確かめます。

## Recommended Models and Effort

結果評価と必要な修正は、Claude Code：Claude Opus 5.5／xhigh、Codex：GPT-6-Astra／xhighを推奨します。
