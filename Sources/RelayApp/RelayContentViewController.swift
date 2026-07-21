import AppKit
import RelayCore

final class RelayContentViewController: NSViewController {
    private let store: SQLiteStore
    private let monitor: MonitoringCoordinator
    private let titleLabel = NSTextField(labelWithString: "Today")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let contentContainer = NSView()
    private var currentController: NSViewController?

    init(store: SQLiteStore, monitor: MonitoringCoordinator) {
        self.store = store
        self.monitor = monitor
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = root

        titleLabel.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        let header = NSStackView(views: [titleLabel, subtitleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 5
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)
        root.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 32),
            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            contentContainer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),
            contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        show(destination: .today)
    }

    func show(destination: RelayDestination) {
        guard isViewLoaded else { return }
        titleLabel.stringValue = destination.title
        subtitleLabel.stringValue = destination.subtitle
        let controller: NSViewController
        switch destination {
        case .today:
            controller = RelayTodayViewController(store: store, monitor: monitor)
        case .playbook:
            controller = RelayPlaybookViewController(store: store)
        case .usage:
            controller = RelayUsageViewController(store: store)
        }
        if let currentController {
            currentController.view.removeFromSuperview()
            currentController.removeFromParent()
        }
        addChild(controller)
        currentController = controller
        let childView = controller.view
        childView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(childView)
        NSLayoutConstraint.activate([
            childView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            childView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            childView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }
}
