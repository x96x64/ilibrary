import CatalogCore
import Foundation

enum TimestampsCommand {
    static let syntax = CommandSyntax(
        name: "timestamps",
        usage: """
            Usage: ilibrary timestamps CATALOG.json PATH... [--dry-run] [--script FILE]

            Sets the creation and modification dates of the matched .m4a files to their release dates at local
            midnight, then of album folders that hold one album, then of artist folders for which the catalog
            gives a folderDate. A missing path is reported and never created; symbolic links are refused. Each
            date is read back after it is set. Setting creation dates requires macOS.

            Options:
              --dry-run       list the planned dates and change nothing
              --script FILE   also write an equivalent shell script that uses SetFile and touch
            """, valued: ["--script": []], flags: ["--dry-run"], positionals: 2...Int.max)

    static func run(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        let parsed = try syntax.parse(arguments)
        let dryRun = parsed.flag("--dry-run")
        let paths = Array(parsed.positionals.dropFirst())
        let roots = directoryRoots(paths)
        if !dryRun, environment.setDates == nil {
            throw CommandError.failure("setting creation dates is supported only on macOS; use --dry-run or --script")
        }
        let script = parsed.value("--script").map { URL(fileURLWithPath: $0).standardizedFileURL }
        if let script, pathKind(script) != .missing {
            throw CommandError.failure("\(script.path) already exists; it is not overwritten")
        }
        let (catalog, _) = try loadCatalog(parsed.positionals[0], console: console)
        let correspondence = try Correspondence.requireComplete(paths, catalog: catalog, console: console)
        let files = correspondence.matchedFiles.map { ($0.file.url, catalog.resolve($0.match.reference)) }
        let plan = TimestampPlanner.plan(files: files, catalog: catalog, roots: roots, timeZone: environment.timeZone)
        TimestampPlanner.printPlan(
            plan, timeZone: environment.timeZone, root: roots.count == 1 ? roots[0] : nil, console: console)
        if let script {
            try TimestampPlanner.script(plan, timeZone: environment.timeZone).write(
                to: script, atomically: false, encoding: .utf8)
            console.print("Wrote the equivalent script \(script.path)")
        }
        if dryRun {
            console.print("Dry run: no date was changed.")
            return 0
        }
        let dated = try TimestampPlanner.execute(plan, environment: environment)
        console.print("Dated and verified: \(dated) paths")
        return 0
    }
}
