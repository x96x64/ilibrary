import Foundation

/// A calendar date in the proleptic Gregorian calendar, written `YYYY-MM-DD`.
public struct ReleaseDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Parses exactly `YYYY-MM-DD` with a valid month and day; returns nil otherwise.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
            (1...ReleaseDate.daysInMonth(year: year, month: month)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Reads the date part of a tag value such as `1958-08-29T00:00:00Z` or `1958-08-29`.
    /// A year alone is not a date and returns nil.
    public init?(tagValue: String) {
        self.init(String(tagValue.prefix(10)))
        let rest = tagValue.dropFirst(10)
        guard rest.isEmpty || rest.hasPrefix("T") else { return nil }
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    public static func < (lhs: ReleaseDate, rhs: ReleaseDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The value written to files: midnight UTC of the date, as Music writes release dates.
    public var tagValue: String { "\(description)T00:00:00Z" }

    /// The first instant of the date in a time zone. Where the zone skips midnight, such as São Paulo on
    /// 2018-11-04, this is the first existing time of the day, and `isMidnight` is false so that it can be reported.
    public func localStart(in zone: TimeZone) -> (date: Date, isMidnight: Bool) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        let start = calendar.startOfDay(for: noon)
        let components = calendar.dateComponents([.hour, .minute, .second], from: start)
        return (start, components.hour == 0 && components.minute == 0 && components.second == 0)
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
