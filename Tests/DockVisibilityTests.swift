import AppKit
import SwiftUI

@MainActor
private final class DockTestLogin: LoginItemManaging {
    var state: LoginItemState { .disabled }
    func setEnabled(_ enabled: Bool) async throws {}
    func openSystemSettings() {}
}

/// Native window/delegate integration. Does not simulate mouse clicks or prove Dock rendering.
@main
struct DockVisibilityTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "RadioBar.DockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, loginManager: DockTestLogin())
        let timer = SleepTimer(defaults: defaults) {}
        let delegate = RadioBarApplicationDelegate()
        delegate.settings = settings
        delegate.timer = timer
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let controller = delegate.settingsWindow
        precondition(controller.window == nil)
        precondition(NSApp.activationPolicy() == .accessory)
        precondition(!delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
        print("PASS: default launch has no settings window and uses accessory policy")

        settings.alwaysShowDockIcon = true
        precondition(NSApp.activationPolicy() == .regular && controller.window == nil)
        settings.alwaysShowDockIcon = false
        precondition(NSApp.activationPolicy() == .accessory)
        print("PASS: preference changes apply without opening settings")

        controller.show(settings: settings, timer: timer, page: .sleepTimer)
        let window = controller.window!
        let host = window.contentView as! NSHostingView<RadioSettingsView>
        precondition(host.rootView.navigation.page == .sleepTimer)
        precondition(window.isVisible && NSApp.activationPolicy() == .regular)
        window.resignKey()
        window.orderOut(nil)
        precondition(NSApp.activationPolicy() == .regular)
        settings.alwaysShowDockIcon = true
        settings.alwaysShowDockIcon = false
        precondition(NSApp.activationPolicy() == .regular)
        precondition(!delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        precondition(controller.window === window && window.isVisible)
        precondition(host.rootView.navigation.page == .sleepTimer)
        window.performClose(nil)
        precondition(!window.isVisible && NSApp.activationPolicy() == .accessory)
        print("PASS: open settings retains regular policy through focus loss/occlusion and toggle-off; close restores accessory")

        settings.alwaysShowDockIcon = true
        precondition(!delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        precondition(controller.window === window && window.isVisible)
        precondition(host.rootView.navigation.page == .sleepTimer)
        precondition(!delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true))
        precondition(controller.window === window)
        window.performClose(nil)
        precondition(NSApp.activationPolicy() == .regular)
        settings.alwaysShowDockIcon = false
        precondition(NSApp.activationPolicy() == .accessory)
        print("PASS: Dock reopen callback reuses settings, and always-show survives window close")

        controller.show(settings: settings, timer: timer, page: .sync)
        precondition(controller.window === window && window.isVisible)
        precondition(host.rootView.navigation.page == .sync)
        window.performClose(nil)
        precondition(!window.isVisible && NSApp.activationPolicy() == .accessory)
        precondition(!delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        precondition(controller.window === window && window.isVisible)
        precondition(host.rootView.navigation.page == .sync)
        window.performClose(nil)
        print("PASS: dedicated Sync page routing reuses the settings window and survives close/reopen")

        settings.alwaysShowDockIcon = true
        let restored = AppSettings(defaults: defaults, loginManager: DockTestLogin())
        let relaunched = RadioBarApplicationDelegate()
        relaunched.settings = restored
        relaunched.timer = timer
        relaunched.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        precondition(NSApp.activationPolicy() == .regular && relaunched.settingsWindow.window == nil)
        restored.alwaysShowDockIcon = false
        precondition(NSApp.activationPolicy() == .accessory)
        print("PASS: stored always-show applies at launch without opening settings")
    }
}
