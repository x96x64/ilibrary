# Rebuilding Display-Order Validation

## Scope and Stop Boundary

**メディアフォルダ名の判定を修正した一式です。** 停止時の記録では、smallの保存先は`Media.localized`でした。旧検証が`Media`だけを認めていたことが停止の直接原因です。新しい一式は別名の`ilibrary-m10-display-v2`に展開します。旧`ilibrary-m10-display`と`ilibrary-m10-v2`、停止記録、ライブラリはそのまま残してください。

対象ライブラリの直下にある`Media`と`Media.localized`の両方を認めます。末尾を合わせるためのフォルダ作成・名前変更・曲の移動は不要です。別ライブラリの場所やシンボリックリンクは従来どおり拒否します。既存smallの現在の登録と保存済み記録は、改めて厳密に照合します。

M10の新しい条件は、**追加日時に差があっても、「最近追加した項目」が意図したアルバム順になること**です。画面上の順序をMusicの再起動前後に確認します。日時の差は報告に残しますが、差だけでは不合格にしません。

今回の一式は、既存のsmallの不足分と、新しい合成ライブラリ4つを確認し、**最後に結果を一つにまとめて報告**するためのものです。成功を約束するものではありません。以前の結果とライブラリは残します。

**普段のmacOSユーザーと実ライブラリでは実行しません。** エージェントは一式の準備・合成試験・転送までで止まります。以下のMusic操作は、本人が既存の検証用ユーザーで行います。Apple Accountにサインインせず、同期を使いません。

| ケース | 内容 | 曲数 | 登録削除 |
| --- | --- | --- | --- |
| `small-existing` | 以前のsmallを照合し、表示、再起動後の維持、完了済み追加の再実行、バックアップを確認 | 既存6曲 | 行わない |
| `scale-release` | 発売日の古い順で全工程を確認 | 新しい300曲 | この実行で生成・登録した対象だけ |
| `artist` | アーティスト名・アルバム名の昇順 | 新しい8曲 | 同上 |
| `artist-desc` | アーティスト名・アルバム名の降順 | 新しい8曲 | 同上 |
| `artist-release` | アーティスト名、次に発売日の順 | 新しい8曲 | 同上 |

smallの照合では、以前の実行記録・元ファイルの保存用コピー・現在の登録とファイルを比較します。確認用の独立したコピーだけを新しい一式の中に作り、既存の曲ファイルや旧記録を編集しません。以前の記録と違っていた場合は停止します。smallを自動で作り直したり、登録を削除したりしません。

## Step 1: Switch to the Existing Test User

準備完了の報告で、次の2ファイルが共有場所に転送済みか確認してください。

- `/Users/Shared/ilibrary-m10-display-v2.zip`
- `/Users/Shared/ilibrary-m10-display-v2.zip.sha256`

1. 作業中の文書を保存し、普段のユーザーからログアウトします。
2. 前回使用した **`ilibrarytest`** などの検証用ユーザーでログインします。新しいユーザーは不要です。
3. Apple Accountにはサインインしません。普段の音楽ファイルをコピーする必要もありません。
4. 検証用ユーザーのターミナルを開き、以下を一つのブロックとして実行します。

```sh
cd /Users/Shared &&
shasum -a 256 -c ilibrary-m10-display-v2.zip.sha256 &&
cd ~ &&
test ! -e ilibrary-m10-display-v2 &&
unzip -q /Users/Shared/ilibrary-m10-display-v2.zip &&
cd ~/ilibrary-m10-display-v2 &&
python3 display_probe.py verify .
```

ZIPの`OK`と、最後の`PASS: bundle verification; Music not accessed`を確認します。途中で失敗した場合は上書き・削除せず停止し、最後の表示を報告してください。同名のフォルダが既にある場合、このブロックは先へ進みません。旧`ilibrary-m10-v2`はそのまま残します。

手順は一式の`PROCEDURE.md`にも入っています。確認するには次を実行できます。

```sh
open -a TextEdit ~/ilibrary-m10-display-v2/PROCEDURE.md
```

## Step 2: Select the Existing Small Library

1. 検証用ユーザーでMusicを終了します。
2. **Optionキーを押したままMusicを開き、「ライブラリを選択」を選びます。** このケースでは新規作成しません。
3. ホームの「ミュージック」内にある、以前の **`M10-v2-small`** のライブラリを選びます。フォルダの中にあるMusicライブラリのファイルを選択します。
4. Musicの「設定」→「ファイル」で、メディアの場所が **`~/Music/M10-v2-small/Media`または同じ場所の`Media.localized`** であることを確認します。今回のログの`Media.localized`を変更する必要はありません。これ以外の場所なら、設定を変更して合わせず停止してください。別のライブラリの可能性があります。
5. 「曲」に以前の合成曲6曲があることを確認します。登録の削除や追加はしません。Musicは開いたままにします。

Optionキーによる既存ライブラリの選択と新規作成は[Appleの案内](https://support.apple.com/guide/music/use-multiple-libraries-mus7663a920a/mac)、メディアフォルダの確認は[ファイル設定の案内](https://support.apple.com/guide/music/files-settings-mus0f5accea/mac)に基づきます。

## Step 3: Complete the Small Observations

まず予定を確認します。これはMusicを調べたり変更したりしません。

```sh
cd ~/ilibrary-m10-display-v2 &&
python3 display_probe.py run --case small-existing --dry-run
```

停止表示がなければ、確認を実行します。

```sh
python3 display_probe.py run --case small-existing
```

質問が表示されたときだけ回答します。

| 質問 | 操作・回答 |
| --- | --- |
| 最初の`TEST` | 検証用ユーザー・未サインイン・同期なし・指定のライブラリを確認して`TEST`と入力。TerminalからMusicの操作許可を求められたら許可 |
| 表示順の`1 / 2 / 3` | Musicの「最近追加した項目」を開き、全体を見て、`1`＝期待どおり、`2`＝違う、`3`＝判断できないを選ぶ |
| `2`の後の番号入力 | 実際のAlbum番号を、例えば`02 03 01`のように空白区切りで入力。抜け・重複も見たまま入力。番号で表せなければ`UNKNOWN` |

期待する表示順は **03 → 02 → 01** です。先頭から左→右、次の行へ進みます。アルバムが欠けている、同じアルバムが複数に分かれている、順序が違う場合は`2`です。判定を急がず、表示が読み込まれてから確認してください。

表示順は**2回**質問します。1回目の回答後、スクリプトがMusicを終了して再起動し、同じ順序が保たれているか確認します。実行中に自分でMusicを起動・終了したり、曲を移動・編集・削除したりしないでください。

**smallでは空の確認を尋ねません。** 既存の6曲を保持し、退避と登録削除を繰り返さないためです。この追加観察は、以前の実行時の観察とは区別して記録されます。

## Step 4: Read the Case Result

`PHASE:`は処理中の段階です。最後の`case result:`とターミナルの入力待ちが出れば、そのケースは終了しています。

| 最後の表示 | 次に行うこと |
| --- | --- |
| `PASS` | 次の新しいケースへ進む |
| `FAIL` | 表示の不一致が確認された結果。直そうとせず残し、次の独立したケースへ進む |
| `UNVERIFIED` | 表示を確認しきれなかった結果。成功扱いにせず、次の独立したケースへ進む |
| `STOP`、または最後まで結果が出ない | **同じコマンドを再実行せず、残りのケースも始めず、Step 7で報告する** |

最初のsmallが既存状態との不一致で止まっても、削除して作り直しません。空の確認に答えられない場合や、意図しない画面・エラーが出た場合も、ターミナルでControl-Cを押して止め、Step 7へ進みます。

## Step 5: Measure the New Scale Library

smallが`STOP`なしで終了した場合だけ進みます。

1. Musicを終了します。
2. Optionキーを押したままMusicを開き、今度は **「ライブラリを作成」**を選びます。
3. ホームの「ミュージック」の中に **`M10-display-scale-release`** という名前で新規作成します。同名のライブラリがあれば上書きせず停止します。
4. Musicの「設定」→「ファイル」で、メディアの場所を **`~/Music/M10-display-scale-release/Media`** にします。同じライブラリ直下の`Media.localized`も使用できます。既にその場所なら変更しません。選択画面で対象がまだない場合だけ、新しい`Media`フォルダを作ります。
5. **メディアフォルダの整理**と、**追加時にメディアフォルダへコピー**の設定をオンにします。この専用ライブラリだけの設定です。
6. 未サインイン・同期なし、「曲」と「最近追加した項目」が空であることを確認し、Musicを開いたままにします。
7. 次の予定表示を実行し、停止表示がなければ本測定を実行します。

```sh
cd ~/ilibrary-m10-display-v2 &&
python3 display_probe.py run --case scale-release --dry-run
```

```sh
python3 display_probe.py run --case scale-release
```

最初は`TEST`を尋ねます。合成曲を退避し、登録を削除した後に、**「曲」と「最近追加した項目」が両方空か**を尋ねます。両方空なら`1`、空ではない・判断できない場合は`2`です。`2`では終了とタグ編集へ進まず停止します。質問が来る前に登録を自分で削除しないでください。

空の確認後のMusic終了、作業用コピーのタグ編集、再起動、アルバムごとの追加はスクリプトが行います。300曲のバックアップと削除には時間がかかります。`PHASE:`がしばらく変わらなくても、追加のコマンドを重ねて実行しないでください。

表示順の期待値は **20 → 19 → 18 → … → 03 → 02 → 01** です。スクロールして全20アルバムを確認します。表示順の質問は再起動前後の2回です。回答はStep 3と同じです。

## Step 6: Measure the Other Three Orders

前のケースが`STOP`なしで終了した場合だけ、次の3行を上から順に行います。**各行で、Step 5と同じ方法で別の新しいライブラリを作成**します。以前のライブラリを空にして使い回しません。

| ケース | 新しいライブラリ名 | 専用メディアフォルダ | 期待する表示順 |
| --- | --- | --- | --- |
| `artist` | `M10-display-artist` | `~/Music/M10-display-artist/Media` | 03 → 01 → 04 → 02 |
| `artist-desc` | `M10-display-artist-desc` | `~/Music/M10-display-artist-desc/Media` | 02 → 04 → 01 → 03 |
| `artist-release` | `M10-display-artist-release` | `~/Music/M10-display-artist-release/Media` | 01 → 03 → 02 → 04 |

表の各`Media`は、同じライブラリ直下の`Media.localized`でも構いません。

各ライブラリで、整理・コピーの設定、未サインイン・同期なし、空の画面を確認します。どのケースも4アルバム・8曲です。2人の合成アーティストと異なる発売日を使うので、3種類の並び順を区別できます。

まず`artist`のライブラリを開いて実行します。`&&`により、予定表示が失敗した場合は本測定へ進みません。

```sh
cd ~/ilibrary-m10-display-v2 &&
python3 display_probe.py run --case artist --dry-run &&
python3 display_probe.py run --case artist
```

終了結果を確認し、次に`artist-desc`の新しいライブラリを作って実行します。

```sh
python3 display_probe.py run --case artist-desc --dry-run &&
python3 display_probe.py run --case artist-desc
```

終了結果を確認し、最後に`artist-release`の新しいライブラリを作って実行します。

```sh
python3 display_probe.py run --case artist-release --dry-run &&
python3 display_probe.py run --case artist-release
```

各ケースで`TEST`、空の確認、再登録後の表示順、再起動後の表示順を尋ねます。途中の`STOP`では残りを始めず、次の報告へ進みます。

## Step 7: Return One Report

成功・不一致・未確認・途中停止のどの場合も、最後に**このブロックを一度実行**します。保存した結果をまとめるだけで、Musicにはアクセスしません。

```sh
cd ~/ilibrary-m10-display-v2 &&
mkdir -p reference-private &&
python3 display_probe.py report > reference-private/ilibrary-m10-display-v2-report.txt &&
cat reference-private/ilibrary-m10-display-v2-report.txt
```

**表示された全文を一度、この会話へ貼り付ければ報告は完了です。** 実行しなかったケースも`NOT RUN`と記録されます。ケースごとの結果ファイルを探す必要はありません。報告には、段階・件数・日時の差・期待順と観察順・再起動前後の結果・停止理由が含まれ、個人パスや登録IDは含みません。

ファイルの場所だけを伝えたい場合は、次を続けて実行します。

```sh
cp -n reference-private/ilibrary-m10-display-v2-report.txt /Users/Shared/ilibrary-m10-display-v2-report.txt &&
cmp -s reference-private/ilibrary-m10-display-v2-report.txt /Users/Shared/ilibrary-m10-display-v2-report.txt &&
echo '報告用コピー: OK'
```

`OK`なら普段のユーザーに戻り、次の一文だけをこの会話へ送れます。

> M10表示順検証の結果を評価してください：`/Users/Shared/ilibrary-m10-display-v2-report.txt`

`OK`が出なければ上書きせず、先ほどの全文を貼り付けます。`diagnostics.jsonl`、登録のJSON、音声、ディスクイメージは送らず、検証用ユーザー内の`reference-private/`に保持してください。

展開や一式の検証の段階で止まり、まだ報告を作れない場合は、そのStep番号と最後の表示を送ってください。結果待ちの間、新旧の一式・ライブラリ・バックアップを削除しません。

## Evidence Limits and Preparation

画面の空き状態と表示順は本人による観察です。GUIの自動判定を実装・検証したことにはなりません。同じ物理ディスク上の読み取り専用イメージは合成検証用であり、実データの別媒体バックアップの代わりにはなりません。

日時が同じ秒になったアルバム間と、日時が異なる場合の両方が観測されたかも報告します。観測できなかった条件は未確認とし、意図しない表示順、追加しただけの順序記録、未実行を成功に置き換えません。全体の結果が揃うまでM10合格とは扱いません。

準備担当は`sh scripts/validation/prepare-display-probe.sh --prepare`で新しい一式を作ります。予定表示は`--dry-run`、試験は`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/validation -p 'test_*probe.py'`です。完成したZIPと照合用ファイルを`/Users/Shared/`へ上書きせず転送し、コピーの一致を確認してから本人へ案内します。

## Recommended Models and Effort

結果評価と必要な修正は、Claude Code：Claude Opus 5.5／xhigh、Codex：GPT-6-Astra／xhighを推奨します。
