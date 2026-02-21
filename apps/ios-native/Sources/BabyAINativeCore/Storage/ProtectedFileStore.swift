import Foundation

public struct ProtectedFileStore {
    private let fileManager: FileManager
    private let rootDirectory: URL?
    private let appDirectoryName: String

    public init(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil,
        appDirectoryName: String = "BabyAINativeCore"
    ) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory
        self.appDirectoryName = appDirectoryName
    }

    public func appSupportDirectory() throws -> URL {
        if let rootDirectory {
            let dir = rootDirectory.appendingPathComponent(appDirectoryName, isDirectory: true)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let dir = base.appendingPathComponent(appDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func read(fileName: String) throws -> Data? {
        let url = try appSupportDirectory().appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    public func write(_ data: Data, fileName: String) throws {
        let url = try appSupportDirectory().appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic])

        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }

    public func remove(fileName: String) throws {
        let url = try appSupportDirectory().appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
