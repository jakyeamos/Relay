import AppKit
import RelayCore

final class RelayPlaybookViewController: NSViewController {
    private let store: SQLiteStore
    private let engine = PlaybookEngine()
    private let transactionManager = FileTransactionManager()
    private let stack = NSStackView()
    private let contentStack = NSStackView()
    private var lastTransaction: FileTransactionRecord?
    private var undoButton: NSButton?

    init(store: SQLiteStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = 12
        view.addSubview(stack)
        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        let title = relayLabel("Playbook Intelligence", size: 18, weight: .bold)
        let undo = relayButton("Undo Last", target: self, action: #selector(undoLastTransaction))
        undo.isEnabled = false
        undoButton = undo
        toolbar.addArrangedSubview(title)
        toolbar.addArrangedSubview(NSView())
        toolbar.addArrangedSubview(undo)
        toolbar.setHuggingPriority(.defaultLow, for: .horizontal)
        toolbar.setHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(toolbar)
        stack.addArrangedSubview(contentStack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refresh()
    }

    private func refresh() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let sessions = (try? store.sessions()) ?? []
        let report = engine.analyze(sessions: sessions)
        if report.pendingCandidates.isEmpty {
            contentStack.addArrangedSubview(RelayEmptyStateView(
                title: "Playbook is quiet",
                message: "Relay will surface evidence-backed candidates after it sees repeated workflow friction."
            ))
            return
        }

        let summary = relayLabel(
            "\(report.latestScanCandidates.count) new · \(report.pendingCandidates.count) pending · \(report.removalCandidates.count) removal candidate(s)",
            size: 12,
            color: .secondaryLabelColor
        )
        contentStack.addArrangedSubview(summary)

        for candidate in report.pendingCandidates {
            contentStack.addArrangedSubview(candidateRow(candidate))
        }
    }

    private func candidateRow(_ candidate: IntelligenceCandidate) -> NSView {
        let card = relayCard()
        let title = relayLabel(candidate.title, size: 14, weight: .semibold)
        let metadata = relayLabel(
            "\(candidate.lane.rawValue) · \(candidate.evidence.count) evidence item(s) · confidence \(Int(candidate.confidence * 100))%",
            size: 11,
            color: .secondaryLabelColor
        )
        let rationale = relayLabel(candidate.rationale, size: 12, color: .secondaryLabelColor)
        let preview = relayButton("Preview & Apply", target: self, action: #selector(previewSuggestion(_:)))
        preview.identifier = NSUserInterfaceItemIdentifier(candidate.id)
        let textStack = NSStackView(views: [title, metadata, rationale])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 5
        let row = NSStackView(views: [textStack, preview])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            preview.widthAnchor.constraint(equalToConstant: 125),
            textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 300)
        ])
        return card
    }

    @objc private func previewSuggestion(_ sender: NSButton) {
        guard let candidateID = sender.identifier?.rawValue,
              let candidate = engine.analyze(sessions: (try? store.sessions()) ?? []).pendingCandidates.first(where: { $0.id == candidateID }) else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose a Playbook file"
        panel.message = "Select the exact file Relay may modify. The path will be confirmed again before writing."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let targetURL = panel.url else { return }

        let currentContent = try? String(contentsOf: targetURL, encoding: .utf8)
        let proposedContent = makeProposedContent(candidate: candidate, current: currentContent)
        let suggestion = engine.makeSuggestion(
            for: candidate,
            targetURL: targetURL,
            proposedContent: proposedContent,
            currentContent: currentContent
        )
        let preview = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 260))
        preview.isEditable = false
        preview.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        preview.string = diff(current: currentContent ?? "", proposed: proposedContent)
        let scroll = NSScrollView(frame: preview.frame)
        scroll.documentView = preview
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        let alert = NSAlert()
        alert.messageText = suggestion.title
        alert.informativeText = "Review the full proposed change. Relay will write only after you approve this exact path."
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let record = try transactionManager.apply(suggestion, grant: PathGrant(paths: [targetURL.path]))
            try store.record(transaction: record)
            try store.record(auditEvent: AuditEvent(
                action: "apply-suggestion",
                entityID: suggestion.id,
                processingMode: "offline",
                detail: "Applied an explicitly approved Playbook transaction to \(targetURL.path)."
            ))
            lastTransaction = record
            undoButton?.isEnabled = true
            showSuccess("Relay applied the suggestion and recorded an undo snapshot.")
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func undoLastTransaction() {
        guard let transaction = lastTransaction else { return }
        do {
            let undone = try transactionManager.undo(transaction)
            try store.record(transaction: undone)
            try store.record(auditEvent: AuditEvent(
                action: "undo-suggestion",
                entityID: transaction.suggestionID,
                processingMode: "offline",
                detail: "Undid the last explicitly approved Playbook transaction."
            ))
            lastTransaction = nil
            undoButton?.isEnabled = false
            showSuccess("Relay restored the guarded undo snapshot.")
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func makeProposedContent(candidate: IntelligenceCandidate, current: String?) -> String {
        let addition = "\n\n## Relay Playbook note\n\n- \(candidate.title): \(candidate.rationale)\n"
        return (current ?? "").trimmingCharacters(in: .whitespacesAndNewlines) + addition
    }

    private func diff(current: String, proposed: String) -> String {
        let beforeLines = current.split(separator: "\n", omittingEmptySubsequences: false).map { "-\($0)" }
        let afterLines = proposed.split(separator: "\n", omittingEmptySubsequences: false).map { "+\($0)" }
        return (["--- before", "+++ after", ""] + beforeLines + afterLines).joined(separator: "\n")
    }

    private func showSuccess(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Done"
        alert.informativeText = message
        alert.runModal()
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Relay did not change the file"
        alert.informativeText = message
        alert.runModal()
    }
}
