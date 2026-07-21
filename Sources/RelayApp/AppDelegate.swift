import AppKit
import RelayCore

@MainActor
final class RelayAppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: RelayWindowController?
    private var store: SQLiteStore?
    private var monitor: MonitoringCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let store = try SQLiteStore()
            let configuration = RelayConfiguration.load()
            let monitor = MonitoringCoordinator(store: store, adapters: configuration.makeAdapters())
            self.store = store
            self.monitor = monitor
            windowController = RelayWindowController(store: store, monitor: monitor)
            windowController?.showWindow(nil)
            configureMenu()
            monitor.start()
            _ = monitor.runOnce()
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Relay could not start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }

    @objc private func showToday() {
        windowController?.show(destination: .today)
    }

    @objc private func showPlaybook() {
        windowController?.show(destination: .playbook)
    }

    @objc private func showUsage() {
        windowController?.show(destination: .usage)
    }

    private func configureMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Relay", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Relay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let today = viewMenu.addItem(withTitle: "Today", action: #selector(showToday), keyEquivalent: "1")
        today.keyEquivalentModifierMask = [.command]
        let playbook = viewMenu.addItem(withTitle: "Playbook", action: #selector(showPlaybook), keyEquivalent: "2")
        playbook.keyEquivalentModifierMask = [.command]
        let usage = viewMenu.addItem(withTitle: "Usage", action: #selector(showUsage), keyEquivalent: "3")
        usage.keyEquivalentModifierMask = [.command]
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        NSApp.mainMenu = mainMenu
    }
}
