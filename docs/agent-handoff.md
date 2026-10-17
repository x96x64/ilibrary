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
   公開の最終承認は取得済みです。push 前の実ファイルプレビュー・要約と邦訳は続けてください。
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
現在は codex/m10-rebuild-feasibility で M10 v2 の結果評価まで終わっています。docs/reports/rebuild-feasibility-v2-results.md が最新の評価です。0.1.0 の公開は完了しています。
v2 の small（6曲・3アルバム）は、バックアップ復元、退避、登録削除、本人による空のGUI確認、Music終了、終了中の編集、順序付き再登録と照合まで成功しました。その後、日時の集計で ValueError が発生しています。scale は未実行です。
追加日時の完全一致、最近追加した項目の表示順、再実行時の登録不変、最後のバックアップ検証は未確認です。M10 合格や日時不一致と取り違えないでください。
AppleScript が大きな整数を指数表記にすると旧処理が失敗することを、Music を使わずに再現しました。実測値の表記は未確認なので、今回の原因としては推測です。ローカルの集計を Decimal に直し、31件のテストで1秒の差を丸めないことなどを確認しました。渡したv2のZIPは変更していません。
次は docs/rebuild-feasibility-date-check.md の読み取り専用手順で本人が返す日時の補足結果を評価してください。保存済みの最終登録を読むだけで、Musicにアクセスしたりファイルを書き換えたりしません。本人の別ユーザーの記録は通常ユーザーから読めず、権限は変更していません。
small を最初からやり直したり、scale を始めたり、既存登録を削除したりしないでください。日時が異なるなら現行条件を満たさない結果として停止し、条件の変更は本人に判断してもらいます。同じでも残りの確認事項を成功扱いにしません。
生の結果の保存先は reference-private/m10-v2-results-2026-10-17/ です。初回の記録と報告書も保持しています。実ライブラリ、私的な音源、普段の Music には触れないでください。
M10 合格前に M11 以降や製品の rebuild を実装しないでください。新たな push・公開は別途承認が必要です。README の本人指定の Bad の例と公開済み 0.1.0 は変更しません。
区切りで Current Status を更新してコミットし、結果・残課題・次の作業・引き継ぎプロンプトを日本語で報告してください。変更文書は実ファイルのプレビューと各セクションの要約・邦訳を示してください。
```

## Recommended Models and Effort

For M10 feasibility and the subsequent registration-removal and recovery work, use Claude Opus 5.5 with xhigh in Claude Code or GPT-6-Astra with xhigh in Codex. The maintainer selected this effort before starting M10; it follows the M5 safety rationale. Use the milestone table for later work. Do not use ultra.
