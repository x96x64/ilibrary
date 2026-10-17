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
~/ilibrary の AGENTS.md、docs/planning-study.md、docs/roadmap-to-stable.md、docs/stable-release-plan.md、docs/reports/display-order-v2-results.md を読み、git status と git log を確認してください。
現在は codex/m10-rebuild-feasibility です。display-v2（97d4c0b）の結果を受領しました。Media.localizedの確認はPASS、Music 1.7を取得し、legacy-evidenceで「検証一式のファイル一覧が一致しません」とSTOPしました。残り4ケースはNOT RUNです。表示順は未測定で、M10は未完了です。
旧一式のmanifest識別情報は停止箇所より前に照合済みです（コードからの推定）。旧一式のファイル名集合で停止し、内容のハッシュ照合や現在の登録の確認には達していません。追加・欠損のどちらか、具体的なファイル名、原因はまだ不明です。音声破損やユーザーの操作ミスを断定しないでください。
受領報告はreference-private/m10-display-v2-results-2026-10-17/report.txtに保存済みで、SHA-256は486f1ae64cbb9b1b7b41433dff48eeeb0695e3a4005444d93b3291b9f7c41cf6です。旧報告、ライブ検証コード、全ZIPは変更していません。
c56190dで読み取り専用診断inspect_rebuild_bundle.pyを追加し、9件の合成試験が通っています。開発側の旧準備一式は314ファイルと内容が一致しましたが、検証ユーザー側の実態は未確認です。診断は検証用ユーザーに限定し、manifestを固定、リンクをたどらず、private記録を走査せず、追加ファイルの内容も読みません。差分の名前はreference-privateの新しい報告だけへ保存します。
診断スクリプトと照合ファイルは/Users/Shared/ilibrary-m10-inspect-bundle.pyと同名の.py.sha256へ転送済みです。スクリプトのSHA-256は865e7820931af3341feb72269f1a9eba5dfcd801df2788fd89d978a5def262aeです。docs/rebuild-bundle-diagnostics.mdが現在の手順です。本人の別ユーザー操作の直前で止まっています。
次に評価するのは/Users/Shared/reference-private/m10-display-inventory/inventory.jsonです。受領したらignoreを確認してreference-privateに保存し、追加・欠損・内容の差・リンク等を区別してください。未知の相対ファイル名も公開文書や会話にそのまま出さないでください。診断ログの再転送やMusicの再測定を先に求めないでください。
差分の原因が分かるまで全ライブ手順を再実行しません。ファイル削除、旧一式の修復、設定変更、smallの作り直しは行いません。以前の6曲・ライブラリ・バックアップ・停止記録をすべて保持します。必要な修正は対象保護を維持して準備・検証し、別ユーザーでの操作前に止まってください。
Music・実ライブラリ・私的音源は操作しません。M10完了前にM11以降や製品rebuildへ進めません。新たなpush・公開は別途承認が必要です。Current Statusと引き継ぎを更新してコミットし、実ファイルプレビューと各セクションの要約・邦訳を示してください。
```

## Recommended Models and Effort

For M10 feasibility and the subsequent registration-removal and recovery work, use Claude Opus 5.5 with xhigh in Claude Code or GPT-6-Astra with xhigh in Codex. The maintainer selected this effort before starting M10; it follows the M5 safety rationale. Use the milestone table for later work. Do not use ultra.
