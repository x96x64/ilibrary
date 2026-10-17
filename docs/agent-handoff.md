# Agent Handoff

## Purpose

This document contains a general-purpose prompt for resuming work in Codex or Claude Code from the repository alone. It applies at any milestone. The prompt is written in Japanese, the maintainer's working language; the rules it refers to are defined in [AGENTS.md](../AGENTS.md). Recommended models and effort levels are listed in the [roadmap](roadmap-to-stable.md#recommended-models-and-effort).

## Prompt

```
作業ディレクトリは ~/ilibrary です。この会話の前の経緯は、リポジトリにすべて記録されています。

1. まず AGENTS.md、docs/planning-study.md、docs/roadmap-to-stable.md（特に Current Status と
   Decisions in Force）を読み、git log と git status で現在の状態を確認してください。
2. Current Status に書かれた次のマイルストーンを特定し、作業に入る前に、次の内容を日本語で私に示してください。
   - 今回やる作業の範囲
   - 完了条件（ゲート）
   - 私の Mac が必要かどうか
   既に承認した範囲は再確認せず続けてください。0.1.0 は公開・導入確認まで完了しています。
   M5/M6 の別ユーザー検証と M8 のコピー検証は報告書に記録済みです。
   取得済みの公開承認は完了した0.1.0に限ります。新しい push・公開には明示的な承認が必要です。
   承認済みの push 前にも、実ファイルプレビュー・要約と邦訳を続けてください。
   途中の作業が残っている場合は、その続きから再開してください。
3. 作業はマイルストーン用のブランチで行い、AGENTS.md の規約に従ってください。
   - コミットは iLyrics と同じ Conventional Commits、正式な英語、小さな単位とし、
     実質的に関与したコミットには Co-authored-by: Codex <codex@openai.com> を付けてください。
   - 文書の見出しは MLA のタイトルケースにしてください。
   - 根拠は測定・推測・未確認に区分し、確かめていないことを事実として書かないでください。
4. 私の実ライブラリ（~/Music/Music/Media.localized/Music）と Apple Music のライブラリには、
   私の明示的な指示なしに触れないでください。検証はコピーまたは合成ファイルで行ってください。
   実際の音楽ファイル、Apple ID、個人パスは reference-private/ 以外に置かず、公開物に含めないでください。
5. 0.1.0 は公開済みで、私の手元確認も完了しています。GitHub は修正済み本文と Latest 表示を確認してください。
   完了した公開や検証は繰り返さず、新しい公開経路や版の公開は別途承認を得てください。
   公開済みの版を再公開したり、既存タグを動かしたりしないでください。
   push の前には、変更した文書のプレビュー、主要な変更の要約、その日本語訳を示してください。
6. 区切りごとに docs/roadmap-to-stable.md の Current Status を更新してコミットし、
   Claude Code に戻っても続けられる状態にしてください。
7. 返信はすべて日本語にしてください。確認が不可欠な場合だけ、専門用語を控え、選択肢と推奨を添えてください。
   docs/test-library-validation.md に、別ユーザーへの切り替えと結果の報告方法があります。
   普段のユーザーでは Music や私の音楽ファイルを操作しないでください。
8. 最後に日本語で、次の4点を報告してください。
   - やったこと、検証結果、残っている課題
   - 次の作業
   - 次の作業の推奨モデルとエフォート（Claude Code と Codex それぞれ。Codex は GPT のモデル名で、ultra は使わない）
   - 次のセッション用のプロンプト
```

## Use in Claude Code

The same prompt applies in Claude Code. Replace the Codex attribution in item 3 with `Co-Authored-By: Claude <noreply@anthropic.com>`, optionally preceded by the model name, as defined in AGENTS.md.

## Next Session for M10

```text
~/ilibrary の AGENTS.md、docs/planning-study.md、docs/roadmap-to-stable.md、docs/stable-release-plan.md、docs/reports/finder-metadata-verification.md を読み、git status と git log を確認してください。
現在は codex/m10-rebuild-feasibility です。旧一式の差分診断を受領しました。必要な314ファイルとmanifestはすべて一致し、欠損・内容変更・読み取り不能・通常ファイル以外は0件、追加は.DS_Store一つだけでした。旧検証がこれを入力として扱ったことが停止原因です。本人の設定ミスや音声の破損とは扱いません。
受領記録はreference-private/m10-display-inventory-2026-10-17/inventory.jsonに保存し、SHA-256はe529747b427b903448e59f3394e8ad0ba7c0d04be5ea96a920d725a4aaefab12です。Musicの現在の登録やバックアップの状態を確認した結果ではありません。以前の報告とZIPは保持しています。
修正f6511d5は通常ファイルの.DS_Storeだけを一式の入力から除外し、削除も内容読み取りもしません。必要な入力の一覧とハッシュ、別名の追加・欠損・変更・リンク等の拒否は維持します。73件の合成試験が通り、旧一式を照合する実際の関数を通したsmallの代替試験を含みます。旧準備一式のコピーで旧版の停止を再現し、修正版の成功と全ファイルの保持を確認しました。Musicの実測ではありません。
新しい一式はilibrary-m10-display-v3、ソースはf6511d5です。releaseビルド、324曲と8カタログ、ZIPと共有コピーの照合が通っています。実行ファイルはdisplay-v2と同一です。ZIPのSHA-256は39e80493dc54f093428f1bdf3f62edfbe91b86abc0f1a15ea15fd913bf1b5adcです。共有場所へ転送済みで、docs/rebuild-display-validation.mdと同梱PROCEDURE.mdが現在の日本語手順です。
エージェントは別ユーザー操作の直前で止まっています。次に評価するのは/Users/Shared/ilibrary-m10-display-v3-report.txtです。成功・不一致・未確認・停止・未実行を区別します。表示順、再起動後の維持、再実行の安全性、最終保全、残り4ケースは未確認です。M10は未完了です。
旧smallの6曲、全一式、.DS_Store、停止記録、バックアップを保持します。旧コマンド・診断を繰り返さず、ファイル削除や修復、メディアフォルダの変更はしません。新しい一式でsmallを再照合し、退避・登録削除は繰り返しません。新たな停止を記録削除などで回避しません。
Music・実ライブラリ・私的音源は操作しません。M10完了前にM11以降や製品rebuildへ進めません。新たなpush・公開は別途承認が必要です。Current Statusと引き継ぎを更新してコミットし、実ファイルプレビューと各セクションの要約・邦訳を示してください。
```

## Recommended Models and Effort

For M10 feasibility and the subsequent registration-removal and recovery work, use Claude Opus 5.5 with xhigh in Claude Code or GPT-6-Astra with xhigh in Codex. The maintainer selected this effort before starting M10; it follows the M5 safety rationale. Use the milestone table for later work. Do not use ultra.
