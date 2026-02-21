import Foundation

public enum ChatDateMode: String, Codable, Sendable {
    case day
    case week
    case month
}

public enum DateScope {
    public static func ymdLocal(_ date: Date, calendar: Calendar = .current) -> String {
        var calendar = calendar
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = String(format: "%04d", parts.year ?? 0)
        let month = String(format: "%02d", parts.month ?? 1)
        let day = String(format: "%02d", parts.day ?? 1)
        return "\(year)-\(month)-\(day)"
    }

    public static func localNoon(_ date: Date, calendar: Calendar = .current) -> Date {
        var calendar = calendar
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: DateComponents(
            year: parts.year,
            month: parts.month,
            day: parts.day,
            hour: 12,
            minute: 0,
            second: 0
        )) ?? date
    }

    public static func timezoneOffsetString(
        referenceDate: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let seconds = timeZone.secondsFromGMT(for: referenceDate)
        let totalMinutes = seconds / 60
        let sign = totalMinutes >= 0 ? "+" : "-"
        let absoluteMinutes = abs(totalMinutes)
        let hours = absoluteMinutes / 60
        let minutes = absoluteMinutes % 60
        return String(format: "%@%02d:%02d", sign, hours, minutes)
    }

    public static func monthStart(_ date: Date, calendar: Calendar = .current) -> Date {
        var calendar = calendar
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1)) ?? date
    }

    public static func weekStartMonday(_ date: Date, calendar: Calendar = .current) -> Date {
        var calendar = calendar
        calendar.timeZone = .current
        let weekday = calendar.component(.weekday, from: date)
        let mondayBasedDistance = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -mondayBasedDistance, to: date) ?? date
    }
}
