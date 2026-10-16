import CatalogCore
import Foundation

enum PromptCommand {
    static let syntax = CommandSyntax(
        name: "prompt",
        usage: """
            Usage: ilibrary prompt CATALOG.json

            Prints instructions for completing a draft catalog with an AI agent or AI chat: the authoring rules
            in English with Japanese explanations, the JSON Schema, and the draft. Output from a model must be
            checked with 'ilibrary validate' and previewed with 'ilibrary apply --dry-run' before it is applied.
            """, positionals: 1...1)

    static let rules = """
        # Completing an iLibrary Catalog

        You are completing a draft catalog in the iLibrary format `ilibrary-catalog-1`. The catalog is the
        reference record from which metadata is written to music files. Return the complete catalog as one JSON
        document that conforms to the schema below, and nothing else.
        （iLibrary のカタログ形式 `ilibrary-catalog-1` の下書きを完成させてください。カタログは音楽ファイルに書き込む
        メタデータの基準となる記録です。下記のスキーマに従う JSON 文書を一つだけ、完全な形で返してください。）

        ## Rules

        1. Keep `"format": "ilibrary-catalog-1"`, every album, every disc, and the order of the tracks. Do not
           add, remove, merge, or reorder tracks: their positions are their disc and track numbers.
           （形式名、アルバム、ディスク、曲の順序はそのまま残してください。曲の位置がディスク番号と曲番号になります。）
        2. Leave a value empty (`""`) or omit it when you do not know it. Never guess. An empty value leaves the
           file's existing value unchanged.
           （分からない値は推測せず、空文字列にするか省略してください。空の値はファイルの既存の値を変更しません。）
        3. Record your evidence for copyright lines and release dates in `notes` and `sources` (URLs) of the
           album. These fields are ignored when the catalog is applied.
           （著作権表示とリリース日の根拠は、アルバムの `notes` と `sources`（URL）に記録してください。適用時には無視されます。）
        4. Write copyright lines with the symbols ℗ and ©, as in `℗ 1980 Example Records, Inc.`, not (P) or (C).
           （著作権表示は (P) や (C) ではなく、記号 ℗ と © で書いてください。）
        5. Write release dates as `YYYY-MM-DD`. Set a track's `releaseDate` only when it differs from the album's.
           （リリース日は `YYYY-MM-DD` 形式で書き、曲ごとの値はアルバムと異なる場合だけ設定してください。）
        6. Values at album level apply to every track; set a track-level value only to override it. Write each
           composer's full name, and separate several composers with a comma and a space.
           （アルバム単位の値は全曲に適用されます。曲単位の値は上書きする場合だけ設定してください。作曲者は省略せず正式な名前で書き、
           複数の場合は「, 」で区切ってください。）
        7. Titles follow the source's capitalization unless `titleRules.case` says otherwise. A parenthetical
           that contains another parenthetical is written with square brackets, as in
           `Under the Lights [Sam's Mix (Demo)]`.
           （曲名は、`titleRules.case` に指定がない限り元の大文字小文字に従います。括弧の中にさらに括弧がある場合は、外側を角括弧に
           してください。）
        8. Live recordings carry `(Live)`, or `[Live]` when the title already ends with a parenthetical.
           Interludes carry no live designation.
           （ライブ録音には `(Live)` を付け、曲名がすでに括弧で終わる場合は `[Live]` にしてください。インタールードには付けません。）
        9. Use `aliases` for other names under which an album's files are tagged, such as a name with
           `(Remastered)`.
           （ファイルに別の名前（例：`(Remastered)` 付き）で付いているアルバム名は、`aliases` に入れてください。）
        10. Do not add fields that the schema does not define.
            （スキーマにないフィールドを追加しないでください。）

        The result is checked with `ilibrary validate` and previewed with `ilibrary apply --dry-run` before
        anything is written.
        （結果は、書き込む前に `ilibrary validate` で検査し、`ilibrary apply --dry-run` で変更内容を確認します。）
        """

    static func run(_ arguments: [String], console: Console) throws -> Int32 {
        let parsed = try syntax.parse(arguments)
        let (catalog, _) = try loadCatalog(parsed.positionals[0], console: console)
        let draft = String(decoding: try catalog.encoded(), as: UTF8.self)
        console.print(rules)
        console.print()
        console.print("## JSON Schema")
        console.print()
        console.print("```json\n\(Catalog.jsonSchema)\n```")
        console.print()
        console.print("## Draft Catalog")
        console.print()
        console.print("```json\n\(draft.trimmingCharacters(in: .newlines))\n```")
        return 0
    }
}
