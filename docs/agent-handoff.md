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
現在は codex/m10-rebuild-feasibility で M10 の v2 を準備しています。初回の small と scale は、最初の登録後の保存場所確認で STOP となり、M10 は未完了です。本人は新しい空の検証ライブラリでの測り直しと1回の結果報告を希望しています。0.1.0 の公開は完了しています。
M10 の順序は、バックアップ確認→退避→登録の自動削除→ライブラリと GUI が空になった確認→Music 終了→タグ編集→1 アルバムずつ再登録です。
全曲の「追加した日時」の完全一致と、「最近追加した項目」の表示順を別々に確認します。成立しない場合は条件を変えずに停止し、結果を説明してください。
docs/rebuild-feasibility-validation.md、docs/reports/rebuild-feasibility-preparation.md、docs/reports/rebuild-feasibility-results.md を読み、記録された測定と未確認事項を区別してください。
既存ログと記録では、6 曲・3 アルバムと 300 曲・20 アルバムの初回追加は成功しています。その後、プローブの保存場所の比較で停止しました。失敗した比較の実際の値は保存されておらず、原因は未確定です。退避・登録削除・再登録・追加日時・GUI 順序の測定には達していません。
初回結果のコピーは reference-private/m10-results-2026-10-17/ にあります。個人パスや ID を含むため公開しないでください。Decision 32 により、読み取り専用診断だけを先に行う案から、診断と本測定をまとめた v2 に変更しました。新しい ilibrary-m10-v2、M10-v2-small、M10-v2-scale を使います。本人が別ユーザーで実行する直前で止めて手順を示してください。普段のユーザーで Music を開いたり、ライブラリを読み書きしたりしないでください。
旧版の停止した検証一式を再実行したり、既存登録を削除したりしないでください。比較条件を緩めず、旧ライブラリとファイルを保持します。v2 の report コマンドで両ケースを一つの結果にまとめます。STOP 時は後続測定をせず、未実行ケースも含めて報告します。測定未完了を、要求された動作が不可能だという証拠として扱わないでください。
プローブは合成音声だけを扱います。読み取り専用ディスクイメージは同じ物理媒体上の模擬バックアップであり、本番用の独立したバックアップの証拠ではありません。
M10 合格前に M11 以降や製品の rebuild を実装しないでください。実ライブラリの操作、新たな push・公開は別途承認が必要です。
README の Bad の例は本人が選び、端末内の当該ファイルから公開用のタグだけを読み取りました。原本は変更していません。測定記録は reference-private/ 内だけです。
区切りで Current Status を更新してコミットし、結果・残課題・次の作業・引き継ぎプロンプトを日本語で報告してください。
```

## Recommended Models and Effort

For M10 feasibility and the subsequent registration-removal and recovery work, use Claude Opus 5.5 with xhigh in Claude Code or GPT-6-Astra with xhigh in Codex. The maintainer selected this effort before starting M10; it follows the M5 safety rationale. Use the milestone table for later work. Do not use ultra.
