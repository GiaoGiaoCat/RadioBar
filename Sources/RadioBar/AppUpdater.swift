import AppKit
import Combine
#if !RADIOBAR_TESTING
import Sparkle
#endif

/// One updater per process. Rendering and offline tests never start Sparkle.
@MainActor
final class AppUpdater: NSObject, ObservableObject {
    static let shared = AppUpdater()
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var startupFailed = false
    @Published private(set) var automaticallyChecksForUpdates = true
#if RADIOBAR_TESTING
    // Offline previews show the idle button without loading Sparkle or networking.
    override init() { super.init(); canCheckForUpdates = true }
#endif
#if !RADIOBAR_TESTING
    private var controller: SPUStandardUpdaterController?
#endif

    func start() {
#if !RADIOBAR_TESTING
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false,
            updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
        do {
            try controller.updater.start()
        } catch {
            startupFailed = true
        }
#endif
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
#if RADIOBAR_TESTING
        automaticallyChecksForUpdates = enabled
#else
        controller?.updater.automaticallyChecksForUpdates = enabled
#endif
    }

    func checkForUpdates() {
#if !RADIOBAR_TESTING
        guard canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
#endif
    }

    /// Resolve on each check so a settings change applies without restarting.
    static func localizedFeedURL(_ base: URL, language: AppLanguage,
                                 preferredLanguages: [String] = Locale.preferredLanguages) -> URL {
        guard base.lastPathComponent == "appcast.xml" else { return base }
        let suffix: String
        switch language.resolved(preferredLanguages: preferredLanguages) {
        case .chinese: suffix = "zh-Hans"
        case .traditionalChinese: suffix = "zh-Hant"
        case .english, .system: suffix = "en"
        }
        return base.deletingLastPathComponent().appendingPathComponent("appcast-\(suffix).xml")
    }
}

#if !RADIOBAR_TESTING
extension AppUpdater: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let base = URL(string: value) else { return nil }
        let language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppLanguage.preferenceKey) ?? "") ?? .system
        return Self.localizedFeedURL(base, language: language).absoluteString
    }
}
#endif
