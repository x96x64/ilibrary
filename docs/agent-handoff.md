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
~/ilibrary の AGENTS.md、docs/planning-study.md、docs/roadmap-to-stable.md、docs/stable-release-plan.md を読み、git status と git log を確認してください。
現在は codex/m10-rebuild-feasibility です。本人は「追加日時に多少の差があっても、最近追加した項目が意図したアルバム順ならよい」と決定しました。Decision 33 と docs/reports/display-order-plan-revision.md に記録し、1.0.0までの計画を改訂しました。完全一致の要否を再確認しないでください。0.1.0 の公開は完了しています。
v2 small（6曲・3アルバム）は、バックアップ復元、退避、対象登録の削除、本人による空のGUI確認、Music終了、終了中の編集、順序付き再登録と照合まで成功しました。その後の日時集計は指数表記を読めない検証側の不具合で停止しました。
本人が保存済みの数値を返し、6曲の日時が2種類、差が1秒、先の日時が2曲、1秒後が4曲と確認できました。旧条件での不合格は docs/reports/rebuild-timestamp-gate.md に保存しています。新条件ではこの差だけで失敗にはなりませんが、M10全体を合格に変更してはいけません。アルバムごとの日時の割り当ては今回の出力からは分かりません。
日時集計の修正 a608017 と31件の合成テスト成功は記録済みです。保存日時を読み直す手順も完了しています。scale、画面上の順序と再起動後の維持、再実行時の登録不変、最後のバックアップ照合は未確認です。自動でGUIが空と確認する方法と、別の物理媒体によるバックアップ復元も未確認です。
今回の承認は計画の見直しだけです。実装や追加の測定は、次の本人の指示を受けてからにしてください。次に予定するのはM10の表示順検証の準備です。追加順と期待する表示順を先に保存し、実際の画面で全アルバムを確認する計画にします。追加順の逆順表示を検証目標とし、まだ実測済みとは書きません。追加日時は差と処理経過を記録し、1秒以内などの上限を勝手に決めません。
準備開始の指示が来たら、smallの既存状態を利用できるかを先に判断し、未確認項目とscaleを検証する手順をまとめます。別ユーザーでの操作の直前に止め、実行・画面確認・一つの結果報告までを日本語で案内してください。後日の観察を元の実行時の観察として扱わないでください。
新たな実行指示が出るまでは、small、日時抽出を再実行したり、scale を開始したり、登録を削除したりしないでください。検証ライブラリ・音声・バックアップ・全記録を保持します。生の結果は reference-private/m10-v2-results-2026-10-17/ にあります。過去の報告は保存します。
M10 合格前に M11 以降や製品の rebuild を実装しないでください。実ライブラリ、私的音源、普段の Music は操作禁止です。新たな push・公開は別途承認が必要です。
区切りで Current Status を更新してコミットし、結果・残課題・次の作業・引き継ぎプロンプトを日本語で報告してください。変更文書は実ファイルのプレビューと各セクションの要約・邦訳を示してください。
```

## Recommended Models and Effort

For M10 feasibility and the subsequent registration-removal and recovery work, use Claude Opus 5.5 with xhigh in Claude Code or GPT-6-Astra with xhigh in Codex. The maintainer selected this effort before starting M10; it follows the M5 safety rationale. Use the milestone table for later work. Do not use ultra.
