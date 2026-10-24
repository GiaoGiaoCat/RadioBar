import AppKit
import SwiftUI

/// An isolated comparison, not a production menu migration. NSMenu owns the
/// candidate's screen anchoring, material, rounded border and accessibility
/// transparency behavior. Playback and all preferences belong to the fixture.
@MainActor
private final class MenuSurfacePreview: NSObject, NSMenuDelegate {
    private let radio: RadioPlayer
    private let settings: AppSettings
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var nativeMenu: NSMenu?
    private var hosting: NSHostingView<NativeCapturedMenuView>?
    private var controls: NSWindow!
    private var backdrop: NSWindow!
    private var language: NSPopUpButton!
    private var appearance: NSPopUpButton!
    private var lastGeometry = ""
    private var geometryTimer: Timer?

    init(radio: RadioPlayer, settings: AppSettings) {
        self.radio = radio
        self.settings = settings
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right.circle", accessibilityDescription: "原生菜单预览 / Native menu preview")
        statusItem.button?.toolTip = "RadioBar 原生菜单预览 / Native menu preview"
        statusItem.button?.setAccessibilityLabel("RadioBar 原生菜单预览 / Native menu preview")
        makeCandidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordGeometry() }
        }
        geometryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func show() {
        makeBackdrop()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let title = NSTextField(labelWithString: "RadioBar 菜单外观预览 / Menu surface preview")
        title.font = .systemFont(ofSize: 15, weight: .medium)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(NSTextField(wrappingLabelWithString: "系统原生定位与背景；沿用当前内容布局。\nSystem menu placement and material with the current content layout."))
        let row = NSStackView()
        row.spacing = 8
        for (title, selector) in [
            ("当前效果 / Current", #selector(showCurrent)),
            ("调整预览 / Preview", #selector(showCandidate)),
            ("系统菜单参照 / Reference", #selector(showReference))
        ] {
            let button = NSButton(title: title, target: self, action: selector)
            button.bezelStyle = .rounded
            row.addArrangedSubview(button)
        }
        stack.addArrangedSubview(row)
        let choices = NSStackView()
        choices.spacing = 10
        language = NSPopUpButton()
        language.addItems(withTitles: ["简体中文", "繁體中文", "English"])
        language.target = self
        language.action = #selector(changeLanguage)
        appearance = NSPopUpButton()
        appearance.addItems(withTitles: ["跟随系统 / System", "浅色 / Light", "深色 / Dark"])
        appearance.target = self
        appearance.action = #selector(changeAppearance)
        choices.addArrangedSubview(language)
        choices.addArrangedSubview(appearance)
        let short = NSButton(checkboxWithTitle: "单台列表 / One station", target: self, action: #selector(changeStationCount(_:)))
        choices.addArrangedSubview(short)
        stack.addArrangedSubview(choices)
        stack.addArrangedSubview(NSTextField(wrappingLabelWithString: "彩色背景仅用于观察通透度；预览无直播音频。\nThe color backdrop reveals translucency. Playback is simulated."))
        let quit = NSButton(title: "关闭预览 / Close preview", target: self, action: #selector(closePreview))
        quit.bezelStyle = .rounded
        stack.addArrangedSubview(quit)
        controls = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 254),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        controls.title = "RadioBar 菜单外观预览 / Menu surface preview"
        controls.isReleasedWhenClosed = false
        controls.contentView = stack
        if let screen = statusItem.button?.window?.screen ?? NSScreen.main {
            controls.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 32, y: screen.visibleFrame.minY + 32))
        }
        controls.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeCandidate() {
        nativeMenu?.cancelTracking()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.appearance = settings.appearance.nativeAppearance
        let item = NSMenuItem()
        let host = NSHostingView(rootView: NativeCapturedMenuView(radio: radio, settings: settings, usesNativeMenu: true, showSettings: { [weak self] _ in
            self?.nativeMenu?.cancelTracking()
        }))
        host.sizingOptions = [.intrinsicContentSize]
        let natural = host.fittingSize
        host.frame = NSRect(origin: .zero, size: natural)
        item.view = host
        menu.addItem(item)
        hosting = host
        nativeMenu = menu
        statusItem.menu = menu
    }

    private func makeBackdrop() {
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return }
        let rect = NSRect(x: screen.frame.minX, y: screen.visibleFrame.maxY - 650,
                          width: screen.frame.width, height: 650)
        backdrop = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        backdrop.ignoresMouseEvents = true
        backdrop.contentView = SurfaceBackdrop(frame: NSRect(origin: .zero, size: rect.size))
        backdrop.orderFront(nil)
    }

    @objc private func showCurrent() {
        nativeMenu?.cancelTracking()
        for window in NSApp.windows {
            if let button = findStatusButton(in: window.contentView), button !== statusItem.button {
                DispatchQueue.main.async { button.performClick(nil) }
                return
            }
        }
    }

    @objc private func showCandidate() {
        makeCandidate()
        DispatchQueue.main.async { [weak self] in self?.statusItem.button?.performClick(nil) }
    }

    func menuDidClose(_ menu: NSMenu) {
        controls?.makeKeyAndOrderFront(nil)
    }

    @objc private func showReference() {
        nativeMenu?.cancelTracking()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.minimumWidth = 256
        menu.appearance = settings.appearance.nativeAppearance
        let header = NSMenuItem(title: "RadioBar", action: nil, keyEquivalent: "")
        menu.addItem(header)
        menu.addItem(.separator())
        for station in settings.visibleStations {
            let item = NSMenuItem(title: station.menuName.value(settings.language), action: #selector(referenceSelection), keyEquivalent: "")
            item.target = self
            item.state = station == radio.station ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: settings.text("关闭预览", "Close preview"), action: #selector(closePreview), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        nativeMenu = menu
        statusItem.menu = menu
        DispatchQueue.main.async { [weak self] in self?.statusItem.button?.performClick(nil) }
    }

    @objc private func referenceSelection() {}
    @objc private func closePreview() { NSApp.terminate(nil) }
    @objc private func changeLanguage() {
        nativeMenu?.cancelTracking()
        settings.language = [AppLanguage.chinese, .traditionalChinese, .english][language.indexOfSelectedItem]
    }
    @objc private func changeAppearance() {
        nativeMenu?.cancelTracking()
        settings.appearance = [AppAppearance.system, .light, .dark][appearance.indexOfSelectedItem]
    }
    @objc private func changeStationCount(_ sender: NSButton) {
        nativeMenu?.cancelTracking()
        let visible: [Station] = sender.state == .on ? [.musicRadio] : [.kiss, .musicRadio, .bcc, .asiaFM, .guangdong, .grooveSalad, .swissJazz]
        for station in visible { settings.setStationVisible(station, true) }
        for station in Station.allCases where !visible.contains(station) { settings.setStationVisible(station, false) }
    }

    private func findStatusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap { self.findStatusButton(in: $0) }.first
    }

    private func recordGeometry() {
        guard let menuWindow = hosting?.window, menuWindow.isVisible,
              let buttonWindow = statusItem.button?.window else { return }
        let report = "nativeMenuID=\(menuWindow.windowNumber) nativeMenuFrame=\(menuWindow.frame) statusButtonWindow=\(buttonWindow.frame) gap=\(buttonWindow.frame.minY - menuWindow.frame.maxY) content=\(hosting?.frame ?? .zero) appearance=\(settings.appearance.rawValue) language=\(settings.language.rawValue) stations=\(settings.visibleStations.count)\n"
        guard report != lastGeometry else { return }
        lastGeometry = report
        // Content-cache images verify layout only, not desktop translucency.
        if let view = menuWindow.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let name = "menu-surface-layout-\(settings.language.rawValue)-\(settings.appearance.rawValue)-\(settings.visibleStations.count).png"
            let image = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(name)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: image)
        }
        let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("menu-surface-geometry.txt")
        if let handle = try? FileHandle(forWritingTo: output) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(report.utf8))
        } else {
            try? report.write(to: output, atomically: true, encoding: .utf8)
        }
    }
}

private final class SurfaceBackdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        // Broad colors plus edges/text make system blur and tint observable.
        let colors = [NSColor(calibratedRed: 0.45, green: 0.68, blue: 0.82, alpha: 1),
                      NSColor(calibratedRed: 0.70, green: 0.78, blue: 0.61, alpha: 1),
                      NSColor(calibratedRed: 0.86, green: 0.69, blue: 0.55, alpha: 1),
                      NSColor(calibratedRed: 0.69, green: 0.63, blue: 0.80, alpha: 1)]
        for (index, color) in colors.enumerated() {
            color.setFill()
            NSRect(x: 0, y: CGFloat(index) * bounds.height / 4,
                   width: bounds.width, height: bounds.height / 4 + 1).fill()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black.withAlphaComponent(0.28)]
        for x in stride(from: 20.0, to: bounds.width, by: 360.0) {
            for y in stride(from: 20.0, to: bounds.height, by: 92.0) {
                ("RadioBar · 背景 / Backdrop" as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
            }
        }
    }
}
