import Foundation
import Combine
import ServiceManagement

enum LoginItemState: Equatable {
    case disabled, enabled, requiresApproval, unavailable
    var isOn: Bool { self == .enabled || self == .requiresApproval }
    var text: RadioText {
        switch self {
        case .disabled: return RadioText("未启用", "Disabled")
        case .enabled: return RadioText("已启用", "Enabled")
        case .requiresApproval: return RadioText("等待系统批准，请在“登录项”中允许 RadioBar", "Approval required. Allow RadioBar in Login Items")
        case .unavailable: return RadioText("系统未找到登录项，请将 App 移至“应用程序”后重试", "Login item unavailable. Move the app to Applications and retry")
        }
    }
}

@MainActor
protocol LoginItemManaging {
    var state: LoginItemState { get }
    func setEnabled(_ enabled: Bool) async throws
    func openSystemSettings()
}

@MainActor
final class SystemLoginItemManager: LoginItemManaging {
    var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }
    func setEnabled(_ enabled: Bool) async throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try await SMAppService.mainApp.unregister() }
    }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let preferenceKey = "appAppearance"
    var id: String { rawValue }
    var title: RadioText {
        switch self {
        case .system: return RadioText("跟随系统", "System default")
        case .light: return RadioText("浅色", "Light")
        case .dark: return RadioText("深色", "Dark")
        }
    }
}

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case iconOnly, iconAndStation
    static let preferenceKey = "menuBarDisplay"
    var id: String { rawValue }
    var title: RadioText {
        switch self {
        case .iconOnly: return RadioText("仅图标", "Icon only")
        case .iconAndStation: return RadioText("图标加电台名称", "Icon and station name")
        }
    }
}

enum StationVisibilityFeedback: Equatable {
    case lastVisible, defaultReset
    var text: RadioText {
        switch self {
        case .lastVisible:
            return RadioText("至少保留一个显示的电台。请先显示另一个电台，再隐藏这个电台。",
                             "Keep at least one station visible. Show another station before hiding this one.")
        case .defaultReset:
            return RadioText("默认电台已隐藏，启动时将改为上次收听的电台；若其已隐藏，则选择首个显示的电台。",
                             "The default station is now hidden. Launch will use Last listened, or the first visible station if it is hidden.")
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published private(set) var stationVisibilityFeedback: StationVisibilityFeedback?
    func dismissStationVisibilityFeedback() { stationVisibilityFeedback = nil }
    @Published private(set) var orderedStations: [Station]
    @Published private(set) var hiddenStations: Set<Station>
    var hasCustomStationOrder: Bool { orderedStations != Station.allCases }
    var visibleStations: [Station] { orderedStations.filter { !hiddenStations.contains($0) } }
    @Published private(set) var isUpdatingStations = false
    @Published private(set) var stationSync: MacStationSyncController?
    @Published private(set) var isStationRecoveryBlocked = false
    private var stationEditorOpen = false
    private var stationReordering = false
    var stationInteractionActive: Bool { stationEditorOpen || stationReordering }
    var stationChangesBlocked: Bool { isUpdatingStations || isStationRecoveryBlocked }

    func enableStationSync(supportDirectory: URL? = nil, automatic: Bool = true) {
        guard stationSync == nil else { return }
        do {
            let support = try supportDirectory ?? FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: false)
            stationSync = MacStationSyncController(localFile: StationCatalog.userFile(in: support), defaults: defaults,
                automatic: automatic, canPublish: { [weak self] in
                    guard let self else { return false }
                    return !self.stationChangesBlocked && !self.stationInteractionActive
                }, recoveryChanged: { [weak self] blocked in self?.isStationRecoveryBlocked = blocked })
        } catch { }
    }

    func setStationEditing(_ active: Bool) {
        stationEditorOpen = active
        if !active { stationSync?.interactionEnded() }
    }
    func setStationReordering(_ active: Bool) {
        stationReordering = active
        if !active { stationSync?.interactionEnded() }
    }
    private var catalogueObservation: AnyCancellable?

    func updateStations(restoring: Bool, supportDirectory: URL? = nil) async -> StationRestoreResult {
        guard !stationChangesBlocked else { return .unchanged }
        isUpdatingStations = true
        var accepted = false
        defer {
            isUpdatingStations = false
            if accepted { stationSync?.localConfigurationChanged(documentChanged: true) }
        }
        let (result, candidate) = await Task.detached(priority: .userInitiated) {
            do {
                let support = try supportDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                                              appropriateFor: nil, create: false)
                return StationCatalog.prepareUpdate(userFile: StationCatalog.userFile(in: support), restoring: restoring)
            } catch {
                return (restoring ? StationRestoreResult.backupFailed : .reloadFailed(RadioText(
                    "无法访问配置文件夹。", "Unable to access the configuration folder.")), nil)
            }
        }.value
        guard let candidate else { return result }
        accepted = true
        let changed = candidate.count != Station.allCases.count || zip(candidate, Station.allCases).contains { !$0.hasSameConfiguration(as: $1) }
        if changed {
            // Remember the previous order, including removed IDs, so re-added IDs retain their positions.
            if defaults.stringArray(forKey: StationOrder.preferenceKey) == nil {
                defaults.set(orderedStations.map(\.id), forKey: StationOrder.preferenceKey)
            }
            StationCatalog.apply(candidate)
        }
        return restoring ? result : changed ? .reloaded : .unchanged
    }

    func saveStation(_ session: StationEditorSession, deleting: Bool) async -> RadioText? {
        guard !stationChangesBlocked else {
            return RadioText("正在处理配置，请稍后再试。", "Configuration is busy. Try again shortly.")
        }
        isUpdatingStations = true
        var accepted = false
        defer {
            isUpdatingStations = false
            if accepted { stationSync?.localConfigurationChanged(documentChanged: true) }
        }
        do {
            let candidate = try await Task.detached(priority: .userInitiated) { try session.save(deleting: deleting) }.value
            if defaults.stringArray(forKey: StationOrder.preferenceKey) == nil {
                defaults.set(orderedStations.map(\.id), forKey: StationOrder.preferenceKey)
            }
            StationCatalog.apply(candidate)
            accepted = true
            return nil
        } catch {
            return (error as? StationConfigurationError)?.text ?? RadioText(
                "保存失败。请检查配置文件及文件夹权限；当前列表保持不变。",
                "Save failed. Check file and folder permissions. The current list is unchanged.")
        }
    }

    private func refreshCatalogueReferences() {
        orderedStations = StationOrder.stations(defaults: defaults)
        hiddenStations = StationVisibility.hiddenStations(defaults: defaults)
        let choice = DefaultStationChoice(storedValue: defaults.string(forKey: PlaybackPreferences.defaultStationKey))
        if case .station(let selected) = choice, !visibleStations.contains(selected) {
            defaultStation = .lastListened
        } else { defaultStation = choice }
    }

    func moveStation(_ source: Station, relativeTo target: Station, after: Bool) {
        guard !stationChangesBlocked, source != target, let sourceIndex = orderedStations.firstIndex(of: source) else { return }
        var order = orderedStations
        order.remove(at: sourceIndex)
        guard let targetIndex = order.firstIndex(of: target) else { return }
        order.insert(source, at: targetIndex + (after ? 1 : 0))
        guard order != orderedStations else { return }
        defaults.set(StationOrder.preservingUnknownIDs(order, defaults: defaults), forKey: StationOrder.preferenceKey)
        orderedStations = order
        stationSync?.localConfigurationChanged()
    }

    func resetStationOrder() {
        guard !stationChangesBlocked else { return }
        defaults.removeObject(forKey: StationOrder.preferenceKey)
        if hasCustomStationOrder { orderedStations = Station.allCases }
        stationSync?.localConfigurationChanged()
    }
    func isStationVisible(_ station: Station) -> Bool { !hiddenStations.contains(station) }
    func canHideStation(_ station: Station) -> Bool { !isStationVisible(station) || visibleStations.count > 1 }

    /// Changes menu/launch preferences only; never interrupts a live playback session.
    func setStationVisible(_ station: Station, _ visible: Bool) {
        guard !stationChangesBlocked, orderedStations.contains(station) else { return }
        guard visible || canHideStation(station) else {
            stationVisibilityFeedback = .lastVisible
            return
        }
        StationVisibility.setVisible(visible, station: station, defaults: defaults)
        var updated = hiddenStations
        if visible { updated.remove(station) } else { updated.insert(station) }
        guard updated != hiddenStations else { return }
        let resetsDefault = !visible && defaultStation == .station(station)
        if resetsDefault { defaultStation = .lastListened }
        hiddenStations = updated
        if resetsDefault { stationVisibilityFeedback = .defaultReset }
        stationSync?.localConfigurationChanged()
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: AppAppearance.preferenceKey) }
    }
    static let alwaysShowDockIconKey = "alwaysShowDockIcon"
    @Published var alwaysShowDockIcon: Bool {
        didSet { defaults.set(alwaysShowDockIcon, forKey: Self.alwaysShowDockIconKey) }
    }
    static let animateMenuBarIconKey = "animateMenuBarIcon"
    @Published var animateMenuBarIcon: Bool {
        didSet { defaults.set(animateMenuBarIcon, forKey: Self.animateMenuBarIconKey) }
    }
    static let showSleepTimerInMenuBarKey = "showSleepTimerInMenuBar"
    @Published var showSleepTimerInMenuBar: Bool {
        didSet { defaults.set(showSleepTimerInMenuBar, forKey: Self.showSleepTimerInMenuBarKey) }
    }
    @Published var menuBarDisplay: MenuBarDisplay {
        didSet { defaults.set(menuBarDisplay.rawValue, forKey: MenuBarDisplay.preferenceKey) }
    }
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: AppLanguage.preferenceKey) }
    }
    @Published var defaultStation: DefaultStationChoice {
        didSet {
            if let value = defaultStation.storedValue {
                defaults.set(value, forKey: PlaybackPreferences.defaultStationKey)
            } else {
                defaults.removeObject(forKey: PlaybackPreferences.defaultStationKey)
            }
            if !isUpdatingStations { stationSync?.localConfigurationChanged() }
        }
    }
    @Published var autoPlayOnLaunch: Bool {
        didSet { defaults.set(autoPlayOnLaunch, forKey: PlaybackPreferences.autoPlayOnLaunchKey) }
    }
    @Published private(set) var loginState: LoginItemState
    @Published private(set) var isUpdatingLogin = false
    @Published private(set) var loginError: RadioText?
    private let defaults: UserDefaults
    private let loginManager: any LoginItemManaging

    init(defaults: UserDefaults = .standard, loginManager: (any LoginItemManaging)? = nil) {
        self.defaults = defaults
        let manager = loginManager ?? SystemLoginItemManager()
        self.loginManager = manager
        orderedStations = StationOrder.stations(defaults: defaults)
        let hidden = StationVisibility.hiddenStations(defaults: defaults)
        hiddenStations = hidden
        appearance = AppAppearance(rawValue: defaults.string(forKey: AppAppearance.preferenceKey) ?? "") ?? .system
        alwaysShowDockIcon = defaults.bool(forKey: Self.alwaysShowDockIconKey)
        animateMenuBarIcon = defaults.bool(forKey: Self.animateMenuBarIconKey)
        showSleepTimerInMenuBar = defaults.object(forKey: Self.showSleepTimerInMenuBarKey) == nil
            ? true : defaults.bool(forKey: Self.showSleepTimerInMenuBarKey)
        menuBarDisplay = MenuBarDisplay(rawValue: defaults.string(forKey: MenuBarDisplay.preferenceKey) ?? "") ?? .iconOnly
        language = AppLanguage(rawValue: defaults.string(forKey: AppLanguage.preferenceKey) ?? "") ?? .system
        let storedDefault = DefaultStationChoice(storedValue: defaults.string(forKey: PlaybackPreferences.defaultStationKey))
        if case .station(let selected) = storedDefault, hidden.contains(selected) {
            defaultStation = .lastListened
            defaults.removeObject(forKey: PlaybackPreferences.defaultStationKey)
        } else { defaultStation = storedDefault }
        autoPlayOnLaunch = defaults.bool(forKey: PlaybackPreferences.autoPlayOnLaunchKey)
        loginState = manager.state
        catalogueObservation = NotificationCenter.default.publisher(for: StationCatalog.didChange).sink { [weak self] _ in
            self?.refreshCatalogueReferences()
        }
    }
    func text(_ zh: String, _ en: String) -> String { RadioText(zh, en).value(language) }
    func refreshLoginState() { loginState = loginManager.state }
    func openLoginSettings() { loginManager.openSystemSettings() }

    func setLaunchAtLogin(_ enabled: Bool) async {
        guard !isUpdatingLogin else { return }
        isUpdatingLogin = true
        loginError = nil
        defer {
            refreshLoginState()
            isUpdatingLogin = false
        }
        do { try await loginManager.setEnabled(enabled) }
        catch {
            // Show a stable message and error code, without persisting a false success.
            let code = (error as NSError).code
            loginError = RadioText("无法更改开机自启动（错误 \(code)）。请在系统“登录项”中检查 RadioBar。",
                                   "Unable to change launch at login (error \(code)). Check RadioBar in system Login Items.")
        }
    }
}
