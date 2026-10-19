# Separated Addition Qualification, Version 2

## Scope and Stop Boundary

決定36により、アルバムごとに追加時刻を分ける方法をM10の候補方式として採用しました。この手順は、その方式の**4ケースを新しい一式（バージョン2）でやり直す**ためのものです。初回の実行（`docs/rebuild-qualification-validation.md`の手順）では`scale-release`が登録削除の途中で中断され、`artist`系の3ケースは実行されませんでした。バージョン2では、登録削除の前後の確認に使う登録の取得を、1曲ずつの取得から一括取得へ置き換えています。置き換えは、削除前に両者の結果が一致することを確かめた場合だけ有効になります。

| ケース | 内容 | 曲数 | 新しいライブラリ名 | 期待する表示順 |
| --- | --- | --- | --- | --- |
| `scale-release` | 発売日の古い順 | 20アルバム・300曲 | `M10-separated-v2-scale-release` | 20 → 19 → … → 02 → 01 |
| `artist` | アーティスト名・アルバム名の昇順 | 4アルバム・8曲 | `M10-separated-v2-artist` | 03 → 01 → 04 → 02 |
| `artist-desc` | アーティスト名・アルバム名の降順 | 4アルバム・8曲 | `M10-separated-v2-artist-desc` | 02 → 04 → 01 → 03 |
| `artist-release` | アーティスト名、次に発売日の順 | 4アルバム・8曲 | `M10-separated-v2-artist-release` | 01 → 03 → 02 → 04 |

**初回の実行のライブラリ`M10-separated-scale-release`、その一式（`ilibrary-m10-qualification`）、記録、報告は保存されています。開かず、操作せず、再実行も継続もしません。** バージョン2の各ケースは、上の表の名前の**新しいライブラリ**だけを使います。一式の`manifest.json`にはソースのコミットが記録されており、報告の先頭の行にも同じコミットが繰り返されます。報告を受け取った側は、これで一式と報告の対応を確認します。

再追加では、1回の`ilibrary add`に1アルバムだけを渡します。前のアルバムの登録を確認してから少なくとも2秒待ち、次のアルバムの全曲の追加日時が、それまでの全曲より後であることをMusicから読み取って確かめます。**アルバム間で同じ秒になった場合は対応範囲外として、次のアルバムを追加せずに停止します。** 追加済みの曲は残します。同じアルバム内で同じ秒になるのは問題ありません。待機の前後の確認が合計120秒を超えた場合も止まります。

**2秒待てば成功するという意味ではありません。** 実際の時刻と画面で判定します。全ケースが成功しても、それだけでM10の完了を宣言するものではありません。自動の空画面判定と、別の物理媒体へのバックアップは未検証のまま残ります。

**一括取得による実機での性能改善は、まだ測定されていません。** 合成のスタブで、Apple Eventsを使わずに測った1件あたり約14ミリ秒という値は、Musicでの性能を予測するものではありません。実機の値は、この実行の記録だけが示します。

**普段のmacOSユーザーと実ライブラリでは実行しません。** エージェントは一式の準備・試験・共有場所への転送までで止まります。以下のMusic操作は、本人が既存の検証用ユーザーで行います。Apple Accountにはサインインせず、同期も使いません。旧一式（`ilibrary-m10-qualification`、`ilibrary-m10-timing-v2`、`ilibrary-m10-display-v3`など）、すべてのライブラリ、保存用コピー、記録はそのまま残します。

## Step 1: Verify and Open the New Bundle in the Test User

準備完了の報告で、次の2ファイルが共有場所に転送済みか確認してください。

- `/Users/Shared/ilibrary-m10-qualification-v2.zip`
- `/Users/Shared/ilibrary-m10-qualification-v2.zip.sha256`

1. 作業中の文書を保存し、普段のユーザーからログアウトします。
2. 前回の **`ilibrarytest`** など、既存の検証用ユーザーでログインします。新しいユーザーは不要です。このユーザーはApple Accountにサインインしておらず、同期も使いません。
3. Terminalを開き、次をまとめて実行します。**展開の前に、SHA-256を照合します。** 照合に成功した場合だけ新しいフォルダに展開します。Musicは操作しません。

```sh
cd /Users/Shared &&
shasum -a 256 -c ilibrary-m10-qualification-v2.zip.sha256 &&
cd ~ &&
test ! -e ilibrary-m10-qualification-v2 &&
unzip -q /Users/Shared/ilibrary-m10-qualification-v2.zip &&
cd ~/ilibrary-m10-qualification-v2 &&
python3 qualification_probe.py verify .
```

最後に`PASS: 検証一式の照合。Music未操作。`が出れば次へ進みます。照合が失敗した場合、同名のフォルダがある場合、エラーの場合は、展開・削除・上書きをせず、その表示を報告してください。

手順は一式の`PROCEDURE.md`にも入っています。

```sh
open -a TextEdit ~/ilibrary-m10-qualification-v2/PROCEDURE.md
```

## Step 2: Create a New Library for Each Case

各ケースの前に、表のライブラリ名で**新しい空のライブラリを1つ作成**します。以前のライブラリ（初回の`M10-separated-scale-release`を含む）を空にして使い回したり、開いて操作したりしません。

1. 検証用ユーザーでMusicを終了します。
2. **Optionキーを押したままMusicを開き、「ライブラリを作成」**を選びます。
3. 保存先をホームの「ミュージック」にし、表の名前（最初は **`M10-separated-v2-scale-release`**）で作成します。同名のライブラリがあれば、上書きせず停止します。
4. Musicの「設定」→「ファイル」で、メディアの場所がこの新しいライブラリ直下の`Media`または`Media.localized`であることを確認します。既にその場所なら変更しません。必要な場合だけ、この新しいライブラリ内に空の`Media`フォルダを作って選びます。以前のフォルダを移動・変更しません。
5. この新しいライブラリで、**メディアフォルダの整理**と、**追加時にメディアフォルダへコピー**の設定をオンにします。
6. 未サインイン・同期なしを確認し、「曲」と「最近追加した項目」が空であることを確認します。Musicは開いたままにします。

ライブラリの作成は[Appleの複数ライブラリの案内](https://support.apple.com/guide/music/use-multiple-libraries-mus7663a920a/mac)、メディアの場所は[ファイル設定の案内](https://support.apple.com/guide/music/files-settings-mus0f5accea/mac)に基づきます。

## Step 3: Run the Scale Case

まず予定を確認し、停止表示がなければ本測定を一度だけ実行します。`&&`により、予定表示が失敗した場合は本測定へ進みません。

```sh
cd ~/ilibrary-m10-qualification-v2 &&
python3 qualification_probe.py run --case scale-release --dry-run &&
python3 qualification_probe.py run --case scale-release
```

| 表示された質問 | 回答 |
| --- | --- |
| 最初の`TEST` | 検証用ユーザー・未サインイン・同期なし・新しい空のライブラリを確認し、`TEST`と入力します。TerminalからMusicへの操作許可が出たら許可します |
| 空の確認`1 / 2` | 登録削除の後に尋ねます。「曲」と「最近追加した項目」が**両方空なら1**、空ではない・判断できない場合は2です。2では終了と編集へ進まず停止します |
| 表示順の`1 / 2 / 3` | 「最近追加した項目」を開き、先頭から左→右、次の行へ、スクロールして最後まで見ます。**期待どおりなら1**、違えば2、判断できなければ3です |
| `2`を選んだ後の番号入力 | 実際のAlbum番号を`02 03 01`のように空白区切りで入力します。抜け・重複も見たまま入力します。番号で表せなければ`UNKNOWN`です |

スクリプトが合成曲の追加、取得方法の一致確認、保存用コピーの作成と復元確認、退避、この実行で登録した曲だけの削除（1曲ずつ）、Musicの終了、作業用ファイルの編集、再起動、アルバムごとの待機と再追加を行います。自分でファイルを移動したり、曲を削除・追加したり、Musicを起動・終了したりせず、質問が出るまで待ちます。300曲の削除と20回の再追加には時間がかかります。表示がしばらく変わらなくても、コマンドを重ねて実行しないでください。

表示順は再起動の前後に**2回**尋ねます。アルバムが欠けている、同じアルバムが複数に分かれている、順序が違う場合は`2`です。表示が読み込まれてから確認してください。

### Expected Output

画面には、次の種類の行が順に出ます。同じ内容が一式内の`reference-private/<case>/result.txt`に保存されます。先頭には`iLibrary M10 separated-addition qualification`と`source commit: <コミット>`が出ます。このコミットは`manifest.json`と報告の先頭の行に記録されるものと同じです。

`PHASE:`の行が段階の開始を示します。段階は、`empty-library`、`seed-addition`、`backup`、`evacuation`、`registration-removal`、`empty-gui`、`quit-and-edit`、`separated-readdition`、`display-before-relaunch`、`relaunch`、`display-after-relaunch`、`repeat-and-preservation`、`complete`の順です。段階が終わるたびに`DURATION: phase <名前>; seconds: <秒>`が出ます。

追加の直後（`seed-addition`）に、取得方法の一致確認が行われ、まだ何も退避していない状態で次の行が出ます。`MEASURED: per-track snapshot of <件数> registrations: <秒> seconds`と`MEASURED: bulk snapshot of <件数> registrations: <秒> seconds`が、1曲ずつの取得と一括取得の所要時間です。続く`MEASURED: per-track rows with a legacy location read error (diagnostic only, not compared): <件数> of <総数>`は参考の件数で、比較には使いません。両方の取得が、`id`、`title`、`album`、`artist`、`path`、`path_error`、`added`について（順序によらず）一致した場合だけ、`PASS: bulk snapshot equals the per-track snapshot`が出て、以降の取得が一括取得に切り替わります。**一致しない場合は`STOP: bulk snapshot differs from the per-track snapshot`が出て、何も退避せずに停止します。**

`registration-removal`では、登録を1件削除するたびに次の行が出ます。`PROGRESS: returned removals <完了>/<総数>; remaining <残り>; phase elapsed seconds: <秒>; mean seconds per removal: <秒>`。ここでの「完了」は、Musicが削除の呼び出しに応答を返した件数です。次の取得で削除が確認されるまで、確認済みとは数えません。アルバムの全曲の削除が終わるたびに`CHECKPOINT: album <名前> fully removed; albums <完了>/<総数>; registrations removed <件数>/<総数>`が出ます。最後に`PASS: removed only this run's <件数> inventoried registrations, one persistent ID per call; evacuated files unchanged`が出ます。

`separated-readdition`では、アルバムごとに`WAIT: before album <番号>; observed monotonic seconds: <秒>`と`MEASURED: album <番号>; minimum ...; maximum ...; gap from previous maximum: ...; separated: ...`が出ます。`separated: True`でなければ、そのケースは停止します。

### Performance Figures to Record

性能の記録として、次の4つを報告に残します。値はすべて`result.txt`に含まれ、後述の報告に自動的に入るので、手で書き写す必要はありません。確認のために画面から控える場合は、次を使います。

1. 1曲ずつの取得の所要時間（`MEASURED: per-track snapshot`の行）
2. 一括取得の所要時間（`MEASURED: bulk snapshot`の行）
3. 削除の段階の所要時間（`DURATION: phase registration-removal`の行）
4. 最後の`PROGRESS`の行の`mean seconds per removal`

これらは、このMusicとこの合成ライブラリでの実測値です。ほかの環境や実ライブラリでの性能を示すものではありません。

## Step 4: Read the Case Result

最後の`case result:`とTerminalの入力待ちが戻れば、そのケースは終了しています。

| 最後の表示 | 意味と次に行うこと |
| --- | --- |
| `PASS` | 2回の表示順の確認がどちらも期待どおりで、全工程が完了した。次のケースへ進む |
| `FAIL` | 表示の不一致が確認された結果。直そうとせず残し、次の独立したケースへ進む |
| `UNVERIFIED` | 表示を確認しきれなかった結果。成功扱いにせず、次の独立したケースへ進む |
| `STOP` | 検証側の確認が条件を満たさず、拒否して止まった結果（`STOP:`と`reason:`の行に理由が出る）。**同じコマンドを再実行せず、残りのケースも始めず、Step 6で報告する** |
| `INTERRUPTED` | 本人がControl-Cで中断した結果。`STOP`と同様に**再実行も継続もせず、残りのケースも始めず、Step 6で報告する** |

`STOP`または`INTERRUPTED`のケースの後は、次のケースの実行が拒否されます。結果が出ないまま止まった場合も、同じ扱いにします。

`STOP`と`INTERRUPTED`では、削除の記録として、`removals verified by a later snapshot: <件数>`、`removals returned without verification: <件数>`、`indeterminate removal (intent without returned record): yes/no`が出ます。これらの値は、削除の途中で止まった場合に、どこまで確認済みかを示します。

### Interruption Precautions

登録の削除は、300件で長時間かかります。**削除の最中のControl-Cは、できる限り避けてください。** 削除の呼び出しが途中のまま中断されると、その1件が削除されたかどうかが確認できなくなるおそれがあります。初回の実行は、この段階でKeyboardInterruptにより止まりました。

中断を考えるのは、**`PROGRESS`の行が10分間まったく増えなかった場合だけ**にしてください。10分は保守的な上限です。削除の1回の呼び出しの制限は120秒、一括取得の制限は300秒で、1件の処理には取得、削除、確認が含まれます。これらを合計しても、通常の1件は10分に満たず、外側の呼び出しの制限（600秒）もこの値を超えません。10分何も表示されない場合は、制限を過ぎても進んでいない可能性が高いと判断できます。`PROGRESS`が出ていない段階（追加、退避、再追加など）では、`PHASE:`、`WAIT:`、`MEASURED:`の最後の行からの経過で同様に判断し、質問が出ている間は待ちます。

中断する場合の注意は次のとおりです。

1. Control-Cは**一度だけ**押します。続けて押しません。スクリプトが記録を書き終えて入力待ちに戻るまで待ちます。
2. `STOP`または`INTERRUPTED`の後は、**そのケースを再実行も継続もしません。** 同じライブラリでもう一度`run`を実行しません。
3. Musicの登録を**手動で削除したり、再追加したりしません。** ファイルの移動、ライブラリの整理、Musicの設定変更もしません。残った登録、退避したファイル、保存用コピーはそのままにします。
4. 残りのケースを始めず、**Step 6の報告へ進みます。**

## Step 5: Run the Three Artist Orders

前のケースが`STOP`も`INTERRUPTED`もなく終了した場合だけ、次の3つを上から順に行います。**各ケースの前にStep 2で、表の名前の新しいライブラリを作成**します。

```sh
cd ~/ilibrary-m10-qualification-v2 &&
python3 qualification_probe.py run --case artist --dry-run &&
python3 qualification_probe.py run --case artist
```

結果を確認し、`M10-separated-v2-artist-desc`を作成してから実行します。

```sh
python3 qualification_probe.py run --case artist-desc --dry-run &&
python3 qualification_probe.py run --case artist-desc
```

結果を確認し、`M10-separated-v2-artist-release`を作成してから実行します。

```sh
python3 qualification_probe.py run --case artist-release --dry-run &&
python3 qualification_probe.py run --case artist-release
```

どのケースも4アルバム・8曲です。2人の合成アーティストと異なる発売日を使うので、3種類の並び順を区別できます。質問と回答はStep 3と同じです。途中の`STOP`または`INTERRUPTED`では残りを始めず、次の報告へ進みます。

## Step 6: Return One Report

成功・不一致・未確認・途中停止・中断のどの場合も、最後に検証用ユーザーで次を一度実行します。保存した結果を一つの新しい報告にまとめるだけで、Musicにはアクセスしません。実行しなかったケースは`NOT RUN`と記録されます。

```sh
cd ~/ilibrary-m10-qualification-v2 &&
python3 qualification_probe.py report --output /Users/Shared/ilibrary-m10-qualification-v2-report.txt
```

`PASS: 共有報告を保存・照合しました。`が出たら完了です。報告先が既にあれば上書きせず止まります。報告自体が止まった場合は、最後の表示をそのまま伝えてください。報告の先頭の行は`iLibrary M10 separated-addition qualification report`、2行目は`source commit: <コミット>`で、一式の`manifest.json`と同じコミットです。初回の実行は`first qualification run`として履歴の欄に記載され、そのライブラリを読み直すことはありません。

普段のユーザーに戻り、次の一文だけを送ってください。

> M10分離追加バージョン2の検証結果を評価してください：`/Users/Shared/ilibrary-m10-qualification-v2-report.txt`

`diagnostics.jsonl`、削除の記録、登録のJSON、音声、ディスクイメージは送らず、検証用ユーザー内の`reference-private/`に保持してください。展開や一式の検証の段階で止まり、まだ報告を作れない場合は、そのStep番号と最後の表示を送ってください。評価の前に、新旧の一式・ライブラリ・バックアップを削除したり、手動で再追加したりしないでください。

## Evidence Limits and Preparation

報告には、段階、件数、2種類の取得の所要時間、削除の進行と段階ごとの所要時間、アルバムごとの追加日時の境界と待機時間、日時の差、期待順と観察順、再起動前後の結果、停止理由が含まれ、個人パスや登録IDは含みません。display-v3の不一致、日時比較v2の成功、初回の分離追加の中断は、それぞれのコミットとSHA-256を添えた履歴として記載し、そのライブラリを読み直すことはありません。

画面の空き状態と表示順は本人による観察で、GUIの自動判定ではありません。同じ物理ディスク上の読み取り専用イメージは合成検証用の模擬であり、実データの別媒体バックアップの代わりにはなりません。今回の待機と日時確認、一括取得は検証スクリプトだけのもので、公開済みの`ilibrary add`や、まだ未実装の`rebuild`には追加しません。固定の待機時間は適格としません。一括取得による性能改善は、この実行の前には実機で測定されていません。

準備担当は`sh scripts/validation/prepare-qualification-probe.sh --prepare`を使います。`--dry-run`は作成しません。試験は`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/validation -p 'test_*probe.py'`です。共有場所には新しいZIPと照合用ファイルだけを上書きせず転送し、コピーの一致を確かめます。

## Recommended Models and Effort

結果評価と必要な修正は、Claude Code：Claude Opus 5.5／xhigh、Codex：GPT-6-Astra／xhighを推奨します。
