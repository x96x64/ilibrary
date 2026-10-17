# Saved Addition-Date Verification

## Current Status and Scope

M10 v2 の small は、退避・登録削除・空の確認・終了・タグ編集・再登録まで成功しました。その後、日時を集計する検証処理が停止しています。scale は未実行です。[評価報告](reports/rebuild-feasibility-v2-results.md)に成立・未確認を分けて記録しています。

次は **保存済みの日時だけを読む操作**です。検証を最初からやり直しません。Music の起動・終了・登録変更、ファイルの移動・編集は行いません。旧手順の `run` を再実行したり、scale を始めたりしないでください。

## Read the Saved Values

1. 前回の検証用ユーザー `ilibrarytest` にログインします。新しいユーザーやライブラリは作りません。
2. Music の状態はそのままにして、ターミナルを開きます。
3. 以下を一つのブロックとして貼り付け、実行します。

```sh
python3 - <<'PY'
import json
import re
from decimal import Decimal
from pathlib import Path

try:
    root = Path.home() / 'ilibrary-m10-v2'
    manifest = json.loads((root / 'manifest.json').read_text())
    if not isinstance(manifest, dict) or manifest.get('probeVersion') != 2 or manifest.get('commit') != '9fe4a53f8ef5aa78cb6245f48360ad5044cf780e':
        raise ValueError()
    rows = json.loads((root / 'reference-private/small/final-registration.json').read_text())
    if len(rows) != 6:
        raise ValueError()
    raw = [row['added'] for row in rows]
    if not all(isinstance(v, str) and len(v) <= 64 and re.fullmatch(r'[+-]?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]{1,3})?', v) for v in raw):
        raise ValueError()
    values = [Decimal(v) for v in raw]
    if not all(-(2 ** 31) <= v <= 2 ** 31 - 1 and v == v.to_integral_value() for v in values):
        raise ValueError()
    seconds = [int(v) for v in values]
except (OSError, ValueError, KeyError, TypeError, ArithmeticError):
    raise SystemExit('STOP: 保存済みの日時を確認できません。この表示を報告してください。')
print('iLibrary M10 v2 saved-date supplement; small')
print('source commit:', manifest['commit'])
print('saved tracks:', len(seconds))
print('saved numeric representations:', ', '.join(raw))
print('distinct addition timestamps:', len(set(seconds)))
print('span seconds:', max(seconds) - min(seconds))
print('timestamp equality:', 'PASS' if len(set(seconds)) == 1 else 'FAIL')
print('Saved evidence only; Music not accessed; no files changed.')
print('This is not a complete M10 gate result.')
PY
```

数値の読み取りに失敗した場合も、その表示を報告します。推測でファイルを書き換えたり、別の検証を実行したりしません。

## Return the Result

表示された全文を、この会話に一度貼り付けてください。出力するのは保存済みの数値と集計だけで、曲名・パス・曲の ID は含みません。ファイル全体を共有場所へコピーする必要はありません。

`timestamp equality: FAIL` なら、今回の small では全曲の追加日時が同一ではありません。`PASS` でも表示順などは別の確認事項で、M10 全体の合格を意味しません。結果を評価するまで現在の状態を残してください。

## Recommended Models and Effort

保存済みの結果評価は、Claude Code：Claude Opus 5.5／xhigh、Codex：GPT-6-Astra／xhigh を推奨します。
