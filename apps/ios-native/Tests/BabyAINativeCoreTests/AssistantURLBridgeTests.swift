import Foundation
import Testing
@testable import BabyAINativeCore

@Test func assistantURLParsingMatchesContract() async throws {
    let url = try #require(URL(string: "babyai://assistant/query?feature=formula&query=record%20formula&amount_ml=120&duration_min=15&diaper_type=PEE&source=siri"))

    let payload = AssistantURLBridge.parse(url: url)
    #expect(payload != nil)
    #expect(payload?.feature == "formula")
    #expect(payload?.query == "record formula")
    #expect(payload?.amountML == 120)
    #expect(payload?.durationMin == 15)
    #expect(payload?.diaperType == "PEE")
    #expect(payload?.source == "siri")
}

@Test func assistantURLRejectsUnknownPath() async throws {
    let invalid = try #require(URL(string: "babyai://assistant/unsupported?query=test"))
    let payload = AssistantURLBridge.parse(url: invalid)
    #expect(payload == nil)
}
