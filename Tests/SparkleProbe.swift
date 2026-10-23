import AppKit
import Sparkle

@MainActor
final class Probe: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    var result = ""
    var failure: Error?
    var notes: String?
    var shownNotes: String?
    func feedURLString(for updater: SPUUpdater) -> String? { CommandLine.arguments[1] }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        notes = item.itemDescription
        precondition(item.itemDescriptionFormat == "plain-text")
        precondition(item.releaseNotesURL == nil, "Release notes must be embedded in the signed feed")
        result = item.versionString == CommandLine.arguments[3] ? "found" : "wrong-version"
    }
    nonisolated func standardUserDriverWillShowReleaseNotesText(_ text: NSAttributedString, forUpdate update: SUAppcastItem,
                                                  withBundleDisplayVersion: String, bundleVersion: String) -> NSAttributedString? {
        MainActor.assumeIsolated { shownNotes = text.string }
        return nil
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) { result = "no-update" }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        failure = error
        if result.isEmpty { result = error == nil ? "empty" : "rejected" }
    }
}

@main
struct SparkleProbe {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let identifier = Bundle.main.bundleIdentifier!
        defer { UserDefaults.standard.removePersistentDomain(forName: identifier) }
        if CommandLine.arguments[1] == "controller" {
            UserDefaults.standard.removePersistentDomain(forName: identifier)
            let updater = AppUpdater.shared
            precondition(!updater.canCheckForUpdates)
            updater.start()
            updater.start()
            precondition(!updater.startupFailed && updater.canCheckForUpdates)
            precondition(updater.automaticallyChecksForUpdates)
            precondition(UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") == nil)
            updater.setAutomaticallyChecksForUpdates(false)
            precondition(!updater.automaticallyChecksForUpdates)
            precondition(UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool == false)
            let restored = AppUpdater()
            restored.start()
            precondition(!restored.automaticallyChecksForUpdates)
            precondition(restored.canCheckForUpdates)
            restored.setAutomaticallyChecksForUpdates(true)
            precondition(restored.automaticallyChecksForUpdates)
            precondition(UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool == true)
            let enabled = AppUpdater()
            enabled.start()
            precondition(enabled.automaticallyChecksForUpdates)
            let base = URL(string: "https://github.com/GiaoGiaoCat/RadioBar/releases/latest/download/appcast.xml")!
            for (language, system, suffix) in [(AppLanguage.chinese, ["en"], "zh-Hans"),
                (.traditionalChinese, ["en"], "zh-Hant"), (.english, ["zh-Hant"], "en"),
                (.system, ["zh-TW"], "zh-Hant"), (.system, ["zh-Hans-HK"], "zh-Hans"),
                (.system, ["fr"], "en")] {
                precondition(AppUpdater.localizedFeedURL(base, language: language, preferredLanguages: system).lastPathComponent == "appcast-\(suffix).xml")
            }
            for (raw, suffix) in [("chinese", "zh-Hans"), ("traditionalChinese", "zh-Hant"), ("english", "en")] {
                UserDefaults.standard.set(raw, forKey: AppLanguage.preferenceKey)
                precondition(enabled.feedURLString(for: SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater) == base.deletingLastPathComponent().appendingPathComponent("appcast-\(suffix).xml").absoluteString)
            }
            print("PASS: production AppUpdater starts once and publishes button availability")
            print("PASS: automatic checks default on, toggle immediately, persist off/on and preserve manual checks")
            print("PASS: app language overrides system; feed resolves again after each preference change")
            return
        }
        let probe = Probe()
        let preview = CommandLine.arguments[2] == "preview"
        if preview {
            NSApp.appearance = NSAppearance(named: CommandLine.arguments.last == "dark" ? .darkAqua : .aqua)
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: probe, userDriverDelegate: probe)
        try controller.updater.start()
        precondition(controller.updater.canCheckForUpdates)
        if preview { controller.checkForUpdates(nil) }
        else { controller.updater.checkForUpdateInformation() }
        let deadline = Date().addingTimeInterval(20)
        while (preview ? probe.shownNotes == nil : probe.result.isEmpty) && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let expected = preview ? "found" : CommandLine.arguments[2]
        guard probe.result == expected else {
            print("FAIL: expected \(expected), got \(probe.result), error: \(String(describing: probe.failure))")
            exit(1)
        }
        if CommandLine.arguments.count > 4 {
            precondition(probe.notes?.contains(CommandLine.arguments[4]) == true)
        }
        if preview {
            precondition(probe.shownNotes == probe.notes, "Native user driver must show the signed text directly")
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let window = NSApp.windows.first { $0.contentView != nil && $0.frame.width > 300 }!
            let view = window.contentView!
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                view.cacheDisplay(in: view.bounds, to: bitmap)
            }
            // This view cache verifies the notes; compositor chrome needs desktop QA.
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[5]))
            print("PASS: real Sparkle window directly presents localized notes; native preview saved")
        }
        print("PASS: real Sparkle signed-feed probe: \(expected)")
    }
}
