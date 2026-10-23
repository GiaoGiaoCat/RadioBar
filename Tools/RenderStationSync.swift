import SwiftUI
import AppKit

@MainActor private final class SyncPreviewLogin: LoginItemManaging {
    var state: LoginItemState = .disabled
    func setEnabled(_ enabled: Bool) async throws {}
    func openSystemSettings() {}
}

@main @MainActor
struct StationSyncSnapshots {
    static func changedDocument(_ data: Data) throws -> StationDocument {
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var entries = object["stations"] as! [[String: Any]]
        entries[0]["name"] = ["zh": "同步示例电台", "en": "Sync example station"]
        object["stations"] = entries
        return try StationDocument(data: JSONSerialization.data(withJSONObject: object))
    }

    static func render<V: View>(_ view: V, name: String, dark: Bool, output: URL, size: NSSize? = nil) async throws {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        NSApp.appearance = appearance
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.controlActiveState, .key).background(Color(nsColor: .windowBackgroundColor)))
        host.safeAreaRegions = []
        let bounds = size ?? host.fittingSize
        precondition(bounds.width <= 760 && bounds.height <= 620, "Sync UI must fit existing settings window")
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: bounds), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = appearance; window.contentView = host
        host.frame = NSRect(origin: .zero, size: bounds)
        for _ in 0..<4 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(80)) }
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        appearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        print("Rendered \(name): \(bounds)")
        window.contentView = nil; window.close()
    }

    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let metadata = Bundle(path: CommandLine.arguments[2])!
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let factory = try StationCatalog.defaultData()
        let original = StationCatalog.stations
        defer { StationCatalog.apply(original) }
        for (code, language) in [("zh", AppLanguage.chinese), ("en", .english), ("hant", .traditionalChinese)] {
            for dark in [false, true] {
                for state in ["disconnected", "confirm", "replace", "published", "waiting", "changed", "invalid", "stopped"] {
                    let root = FileManager.default.temporaryDirectory.appendingPathComponent("RadioBar-PublishPreview-" + UUID().uuidString)
                    let suite = "RadioBar.PublishPreview." + UUID().uuidString
                    let defaults = UserDefaults(suiteName: suite)!
                    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
                    let file = StationCatalog.userFile(in: root)
                    _ = try StationCatalog.load(userFile: file, defaultData: factory)
                    StationCatalog.apply(StationCatalog.merge(try StationConfiguration.decode(factory)))
                    let settings = AppSettings(defaults: defaults, loginManager: SyncPreviewLogin())
                    settings.language = language; settings.appearance = dark ? .dark : .light
                    settings.enableStationSync(supportDirectory: root, automatic: false)
                    let sync = settings.stationSync!
                    let cloud = root.appendingPathComponent("RadioBar iCloud")
                    try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
                    var sheet: StationSyncReview?
                    if state != "disconnected" {
                        await sync.prepareAssociation(to: cloud)
                        if state == "confirm" { sheet = sync.review; sync.cancelReview() }
                        else {
                            await sync.confirmReview()
                            precondition(sync.status == .checked, sync.errorText?.en ?? "Publication failed")
                            if state == "waiting" { settings.defaultStation = .random }
                            if state == "replace" {
                                settings.defaultStation = .random
                                sync.disconnect(); await sync.prepareAssociation(to: cloud)
                                sheet = sync.review; sync.cancelReview()
                            }
                            let current = cloud.appendingPathComponent("RadioBarSync/current.json")
                            if state == "changed" {
                                let first = try StationPublication.decode(Data(contentsOf: current))
                                let next = try StationPublication(libraryID: first.libraryID, sequence: first.sequence + 10, configuration: first.configuration)
                                try next.encoded().write(to: current, options: .atomic)
                                await sync.synchronize()
                            }
                            if state == "invalid" {
                                try Data("invalid".utf8).write(to: current, options: .atomic)
                                await sync.synchronize()
                            }
                            if state == "stopped" { sync.disconnect() }
                        }
                    }
                    let name = code + "-" + (dark ? "dark-" : "light-") + state
                    if let sheet {
                        try await render(StationSyncReviewSheet(sync: sync, review: sheet, language: language), name: name, dark: dark, output: output)
                    } else {
                        let navigation = SettingsNavigation(); navigation.page = .sync
                        let timer = SleepTimer(defaults: defaults) {}
                        let view = RadioSettingsView(settings: settings, navigation: navigation, timer: timer, metadataBundle: metadata, stationConfigurationSupportDirectory: root)
                        try await render(view, name: name, dark: dark, output: output, size: NSSize(width: 760, height: 620))
                    }
                }
            }
        }
    }
}
