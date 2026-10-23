import SwiftUI
import AppKit

@main
@MainActor
struct RadioBarApp: App {
    // Acquire before SwiftUI creates the menu bar extra or starts a player.
    private static let instanceLock: SingleInstanceLock = {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            let file = support.appendingPathComponent("local.victor.RadioBar/instance.lock")
            guard let lock = try SingleInstanceLock.acquire(at: file) else {
                // The existing instance keeps its playback and menu bar icon.
                exit(EXIT_SUCCESS)
            }
            return lock
        } catch {
            let alert = NSAlert()
            let language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppLanguage.preferenceKey) ?? "") ?? .system
            alert.messageText = RadioText("无法启动 RadioBar", "Unable to start RadioBar").value(language)
            alert.informativeText = RadioText("无法建立单实例锁：\(error.localizedDescription)", "Unable to create the single-instance lock: \(error.localizedDescription)").value(language)
            alert.runModal()
            exit(EXIT_FAILURE)
        }
    }()

    init() {
        _ = Self.instanceLock
        // Recover a durable local configuration transaction before launch preferences/player read it.
        if let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: false) {
            _ = try? MacStationSyncController.recoverBeforeStartup(file: StationCatalog.userFile(in: support), defaults: .standard)
        }
        if let issue = StationCatalog.start() {
            let language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppLanguage.preferenceKey) ?? "") ?? .system
            let alert = NSAlert()
            alert.messageText = RadioText("电台配置未加载", "Station configuration could not be loaded").value(language)
            alert.informativeText = issue.value(language)
            alert.runModal()
        }
        AppUpdater.shared.start()
        let player = RadioPlayer()
        let preferences = AppSettings()
        preferences.enableStationSync()
        _radio = MenuState(initialValue: player)
        _settings = StateObject(wrappedValue: preferences)
        _signal = MenuState(initialValue: MenuBarSignal(radio: player, settings: preferences))
        appDelegate.settings = preferences
        appDelegate.timer = player.sleepTimer
    }

    @NSApplicationDelegateAdaptor(RadioBarApplicationDelegate.self) private var appDelegate

    // Playback ticks and icon animation must not invalidate MenuBarExtra's scene.
    // Settings must reach the scene so a changed station list updates its size.
    @MenuState private var radio: RadioPlayer
    @MenuState private var signal: MenuBarSignal
    @StateObject private var settings: AppSettings
    var body: some Scene {
        MenuBarExtra {
            RadioMenuView(radio: radio, settings: settings) { page in
                appDelegate.settingsWindow.show(settings: settings, timer: radio.sleepTimer, page: page)
            }
            // The native extra can retain the previous presentation's height
            // while hidden. Give a changed list a fresh content identity.
            .id(settings.visibleStations.map(\.id))
        } label: {
            RadioMenuBarLabel(signal: signal, radio: radio, settings: settings)
        }.menuBarExtraStyle(.window)
        .commands {
            RadioSettingsCommands(settings: settings) {
                appDelegate.settingsWindow.show(settings: settings, timer: radio.sleepTimer)
            }
        }
    }
}


@MainActor
private struct RadioSettingsCommands: Commands {
    @ObservedObject var settings: AppSettings
    let showSettings: () -> Void
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(settings.text("设置…", "Settings…"), action: showSettings)
                .keyboardShortcut(",", modifiers: .command)
        }
    }
}

/// A stable scene child owns playback-driven menu updates.
@MainActor
private struct RadioMenuView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var radio: RadioPlayer
    @ObservedObject var settings: AppSettings
    var showSettings: (SettingsPage?) -> Void = { _ in }
    private var menuDivider: some View {
        Divider().padding(.horizontal, 11).padding(.vertical, 4)
    }
    private var statusColor: Color {
        menuStatusTint(isPlaying: radio.isPlaying, wantsPlayback: radio.wantsPlayback,
                       needsAttention: radio.needsAttention, status: radio.statusText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text("RadioBar")
                    .foregroundStyle(menuPrimaryTextColor(colorScheme))
                Spacer(minLength: 8)
                Text(radio.statusText.value(settings.language)).foregroundStyle(.secondary).font(.system(size: 11))
            }
            .padding(.horizontal, 9).frame(height: 24)
            .help(radio.detailText.value(settings.language))

            if radio.stationIsRemoved {
                Text(settings.text("当前电台已移出列表，切换后将无法再次选择。",
                                   "This station was removed. It will be unavailable after switching."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 9)
            }

            menuDivider
            ForEach(settings.visibleStations) { station in
                CompactMenuRow(title: station.menuName.value(settings.language),
                               symbol: radio.station == station ? "checkmark" : nil,
                               trailingText: station.frequencyMHz == nil ? nil : station.frequencyLabel,
                               isFrequency: true) {
                    radio.select(station)
                }
                .accessibilityValue(radio.station == station ? settings.text("已选择", "Selected") : "")
                .help(station.displayName.value(settings.language))
            }
            menuDivider
            CompactMenuRow(title: radio.wantsPlayback ? settings.text("暂停", "Pause") : settings.text("播放", "Play"),
                           symbol: radio.wantsPlayback ? "pause.fill" : "play.fill") {
                radio.toggle()
            }.keyboardShortcut(.space, modifiers: [])
            CompactMenuRow(title: settings.text("重新连接", "Reconnect"), symbol: "arrow.clockwise", shortcut: "⌘R") {
                radio.play()
            }.keyboardShortcut("r", modifiers: .command)

            HStack(spacing: 8) {
                Button { radio.toggleMute() } label: {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(radio.isSilent ? Color.primary : Color.secondary)
                        .frame(width: 24, height: 24)
                        .background(radio.isSilent ? Color.primary.opacity(0.09) : .clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("muteButton")
                .accessibilityLabel(settings.text(radio.isSilent ? "取消静音" : "静音",
                                                   radio.isSilent ? "Unmute" : "Mute"))
                .help(settings.text(radio.isSilent ? "取消静音" : "静音",
                                    radio.isSilent ? "Unmute" : "Mute"))
                Image(systemName: "speaker.fill")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(width: 12).accessibilityHidden(true)
                Slider(value: $radio.volume, in: 0...1)
                    .controlSize(.small).accessibilityLabel(settings.text("音量", "Volume"))
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(width: 16).accessibilityHidden(true)
            }.padding(.horizontal, 9).frame(height: 27)

            SleepTimerMenuStatus(timer: radio.sleepTimer, language: settings.language) {
                showSettings(.sleepTimer)
            }

            // Keep transient recovery details in Diagnostics. Adding/removing
            // a retry row resizes the live MenuBarExtra and can leave its native
            // backdrop out of sync with the content.
            menuDivider
            CompactMenuRow(title: settings.text("设置…", "Settings…"), symbol: "gearshape", shortcut: "⌘,") {
                showSettings(nil)
            }.keyboardShortcut(",", modifiers: .command)
            CompactMenuRow(title: settings.text("退出 RadioBar", "Quit RadioBar"), symbol: "power", shortcut: "⌘Q") {
                radio.pause()
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
        .font(.system(size: 13))
        .padding(5).frame(width: 256)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            MenuBackground()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .background {
            GeometryReader { geometry in
                MenuContentSizeBridge(size: geometry.size)
                    .frame(width: 0, height: 0)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .radioAppearance(settings.appearance)
        .background(alignment: .topLeading) {
            MenuWindowDiagnostics(phase: radio.statusText.en, diagnostics: radio.diagnostics)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

/// Keep the reused native menu sized to its fixed-size SwiftUI content.
/// Measurement includes every row and padding; native presentation owns position.
private struct MenuContentSizeBridge: NSViewRepresentable {
    let size: CGSize
    final class SizingView: NSView {
        var naturalSize: CGSize = .zero
        private var observers: [NSObjectProtocol] = []
        private var generation = 0
        private var pending = false
        private var disposed = false
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            cancelPendingWork()
            guard !disposed, let window else { return }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResizeNotification,
                         NSWindow.didChangeOcclusionStateNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleResize() }
                })
            }
            scheduleResize()
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
        private func cancelPendingWork() {
            generation &+= 1
            pending = false
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }
        func dispose() {
            disposed = true
            cancelPendingWork()
        }
        func scheduleResize() {
            guard !disposed, !pending, let window else { return }
            pending = true
            let scheduledGeneration = generation
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, !self.disposed, self.generation == scheduledGeneration else { return }
                self.pending = false
                guard let window, self.window === window else { return }
                let measured = self.naturalSize
                guard measured.width.isFinite, measured.height.isFinite,
                      measured.width > 0, measured.height > 0 else { return }
                let scale = max(window.backingScaleFactor, 1)
                let size = CGSize(width: ceil(measured.width * scale) / scale,
                                  height: ceil(measured.height * scale) / scale)
                // Leave oversized menus to native presentation rather than
                // repeatedly fighting its screen-size constraints.
                guard let screen = window.screen else { return }
                let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
                guard frameSize.width <= screen.visibleFrame.width,
                      frameSize.height <= screen.visibleFrame.height else { return }
                let current = window.contentRect(forFrameRect: window.frame).size
                let tolerance = 0.5 / scale
                guard abs(current.width - size.width) > tolerance
                    || abs(current.height - size.height) > tolerance else { return }
                window.setContentSize(size)
            }
        }
    }
    func makeNSView(context: Context) -> SizingView {
        let view = SizingView()
        view.naturalSize = size
        return view
    }
    func updateNSView(_ view: SizingView, context: Context) {
        guard view.naturalSize != size else { return }
        view.naturalSize = size
        view.scheduleResize()
    }
    static func dismantleNSView(_ view: SizingView, coordinator: ()) { view.dispose() }
}

/// Use the semantic menu material instead of the window-style extra's default
/// backdrop. AppKit resolves its tint and translucency from the window appearance.
private struct MenuBackground: NSViewRepresentable {
    final class BackgroundView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> BackgroundView {
        let view = BackgroundView()
        view.identifier = NSUserInterfaceItemIdentifier("radioMenuBackground")
        configure(view)
        return view
    }
    func updateNSView(_ view: BackgroundView, context: Context) { configure(view) }
    private func configure(_ view: BackgroundView) {
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
    }
}

/// Observe window lifecycle and geometry without changing its native frame.
/// These numeric records share the existing bounded, memory-only diagnostics.
private struct MenuWindowDiagnostics: NSViewRepresentable {
    let phase: String
    let diagnostics: RadioDiagnostics
    final class Probe: NSView {
        var phase = ""
        var diagnostics: RadioDiagnostics?
        private var observers: [NSObjectProtocol] = []
        private var pending = false
        private var lastRecord = ""
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            lastRecord = ""
            if let window {
                for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResizeNotification,
                             NSWindow.didChangeOcclusionStateNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.scheduleRecord() }
                    })
                }
            }
            scheduleRecord()
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
        func scheduleRecord() {
            guard !pending else { return }
            pending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pending = false
                self.record()
                // Compare again after the presentation layer has had a frame to
                // settle; this is one bounded follow-up, not a polling timer.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.record() }
            }
        }
        private func record() {
            guard let window, let host = window.contentView, let diagnostics else { return }
            func rect(_ rect: NSRect) -> String {
                String(format: "%.1f,%.1f,%.1f,%.1f", rect.minX, rect.minY, rect.width, rect.height)
            }
            let origin = convert(NSPoint.zero, to: host)
            let presented = host.layer?.presentation().map { rect($0.frame) } ?? "none"
            let drawnOrigin: String
            if let source = layer?.presentation(), let target = host.layer?.presentation() {
                let point = source.convert(CGPoint.zero, to: target)
                drawnOrigin = String(format: "%.1f,%.1f", point.x, point.y)
            } else { drawnOrigin = "none" }
            let safe = String(format: "%.1f,%.1f", host.safeAreaInsets.top, host.safeAreaInsets.bottom)
            let record = "phase=\(phase); visible=\(window.isVisible); window=\(Int(window.frame.width))x\(Int(window.frame.height)); layout=\(rect(window.contentLayoutRect)); host=\(rect(host.frame)); bounds=\(rect(host.bounds)); presented=\(presented); contentOrigin=\(String(format: "%.1f,%.1f", origin.x, origin.y)); drawnOrigin=\(drawnOrigin); safe=\(safe)"
            guard record != lastRecord else { return }
            lastRecord = record
            diagnostics.record("menu.layout", record)
        }
    }
    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.diagnostics = diagnostics
        view.phase = phase
        return view
    }
    func updateNSView(_ view: Probe, context: Context) {
        view.diagnostics = diagnostics
        if view.phase != phase {
            view.phase = phase
            view.scheduleRecord()
        }
    }
}

@MainActor
private struct RadioMenuBarLabel: View {
    @ObservedObject var signal: MenuBarSignal
    @ObservedObject var radio: RadioPlayer
    @ObservedObject var settings: AppSettings
    @ObservedObject private var timer: SleepTimer

    init(signal: MenuBarSignal, radio: RadioPlayer, settings: AppSettings) {
        self.signal = signal
        self.radio = radio
        self.settings = settings
        self.timer = radio.sleepTimer
    }

    var body: some View {
        let countdown = settings.showSleepTimerInMenuBar && timer.isRunning ? timer.remainingText : nil
        let name = settings.menuBarDisplay == .iconAndStation ? radio.station.menuName.value(settings.language) : nil
        let title = MenuBarTitle.text(stationName: name, countdown: countdown)
        HStack(spacing: 0) {
            if let countdown {
                Image(nsImage: MenuBarTitle.image(antenna: signal.image, stationName: name, countdown: countdown))
                    .renderingMode(.template)
            } else {
                Image(nsImage: signal.image).renderingMode(.template)
                if !title.isEmpty { Text(title).fixedSize() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("RadioBar · \(radio.station.menuName.value(settings.language)) · \(radio.statusText.value(settings.language))"
            + (countdown.map { " · " + RadioText("剩余时间", "Time remaining").value(settings.language) + " " + $0 } ?? ""))
        .help(radio.station.menuName.value(settings.language) + (countdown.map { " · " + $0 } ?? ""))
    }
}

// Explicit alias selects the State property wrapper with CLT-only Swift toolchains.
private typealias MenuState<Value> = SwiftUI.State<Value>

// Match the reference menus' deep gray without letting light-window vibrancy
// resolve primary text to pure black. Preserve the system color in dark mode.
private func menuPrimaryTextColor(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(nsColor: .controlTextColor) : Color(.sRGB, white: 37.0 / 255.0, opacity: 1)
}

/// Compact menu spacing with a full-width hover target, retaining the volume slider.
private struct CompactMenuRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let symbol: String?
    var shortcut: String? = nil
    var trailingText: String? = nil
    var isFrequency = false
    let action: () -> Void
    @MenuState private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Group {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: symbol == "checkmark" ? 12 : 10, weight: .regular))
                            .foregroundStyle(hovered ? Color.white :
                                symbol == "checkmark" ? Color.primary : menuPrimaryTextColor(colorScheme))
                    }
                    else { Color.clear }
                }.frame(width: 15, height: 15)
                Text(title).lineLimit(1)
                    .foregroundStyle(hovered ? Color.white : menuPrimaryTextColor(colorScheme))
                Spacer(minLength: 4)
                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: isFrequency ? 11 : 13).monospacedDigit()).lineLimit(1)
                        .frame(width: 64, alignment: .trailing).fixedSize()
                        .foregroundStyle(hovered ? Color.white.opacity(isFrequency ? 0.65 : 0.9) :
                            isFrequency ? Color(nsColor: .tertiaryLabelColor) : .secondary)
                }
                if let shortcut {
                    Text(shortcut).foregroundStyle(hovered ? Color.white.opacity(0.8) : .secondary)
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 9).frame(height: 24)
            .contentShape(Rectangle())
            .foregroundStyle(hovered ? Color.white : Color.primary)
            .background {
                if hovered {
                    MenuSelectionBackground()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel([title, trailingText].compactMap { $0 }.joined(separator: " "))
    }
}

/// Draw only the existing hover state. The material never handles input.
private struct MenuSelectionBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { configure(view) }
    private func configure(_ view: NSVisualEffectView) {
        view.material = .selection
        view.blendingMode = .withinWindow
        view.state = .active
        view.isEmphasized = true
    }
}

/// UI projection of existing player values, not an additional playback state.
private func menuStatusTint(isPlaying: Bool, wantsPlayback: Bool, needsAttention: Bool, status: RadioText) -> Color {
    if needsAttention { return .red }
    if isPlaying && status.en == "Playing" { return .green }
    if wantsPlayback { return .orange }
    return .secondary
}

@MainActor
private struct SleepTimerMenuStatus: View {
    @ObservedObject var timer: SleepTimer
    let language: AppLanguage
    let action: () -> Void
    var body: some View {
        CompactMenuRow(title: RadioText("睡眠定时", "Sleep timer").value(language),
                       symbol: "timer", trailingText: timer.isRunning ? timer.remainingText
                           : timer.isFadingOut ? RadioText("渐弱停止", "Fading out").value(language)
                           : timer.hasExpired ? RadioText("已结束", "Finished").value(language)
                           : RadioText("未开启", "Off").value(language), action: action)
    }
}
