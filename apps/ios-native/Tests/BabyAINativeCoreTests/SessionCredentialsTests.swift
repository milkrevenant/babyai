import Foundation
import Testing
@testable import BabyAINativeCore

@Test func googleIssuerIsDetectedFromJWT() async throws {
    let payload = #"{"iss":"accounts.google.com","sub":"u-1"}"#
    let base64 = Data(payload.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    let token = "h.\(base64).s"

    let credentials = SessionCredentials(bearerToken: token)
    #expect(credentials.tokenProvider == "google")
    #expect(credentials.isGoogleLinked)
}
