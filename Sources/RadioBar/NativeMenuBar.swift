import AppKit
import Combine
import SwiftUI

/// NSMenu owns placement and the system surface. Only its custom item's content
/// is measured; never resize or reposition the enclosing native menu window.
@MainActor
final class NativeMenuBar: NSObject, NSMenuDelegate {
    private final class HostingView: NSHostingView<AnyView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
    private final class CommandMenu: NSMenu {
        var handleKey: ((NSEvent) -> Bool)?
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if handleKey?(event) == true { return true }
            return super.performKeyEquivalent(with: event)
        }
    }
    private(set) var menu = NSMenu()
    private(set) var statusItem: NSStatusItem?
    private(set) var hosting: NSHostingView<AnyView>?
    private(set) var isOpen = false
    private let radio: RadioPlayer
    private let settings: AppSettings
    private let signal: MenuBarSignal
    private let showSettings: (SettingsPage?) -> Void
    private let content: (@escaping () -> Void) -> AnyView
    private var subscriptions = Set<AnyCancellable>()
    private var refreshPending = false
    private var stationIDs: [String] = []
    private var layoutKey = ""
    private var keyMonitor: Any?
    private var generation = 0

    init(radio: RadioPlayer, settings: AppSettings, showSettings: @escaping (SettingsPage?) -> Void,
         content: @escaping (@escaping () -> Void) -> AnyView) {
        self.radio = radio
        self.settings = settings
        self.signal = MenuBarSignal(radio: radio, settings: settings)
        self.showSettings = showSettings
        self.content = content
        super.init()
        for publisher in [radio.objectWillChange.eraseToAnyPublisher(), settings.objectWillChange.eraseToAnyPublisher(),
                          signal.objectWillChange.eraseToAnyPublisher(), radio.sleepTimer.objectWillChange.eraseToAnyPublisher()] {
            publisher.sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &subscriptions)
        }
    }

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        rebuildContent()
        item.menu = menu
        refresh()
    }

    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        // ObservableObject publishes before the values change. Read the latest
        // snapshot after publication, coalescing playback/timer notifications.
        RunLoop.main.perform(inModes: [.default, .eventTracking]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshPending = false
                self.refresh()
            }
        }
    }

    private func refresh() {
        let ids = settings.visibleStations.map(\.id)
        let key = ids.joined(separator: "|") + "-\(settings.language.rawValue)-\(settings.appearance.rawValue)-\(radio.stationIsRemoved)"
        if key != layoutKey {
            if isOpen { menu.cancelTracking() }
            else if statusItem != nil { rebuildContent() }
        }
        menu.appearance = settings.appearance.nativeAppearance
        guard let button = statusItem?.button else { return }
        let countdown = settings.showSleepTimerInMenuBar && radio.sleepTimer.isRunning ? radio.sleepTimer.remainingText : nil
        let name = settings.menuBarDisplay == .iconAndStation ? radio.station.menuName.value(settings.language) : nil
        button.font = MenuBarTitle.titleFont
        if let countdown {
            button.image = MenuBarTitle.image(antenna: signal.image, stationName: name, countdown: countdown)
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            button.image = signal.image
            button.title = MenuBarTitle.text(stationName: name, countdown: nil)
            button.imagePosition = name == nil ? .imageOnly : .imageLeading
        }
        button.setAccessibilityLabel("RadioBar · \(radio.station.menuName.value(settings.language)) · \(radio.statusText.value(settings.language))"
            + (countdown.map { " · " + RadioText("剩余时间", "Time remaining").value(settings.language) + " " + $0 } ?? ""))
        button.toolTip = radio.station.menuName.value(settings.language) + (countdown.map { " · " + $0 } ?? "")
    }

    private func rebuildContent() {
        generation &+= 1
        let replacement = CommandMenu()
        replacement.handleKey = { [weak self] in self?.handleKey($0) ?? false }
        replacement.autoenablesItems = false
        replacement.delegate = self
        menu = replacement
        menu.appearance = settings.appearance.nativeAppearance
        let host = HostingView(rootView: content { [weak self] in self?.menu.cancelTracking() })
        host.sizingOptions = [.intrinsicContentSize]
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let item = NSMenuItem()
        item.view = host
        menu.addItem(item)
        hosting = host
        stationIDs = settings.visibleStations.map(\.id)
        layoutKey = stationIDs.joined(separator: "|") + "-\(settings.language.rawValue)-\(settings.appearance.rawValue)-\(radio.stationIsRemoved)"
        // Custom item views do not reliably register SwiftUI key equivalents
        // with menu tracking. Native commands and the open-menu-only local
        // monitor route the same existing keys without adding visible rows.
        for (key, modifiers, action) in [
            (" ", NSEvent.ModifierFlags(), #selector(togglePlayback)),
            ("r", .command, #selector(reconnect)),
            (",", .command, #selector(openSettings)),
            ("q", .command, #selector(quit))
        ] {
            let command = NSMenuItem(title: "", action: action, keyEquivalent: key)
            command.target = self
            command.keyEquivalentModifierMask = modifiers
            command.isHidden = true
            command.allowsKeyEquivalentWhenHidden = true
            menu.addItem(command)
        }
        statusItem?.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        radio.sleepTimer.refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { menu.cancelTracking(); return }
        isOpen = true
        radio.sleepTimer.refresh()
        refresh()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard isOpen else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers.isEmpty, key == " " { togglePlayback(); return true }
        guard modifiers == .command else { return false }
        switch key {
        case "r": reconnect(); return true
        case ",": openSettings(); return true
        case "q": quit(); return true
        default: return false
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        isOpen = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        let closedGeneration = generation
        RunLoop.main.perform(inModes: [.default, .eventTracking]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isOpen, self.generation == closedGeneration else { return }
                self.rebuildContent()
                self.refresh()
            }
        }
    }

    @objc private func togglePlayback() { radio.toggle() }
    @objc private func reconnect() { radio.play() }
    @objc private func openSettings() {
        menu.cancelTracking()
        RunLoop.main.perform(inModes: [.default, .eventTracking]) { [weak self] in
            MainActor.assumeIsolated { self?.showSettings(nil) }
        }
    }
    @objc private func quit() { radio.pause(); NSApp.terminate(nil) }
}
