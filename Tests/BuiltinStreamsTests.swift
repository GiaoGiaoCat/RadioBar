import Foundation
import CryptoKit

@main
struct BuiltinStreamsTests {
    static func main() throws {
        func check(_ condition: Bool) { precondition(condition) }
        let manager = FileManager.default
        let root = URL(fileURLWithPath: CommandLine.arguments[2])
        let input = root.appendingPathComponent("input.json")
        let output = root.appendingPathComponent("Generated")
        let kiss = "https://fixture.invalid/kiss.m3u8?token=FAKE%2Bvalue&x=a+b&x=%2F&expires=1"
        let cnr = "https://fixture.invalid/cnr.m3u8?empty=&encoded=%26%3D"
        let payload = ["builtin.kiss": [kiss], "builtin.music-radio": [cnr]]
        func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) }
        let valid = try data(payload)
        let decoded = try BuiltinStreams.decode(valid)
        check(decoded["builtin.kiss"]?.first?.absoluteString == kiss)
        check(decoded["builtin.music-radio"]?.first?.absoluteString == cnr)
        var ordered = payload
        ordered["builtin.kiss"] = [kiss, cnr]
        check(try BuiltinStreams.decode(data(ordered))["builtin.kiss"]?.map(\.absoluteString) == [kiss, cnr])
        var rejected = 0
        func rejects(_ bytes: Data) {
            do { _ = try BuiltinStreams.decode(bytes); fatalError("Invalid built-in streams accepted") }
            catch { check(error is BuiltinStreams.ConfigurationError); rejected += 1 }
        }
        rejects(Data("{ broken".utf8))
        rejects(Data(repeating: 32, count: 65_537))
        rejects(try data(["builtin.kiss": [kiss]]))
        rejects(try data(payload.merging(["unknown": [cnr]]) { _, new in new }))
        for urls in [[], Array(repeating: kiss, count: 21), ["file:///tmp/a"], ["https:///missing"],
                     ["https://user:pass@fixture.invalid/a"], ["https://fixture.invalid/a#fragment"],
                     ["https://fixture.invalid/a b"], ["https://fixture.invalid/a\n"],
                     ["https://fixture.invalid/a\u{0}"], [String(repeating: "a", count: 8193)]] {
            rejects(try data(["builtin.kiss": urls, "builtin.music-radio": [cnr]]))
        }
        let key = Data((0..<32).map(UInt8.init))
        let mask = [UInt8](repeating: 0xA5, count: 32)
        let order = Array((UInt8(0)..<UInt8(32)).reversed())
        let masked = order.map { key[Int($0)] ^ 0xA5 }
        check(BuiltinStreams.restoreKey(masked, mask, order) == key)
        check(BuiltinStreams.restoreKey(masked, mask, [UInt8](repeating: 0, count: 32)).isEmpty)
        check(BuiltinStreams.restoreKey([], mask, order).isEmpty)
        func seal(_ plaintext: Data) throws -> Data {
            BuiltinStreams.envelopeHeader + (try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), authenticating: BuiltinStreams.envelopeHeader).combined!)
        }
        let encrypted = try seal(valid)
        check(try BuiltinStreams.open(encrypted, key: key) == decoded)
        check(try BuiltinStreams.open(seal(data(ordered)), key: key)["builtin.kiss"]?.map(\.absoluteString) == [kiss, cnr])
        check(encrypted != (try seal(valid))) // Fresh nonce for the same input.
        func rejectsEncrypted(_ bytes: Data, using material: Data = key) {
            do { _ = try BuiltinStreams.open(bytes, key: material); fatalError("Invalid encrypted resource accepted") }
            catch { check(error is BuiltinStreams.ConfigurationError) }
        }
        rejectsEncrypted(valid) // Never fall back to plaintext.
        rejectsEncrypted(encrypted, using: Data(repeating: 99, count: 32))
        rejectsEncrypted(encrypted, using: Data())
        rejectsEncrypted(try seal(Data("broken JSON".utf8)))
        rejectsEncrypted(Data(repeating: 0, count: 65_569))
        for index in [0, 3, 4, 16, encrypted.count - 1] {
            var tampered = encrypted; tampered[index] ^= 1; rejectsEncrypted(tampered)
        }
        for count in [0, 4, 16, 31, encrypted.count - 1] { rejectsEncrypted(encrypted.prefix(count)) }
        let resource = root.appendingPathComponent("fixture.bin")
        try encrypted.write(to: resource)
        check(BuiltinStreams.load(from: resource, key: key) == decoded)
        check(BuiltinStreams.load(from: nil, key: key).isEmpty)
        check(BuiltinStreams.load(from: root.appendingPathComponent("missing"), key: key).isEmpty)
        check(BuiltinStreams.load(from: resource, key: Data()).isEmpty)
        try valid.write(to: input)
        check(BuiltinStreams.load(from: input, key: key).isEmpty)
        // Build input selection is exercised through the real helper executable, without touching private/.
        let helper = CommandLine.arguments[1]
        var base = ProcessInfo.processInfo.environment
        for key in ["KISS_STREAM_URL", "CNR_STREAM_URL", "GITHUB_ACTIONS"] { base.removeValue(forKey: key) }
        var runs = 0
        func prepare(_ overrides: [String: String] = [:], succeeds: Bool) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: helper)
            process.arguments = [input.path, output.path]
            process.environment = base.merging(overrides) { _, new in new }
            let log = root.appendingPathComponent("log")
            manager.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log)
            process.standardOutput = handle; process.standardError = handle
            try process.run(); process.waitUntilExit(); try handle.close()
            check((process.terminationStatus == 0) == succeeds)
            let text = try String(contentsOf: log, encoding: .utf8)
            check(!text.contains("fixture.invalid") && !text.contains("PRIVATE_SENTINEL"))
            runs += 1
        }
        func pair() throws -> [Data] {
            try ["builtin-streams.bin", "BuiltinStreamKey.swift"].map { try Data(contentsOf: output.appendingPathComponent($0)) }
        }
        try prepare(succeeds: true)
        let first = try pair()
        check(first.allSatisfy { !$0.contains(Data(kiss.utf8)) && !$0.contains(Data(cnr.utf8)) })
        let attrs = try manager.attributesOfItem(atPath: output.appendingPathComponent("builtin-streams.bin").path)
        check((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o644)
        let sourceAttrs = try manager.attributesOfItem(atPath: output.appendingPathComponent("BuiltinStreamKey.swift").path)
        check((sourceAttrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try prepare(succeeds: true)
        let second = try pair()
        check(second[0] != first[0] && second[1] != first[1])
        // Environment wins as a complete pair; never combine a partial Secret with the local file.
        try prepare(["KISS_STREAM_URL": cnr, "CNR_STREAM_URL": kiss], succeeds: true)
        let swapped = try pair()
        try manager.copyItem(at: output, to: root.appendingPathComponent("Swapped"))
        for overrides in [["KISS_STREAM_URL": kiss], ["KISS_STREAM_URL": "", "CNR_STREAM_URL": cnr],
                          ["KISS_STREAM_URL": "PRIVATE_SENTINEL invalid", "CNR_STREAM_URL": cnr],
                          ["GITHUB_ACTIONS": "true"], ["GITHUB_ACTIONS": "true", "CNR_STREAM_URL": cnr]] {
            try prepare(overrides, succeeds: false)
            check(try pair() == swapped)
        }
        try prepare(["GITHUB_ACTIONS": "true", "KISS_STREAM_URL": kiss, "CNR_STREAM_URL": cnr], succeeds: true)
        let actionPair = try pair()
        try Data("PRIVATE_SENTINEL broken JSON".utf8).write(to: input)
        try prepare(succeeds: false)
        check(try pair() == actionPair)
        try manager.removeItem(at: input)
        try prepare(succeeds: false)
        check(try pair() == actionPair)
        try valid.write(to: input)
        // Unrelated output contents must not be replaced or removed.
        let sentinel = output.appendingPathComponent("unrelated")
        try Data("keep".utf8).write(to: sentinel)
        try prepare(succeeds: false)
        check(try pair() == actionPair && Data(contentsOf: sentinel) == Data("keep".utf8))
        try manager.removeItem(at: sentinel)
        try prepare(succeeds: true)
        print("PASS: built-in streams: exact queries/order, \(rejected) invalid payloads, AES-GCM tamper/wrong-key/truncation rejection, randomized builds, \(runs) input selection/log/atomic pair cases")
    }
}
