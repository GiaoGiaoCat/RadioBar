import AppKit
import SwiftUI

private struct MenuBoundsProbe: NSViewRepresentable {
    let name: String
    final class Probe: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }
    func makeNSView(context: Context) -> NSView {
        let view = Probe(); view.identifier = NSUserInterfaceItemIdentifier(name); return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
private struct MenuColorSchemeProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {}
}
@MainActor private final class NativeMenuTestLogin: LoginItemManaging {
    var state: LoginItemState { .disabled }
    func setEnabled(_ enabled: Bool) async throws {}
    func openSystemSettings() {}
}
@MainActor private final class NativeMenuTestResolver: StreamURLResolving {
    func resolve(_ station: Station, attempt: Int) async throws -> StreamAddress {
        try await Task.sleep(for: .seconds(120))
        throw CancellationError()
    }
}
private final class NativeMenuTestClock {
    let anchor = ContinuousClock().now
    var now: ContinuousClock.Instant
    init() { now = anchor }
}

/// Exercises the production controller and extracted content using actual
/// NSStatusBarButton presentation and app-local native keyboard events. Playback
/// is simulated; this is not a physical mouse, glass-compositing or audio test.
@MainActor private final class NativeMenuFixture {
    let suite = "RadioBar.NativeMenuTests.\(UUID().uuidString)"
    let settings: AppSettings
    let radio: RadioPlayer
    var controller: NativeMenuBar!
    let settingsWindow = SettingsWindowController()
    let clock: NativeMenuTestClock
    var timer: Timer?
    var step = 0
    var results: [String] = []
    var openedSettings = 0
    var baselineWindow: NSWindow?
    var baselineButtonAccepted = false
    var nativeButtonAccepted = false
    var labelWidths: [String: CGFloat] = [:]
    let initial: [Station] = [.kiss, .musicRadio, .bcc, .asiaFM, .guangdong, .grooveSalad, .swissJazz]
    let appearances: [(AppLanguage, AppAppearance)] = [(.chinese,.light),(.chinese,.dark),(.traditionalChinese,.light),(.traditionalChinese,.dark),(.english,.light),(.english,.dark),(.chinese,.system)]
    let samples = [644,641,599,5382,5381,3600,3599,43200,43199]
    init() {
        let defaults = UserDefaults(suiteName: suite)!
        let testClock = NativeMenuTestClock()
        clock = testClock
        settings = AppSettings(defaults: defaults, loginManager: NativeMenuTestLogin())
        radio = RadioPlayer(resolver: NativeMenuTestResolver(), defaults: defaults, sleepClockNow: { testClock.now })
        settings.language = .chinese
        settings.appearance = .light
        settingsWindow.configure(settings: settings)
        setVisible(initial)
        controller = NativeMenuBar(radio: radio, settings: settings, showSettings: { [weak self] page in
            guard let self else { return }
            self.openedSettings += 1
            self.settingsWindow.show(settings: self.settings, timer: self.radio.sleepTimer, page: page)
        }) { [weak self] dismiss in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(CapturedMenuView(radio: self.radio, settings: self.settings, usesNativeMenu: true,
                                           closeMenu: dismiss, showSettings: { [weak self] page in
                guard let self else { return }
                self.openedSettings += 1
                self.settingsWindow.show(settings: self.settings, timer: self.radio.sleepTimer, page: page)
            }))
        }
    }
    func setVisible(_ stations: [Station]) {
        for station in stations { settings.setStationVisible(station, true) }
        for station in Station.allCases where !stations.contains(station) { settings.setStationVisible(station, false) }
    }
    func start() {
        controller.install()
        let ticker = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer = ticker
        RunLoop.main.add(ticker, forMode: .common)
    }
    func open() { DispatchQueue.main.async { [weak self] in self?.controller.statusItem?.button?.performClick(nil) } }
    func check(_ valid: Bool, _ name: String) { results.append("\(valid ? "PASS" : "FAIL"): \(name)"); print(results.last!) }
    func key(_ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags) {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: controller.hosting?.window?.windowNumber ?? 0,
                                          context: nil, characters: text, charactersIgnoringModifiers: text,
                                          isARepeat: false, keyCode: code) else { return }
        NSApp.sendEvent(event)
    }
    func find(_ id: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == id { return view }
        return view.subviews.lazy.compactMap { self.find(id,in:$0) }.first
    }
    func rows(in view: NSView) -> [NSView] {
        (view.identifier?.rawValue.hasPrefix("menuRow:") == true ? [view] : []) + view.subviews.flatMap { rows(in:$0) }
    }
    func click(_ view: NSView, fraction: CGFloat = 0.5, tracking: Bool = false) {
        guard let window = view.window else { return }
        let point = view.convert(NSPoint(x:view.bounds.width*fraction,y:view.bounds.midY),to:nil)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                               windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        }
        if tracking { NSApp.postEvent(event(.leftMouseUp),atStart:true) }
        NSApp.sendEvent(event(.leftMouseDown))
        if !tracking { NSApp.sendEvent(event(.leftMouseUp)) }
    }
    func exerciseVolume() {
        guard let host = controller.hosting else { check(false,"missing volume host"); return }
        if let mute=find("menuMuteProbe",in:host),let slider=find("menuSliderProbe",in:host) {
            click(mute)
            nativeButtonAccepted = radio.isMuted
            click(slider,fraction:0.25,tracking:true)
        } else { check(false,"missing volume hit probes") }
    }
    func geometry(_ name: String, count: Int) {
        guard let window = controller.hosting?.window, window.isVisible, let root = window.contentView,
              let header = find("menuHeaderProbe",in:root), let bottom = find("menuBottomProbe",in:root),
              let anchor = controller.statusItem?.button?.window else { check(false,"\(name) missing native window"); return }
        let headerRect = header.convert(header.bounds,to:root), bottomRect = bottom.convert(bottom.bounds,to:root)
        let top = root.isFlipped ? headerRect.minY : root.bounds.height-headerRect.maxY
        let tail = root.isFlipped ? root.bounds.height-bottomRect.maxY : bottomRect.minY
        let rowViews = rows(in:root)
        let gap = anchor.frame.minY-window.frame.maxY
        let expected = CGFloat(208+24*count)
        let appearance = settings.appearance.nativeAppearance?.name ?? NSApp.effectiveAppearance.name
        let colorMatches = window.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == NSAppearance(named:appearance)?.bestMatch(from:[.aqua,.darkAqua])
        check(abs(window.frame.width-256)<0.5 && abs(window.frame.height-expected)<0.5
              && abs(top-9)<0.5 && abs(tail-5)<0.5 && abs(gap-1)<0.5
              && rowViews.count == count+5 && rowViews.allSatisfy { abs($0.frame.height-24)<0.5 }
              && colorMatches && controller.menu.items.filter({!$0.isHidden}).count == 1,
              "\(name) count=\(count) frame=\(window.frame) top=\(top) bottom=\(tail) gap=\(gap) rows=\(rowViews.map{$0.frame.height}) appearance=\(colorMatches)")
    }
    func tick() {
        step += 1
        switch step {
        case 1:
            let host=NSHostingView(rootView:CapturedMenuView(radio:radio,settings:settings))
            let window=NSWindow(contentRect:NSRect(x:100,y:100,width:256,height:376),styleMask:[.titled],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false; window.contentView=host; baselineWindow=window
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        case 2:
            if let root=baselineWindow?.contentView,let mute=find("menuMuteProbe",in:root) { click(mute) }
            baselineButtonAccepted=radio.isMuted
            if radio.isMuted { radio.toggleMute() }
            baselineWindow?.contentView=nil; baselineWindow?.close(); baselineWindow=nil
        case 3,8,13,20,25,53,57: open()
        case 4: geometry("initial-seven",count:7); exerciseVolume()
        case 5:
            check((0.1..<0.5).contains(radio.volume) && controller.isOpen,"native mouse events update slider without dismissing menu volume=\(radio.volume)")
            check(baselineButtonAccepted && nativeButtonAccepted,"native mute click compared with reference button baseline=\(baselineButtonAccepted)")
            key(" ",code:49,modifiers:[])
        case 7:
            check(radio.wantsPlayback && controller.isOpen,"space toggles playback without dismissing menu via native event")
            if ProcessInfo.processInfo.environment["RADIOBAR_NATIVE_MENU_VOLUME_ONLY"] == "1" { finish() }
            radio.pause(); controller.menu.cancelTracking()
        case 10: key("r",code:15,modifiers:.command)
        case 12:
            check(radio.wantsPlayback && controller.isOpen,"command-R reconnects without dismissing menu via native event")
            radio.pause(); controller.menu.cancelTracking()
        case 15: key(",",code:43,modifiers:.command)
        case 17:
            check(openedSettings == 1 && settingsWindow.window?.isVisible == true && !controller.isOpen,"command-comma opens production settings after dismiss")
        case 18: settingsWindow.window?.performClose(nil)
        case 19: setVisible([.musicRadio])
        case 22: geometry("hidden-to-one",count:1); controller.menu.cancelTracking()
        case 24: setVisible(initial)
        case 27: geometry("restore-seven",count:7); controller.menu.cancelTracking()
        case 52: setVisible(Station.allCases)
        case 55: geometry("twelve-stations",count:12); controller.menu.cancelTracking()
        case 56: setVisible(Array(initial.prefix(5)))
        case 59: geometry("five-stations",count:5); controller.menu.cancelTracking()
        case 60: open()
        case 98:
            check(controller.menu.items.filter{$0.isHidden}.map(\.keyEquivalent) == [" ","r",",","q"],"only existing four native key equivalents")
            finish()
        default: break
        }
        if (30..<51).contains(step) {
            let index = (step-30)/3
            switch (step-30)%3 {
            case 0: settings.language=appearances[index].0; settings.appearance=appearances[index].1
            case 1: open()
            default: geometry("\(settings.language.rawValue)-\(settings.appearance.rawValue)",count:7); controller.menu.cancelTracking()
            }
        }
        if (60..<96).contains(step) {
            let index = (step-60)/2, sample = samples[index%samples.count]
            if (step-60)%2 == 0 {
                settings.menuBarDisplay = index<samples.count ? .iconAndStation : .iconOnly
                radio.station = .grooveSalad
                radio.sleepTimer.cancel()
                clock.now = clock.anchor
                radio.sleepTimer.minutesInput = "720"
                _ = radio.sleepTimer.start()
                clock.now = clock.anchor.advanced(by:.seconds(43200-sample))
                radio.sleepTimer.refresh()
            } else if let button=controller.statusItem?.button,let image=button.image {
                let text=radio.sleepTimer.remainingText
                let key="\(settings.menuBarDisplay.rawValue)-\(text.count)"
                let width=labelWidths[key] ?? image.size.width
                let name = settings.menuBarDisplay == .iconAndStation ? MenuBarTitle.abbreviated(radio.station.menuName.value(settings.language))+" · " : ""
                let prefixWidth = (("\u{2002}"+name) as NSString).size(withAttributes:[.font:MenuBarTitle.titleFont]).width
                let clockWidth = (text as NSString).size(withAttributes:[.font:MenuBarTitle.clockFont]).width
                let expected = ceil(18+prefixWidth+clockWidth)
                check(controller.isOpen && image.isTemplate && button.title.isEmpty && abs(width-image.size.width)<0.5 && abs(image.size.width-expected)<0.5,
                      "native countdown label \(index) text=\(text) imageWidth=\(image.size.width)")
                labelWidths[key]=image.size.width
                radio.sleepTimer.cancel()
            }
        }
    }
    func finish() {
        timer?.invalidate(); radio.pause(); radio.sleepTimer.cancel(); controller.menu.cancelTracking()
        settingsWindow.window?.performClose(nil)
        UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite)
        let scope = ProcessInfo.processInfo.environment["RADIOBAR_NATIVE_MENU_VOLUME_ONLY"] == "1" ? "volume-only" : "complete"
        let text="Native production menu integration (\(scope)); isolated preferences, simulated playback, app-local key events.\n"+results.joined(separator:"\n")+"\n"
        try? text.write(toFile:"build/native-menu-result.txt",atomically:true,encoding:.utf8)
        exit(results.contains(where:{$0.hasPrefix("FAIL:")}) ? 1 : 0)
    }
}

@main struct NativeMenuTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let fixture=NativeMenuFixture(); fixture.start()
        withExtendedLifetime(fixture) { NSApp.run() }
    }
}
