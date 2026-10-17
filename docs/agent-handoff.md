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
~/ilibrary の AGENTS.md、docs/planning-study.md、docs/roadmap-to-stable.md、docs/stable-release-plan.md、docs/reports/display-media-path-correction.md を読み、git status と git log を確認してください。
現在は codex/m10-rebuild-feasibility です。停止時ログを受領し、保存先は予定のM10-v2-smallの直下のMedia.localized、旧検証の期待値はMediaと確認しました。検証側がこの末尾名に対応していなかったことが直接原因です。設定を合わせた本人の操作ミスとは扱いません。旧結果と当時の評価は保持しています。
修正97d4c0bは、予定したライブラリ直下のMediaとMedia.localizedだけを認め、実行中は選択したパスに固定します。別ライブラリ・余分な階層・似た別名・存在しない場所・シンボリックリンク・途中のパス変更は拒否します。旧smallのID、登録場所、内容、バックアップの照合は維持しています。
67件の合成試験が通り、設定値を解析する実際の関数に合成のコマンド出力を通す試験と、Media.localizedでのsmall再利用・4種類の全工程の代替試験を含みます。Musicの実測ではありません。releaseビルド、324曲と8カタログ、新しい一式とZIPの照合も通っています。
新しい一式はilibrary-m10-display-v2、ソースは97d4c0bです。ZIPと照合ファイルは共有場所へ別名で転送し一致を確認済みです。SHA-256は9676a7cea84544ebe37ce2b0c071ece781c8cbffffdd95a54c5a9116a3c49290です。docs/rebuild-display-validation.mdと同梱PROCEDURE.mdが現在の日本語手順です。エージェントは別ユーザー操作の直前で止まっています。
旧ilibrary-m10-displayと停止記録、さらに古いilibrary-m10-v2とsmallの6曲を保持します。Media.localizedを変更せず、新しい一式でsmallの事前検査から再開します。旧runを再実行したり、停止記録を削除して再開したりしません。smallは退避・登録削除を繰り返しません。ほかの4ケースは未実行のため別々の新しい空の合成ライブラリを使います。
次は本人からの/Users/Shared/ilibrary-m10-display-v2-report.txtの評価です。成功、不一致、確認不能、停止、未実行を区別します。準備完了だけでM10を合格にしません。追加日時の1秒差だけでは不合格にせず、表示順と再起動後の維持、再実行時の安全性、最後の保全確認を実測結果から判定します。
今回の受領ログはreference-private/m10-display-results-2026-10-17/preflight-diagnostics.jsonlに保存済みで、SHA-256は92d93d2e7f05be274bd427c960358038ace2d2422fbf701558c79c70245fe46dです。個人パスを公開しません。診断ログの再転送や準備のやり直しを求めないでください。
Music・実ライブラリ・私的音源は操作しません。M10完了前にM11以降や製品rebuildへ進めません。新たなpush・公開は別途承認が必要です。Current Statusと引き継ぎを更新してコミットし、実ファイルプレビューと各セクションの要約・邦訳を示してください。
```

## Recommended Models and Effort

For M10 feasibility and the subsequent registration-removal and recovery work, use Claude Opus 5.5 with xhigh in Claude Code or GPT-6-Astra with xhigh in Codex. The maintainer selected this effort before starting M10; it follows the M5 safety rationale. Use the milestone table for later work. Do not use ultra.
