import Foundation

enum DoctorCommand {
    static let syntax = CommandSyntax(
        name: "doctor",
        usage: """
            Usage: ilibrary doctor

            Reports the version, the platform, the Music app and its media folder, the free space there, and the
            Automation permission for Music, with a recovery step for each problem. It reads Music's preferences
            and the stored permission only: it never launches Music, asks for a permission, or reads the library.
            Exit status is 0 when nothing prevents iLibrary from working, and 1 otherwise.
            """, positionals: 0...0)

    enum Level: String {
        case ok, note, problem
    }

    struct Finding {
        var level: Level
        var subject: String
        var detail: String
        var remedy: String?

        static func ok(_ subject: String, _ detail: String) -> Finding {
            Finding(level: .ok, subject: subject, detail: detail)
        }

        static func note(_ subject: String, _ detail: String, remedy: String? = nil) -> Finding {
            Finding(level: .note, subject: subject, detail: detail, remedy: remedy)
        }

        static func problem(_ subject: String, _ detail: String, remedy: String) -> Finding {
            Finding(level: .problem, subject: subject, detail: detail, remedy: remedy)
        }
    }

    static func findings(environment: Environment) -> [Finding] {
        var findings = platformFindings(environment: environment)
        guard let status = environment.musicStatus, let music = environment.music else {
            findings.append(.note("Music", "unavailable on this platform"))
            return findings
        }
        if let musicVersion = status.version() {
            findings.append(.ok("Music", "version \(musicVersion)"))
        } else {
            findings.append(
                .problem(
                    "Music", "the Music app was not found",
                    remedy:
                        "Music is part of macOS; verify that /System/Applications/Music.app is installed before using library commands."
                ))
        }
        findings += mediaFolderFindings(music.mediaFolder()?.standardizedFileURL, environment: environment)
        findings.append(permissionFinding(status.permission()))
        return findings
    }

    static func platformFindings(environment: Environment) -> [Finding] {
        var findings: [Finding] = [.ok("ilibrary", version)]
        #if compiler(>=6.4)
            findings.append(.ok("build toolchain", "Swift 6.4 or later"))
        #else
            findings.append(.ok("build toolchain", "Swift 6.x"))
        #endif
        #if os(macOS)
            let system = ProcessInfo.processInfo.operatingSystemVersion
            findings.append(.ok("macOS", "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"))
        #else
            findings.append(
                .note(
                    "platform",
                    "not macOS: conversion, file dates, and Music are unavailable; catalogs and copies work",
                    remedy:
                        "Run iLibrary on macOS 14 or later for import of lossless files, timestamps, add, and check --library."
                ))
        #endif
        findings.append(
            environment.converter == nil
                ? .note("conversion", "unavailable on this platform")
                : .ok("conversion", "Apple Lossless through AudioToolbox"))
        findings.append(
            environment.setDates == nil
                ? .note("file dates", "creation dates cannot be set on this platform")
                : .ok("file dates", "creation and modification dates can be set"))
        return findings
    }

    static func mediaFolderFindings(_ media: URL?, environment: Environment) -> [Finding] {
        guard let media else {
            return [
                .problem(
                    "media folder", "Music's preferences name no media folder",
                    remedy:
                        "Open Music once, so that it creates its library and media folder; then run ilibrary doctor again."
                )
            ]
        }
        guard pathKind(media) == .directory else {
            return [
                .problem(
                    "media folder", "\(media.path) does not exist",
                    remedy: "Open Music and choose its media folder in Settings, Files; then run ilibrary doctor again."
                )
            ]
        }
        var findings: [Finding] = [.ok("media folder", media.path)]
        guard let available = environment.availableCapacity(media) else {
            findings.append(
                .note(
                    "free space", "could not be determined",
                    remedy: "Check the media volume in Finder before importing or adding files."))
            return findings
        }
        let gigabytes = Double(available) / 1_000_000_000
        let detail = String(format: "%.1f GB available on the media folder's volume", gigabytes)
        findings.append(
            gigabytes < 1
                ? .problem(
                    "free space", detail, remedy: "Free space on the volume of the media folder before adding albums.")
                : .ok("free space", detail))
        return findings
    }

    static func permissionFinding(_ permission: String) -> Finding {
        switch permission {
        case "permitted":
            .ok("Automation", "this terminal may control Music")
        case "denied":
            .problem(
                "Automation", "this terminal may not control Music",
                remedy:
                    "Allow it in System Settings, Privacy & Security, Automation, under your terminal app, by turning on Music."
            )
        case "not determined":
            .note(
                "Automation", "not decided yet",
                remedy: "macOS asks the first time ilibrary add or check --library controls Music; choose OK.")
        case "Music not running":
            .note(
                "Automation", "cannot be determined while Music is not running; doctor does not launch it",
                remedy: "Open Music and run ilibrary doctor again to see the permission.")
        default:
            .note(
                "Automation", "could not be determined",
                remedy: "Check System Settings, Privacy & Security, Automation, and run doctor again.")
        }
    }

    static func run(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        _ = try syntax.parse(arguments)
        let findings = findings(environment: environment)
        for finding in findings {
            let mark = finding.level.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
            console.print("\(mark) \(finding.subject): \(finding.detail)")
            if let remedy = finding.remedy { console.print("        \(remedy)") }
        }
        let problems = findings.filter { $0.level == .problem }.count
        console.print(problems == 0 ? "No problems found." : "\(problems) problem(s) found.")
        return problems == 0 ? 0 : 1
    }
}
