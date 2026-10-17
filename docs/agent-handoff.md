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
~/ilibrary の AGENTS.md、docs/planning-study.md、docs/roadmap-to-stable.md、docs/stable-release-plan.md、docs/reports/display-order-v3-results.md を読み、git status と git log を確認してください。
現在は codex/m10-rebuild-feasibility です。display-v3（ソースf6511d5）のsmallは最後まで実行され、表示順が不一致でした。期待3,2,1に対し、本人の観察は再起動前後とも2,3,1です。準備段階のSTOPではなく、完了した測定のFAILです。M10は未達で、残り4ケースはNOT RUNです。
元の合成バックアップの復元・照合、編集済みコピーとの一致、完了済み追加の再実行でID・日時・ファイル・記録が変わらないこと、最後のバックアップ確認は成功しました。旧smallの退避・登録削除は繰り返していません。日時は2種類で差は1秒、複数アルバムが同じ秒を共有しています。日時の重なりが表示不一致の原因かは未確認です。
報告はreference-private/m10-display-v3-results-2026-10-17/report.txtに保存しています。SHA-256は6b859c028563f78efd741344ace1ebf23c67f70b0748ef11f029f68113795cfeです。今回の評価ではMusicを操作していません。
次の候補は、アルバム間の追加日時が重ならないように待つ方法の独立した合成比較です。実際の日時の境界、待ち時間、時間切れ時の停止、期待順と観察順、再起動後を記録する設計を検討してください。待てば直るとは断定せず、製品コードや新しい検証の実装は今回の評価では行っていません。日時の重なりを対応範囲から除外するなら、条件変更の明示的な判断が必要です。
旧small、全ライブラリ、全一式、バックアップ、完了記録、停止記録を保持します。現行手順の残り4ケースもいったん保留です。既存登録の削除や再追加、記録削除による再実行、期待順の書き換えをしません。同じ手順を本人に再実行させず、次の検証が必要なら一式を準備・確認してから、別ユーザー操作直前で止め、実行から一度の結果報告までの日本語手順を示してください。
実ライブラリと私的音源は操作しません。自動GUI空判定と別の物理媒体のバックアップは未検証です。M10完了前にM11以降や製品rebuildへ進めません。新たなpush・公開には承認が必要です。Current Statusと引き継ぎを更新してコミットし、実ファイルプレビューと各セクションの要約・邦訳を示してください。
次の作業の推奨は、Claude Code: Claude Opus 5.5／xhigh、Codex: GPT-6-Astra／xhighです。
```

## Recommended Models and Effort

For M10 feasibility and the subsequent registration-removal and recovery work, use Claude Opus 5.5 with xhigh in Claude Code or GPT-6-Astra with xhigh in Codex. The maintainer selected this effort before starting M10; it follows the M5 safety rationale. Use the milestone table for later work. Do not use ultra.
