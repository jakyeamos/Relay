import AppKit
import RelayCore

enum RelayDestination: CaseIterable {
    case today
    case playbook
    case usage

    var title: String {
        switch self {
        case .today: return "Today"
        case .playbook: return "Playbook"
        case .usage: return "Usage"
        }
    }

    var subtitle: String {
        switch self {
        case .today: return "See what needs your attention and get back to work."
        case .playbook: return "Turn repeated corrections into reviewable improvements."
        case .usage: return "Understand local workflow activity and provider data freshness."
        }
    }
}

final class RelayWindowController: NSWindowController {
    private let rootViewController: RelayRootViewController

    init(store: SQLiteStore, monitor: MonitoringCoordinator) {
        rootViewController = RelayRootViewController(store: store, monitor: monitor)
        let window = NSWindow(contentViewController: rootViewController)
        window.title = "Relay"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1_160, height: 760))
        window.minSize = NSSize(width: 920, height: 600)
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(destination: RelayDestination) {
        rootViewController.show(destination: destination)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class RelayRootViewController: NSSplitViewController {
    private let sidebar: RelaySidebarViewController
    private let content: RelayContentViewController

    init(store: SQLiteStore, monitor: MonitoringCoordinator) {
        sidebar = RelaySidebarViewController()
        content = RelayContentViewController(store: store, monitor: monitor)
        super.init(nibName: nil, bundle: nil)
        sidebar.onSelect = { [weak self] destination in
            self?.show(destination: destination)
        }
        addSplitViewItem(NSSplitViewItem(sidebarWithViewController: sidebar))
        addSplitViewItem(NSSplitViewItem(viewController: content))
        splitView.setPosition(230, ofDividerAt: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(destination: RelayDestination) {
        sidebar.select(destination: destination)
        content.show(destination: destination)
    }
}
