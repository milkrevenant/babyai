import Foundation
import Testing
@testable import BabyAINativeCore

@Test func timezoneOffsetFormattingIsStable() async throws {
    let seoul = try #require(TimeZone(secondsFromGMT: 9 * 60 * 60))
    let value = DateScope.timezoneOffsetString(referenceDate: Date(timeIntervalSince1970: 0), timeZone: seoul)
    #expect(value == "+09:00")
}

@Test func weekStartIsMonday() async throws {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)

    let wednesday = try #require(formatter.date(from: "2026-02-18"))
    let monday = DateScope.weekStartMonday(wednesday, calendar: Calendar(identifier: .gregorian))

    #expect(formatter.string(from: monday) == "2026-02-16")
}
