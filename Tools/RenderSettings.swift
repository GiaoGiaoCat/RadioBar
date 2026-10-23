import SwiftUI
import AppKit

@MainActor
private final class PreviewLogin: LoginItemManaging {
    var state: LoginItemState = .disabled
    func setEnabled(_ enabled: Bool) async throws {}
    func openSystemSettings() {}
}

@main
struct SettingsSnapshots {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApp.applicationIconImage = NSImage(contentsOfFile: "Resources/RadioBar.icns")
        let metadata = Bundle(path: CommandLine.arguments[2])!
        let sourceInfo = NSDictionary(contentsOfFile: "Resources/Info.plist")!
        let expectedVersion = "\(sourceInfo["CFBundleShortVersionString"]!) (\(sourceInfo["CFBundleVersion"]!))"
        precondition(SettingsVersion.label(in: metadata) == expectedVersion)
        print("PASS: sidebar version comes from Bundle: \(SettingsVersion.label(in: metadata))")
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let license = try String(contentsOfFile: "Resources/Sparkle-LICENSE.txt", encoding: .utf8)
        precondition(RadioAcknowledgments.license(in: metadata) == license, "Read the complete license from the packaged resource")
        for (name, language, dark, atEnd, missing) in [
            ("zh-acknowledgments", AppLanguage.chinese, false, false, false),
            ("en-acknowledgments-dark", AppLanguage.english, true, false, false),
            ("hant-acknowledgments", AppLanguage.traditionalChinese, false, false, false),
            ("en-acknowledgments-end", AppLanguage.english, false, true, false),
            ("zh-acknowledgments-missing", AppLanguage.chinese, false, false, true)
        ] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            NSApp.appearance = appearance
            let root = ScrollViewReader { proxy in
                AcknowledgmentsSheet(language: language, licenseText: missing ? nil : RadioAcknowledgments.license(in: metadata))
                    .onAppear {
                        if atEnd {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { proxy.scrollTo("licenseEnd", anchor: .bottom) }
                        }
                    }
            }
            let host = NSHostingView(rootView: root.environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.controlActiveState, .key))
            host.safeAreaRegions = []
            let size = host.fittingSize
            precondition(size == NSSize(width: 560, height: 480))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = appearance
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            for _ in 0..<3 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            appearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            print("Rendered \(name): \(size)")
            window.contentView = nil
            window.close()
        }
        let suite = "RadioBar.LayoutPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = PreviewLogin()
        var settings = AppSettings(defaults: defaults, loginManager: manager)
        let configRoot = FileManager.default.temporaryDirectory.appendingPathComponent("RadioBar-SettingsPreview-" + UUID().uuidString)
        let configFile = StationCatalog.userFile(in: configRoot)
        let factoryData = try StationCatalog.defaultData()
        _ = try StationCatalog.load(userFile: configFile, defaultData: factoryData)
        defer {
            try? factoryData.write(to: configFile, options: .atomic)
            _ = StationCatalog.start(defaults: defaults, supportDirectory: configRoot)
            try? FileManager.default.removeItem(at: configRoot)
        }
        for (name, language, dark, adding, failed) in [
            ("zh-station-add", AppLanguage.chinese, false, true, false),
            ("en-station-edit-dark", AppLanguage.english, true, false, false),
            ("hant-station-edit-error", AppLanguage.traditionalChinese, false, false, true),
            ("en-station-url-error", AppLanguage.english, false, false, true)
        ] {
            let session = try StationEditorSession(file: configFile, station: adding ? nil : .bcc)
            let reason = name == "en-station-url-error"
                ? RadioText("播放地址第 3 行包含空白或不可见字符，请删除这些字符后重试。", "Stream URL line 3 contains whitespace or invisible characters. Remove them and try again.")
                : RadioText("配置文件已被外部修改。请取消编辑，重新加载后再试。", "The configuration changed outside the app. Cancel editing, reload and try again.")
            let view = StationEditorSheet(session: session, language: language, save: { _, _ in nil }, error: failed ? reason : nil)
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            NSApp.appearance = appearance
            let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.controlActiveState, .key).background(Color(nsColor: .windowBackgroundColor)))
            host.safeAreaRegions = []
            let size = host.fittingSize
            precondition(size.width == 480 && size.height < 580, "Editor must fit inside the settings window")
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = appearance
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            for _ in 0..<3 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            appearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            print("Rendered \(name): \(size)")
            window.contentView = nil
            window.close()
        }
        let navigation = SettingsNavigation()
        var instant = ContinuousClock().now
        let timer = SleepTimer(defaults: defaults, now: { instant }) {}
        let fixtureStore = RadioDiagnostics.shared
        let fixtureID = fixtureStore.begin(station: .musicRadio)
        let fixtureTrace = DiagnosticTrace(store: fixtureStore, connection: fixtureID, attempt: 2, station: Station.musicRadio.id)
        fixtureStore.state(fixtureTrace, phase: "Retrying", source: "primary", retries: 1, error: "NSURLErrorDomain/-1001")
        fixtureTrace.event("resolve.complete", "elapsedMs=0")
        fixtureTrace.event("retry.scheduled", "retry=1/4; delaySeconds=2")
        let configurations: [(String, AppLanguage, SettingsPage, String, Bool)] = [
            ("zh-station-saved", .chinese, .channels, "editorSaved", false),
            ("en-station-saved-dark", .english, .channels, "editorSaved", true),
            ("zh-station-edit-long-failed", .chinese, .channels, "editorLongFailed", false),
            ("en-station-edit-long-failed-dark", .english, .channels, "editorLongFailed", true),
            ("en-station-edit-failed-dark", .english, .channels, "editorFailed", true),
            ("en-config-file-failed", .english, .channels, "fileFailed", false),
            ("zh-reload-success", .chinese, .channels, "reloadSuccess", false),
            ("en-reload-failed-dark", .english, .channels, "reloadFailed", true),
            ("hant-reload-unchanged", .traditionalChinese, .channels, "reloadUnchanged", false),
            ("zh-restore-success", .chinese, .channels, "restoreSuccess", false),
            ("en-restore-success-dark", .english, .channels, "restoreSuccess", true),
            ("hant-restore-backup-failed", .traditionalChinese, .channels, "restoreBackupFailed", false),
            ("en-restore-backup-failed", .english, .channels, "restoreBackupFailed", false),
            ("zh-restore-failed-dark", .chinese, .channels, "restoreFailed", true),
            ("en-restore-failed-dark", .english, .channels, "restoreFailed", true),
            ("hant-general", .traditionalChinese, .general, "off", false),
            ("hant-general-dark", .traditionalChinese, .general, "off", true),
            ("hant-channels", .traditionalChinese, .channels, "off", false),
            ("hant-playback", .traditionalChinese, .playback, "off", false),
            ("hant-timer-dark", .traditionalChinese, .sleepTimer, "active", true),
            ("hant-diagnostics-dark", .traditionalChinese, .diagnostics, "off", true),
            ("hant-diagnostics", .traditionalChinese, .diagnostics, "off", false),
            ("hant-about-expanded", .traditionalChinese, .about, "historyExpanded", false),
            ("hant-about-expanded-dark", .traditionalChinese, .about, "historyExpanded", true),
            ("zh-channels-sorted-dark", .chinese, .channels, "sorted", true),
            ("en-channels-sorted", .english, .channels, "sorted", false),
            ("zh-playback-sorted", .chinese, .playback, "sorted", true),
            ("zh-channels", .chinese, .channels, "channels", false),
            ("zh-channels-dark", .chinese, .channels, "channels", true),
            ("en-channels", .english, .channels, "channels", false),
            ("en-channels-dark", .english, .channels, "channels", true),
            ("zh-channels-bottom-dark", .chinese, .channels, "channelsEnd", true),
            ("en-channels-bottom", .english, .channels, "channelsEnd", false),
            ("zh-channels-bottom", .chinese, .channels, "channelsEnd", false),
            ("en-channels-bottom-dark", .english, .channels, "channelsEnd", true),
            ("hant-channels-bottom", .traditionalChinese, .channels, "channelsEnd", false),
            ("zh-channels-last-visible", .chinese, .channels, "lastVisible", true),
            ("zh-playback-filtered", .chinese, .playback, "channels", true),
            ("zh-playback-random", .chinese, .playback, "random", false),
            ("en-playback-random", .english, .playback, "random", false),
            ("zh-playback-random-dark", .chinese, .playback, "random", true),
            ("en-playback-random-dark", .english, .playback, "random", true),
            ("zh-general-force-dark", .chinese, .general, "forceDark", false),
            ("zh-general-force-light", .chinese, .general, "forceLight", true),
            ("en-general-force-dark", .english, .general, "forceDark", false),
            ("en-general-force-light", .english, .general, "forceLight", true),
            ("hant-about", .traditionalChinese, .about, "off", false),
            ("hant-about-dark", .traditionalChinese, .about, "off", true),
            ("zh-about-copied", .chinese, .about, "versionCopied", false),
            ("en-about-copied-dark", .english, .about, "versionCopied", true),
            ("zh-about", .chinese, .about, "off", false),
            ("en-about", .english, .about, "off", false),
            ("zh-about-dark", .chinese, .about, "off", true),
            ("en-about-dark", .english, .about, "off", true),
            ("zh-about-updates-disabled", .chinese, .about, "updatesDisabled", false),
            ("en-about-updates-disabled-dark", .english, .about, "updatesDisabled", true),
            ("en-about-expanded", .english, .about, "historyExpanded", false),
            ("en-about-expanded-dark", .english, .about, "historyExpanded", true),
            ("zh-about-expanded", .chinese, .about, "historyExpanded", false),
            ("zh-about-expanded-dark", .chinese, .about, "historyExpanded", true),
            ("zh-about-oldest", .chinese, .about, "historyEnd", false),
            ("en-about-oldest-dark", .english, .about, "historyEnd", true),
            ("en-diagnostics", .english, .diagnostics, "off", false),
            ("zh-diagnostics", .chinese, .diagnostics, "off", false),
            ("en-diagnostics-dark", .english, .diagnostics, "off", true),
            ("zh-diagnostics-dark", .chinese, .diagnostics, "off", true),
            ("en-playback-dark", .english, .playback, "off", true),
            ("zh-general-dark", .chinese, .general, "name", true),
            ("zh-playback-dark", .chinese, .playback, "off", true),
            ("zh-timer-dark", .chinese, .sleepTimer, "active", true),
            ("en-general", .english, .general, "off", false),
            ("en-general-name", .english, .general, "name", false),
            ("zh-general-animation", .chinese, .general, "animation", false),
            ("en-general-animation", .english, .general, "animation", false),
            ("zh-general-name", .chinese, .general, "name", false),
            ("en-general-dark", .english, .general, "name", true),
            ("en-playback", .english, .playback, "off", false),
            ("en-timer-off", .english, .sleepTimer, "off", false),
            ("zh-timer-name", .chinese, .sleepTimer, "timerName", false),
            ("en-timer-hidden-dark", .english, .sleepTimer, "timerHidden", true),
            ("zh-timer-fading", .chinese, .sleepTimer, "fading", false),
            ("en-timer-finished-dark", .english, .sleepTimer, "finished", true),
            ("hant-timer-maximum", .traditionalChinese, .sleepTimer, "maximum", false),
            ("en-timer-active", .english, .sleepTimer, "active", false),
            ("en-timer-invalid", .english, .sleepTimer, "invalid", false),
            ("zh-general", .chinese, .general, "off", false),
            ("zh-playback", .chinese, .playback, "off", false),
            ("zh-timer-off", .chinese, .sleepTimer, "off", false),
            ("zh-timer-active", .chinese, .sleepTimer, "active", false),
            ("zh-timer-invalid", .chinese, .sleepTimer, "invalid", false),
            ("en-timer-dark", .english, .sleepTimer, "active", true),
            ("en-general-approval", .english, .general, "approval", false),
            ("zh-channels-custom", .chinese, .channels, "customStations", false),
            ("en-channels-custom-dark", .english, .channels, "customStations", true),
            ("hant-channels-custom", .traditionalChinese, .channels, "customStations", false),
            ("zh-playback-custom", .chinese, .playback, "customStations", false),
            ("en-playback-custom-dark", .english, .playback, "customStations", true),
            ("zh-channels-builtins-only", .chinese, .channels, "builtinsOnly", false),
            ("en-channels-builtins-only-dark", .english, .channels, "builtinsOnly", true),
            ("en-playback-builtins-only", .english, .playback, "builtinsOnly", false),
            ("zh-channels-default-hidden", .chinese, .channels, "customHidden", false),
            ("en-playback-default-hidden", .english, .playback, "customHidden", false)
        ]
        for (name, language, page, state, dark) in configurations {
            if state == "customStations" || state == "builtinsOnly" || state == "customHidden" {
                let entries: [[String: Any]] = state == "builtinsOnly" ? [] : [
                    ["id": "custom.preview.music", "name": ["zh": "自定义音乐台", "en": "Custom Music"],
                     "urls": ["https://fixture.invalid/live.mp3"], "defaultVisible": state != "customHidden"]
                ]
                try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "stations": entries]).write(to: configFile, options: .atomic)
                precondition(StationCatalog.start(defaults: defaults, supportDirectory: configRoot) == nil)
                defaults.removeObject(forKey: StationOrder.preferenceKey)
                defaults.removeObject(forKey: StationVisibility.preferenceKey)
                defaults.removeObject(forKey: StationVisibility.overridesKey)
                settings = AppSettings(defaults: defaults, loginManager: manager)
                precondition(settings.orderedStations.count == (entries.isEmpty ? 2 : 3))
                precondition(settings.orderedStations.map(\.id) == ["builtin.kiss", "builtin.music-radio"] + entries.map { $0["id"] as! String })
            }
            AppUpdater.shared.setAutomaticallyChecksForUpdates(state != "updatesDisabled")
            settings.resetStationOrder()
            if state == "customHidden" {
                precondition(settings.visibleStations == [.kiss, .musicRadio])
            } else {
                for station in Station.allCases { settings.setStationVisible(station, true) }
            }
            if state == "sorted" {
                settings.moveStation(.swissJazz, relativeTo: .kiss, after: false)
                settings.moveStation(.radioParadise, relativeTo: .kiss, after: false)
                settings.setStationVisible(.guangdong, false)
                settings.setStationVisible(.classic947, false)
            }
            if state == "channels" || state == "channelsEnd" {
                settings.setStationVisible(.guangdong, false)
                settings.setStationVisible(.classic947, false)
            } else if state == "lastVisible" {
                for station in Station.allCases where station != .kiss { settings.setStationVisible(station, false) }
            }
            settings.appearance = state == "forceDark" ? .dark : state == "forceLight" ? .light : .system
            settings.defaultStation = state == "random" ? .random : .station(settings.visibleStations.contains(.classic947) ? .classic947 : .kiss)
            settings.animateMenuBarIcon = state == "animation"
            settings.language = language
            settings.showSleepTimerInMenuBar = state != "timerHidden"
            settings.menuBarDisplay = state == "name" || state == "timerName" ? .iconAndStation : .iconOnly
            navigation.page = page
            manager.state = state == "approval" ? .requiresApproval : .disabled
            settings.refreshLoginState()
            timer.cancel()
            timer.setFadingOut(false)
            timer.minutesInput = "30"
            if ["active", "timerName", "timerHidden", "maximum"].contains(state) {
                if state == "maximum" { timer.minutesInput = "720" }
                timer.start()
                instant = instant.advanced(by: .seconds(65))
                timer.refresh()
            } else if state == "invalid" { timer.minutesInput = "0" }
            else if state == "fading" || state == "finished" {
                timer.minutesInput = "1"
                timer.start()
                instant = instant.advanced(by: .seconds(61))
                timer.refresh()
                timer.setFadingOut(state == "fading")
            }
            settings.dismissStationVisibilityFeedback()
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            NSApp.appearance = appearance
            let root = ScrollViewReader { proxy in
                RadioSettingsView(settings: settings, navigation: navigation, releaseNotesExpanded: state == "historyEnd" || state == "historyExpanded",
                                  versionInfoCopied: state == "versionCopied",
                                  stationRestoreResult: state == "restoreSuccess" ? .restored(backup: configFile) :
                                    state == "editorSaved" ? .saved :
                                    state == "editorLongFailed" ? .editFailed(RadioText("配置文件已被外部修改。请取消编辑，重新加载后再试。如果问题仍然存在，请检查配置文件及所在文件夹的访问权限。", "The configuration changed outside the app. Cancel editing, reload and try again. If the problem continues, check access permissions for the configuration file and its folder.")) :
                                    state == "editorFailed" ? .editFailed(RadioText("无法读取配置文件，请检查文件及访问权限。", "Unable to read the configuration file. Check the file and permissions.")) :
                                    state == "restoreBackupFailed" ? .backupFailed :
                                    state == "restoreFailed" ? .restoreFailed(backup: configFile) :
                                    state == "reloadSuccess" ? .reloaded : state == "reloadUnchanged" ? .unchanged :
                                    state == "fileFailed" ? .openFailed : state == "reloadFailed" ? .reloadFailed(RadioText("第 3 个电台：ID 重复。", "Station 3: Duplicate ID.")) : nil,
                                  timer: timer, metadataBundle: metadata)
                    .onAppear {
                        if state.hasPrefix("editor") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                proxy.scrollTo("stationListActions", anchor: .bottom)
                            }
                        }
                        if state.hasPrefix("restore") || state.hasPrefix("reload") || state == "fileFailed" || state == "channelsEnd" {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                proxy.scrollTo(state == "channelsEnd" ? "stationConfigurationHint" : "stationConfigurationActions",
                                               anchor: state == "channelsEnd" ? .top : .bottom)
                            }
                        }
                        if state == "historyEnd" || state == "historyExpanded" {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                let entry = state == "historyEnd" ? RadioReleaseNotes.entries.last : RadioReleaseNotes.entries.first
                                if let entry { proxy.scrollTo(entry.id, anchor: state == "historyEnd" ? .bottom : .top) }
                            }
                        }
                    }
            }
                .environment(\.controlActiveState, .key)
            let hosting = NSHostingView(rootView: root)
            hosting.safeAreaRegions = []
            let rect = NSRect(x: 0, y: 0, width: SettingsLayout.width, height: SettingsLayout.height)
            let window = NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            SettingsLayout.configure(window)
            precondition(window.titleVisibility == .hidden && window.styleMask.contains(.fullSizeContentView))
            precondition(window.standardWindowButton(.closeButton) != nil)
            window.isReleasedWhenClosed = false
            window.appearance = appearance
            window.contentView = hosting
            hosting.frame = rect
            // Render the real view in an offscreen window; never show or capture the desktop.
            for _ in 0..<3 {
                hosting.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            func scrollViews(in view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
            }
            let scroll = scrollViews(in: hosting).first!
            precondition(scroll.verticalScroller is SettingsScroller, "Settings must use the slim native scroller")
            if page == .general || (page == .about && (state == "off" || state == "updatesDisabled" || state == "versionCopied")) {
                precondition(scroll.documentView!.frame.height <= scroll.contentView.bounds.height + 1,
                             "Short settings content must fit without scrolling: \(name)")
                precondition(scroll.verticalScroller!.isHidden || scroll.verticalScroller!.knobProportion == 0 ||
                             scroll.verticalScroller!.knobProportion == 1, "No visible knob when content fits")
            }
            if (page == .channels && scroll.documentView!.frame.height > scroll.contentView.bounds.height + 1) || state == "historyExpanded" || state == "historyEnd" {
                precondition(scroll.documentView!.frame.height > scroll.contentView.bounds.height,
                             "Long content must remain scrollable")
                precondition(!scroll.verticalScroller!.isHidden)
            }
            precondition(hosting.fittingSize == NSSize(width: SettingsLayout.width, height: SettingsLayout.height))
            precondition(hosting.bounds.size == hosting.fittingSize)
            func popupButtons(in view: NSView) -> [NSPopUpButton] {
                (view as? NSPopUpButton).map { [$0] } ?? view.subviews.flatMap { popupButtons(in: $0) }
            }
            let popups = popupButtons(in: hosting)
            if page == .general {
                precondition(popups.count == 3)
                precondition(popups.allSatisfy { abs($0.frame.width - 196) < 1 && $0.controlSize == .regular },
                             "General pickers must use matching native widths and control sizes")
                // Exercise the native action bridge without opening a menu or changing the fixture.
                for button in popups {
                    let selected = button.indexOfSelectedItem
                    precondition(selected >= 0)
                    precondition(button.sendAction(button.action, to: button.target))
                    precondition(button.indexOfSelectedItem == selected)
                }
            } else if page == .playback {
                precondition(popups.count == 1 && popups[0].controlSize == .regular)
                precondition(popups[0].numberOfItems == settings.visibleStations.count + 3)
                precondition(popups[0].item(at: 2)?.isSeparatorItem == true)
                let previous = settings.defaultStation
                popups[0].selectItem(at: 1)
                precondition(popups[0].sendAction(popups[0].action, to: popups[0].target))
                precondition(settings.defaultStation == .random, "Native picker must update the existing preference binding")
                settings.defaultStation = previous
                for _ in 0..<2 {
                    hosting.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                }
            }
            let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            }
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            print("Rendered \(name): \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
            if state == "forceDark" || state == "forceLight" {
                for (step, choice) in [AppAppearance.light, .system, .dark, .system].enumerated() {
                    settings.appearance = choice
                    for _ in 0..<3 {
                        hosting.layoutSubtreeIfNeeded()
                        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                    }
                    let expected: NSAppearance.Name = choice == .system ? (dark ? .darkAqua : .aqua) :
                        choice == .dark ? .darkAqua : .aqua
                    precondition(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected)
                    if choice == .system { precondition(window.appearance == nil) }
                    precondition(NSApp.appearance?.name == appearance.name, "Must not override the app/status item appearance")
                    let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
                    window.effectiveAppearance.performAsCurrentDrawingAppearance {
                        hosting.cacheDisplay(in: hosting.bounds, to: image)
                    }
                    let color = image.colorAt(x: image.pixelsWide - 10, y: image.pixelsHigh - 10)!.usingColorSpace(.deviceRGB)!
                    let luminance = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                    try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name)-transition-\(step)-\(choice.rawValue).png"))
                    precondition(expected == .darkAqua ? luminance < 0.4 : luminance > 0.7,
                                 "Content must match native window immediately, without a focus change: \(name) -> \(choice), brightness=\(luminance)")
                }
                NSApp.appearance = NSAppearance(named: dark ? .aqua : .darkAqua)
                for _ in 0..<3 {
                    hosting.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                }
                precondition(window.appearance == nil)
                precondition(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == (dark ? .aqua : .darkAqua))
                NSApp.appearance = appearance
                print("PASS: rendered content and native window agree for light -> system -> dark -> system, without focus changes")
                print("PASS: system mode follows a simulated system appearance change in the open window")
            }
            window.contentView = nil
            window.close()
        }
        timer.cancel()
    }
}
