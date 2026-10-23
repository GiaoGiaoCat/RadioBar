import Foundation

/// Development-only: publish the same release text used by About, inside signed feeds.
@main
struct PrepareUpdateNotes {
    @MainActor static func main() throws {
        let info = NSDictionary(contentsOfFile: "Resources/Info.plist")!
        let version = info["CFBundleShortVersionString"] as! String
        guard let note = RadioReleaseNotes.entries.first, note.version == version, !note.changes.isEmpty else {
            throw NSError(domain: "RadioBar.ReleaseNotes", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Latest bundled release notes must match Info.plist"])
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let base = try String(contentsOf: directory.appendingPathComponent("appcast.xml"), encoding: .utf8)
            .replacingOccurrences(of: #"<!-- sparkle-signatures:[\s\S]*?-->"#, with: "", options: .regularExpression)
        guard base.components(separatedBy: "<item>").count == 2, !base.contains("<description") else {
            throw NSError(domain: "RadioBar.ReleaseNotes", code: 2)
        }
        for (suffix, language) in [("zh-Hans", AppLanguage.chinese), ("zh-Hant", .traditionalChinese), ("en", .english)] {
            let heading = RadioText("本次更新", "What's New").value(language)
            let text = "\(heading) · \(version)\n\n" + note.changes.map { "• " + $0.value(language) }.joined(separator: "\n\n")
            let escaped = text.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            let feed = base.replacingOccurrences(of: "<item>", with: "<item>\n<description sparkle:format=\"plain-text\">\(escaped)</description>")
            try feed.write(to: directory.appendingPathComponent("appcast-\(suffix).xml"), atomically: true, encoding: .utf8)
            // Existing clients keep their original feed URL and receive English notes.
            if suffix == "en" {
                try feed.write(to: directory.appendingPathComponent("appcast.xml"), atomically: true, encoding: .utf8)
            }
        }
        print("PASS: current bundled notes embedded in default and three localized feeds")
    }
}
