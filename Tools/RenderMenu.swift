import SwiftUI
import AppKit
import Combine

@MainActor
private final class MenuPreviewLogin: LoginItemManaging {
    var state: LoginItemState { .disabled }
    func setEnabled(_ enabled: Bool) async throws {}
    func openSystemSettings() {}
}

@MainActor
private final class MenuPreviewResolver: StreamURLResolving {
    var shouldFail = false
    private var pending: [CheckedContinuation<StreamAddress, Error>] = []
    func resolve(_ station: Station, attempt: Int) async throws -> StreamAddress {
        if shouldFail { throw NSError(domain: NSURLErrorDomain, code: -1004) }
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func cancelPending() {
        let old = pending
        pending.removeAll()
        old.forEach { $0.resume(throwing: CancellationError()) }
    }
}

private struct MenuBoundsProbe: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(name)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

// An isolated real MenuBarExtra using the same extracted production views.
// Playback state is simulated; the production toggle/pause actions still run.
@MainActor
private final class MenuLiveFixture {
    let radio: RadioPlayer
    let settings: AppSettings
    let signal: MenuBarSignal
    private let defaultsSuite: String
    private let resolver = MenuPreviewResolver()
    private final class Clock { var now = ContinuousClock().now }
    private let clock = Clock()
    private var labelWidths: [String: CGFloat] = [:]
    private let labelSamples = [644, 641, 599, 5382, 5381, 3600, 3599, 43200, 43199]
    private var subscription: AnyCancellable?
    private var timer: Timer?
    private var lastReport = ""
    private var step = 0
    private var layoutResults: [String] = []
    init() {
        let suite = "RadioBar.MenuLivePreview.\(UUID().uuidString)"
        defaultsSuite = suite
        let defaults = UserDefaults(suiteName: suite)!
        _ = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        defaults.set(Station.musicRadio.rawValue, forKey: "station")
        let clock = self.clock
        let labelAutomatic = ProcessInfo.processInfo.environment["RADIOBAR_MENU_LABEL_AUTORUN"] == "1"
        radio = RadioPlayer(resolver: resolver, defaults: defaults,
                            sleepClockNow: { labelAutomatic ? clock.now : ContinuousClock().now })
        settings = AppSettings(defaults: defaults, loginManager: MenuPreviewLogin())
        settings.language = .english
        let visible: [Station] = [.kiss, .musicRadio, .bcc, .asiaFM, .guangdong, .grooveSalad, .swissJazz]
        for station in Station.allCases { settings.setStationVisible(station, visible.contains(station)) }
        if ProcessInfo.processInfo.environment["RADIOBAR_MENU_LABEL_AUTORUN"] == "1" {
            settings.menuBarDisplay = .iconAndStation
            radio.station = .grooveSalad
        }
        settings.animateMenuBarIcon = true
        signal = MenuBarSignal(radio: radio, settings: settings)
        subscription = radio.$wantsPlayback.dropFirst().sink { [weak self] wanted in
            guard let self else { return }
            if !wanted { self.resolver.cancelPending(); return }
            if ProcessInfo.processInfo.environment["RADIOBAR_MENU_AUTORUN"] == "1" { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.radio.wantsPlayback else { return }
                self.radio.statusText = RadioText("缓冲中…", "Buffering…")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.radio.wantsPlayback else { return }
                self.radio.isPlaying = true
                self.radio.statusText = RadioText("播放中", "Playing")
            }
        }
        let interval = ProcessInfo.processInfo.environment["RADIOBAR_MENU_AUTORUN"] == "1" || labelAutomatic ? 0.2 : 0.5
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordGeometry() }
        }
    }
    private func menuWindow() -> NSWindow? {
        func containsHeader(_ view: NSView) -> Bool {
            view.identifier?.rawValue == "menuHeaderProbe" || view.subviews.contains(where: containsHeader)
        }
        return NSApp.windows.first { $0.contentView.map(containsHeader) ?? false }
    }
    private func statusButton() -> NSStatusBarButton? {
        func find(_ view: NSView) -> NSStatusBarButton? {
            if let button = view as? NSStatusBarButton { return button }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        return NSApp.windows.lazy.compactMap { $0.contentView.flatMap(find) }.first
    }
    private func recordLabelGeometry() {
        if step % 2 == 1 {
            let index = (step - 1) / 2
            guard index < labelSamples.count * 2 else { return }
            settings.menuBarDisplay = index < labelSamples.count ? .iconAndStation : .iconOnly
            radio.sleepTimer.minutesInput = "720"
            radio.sleepTimer.start()
            clock.now = clock.now.advanced(by: .seconds(43200 - labelSamples[index % labelSamples.count]))
            radio.sleepTimer.refresh()
        } else if let button = statusButton() {
            let width = button.frame.width
            let clock = radio.sleepTimer.remainingText
            let key = "\(settings.menuBarDisplay.rawValue)-\(clock.count)"
            let stableWidth = labelWidths[key] ?? width
            labelWidths[key] = width
            let prefix = "\u{2002}" + (settings.menuBarDisplay == .iconAndStation ? radio.station.menuName.en + " · " : "")
            let contentWidth = MenuBarAntenna.size.width
                + (prefix as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width
                + (clock as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]).width
            let trailingReservation = (button.image?.size.width ?? 0) - contentWidth
            let valid = button.image?.isTemplate == true && button.title.isEmpty
                && (button.image?.size.width ?? 0) > MenuBarAntenna.size.width
                && abs(width - stableWidth) < 0.1 && trailingReservation >= 0 && trailingReservation < 1
            layoutResults.append("\(valid ? "PASS" : "FAIL"): mode=\(settings.menuBarDisplay.rawValue) countdown=\(clock) trailingReservation=\(trailingReservation) buttonWidth=\(width) imageWidth=\(button.image?.size.width ?? 0) title=\(button.title) font=\(String(describing: button.font))")
            if let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) {
                button.cacheDisplay(in: button.bounds, to: bitmap)
                let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("menu-label-step-\(step).png")
                try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
            }
        } else {
            layoutResults.append("INCOMPLETE: Native status button unavailable")
        }
        if step == labelSamples.count * 4 {
            let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("menu-label-result.txt")
            try? layoutResults.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
            radio.sleepTimer.cancel()
            UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite)
            guard layoutResults.count == labelSamples.count * 2 && layoutResults.allSatisfy({ $0.hasPrefix("PASS:") }) else {
                FileHandle.standardError.write(Data("FAIL: Native countdown label validation; see menu-label-result.txt\n".utf8))
                exit(EXIT_FAILURE)
            }
            NSApp.terminate(nil)
        }
    }
    private func recordGeometry() {
        step += 1
        if ProcessInfo.processInfo.environment["RADIOBAR_MENU_LABEL_AUTORUN"] == "1" {
            recordLabelGeometry()
            return
        }
        let automatic = ProcessInfo.processInfo.environment["RADIOBAR_MENU_AUTORUN"] == "1"
        if automatic && step == 2 {
            func findButton(_ view: NSView) -> NSStatusBarButton? {
                if let button = view as? NSStatusBarButton { return button }
                return view.subviews.lazy.compactMap { findButton($0) }.first
            }
            for window in NSApp.windows {
                if let root = window.contentView, let button = findButton(root) {
                    button.performClick(nil)
                    break
                }
            }
        }
        // Allow the status-button presentation to settle before testing the
        // cached native window; its event tracking can dismiss an early show.
        let step = self.step - 24
        if automatic && step == 8
            && ProcessInfo.processInfo.environment["RADIOBAR_MENU_TEST_EARLY_DISMISS"] == "1" {
            menuWindow()?.orderOut(nil)
        }
        if automatic && [3, 4, 28, 30].contains(step) {
            // Exercise native visibility directly after initial status-button
            // presentation; performClick can reuse an unrelated current event.
            if let menu = menuWindow() {
                if step == 3 || step == 28 { menu.orderOut(nil) }
                else { menu.makeKeyAndOrderFront(nil) }
            }
        }
        if automatic {
            switch step {
            case 4: radio.toggle()
            case 6, 14:
                radio.statusText = RadioText("等待重试（4/4）", "Retrying (4/4)")
                radio.detailText = RadioText("直播连接失败，16 秒后重试连接", "The live stream failed · Retry connection in 16s")
            case 10, 18:
                radio.statusText = RadioText("连接中…", "Connecting…")
                radio.detailText = radio.station.resolutionText
            case 22: radio.statusText = RadioText("缓冲中…", "Buffering…")
            case 24:
                radio.pause()
                radio.statusText = RadioText("连接失败", "Connection failed")
            case 26:
                radio.wantsPlayback = true
                radio.isPlaying = true
                radio.statusText = RadioText("播放中", "Playing")
            case 32:
                radio.select(.kiss)
                resolver.cancelPending()
            case 34:
                radio.isPlaying = true
                radio.statusText = RadioText("播放中", "Playing")
            case 36: settings.appearance = .dark
            case 38: settings.appearance = .light
            case 40: settings.appearance = .system
            default: break
            }
        }
        if automatic && [9, 13, 17, 21, 25, 27, 31, 35, 37, 39, 41].contains(step) {
            func find(_ identifier: String, in view: NSView) -> NSView? {
                if view.identifier?.rawValue == identifier { return view }
                return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
            }
            let menu = NSApp.windows.first { window in
                window.contentView.map { find("menuHeaderProbe", in: $0) != nil } ?? false
            }
            let expectedHeight: CGFloat = 376
            if let menu, menu.isVisible, let host = menu.contentView,
               let header = find("menuHeaderProbe", in: host), let bottom = find("menuBottomProbe", in: host) {
                let headerRect = header.convert(header.bounds, to: host)
                let bottomRect = bottom.convert(bottom.bounds, to: host)
                let topInset = host.isFlipped ? headerRect.minY : host.bounds.height - headerRect.maxY
                let bottomInset = host.isFlipped ? host.bounds.height - bottomRect.maxY : bottomRect.minY
                let presentedHeight = host.layer?.presentation()?.bounds.height ?? host.bounds.height
                let appearanceMatches = settings.appearance.nativeAppearance.map {
                    menu.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == $0.name
                } ?? true
                let backdrop = find("radioMenuBackground", in: host)
                let backdropRect = backdrop.map { $0.convert($0.bounds, to: host) } ?? .zero
                let backdropCoversContent = backdrop != nil
                    && abs(backdropRect.minX) < 0.5 && abs(backdropRect.minY) < 0.5
                    && abs(backdropRect.width - host.bounds.width) < 0.5
                    && abs(backdropRect.height - host.bounds.height) < 0.5
                let backdropPassesInput = backdrop.map { $0.hitTest(NSPoint(x: 128, y: 12)) == nil } ?? false
                let valid = backdropCoversContent && backdropPassesInput
                    && abs(menu.frame.height - expectedHeight) < 0.5
                    && abs(presentedHeight - expectedHeight) < 0.5
                    && abs(topInset - 9) < 0.5 && abs(bottomInset - 5) < 0.5 && appearanceMatches
                layoutResults.append("\(valid ? "PASS" : "FAIL"): step=\(step) phase=\(radio.statusText.en) height=\(menu.frame.height) presented=\(presentedHeight) expected=\(expectedHeight) top=\(topInset) bottom=\(bottomInset) appearance=\(settings.appearance.rawValue) matches=\(appearanceMatches) backdropCoversContent=\(backdropCoversContent) backdropPassesInput=\(backdropPassesInput)")
                if [13, 27, 31, 37, 39].contains(step), let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    menu.effectiveAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
                    let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("menu-retry-step-\(step).png")
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
                }
            } else {
                layoutResults.append("INCOMPLETE: step=\(step), native menu was not visible")
            }
            let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("menu-retry-result.txt")
            try? layoutResults.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
        }
        let report = radio.diagnostics.report()
        if report != lastReport {
            lastReport = report
            let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("menu-live-diagnostics.txt")
            try? report.write(to: output, atomically: true, encoding: .utf8)
        }
        if automatic && step == 42 {
            timer?.invalidate()
            timer = nil
            guard layoutResults.count == 11 && layoutResults.allSatisfy({ $0.hasPrefix("PASS:") }) else {
                let message = "FAIL: Native retry layout validation incomplete or failed; see menu-retry-result.txt\n"
                FileHandle.standardError.write(Data(message.utf8))
                radio.pause()
                resolver.cancelPending()
                // exit(1) preserves the failed check for callers without a
                // Swift assertion trap or a macOS crash notification.
                UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite)
                exit(EXIT_FAILURE)
            }
            NSApp.terminate(nil)
        }
    }
}

private struct MenuLivePreview: App {
    @MenuState private var fixture = MenuLiveFixture()
    var body: some Scene {
        MenuBarExtra {
            CapturedMenuView(radio: fixture.radio, settings: fixture.settings)
        } label: {
            CapturedMenuBarLabel(signal: fixture.signal, radio: fixture.radio, settings: fixture.settings)
        }.menuBarExtraStyle(.window)
        .commands {
            CommandMenu("Preview Appearance") {
                Button("Light") { fixture.settings.appearance = .light }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Dark") { fixture.settings.appearance = .dark }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("System") { fixture.settings.appearance = .system }
                    .keyboardShortcut("0", modifiers: [.command, .option])
            }
        }
    }
}

@main
struct MenuSnapshots {
    @MainActor static func main() throws {
        if Bundle.main.bundleIdentifier == "local.victor.RadioBar.MenuPreview" {
            NSApplication.shared.setActivationPolicy(.regular)
            MenuLivePreview.main()
            return
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "RadioBar.MenuPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Station.bcc.rawValue, forKey: "station")
        let anchor = ContinuousClock().now
        let resolver = MenuPreviewResolver()
        let radio = RadioPlayer(resolver: resolver, defaults: defaults, sleepClockNow: { anchor })
        let settings = AppSettings(defaults: defaults, loginManager: MenuPreviewLogin())
        let signal = MenuBarSignal(reducedMotion: true)
        // Preserve the current bilingual titles at the unchanged 13 pt font.
        let titleBudget: CGFloat = 256 - 2*5 - 2*9 - 15 - 3*3 - 4 - 64
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
        for station in Station.allCases {
            for language in [AppLanguage.chinese, .traditionalChinese, .english] {
                let title = station.menuName.value(language)
                let measured = (title as NSString).size(withAttributes: attributes).width
                let budget = station.frequencyMHz == nil ? titleBudget + 67 : titleBudget
                precondition(measured <= budget, "Station title would truncate: \(title)")
                print("PASS: \(title) = \(String(format: "%.1f", measured)) pt <= \(budget) pt")
            }
        }
        let configurations: [(String, AppLanguage, Bool, String)] = [
            ("zh-removed-station", .chinese, false, "removed"),
            ("en-removed-station-dark", .english, true, "removed"),
            ("hant-light", .traditionalChinese, false, "paused"),
            ("hant-dark", .traditionalChinese, true, "paused"),
            ("hant-error", .traditionalChinese, false, "error"),
            ("en-volume-full", .english, false, "fullVolume"),
            ("zh-volume-muted-dark", .chinese, true, "muted"),
            ("zh-sorted-dark", .chinese, true, "sorted"),
            ("en-sorted", .english, false, "sorted"),
            ("zh-hidden-dark", .chinese, true, "hidden"),
            ("en-last-visible", .english, false, "lastVisible"),
            ("en-light", .english, false, "paused"), ("zh-light", .chinese, false, "paused"),
            ("en-dark", .english, true, "paused"), ("zh-dark", .chinese, true, "paused"),
            ("zh-force-dark", .chinese, false, "forceDark"),
            ("zh-force-light", .chinese, true, "forceLight"),
            ("en-timer", .english, false, "timer"),
            ("en-connecting", .english, false, "connecting"),
            ("en-retry", .english, false, "retry"),
            ("en-playing", .english, false, "playing"),
            ("en-playing-dark", .english, true, "playing"),
            ("en-buffering", .english, false, "buffering"),
            ("en-error", .english, false, "error")
        ]
        for (name, language, dark, state) in configurations {
            settings.resetStationOrder()
            for station in Station.allCases { settings.setStationVisible(station, true) }
            if state == "sorted" {
                settings.moveStation(.swissJazz, relativeTo: .kiss, after: false)
                settings.moveStation(.radioParadise, relativeTo: .kiss, after: false)
                settings.setStationVisible(.guangdong, false)
                settings.setStationVisible(.classic947, false)
            }
            if state == "hidden" {
                settings.setStationVisible(.guangdong, false)
                settings.setStationVisible(.classic947, false)
            } else if state == "lastVisible" {
                for station in Station.allCases where station != .kiss { settings.setStationVisible(station, false) }
            }
            settings.appearance = state == "forceDark" ? .dark : state == "forceLight" ? .light : .system
            settings.language = language
            radio.volume = state == "fullVolume" ? 1 : 0.65
            if state == "muted" { radio.toggleMute() }
            radio.pause()
            radio.station = state == "removed" ? Station(id: "custom.removed", title: RadioText("已移除电台", "Removed station"),
                                                         category: RadioText("自定义", "Custom")) : .bcc
            resolver.cancelPending()
            radio.sleepTimer.cancel()
            resolver.shouldFail = state == "retry"
            if state == "timer" {
                radio.sleepTimer.minutesInput = "720"
                radio.sleepTimer.start()
            } else if state == "connecting" || state == "retry" { radio.play() }
            else if state == "playing" || state == "buffering" {
                radio.wantsPlayback = true
                radio.isPlaying = true
                radio.statusText = state == "playing" ? RadioText("播放中", "Playing") : RadioText("缓冲中…", "Buffering…")
            } else if state == "error" { radio.statusText = RadioText("连接失败", "Connection failed") }
            let root = CapturedMenuView(radio: radio, settings: settings)
            try capture(root, name: name, dark: dark, output: output)
            if state == "connecting" { precondition(radio.wantsPlayback && !radio.needsAttention) }
            if state == "retry" { precondition(radio.needsAttention) }
        }
        verifyResumeLayout(radio: radio, settings: settings, resolver: resolver)
        radio.pause()
        resolver.cancelPending()
        radio.sleepTimer.cancel()

        for dark in [false, true] {
            let rows = VStack(spacing: 0) {
                CompactMenuRow(title: "BCC i Radio", symbol: "checkmark", trailingText: "FM 96.3", action: {})
                CompactMenuRow(title: "UFO Radio", symbol: nil, trailingText: "FM 92.1", previewHovered: true, action: {})
                CompactMenuRow(title: "BCC i Radio", symbol: "checkmark", trailingText: "FM 96.3", previewHovered: true, action: {})
                CompactMenuRow(title: "Play", symbol: "play.fill", previewHovered: true, action: {})
                CompactMenuRow(title: "Pause", symbol: "pause.fill", previewHovered: true, action: {})
                CompactMenuRow(title: "Reconnect", symbol: "arrow.clockwise", previewHovered: true, action: {})
                CompactMenuRow(title: "Settings…", symbol: "gearshape", previewHovered: true, action: {})
                CompactMenuRow(title: "Quit RadioBar", symbol: "power", previewHovered: true, action: {})
            }
            .font(.system(size: 13)).padding(5).frame(width: 256)
            try capture(rows, name: dark ? "hover-dark" : "hover-light", dark: dark, output: output)
        }
        // Render the actual scene label in both modes; no live status item or audio.
        for language in [AppLanguage.chinese, .traditionalChinese, .english] {
            settings.language = language
            radio.station = .guangdong
            for mode in MenuBarDisplay.allCases {
                settings.menuBarDisplay = mode
                let label = HStack {
                    CapturedMenuBarLabel(signal: signal, radio: radio, settings: settings)
                    Spacer(minLength: 0)
                }.font(.system(size: 13)).padding(8).frame(width: 256, height: 32)
                try capture(label, name: "label-\(language.rawValue)-\(mode.rawValue)", dark: false, output: output)
            }
        }
        for (tag, minutes) in [("minutes", "30"), ("hour", "60"), ("maximum", "720")] {
            radio.sleepTimer.minutesInput = minutes
            radio.sleepTimer.start()
            radio.station = Station(id: "custom.long-name", title: RadioText("这是一段需要截断的很长的自定义电台名称", "An unusually long custom station name for layout testing"), category: RadioText("音乐", "Music"))
            for language in [AppLanguage.chinese, .traditionalChinese, .english] {
                settings.language = language
                for mode in MenuBarDisplay.allCases {
                    settings.menuBarDisplay = mode
                    for visible in [true, false] {
                        settings.showSleepTimerInMenuBar = visible
                        let label = CapturedMenuBarLabel(signal: signal, radio: radio, settings: settings)
                            .font(.system(size: 13)).padding(8).frame(width: 256, height: 32)
                        try capture(label, name: "clock-\(language.rawValue)-\(mode.rawValue)-\(tag)-\(visible)", dark: language == .english, output: output)
                    }
                }
            }
        }
        radio.sleepTimer.cancel()
        radio.station = .guangdong
        settings.showSleepTimerInMenuBar = true
        settings.language = .english
        settings.menuBarDisplay = .iconAndStation
        radio.wantsPlayback = true
        radio.isPlaying = true
        radio.statusText = RadioText("播放中", "Playing")
        signal.setAnimationEnabled(true)
        for reduced in [false, true] {
            signal.setReducedMotion(reduced)
            signal.setPlaying(true)
            let label = HStack {
                CapturedMenuBarLabel(signal: signal, radio: radio, settings: settings)
                Spacer(minLength: 0)
            }.font(.system(size: 13)).padding(8).frame(width: 256, height: 32)
            try capture(label, name: reduced ? "label-playing-reduced-motion" : "label-playing", dark: false, output: output)
        }
        signal.setPlaying(false)
        radio.pause()
        precondition(menuStatusTint(isPlaying: true, wantsPlayback: true, needsAttention: false, status: RadioText("播放中", "Playing")) == .green)
        precondition(menuStatusTint(isPlaying: false, wantsPlayback: false, needsAttention: false, status: RadioText("已暂停", "Paused")) == .secondary)
        precondition(menuStatusTint(isPlaying: false, wantsPlayback: true, needsAttention: false, status: RadioText("连接中…", "Connecting…")) == .orange)
        precondition(menuStatusTint(isPlaying: true, wantsPlayback: true, needsAttention: false, status: RadioText("缓冲中…", "Buffering…")) == .orange)
        precondition(menuStatusTint(isPlaying: false, wantsPlayback: false, needsAttention: true, status: RadioText("连接失败", "Connection failed")) == .red)
        precondition(menuStatusTint(isPlaying: false, wantsPlayback: true, needsAttention: true, status: RadioText("等待重试", "Retrying")) == .red)
        print("PASS: existing status dot colors; buffering with an active player stays orange; failure/retry are red")
    }

    // Exercise the production root directly, without the snapshot helper's
    // fixedSize wrapper or an artificial, center-aligned SwiftUI parent frame.
    // This checks content edges/intrinsic sizing, not MenuBarExtra positioning.
    @MainActor private static func verifyResumeLayout(radio: RadioPlayer, settings: AppSettings,
                                                       resolver: MenuPreviewResolver) {
        settings.resetStationOrder()
        radio.sleepTimer.cancel()
        let hosting = NSHostingView(rootView: CapturedMenuView(radio: radio, settings: settings))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 256, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        func findProbe(_ name: String, in view: NSView) -> NSView? {
            if view.identifier?.rawValue == name { return view }
            return view.subviews.lazy.compactMap { findProbe(name, in: $0) }.first
        }
        for language in [AppLanguage.chinese, .traditionalChinese, .english] {
            settings.language = language
            for count in [Station.allCases.count, 7, 1] {
                for (index, station) in Station.allCases.enumerated() {
                    settings.setStationVisible(station, index < count)
                }
                var normalHeight: CGFloat?
                for state in ["paused", "connecting", "buffering", "retry", "longRetry", "buffering", "playing", "error", "paused"] {
                    radio.pause()
                    resolver.cancelPending()
                    resolver.shouldFail = false
                    switch state {
                    case "connecting": radio.toggle()
                    case "buffering", "playing":
                        radio.wantsPlayback = true
                        radio.isPlaying = state == "playing"
                        radio.statusText = state == "playing" ? RadioText("播放中", "Playing") : RadioText("缓冲中…", "Buffering…")
                    case "retry", "longRetry":
                        radio.wantsPlayback = true
                        radio.statusText = RadioText("等待重试（1/4）", "Retrying (1/4)")
                        radio.detailText = RadioText("连接暂时中断，稍后自动重试", "Connection interrupted. Retrying shortly.")
                        if state == "longRetry" {
                            radio.detailText = RadioText(String(repeating: "连接中断，稍后自动重试。", count: 20),
                                                         String(repeating: "Connection interrupted. Retrying shortly. ", count: 20))
                            settings.appearance = .dark
                        }
                    case "error": radio.statusText = RadioText("连接失败", "Connection failed")
                    default: break
                    }
                    if state == "playing" { settings.appearance = .light }
                    if state == "paused" { settings.appearance = .system }
                    for _ in 0..<3 {
                        hosting.layoutSubtreeIfNeeded()
                        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
                    }
                    let size = hosting.fittingSize
                    precondition(abs(size.width - 256) < 0.5 && size.height < 600)
                    window.setContentSize(size)
                    hosting.layoutSubtreeIfNeeded()
                    let header = findProbe("menuHeaderProbe", in: hosting)!
                    let bottom = findProbe("menuBottomProbe", in: hosting)!
                    let headerRect = header.convert(header.bounds, to: hosting)
                    let bottomRect = bottom.convert(bottom.bounds, to: hosting)
                    let topInset = hosting.isFlipped ? headerRect.minY : hosting.bounds.height - headerRect.maxY
                    let bottomInset = hosting.isFlipped ? hosting.bounds.height - bottomRect.maxY : bottomRect.minY
                    precondition(abs(topInset - 9) < 0.5 && abs(bottomInset - 5) < 0.5,
                                 "Menu edges drifted or left blank space in the native host")
                    if let normalHeight {
                        precondition(abs(size.height - normalHeight) < 0.5,
                                     "Recovery state or appearance changed the compact menu height")
                    } else { normalHeight = size.height }
                    print("PASS: \(language.rawValue) / \(count) stations / \(state): \(size), top=\(topInset), bottom=\(bottomInset)")
                }
            }
        }
        for station in Station.allCases { settings.setStationVisible(station, true) }
        precondition(radio.diagnostics.snapshot().lines.contains { $0.contains("menu.layout") && $0.contains("contentOrigin=") })
        print("PASS: native window geometry reaches the bounded diagnostics store")
        print("PASS: live menu host intrinsic size and both content edges across playback states and station counts")
    }

    @MainActor private static func capture<Content: View>(_ content: Content, name: String, dark: Bool, output: URL) throws {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        NSApp.appearance = appearance
        let root = content.fixedSize()
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.controlActiveState, .key)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 256, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = hosting
        for _ in 0..<3 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let size = hosting.fittingSize
        precondition(size.width == 256 && size.height > 0 && size.height < 600)
        window.setContentSize(size)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        if name.hasPrefix("hover-") {
            func selectionEffects(_ view: NSView) -> [NSVisualEffectView] {
                let own = (view as? NSVisualEffectView).map { $0.material == .selection ? [$0] : [] } ?? []
                return own + view.subviews.flatMap(selectionEffects)
            }
            let effects = selectionEffects(hosting)
            precondition(effects.count == 7)
            precondition(effects.allSatisfy { $0.blendingMode == .withinWindow && $0.state == .active && $0.isEmphasized })
            print("PASS: seven hover materials configured as selection / withinWindow / active / emphasized")
        }
        let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        }
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        print("Rendered \(name): \(Int(size.width))x\(Int(size.height)) pt; expected width verified")
        window.contentView = nil
        window.close()
    }
}
