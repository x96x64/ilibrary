# Package Publication Setup

## Purpose

この手順は、iLibrary の npm・PyPI 公開に必要な、ご本人の Web 操作を説明します。GitHub 側の準備、配布物の作成、確認、公開処理はエージェントが担当します。通常の Music や音楽ファイルを操作する必要はありません。

今回の配布名は次のとおりです。npm のログイン名は `x96_64`、GitHub の所有者名は `x96x64` です。npm ではご本人の名前を使い、グループ作成やアカウント名の変更は行いません。

| 公開先 | 名前 |
| --- | --- |
| npm | `@x96_64/ilibrary` |
| PyPI | `x96_64-ilibrary` |
| GitHub | `x96x64/ilibrary` |

パスワード、認証コード、リカバリーコード、トークンは、画面上でご本人が入力してください。この会話へ貼る必要はありません。

## PyPI Setup

以前の `x96x64-ilibrary` の登録とは別に、新しい配布名 `x96_64-ilibrary` で登録します。以前の登録だけでは、新しい名前で公開できません。新しい登録を確認してから、不要になった古い pending publisher を削除できます。iLyrics の登録はそのままにしてください。

これは初回公開の前に進められます。PyPI に「この GitHub リポジトリの公開処理を信頼する」と登録します。登録だけではパッケージは公開されません。

1. [PyPI のログイン画面](https://pypi.org/account/login/)を開き、iLyrics で使っている PyPI アカウントへログインします。表示された場合は、ご本人の方法で二段階認証を完了します。
2. [Publishing 設定](https://pypi.org/manage/account/publishing/)を開きます。メニューから辿る場合は、右上のアカウントメニューで **Account settings** を開き、左側の **Publishing** を選びます。
3. **Add a new pending publisher** に相当する、新規プロジェクト向けの入力欄を探し、**GitHub** または **GitHub Actions** を選びます。既存の iLyrics の設定は変更しません。
4. 次の表どおりに入力します。画面の表記が多少異なる場合も、対応する項目へ入力してください。

| 画面の項目 | 入れる値 |
| --- | --- |
| PyPI project name / Project name | `x96_64-ilibrary` |
| Owner / GitHub owner | `x96x64` |
| Repository name | `ilibrary` |
| Workflow name / Workflow filename | `release.yml` |
| Environment name | `pypi` |

5. **Add** を押します。ワークフロー名には `.github/workflows/` を付けず、`release.yml` だけを入れます。
6. 登録一覧に `x96_64-ilibrary` と `x96x64/ilibrary`、`release.yml`、`pypi` が表示されたことを確認します。
7. この会話へ **「PyPI の pending publisher を登録しました」** と報告してください。パッケージのページがまだ存在しなくても正常です。最初の公開時に作られます。

名前が使用済みと表示された場合は、その文面だけを教えてください。別の名前を作ったり、既存の設定を削除したりする必要はありません。

根拠：[PyPI の初回公開手順](https://docs.pypi.org/trusted-publishers/creating-a-project-through-oidc/)。pending publisher は名前の予約ではなく、最初の公開が成功した時点で通常の登録に変わります。

## npm Sign-In

npm の新しいパッケージは、初回公開後に Web の公開設定を追加する流れで進めます。先に、この Mac の npm をご本人のアカウントへログインさせます。

1. [npm のログイン画面](https://www.npmjs.com/login)を開き、`x96_64` のアカウントへログインします。アカウントメニューでユーザー名を確認してください。GitHub 側の `x96x64` と npm の `x96_64` を区別します。
2. この Mac の **ターミナル**を開き、次のコマンドを実行します。音楽のテストユーザーへ切り替える必要はありません。

```bash
npm login --auth-type=web --registry=https://registry.npmjs.org
```

3. ブラウザを開く案内が表示されたら、ターミナルで Return を押します。自動で開かない場合は、ターミナルに表示されたログイン用 URL をご本人のブラウザで開きます。その URL を会話へ貼る必要はありません。
4. ブラウザ上で npm のログイン・認証を完了し、この Mac からのログインを許可します。確認に表示されるアカウントが `x96_64` であることを確かめてください。
5. ターミナルへ戻り、ログイン成功の表示を待ちます。続いて次を実行します。

```bash
npm whoami --registry=https://registry.npmjs.org
```

6. `x96_64` と表示されたら、**「npm のログインが完了し、whoami は x96_64 でした」** と報告してください。

別のユーザー名が表示された場合は、そのユーザー名だけを教えてください。名前変更や新規アカウント作成はまだ不要です。

初回公開で npm が追加の Web 認証を求める場合は、その時点でエージェントが案内します。トークンを作成して貼り付ける手順は使いません。

根拠：[npm login](https://docs.npmjs.com/cli/v11/commands/npm-login/)、[スコープ付き公開パッケージ](https://docs.npmjs.com/creating-and-publishing-scoped-public-packages/)。

## npm Trusted Publisher Setup

この操作は初回公開後に行えます。次の GitHub 経由の公開直前に設定することを推奨します。npm の現行仕様では、新しい接続は 2 日以内に最初の公開を成功させないと期限切れになるため、次の公開予定がない段階では設定を急ぐ必要はありません。初回公開前は設定画面が存在しない場合があります。

1. [@x96_64/ilibrary のページ](https://www.npmjs.com/package/@x96_64/ilibrary)を開きます。
2. 公開権限を持つ `x96_64` にログインした状態で **Settings** を選びます。
3. **Trusted Publisher** または **Trusted publishing** の欄を探し、**GitHub Actions** を選びます。
4. 次の値を入力します。

| 画面の項目 | 入れる値 |
| --- | --- |
| Organization or user / Owner | `x96x64` |
| Repository | `ilibrary` |
| Workflow filename | `release.yml` |
| Environment name | `npm` |

5. 公開方法の選択が表示された場合は、`npm publish` による直接公開を許可します。設定欄の追加・保存ボタンで登録します。画面が求めた場合は、ご本人の二段階認証を完了してください。
6. 登録された接続先が `x96x64/ilibrary`、`release.yml`、`npm` であることを確認します。
7. **「npm の Trusted Publisher を登録しました」** と報告してください。

この設定によって、次回以降は GitHub の確認済み公開処理から公開できます。iLyrics の接続先やアカウント全体の認証設定は変更しません。

根拠：[npm Trusted Publishing](https://docs.npmjs.com/trusted-publishers/)。

## Result Report

途中でも、完了した行だけで報告できます。

```text
PyPI: x96_64-ilibrary の pending publisher 登録済み
npm: ログイン済み、whoami は x96_64
npm Trusted Publisher: 次回の GitHub 経由公開前に設定予定
```

初回公開後の設定まで終わったら、最後の行を `登録済み` に変えてください。画面が手順と違う場合は、見えている項目名やエラー文だけを教えてください。

## Recommended Models and Effort

次の公開作業は、ロードマップの M9 に従い、Claude Code は Claude Opus 5.5／high、Codex は GPT-6.1-Sol／high を推奨します。
