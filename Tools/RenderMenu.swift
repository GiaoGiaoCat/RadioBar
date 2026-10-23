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

/// Read inside the production menu's radioAppearance scope, without drawing or
/// altering its layout. Native appearance alone cannot prove SwiftUI agrees.
private struct MenuColorSchemeProbe: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    final class Probe: NSView {
        var colorScheme: ColorScheme = .light
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.colorScheme = colorScheme
        return view
    }
    func updateNSView(_ view: Probe, context: Context) { view.colorScheme = colorScheme }
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
    private let appearanceSettingsController = SettingsWindowController()
    private let interactiveSettingsController = SettingsWindowController()
    private var interactiveSettingsConfigured = false
    private let shortListInteractive = ProcessInfo.processInfo.environment["RADIOBAR_MENU_SHORT_LIST_INTERACTIVE"] == "1"
    private let shortListAutomatic = ProcessInfo.processInfo.environment["RADIOBAR_MENU_SHORT_LIST_AUTORUN"] == "1"
    private var shortListInitialStations: [Station] = []
    private var shortListActions: [String] = []
    private var shortListGeometry: [String] = []
    private var shortListInitialAnchorGap: CGFloat?
    private var interactiveControlsWindow: NSWindow?
    private var interactiveControlsActions: InteractiveControlsActions?
    private final class InteractiveControlsActions: NSObject {
        var toggleMenu: () -> Void = {}
        var openSettings: () -> Void = {}
        @objc func toggleMenuPressed(_ sender: NSButton) { toggleMenu() }
        @objc func openSettingsPressed(_ sender: NSButton) { openSettings() }
    }
    private weak var appearanceMenuWindow: NSWindow?
    private weak var appearanceSettingsWindow: NSWindow?
    private var simulatedSystemAppearance: NSAppearance.Name = .aqua
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
        let appearanceAutomatic = ProcessInfo.processInfo.environment["RADIOBAR_MENU_APPEARANCE_AUTORUN"] == "1"
        if appearanceAutomatic { NSApp.appearance = NSAppearance(named: simulatedSystemAppearance) }
        radio = RadioPlayer(resolver: resolver, defaults: defaults,
                            sleepClockNow: { labelAutomatic ? clock.now : ContinuousClock().now })
        settings = AppSettings(defaults: defaults, loginManager: MenuPreviewLogin())
        settings.language = .english
        let visible: [Station] = [.kiss, .musicRadio, .bcc, .asiaFM, .guangdong, .grooveSalad, .swissJazz]
        for station in Station.allCases { settings.setStationVisible(station, visible.contains(station)) }
        shortListInitialStations = visible
        if ProcessInfo.processInfo.environment["RADIOBAR_MENU_LABEL_AUTORUN"] == "1" {
            settings.menuBarDisplay = .iconAndStation
            radio.station = .grooveSalad
        }
        settings.animateMenuBarIcon = true
        signal = MenuBarSignal(radio: radio, settings: settings)
        if (shortListInteractive || shortListAutomatic) && !labelAutomatic && !appearanceAutomatic
            && ProcessInfo.processInfo.environment["RADIOBAR_MENU_AUTORUN"] != "1" {
            interactiveSettingsController.configure(settings: settings)
            interactiveSettingsConfigured = true
        }
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
        let interval = ProcessInfo.processInfo.environment["RADIOBAR_MENU_AUTORUN"] == "1" || labelAutomatic || appearanceAutomatic || shortListAutomatic ? 0.2 : 0.5
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordGeometry() }
        }
        if shortListAutomatic, let timer {
            // A native status-button action can enter an event-tracking run
            // loop. Keep this independent lifecycle driver eligible there.
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    func showSettings(_ page: SettingsPage?) {
        if !interactiveSettingsConfigured {
            interactiveSettingsController.configure(settings: settings)
            interactiveSettingsConfigured = true
        }
        interactiveSettingsController.show(settings: settings, timer: radio.sleepTimer, page: page)
    }
    private func showInteractiveControls() {
        guard shortListInteractive else { return }
        if interactiveControlsWindow == nil {
            let actions = InteractiveControlsActions()
            actions.toggleMenu = { [weak self] in
                // Leave this button's mouse-up event before asking the real
                // status item to present or dismiss its native menu window.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.statusButton()?.performClick(nil)
                }
            }
            actions.openSettings = { [weak self] in self?.showSettings(.channels) }
            let toggle = NSButton(title: "Toggle menu", target: actions,
                                  action: #selector(InteractiveControlsActions.toggleMenuPressed(_:)))
            let settings = NSButton(title: "Open settings", target: actions,
                                    action: #selector(InteractiveControlsActions.openSettingsPressed(_:)))
            toggle.bezelStyle = .rounded
            settings.bezelStyle = .rounded
            let stack = NSStackView(views: [toggle, settings])
            stack.orientation = .vertical
            stack.spacing = 10
            stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 110),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Menu layout controls"
            window.isReleasedWhenClosed = false
            window.contentView = stack
            if let screen = NSScreen.main {
                window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 24, y: screen.visibleFrame.minY + 24))
            }
            interactiveControlsActions = actions
            interactiveControlsWindow = window
        }
        // This test-only window does not participate in the production
        // settings controller's Dock policy or termination handling.
        interactiveControlsWindow?.orderFront(nil)
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
    private func recordAppearance() {
        if step == 2 { statusButton()?.performClick(nil) }
        // The first status-button presentation enters event tracking. As with
        // the geometry mode, let it settle before reusing the native window.
        let phase = step - 24
        func system(_ name: NSAppearance.Name) {
            simulatedSystemAppearance = name
            NSApp.appearance = NSAppearance(named: name)
        }
        if phase == 40 {
            // Check before ordering the window front: an unrelated SwiftUI
            // update during presentation must not conceal a retained override.
            checkAppearance(name: "injected-same-color-system-hidden", expectedVisible: false)
        }
        switch phase {
        case 1:
            settings.appearance = .system
            menuWindow()?.makeKeyAndOrderFront(nil)
        case 4, 8, 12, 18, 22, 28, 34:
            menuWindow()?.orderOut(nil)
        case 5: settings.appearance = .dark
        case 9: settings.appearance = .light
        case 13:
            settings.appearance = .system
            system(.darkAqua)
        case 6, 10, 14, 20, 26, 32, 36, 40, 44, 48:
            menuWindow()?.makeKeyAndOrderFront(nil)
        case 16: system(.aqua)
        case 19: system(.darkAqua)
        case 23:
            appearanceSettingsController.configure(settings: settings)
            appearanceSettingsController.show(settings: settings, timer: radio.sleepTimer, page: .general)
            appearanceSettingsWindow = appearanceSettingsController.window
            settings.appearance = .light
        case 25, 31: appearanceSettingsController.window?.performClose(nil)
        case 29:
            appearanceSettingsController.show(settings: settings, timer: radio.sleepTimer, page: .general)
            settings.appearance = .dark
        case 35:
            // Deliberate stale-host injection validates recovery on reopen. It
            // does not reproduce or explain the user's physical-screen symptom.
            menuWindow()?.appearance = NSAppearance(named: .aqua)
        case 38:
            menuWindow()?.orderOut(nil)
            settings.appearance = .system
            system(.darkAqua)
        case 39:
            // Same resolved color, but system mode must clear this override.
            menuWindow()?.appearance = NSAppearance(named: .darkAqua)
        case 42:
            menuWindow()?.orderOut(nil)
            settings.appearance = .light
        case 43:
            menuWindow()?.appearance = NSAppearance(named: .darkAqua)
        case 46:
            menuWindow()?.orderOut(nil)
            settings.appearance = .system
            system(.aqua)
        case 47:
            menuWindow()?.appearance = NSAppearance(named: .darkAqua)
        case 50: system(.darkAqua)
        case 52: system(.aqua)
        default: break
        }
        let checks = [
            3: "initial-system-light", 7: "hidden-to-dark", 11: "hidden-to-light",
            15: "hidden-to-system-dark", 17: "visible-system-to-light", 21: "hidden-system-to-dark",
            27: "settings-light-close-reopen", 33: "settings-dark-close-reopen",
            37: "injected-light-override-with-dark-choice", 41: "injected-same-color-system-override",
            45: "injected-dark-override-with-light-choice", 49: "injected-dark-override-with-system-light",
            51: "visible-system-to-dark", 53: "visible-system-back-to-light"
        ]
        if let name = checks[phase] { checkAppearance(name: name) }
        if phase == 54 {
            timer?.invalidate()
            timer = nil
            let passed = layoutResults.count == checks.count + 1 && layoutResults.allSatisfy { $0.hasPrefix("PASS:") }
            let header = "Native appearance integration; isolated preferences and simulated NSApp appearance.\nStale-host overrides are deliberate injections, not a reproduction of the physical-screen symptom.\nContent caches do not verify desktop glass compositing or real mouse interaction.\n"
            let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("menu-appearance-result.txt")
            try? (header + layoutResults.joined(separator: "\n") + "\n").write(to: output, atomically: true, encoding: .utf8)
            appearanceSettingsController.window?.performClose(nil)
            radio.pause()
            resolver.cancelPending()
            UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite)
            if !passed {
                FileHandle.standardError.write(Data("FAIL: Native appearance validation; see menu-appearance-result.txt\n".utf8))
                exit(EXIT_FAILURE)
            }
            NSApp.terminate(nil)
        }
    }
    private func checkAppearance(name: String, expectedVisible: Bool = true) {
        func find(_ identifier: String, in view: NSView) -> NSView? {
            if view.identifier?.rawValue == identifier { return view }
            return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
        }
        func schemeProbe(in view: NSView) -> MenuColorSchemeProbe.Probe? {
            if let probe = view as? MenuColorSchemeProbe.Probe { return probe }
            return view.subviews.lazy.compactMap { schemeProbe(in: $0) }.first
        }
        func effects(in view: NSView) -> [NSVisualEffectView] {
            ((view as? NSVisualEffectView).map { [$0] } ?? []) + view.subviews.flatMap { effects(in: $0) }
        }
        guard let menu = menuWindow(), menu.isVisible == expectedVisible, let host = menu.contentView,
              let header = find("menuHeaderProbe", in: host), let bottom = find("menuBottomProbe", in: host),
              let backdrop = find("radioMenuBackground", in: host) as? NSVisualEffectView,
              let probe = schemeProbe(in: host) else {
            layoutResults.append("INCOMPLETE: \(name), native menu/background/SwiftUI probe unavailable")
            return
        }
        if appearanceMenuWindow == nil { appearanceMenuWindow = menu }
        let expected = settings.appearance.nativeAppearance?.name ?? simulatedSystemAppearance
        let nativeMatches = menu.appearance?.name == settings.appearance.nativeAppearance?.name
            && menu.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected
        let materialMatches = backdrop.material == .menu && backdrop.blendingMode == .behindWindow
            && backdrop.state == .active && backdrop.appearance == nil
        let effectsMatch = effects(in: host).allSatisfy {
            $0.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected
        }
        let schemeMatches = probe.colorScheme == (expected == .darkAqua ? ColorScheme.dark : .light)
        let headerRect = header.convert(header.bounds, to: host)
        let bottomRect = bottom.convert(bottom.bounds, to: host)
        let topInset = host.isFlipped ? headerRect.minY : host.bounds.height - headerRect.maxY
        let bottomInset = host.isFlipped ? host.bounds.height - bottomRect.maxY : bottomRect.minY
        let expectedHeight = CGFloat(208 + 24 * settings.visibleStations.count)
        let presentedHeight = host.layer?.presentation()?.bounds.height ?? host.bounds.height
        let backgroundRect = backdrop.convert(backdrop.bounds, to: host)
        let geometryMatches = abs(menu.frame.height - expectedHeight) < 0.5
            && abs(presentedHeight - expectedHeight) < 0.5
            && abs(topInset - 9) < 0.5 && abs(bottomInset - 5) < 0.5
            && abs(backgroundRect.minX) < 0.5 && abs(backgroundRect.minY) < 0.5
            && abs(backgroundRect.width - host.bounds.width) < 0.5
            && abs(backgroundRect.height - host.bounds.height) < 0.5
        let inputPasses = backdrop.hitTest(NSPoint(x: 128, y: 12)) == nil
        let appUnchanged = NSApp.appearance?.name == simulatedSystemAppearance
        let settingsClosed = !name.hasPrefix("settings-") || (
            appearanceSettingsController.window === appearanceSettingsWindow
            && appearanceSettingsWindow?.isVisible == false
            && appearanceSettingsWindow?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected
            && NSApp.activationPolicy() == .accessory)
        let reusedWindow = menu === appearanceMenuWindow
        let valid = nativeMatches && materialMatches && effectsMatch && schemeMatches && geometryMatches
            && inputPasses && appUnchanged && settingsClosed && reusedWindow
        layoutResults.append("\(valid ? "PASS" : "FAIL"): \(name) visible=\(menu.isVisible) choice=\(settings.appearance.rawValue) expected=\(expected.rawValue) native=\(nativeMatches) effects=\(effectsMatch) swiftUI=\(schemeMatches) material=\(materialMatches) geometry=\(geometryMatches) input=\(inputPasses) appUnchanged=\(appUnchanged) settingsClosed=\(settingsClosed) reusedWindow=\(reusedWindow)")
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            menu.effectiveAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
            let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("menu-appearance-\(name).png")
            try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
        }
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
        if ProcessInfo.processInfo.environment["RADIOBAR_MENU_APPEARANCE_AUTORUN"] == "1" {
            recordAppearance()
            return
        }
        if ProcessInfo.processInfo.environment["RADIOBAR_MENU_LABEL_AUTORUN"] == "1" {
            recordLabelGeometry()
            return
        }
        if shortListAutomatic {
            recordShortListLifecycle()
            return
        }
        let automatic = ProcessInfo.processInfo.environment["RADIOBAR_MENU_AUTORUN"] == "1"
        if shortListInteractive && !automatic && self.step == 4 {
            // Open the real production settings path only after SwiftUI's
            // application startup settles. Subsequent changes are user driven.
            showInteractiveControls()
            showSettings(.channels)
        }
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
            case 42, 46, 50, 54, 58, 62: menuWindow()?.orderOut(nil)
            case 43, 47, 51, 55, 59, 63:
                let count = [43: 12, 47: 5, 51: 1, 55: 12, 59: 5, 63: 7][step]!
                for (index, station) in Station.allCases.enumerated() {
                    settings.setStationVisible(station, index < count)
                }
            case 44, 48, 52, 56, 60, 64: menuWindow()?.makeKeyAndOrderFront(nil)
            default: break
            }
        }
        if automatic && [9, 13, 17, 21, 25, 27, 31, 35, 37, 39, 41, 45, 49, 53, 57, 61, 65].contains(step) {
            func find(_ identifier: String, in view: NSView) -> NSView? {
                if view.identifier?.rawValue == identifier { return view }
                return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
            }
            let menu = NSApp.windows.first { window in
                window.contentView.map { find("menuHeaderProbe", in: $0) != nil } ?? false
            }
            let expectedHeight = CGFloat(208 + 24 * settings.visibleStations.count)
            if let menu, menu.isVisible, let host = menu.contentView,
               let header = find("menuHeaderProbe", in: host), let bottom = find("menuBottomProbe", in: host) {
                let headerRect = header.convert(header.bounds, to: host)
                let bottomRect = bottom.convert(bottom.bounds, to: host)
                let topInset = host.isFlipped ? headerRect.minY : host.bounds.height - headerRect.maxY
                let bottomInset = host.isFlipped ? host.bounds.height - bottomRect.maxY : bottomRect.minY
                let presentedHeight = host.layer?.presentation()?.bounds.height ?? host.bounds.height
                let expectedAppearance = settings.appearance.nativeAppearance?.name
                    ?? NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                let appearanceMatches = menu.appearance?.name == settings.appearance.nativeAppearance?.name
                    && menu.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expectedAppearance
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
                if [13, 27, 31, 37, 39, 45, 49, 53, 57, 61, 65].contains(step), let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
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
        var report = radio.diagnostics.report()
        if !automatic { report += "\n" + interactiveGeometryReport() }
        if report != lastReport {
            lastReport = report
            let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("menu-live-diagnostics.txt")
            try? report.write(to: output, atomically: true, encoding: .utf8)
        }
        if automatic && step == 66 {
            timer?.invalidate()
            timer = nil
            guard layoutResults.count == 17 && layoutResults.allSatisfy({ $0.hasPrefix("PASS:") }) else {
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
    private func recordShortListLifecycle() {
        let phaseMarker = shortListActions.count + layoutResults.count
        switch step {
        case 8, 42, 74, 106:
            if let button = statusButton() {
                shortListActions.append("ACTION: step=\(step) statusButton.performClick")
                // Finish the timer callback before entering native presentation.
                DispatchQueue.main.async { button.performClick(nil) }
            } else {
                layoutResults.append("INCOMPLETE: step=\(step) native status button unavailable")
            }
        case 14: checkShortListMenu(name: "initial-seven", expectedCount: 7)
        case 18, 52, 84:
            shortListActions.append("ACTION: step=\(step) production settings show channels")
            DispatchQueue.main.async { [weak self] in self?.showSettings(.channels) }
        case 20, 53, 85:
            // Programmatic settings presentation need not dismiss the extra.
            // Toggle it through its real status button before changing rows.
            if menuWindow()?.isVisible == true {
                if let button = statusButton() {
                    shortListActions.append("ACTION: step=\(step) statusButton.performClick to close visible menu")
                    DispatchQueue.main.async { button.performClick(nil) }
                } else {
                    layoutResults.append("INCOMPLETE: step=\(step) cannot close menu through native status button")
                }
            }
        case 22, 54, 86:
            let settingsVisible = interactiveSettingsController.window?.isVisible == true
            let menuVisible = menuWindow()?.isVisible == true
            layoutResults.append("\(settingsVisible && !menuVisible ? "PASS" : "FAIL"): step=\(step) settings-open settingsVisible=\(settingsVisible) menuVisible=\(menuVisible)")
        case 24, 26, 28, 30, 32, 34, 88, 90, 92, 94, 96, 98:
            if let station = settings.visibleStations.last, settings.visibleStations.count > 1 {
                settings.setStationVisible(station, false)
                shortListActions.append("ACTION: step=\(step) hide-one visibleCount=\(settings.visibleStations.count)")
            } else {
                layoutResults.append("INCOMPLETE: step=\(step) cannot hide next station")
            }
        case 56, 58, 60, 62, 64, 66:
            let index = (step - 56) / 2 + 1
            settings.setStationVisible(shortListInitialStations[index], true)
            shortListActions.append("ACTION: step=\(step) show-one visibleCount=\(settings.visibleStations.count)")
        case 38, 70, 102:
            shortListActions.append("ACTION: step=\(step) production settings performClose")
            DispatchQueue.main.async { [weak self] in self?.interactiveSettingsController.window?.performClose(nil) }
        case 48: checkShortListMenu(name: "seven-to-one", expectedCount: 1)
        case 80: checkShortListMenu(name: "one-to-seven", expectedCount: 7)
        case 112: checkShortListMenu(name: "seven-to-one-again", expectedCount: 1)
        default: break
        }
        let header = "Native short-list lifecycle; isolated preferences and simulated playback.\nNormal 7 -> 1 -> 7 -> 1 presentations use only the real status button, production settings open/close, and visibility setters.\nNo manual menu sizing or direct menu-window visibility changes.\nAutomated native actions do not verify physical mouse interaction or audio.\n"
        let geometry = interactiveGeometryReport()
        let report = radio.diagnostics.report() + "\n" + geometry
        if report != lastReport || phaseMarker != shortListActions.count + layoutResults.count {
            shortListGeometry.append("GEOMETRY: step=\(step)\n" + geometry)
        }
        if report != lastReport {
            lastReport = report
            let diagnostics = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("menu-live-diagnostics.txt")
            try? report.write(to: diagnostics, atomically: true, encoding: .utf8)
        }
        let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("menu-short-list-result.txt")
        try? (header + shortListActions.joined(separator: "\n") + "\n" + layoutResults.joined(separator: "\n")
              + "\n" + shortListGeometry.joined(separator: "\n") + "\n")
            .write(to: output, atomically: true, encoding: .utf8)
        if step == 116 {
            timer?.invalidate()
            timer = nil
            radio.pause()
            resolver.cancelPending()
            UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite)
            let passed = layoutResults.count == 7 && layoutResults.allSatisfy { $0.hasPrefix("PASS:") }
            if !passed {
                FileHandle.standardError.write(Data("FAIL: Native short-list lifecycle validation; see menu-short-list-result.txt\n".utf8))
                exit(EXIT_FAILURE)
            }
            NSApp.terminate(nil)
        }
    }
    private func checkShortListMenu(name: String, expectedCount: Int) {
        func find(_ identifier: String, in view: NSView) -> NSView? {
            if view.identifier?.rawValue == identifier { return view }
            return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
        }
        guard let menu = menuWindow(), let host = menu.contentView,
              let header = find("menuHeaderProbe", in: host), let bottom = find("menuBottomProbe", in: host) else {
            layoutResults.append("INCOMPLETE: step=\(step) \(name) native menu/window bounds probes unavailable")
            return
        }
        let expectedHeight = CGFloat(208 + 24 * expectedCount)
        let headerRect = header.convert(header.bounds, to: host)
        let bottomRect = bottom.convert(bottom.bounds, to: host)
        let topInset = host.isFlipped ? headerRect.minY : host.bounds.height - headerRect.maxY
        let bottomInset = host.isFlipped ? host.bounds.height - bottomRect.maxY : bottomRect.minY
        let presentedHeight = host.layer?.presentation()?.bounds.height ?? host.bounds.height
        let settingsClosed = interactiveSettingsController.window?.isVisible != true
        let statusWindowFrame = statusButton()?.window?.frame
        let anchorGap = statusWindowFrame.map { $0.minY - menu.frame.maxY }
        if shortListInitialAnchorGap == nil { shortListInitialAnchorGap = anchorGap }
        let anchorMatches: Bool
        if let anchorGap, let initialGap = shortListInitialAnchorGap {
            anchorMatches = abs(anchorGap - initialGap) < 0.5
        } else { anchorMatches = false }
        let valid = menu.isVisible && settingsClosed && settings.visibleStations.count == expectedCount
            && abs(menu.frame.height - expectedHeight) < 0.5
            && abs(host.bounds.height - expectedHeight) < 0.5
            && abs(presentedHeight - expectedHeight) < 0.5
            && abs(topInset - 9) < 0.5 && abs(bottomInset - 5) < 0.5 && anchorMatches
        layoutResults.append("\(valid ? "PASS" : "FAIL"): step=\(step) \(name) visible=\(menu.isVisible) settingsClosed=\(settingsClosed) count=\(settings.visibleStations.count) expectedCount=\(expectedCount) expectedHeight=\(expectedHeight) actualHeight=\(menu.frame.height) hostHeight=\(host.bounds.height) presentedHeight=\(presentedHeight) topInset=\(topInset) bottomInset=\(bottomInset) minX=\(menu.frame.minX) maxY=\(menu.frame.maxY) statusButtonWindowMinY=\(String(describing: statusWindowFrame?.minY)) anchorGap=\(String(describing: anchorGap)) initialAnchorGap=\(String(describing: shortListInitialAnchorGap)) anchorMatches=\(anchorMatches)")
    }
    private func interactiveGeometryReport() -> String {
        func find(_ identifier: String, in view: NSView) -> NSView? {
            if view.identifier?.rawValue == identifier { return view }
            return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
        }
        var lines = [
            "Interactive preview; isolated preferences and simulated playback.",
            "visibleStations=\(settings.visibleStations.count) settingsVisible=\(interactiveSettingsController.window?.isVisible ?? false) activationPolicy=\(NSApp.activationPolicy().rawValue)"
        ]
        if let button = statusButton() {
            lines.append("statusButtonFrame=\(button.frame) statusButtonWindowFrame=\(button.window?.frame ?? .zero)")
        }
        guard let menu = menuWindow(), let host = menu.contentView else {
            lines.append("menuWindow=unavailable")
            for (index, window) in NSApp.windows.enumerated() {
                let host = window.contentView
                lines.append("nativeWindow[\(index)]=\(String(describing: type(of: window))) visible=\(window.isVisible) frame=\(window.frame) contentClass=\(host.map { String(describing: type(of: $0)) } ?? "none") contentFrame=\(host?.frame ?? .zero) contentBounds=\(host?.bounds ?? .zero)")
            }
            return lines.joined(separator: "\n")
        }
        lines.append("menuVisible=\(menu.isVisible) frame=\(menu.frame) minX=\(menu.frame.minX) maxY=\(menu.frame.maxY) contentMinSize=\(menu.contentMinSize) contentMaxSize=\(menu.contentMaxSize)")
        lines.append("hostClass=\(String(describing: type(of: host))) hostFrame=\(host.frame) hostBounds=\(host.bounds) intrinsicContentSize=\(host.intrinsicContentSize) fittingSize=\(host.fittingSize) presentedBounds=\(host.layer?.presentation()?.bounds ?? host.bounds)")
        for (index, view) in host.subviews.enumerated() {
            lines.append("hostSubview[\(index)]=\(String(describing: type(of: view))) frame=\(view.frame) bounds=\(view.bounds) intrinsicContentSize=\(view.intrinsicContentSize) fittingSize=\(view.fittingSize)")
        }
        if let background = find("radioMenuBackground", in: host) {
            lines.append("backgroundInHost=\(background.convert(background.bounds, to: host))")
        }
        if let header = find("menuHeaderProbe", in: host), let bottom = find("menuBottomProbe", in: host) {
            let headerRect = header.convert(header.bounds, to: host)
            let bottomRect = bottom.convert(bottom.bounds, to: host)
            let topInset = host.isFlipped ? headerRect.minY : host.bounds.height - headerRect.maxY
            let bottomInset = host.isFlipped ? host.bounds.height - bottomRect.maxY : bottomRect.minY
            lines.append("expectedHeight=\(208 + 24 * settings.visibleStations.count) topInset=\(topInset) bottomInset=\(bottomInset) header=\(headerRect) bottom=\(bottomRect)")
        }
        return lines.joined(separator: "\n")
    }
}

private struct MenuLivePreview: App {
    @MenuState private var fixture: MenuLiveFixture
    @StateObject private var settings: AppSettings
    init() {
        let fixture = MenuLiveFixture()
        _fixture = MenuState(initialValue: fixture)
        _settings = StateObject(wrappedValue: fixture.settings)
    }
    var body: some Scene {
        MenuBarExtra {
            CapturedMenuView(radio: fixture.radio, settings: settings) { page in
                fixture.showSettings(page)
            }
                .id(settings.visibleStations.map(\.id))
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
        if ProcessInfo.processInfo.environment["RADIOBAR_MENU_CACHED_HOST_ONLY"] == "1" {
            if !verifyCachedHostSizing(output: output) { exit(EXIT_FAILURE) }
            return
        }
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
            ("en-last-visible-dark", .english, true, "lastVisible"),
            ("zh-last-visible", .chinese, false, "lastVisible"),
            ("zh-last-visible-dark", .chinese, true, "lastVisible"),
            ("hant-last-visible", .traditionalChinese, false, "lastVisible"),
            ("hant-last-visible-dark", .traditionalChinese, true, "lastVisible"),
            ("en-five-stations", .english, false, "fiveStations"),
            ("en-five-stations-dark", .english, true, "fiveStations"),
            ("zh-five-stations", .chinese, false, "fiveStations"),
            ("zh-five-stations-dark", .chinese, true, "fiveStations"),
            ("hant-five-stations", .traditionalChinese, false, "fiveStations"),
            ("hant-five-stations-dark", .traditionalChinese, true, "fiveStations"),
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
            } else if state == "fiveStations" {
                let visible: [Station] = [.kiss, .musicRadio, .bcc, .asiaFM, .guangdong]
                for station in Station.allCases { settings.setStationVisible(station, visible.contains(station)) }
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
        guard verifyCachedHostSizing(output: output) else {
            FileHandle.standardError.write(Data("FAIL: Controlled cached-host sizing model; see cached-host-size-result.txt\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    /// A controlled model of failed host-to-window size propagation, not a
    /// natural MenuBarExtra reproduction. NSHostingView's sizing options are
    /// disabled; after the initial seven-station frame only production code is
    /// allowed to resize the native window as preferences change.
    @MainActor private static func verifyCachedHostSizing(output: URL) -> Bool {
        let suite = "RadioBar.CachedHostPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let resolver = MenuPreviewResolver()
        let radio = RadioPlayer(resolver: resolver, defaults: defaults)
        let settings = AppSettings(defaults: defaults, loginManager: MenuPreviewLogin())
        settings.language = .english
        settings.appearance = .light
        let initialStations = Array(Station.allCases.prefix(7))
        for station in Station.allCases {
            settings.setStationVisible(station, initialStations.contains(station))
        }
        radio.station = initialStations[0]
        let hosting = NSHostingView(rootView: CapturedMenuView(radio: radio, settings: settings))
        hosting.sizingOptions = []
        let screenOrigin = NSScreen.main?.visibleFrame.origin ?? .zero
        // This is the only fixture-defined window size. No subsequent test
        // phase sets a window/content size or replaces the hosting view.
        let window = NSWindow(contentRect: NSRect(x: screenOrigin.x + 100, y: screenOrigin.y + 100,
                                                  width: 256, height: 376),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer {
            radio.pause()
            resolver.cancelPending()
            window.contentView = nil
            window.close()
        }
        var results: [String] = []
        var initialAnchor: NSPoint?
        func settleLayout() {
            for _ in 0..<6 {
                hosting.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.025))
            }
        }
        func find(_ identifier: String, in view: NSView) -> NSView? {
            if view.identifier?.rawValue == identifier { return view }
            return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
        }
        func check(_ phase: String, expectedCount: Int) {
            settleLayout()
            guard let header = find("menuHeaderProbe", in: hosting),
                  let bottom = find("menuBottomProbe", in: hosting) else {
                let line = "INCOMPLETE: \(phase) production menu probes unavailable frame=\(window.frame) hostBounds=\(hosting.bounds)"
                results.append(line)
                print(line)
                return
            }
            if initialAnchor == nil { initialAnchor = NSPoint(x: window.frame.minX, y: window.frame.maxY) }
            let expectedHeight = CGFloat(208 + 24 * expectedCount)
            let nativeSize = window.contentRect(forFrameRect: window.frame).size
            let presentedSize = hosting.layer?.presentation()?.bounds.size ?? hosting.bounds.size
            let headerRect = header.convert(header.bounds, to: hosting)
            let bottomRect = bottom.convert(bottom.bounds, to: hosting)
            let topInset = hosting.isFlipped ? headerRect.minY : hosting.bounds.height - headerRect.maxY
            let bottomInset = hosting.isFlipped ? hosting.bounds.height - bottomRect.maxY : bottomRect.minY
            // Ordinary NSWindow owns its resize anchoring. Actual menu-bar
            // placement is checked by the native MenuBarExtra lifecycle mode.
            let valid = settings.visibleStations.count == expectedCount && hosting.sizingOptions.isEmpty
                && abs(nativeSize.width - 256) < 0.5 && abs(nativeSize.height - expectedHeight) < 0.5
                && abs(window.frame.height - expectedHeight) < 0.5
                && abs(hosting.bounds.width - 256) < 0.5 && abs(hosting.bounds.height - expectedHeight) < 0.5
                && abs(presentedSize.height - expectedHeight) < 0.5
                && abs(topInset - 9) < 0.5 && abs(bottomInset - 5) < 0.5
            let line = "\(valid ? "PASS" : "FAIL"): \(phase) count=\(settings.visibleStations.count) expectedCount=\(expectedCount) expectedHeight=\(expectedHeight) windowFrame=\(window.frame) contentSize=\(nativeSize) hostBounds=\(hosting.bounds) fittingSize=\(hosting.fittingSize) presentedSize=\(presentedSize) topInset=\(topInset) bottomInset=\(bottomInset) minX=\(window.frame.minX) maxY=\(window.frame.maxY) initialTopLeft=\(String(describing: initialAnchor)) sizingOptionsEmpty=\(hosting.sizingOptions.isEmpty)"
            results.append(line)
            print(line)
        }
        check("initial-seven", expectedCount: 7)
        for (index, station) in initialStations.dropFirst().reversed().enumerated() {
            settings.setStationVisible(station, false)
            check("first-shrink-\(index + 1)", expectedCount: 6 - index)
        }
        for (index, station) in initialStations.dropFirst().enumerated() {
            settings.setStationVisible(station, true)
            check("grow-\(index + 1)", expectedCount: index + 2)
        }
        for (index, station) in initialStations.dropFirst().reversed().enumerated() {
            settings.setStationVisible(station, false)
            check("second-shrink-\(index + 1)", expectedCount: 6 - index)
        }
        let header = "Controlled cached-host sizing model; ordinary borderless NSWindow with production menu content.\nNSHostingView.sizingOptions=[] deliberately disables host size propagation.\nOnly the initial seven-station 256x376 frame is supplied by the fixture; all later changes use production AppSettings visibility setters and normal layout/run-loop settling.\nThis is not a natural reproduction of MenuBarExtra caching, a physical interaction test, or an audio test.\n"
        do {
            try (header + results.joined(separator: "\n") + "\n")
                .write(to: output.appendingPathComponent("cached-host-size-result.txt"), atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("FAIL: Could not write cached-host-size-result.txt\n".utf8))
            return false
        }
        return results.count == 19 && results.allSatisfy { $0.hasPrefix("PASS:") }
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
            for count in [Station.allCases.count, 7, 5, 1] {
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
