# Stopped Timing Probe Diagnostics

## Purpose and Boundary

今回の検証は、メディアフォルダ内のファイル確認で停止しました。追加日時や表示順の判定にはまだ進んでいません。フォルダの選択は確認済みですが、何が停止の原因になったかは報告に残っていません。

次は**検証用ユーザーで、保存済み記録とフォルダ内の名前・種類・大きさだけを確認**します。Musicの起動・終了・問い合わせ、曲の追加・削除、ファイル内容の読み取りは行いません。記録用JSONを一つ作成します。元の検証は再実行しません。ファイル、ライブラリ、設定、過去の記録をそのまま残してください。

この確認で分かるのは「確認時点の内容」です。停止時点の内容と同一だったとは自動的に判断しません。

## Step 1: Use the Existing Test User

普段のユーザーから、今回使った **ilibrarytest** などの検証用ユーザーへ切り替えます。新しいユーザーやライブラリは作りません。Musicの状態やメディアフォルダの設定は変えず、Terminalを開きます。

## Step 2: Save One Private Inventory

次を一度に貼り付けて実行してください。共有場所に置いた確認用スクリプトを照合して実行します。登録を追加する検証は呼び出しません。保存先が既にある場合は上書きせず停止します。

```sh
cd /Users/Shared &&
shasum -a 256 -c ilibrary-m10-inspect-timing-media.py.sha256 &&
python3 -B /Users/Shared/ilibrary-m10-inspect-timing-media.py
```

予定だけ見る場合は、最後のコマンドの末尾に`--dry-run`を付けます。

以下は同じスクリプトの全文です。上のコマンドを実行したら、こちらを重ねて実行する必要はありません。

<details>
<summary>確認用スクリプト全文</summary>


```sh
python3 - <<'PY'
import datetime, json, os, pwd, stat, sys
from pathlib import Path

SOURCE = '1493bdaa36257c848730a6fcdaabca17d24f1068'

def require(ok):
    if not ok:
        raise ValueError('conditions')

def safe(path):
    require(path.is_absolute() and '..' not in path.parts)
    for part in (path, *path.parents):
        require(not part.is_symlink())
    return path

def read_json(path):
    safe(path)
    require(stat.S_ISREG(path.stat().st_mode) and path.stat().st_size < 1048576)
    return json.loads(path.read_text())

def inventory(root):
    rows = []
    def visit(fd, prefix, depth):
        require(depth <= 20)
        for name in sorted(os.listdir(fd)):
            require(len(rows) < 5000)
            info = os.stat(name, dir_fd=fd, follow_symlinks=False)
            relative = prefix + name
            kind = ('directory' if stat.S_ISDIR(info.st_mode) else
                    'file' if stat.S_ISREG(info.st_mode) else
                    'symlink' if stat.S_ISLNK(info.st_mode) else 'other')
            rows.append({'relative': relative, 'type': kind, 'size': info.st_size,
                         'allowed_by_stopped_guard': kind == 'directory' or
                         (name == '.DS_Store' and kind != 'symlink')})
            if kind == 'directory':
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                try:
                    visit(child, relative + '/', depth + 1)
                finally:
                    os.close(child)
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        visit(fd, '', 0)
    finally:
        os.close(fd)
    return rows

def main():
    account = pwd.getpwuid(os.getuid())
    require(sys.platform == 'darwin' and os.getuid() != 0 and
            (account.pw_name == 'ilibrarytest' or account.pw_name.startswith('ilibrary-test')))
    require(sys.argv[1:] in ([], ['--dry-run']))
    print('予定: 保存済み記録と対象フォルダの名前・種類・大きさを読み、私的な報告を一つ保存します。Musicは操作しません。')
    if sys.argv[1:] == ['--dry-run']:
        print('Dry run: 保存済み記録とフォルダは読まず、報告も作成していません。')
        return
    home = safe(Path(account.pw_dir))
    work = home / 'ilibrary-m10-timing/reference-private/timing-small'
    result = read_json(work / 'result.json')
    require(result['commit'] == SOURCE and result['case'] == 'timing-small' and
            result['state'] == 'STOP' and result['phase'] == 'empty-library')
    plan = read_json(work / 'plan.json')
    media = safe(Path(plan['media']))
    require(media.parent == home / 'Music/M10-timing-small' and
            media.name in ('Media', 'Media.localized') and media.is_dir())
    initial = read_json(work / 'initial-registration.json')
    require(initial == [])
    output = safe(Path('/Users/Shared/reference-private/ilibrary-m10-timing-media-inventory.json'))
    require(not output.exists())
    data = {'format': 'ilibrary-m10-timing-media-inventory-1', 'source_commit': SOURCE,
            'observed_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'observation': 'current filesystem; not a snapshot of the stopped run',
            'saved_initial_registration_count': len(initial), 'media_name': media.name,
            'entries': inventory(media)}
    payload = json.dumps(data, ensure_ascii=False, indent=2) + '\n'
    output.parent.mkdir(mode=0o755, exist_ok=True)
    fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(payload)
        stream.flush()
        os.fchmod(stream.fileno(), 0o644)
    require(output.read_text() == payload)
    print('PASS: 一覧を保存・照合しました。音楽ファイル・Music・元の検証記録は変更していません。')
    print('報告先: /Users/Shared/reference-private/ilibrary-m10-timing-media-inventory.json')

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, RecursionError) as error:
        print('STOP: ' + type(error).__name__ + '。何も削除・再実行せず、この表示を報告してください。')
        sys.exit(1)
PY
```

</details>

`PASS`が出れば完了です。名前や個人パスをTerminalに並べず、詳細は`reference-private/`内の報告に保管します。エラー時も自動削除や修復はしません。

## Step 3: Return the Result Once

普段のユーザーへ戻り、次の一文を送ってください。

> M10日時検証の停止原因を確認してください：`/Users/Shared/reference-private/ilibrary-m10-timing-media-inventory.json`

`STOP`の場合は、その表示をそのまま送ってください。原因が分かるまでは、元の検証、追加、削除、設定変更は行いません。

## Recommended Models and Effort

次の結果評価は、Claude Code：Claude Opus 5.5／xhigh、Codex：GPT-6-Astra／xhighを推奨します。
