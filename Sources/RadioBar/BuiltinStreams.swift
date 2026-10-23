import Foundation
import CryptoKit

/// Plaintext is a build input only. Bundled streams use authenticated encryption.
enum BuiltinStreams {
    static let ids: Set<String> = ["builtin.kiss", "builtin.music-radio"]
    static let envelopeHeader = Data([0x52, 0x42, 0x53, 0x01])
    enum ConfigurationError: Error { case invalid }

    static func decode(_ data: Data) throws -> [String: [URL]] {
        guard data.count <= 65_536,
              let entries = try? JSONDecoder().decode([String: [String]].self, from: data),
              Set(entries.keys) == ids else { throw ConfigurationError.invalid }
        var result: [String: [URL]] = [:]
        for (id, strings) in entries {
            guard (1...20).contains(strings.count) else { throw ConfigurationError.invalid }
            result[id] = try strings.map { string in
                guard string.utf8.count <= 8192,
                      !string.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
                      let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      let host = url.host, !host.isEmpty,
                      url.user == nil, url.password == nil, url.fragment == nil else {
                    throw ConfigurationError.invalid
                }
                return url
            }
        }
        return result
    }

    static func open(_ data: Data, key: Data) throws -> [String: [URL]] {
        do {
            guard key.count == 32, (32...65_568).contains(data.count),
                  data.starts(with: envelopeHeader) else { throw ConfigurationError.invalid }
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(envelopeHeader.count))
            let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: envelopeHeader)
            return try decode(plaintext)
        } catch { throw ConfigurationError.invalid }
    }

    // This raises the cost of extracting a package's key; it is not a secret from a debugger.
    // Keep reconstruction out of the generated call site to avoid folding it into a key literal.
    @inline(never)
    static func restoreKey(_ masked: [UInt8], _ mask: [UInt8], _ order: [UInt8]) -> Data {
        guard masked.count == 32, mask.count == 32, order.count == 32,
              Set(order) == Set(UInt8(0)..<UInt8(32)) else { return Data() }
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in 0..<32 { bytes[Int(order[index])] = masked[index] ^ mask[index] }
        return Data(bytes)
    }

    static func load(from file: URL?, key: Data) -> [String: [URL]] {
        guard let file, let data = try? Data(contentsOf: file), let streams = try? open(data, key: key) else { return [:] }
        return streams
    }

    static let bundled: [String: [URL]] = {
        #if RADIOBAR_STREAM_TOOL
        return [:]
        #elseif RADIOBAR_TESTING && !RADIOBAR_LIVE_STREAMS
        // Offline tests and previews must neither need private inputs nor play real built-in streams.
        return ["builtin.kiss": [URL(string: "https://fixture.invalid/kiss.m3u8")!],
                "builtin.music-radio": [URL(string: "https://fixture.invalid/cnr.m3u8")!]]
        #else
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return load(from: bundle.url(forResource: "builtin-streams", withExtension: "bin"), key: BuiltinStreamKey.material())
        #endif
    }()
}
