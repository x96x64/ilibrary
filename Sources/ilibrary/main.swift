import Foundation

exit(CommandLineInterface.run(Array(CommandLine.arguments.dropFirst()), console: .standard, environment: .system))
