import Foundation
import Darwin

/// Single Mac publisher. Wire format is fixed in docs/IPHONE_SYNC_SIMPLIFICATION.md.
struct StationPublication: Codable, Equatable {
    static let maximumBytes = 4 * 1_048_576
    static let maximumSequence: Int64 = 9_007_199_254_740_991
    let schemaVersion: Int
    let libraryID: UUID
    let sequence: Int64
    let publishedAt: Double
    let configuration: SharedStationConfiguration

    init(libraryID: UUID, sequence: Int64, configuration: SharedStationConfiguration, publishedAt: Double = Date().timeIntervalSince1970) throws {
        schemaVersion = 2; self.libraryID = libraryID; self.sequence = sequence
        self.publishedAt = publishedAt; self.configuration = configuration
        try validate()
    }
    func validate() throws {
        guard schemaVersion == 2 else { throw StationSharingError.unsupportedVersion }
        guard (1...Self.maximumSequence).contains(sequence), publishedAt.isFinite, publishedAt >= 0 else {
            throw StationSharingError.invalidDocument
        }
        try configuration.validate()
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw StationSharingError.invalidDocument }
        do {
            struct Version: Decodable { let schemaVersion: Int }
            guard try JSONDecoder().decode(Version.self, from: data).schemaVersion == 2 else { throw StationSharingError.unsupportedVersion }
            let value = try JSONDecoder().decode(Self.self, from: data)
            try value.validate()
            return value
        } catch let error as StationSharingError { throw error }
        catch { throw StationSharingError.invalidDocument }
    }
    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw StationSharingError.invalidDocument }
        return data
    }
}

/// File coordination is cooperative, never a cross-device lock.
enum StationSyncFiles {
    static let directoryName = "RadioBarSync"
    static let currentName = "current.json"

    static func read(_ file: URL, maximumBytes: Int) throws -> Data {
        var result: Result<Data, Error> = .failure(StationSharingError.unavailable)
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &error) { url in
            result = Result { try readCoordinatedContents(url, maximumBytes: maximumBytes) }
        }
        if let error { throw error }
        return try result.get()
    }
    static func readCoordinatedContents(_ url: URL, maximumBytes: Int) throws -> Data {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= maximumBytes else { throw StationSharingError.invalidDocument }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw StationSharingError.invalidDocument }
        return data
    }
    static func replace(_ data: Data, at file: URL) throws {
        var result: Result<Void, Error> = .failure(StationSharingError.unavailable)
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &error) { url in
            result = Result { try replaceCoordinatedContents(data, at: url) }
        }
        if let error { throw error }
        try result.get()
    }
    static func replaceCoordinatedContents(_ data: Data, at file: URL) throws {
        var info = stat()
        if lstat(file.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFREG else { throw StationSharingError.unavailable }
        } else if errno != ENOENT { throw StationSharingError.unavailable }
        try data.write(to: file, options: .atomic)
    }
    static func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw StationSharingError.unavailable }
    }
}
