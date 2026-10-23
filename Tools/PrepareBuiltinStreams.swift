import Foundation
import Darwin
import CryptoKit

@main
struct PrepareBuiltinStreams {
    static func main() {
        umask(0o077)
        // Keep even Foundation's file/JSON errors out of build logs: they may include private input.
        do {
            guard CommandLine.arguments.count == 3 else { throw BuiltinStreams.ConfigurationError.invalid }
            let environment = ProcessInfo.processInfo.environment
            let keys = ["KISS_STREAM_URL", "CNR_STREAM_URL"]
            let data: Data
            if keys.contains(where: { environment[$0] != nil }) || environment["GITHUB_ACTIONS"] == "true" {
                guard keys.allSatisfy({ !(environment[$0] ?? "").isEmpty }) else {
                    fputs("Missing KISS_STREAM_URL or CNR_STREAM_URL. Both must be configured.\n", stderr)
                    exit(1)
                }
                data = try JSONSerialization.data(withJSONObject: [
                    "builtin.kiss": [environment[keys[0]]!],
                    "builtin.music-radio": [environment[keys[1]]!]
                ], options: [.sortedKeys, .withoutEscapingSlashes])
            } else {
                data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            }
            let streams = try BuiltinStreams.decode(data)
            let key = SymmetricKey(size: .bits256)
            let keyBytes = key.withUnsafeBytes { Array($0) }
            let mask = SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }
            let order = Array(UInt8(0)..<UInt8(32)).shuffled()
            let masked = order.enumerated().map { keyBytes[Int($0.element)] ^ mask[$0.offset] }
            let sealed = try AES.GCM.seal(data, using: key, authenticating: BuiltinStreams.envelopeHeader)
            guard let combined = sealed.combined else { throw BuiltinStreams.ConfigurationError.invalid }
            let encrypted = BuiltinStreams.envelopeHeader + combined
            let restored = BuiltinStreams.restoreKey(masked, mask, order)
            guard try BuiltinStreams.open(encrypted, key: restored) == streams else { throw BuiltinStreams.ConfigurationError.invalid }
            let source = """
            // Generated for this build only. Do not commit or package this source.
            import Foundation
            enum BuiltinStreamKey {
                static func material() -> Data {
                    BuiltinStreams.restoreKey(\(masked), \(mask), \(order))
                }
            }

            """
            let destination = URL(fileURLWithPath: CommandLine.arguments[2])
            let manager = FileManager.default
            let names: Set<String> = ["builtin-streams.bin", "BuiltinStreamKey.swift"]
            let exists = manager.fileExists(atPath: destination.path)
            if exists {
                // This directory belongs exclusively to the generator. Never replace unrelated files.
                guard Set(try manager.contentsOfDirectory(atPath: destination.path)).isSubset(of: names) else {
                    throw BuiltinStreams.ConfigurationError.invalid
                }
            }
            let parent = destination.deletingLastPathComponent()
            try manager.createDirectory(at: parent, withIntermediateDirectories: true)
            let stage = parent.appendingPathComponent(".RadioBar-streams-" + UUID().uuidString)
            try manager.createDirectory(at: stage, withIntermediateDirectories: false)
            defer { try? manager.removeItem(at: stage) }
            let resource = stage.appendingPathComponent("builtin-streams.bin")
            try encrypted.write(to: resource)
            try Data(source.utf8).write(to: stage.appendingPathComponent("BuiltinStreamKey.swift"))
            // Readable for other users once copied into an installed App; key source remains 0600.
            try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: resource.path)
            // Commit the pair together. Failed validation or generation preserves the prior pair.
            let status = exists ? renamex_np(stage.path, destination.path, UInt32(RENAME_SWAP)) : rename(stage.path, destination.path)
            guard status == 0 else { throw BuiltinStreams.ConfigurationError.invalid }
        } catch {
            fputs("Cannot prepare built-in streams. Check both Secrets or private/builtin-streams.json; existing output kept.\n", stderr)
            exit(1)
        }
    }
}
