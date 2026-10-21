// The interface profile: a reviewed description of how one Music version in one locale exposes the Songs and
// Recently Added views. The repository ships no profile, and no default exists for any field. Decoding is strict:
// an unknown key, a missing required field, or an empty identifier is refused.
import Foundation

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private func rejectUnknownKeys(_ decoder: Decoder, allowed: Set<String>) throws {
    let container = try decoder.container(keyedBy: AnyKey.self)
    if let unknown = container.allKeys.map(\.stringValue).filter({ !allowed.contains($0) }).sorted().first {
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "unknown key '\(unknown)'"))
    }
}

/// Matches one element by role, optional subrole, optional identifier, and an optional label that must equal the
/// element's title or description exactly.
struct ElementRule: Codable, Equatable, Sendable {
    var role: String
    var subrole: String?
    var identifier: String?
    var label: String?

    private enum CodingKeys: String, CodingKey { case role, subrole, identifier, label }

    init(role: String, subrole: String? = nil, identifier: String? = nil, label: String? = nil) {
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.label = label
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: ["role", "subrole", "identifier", "label"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        role = try values.decode(String.self, forKey: .role)
        subrole = try values.decodeIfPresent(String.self, forKey: .subrole)
        identifier = try values.decodeIfPresent(String.self, forKey: .identifier)
        label = try values.decodeIfPresent(String.self, forKey: .label)
    }
}

struct ViewRule: Codable, Equatable, Sendable {
    var identification: ElementRule
    var containerRole: String
    var contentRole: String
    var rowsComplete: Bool
    var placeholder: ElementRule?
    var loading: ElementRule?

    private enum CodingKeys: String, CodingKey {
        case identification, containerRole, contentRole, rowsComplete, placeholder, loading
    }

    init(
        identification: ElementRule, containerRole: String, contentRole: String, rowsComplete: Bool,
        placeholder: ElementRule? = nil, loading: ElementRule? = nil
    ) {
        self.identification = identification
        self.containerRole = containerRole
        self.contentRole = contentRole
        self.rowsComplete = rowsComplete
        self.placeholder = placeholder
        self.loading = loading
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownKeys(
            decoder,
            allowed: ["identification", "containerRole", "contentRole", "rowsComplete", "placeholder", "loading"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        identification = try values.decode(ElementRule.self, forKey: .identification)
        containerRole = try values.decode(String.self, forKey: .containerRole)
        contentRole = try values.decode(String.self, forKey: .contentRole)
        rowsComplete = try values.decode(Bool.self, forKey: .rowsComplete)
        placeholder = try values.decodeIfPresent(ElementRule.self, forKey: .placeholder)
        loading = try values.decodeIfPresent(ElementRule.self, forKey: .loading)
    }
}

struct Stability: Codable, Equatable, Sendable {
    var minimumReadings: Int
    var minimumSpanSeconds: Double

    private enum CodingKeys: String, CodingKey { case minimumReadings, minimumSpanSeconds }

    init(minimumReadings: Int, minimumSpanSeconds: Double) {
        self.minimumReadings = minimumReadings
        self.minimumSpanSeconds = minimumSpanSeconds
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: ["minimumReadings", "minimumSpanSeconds"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        minimumReadings = try values.decode(Int.self, forKey: .minimumReadings)
        minimumSpanSeconds = try values.decode(Double.self, forKey: .minimumSpanSeconds)
    }

    /// Stability needs repeated readings over a positive span: one reading, or readings at one instant, cannot show
    /// that a view has settled.
    var isUsable: Bool { minimumReadings >= 2 && minimumSpanSeconds.isFinite && minimumSpanSeconds > 0 }
}

struct InterfaceProfile: Codable, Equatable, Sendable {
    var musicVersion: String
    var macOSVersion: String
    var locale: String
    var songs: ViewRule
    var recentlyAdded: ViewRule
    /// Optional in the file so that an omission is reported as an unqualified profile and never defaulted.
    var stability: Stability?

    private enum CodingKeys: String, CodingKey {
        case musicVersion, macOSVersion, locale, songs, recentlyAdded, stability
    }

    init(
        musicVersion: String, macOSVersion: String, locale: String, songs: ViewRule, recentlyAdded: ViewRule,
        stability: Stability?
    ) {
        self.musicVersion = musicVersion
        self.macOSVersion = macOSVersion
        self.locale = locale
        self.songs = songs
        self.recentlyAdded = recentlyAdded
        self.stability = stability
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownKeys(
            decoder, allowed: ["musicVersion", "macOSVersion", "locale", "songs", "recentlyAdded", "stability"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        musicVersion = try values.decode(String.self, forKey: .musicVersion)
        macOSVersion = try values.decode(String.self, forKey: .macOSVersion)
        locale = try values.decode(String.self, forKey: .locale)
        songs = try values.decode(ViewRule.self, forKey: .songs)
        recentlyAdded = try values.decode(ViewRule.self, forKey: .recentlyAdded)
        stability = try values.decodeIfPresent(Stability.self, forKey: .stability)
        guard !musicVersion.isEmpty, !macOSVersion.isEmpty, !locale.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "a version or locale is empty"))
        }
    }

    static func decode(from data: Data) throws -> InterfaceProfile {
        try JSONDecoder().decode(InterfaceProfile.self, from: data)
    }

    func rule(for view: ViewKind) -> ViewRule {
        switch view {
        case .songs: songs
        case .recentlyAdded: recentlyAdded
        }
    }

    /// The reasons for which this profile cannot be applied to the observed system.
    func qualificationFailures(for context: ObservedContext) -> [Reason] {
        var result: [Reason] = []
        if context.macOSVersion != macOSVersion || context.musicVersion != musicVersion || context.locale != locale {
            result.append(.versionMismatch)
        }
        if stability?.isUsable != true { result.append(.stabilityUnqualified) }
        return result
    }
}
