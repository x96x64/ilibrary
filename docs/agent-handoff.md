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
~/ilibrary の AGENTS.md、docs/planning-study.md、docs/roadmap-to-stable.md、docs/stable-release-plan.md、docs/reports/addition-timing-results.md を読み、git status と git log を確認してください。
現在は codex/m10-rebuild-feasibility です。M10日時分離の報告（ソース1493bda）は、Media.localizedの選択確認を通過した後、empty-libraryのメディア内ファイル確認で4.703秒後にSTOPしました。日時分離・追加・GUI・再実行・今回の保全確認には進んでいません。初期登録ゼロの通過はソースからの推測で、保存済みsnapshot自体は未受領です。
拒否したファイルの名前・種類・由来は未確認です。設定ミスや.DS_Storeと断定しないでください。日時比較の手順は停止中です。次はdocs/rebuild-timing-diagnostics.mdの、同じ検証用ユーザーで行うMusic未操作の一覧確認だけです。報告先は/Users/Shared/reference-private/ilibrary-m10-timing-media-inventory.jsonです。報告が来たら、初期登録記録と現在のファイル一覧を評価し、停止時点の一覧と混同しないでください。未受領ならエージェントから検証ユーザーのメディアを読まず、別ユーザー操作前で止めてください。
受領済みの停止報告はreference-private/m10-timing-results-2026-10-17/report.txt、SHA-256は5db76008caa4b5796bd05063f3edaa0a0b345c90503851970373e36ca3c32181です。旧display-v3のsmallは期待3,2,1に対し再起動前後とも2,3,1で不合格でした。保全と再実行は成功し、残り4ケースは未実行です。旧結果は変更しません。
すべてのライブラリ、一式、バックアップ、完了・停止記録を保持します。同じ実行の繰り返し、登録削除、手動再追加、記録削除、設定や期待順の変更をしません。今回の結果から許可対象ファイルを追加したり、ガードを緩めたりしません。実ライブラリ・私的音源は操作しません。原因を確認してから、必要な限定修正と新しい手順を検討します。
M10は未完了です。300曲、ほかの順序、製品の待機方式、自動GUI空判定、別媒体バックアップは未検証です。M10完了前のM11以降・製品rebuild、未承認のpush・公開には進みません。Current Statusと引き継ぎを更新してコミットし、実ファイルプレビューと要約・邦訳を示してください。
次の原因確認の推奨は、Claude Code: Claude Opus 5.5／xhigh、Codex: GPT-6-Astra／xhighです。
```

## Recommended Models and Effort

For M10 feasibility and the subsequent registration-removal and recovery work, use Claude Opus 5.5 with xhigh in Claude Code or GPT-6-Astra with xhigh in Codex. The maintainer selected this effort before starting M10; it follows the M5 safety rationale. Use the milestone table for later work. Do not use ultra.
