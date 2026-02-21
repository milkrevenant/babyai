import Foundation
import Testing
@testable import BabyAINativeCore

@Test func routeDriftEndpointsAreBlocked() async throws {
    let sessionStore = SessionStore(keychain: InMemoryKeychainStore())
    let api = BabyAIApiClient(
        environment: AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8080")!),
        sessionStore: sessionStore
    )

    do {
        _ = try await api.uploadPhotoFromDeviceRouteDrift()
        Issue.record("Expected route drift error")
    } catch let error as BabyAIError {
        #expect(error == .routeDrift(.photosUpload))
    }

    do {
        _ = try await api.quickLastFeedingRouteDrift()
        Issue.record("Expected route drift error")
    } catch let error as BabyAIError {
        #expect(error == .routeDrift(.quickLastFeeding))
    }
}
