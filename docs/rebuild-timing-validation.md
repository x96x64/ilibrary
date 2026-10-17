# Rebuilding Addition Timing Validation

## Scope and Stop Boundary

**これは修正版v2の手順です。** 前回の一式`ilibrary-m10-timing`は、追加の前に、Musicが新しいメディアフォルダに自動で作る設定ファイル1件と言語ファイル88件を「想定外のファイル」として止まりました。音声ファイルはありませんでした。v2は、観測したこの3種類（Finderの`.DS_Store`、メディアフォルダ直下の`.Media Preferences.plist`、決まった2か所の`.localized`内の言語ファイル）だけを、名前・種類・大きさで受け入れます。中身は読みません。それ以外の項目があれば、最初の項目の名前を記録して、追加の前に止まります。詳細は[メディア一覧の評価と修正](reports/timing-media-scaffolding.md)にあります。

前回の一式、`M10-timing-small`ライブラリ、停止記録、一覧の報告は、すべてそのまま残します。前回の一式は再実行しません。

新しい空のライブラリに、合成3アルバム・6曲を追加する比較です。**既存のsmall・scale・displayのライブラリ、結果、保存用コピーは残します。今回、曲の登録削除は一切行いません。** 普段のユーザーと実ライブラリでは実行しません。エージェントは一式の準備・確認・共有場所への転送までで止まります。

前回は追加順01→02→03に対し、画面が02→03→01でした。今回は同じ合成アルバムを新しい空のライブラリで使い、アルバムごとに追加を区切ります。前の追加確認後に少なくとも2秒待ち、次のアルバムの全曲の追加日時が、前までの全曲より後になったかをMusicから読み取って確かめます。重なりや逆転があれば、次のアルバムを追加せず停止し、追加済みの曲も残します。待機中の確認が30秒を超えた場合も、確認処理が戻った時点で止めます。Musicなどへの呼び出しには別のタイムアウトがあります。

**2秒待てば成功するという意味ではありません。** 実際の時刻と画面で判定するための候補です。成功しても、この小さな比較だけでM10全体は完了しません。300曲、ほかの順序、製品での待機方式などは次の評価に残ります。

質問は最初の`TEST`と、表示順の確認2回です。空の確認は最初の`TEST`に含めます。削除しないので、途中に`EMPTY`の質問はありません。

## Step 1: Open the New Bundle in the Test User

1. 作業中の文書を保存し、普段のユーザーからログアウトします。
2. 前回の **`ilibrarytest`** など、既存の検証用ユーザーでログインします。新しいユーザーは不要です。Apple Accountにはサインインしません。
3. Terminalを開き、次をまとめて実行します。ZIPを照合して新しいフォルダに展開するだけで、Musicは操作しません。

```sh
cd /Users/Shared &&
shasum -a 256 -c ilibrary-m10-timing-v2.zip.sha256 &&
cd ~ &&
test ! -e ilibrary-m10-timing-v2 &&
unzip -q /Users/Shared/ilibrary-m10-timing-v2.zip &&
cd ~/ilibrary-m10-timing-v2 &&
python3 timing_probe.py verify .
```

最後に`PASS: 検証一式の照合。Music未操作。`が出れば次へ進みます。既に同名のフォルダがある場合やエラーの場合は、削除・上書きせず、その表示を報告してください。

手順を別ユーザーでも開けます。

```sh
open -a TextEdit ~/ilibrary-m10-timing-v2/PROCEDURE.md
```

## Step 2: Create One Empty Test Library

1. 検証用ユーザーでMusicを終了します。
2. **Optionキーを押したままMusicを開き、「ライブラリを作成」**を選びます。
3. 保存先をホームの「ミュージック」にし、名前を **`M10-timing-v2-small`** にして作成します。前回の`M10-timing-small`は選ばず、そのまま残します。同名のライブラリがあれば、上書きせず停止します。以前のライブラリを選んだり空にしたりしません。
4. Musicの「設定」→「ファイル」で、メディアの場所を **`~/Music/M10-timing-v2-small/Media`** にします。この新しいライブラリ直下の`Media.localized`でも構いません。既にその場所なら変更しません。必要な場合だけ、この新しいライブラリ内に空の`Media`フォルダを作って選びます。以前のフォルダを移動・変更しません。
5. この新しいライブラリで、メディアフォルダの整理と、追加時にメディアフォルダへコピーする設定をオンにします。
6. 未サインイン・同期なしを確認し、「曲」と「最近追加した項目」が空であることを確認します。Musicは開いたままにします。

ライブラリの作成は[Appleの複数ライブラリの案内](https://support.apple.com/guide/music/use-multiple-libraries-mus7663a920a/mac)、メディアの場所は[ファイル設定の案内](https://support.apple.com/guide/music/files-settings-mus0f5accea/mac)に基づきます。

## Step 3: Run the Single Comparison

まず予定を確認します。Musicへのアクセスやファイル作成は行いません。

```sh
cd ~/ilibrary-m10-timing-v2 &&
python3 timing_probe.py run --dry-run
```

停止表示がなければ、次を一度だけ実行します。

```sh
python3 timing_probe.py run
```

| 表示された質問 | 回答 |
| --- | --- |
| 最初の`TEST` | 検証用ユーザー・未サインイン・同期なし・新しい空のライブラリを確認し、`TEST`と入力します。TerminalからMusicへの操作許可が出たら許可します |
| 表示順の`1 / 2 / 3` | Musicの「最近追加した項目」を開き、先頭から左→右、次の行へ見ます。**03→02→01なら1**、違えば2、判断できなければ3を入力します |
| `2`を選んだ後の番号入力 | 実際の順を`02 03 01`のように空白区切りで入力します。抜け・重複も見たまま入力します。番号で表せなければ`UNKNOWN`です |

スクリプトが保存用コピーの作成・復元確認、Music終了中のタグ編集、再起動、アルバムごとの待機と追加を行います。自分でファイルを移動したり、Musicを起動・終了したりせず、質問が出るまで待ちます。

表示が読み込まれてから、合成アルバムが3枚ともあるか、順序が合うかを回答してください。分裂・重複・欠けも不一致です。最初の回答後、スクリプトがMusicを再起動し、**もう一度同じ画面の順序を尋ねます**。その後、完了済みの追加を再実行しても変化しないことと、保存用コピーを確認します。

最後の`case result:`とTerminalの入力待ちが戻れば終了です。`PASS`は今回の小さな比較の成功、`FAIL`は表示不一致、`UNVERIFIED`は表示未確認、`STOP`は途中停止です。どの結果でも次の報告へ進み、同じ検証は再実行しません。途中で止める必要があればControl-Cを押し、入力待ちに戻ってから報告します。

## Step 4: Return One Report

成功・不一致・途中停止のどの場合も、検証用ユーザーで次を一度実行します。以前の結果の要約と今回の結果を、一つの新しい報告にまとめます。Musicは操作しません。

```sh
cd ~/ilibrary-m10-timing-v2 &&
python3 timing_probe.py report --output /Users/Shared/ilibrary-m10-timing-v2-report.txt
```

`PASS: 共有報告を保存・照合しました。`が出たら完了です。報告先が既にあれば上書きせず止まります。報告自体が止まった場合は、最後の表示をそのまま伝えてください。検証用ユーザーのフォルダを丸ごと共有する必要はありません。

普段のユーザーに戻り、次の一文だけを送ってください。

> M10追加日時分離v2の結果を評価してください：`/Users/Shared/ilibrary-m10-timing-v2-report.txt`

合成曲、Musicライブラリ、旧一式、新一式、保存用コピー、途中記録はすべて残します。こちらで評価する前に手動の削除や再追加をしないでください。

## Evidence Limits and Preparation

前回の表示不一致と、前回の日時比較の停止は、それぞれの報告のコミットとSHA-256を添えた履歴として記載します。今回そのライブラリを読み直すことはありません。個人のパスや登録IDを含む詳細ログは新一式内の`reference-private/`に保持し、共有報告は合成アルバムの番号、時刻、判定を中心とした要約です。

同じディスクの保存用イメージは保全の模擬試験であり、別の物理媒体の検証にはなりません。画面は本人の観察で、自動GUI判定ではありません。今回の方法は検証スクリプトだけのものです。公開済みの`ilibrary add`や、まだ未実装の`rebuild`に待機機能を追加しません。

準備担当は`sh scripts/validation/prepare-timing-probe.sh --prepare`を使います。`--dry-run`は作成しません。試験は`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/validation -p 'test_*probe.py'`です。共有場所には新しいZIPと照合用ファイルだけを上書きせず転送し、コピーの一致を確かめます。

## Recommended Models and Effort

次の結果評価の推奨は、Claude Code: **Claude Opus 5.5／xhigh**、Codex: **GPT-6-Astra／xhigh**です。
