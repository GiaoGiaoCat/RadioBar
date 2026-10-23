import Foundation

/// Compatibility for unfinished v1 local transactions and previously confirmed applications.
/// New v2 publication never applies remote data or creates these transactions.
@MainActor
final class StationConfigurationTransaction {
    private struct Journal: Codable {
        let schemaVersion: Int
        let original: Data
        let originalPreferences: [String: Data]
        let candidate: SharedStationConfiguration
        let candidatePreferences: [String: Data]
    }

    let file: URL
    let journalFile: URL
    private let defaults: UserDefaults
    private let writeDocument: (Data, URL) throws -> Void

    init(file: URL, defaults: UserDefaults,
         writeDocument: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.file = file; self.defaults = defaults; self.writeDocument = writeDocument
        journalFile = file.deletingLastPathComponent().appendingPathComponent("station-sync-transaction.json")
    }

    private static func preferenceBytes(_ defaults: UserDefaults) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for key in SharedStationPreferences.managedKeys {
            if let value = defaults.object(forKey: key) {
                result[key] = try PropertyListSerialization.data(fromPropertyList: [value], format: .binary, options: 0)
            }
        }
        return result
    }

    private static func targetBytes(_ preferences: SharedStationPreferences) throws -> [String: Data] {
        var values: [String: Any] = ["stationOrderIDs": preferences.orderIDs,
                                   "stationVisibilityOverrides": preferences.visibilityOverrides,
                                   "hiddenStationIDs": preferences.visibilityOverrides.filter { !$0.value }.keys.sorted()]
        values["defaultStation"] = preferences.defaultStation
        return try values.mapValues { try PropertyListSerialization.data(fromPropertyList: [$0], format: .binary, options: 0) }
    }

    private static func sameValue(_ left: Data?, _ right: Data?) throws -> Bool {
        if left == right { return true }
        guard let left, let right else { return false }
        let a = try PropertyListSerialization.propertyList(from: left, format: nil)
        let b = try PropertyListSerialization.propertyList(from: right, format: nil)
        // Binary plist dictionaries need not have a stable serialization order.
        return (a as? NSObject)?.isEqual(b) == true
    }

    private static func samePreferences(_ left: [String: Data], _ right: [String: Data]) throws -> Bool {
        guard Set(left.keys) == Set(right.keys) else { return false }
        for key in left.keys where try !sameValue(left[key], right[key]) { return false }
        return true
    }

    private func restorePreferences(_ values: [String: Data]) throws {
        guard Set(values.keys).isSubset(of: Set(SharedStationPreferences.managedKeys)) else {
            throw StationSharingError.invalidPreferences
        }
        // Decode everything before changing even one key.
        var decoded: [String: Any] = [:]
        for (key, data) in values {
            guard let array = try PropertyListSerialization.propertyList(from: data, format: nil) as? [Any], array.count == 1 else {
                throw StationSharingError.invalidPreferences
            }
            decoded[key] = array[0]
        }
        for key in SharedStationPreferences.managedKeys {
            if let value = decoded[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        // A transaction explicitly needs the preference write flushed before removing its journal.
        guard defaults.synchronize() else { throw StationSharingError.unavailable }
    }

    private func coordinated<T>(_ operation: (URL) throws -> T) throws -> T {
        var result: Result<T, Error> = .failure(StationSharingError.unavailable)
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &error) { url in
            result = Result { try operation(url) }
        }
        if let error { throw error }
        return try result.get()
    }

    /// Phase 1: validate/check conflicts, back up exact originals, then persist a recovery intent.
    /// Exposed separately so crash recovery can be tested at each durable boundary.
    func prepare(_ candidate: SharedStationConfiguration, expecting expected: SharedStationConfiguration, validatingSource: () throws -> Void = {}) throws {
        let candidate = try candidate.normalized()
        let target = try Self.targetBytes(candidate.preferences)
        try coordinated { url in
            guard !FileManager.default.fileExists(atPath: journalFile.path) else { throw StationSharingError.changedLocally }
            let original = try StationSyncFiles.readCoordinatedContents(url, maximumBytes: 1_048_576)
            let originalPreferences = try Self.preferenceBytes(defaults)
            guard original == expected.document.data,
                  try SharedStationPreferences.capture(from: defaults) == expected.preferences else {
                throw StationSharingError.changedLocally
            }
            try validatingSource()
            let id = UUID().uuidString.lowercased()
            let directory = url.deletingLastPathComponent()
            try original.write(to: directory.appendingPathComponent("stations.backup-sync-\(id).json"), options: .withoutOverwriting)
            let backup = try PropertyListEncoder().encode(originalPreferences)
            try backup.write(to: directory.appendingPathComponent("stations.preferences.backup-sync-\(id).plist"), options: .withoutOverwriting)
            // Cooperative coordination is not an absolute lock against external editors.
            guard try Data(contentsOf: url) == original, try Self.samePreferences(Self.preferenceBytes(defaults), originalPreferences) else {
                throw StationSharingError.changedLocally
            }
            let journal = Journal(schemaVersion: 1, original: original, originalPreferences: originalPreferences,
                                  candidate: candidate, candidatePreferences: target)
            let bytes = try JSONEncoder().encode(journal)
            guard bytes.count <= 8 * 1_048_576 else { throw StationSharingError.invalidDocument }
            try bytes.write(to: journalFile, options: .withoutOverwriting)
        }
    }

    private func journal() throws -> Journal {
        let data = try StationSyncFiles.read(journalFile, maximumBytes: 8 * 1_048_576)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard root?["schemaVersion"] as? Int == 1 else { throw StationSharingError.unsupportedVersion }
        let journal = try JSONDecoder().decode(Journal.self, from: data)
        _ = try StationDocument(data: journal.original)
        try journal.candidate.validate()
        guard try journal.candidate.normalized() == journal.candidate,
              try Self.samePreferences(Self.targetBytes(journal.candidate.preferences), journal.candidatePreferences),
              Set(journal.originalPreferences.keys).isSubset(of: Set(SharedStationPreferences.managedKeys)) else {
            throw StationSharingError.invalidPreferences
        }
        return journal
    }

    private func checkUnchanged(_ journal: Journal, at url: URL) throws {
        let current = try StationSyncFiles.readCoordinatedContents(url, maximumBytes: 1_048_576)
        guard current == journal.original || current == journal.candidate.document.data else { throw StationSharingError.changedLocally }
        let preferences = try Self.preferenceBytes(defaults)
        // A crash may leave an arbitrary prefix of these keys applied.
        for key in SharedStationPreferences.managedKeys {
            guard try Self.sameValue(preferences[key], journal.originalPreferences[key]) || Self.sameValue(preferences[key], journal.candidatePreferences[key]) else {
                throw StationSharingError.changedLocally
            }
        }
    }

    /// Roll forward a prepared/interrupted operation; external edits always stop recovery.
    /// The returned complete candidate is the only value the future UI adapter may publish.
    @discardableResult func recover() throws -> SharedStationConfiguration? {
        guard FileManager.default.fileExists(atPath: journalFile.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: journalFile.path)) != nil else { return nil }
        return try coordinated { url in
            let journal = try self.journal()
            try checkUnchanged(journal, at: url)
            if try Data(contentsOf: url) != journal.candidate.document.data {
                try writeDocument(journal.candidate.document.data, url)
            }
            try restorePreferences(journal.candidatePreferences)
            try FileManager.default.removeItem(at: journalFile)
            return journal.candidate
        }
    }

    @discardableResult func apply(_ candidate: SharedStationConfiguration, expecting expected: SharedStationConfiguration, validatingSource: () throws -> Void = {}) throws -> SharedStationConfiguration {
        try prepare(candidate, expecting: expected, validatingSource: validatingSource)
        do {
            guard let applied = try recover() else { throw StationSharingError.unavailable }
            return applied
        } catch {
            // Normal write failure rolls back. A process crash leaves the journal for recovery.
            // If rollback also fails, retain the journal + backups and report failure.
            try? coordinated { url in
                let journal = try self.journal()
                try checkUnchanged(journal, at: url)
                if try Data(contentsOf: url) != journal.original { try journal.original.write(to: url, options: .atomic) }
                try restorePreferences(journal.originalPreferences)
                try FileManager.default.removeItem(at: journalFile)
            }
            throw error
        }
    }
}
