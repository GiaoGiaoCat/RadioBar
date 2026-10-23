import SwiftUI
import AppKit

@MainActor
private final class NoLogin: LoginItemManaging {
    var state: LoginItemState { .disabled }
    func setEnabled(_ enabled: Bool) async throws {}
    func openSystemSettings() {}
}

/// Fake OS envelope and in-memory transfer; source payload writer, NSViews and destination callbacks are production code.
@MainActor
private final class DragInfo: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .move
    var draggingLocation: NSPoint = .zero
    var draggedImageLocation: NSPoint = .zero
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any?
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var payloadItem: NSPasteboardItem?
    func payload(_ station: Station) { payloadItem = ChannelDragHandle.HandleView.pasteboardItem(for: station) }
}

@main
struct NativeChannelDropTests {
    @MainActor static func main() throws {
        let interactive = Bundle.main.bundleIdentifier == "local.victor.RadioBar.DragTests"
        NSApplication.shared.setActivationPolicy(interactive ? .regular : .prohibited)
        let suite = "RadioBar.NativeDropTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, loginManager: NoLogin())
        let editorTest = interactive && (Bundle.main.object(forInfoDictionaryKey: "RadioBarStationEditorTest") as? Bool == true)
        let visibilityFeedbackTest = interactive && (Bundle.main.object(forInfoDictionaryKey: "RadioBarVisibilityFeedbackTest") as? Bool == true)
        if visibilityFeedbackTest {
            for station in Station.allCases where station != .kiss { settings.setStationVisible(station, false) }
            settings.defaultStation = .station(.kiss)
            settings.dismissStationVisibilityFeedback()
        }
        let navigation = SettingsNavigation()
        navigation.page = .channels
        let timer = SleepTimer(defaults: defaults) {}
        let configurationSupport = FileManager.default.temporaryDirectory.appendingPathComponent("RadioBar-DragConfig-" + UUID().uuidString)
        let configurationFile = StationCatalog.userFile(in: configurationSupport)
        let factoryData = try StationCatalog.defaultData()
        _ = try StationCatalog.load(userFile: configurationFile, defaultData: factoryData)
        var configuration = try JSONSerialization.jsonObject(with: factoryData) as! [String: Any]
        var entries = configuration["stations"] as! [[String: Any]]
        let bccIndex = entries.firstIndex { $0["id"] as? String == "bcc" }!
        entries[bccIndex]["name"] = ["zh": "重新加载的中广", "en": "Reloaded BCC"]
        configuration["stations"] = entries
        let originalData = try JSONSerialization.data(withJSONObject: configuration)
        try originalData.write(to: configurationFile, options: .atomic)
        defer { try? FileManager.default.removeItem(at: configurationSupport) }
        let root = RadioSettingsView(settings: settings, navigation: navigation, timer: timer,
                                     stationConfigurationSupportDirectory: configurationSupport)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.width, height: SettingsLayout.height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        SettingsLayout.configure(window)
        host.safeAreaRegions = []
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: SettingsLayout.width, height: SettingsLayout.height)
        func pump() {
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let info = DragInfo()
        let type = NSPasteboard.PasteboardType(ChannelReorderSession.pasteboardType)
        func destination(_ station: Station) -> ChannelDropDestinationView {
            let row = descendants(host).compactMap { $0 as? ChannelDropDestinationView }.first { $0.station == station }!
            row.readStationID = { _ in info.payloadItem?.string(forType: type) }
            return row
        }
        func handle(_ station: Station) -> ChannelDragHandle.HandleView {
            descendants(host).compactMap { $0 as? ChannelDragHandle.HandleView }.first { $0.station == station }!
        }
        pump()
        if interactive {
            var sawLastVisible = false
            var sawDefaultReset = false
            let visibilityObservation = settings.$stationVisibilityFeedback.sink { feedback in
                if feedback == .lastVisible { sawLastVisible = true }
                if feedback == .defaultReset { sawDefaultReset = true }
            }
            var reloadObserved = false
            let reloadObservation = settings.$orderedStations.sink { stations in
                if stations.contains(where: { $0.menuName.en == "Reloaded BCC" }) { reloadObserved = true }
            }
            let delegate = InteractiveDragWindowDelegate()
            window.delegate = delegate
            window.title = "RadioBar Drag Tests"
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            pump()
            let origin = window.frame.origin
            let originalOrder = settings.orderedStations
            withExtendedLifetime(delegate) { NSApp.run() }
            withExtendedLifetime(reloadObservation) { }
            withExtendedLifetime(visibilityObservation) { }
            if editorTest {
                let data = try Data(contentsOf: configurationFile)
                let disk = try StationConfiguration.decode(data)
                precondition(disk.contains { $0.id.hasPrefix("user.") && $0.title.en == "Editor Test" }, "Add a station named Editor Test")
                precondition(disk.first { $0.id == "bcc" }?.title.en == "Edited BCC", "Edit BCC without changing its ID")
                precondition(!disk.contains { $0.id == "ufo" }, "Delete UFO with confirmation")
                precondition(settings.orderedStations.contains { $0.title.en == "Editor Test" })
                precondition(AppSettings(defaults: defaults, loginManager: NoLogin()).orderedStations == settings.orderedStations)
                let backups = try FileManager.default.contentsOfDirectory(atPath: configurationFile.deletingLastPathComponent().path).filter { $0.hasPrefix("stations.backup-v2-") }
                precondition(backups.count >= 3 && window.frame.origin == origin)
                let report = "PASS: native editor add/edit/delete writes JSON, applies the list, preserves IDs and window origin, and creates sibling backups\n"
                try report.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("native-station-editor-result.txt"), atomically: true, encoding: .utf8)
                print(report)
                return
            }
            if visibilityFeedbackTest {
                precondition(sawLastVisible && sawDefaultReset, "Exercise both visibility prompts")
                precondition(settings.stationVisibilityFeedback == nil, "Dismiss the final prompt")
                precondition(settings.visibleStations == [.musicRadio] && settings.defaultStation == .lastListened)
                precondition(AppSettings(defaults: defaults, loginManager: NoLogin()).visibleStations == [.musicRadio])
                precondition(window.frame.origin == origin)
                let report = "PASS: actual last-visible toggle explains rejection; showing CNR then hiding default KISS explains fallback; acknowledged prompts clear and visibility persists\n"
                try report.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("native-station-visibility-result.txt"), atomically: true, encoding: .utf8)
                print(report)
                return
            }
            precondition(reloadObserved, "Click Reload before restoring bundled stations")
            precondition(window.frame.origin == origin, "Dragging a station must not move the window")
            precondition(settings.orderedStations != originalOrder, "Perform a station drag before closing")
            precondition(AppSettings(defaults: defaults, loginManager: NoLogin()).orderedStations == settings.orderedStations)
            let restoredData = try Data(contentsOf: configurationFile)
            precondition(restoredData == factoryData, "Click Restore bundled stations before closing")
            precondition(Station.allCases.first(where: { $0.id == "bcc" })?.menuName.en != "Reloaded BCC",
                         "Restore must apply the bundled catalogue immediately")
            let backups = try FileManager.default.contentsOfDirectory(at: configurationFile.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("stations.backup-") }
            precondition(!backups.isEmpty)
            let savedData = try Data(contentsOf: backups[0])
            precondition(savedData == originalData, "Restore must back up the isolated user configuration")
            let report = "PASS: real mouse drag persisted order with unchanged window origin \(origin); reload updated metadata; restore backed up, replaced and applied isolated JSON\n" + settings.orderedStations.map(\.id).joined(separator: ", ")
            try report.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("native-channel-drag-result.txt"), atomically: true, encoding: .utf8)
            print("PASS: real mouse drag changed and persisted station order without moving the settings window")
            return
        }
        precondition(window.isMovableByWindowBackground)
        for handle in descendants(host).compactMap({ $0 as? ChannelDragHandle.HandleView }) {
            precondition(!handle.mouseDownCanMoveWindow, "Station handles must not initiate window movement")
            let center = NSPoint(x: handle.bounds.midX, y: handle.bounds.midY)
            guard handle.visibleRect.contains(center) else { continue }
            // NSView.hitTest takes a point in the receiver's superview coordinates.
            let point = handle.convert(center, to: host.superview)
            precondition(host.hitTest(point) === handle, "Visible handle \(handle.station.id) must receive mouse input, got \(String(describing: host.hitTest(point)))")
        }
        print("PASS: production titled window allows background movement, but station handles retain mouse input and cannot initiate window movement")
        precondition(descendants(host).compactMap { $0 as? ChannelDropDestinationView }.count == Station.allCases.count)
        for row in descendants(host).compactMap({ $0 as? ChannelDropDestinationView }) {
            precondition(row.registeredDraggedTypes.contains(type))
            precondition(row.host.superview === row && !row.host.registeredDraggedTypes.contains(type))
            precondition(row.bounds.height == 38 && row.host.frame == row.bounds)
        }
        print("PASS: actual settings page has 12 native receivers registered for the source pasteboard type; hosting children cannot intercept that type")
        info.draggingDestinationWindow = window
        let source = handle(.ufo)
        let session = source.reorderSession!
        func prepare(_ source: ChannelDragHandle.HandleView, _ target: ChannelDropDestinationView, y: CGFloat) {
            info.draggingSource = source
            info.draggingSourceOperationMask = .move
            info.payload(source.station)
            info.draggingLocation = target.convert(NSPoint(x: 100, y: y), to: nil)
            session.begin(source.station)
        }
        let first = destination(.kiss)
        prepare(source, first, y: 6)
        precondition(first.draggingEntered(info) == .move)
        precondition(session.target == .init(station: .kiss, after: false))
        precondition(settings.orderedStations == Station.allCases)
        precondition(first.prepareForDragOperation(info))
        precondition(first.performDragOperation(info))
        precondition(settings.orderedStations == [.ufo] + Station.allCases.filter { $0 != .ufo })
        precondition(session.source == nil && session.target == nil)
        precondition(AppSettings(defaults: defaults, loginManager: NoLogin()).orderedStations == settings.orderedStations)
        print("PASS: native entered -> prepare -> perform inserts before the top half and persists; source cleanup follows successful commit")
        pump()
        let below = destination(.loveRadio)
        prepare(handle(.ufo), below, y: 31)
        precondition(below.draggingUpdated(info) == .move)
        precondition(session.target == .init(station: .loveRadio, after: true))
        precondition(below.prepareForDragOperation(info) && below.performDragOperation(info))
        let order = settings.orderedStations
        precondition(order.firstIndex(of: .ufo)! == order.firstIndex(of: .loveRadio)! + 1)
        print("PASS: updated native callback converts window coordinates and inserts after the lower half")
        pump()
        let target = destination(.bcc)
        let kiss = handle(.kiss)
        let unchanged = settings.orderedStations
        prepare(kiss, target, y: 5)
        precondition(target.draggingEntered(info) == .move)
        target.draggingExited(info)
        precondition(session.target == nil)
        session.cancel()
        precondition(!target.prepareForDragOperation(info) && !target.performDragOperation(info))
        precondition(settings.orderedStations == unchanged)
        prepare(kiss, target, y: 5)
        info.draggingSource = NSObject()
        precondition(target.draggingEntered(info).isEmpty && !target.performDragOperation(info))
        info.draggingSource = kiss
        info.payload(.swissJazz)
        precondition(target.draggingEntered(info).isEmpty && !target.performDragOperation(info))
        info.payload(.kiss)
        info.draggingSourceOperationMask = .copy
        precondition(target.draggingEntered(info).isEmpty && !target.performDragOperation(info))
        session.cancel()
        prepare(kiss, destination(.kiss), y: 8)
        precondition(destination(.kiss).draggingEntered(info).isEmpty)
        precondition(!destination(.kiss).performDragOperation(info))
        session.cancel()
        precondition(settings.orderedStations == unchanged)
        print("PASS: exited/cancelled, external source, forged station payload, copy-only and self drops cannot reorder")
        settings.setStationVisible(.classic947, false)
        pump()
        let hidden = handle(.classic947)
        let target2 = destination(.kiss)
        prepare(hidden, target2, y: 5)
        precondition(target2.draggingEntered(info) == .move && target2.performDragOperation(info))
        precondition(!settings.visibleStations.contains(.classic947))
        settings.setStationVisible(.classic947, true)
        precondition(settings.orderedStations.firstIndex(of: .classic947)! + 1 == settings.orderedStations.firstIndex(of: .kiss)!)
        print("PASS: native drops move hidden channels without changing visibility; restoring shows them at the saved position")
        print("PASS: native channel drop regression completed without network, audio or desktop mouse control")
    }
}

@MainActor
private final class InteractiveDragWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { NSApp.stop(nil) }
}
