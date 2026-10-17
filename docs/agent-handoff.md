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
5. 0.1.0 は公開済みです。現在の文書修正と整理を終えてから、私が確認するためのコマンドを順番に説明してください。
   私の確認が済むまで、GitHub のリリース本文・表示区分や npm の公開経路は変更しないでください。
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

## Next Session after Version 0.1.0

```text
~/ilibrary の AGENTS.md、docs/planning-study.md、docs/roadmap-to-stable.md を読み、Git の現状を確認してください。
M5/M6 は別ユーザーで 12 項目成功、M8 は 301 ファイルのコピーで成功しています。詳細は新しい報告書を読んでください。
0.1.0 は GitHub・npm・PyPI・Homebrew で公開済みです。npm は @x96_64/ilibrary、PyPI は x96_64-ilibrary、Homebrew は x96x64/tap/ilibrary です。公開先からの導入確認も成功しています。完了した公開や検証を理由なく繰り返さないでください。
普段の Music と元ファイルは変更せず、私的なデータは reference-private/ 内だけで扱ってください。
まず文書修正と既存の整理作業を完了し、その後で私が手元で確認するためのコマンドを、順番に説明付きで示してください。確認用コマンドを先に出さないでください。
私が確認するまでは、GitHub のリリース本文・表示区分や npm の公開経路の変更は待ってください。希望はリポジトリ右側の Releases にリリース名を表示することです。GitHub Packages への追加配布や、公開済み npm 0.1.0 の再公開は不要です。
既存のタグ、公開済みバージョン、履歴は変更しないでください。npm の次回 GitHub 公開を使う場合だけ、Trusted Publisher の設定を案内してください。
docs/planning-study.md の Outlook to Version 1.0.0 にある既存の見通しを取り出してください。これは当初の構想で、確定した新計画ではありません。
新しい 1.0.0 までの計画は GPT-6-Astra で作りたいので、計画を作り始める直前で止まってください。モデル切り替え前に計画や新実装を始めないでください。
今後の push 前も、実ファイルのプレビュー、各セクションの要約と邦訳を示してください。計画書と過去の報告書は保存してください。
Current Status を更新してコミットし、結果・残課題・次の作業・引き継ぎプロンプトを日本語で報告してください。
```

## Recommended Models and Effort

For the remaining M9 documentation and release closeout, use Claude Opus 5.5 with high in Claude Code, or GPT-6.1-Sol with high in Codex, following the roadmap. For the subsequent version 1.0.0 planning, the maintainer explicitly selected GPT-6-Astra; use high and stop before planning until that model is selected. Claude Opus 5.5 with high is the corresponding Claude Code recommendation. These models are recorded as available to the maintainer; do not select `ultra`.
