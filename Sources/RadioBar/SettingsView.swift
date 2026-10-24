import SwiftUI
import AppKit
import Combine

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
private final class WindowAppearanceState: ObservableObject {
    @Published var colorScheme: ColorScheme = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
}

/// The native window is the only appearance owner. Mirror its resolved scheme into
/// SwiftUI explicitly, rather than leaving a cached preferredColorScheme override.
private struct AppearanceWindowBridge: NSViewRepresentable {
    let appearance: AppAppearance
    let state: WindowAppearanceState
    final class AppearanceView: NSView {
        var state: WindowAppearanceState?
        private var observation: NSKeyValueObservation?
        private var overrideObservation: NSKeyValueObservation?
        private var observers: [NSObjectProtocol] = []
        private var refreshPending = false
        var choice: AppAppearance = .system {
            didSet { applyAppearance() }
        }
        private func applyAppearance() {
            guard let window else { return }
            let requested = choice.nativeAppearance
            if window.appearance?.name != requested?.name { window.appearance = requested }
            refreshScheme()
        }
        private func refreshScheme() {
            // Publish after the current SwiftUI update; read the latest window at
            // delivery time so rapid changes cannot apply an older queued scheme.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window, let state = self.state else { return }
                let scheme: ColorScheme = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
                if state.colorScheme != scheme { state.colorScheme = scheme }
            }
        }
        private func scheduleAppearanceRefresh() {
            guard !refreshPending else { return }
            refreshPending = true
            // Native presentation/activation can change a reused window after
            // SwiftUI has updated it. Reconcile after that work, using the latest
            // window and choice instead of retaining a previous presentation.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshPending = false
                self.applyAppearance()
            }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = nil
            overrideObservation = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            observation = window?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                self?.scheduleAppearanceRefresh()
            }
            overrideObservation = window?.observe(\.appearance, options: [.new]) { [weak self] _, _ in
                // An explicit override may change without changing the resolved
                // colors. System mode must still release that override.
                self?.scheduleAppearanceRefresh()
            }
            if let window {
                for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.scheduleAppearanceRefresh() }
                    })
                }
                observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                         object: NSApp, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleAppearanceRefresh() }
                })
            }
            applyAppearance()
            scheduleAppearanceRefresh()
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            scheduleAppearanceRefresh()
        }
    }
    func makeNSView(context: Context) -> AppearanceView {
        let view = AppearanceView(frame: .zero)
        view.state = state
        view.choice = appearance
        return view
    }
    func updateNSView(_ view: AppearanceView, context: Context) {
        view.state = state
        view.choice = appearance
    }
}

private struct RadioAppearanceModifier: ViewModifier {
    let appearance: AppAppearance
    @StateObject private var state = WindowAppearanceState()
    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, appearance.colorScheme ?? state.colorScheme)
            .background(AppearanceWindowBridge(appearance: appearance, state: state).frame(width: 0, height: 0))
    }
}

extension View {
    func radioAppearance(_ appearance: AppAppearance) -> some View {
        modifier(RadioAppearanceModifier(appearance: appearance))
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, sync, playback, channels, sleepTimer, diagnostics, about
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .sync: return "arrow.triangle.2.circlepath"
        case .playback: return "play.circle"
        case .channels: return "list.bullet"
        case .sleepTimer: return "moon"
        case .diagnostics: return "waveform.path.ecg"
        case .about: return "info.circle"
        }
    }
    var title: RadioText {
        switch self {
        case .general: return RadioText("通用", "General")
        case .sync: return RadioText("配置同步", "Sync")
        case .playback: return RadioText("播放", "Playback")
        case .channels: return RadioText("电台配置", "Stations")
        case .sleepTimer: return RadioText("睡眠定时", "Sleep timer")
        case .diagnostics: return RadioText("诊断", "Diagnostics")
        case .about: return RadioText("关于", "About")
        }
    }
}

enum SettingsLayout {
    static let width: CGFloat = 760
    static let height: CGFloat = 620
    static let sidebarWidth: CGFloat = 176

    static func configure(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: width, height: height))
    }
}

// Resolve against the native window appearance, including explicit light/dark choices.
private enum SettingsColors {
    static let sidebarBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.88, alpha: 1)
    }
    static let contentBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.965, alpha: 1)
    }
}

/// Keep AppKit scrolling, hit testing and dragging; customize only the indicator ink.
final class SettingsScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let background = dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.965, alpha: 1)
        background.setFill()
        dirtyRect.fill()
        guard knobProportion > 0 && knobProportion < 1 else { return }
        var knob = rect(for: .knob).insetBy(dx: 0, dy: 2)
        knob.origin.x = bounds.midX - 3
        knob.size.width = 6
        guard knob.height > 0 else { return }
        (dark ? NSColor(white: 0.44, alpha: 1) : NSColor(white: 0.76, alpha: 1)).setFill()
        NSBezierPath(roundedRect: knob, xRadius: 3, yRadius: 3).fill()
    }
}

private struct SettingsScrollStyle: NSViewRepresentable {
    final class Bridge: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureLater()
        }
        func configureLater() {
            DispatchQueue.main.async { [weak self] in
                guard let scroll = self?.enclosingScrollView else { return }
                if !(scroll.verticalScroller is SettingsScroller) {
                    let scroller = SettingsScroller()
                    scroller.controlSize = .small
                    scroll.verticalScroller = scroller
                }
                // Reapplying these AppKit properties during every SwiftUI update
                // invalidates layout, including on activation and metadata refresh.
                if scroll.scrollerStyle != .legacy { scroll.scrollerStyle = .legacy }
                if !scroll.hasVerticalScroller { scroll.hasVerticalScroller = true }
                if !scroll.autohidesScrollers { scroll.autohidesScrollers = true }
                if scroll.drawsBackground { scroll.drawsBackground = false }
            }
        }
    }
    func makeNSView(context: Context) -> Bridge { Bridge() }
    func updateNSView(_ view: Bridge, context: Context) { view.configureLater() }
}

enum SettingsVersion {
    static func label(in bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    static func report(in bundle: Bundle = .main) -> String {
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "RadioBar"
        let system = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif
        return "\(name) \(label(in: bundle))\nmacOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)\nArchitecture: \(architecture)"
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage = .general
}

@MainActor
struct RadioSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var navigation: SettingsNavigation
    @SettingsViewState var releaseNotesExpanded = false
    @SettingsViewState var versionInfoCopied = false
    @SettingsViewState private var showingAcknowledgments = false
    @SettingsViewState var stationRestoreResult: StationRestoreResult? = nil
    @SettingsViewState private var stationRestoreDismissal: Task<Void, Never>?
    @SettingsViewState private var stationEditor: StationEditorSession?
    @ObservedObject private var updater = AppUpdater.shared
    @StateObject private var channelReorder = ChannelReorderSession()
    let timer: SleepTimer
    var metadataBundle: Bundle = .main
    var stationConfigurationSupportDirectory: URL? = nil

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: navigation.page.symbol)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.secondary).frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("RadioBar").font(.system(size: 13, weight: .medium))
                        Text(navigation.page.title.value(settings.language))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).frame(height: 52)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch navigation.page {
                        case .general: generalPage
                        case .sync: syncPage
                        case .playback: playbackPage
                        case .channels: channelsPage
                        case .sleepTimer: SleepTimerControls(timer: timer, settings: settings)
                        case .diagnostics: DiagnosticsView(language: settings.language)
                        case .about: aboutPage
                        }
                    }
                    .padding(1)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(24)
                    .background(SettingsScrollStyle())
                }
                .background(Color(nsColor: SettingsColors.contentBackground))
                .id(navigation.page)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: SettingsLayout.width, height: SettingsLayout.height)
        .ignoresSafeArea(.container, edges: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .radioAppearance(settings.appearance)
        .alert(settings.text("电台显示", "Station visibility"), isPresented: Binding(
            get: { settings.stationVisibilityFeedback != nil },
            set: { if !$0 { settings.dismissStationVisibilityFeedback() } }
        )) {
            Button(settings.text("好", "OK"), role: .cancel) { settings.dismissStationVisibilityFeedback() }
        } message: {
            Text(settings.stationVisibilityFeedback?.text.value(settings.language) ?? "")
        }
        .sheet(item: $stationEditor) { session in
            StationEditorSheet(session: session, language: settings.language) { session, deleting in
                let error = await settings.saveStation(session, deleting: deleting)
                if error == nil { showStationConfigurationResult(deleting ? .deleted : .saved) }
                return error
            }
        }
        .sheet(isPresented: $showingAcknowledgments) {
            AcknowledgmentsSheet(language: settings.language,
                                  licenseText: RadioAcknowledgments.license(in: metadataBundle))
                .radioAppearance(settings.appearance)
        }
        .onAppear {
            channelReorder.activitySettings = settings
            settings.setStationEditing(stationEditor != nil)
            settings.refreshLoginState(); timer.refresh()
        }
        .onChange(of: stationEditor?.id) { _, id in settings.setStationEditing(id != nil) }
        .onDisappear { settings.setStationEditing(false); channelReorder.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.refreshLoginState()
            timer.refresh()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                sidebarSection(pages: [.general])
                sidebarSection(title: RadioText("收听", "Listening"), pages: [.playback, .channels, .sleepTimer])
                sidebarSection(title: RadioText("其他", "Others"), pages: [.sync, .diagnostics, .about])
            }
            .padding(.horizontal, 6).padding(.top, 56)
            Spacer(minLength: 16)
            Text(SettingsVersion.label(in: metadataBundle))
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityLabel(settings.text("版本", "Version") + " " + SettingsVersion.label(in: metadataBundle))
                .padding(.horizontal, 18).padding(.bottom, 18)
        }
        .frame(width: SettingsLayout.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: SettingsColors.sidebarBackground))
    }

    private func sidebarSection(title: RadioText? = nil, pages: [SettingsPage]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title.value(settings.language))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(pages) { page in
                Button { navigation.page = page } label: {
                    HStack(spacing: 10) {
                        Image(systemName: page.symbol)
                            .resizable().scaledToFit()
                            .font(.system(size: 14, weight: .regular))
                            .frame(width: 14, height: 14)
                            .frame(width: 20, height: 20)
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        Text(page.title.value(settings.language))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color(nsColor: .labelColor))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).frame(height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SettingsSidebarButtonStyle(isSelected: navigation.page == page))
                .focusEffectDisabled()
                .accessibilityAddTraits(navigation.page == page ? .isSelected : [])
            }
        }
    }

    private var generalPage: some View {
        Group {
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        SettingsRowTitle(title: settings.text("界面语言", "Language"),
                                         subtitle: settings.text("立即生效，音乐继续播放。", "Applies immediately. Music keeps playing."))
                        Spacer(minLength: 8)
                        SettingsMenuPicker(title: settings.text("界面语言", "Language"), selection: $settings.language,
                            options: [(settings.text("跟随系统", "System default"), .system),
                                      ("简体中文", .chinese), ("繁體中文", .traditionalChinese), ("English", .english)])
                            .frame(width: 196, height: 22)
                    }
                    .frame(minHeight: 42)
                    Divider()
                    HStack(spacing: 16) {
                        Text(settings.text("外观", "Appearance"))
                            .font(.system(size: 13, weight: .regular))
                        Spacer(minLength: 8)
                        SettingsMenuPicker(title: settings.text("外观", "Appearance"), selection: $settings.appearance,
                            options: AppAppearance.allCases.map { ($0.title.value(settings.language), Optional($0)) })
                            .frame(width: 196, height: 22)
                    }
                    .frame(minHeight: 22)
                    Divider()
                    HStack(spacing: 16) {
                        Text(settings.text("菜单栏显示", "Menu bar display"))
                            .font(.system(size: 13, weight: .regular))
                        Spacer(minLength: 8)
                        SettingsMenuPicker(title: settings.text("菜单栏显示", "Menu bar display"), selection: $settings.menuBarDisplay,
                            options: MenuBarDisplay.allCases.map { ($0.title.value(settings.language), Optional($0)) })
                            .frame(width: 196, height: 22)
                    }
                    .frame(minHeight: 22)
                    Divider()
                    HStack(spacing: 16) {
                        Text(settings.text("动态图标", "Animate menu bar icon"))
                            .font(.system(size: 13, weight: .regular))
                        Spacer(minLength: 8)
                        Toggle(settings.text("动态图标", "Animate menu bar icon"), isOn: $settings.animateMenuBarIcon)
                            .labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
                            .help(settings.text("播放时循环显示信号；关闭后始终显示完整天线。",
                                                "Animate the signal while playing. When off, always show the full antenna."))
                    }
                    .frame(minHeight: 22)
                }
            }
            SettingsCard {
                HStack(spacing: 16) {
                    SettingsRowTitle(title: settings.text("始终显示 Dock 图标", "Always show Dock icon"),
                                     subtitle: settings.text("关闭后，仅在设置窗口打开时显示。",
                                                             "When off, show only while the settings window is open."))
                    Spacer(minLength: 8)
                    Toggle(settings.text("始终显示 Dock 图标", "Always show Dock icon"), isOn: $settings.alwaysShowDockIcon)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
                }
            }
            SettingsCard {
                HStack(spacing: 16) {
                    SettingsRowTitle(title: settings.text("开机自启动", "Launch at login"),
                                     subtitle: settings.text("登录 Mac 后自动打开 RadioBar。", "Open RadioBar when you sign in to your Mac."))
                    Spacer(minLength: 8)
                    Toggle(settings.text("开机自启动", "Launch at login"), isOn: Binding(
                        get: { settings.loginState.isOn },
                        set: { enabled in Task { await settings.setLaunchAtLogin(enabled) } }
                    ))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(settings.isUpdatingLogin).fixedSize()
                }
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    if settings.isUpdatingLogin {
                        ProgressView().controlSize(.small)
                        Text(settings.text("正在更新…", "Updating…")).font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        Text(settings.loginState.text.value(settings.language))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button { settings.openLoginSettings() } label: {
                        HStack(spacing: 4) {
                            Text(settings.text("管理登录项", "Login Items"))
                            Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .regular))
                        }.font(.system(size: 12))
                    }.buttonStyle(.link).fixedSize()
                }
                if let error = settings.loginError {
                    Text(error.value(settings.language))
                        .font(.system(size: 12)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled).accessibilityIdentifier("loginItemError")
                }
            }
            SettingsHint(text: settings.text("请先将 App 放入“应用程序”。自动播放可在“播放”中单独设置。",
                                             "Move the app to Applications first. Autoplay is controlled separately in Playback."))
        }
    }

    @ViewBuilder
    private var syncPage: some View {
        if let sync = settings.stationSync {
            VStack(alignment: .leading, spacing: 14) {
                StationSyncSettingsCard(sync: sync, settings: settings)
                    .id("stationSyncCard")
                SettingsHint(text: settings.text("保留最近 5 次电台资料备份。配置由 Mac 发布，iPhone 只读。",
                                                 "Keep the last 5 station backups. Mac publishes; iPhone only reads."))
            }
        }
    }

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                VStack(spacing: 10) {
                    Image(nsImage: aboutIcon)
                        .resizable().interpolation(.high)
                        .frame(width: 88, height: 88)
                        .accessibilityHidden(true)
                    Text(metadataBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "RadioBar")
                        .font(.system(size: 18, weight: .medium))
                    HStack(spacing: 4) {
                        Text(settings.text("版本", "Version") + " " + SettingsVersion.label(in: metadataBundle))
                            .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            versionInfoCopied = NSPasteboard.general.setString(SettingsVersion.report(in: metadataBundle), forType: .string)
                        } label: {
                            Image(systemName: versionInfoCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12, weight: .regular))
                                .frame(width: 24, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("copyVersionInfo")
                        .accessibilityLabel(settings.text("复制版本信息", "Copy version information"))
                        .accessibilityValue(versionInfoCopied ? settings.text("已复制", "Copied") : "")
                        .help(versionInfoCopied ? settings.text("已复制", "Copied") : settings.text("复制版本信息", "Copy version information"))
                        .task(id: versionInfoCopied) {
                            guard versionInfoCopied else { return }
                            do { try await Task.sleep(for: .seconds(3)) } catch { return }
                            versionInfoCopied = false
                        }
                        .onDisappear { versionInfoCopied = false }
                    }
                    Text(settings.text("把电台放进 Mac 菜单栏，随手打开，安心听歌。",
                                       "Radio in your Mac menu bar. Tune in and unwind."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    Button(settings.text("检查更新", "Check for Updates")) {
                        updater.checkForUpdates()
                    }
                        .controlSize(.regular)
                        .disabled(!updater.canCheckForUpdates)
                        .padding(.top, 6)
                    Toggle(settings.text("自动检查更新", "Automatically check for updates"),
                        isOn: Binding(get: { updater.automaticallyChecksForUpdates },
                                      set: { updater.setAutomaticallyChecksForUpdates($0) }))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .disabled(updater.startupFailed)
                    if updater.startupFailed {
                        Text(settings.text("更新服务无法启动，请重新打开 App 后再试。", "The update service could not start. Please reopen the app and try again."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    HStack(spacing: 24) {
                        Link(destination: URL(string: "https://github.com/GiaoGiaoCat/RadioBar")!) {
                            HStack(spacing: 4) {
                                Text(settings.text("访问网站", "Visit our Website"))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .regular))
                                    .accessibilityHidden(true)
                            }
                            .fixedSize()
                        }
                        Link(destination: URL(string: "https://github.com/GiaoGiaoCat/RadioBar/issues")!) {
                            HStack(spacing: 4) {
                                Text(settings.text("问题反馈", "Report an Issue"))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .regular))
                                    .accessibilityHidden(true)
                            }
                            .fixedSize()
                        }
                        .accessibilityIdentifier("reportIssue")
                    }
                    .font(.system(size: 12))
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                Divider()
                Button { showingAcknowledgments = true } label: {
                    HStack(spacing: 6) {
                        SettingsActionLabel(title: settings.text("开源许可与致谢", "Open Source Licenses & Acknowledgments"), systemImage: "book")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .regular))
                            .accessibilityHidden(true)
                    }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SettingsDisclosureButtonStyle())
                .accessibilityIdentifier("openAcknowledgments")
                .frame(maxWidth: .infinity)
            }
            DisclosureGroup(isExpanded: $releaseNotesExpanded) {
                ReleaseNotesView(language: settings.language,
                    currentVersion: metadataBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            } label: {
                Text(settings.text("更新日志", "What's New"))
                    .font(.system(size: 13, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
            }
            .disclosureGroupStyle(SettingsDisclosureStyle(language: settings.language))
        }
    }

    private var aboutIcon: NSImage {
        if let url = metadataBundle.url(forResource: "RadioBar", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSApp.applicationIconImage
    }

    private var channelsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(settings.text("电台顺序与显示", "Station order and visibility"))
                            .font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 16)
                        Text(settings.text("已显示 \(settings.visibleStations.count) / \(Station.allCases.count)",
                                           "\(settings.visibleStations.count) / \(Station.allCases.count) visible"))
                            .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().fixedSize()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 20) {
                        Text(settings.text("拖动手柄排序，更改自动保存。",
                                           "Drag handles to reorder. Changes save automatically."))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button(settings.text("恢复默认顺序", "Reset order")) { settings.resetStationOrder() }
                            .buttonStyle(.link).font(.system(size: 12)).fixedSize()
                            .disabled(!settings.hasCustomStationOrder || channelReorder.source != nil || settings.stationChangesBlocked)
                    }
                }
                .padding(18)
                Divider().padding(.horizontal, 18)
                ForEach(Array(settings.orderedStations.enumerated()), id: \.element.id) { index, station in
                    ChannelDropRow(station: station, session: channelReorder, settings: settings) {
                        channelRow(station, index: index)
                    }
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .id(station.id)
                        .opacity(channelReorder.source == station ? 0.45 : 1)
                        .overlay(alignment: channelReorder.target?.after == true ? .bottom : .top) {
                            if channelReorder.target?.station == station {
                                Rectangle().fill(Color.accentColor).frame(height: 2)
                                    .padding(.horizontal, 18).allowsHitTesting(false)
                            }
                        }

                    if index < settings.orderedStations.count - 1 { Divider().padding(.horizontal, 18) }
                }
                Divider().padding(.horizontal, 18)
                stationListActions
                .padding(.horizontal, 18).padding(.vertical, 12)
                .id("stationListActions")
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.055), lineWidth: 1))
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(settings.text("配置文件", "Configuration file"))
                        .font(.system(size: 13, weight: .medium))
                    HStack(spacing: 24) {
                        Button(action: openStationConfigurationFile) {
                            SettingsActionLabel(title: settings.text("打开文件", "Open file"), systemImage: "doc.text")
                        }.accessibilityIdentifier("openStationConfigurationFile")
                        Button(action: openStationConfigurationFolder) {
                            SettingsActionLabel(title: settings.text("打开文件夹", "Open folder"), systemImage: "folder")
                        }.accessibilityIdentifier("openStationConfigurationFolder")
                    }.buttonStyle(.link).font(.system(size: 12))
                        .disabled(settings.stationChangesBlocked || channelReorder.source != nil)
                    if stationResultArea == .file { stationConfigurationStatus(in: .file, height: nil) }
                }
                Divider()
                HStack(spacing: 16) {
                    stationActionTitle("应用文件中的更改", "Apply saved changes",
                                       "保存配置文件后，重新加载即可生效。", "Save the file, then reload to apply your changes.", area: .reload)
                    Spacer(minLength: 8)
                    Button(settings.text("重新加载", "Reload")) { updateStationConfiguration(restoring: false) }
                        .controlSize(.regular)
                        .disabled(settings.stationChangesBlocked || channelReorder.source != nil)
                        .accessibilityIdentifier("reloadStationConfiguration")
                }
            }
            SettingsCard {
                HStack(spacing: 16) {
                    stationActionTitle("恢复内置电台", "Restore bundled stations",
                                       "先自动备份，再替换当前配置。", "Back up automatically, then replace your configuration.", area: .restore)
                    Spacer(minLength: 8)
                    Button(settings.text("恢复", "Restore"), action: restoreBundledStations)
                        .controlSize(.regular)
                        .disabled(settings.stationChangesBlocked || channelReorder.source != nil)
                        .accessibilityLabel(settings.text("恢复内置电台列表", "Restore bundled stations"))
                        .accessibilityIdentifier("restoreBundledStations")
                }
            }.id("stationConfigurationActions")
            SettingsHint(text: settings.text("隐藏的电台不会出现在菜单、默认电台选项或随机选择中，也不会中断当前播放。",
                                             "Hidden stations are excluded from the menu, default station options and random selection. Hiding a station does not interrupt playback."))
                .id("stationConfigurationHint")
        }
    }

    @ViewBuilder
    private var stationListActions: some View {
        if stationResultArea == .editor {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    stationConfigurationStatus(in: .editor, height: nil, wraps: false)
                    addStationButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    stationConfigurationStatus(in: .editor, height: nil)
                    addStationButton.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        } else {
            addStationButton.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var addStationButton: some View {
        Button { openStationEditor(nil) } label: {
            SettingsActionLabel(title: settings.text("添加电台", "Add station"), systemImage: "plus")
        }
        .buttonStyle(.bordered).controlSize(.regular).font(.system(size: 12)).fixedSize()
        .disabled(channelReorder.source != nil || settings.stationChangesBlocked)
        .accessibilityIdentifier("addStation")
    }

    private enum StationConfigurationArea { case file, reload, restore, editor }

    private var stationResultArea: StationConfigurationArea? {
        guard let result = stationRestoreResult else { return nil }
        switch result {
        case .openFailed: return .file
        case .editFailed, .saved, .deleted: return .editor
        case .reloaded, .unchanged, .reloadFailed: return .reload
        case .restored, .backupFailed, .restoreFailed: return .restore
        }
    }

    private func stationActionTitle(_ zh: String, _ en: String, _ detailZH: String, _ detailEN: String, area: StationConfigurationArea) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(settings.text(zh, en)).font(.system(size: 13, weight: .regular))
            Group {
                if stationResultArea == area {
                    stationConfigurationStatus(in: area, height: nil)
                } else {
                    Text(settings.text(detailZH, detailEN)).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func stationConfigurationStatus(in area: StationConfigurationArea, height: CGFloat?, wraps: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 7) {
            if stationResultArea == area, let result = stationRestoreResult {
                Circle().fill(result.succeeded ? Color.green : Color.orange)
                    .frame(width: 6, height: 6).padding(.top, 5)
                Text(result.text.value(settings.language))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: !wraps, vertical: true)
                    .accessibilityIdentifier("stationRestoreStatus")
            }
            Spacer(minLength: 0)
        }.frame(height: height, alignment: .topLeading)
    }

    private func openStationEditor(_ station: Station?) {
        guard !settings.stationChangesBlocked, channelReorder.source == nil else { return }
        do {
            let support = try stationConfigurationSupportDirectory ?? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let session = try StationEditorSession(file: StationCatalog.userFile(in: support), station: station)
            settings.setStationEditing(true)
            stationEditor = session
        } catch {
            showStationConfigurationResult(.editFailed((error as? StationConfigurationError)?.text ?? RadioText(
                "无法读取配置文件，请检查文件及访问权限。", "Unable to read the configuration file. Check the file and permissions.")))
        }
    }

    private func restoreBundledStations() { updateStationConfiguration(restoring: true) }

    private func showStationConfigurationResult(_ result: StationRestoreResult) {
        stationRestoreDismissal?.cancel()
        stationRestoreResult = result
        stationRestoreDismissal = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(result.succeeded ? 5 : 8)) }
            catch { return }
            stationRestoreResult = nil
        }
    }

    private func updateStationConfiguration(restoring: Bool) {
        guard !settings.stationChangesBlocked, channelReorder.source == nil else { return }
        stationRestoreDismissal?.cancel()
        stationRestoreResult = nil
        Task {
            let result = await settings.updateStations(restoring: restoring, supportDirectory: stationConfigurationSupportDirectory)
            showStationConfigurationResult(result)
        }
    }

    private func openStationConfigurationFile() {
        do {
            let support = try stationConfigurationSupportDirectory ?? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let file = StationCatalog.userFile(in: support)
            guard try file.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey]).isRegularFile == true,
                  FileManager.default.isReadableFile(atPath: file.path) else {
                showStationConfigurationResult(.openFailed)
                return
            }
            if NSWorkspace.shared.open(file) { return }
        } catch { }
        showStationConfigurationResult(.openFailed)
    }

    private func openStationConfigurationFolder() {
        do {
            let support = try stationConfigurationSupportDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            let directory = StationCatalog.userFile(in: support).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if NSWorkspace.shared.open(directory) { return }
        } catch { }
        let alert = NSAlert()
        alert.messageText = settings.text("无法打开配置文件夹", "Unable to open the configuration folder")
        alert.informativeText = settings.text("请检查 Application Support 目录的访问权限。", "Check access permissions for the Application Support directory.")
        alert.runModal()
    }

    private func channelRow(_ station: Station, index: Int) -> some View {
        let visible = settings.isStationVisible(station)
        return HStack(spacing: 8) {
            ChannelDragHandle(station: station, title: station.menuName.value(settings.language),
                              help: settings.text("拖动以调整顺序", "Drag to reorder"), session: channelReorder, isEnabled: !settings.stationChangesBlocked)
                .frame(width: 12, height: 28)
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
                .frame(width: 18, alignment: .leading).accessibilityHidden(true)
            Text(station.menuName.value(settings.language))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(visible ? Color.primary : Color.secondary)
                .lineLimit(1).layoutPriority(1)
            if station.isBuiltIn {
                Text(settings.text("内置", "Built-in"))
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
                    .accessibilityIdentifier("builtInStation-" + station.id)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                if !station.frequencyLabel.isEmpty {
                    Text(station.frequencyLabel).font(.system(size: 8)).foregroundStyle(.tertiary)
                }
                Text(station.listeningStyle.value(settings.language))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(width: 150, alignment: .trailing)
            if !station.isBuiltIn {
                Button { openStationEditor(station) } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless).font(.system(size: 12))
                    .help(settings.text("编辑电台", "Edit station"))
                    .accessibilityLabel(settings.text("编辑电台", "Edit station") + " " + station.menuName.value(settings.language))
                    .accessibilityIdentifier("editStation-" + station.id)
                    .disabled(settings.stationChangesBlocked || channelReorder.source != nil)
            }
            Toggle(settings.text("显示", "Show") + " " + station.menuName.value(settings.language), isOn: Binding(
                get: { settings.isStationVisible(station) },
                set: { settings.setStationVisible(station, $0) }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
            .disabled(settings.stationChangesBlocked)
            .help(station.displayName.value(settings.language))
            .accessibilityIdentifier("stationVisibility-" + station.id)
        }
        .padding(.horizontal, 18).frame(height: 38)
        .help(station.displayName.value(settings.language) + " · " + station.listeningStyle.value(settings.language))
    }

    private var playbackPage: some View {
        Group {
            SettingsCard {
                SettingsRowTitle(title: settings.text("默认电台", "Default station"),
                                 subtitle: settings.defaultStation == .random
                                    ? settings.text("每次启动时随机选择一个电台。", "Choose a random station on each launch.")
                                    : settings.text("下次启动时选中的电台。", "The station selected on your next launch."),
                                 titleWeight: .medium)
                SettingsMenuPicker(title: settings.text("默认电台", "Default station"), selection: $settings.defaultStation,
                    options: [(settings.text("上次收听的电台", "Last listened station"), .lastListened),
                              (settings.text("随机电台", "Random station"), .random), ("", nil)]
                        + settings.visibleStations.map { ($0.displayName.value(settings.language), Optional(.station($0))) })
                    .frame(height: 22)
                    .frame(maxWidth: .infinity)
                    .disabled(settings.isStationRecoveryBlocked)
            }
            SettingsCard {
                HStack(spacing: 16) {
                    SettingsRowTitle(title: settings.text("启动后自动播放", "Play on launch"),
                                     subtitle: settings.text("打开 App 后播放默认电台。", "Start the default station when RadioBar opens."))
                    Spacer(minLength: 8)
                    Toggle(settings.text("启动后自动播放", "Play on launch"), isOn: $settings.autoPlayOnLaunch)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
                }
            }
            SettingsHint(text: settings.text("下次启动生效，当前播放不受影响。登录时自启动也遵循此设置。",
                                             "Changes apply next launch without interrupting playback, including when launching at login."))
        }
    }
}

// Disambiguate the property wrapper from the newer SDK's same-named macro.
typealias SettingsViewState<Value> = SwiftUI.State<Value>

private struct SettingsSidebarButtonStyle: ButtonStyle {
    let isSelected: Bool
    @SettingsViewState private var isHovering = false
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 :
                        isSelected ? 0.075 : (isHovering || isFocused) ? 0.045 : 0))
            }
            .onHover { isHovering = $0 }
    }
}

struct SettingsDisclosureStyle: DisclosureGroupStyle {
    let language: AppLanguage
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    configuration.label
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 16)
                    Text(RadioText(configuration.isExpanded ? "收起" : "展开",
                                   configuration.isExpanded ? "Collapse" : "Expand").value(language))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Image(systemName: configuration.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(SettingsDisclosureButtonStyle())
            .accessibilityValue(RadioText(configuration.isExpanded ? "已展开" : "已折叠",
                                          configuration.isExpanded ? "Expanded" : "Collapsed").value(language))
            if configuration.isExpanded { configuration.content }
        }
    }
}

private struct SettingsDisclosureButtonStyle: ButtonStyle {
    @SettingsViewState private var isHovering = false
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.07 : isHovering ? 0.035 : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(isFocused ? 0.7 : 0), lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .onHover { isHovering = $0 }
    }
}

/// Use native popup sizing so content cannot shrink the visible control inside its assigned frame.
struct SettingsMenuPicker<Value: Hashable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Value
    let options: [(String, Value?)]

    final class Coordinator: NSObject {
        var parent: SettingsMenuPicker
        init(_ parent: SettingsMenuPicker) { self.parent = parent }
        @objc func selectItem(_ sender: NSPopUpButton) {
            guard parent.options.indices.contains(sender.indexOfSelectedItem),
                  let value = parent.options[sender.indexOfSelectedItem].1 else { return }
            parent.selection = value
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 13)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectItem(_:))
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        button.setAccessibilityLabel(title)
        let titles = options.map { $0.0 }
        if button.itemTitles != titles {
            button.removeAllItems()
            for (label, value) in options {
                if value == nil { button.menu?.addItem(.separator()) }
                else { button.addItem(withTitle: label) }
            }
        }
        if let index = options.firstIndex(where: { $0.1 == selection }) {
            button.selectItem(at: index)
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.055), lineWidth: 1))
    }
}

struct SettingsRowTitle: View {
    let title: String
    let subtitle: String
    var titleWeight: Font.Weight = .regular
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 13, weight: titleWeight))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsHint: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle").padding(.top, 1)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 6).padding(.top, 2)
    }
}

/// A compact label shared by native settings buttons and links.
struct SettingsActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .regular))
                .accessibilityHidden(true)
            Text(title)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}

/// Retain one settings window and remember its selected page between openings.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    private var dockSubscription: AnyCancellable?
    private var alwaysShowDockIcon = false
    private var settingsWindowOpen = false

    /// Configure once at launch, independently of whether the menu or settings has appeared.
    func configure(settings: AppSettings) {
        dockSubscription = settings.$alwaysShowDockIcon.removeDuplicates().sink { [weak self] value in
            guard let self else { return }
            // @Published sends before the stored property changes; use the emitted value.
            self.alwaysShowDockIcon = value
            self.updateDockVisibility()
        }
    }

    private func updateDockVisibility() {
        let policy: NSApplication.ActivationPolicy = alwaysShowDockIcon || settingsWindowOpen ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow, closed === window else { return }
        settingsWindowOpen = false
        updateDockVisibility()
    }

    private let navigation = SettingsNavigation()
    private var languageSubscription: AnyCancellable?

    func show(settings: AppSettings, timer: SleepTimer, page: SettingsPage? = nil) {
        settings.refreshLoginState()
        timer.refresh()
        if let page { navigation.page = page }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.width, height: SettingsLayout.height),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            SettingsLayout.configure(window)
            window.isReleasedWhenClosed = false
            window.delegate = self
            let hosting = NSHostingView(rootView: RadioSettingsView(settings: settings, navigation: navigation, timer: timer))
            // Layout already reserves space for the native controls in the sidebar.
            hosting.safeAreaRegions = []
            window.contentView = hosting
            window.center()
            self.window = window
            languageSubscription = settings.$language.sink { [weak window] language in
                window?.title = RadioText("RadioBar 设置", "RadioBar Settings").value(language)
            }
        }
        settingsWindowOpen = true
        updateDockVisibility()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Keep the process alive when settings closes; Dock reopening reuses that window.
@MainActor
final class RadioBarApplicationDelegate: NSObject, NSApplicationDelegate {
    let settingsWindow = SettingsWindowController()
    var settings: AppSettings?
    var timer: SleepTimer?
    var didLaunch: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let settings { settingsWindow.configure(settings: settings) }
        didLaunch?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let settings, let timer { settingsWindow.show(settings: settings, timer: timer) }
        return false
    }
}

enum RadioAcknowledgments {
    static func license(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "Sparkle-LICENSE", withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

@MainActor
struct AcknowledgmentsSheet: View {
    let language: AppLanguage
    let licenseText: String?
    @Environment(\.dismiss) private var dismiss
    private func text(_ zh: String, _ en: String) -> String { RadioText(zh, en).value(language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text("开源许可与致谢", "Open Source Licenses & Acknowledgments"))
                .font(.system(size: 15, weight: .medium))
            Text(text("感谢开源项目及其贡献者，让 RadioBar 更好用。",
                      "Thank you to the open source projects and contributors that help make RadioBar possible."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sparkle").font(.system(size: 13, weight: .medium))
                    Text(text("自动更新支持。以下保留其完整许可证与第三方组件声明。",
                              "Automatic update support. The full license and third-party notices are included below."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Divider()
                    if let licenseText {
                        Text(licenseText)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("openSourceLicenseText")
                    } else {
                        Text(text("无法读取随 App 提供的许可证，请重新安装完整的 RadioBar App 后再试。",
                                  "The bundled license could not be read. Reinstall the complete RadioBar app and try again."))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("openSourceLicenseMissing")
                    }
                    Color.clear.frame(height: 1).id("licenseEnd")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
                .background(SettingsScrollStyle())
            }
            HStack {
                Spacer()
                Button(text("完成", "Done")) { dismiss() }
                    .buttonStyle(.bordered).controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("closeAcknowledgments")
            }
        }
        .padding(24).frame(width: 560, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand { dismiss() }
    }
}

@MainActor
struct StationEditorSheet: View {
    @SettingsViewState var session: StationEditorSession
    let language: AppLanguage
    let save: (StationEditorSession, Bool) async -> RadioText?
    @Environment(\.dismiss) private var dismiss
    @SettingsViewState var error: RadioText?
    @SettingsViewState private var saving = false
    @SettingsViewState private var confirmDelete = false
    private func text(_ zh: String, _ en: String) -> String { RadioText(zh, en).value(language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(session.isNew ? text("添加电台", "Add station") : text("编辑电台", "Edit station"))
                .font(.system(size: 15, weight: .medium))
            Form {
                TextField(text("中文名称", "Chinese name"), text: $session.nameZH)
                TextField(text("英文名称", "English name"), text: $session.nameEN)
                TextField(text("中文全称（可选）", "Full Chinese name (optional)"), text: $session.fullNameZH)
                TextField(text("英文全称（可选）", "Full English name (optional)"), text: $session.fullNameEN)
                TextField(text("频率（可选，MHz）", "Frequency (optional, MHz)"), text: $session.frequency)
                TextField(text("中文分类（可选）", "Chinese category (optional)"), text: $session.categoryZH)
                TextField(text("英文分类（可选）", "English category (optional)"), text: $session.categoryEN)
            }.textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 6) {
                Text(text("播放地址", "Stream URLs")).font(.system(size: 13))
                TextEditor(text: $session.addresses).font(.system(size: 12, design: .monospaced))
                    .frame(height: 94).padding(4)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
                    .accessibilityLabel(text("播放地址", "Stream URLs"))
                Text(text("每行一个 HTTP/HTTPS 地址，首行为主线路，其余为备用。", "One HTTP/HTTPS URL per line. The first is primary; the rest are backups."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let error {
                Text(error.value(language)).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("stationEditorError")
            }
            HStack {
                if !session.isNew {
                    Button(text("删除电台…", "Delete station…"), role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button(text("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(text("保存", "Save")) { submit(deleting: false) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 480)
        .disabled(saving)
        .interactiveDismissDisabled(saving)
        .alert(text("删除这个电台？", "Delete this station?"), isPresented: $confirmDelete) {
            Button(text("取消", "Cancel"), role: .cancel) { }
            Button(text("删除", "Delete"), role: .destructive) { submit(deleting: true) }
        } message: {
            Text(text("删除后会备份并更新配置文件。正在播放的连接将继续。", "The configuration will be backed up and updated. Current playback will continue."))
        }
    }

    private func submit(deleting: Bool) {
        guard !saving else { return }
        saving = true
        error = nil
        Task {
            error = await save(session, deleting)
            saving = false
            if error == nil { dismiss() }
        }
    }
}
