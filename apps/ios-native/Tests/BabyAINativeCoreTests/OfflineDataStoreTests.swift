import Foundation
import Testing
@testable import BabyAINativeCore

@Test func offlineStorePersistsCacheAndQueue() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    let fileStore = ProtectedFileStore(rootDirectory: tempRoot, appDirectoryName: "BabyAINativeCoreTests")
    let store = OfflineDataStore(fileStore: fileStore, fileName: "offline.json")

    try await store.writeCache(
        namespace: "daily_report",
        babyID: "baby-1",
        key: "2026-02-21",
        data: ["summary": .array([.string("ok")])]
    )

    let cached = try await store.readCache(namespace: "daily_report", babyID: "baby-1", key: "2026-02-21")
    #expect(cached?.object("summary") == nil)
    #expect(cached?["summary"]?.arrayValue?.count == 1)

    try await store.enqueueMutation(
        kind: .eventCreateClosed,
        payload: ["event_id": .string("local-1"), "type": .string("FORMULA")]
    )

    let queued = try await store.listMutations()
    #expect(queued.count == 1)
    #expect(queued.first?.kind == .eventCreateClosed)

    try await store.removeMutation(id: queued[0].id)
    let empty = try await store.listMutations()
    #expect(empty.isEmpty)
}
