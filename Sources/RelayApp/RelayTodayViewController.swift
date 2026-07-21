import AppKit
import RelayCore

final class RelayTodayViewController: NSViewController, NSSearchFieldDelegate {
    private let store: SQLiteStore
    private let monitor: MonitoringCoordinator
    private let searchField = NSSearchField()
    private let sessionStack = NSStackView()
    private let scrollView = NSScrollView()
    private let emptyState = RelayEmptyStateView(
        title: "No sessions yet",
        message: "Start Codex and Relay will surface the session here automatically."
    )

    init(store: SQLiteStore, monitor: MonitoringCoordinator) {
        self.store = store
        self.monitor = monitor
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        searchField.placeholderString = "Search sessions, repositories, branches, or transcript text"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = relayButton("Refresh", target: self, action: #selector(refreshNow))
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshButton.imagePosition = .imageLeading

        let toolbar = NSStackView(views: [searchField, NSView(), refreshButton])
        toolbar.orientation = .horizontal
        toolbar.spacing = 10
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        sessionStack.orientation = .vertical
        sessionStack.alignment = .width
        sessionStack.spacing = 10
        sessionStack.translatesAutoresizingMaskIntoConstraints = false
        let document = NSView()
        document.addSubview(sessionStack)
        NSLayoutConstraint.activate([
            sessionStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            sessionStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            sessionStack.topAnchor.constraint(equalTo: document.topAnchor),
            sessionStack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        scrollView.documentView = document
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 18),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshFromNotification), name: .relayDataDidChange, object: nil)
        refresh()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        NotificationCenter.default.removeObserver(self, name: .relayDataDidChange, object: nil)
    }

    func controlTextDidChange(_ obj: Notification) {
        refresh()
    }

    @objc private func refreshFromNotification() {
        refresh()
    }

    @objc private func refreshNow() {
        _ = monitor.runOnce()
        refresh()
    }

    private func refresh() {
        let query = searchField.stringValue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let sessions = (try? self.store.sessions(search: query)) ?? []
            DispatchQueue.main.async {
                self.render(sessions: sessions)
            }
        }
    }

    private func render(sessions: [Session]) {
        sessionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !sessions.isEmpty else {
            sessionStack.addArrangedSubview(emptyState)
            return
        }
        for session in sessions {
            sessionStack.addArrangedSubview(RelaySessionRow(session: session))
        }
    }
}

final class RelaySessionRow: NSView {
    private let session: Session

    init(session: Session) {
        self.session = session
        super.init(frame: .zero)
        let card = relayCard()
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let title = relayLabel(session.title, size: 15, weight: .semibold)
        let provider = relayLabel("\(session.provider.rawValue) · \(relativeDate(session.lastActivityAt))", size: 11, color: .secondaryLabelColor)
        let path = relayLabel(session.context.worktreePath ?? session.context.workingDirectory ?? "Repository not mapped", size: 12, color: .secondaryLabelColor)
        let explanation = relayLabel(session.statusEvidence.explanation, size: 11, color: .tertiaryLabelColor)
        let textStack = NSStackView(views: [title, provider, path, explanation])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let badge = RelayStatusBadge(status: session.status)
        let openButton = relayButton("Open", target: self, action: #selector(openContext))
        openButton.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: "Open context")
        openButton.imagePosition = .imageLeading
        let actionStack = NSStackView(views: [badge, openButton])
        actionStack.orientation = .vertical
        actionStack.alignment = .trailing
        actionStack.spacing = 10

        let row = NSStackView(views: [textStack, actionStack])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
            actionStack.widthAnchor.constraint(equalToConstant: 125)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func openContext() {
        do {
            try RelayActionService().resume(session: session)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not open the session context"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func relativeDate(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
