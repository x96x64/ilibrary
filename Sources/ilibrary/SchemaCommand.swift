import CatalogCore

enum SchemaCommand {
    static let syntax = CommandSyntax(
        name: "schema", usage: "Usage: ilibrary schema\n\nPrints the JSON Schema of the ilibrary-catalog-1 format.",
        positionals: 0...0)

    static func run(_ arguments: [String], console: Console) throws -> Int32 {
        _ = try syntax.parse(arguments)
        console.print(Catalog.jsonSchema)
        return 0
    }
}
