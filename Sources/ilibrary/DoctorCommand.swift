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
    }

    static func findings(environment: Environment) -> [Finding] {
        var findings: [Finding] = []
        let system = ProcessInfo.processInfo.operatingSystemVersion
        findings.append(Finding(level: .ok, subject: "ilibrary", detail: version))
        #if compiler(>=6.4)
            findings.append(Finding(level: .ok, subject: "build toolchain", detail: "Swift 6.4 or later"))
        #else
            findings.append(Finding(level: .ok, subject: "build toolchain", detail: "Swift 6.x"))
        #endif
        #if os(macOS)
            findings.append(
                Finding(
                    level: .ok, subject: "macOS",
                    detail: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"))
        #else
            findings.append(
                Finding(
                    level: .note, subject: "platform",
                    detail: "not macOS: conversion, file dates, and Music are unavailable; catalogs and copies work",
                    remedy:
                        "Run iLibrary on macOS 14 or later for import of lossless files, timestamps, add, and check --library."
                ))
        #endif
        findings.append(
            environment.converter == nil
                ? Finding(level: .note, subject: "conversion", detail: "unavailable on this platform")
                : Finding(level: .ok, subject: "conversion", detail: "Apple Lossless through AudioToolbox"))
        findings.append(
            environment.setDates == nil
                ? Finding(level: .note, subject: "file dates", detail: "creation dates cannot be set on this platform")
                : Finding(level: .ok, subject: "file dates", detail: "creation and modification dates can be set"))

        guard let status = environment.musicStatus, let music = environment.music else {
            findings.append(Finding(level: .note, subject: "Music", detail: "unavailable on this platform"))
            return findings
        }
        if let musicVersion = status.version() {
            findings.append(Finding(level: .ok, subject: "Music", detail: "version \(musicVersion)"))
        } else {
            findings.append(
                Finding(
                    level: .problem, subject: "Music", detail: "the Music app was not found",
                    remedy:
                        "Music is part of macOS; verify that /System/Applications/Music.app is installed before using library commands."
                ))
        }
        if let media = music.mediaFolder()?.standardizedFileURL {
            if pathKind(media) == .directory {
                findings.append(Finding(level: .ok, subject: "media folder", detail: media.path))
                if let available = environment.availableCapacity(media) {
                    let gigabytes = Double(available) / 1_000_000_000
                    findings.append(
                        Finding(
                            level: gigabytes < 1 ? .problem : .ok, subject: "free space",
                            detail: String(format: "%.1f GB available on the media folder's volume", gigabytes),
                            remedy: gigabytes < 1
                                ? "Free space on the volume of the media folder before adding albums." : nil))
                } else {
                    findings.append(
                        Finding(
                            level: .note, subject: "free space", detail: "could not be determined",
                            remedy: "Check the media volume in Finder before importing or adding files."))
                }
            } else {
                findings.append(
                    Finding(
                        level: .problem, subject: "media folder", detail: "\(media.path) does not exist",
                        remedy:
                            "Open Music and choose its media folder in Settings, Files; then run ilibrary doctor again."
                    ))
            }
        } else {
            findings.append(
                Finding(
                    level: .problem, subject: "media folder", detail: "Music's preferences name no media folder",
                    remedy:
                        "Open Music once, so that it creates its library and media folder; then run ilibrary doctor again."
                ))
        }
        switch status.permission() {
        case "permitted":
            findings.append(Finding(level: .ok, subject: "Automation", detail: "this terminal may control Music"))
        case "denied":
            findings.append(
                Finding(
                    level: .problem, subject: "Automation", detail: "this terminal may not control Music",
                    remedy:
                        "Allow it in System Settings, Privacy & Security, Automation, under your terminal app, by turning on Music."
                ))
        case "not determined":
            findings.append(
                Finding(
                    level: .note, subject: "Automation", detail: "not decided yet",
                    remedy: "macOS asks the first time ilibrary add or check --library controls Music; choose OK."))
        case "Music not running":
            findings.append(
                Finding(
                    level: .note, subject: "Automation",
                    detail: "cannot be determined while Music is not running; doctor does not launch it",
                    remedy: "Open Music and run ilibrary doctor again to see the permission."))
        default:
            findings.append(
                Finding(
                    level: .note, subject: "Automation", detail: "could not be determined",
                    remedy: "Check System Settings, Privacy & Security, Automation, and run doctor again."))
        }
        return findings
    }

    static func run(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        _ = try syntax.parse(arguments)
        let findings = findings(environment: environment)
        for finding in findings {
            let mark = ["ok": "ok     ", "note": "note   ", "problem": "problem"][finding.level.rawValue]!
            console.print("\(mark) \(finding.subject): \(finding.detail)")
            if let remedy = finding.remedy { console.print("        \(remedy)") }
        }
        let problems = findings.filter { $0.level == .problem }.count
        console.print(problems == 0 ? "No problems found." : "\(problems) problem(s) found.")
        return problems == 0 ? 0 : 1
    }
}
