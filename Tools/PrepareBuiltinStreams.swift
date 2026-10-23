import Foundation
import Darwin

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
            _ = try BuiltinStreams.decode(data)
            let destination = URL(fileURLWithPath: CommandLine.arguments[2])
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Copy original bytes after validation; never normalize the query or drop parameters.
            try data.write(to: destination, options: .atomic)
            // Bundled resources must remain readable when an administrator installs for other users.
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)
        } catch {
            fputs("Cannot prepare built-in streams. Check both Secrets or private/builtin-streams.json; existing output kept.\n", stderr)
            exit(1)
        }
    }
}
