import Foundation

let version = "0.0.0"
let arguments = CommandLine.arguments.dropFirst()

if arguments == ["--version"] {
    print("ilibrary \(version)")
    exit(0)
}

FileHandle.standardError.write(Data("ilibrary: no commands are implemented in this planning baseline\n".utf8))
exit(arguments.isEmpty || arguments == ["--help"] || arguments == ["-h"] ? 0 : 2)
