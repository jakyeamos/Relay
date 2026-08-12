import AppKit
import Foundation
import RelayCore

enum RelayDestination: CaseIterable, Equatable {
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
        case .today: return "Your active agent sessions and the context behind them."
        case .playbook: return "Review evidence-backed workflow improvements before they change files."
        case .usage: return "Local activity, freshness, and attention trends with explicit precision."
        }
    }

    var symbol: String {
        switch self {
        case .today: return "bolt.fill"
        case .playbook: return "book.closed"
        case .usage: return "chart.xyaxis.line"
        }
    }
}

@MainActor
final class RelayWindowController: NSWindowController {
    private let rootViewController: RelayWorkbenchViewController

    init(store: SQLiteStore, monitor: MonitoringCoordinator) {
        rootViewController = RelayWorkbenchViewController(store: store, monitor: monitor)
        let window = NSWindow(contentViewController: rootViewController)
        window.title = "Relay"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1_280, height: 820))
        window.minSize = NSSize(width: 920, height: 600)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("relay.workbench")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(destination: RelayDestination) {
        rootViewController.show(destination: destination)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func toggleCommandPalette() {
        rootViewController.toggleCommandPalette()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class RelayWorkbenchRootView: NSView {
    var onCommandPalette: (() -> Void)?
    var onEscape: (() -> Void)?
    var onShortcut: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("relay.workbench")
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Relay workbench")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), let character = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch character {
        case "k": onCommandPalette?(); return true
        case "1", "2", "3": onShortcut?(character); return true
        case "r": onShortcut?(character); return true
        case "i": onShortcut?(character); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

private struct RelayWorkbenchSnapshot: Sendable {
    let allSessions: [Session]
    let sessions: [Session]
    let summaries: [WorkspaceSummary]
    let hiddenWorkspaces: [RelayWorkspace]
    let candidates: [IntelligenceCandidate]
    let metrics: [UsageMetric]
    let activity: [UsageActivityPoint]
    let providerHealth: [ProviderHealth]
    let dataState: String
    let dataMessage: String?
}

@MainActor
final class RelayWorkbenchViewController: NSViewController, NSSplitViewDelegate {
    private let store: SQLiteStore
    private let monitor: MonitoringCoordinator
    private let resolver = WorkspaceResolver()
    private let usageService = UsageService()
    private let playbookEngine = PlaybookEngine()
    private let transactionManager = FileTransactionManager()

    private let rootView = RelayWorkbenchRootView()
    private let rootSplit = NSSplitView()
    private let contentSplit = NSSplitView()
    private let navigationPane = RelayNavigationPaneView()
    private let listPane = RelayListPaneView()
    private let inspectorPane = RelayInspectorPaneView()
    private let commandPalette = RelayCommandPaletteView()

    private var allSessions: [Session] = []
    private var sessions: [Session] = []
    private var summaries: [WorkspaceSummary] = []
    private var hiddenWorkspaces: [RelayWorkspace] = []
    private var candidates: [IntelligenceCandidate] = []
    private var metrics: [UsageMetric] = []
    private var activity: [UsageActivityPoint] = []
    private var providerHealth: [ProviderHealth] = []

    private var mode: RelayDestination = .today
    private var selectedWorkspaceID: String?
    private var selectedSessionID: String?
    private var selectedCandidateID: String?
    private var selectedMetricID: String?
    private var searchText = ""
    private var providerFilter: ProviderID?
    private var statusFilter: AgentStatus?
    private var sessionSortOrder: SessionSortOrder = .recent
    private var usageTimeRange: UsageTimeRange = .sevenDays
    private var isInspectorVisible = true
    private var isCompactList = false
    private var refreshGeneration = 0
    private var dataChangeObserver: NSObjectProtocol?
    private var didSetInitialSplitPositions = false
    private var inlineMessage: (text: String, tone: NSColor)?
    private var pendingSuggestion: Suggestion?
    private var pendingCandidateID: String?
    private var pendingTargetPath: String?
    private var pendingDiff: String?
    private var lastTransaction: FileTransactionRecord?

    private enum DefaultsKey {
        static let workspace = "Relay.workbench.workspaceID"
        static let session = "Relay.workbench.sessionID"
        static let candidate = "Relay.workbench.candidateID"
        static let metric = "Relay.workbench.metricID"
        static let mode = "Relay.workbench.mode"
        static let search = "Relay.workbench.search"
        static let provider = "Relay.workbench.provider"
        static let status = "Relay.workbench.status"
        static let sort = "Relay.workbench.sort"
        static let usageRange = "Relay.workbench.usageRange"
        static let inspector = "Relay.workbench.inspectorVisible"
        static let compact = "Relay.workbench.compactList"
        static let sidebarWidth = "Relay.workbench.sidebarWidth"
        static let centerWidth = "Relay.workbench.centerWidth"
    }

    init(store: SQLiteStore, monitor: MonitoringCoordinator) {
        self.store = store
        self.monitor = monitor
        super.init(nibName: nil, bundle: nil)
        restoreState()
        wireChildren()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        rootView.translatesAutoresizingMaskIntoConstraints = false
        view = rootView

        rootSplit.isVertical = true
        rootSplit.dividerStyle = .thin
        rootSplit.delegate = self
        rootSplit.translatesAutoresizingMaskIntoConstraints = false
        contentSplit.isVertical = true
        contentSplit.dividerStyle = .thin
        contentSplit.delegate = self
        contentSplit.translatesAutoresizingMaskIntoConstraints = false

        rootSplit.addArrangedSubview(navigationPane)
        rootSplit.addArrangedSubview(contentSplit)
        contentSplit.addArrangedSubview(listPane)
        contentSplit.addArrangedSubview(inspectorPane)
        rootView.addSubview(rootSplit)
        rootView.addSubview(commandPalette)

        NSLayoutConstraint.activate([
            rootSplit.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            rootSplit.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            rootSplit.topAnchor.constraint(equalTo: rootView.topAnchor),
            rootSplit.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            navigationPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 210),
            listPane.widthAnchor.constraint(greaterThanOrEqualToConstant: RelayDesign.minimumListWidth),
            inspectorPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            commandPalette.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            commandPalette.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 42),
            commandPalette.widthAnchor.constraint(equalToConstant: 560),
            commandPalette.heightAnchor.constraint(equalToConstant: 390)
        ])
        commandPalette.isHidden = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if !didSetInitialSplitPositions {
            let defaults = UserDefaults.standard
            let sidebarWidth = defaults.object(forKey: DefaultsKey.sidebarWidth) as? CGFloat ?? RelayDesign.sidebarWidth
            let centerWidth = defaults.object(forKey: DefaultsKey.centerWidth) as? CGFloat ?? 560
            rootSplit.setPosition(sidebarWidth, ofDividerAt: 0)
            contentSplit.setPosition(centerWidth, ofDividerAt: 0)
            didSetInitialSplitPositions = true
        }
        if dataChangeObserver == nil {
            dataChangeObserver = NotificationCenter.default.addObserver(
                forName: .relayDataDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshData() }
            }
        }
        refreshData()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let dataChangeObserver {
            NotificationCenter.default.removeObserver(dataChangeObserver)
            self.dataChangeObserver = nil
        }
    }

    func show(destination: RelayDestination) {
        mode = destination
        UserDefaults.standard.set(destination.title.lowercased(), forKey: DefaultsKey.mode)
        commandPalette.isHidden = true
        listPane.setMode(destination)
        refreshData()
    }

    func toggleCommandPalette() {
        if commandPalette.isHidden {
            commandPalette.setCommands(makeCommands())
            commandPalette.isHidden = false
            rootView.window?.makeFirstResponder(commandPalette.searchField)
        } else {
            dismissCommandPalette()
        }
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView else { return }
        guard splitView.bounds.width > 0 else { return }
        if splitView === rootSplit, let first = rootSplit.arrangedSubviews.first {
            UserDefaults.standard.set(first.frame.width, forKey: DefaultsKey.sidebarWidth)
        }
        if splitView === contentSplit, let first = contentSplit.arrangedSubviews.first {
            UserDefaults.standard.set(first.frame.width, forKey: DefaultsKey.centerWidth)
        }
    }

    private func wireChildren() {
        navigationPane.onSelectWorkspace = { [weak self] id in self?.selectWorkspace(id) }
        navigationPane.onSelectMode = { [weak self] destination in self?.show(destination: destination) }
        navigationPane.onRenameWorkspace = { [weak self] id in self?.renameWorkspace(id: id) }
        navigationPane.onTogglePinWorkspace = { [weak self] id in self?.togglePinWorkspace(id: id) }
        navigationPane.onHideWorkspace = { [weak self] id in self?.hideWorkspace(id: id) }
        navigationPane.onUnhideWorkspace = { [weak self] id in self?.unhideWorkspace(id: id) }
        navigationPane.onMoveWorkspace = { [weak self] id, direction in self?.moveWorkspace(id: id, direction: direction) }

        listPane.onSelectSession = { [weak self] id in self?.selectSession(id) }
        listPane.onSelectCandidate = { [weak self] id in self?.selectCandidate(id) }
        listPane.onSelectMetric = { [weak self] id in self?.selectMetric(id) }
        listPane.onSearchChanged = { [weak self] text in
            self?.searchText = text
            UserDefaults.standard.set(text, forKey: DefaultsKey.search)
            self?.refreshData()
        }
        listPane.onProviderChanged = { [weak self] provider in
            self?.providerFilter = provider
            UserDefaults.standard.set(provider?.rawValue, forKey: DefaultsKey.provider)
            self?.refreshData()
        }
        listPane.onStatusChanged = { [weak self] status in
            self?.statusFilter = status
            UserDefaults.standard.set(status?.rawValue, forKey: DefaultsKey.status)
            self?.refreshData()
        }
        listPane.onSortChanged = { [weak self] sortOrder in
            self?.sessionSortOrder = sortOrder
            UserDefaults.standard.set(sortOrder.rawValue, forKey: DefaultsKey.sort)
            self?.refreshData()
        }
        listPane.onUsageRangeChanged = { [weak self] range in
            self?.usageTimeRange = range
            UserDefaults.standard.set(range.rawValue, forKey: DefaultsKey.usageRange)
            self?.refreshData()
        }
        listPane.onRefresh = { [weak self] in self?.refreshNow() }
        listPane.onToggleInspector = { [weak self] in self?.toggleInspector() }
        listPane.onToggleDensity = { [weak self] in self?.toggleDensity() }

        commandPalette.onDismiss = { [weak self] in self?.dismissCommandPalette() }
        rootView.onCommandPalette = { [weak self] in self?.toggleCommandPalette() }
        rootView.onEscape = { [weak self] in
            if let self, !self.commandPalette.isHidden { self.dismissCommandPalette() }
        }
        rootView.onShortcut = { [weak self] key in
            switch key {
            case "1": self?.show(destination: .today)
            case "2": self?.show(destination: .playbook)
            case "3": self?.show(destination: .usage)
            case "r": self?.refreshNow()
            case "i": self?.toggleInspector()
            default: break
            }
        }
    }

    private func restoreState() {
        let defaults = UserDefaults.standard
        selectedWorkspaceID = defaults.string(forKey: DefaultsKey.workspace)
        selectedSessionID = defaults.string(forKey: DefaultsKey.session)
        selectedCandidateID = defaults.string(forKey: DefaultsKey.candidate)
        selectedMetricID = defaults.string(forKey: DefaultsKey.metric)
        searchText = defaults.string(forKey: DefaultsKey.search) ?? ""
        providerFilter = defaults.string(forKey: DefaultsKey.provider).flatMap(ProviderID.init(rawValue:))
        statusFilter = defaults.string(forKey: DefaultsKey.status).flatMap(AgentStatus.init(rawValue:))
        sessionSortOrder = defaults.string(forKey: DefaultsKey.sort).flatMap(SessionSortOrder.init(rawValue:)) ?? .recent
        if let raw = defaults.string(forKey: DefaultsKey.mode), let restored = RelayDestination.allCases.first(where: { $0.title.lowercased() == raw }) {
            mode = restored
        }
        if let raw = defaults.string(forKey: DefaultsKey.usageRange), let restored = UsageTimeRange(rawValue: raw) {
            usageTimeRange = restored
        }
        if defaults.object(forKey: DefaultsKey.inspector) != nil {
            isInspectorVisible = defaults.bool(forKey: DefaultsKey.inspector)
        }
        if defaults.object(forKey: DefaultsKey.compact) != nil {
            isCompactList = defaults.bool(forKey: DefaultsKey.compact)
        }
    }

    private func refreshData() {
        refreshGeneration += 1
        listPane.setTaskState("loading")
        inspectorPane.setTaskState("loading")
        let generation = refreshGeneration
        let store = self.store
        let resolver = self.resolver
        let usageService = self.usageService
        let playbookEngine = self.playbookEngine
        let workspaceID = selectedWorkspaceID
        let provider = providerFilter
        let status = statusFilter
        let sortOrder = sessionSortOrder
        let text = searchText
        let timeRange = usageTimeRange
        let health = monitor.adapters.map { $0.health() }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard self != nil else { return }
            let now = Date()
            var dataState = "ready"
            var dataMessage: String?
            let allSessions: [Session]
            do {
                allSessions = try store.sessions(query: SessionQuery(sortOrder: .recent, limit: 2_000))
            } catch {
                allSessions = []
                dataState = "data_unavailable"
                dataMessage = "Relay could not read the local session index."
            }
            var storedWorkspaces: [RelayWorkspace] = []
            do {
                try store.ensureWorkspaces(for: allSessions, now: now)
                storedWorkspaces = try store.workspaces(includeHidden: true)
            } catch {
                dataState = "data_unavailable"
                dataMessage = dataMessage ?? "Relay could not read the local workspace index."
            }
            let effectiveWorkspaceID = storedWorkspaces.first(where: { $0.id == workspaceID })?.isHidden == true ? nil : workspaceID
            let summaries = resolver.summaries(sessions: allSessions, storedWorkspaces: storedWorkspaces, now: now)
            let filteredSessions: [Session]
            do {
                filteredSessions = try store.sessions(query: SessionQuery(
                    workspaceID: effectiveWorkspaceID,
                    text: text,
                    provider: provider,
                    statuses: status.map { [$0] }.map(Set.init) ?? [],
                    sortOrder: sortOrder,
                    limit: 2_000
                ))
            } catch {
                filteredSessions = []
                dataState = "data_unavailable"
                dataMessage = dataMessage ?? "Relay could not search the local session index."
            }
            let scopedForPlaybook = allSessions.filter { session in
                resolver.matches(session, workspaceID: effectiveWorkspaceID) && (provider == nil || session.provider == provider)
            }
            let report = playbookEngine.analyze(sessions: scopedForPlaybook, now: now)
            let storedCandidates = (try? store.candidates()) ?? []
            let scopedSessionIDs = Set(scopedForPlaybook.map(\.id))
            var mergedCandidates = report.pendingCandidates.map { candidate -> IntelligenceCandidate in
                guard let stored = storedCandidates.first(where: { $0.id == candidate.id }) else {
                    try? store.saveCandidate(candidate)
                    return candidate
                }
                var restored = candidate
                restored.lifecycle = stored.lifecycle
                return restored
            }
            for stored in storedCandidates where !mergedCandidates.contains(where: { $0.id == stored.id }) {
                if stored.evidence.contains(where: { scopedSessionIDs.contains($0.sessionID) }) {
                    mergedCandidates.append(stored)
                }
            }
            let usageScope = UsageScope(workspaceID: effectiveWorkspaceID, provider: provider, timeRange: timeRange)
            let usageSessions = usageService.filter(sessions: allSessions, scope: usageScope, now: now)
            let metrics = usageService.localMetrics(sessions: usageSessions, now: now)
                + usageService.providerFreshnessMetrics(health: health, now: now)
            let activityDays: Int
            switch timeRange {
            case .today: activityDays = 1
            case .sevenDays: activityDays = 7
            case .thirtyDays: activityDays = 30
            case .all:
                let earliest = usageSessions.map(\.startedAt).min() ?? now
                activityDays = max(7, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: earliest), to: Calendar.current.startOfDay(for: now)).day.map { $0 + 1 } ?? 7)
            }
            let activity = usageService.activitySeries(sessions: usageSessions, now: now, days: activityDays)
            let snapshot = RelayWorkbenchSnapshot(
                allSessions: allSessions,
                sessions: filteredSessions,
                summaries: summaries,
                hiddenWorkspaces: storedWorkspaces.filter(\.isHidden),
                candidates: mergedCandidates,
                metrics: metrics,
                activity: activity,
                providerHealth: health,
                dataState: dataState,
                dataMessage: dataMessage
            )
            DispatchQueue.main.async {
                guard let self, self.refreshGeneration == generation else { return }
                self.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: RelayWorkbenchSnapshot) {
        allSessions = snapshot.allSessions
        sessions = snapshot.sessions
        summaries = snapshot.summaries
        hiddenWorkspaces = snapshot.hiddenWorkspaces
        candidates = snapshot.candidates
        metrics = snapshot.metrics
        activity = snapshot.activity
        providerHealth = snapshot.providerHealth

        if let selectedWorkspaceID, !summaries.contains(where: { $0.id == selectedWorkspaceID }) {
            self.selectedWorkspaceID = nil
            UserDefaults.standard.removeObject(forKey: DefaultsKey.workspace)
        }
        if mode == .today, !sessions.contains(where: { $0.id == selectedSessionID }) {
            selectedSessionID = sessions.first?.id
            UserDefaults.standard.set(selectedSessionID, forKey: DefaultsKey.session)
        }
        if mode == .playbook, !candidates.contains(where: { $0.id == selectedCandidateID }) {
            selectedCandidateID = candidates.first?.id
            UserDefaults.standard.set(selectedCandidateID, forKey: DefaultsKey.candidate)
        }
        if mode == .usage, !metrics.contains(where: { $0.id == selectedMetricID }) {
            selectedMetricID = metrics.first?.id
            UserDefaults.standard.set(selectedMetricID, forKey: DefaultsKey.metric)
        }

        navigationPane.update(mode: mode, summaries: summaries, hiddenWorkspaces: hiddenWorkspaces, sessions: allSessions, selectedWorkspaceID: selectedWorkspaceID, providerHealth: providerHealth)
        listPane.update(
            mode: mode,
            sessions: sessions,
            candidates: candidates,
            metrics: metrics,
            summaries: summaries,
            selectedSessionID: selectedSessionID,
            selectedCandidateID: selectedCandidateID,
            selectedMetricID: selectedMetricID,
            searchText: searchText,
            provider: providerFilter,
            status: statusFilter,
            sortOrder: sessionSortOrder,
            usageRange: usageTimeRange,
            compact: isCompactList,
            workspaceName: selectedWorkspaceName
        )
        if snapshot.dataState != "ready" {
            listPane.setTaskState(snapshot.dataState, message: snapshot.dataMessage)
        }
        updateInspector()
        if snapshot.dataState != "ready" {
            inspectorPane.setTaskState(snapshot.dataState)
        }
        updateInspectorVisibility()
    }

    private var selectedWorkspaceName: String? {
        guard let selectedWorkspaceID else { return nil }
        return summaries.first(where: { $0.id == selectedWorkspaceID })?.workspace.name
    }

    private func selectWorkspace(_ id: String?) {
        selectedWorkspaceID = id
        UserDefaults.standard.set(id, forKey: DefaultsKey.workspace)
        if let id { try? store.touchWorkspace(id: id) }
        selectedSessionID = nil
        selectedCandidateID = nil
        selectedMetricID = nil
        refreshData()
    }

    private func selectSession(_ id: String?) {
        selectedSessionID = id
        UserDefaults.standard.set(id, forKey: DefaultsKey.session)
        updateInspector()
    }

    private func selectCandidate(_ id: String?) {
        selectedCandidateID = id
        UserDefaults.standard.set(id, forKey: DefaultsKey.candidate)
        updateInspector()
    }

    private func selectMetric(_ id: String?) {
        selectedMetricID = id
        UserDefaults.standard.set(id, forKey: DefaultsKey.metric)
        updateInspector()
    }

    private func updateInspector() {
        switch mode {
        case .today:
            guard let session = sessions.first(where: { $0.id == selectedSessionID }) else {
                inspectorPane.showEmpty(title: "Select a session", message: "Choose a session to inspect its context, evidence, events, and recent transcript.")
                return
            }
            inspectorPane.showSession(
                session,
                message: inlineMessage,
                onResume: { [weak self] in self?.resume(session: session) },
                onReveal: { [weak self] in self?.reveal(session: session) },
                onTerminal: { [weak self] in self?.openTerminal(session: session) },
                onCopyPath: { [weak self] in self?.copyPath(session: session) }
            )
        case .playbook:
            guard let candidate = candidates.first(where: { $0.id == selectedCandidateID }) else {
                inspectorPane.showEmpty(title: "Select a candidate", message: "Relay keeps rationale, confidence, source sessions, evidence, target files, risk, and diff review together here.", symbol: "book.closed")
                return
            }
            inspectorPane.showCandidate(
                candidate,
                diff: pendingCandidateID == candidate.id ? pendingDiff : nil,
                targetPath: pendingCandidateID == candidate.id ? pendingTargetPath : nil,
                suggestion: pendingCandidateID == candidate.id ? pendingSuggestion : nil,
                message: inlineMessage,
                onPreview: { [weak self] in self?.preview(candidate: candidate) },
                onApply: { [weak self] in self?.applyPendingSuggestion() },
                onSnooze: { [weak self] in self?.updateCandidate(candidate, lifecycle: .snoozed) },
                onDismiss: { [weak self] in self?.updateCandidate(candidate, lifecycle: .dismissed) },
                onUndo: { [weak self] in self?.undoLastTransaction() }
            )
        case .usage:
            guard let metric = metrics.first(where: { $0.id == selectedMetricID }) ?? metrics.first else {
                inspectorPane.showEmpty(title: "Usage is waiting", message: "Derived activity will appear after Relay imports a session.", symbol: "chart.xyaxis.line")
                return
            }
            inspectorPane.showMetric(metric, activity: activity, message: inlineMessage)
        }
    }

    private func updateInspectorVisibility() {
        inspectorPane.isHidden = !isInspectorVisible
        if isInspectorVisible, inspectorPane.superview == nil {
            contentSplit.addArrangedSubview(inspectorPane)
            contentSplit.setPosition(max(RelayDesign.minimumListWidth, contentSplit.bounds.width - RelayDesign.inspectorWidth), ofDividerAt: 0)
        }
        if !isInspectorVisible {
            inspectorPane.removeFromSuperview()
        }
        listPane.setInspectorVisible(isInspectorVisible)
    }

    private func toggleInspector() {
        isInspectorVisible.toggle()
        UserDefaults.standard.set(isInspectorVisible, forKey: DefaultsKey.inspector)
        updateInspectorVisibility()
    }

    private func toggleDensity() {
        isCompactList.toggle()
        UserDefaults.standard.set(isCompactList, forKey: DefaultsKey.compact)
        listPane.setCompact(isCompactList)
    }

    private func refreshNow() {
        inlineMessage = ("Refreshing local ingestion…", RelayDesign.signal)
        updateInspector()
        let monitor = self.monitor
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = monitor.runOnce()
            DispatchQueue.main.async {
                self?.inlineMessage = ("Local data refreshed.", RelayDesign.success)
                self?.refreshData()
            }
        }
    }

    private func renameWorkspace(id: String) {
        guard let workspace = summaries.first(where: { $0.id == id })?.workspace else { return }
        let alert = NSAlert()
        alert.messageText = "Rename workspace"
        alert.informativeText = workspace.canonicalRepositoryPath ?? workspace.fallbackDirectory ?? "Workspace"
        let field = NSTextField(string: workspace.name)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var updated = workspace
        updated.name = name
        try? store.saveWorkspace(updated)
        refreshData()
    }

    private func togglePinWorkspace(id: String) {
        guard var workspace = summaries.first(where: { $0.id == id })?.workspace else { return }
        workspace.isPinned.toggle()
        try? store.saveWorkspace(workspace)
        refreshData()
    }

    private func hideWorkspace(id: String) {
        guard var workspace = summaries.first(where: { $0.id == id })?.workspace else { return }
        workspace.isHidden = true
        try? store.saveWorkspace(workspace)
        if selectedWorkspaceID == id { selectWorkspace(nil) } else { refreshData() }
    }

    private func unhideWorkspace(id: String) {
        guard var workspace = (try? store.workspaces(includeHidden: true))?.first(where: { $0.id == id }) else { return }
        workspace.isHidden = false
        try? store.saveWorkspace(workspace)
        inlineMessage = ("Restored workspace \(workspace.name).", RelayDesign.success)
        refreshData()
    }

    private func moveWorkspace(id: String, direction: Int) {
        let visible = summaries.filter { $0.workspace.id != RelayWorkspace.unassignedID }
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return }
        let target = index + direction
        guard visible.indices.contains(target) else { return }
        var current = visible[index].workspace
        var neighbor = visible[target].workspace
        swap(&current.sortOrder, &neighbor.sortOrder)
        try? store.saveWorkspace(current)
        try? store.saveWorkspace(neighbor)
        refreshData()
    }

    private func resume(session: Session) {
        do {
            try RelayActionService().resume(session: session)
            inlineMessage = ("Resume requested. Relay used tmux when available and Terminal as the fallback.", RelayDesign.success)
        } catch {
            inlineMessage = (error.localizedDescription, RelayDesign.destructive)
        }
        updateInspector()
    }

    private func reveal(session: Session) {
        guard let path = session.context.worktreePath ?? session.context.repositoryPath ?? session.context.workingDirectory else {
            inlineMessage = ("This session has no mapped repository or working directory.", RelayDesign.attention)
            updateInspector()
            return
        }
        do {
            try RelayActionService().reveal(path: path)
            inlineMessage = ("Revealed \(path) in Finder.", RelayDesign.success)
        } catch {
            inlineMessage = (error.localizedDescription, RelayDesign.destructive)
        }
        updateInspector()
    }

    private func openTerminal(session: Session) {
        guard let path = session.context.worktreePath ?? session.context.repositoryPath ?? session.context.workingDirectory else {
            inlineMessage = ("This session has no mapped working directory.", RelayDesign.attention)
            updateInspector()
            return
        }
        do {
            try RelayActionService().openTerminal(path: path)
            inlineMessage = ("Opened Terminal at \(path).", RelayDesign.success)
        } catch {
            inlineMessage = (error.localizedDescription, RelayDesign.destructive)
        }
        updateInspector()
    }

    private func copyPath(session: Session) {
        guard let path = session.context.worktreePath ?? session.context.repositoryPath ?? session.context.workingDirectory else {
            inlineMessage = ("This session has no mapped path to copy.", RelayDesign.attention)
            updateInspector()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        inlineMessage = ("Copied \(path).", RelayDesign.success)
        updateInspector()
    }

    private func preview(candidate: IntelligenceCandidate) {
        let panel = NSOpenPanel()
        panel.title = "Choose a Playbook file"
        panel.message = "Select the exact file Relay may modify. The path will be confirmed again before writing."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let targetURL = panel.url else { return }

        let currentContent = try? String(contentsOf: targetURL, encoding: .utf8)
        let proposedContent = makeProposedContent(candidate: candidate, current: currentContent)
        let suggestion = playbookEngine.makeSuggestion(
            for: candidate,
            targetURL: targetURL,
            proposedContent: proposedContent,
            currentContent: currentContent
        )
        pendingCandidateID = candidate.id
        pendingSuggestion = suggestion
        pendingTargetPath = targetURL.path
        pendingDiff = diff(current: currentContent ?? "", proposed: proposedContent)
        inlineMessage = ("Preview ready. Nothing has changed on disk.", RelayDesign.signal)
        updateInspector()
    }

    private func applyPendingSuggestion() {
        guard let suggestion = pendingSuggestion, let targetPath = pendingTargetPath else {
            inlineMessage = ("Preview the exact target file before applying this candidate.", RelayDesign.attention)
            updateInspector()
            return
        }
        let confirmation = NSAlert()
        confirmation.alertStyle = suggestion.risk == .high ? .critical : .warning
        confirmation.messageText = "Apply this Playbook change?"
        confirmation.informativeText = "Relay will write the reviewed diff to the exact path:\n\(targetPath)"
        confirmation.addButton(withTitle: "Apply Change")
        confirmation.addButton(withTitle: "Cancel")
        guard let window = view.window else {
            guard confirmation.runModal() == .alertFirstButtonReturn else { return }
            commitPendingSuggestion(suggestion: suggestion, targetPath: targetPath)
            return
        }
        confirmation.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor [weak self] in
                self?.commitPendingSuggestion(suggestion: suggestion, targetPath: targetPath)
            }
        }
    }

    private func commitPendingSuggestion(suggestion: Suggestion, targetPath: String) {
        do {
            let record = try transactionManager.apply(suggestion, grant: PathGrant(paths: [targetPath]))
            try store.record(transaction: record)
            try store.record(auditEvent: AuditEvent(
                action: "apply-suggestion",
                entityID: suggestion.id,
                processingMode: "offline",
                detail: "Applied an explicitly approved Playbook transaction to \(targetPath)."
            ))
            lastTransaction = record
            if let candidate = candidates.first(where: { $0.id == suggestion.candidateID }) {
                updateCandidate(candidate, lifecycle: .applied)
            }
            inlineMessage = ("Applied the guarded change and recorded an undo snapshot.", RelayDesign.success)
            pendingSuggestion = nil
            pendingCandidateID = nil
            pendingTargetPath = nil
            pendingDiff = nil
        } catch {
            inlineMessage = (error.localizedDescription, RelayDesign.destructive)
        }
        updateInspector()
    }

    private func updateCandidate(_ candidate: IntelligenceCandidate, lifecycle: CandidateLifecycle) {
        var updated = candidate
        updated.lifecycle = lifecycle
        do {
            try store.saveCandidate(updated)
            candidates = candidates.map { $0.id == updated.id ? updated : $0 }
            inlineMessage = ("Candidate marked \(lifecycle.rawValue).", RelayDesign.success)
            updateInspector()
            listPane.update(
                mode: mode,
                sessions: sessions,
                candidates: candidates,
                metrics: metrics,
                summaries: summaries,
                selectedSessionID: selectedSessionID,
                selectedCandidateID: selectedCandidateID,
                selectedMetricID: selectedMetricID,
                searchText: searchText,
                provider: providerFilter,
                status: statusFilter,
                sortOrder: sessionSortOrder,
                usageRange: usageTimeRange,
                compact: isCompactList,
                workspaceName: selectedWorkspaceName
            )
        } catch {
            inlineMessage = (error.localizedDescription, RelayDesign.destructive)
            updateInspector()
        }
    }

    private func undoLastTransaction() {
        guard let transaction = lastTransaction else {
            inlineMessage = ("There is no recent guarded change to undo.", RelayDesign.attention)
            updateInspector()
            return
        }
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
            if let candidate = candidates.first(where: { $0.id == transaction.suggestionID }) {
                updateCandidate(candidate, lifecycle: .undone)
            }
            inlineMessage = ("Restored the guarded undo snapshot.", RelayDesign.success)
        } catch {
            inlineMessage = (error.localizedDescription, RelayDesign.destructive)
        }
        updateInspector()
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

    private func dismissCommandPalette() {
        commandPalette.isHidden = true
        rootView.window?.makeFirstResponder(listPane.searchField)
    }

    private func makeCommands() -> [RelayCommand] {
        var commands: [RelayCommand] = []
        commands.append(contentsOf: RelayDestination.allCases.map { destination in
            RelayCommand(
                id: "mode-\(destination.title)",
                title: "Switch to \(destination.title)",
                detail: "⌘\(destination == .today ? "1" : destination == .playbook ? "2" : "3")",
                symbol: destination.symbol,
                perform: { [weak self] in self?.show(destination: destination) }
            )
        })
        commands.append(RelayCommand(id: "focus-search", title: "Focus search", detail: "", symbol: "magnifyingglass", perform: { [weak self] in
            self?.dismissCommandPalette()
            self?.listPane.focusSearch()
        }))
        commands.append(RelayCommand(id: "refresh", title: "Refresh ingestion", detail: "⌘R", symbol: "arrow.clockwise", perform: { [weak self] in self?.refreshNow() }))
        commands.append(RelayCommand(id: "toggle-inspector", title: "Toggle inspector", detail: "⌘I", symbol: "sidebar.right", perform: { [weak self] in self?.toggleInspector() }))
        for summary in summaries where summary.workspace.id != RelayWorkspace.unassignedID {
            commands.append(RelayCommand(
                id: "workspace-\(summary.id)",
                title: "Switch to workspace \(summary.workspace.name)",
                detail: "\(summary.sessionCount) sessions",
                symbol: "folder",
                perform: { [weak self] in self?.selectWorkspace(summary.id) }
            ))
        }
        commands.append(RelayCommand(id: "workspace-all", title: "Show all workspaces", detail: "", symbol: "square.grid.2x2", perform: { [weak self] in self?.selectWorkspace(nil) }))
        for provider in ProviderID.allCases {
            commands.append(RelayCommand(id: "provider-\(provider.rawValue)", title: "Filter provider: \(provider.rawValue)", detail: "", symbol: "cpu", perform: { [weak self] in
                self?.providerFilter = provider
                UserDefaults.standard.set(provider.rawValue, forKey: DefaultsKey.provider)
                self?.listPane.setProvider(provider)
                self?.refreshData()
            }))
        }
        commands.append(RelayCommand(id: "provider-all", title: "Clear provider filter", detail: "", symbol: "line.3.horizontal.decrease.circle", perform: { [weak self] in
            self?.providerFilter = nil
            UserDefaults.standard.removeObject(forKey: DefaultsKey.provider)
            self?.listPane.setProvider(nil)
            self?.refreshData()
        }))
        for status in AgentStatus.allCases {
            commands.append(RelayCommand(id: "status-\(status.rawValue)", title: "Filter status: \(status.displayName)", detail: "", symbol: "circle.fill", perform: { [weak self] in
                self?.statusFilter = status
                UserDefaults.standard.set(status.rawValue, forKey: DefaultsKey.status)
                self?.listPane.setStatus(status)
                self?.refreshData()
            }))
        }
        commands.append(RelayCommand(id: "status-all", title: "Clear status filter", detail: "", symbol: "line.3.horizontal.decrease.circle", perform: { [weak self] in
            self?.statusFilter = nil
            UserDefaults.standard.removeObject(forKey: DefaultsKey.status)
            self?.listPane.setStatus(nil)
            self?.refreshData()
        }))
        if let session = sessions.first(where: { $0.id == selectedSessionID }) {
            commands.append(RelayCommand(id: "resume", title: "Resume \(session.title)", detail: "", symbol: "play.fill", perform: { [weak self] in self?.resume(session: session) }))
            commands.append(RelayCommand(id: "reveal", title: "Reveal session context", detail: "", symbol: "folder", perform: { [weak self] in self?.reveal(session: session) }))
        }
        if let candidate = candidates.first(where: { $0.id == selectedCandidateID }) {
            commands.append(RelayCommand(id: "preview", title: "Preview selected Playbook candidate", detail: "", symbol: "eye", perform: { [weak self] in self?.preview(candidate: candidate) }))
            commands.append(RelayCommand(id: "apply", title: "Apply selected Playbook candidate", detail: "", symbol: "checkmark", perform: { [weak self] in self?.applyPendingSuggestion() }))
            commands.append(RelayCommand(id: "snooze", title: "Snooze selected Playbook candidate", detail: "", symbol: "moon.zzz", perform: { [weak self] in self?.updateCandidate(candidate, lifecycle: .snoozed) }))
            commands.append(RelayCommand(id: "dismiss", title: "Dismiss selected Playbook candidate", detail: "", symbol: "xmark", perform: { [weak self] in self?.updateCandidate(candidate, lifecycle: .dismissed) }))
            commands.append(RelayCommand(id: "undo", title: "Undo last Playbook change", detail: "", symbol: "arrow.uturn.backward", perform: { [weak self] in self?.undoLastTransaction() }))
        }
        return commands
    }
}

@MainActor
private final class RelayNavigationPaneView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onSelectWorkspace: ((String?) -> Void)?
    var onSelectMode: ((RelayDestination) -> Void)?
    var onRenameWorkspace: ((String) -> Void)?
    var onTogglePinWorkspace: ((String) -> Void)?
    var onHideWorkspace: ((String) -> Void)?
    var onUnhideWorkspace: ((String) -> Void)?
    var onMoveWorkspace: ((String, Int) -> Void)?

    private let modeStack = NSStackView()
    private let tableView = RelayWorkspaceTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let providerStack = NSStackView()
    private var buttons: [RelayDestination: NSButton] = [:]
    private var summaries: [WorkspaceSummary] = []
    private var hiddenWorkspaces: [RelayWorkspace] = []
    private var selectedWorkspaceID: String?
    private var rows: [WorkspaceSummary?] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.66).cgColor
        buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(mode: RelayDestination, summaries: [WorkspaceSummary], hiddenWorkspaces: [RelayWorkspace], sessions: [Session], selectedWorkspaceID: String?, providerHealth: [ProviderHealth]) {
        self.summaries = summaries
        self.hiddenWorkspaces = hiddenWorkspaces
        rows = [nil] + summaries
        self.selectedWorkspaceID = selectedWorkspaceID
        buttons.forEach { $0.value.state = $0.key == mode ? .on : .off }
        tableView.reloadData()
        let row = rows.firstIndex(where: { $0?.id == selectedWorkspaceID }) ?? 0
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        let active = sessions.filter { [.running, .waiting, .approvalRequired].contains($0.status) }.count
        let attention = sessions.filter { [.waiting, .approvalRequired].contains($0.status) }.count
        statusLabel.stringValue = "\(active) active  ·  \(attention) attention"
        providerStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for health in providerHealth {
            let symbol = health.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle"
            let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: health.message) ?? NSImage())
            image.contentTintColor = health.isAvailable ? RelayDesign.success : RelayDesign.attention
            let label = relayLabel(health.provider.rawValue, size: 11, color: .secondaryLabelColor)
            let row = NSStackView(views: [image, label])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            providerStack.addArrangedSubview(row)
            NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: 13), image.heightAnchor.constraint(equalToConstant: 13)])
        }
    }

    private func buildView() {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .sidebar
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffect)

        let identity = relayLabel("RELAY", size: 13, weight: .bold, color: .secondaryLabelColor)
        let subtitle = relayLabel("Local-first agent workbench", size: 12, color: .tertiaryLabelColor)
        let identityStack = NSStackView(views: [identity, subtitle])
        identityStack.orientation = .vertical
        identityStack.alignment = .leading
        identityStack.spacing = 3

        modeStack.orientation = .vertical
        modeStack.alignment = .width
        modeStack.spacing = 3
        for destination in RelayDestination.allCases {
            let button = NSButton(title: destination.title, target: self, action: #selector(selectMode(_:)))
            button.image = NSImage(systemSymbolName: destination.symbol, accessibilityDescription: destination.title)
            button.imagePosition = .imageLeading
            button.alignment = .left
            button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            button.bezelStyle = .texturedRounded
            button.isBordered = false
            button.setButtonType(.pushOnPushOff)
            button.contentTintColor = .labelColor
            button.identifier = NSUserInterfaceItemIdentifier(destination.title.lowercased())
            button.state = destination == .today ? .on : .off
            button.translatesAutoresizingMaskIntoConstraints = false
            modeStack.addArrangedSubview(button)
            buttons[destination] = button
        }

        let workspaceHeader = relaySectionHeader("Workspaces")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("workspace"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.style = .sourceList
        tableView.rowSizeStyle = .medium
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.onContextMenu = { [weak self] event in self?.workspaceMenu(for: event) }
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        providerStack.orientation = .vertical
        providerStack.alignment = .leading
        providerStack.spacing = 5

        let bottom = NSStackView(views: [statusLabel, providerStack])
        bottom.orientation = .vertical
        bottom.alignment = .leading
        bottom.spacing = 9

        let stack = NSStackView(views: [identityStack, modeStack, workspaceHeader, scroll, NSView(), bottom])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(stack)
        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -16),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            modeStack.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    @objc private func selectMode(_ sender: NSButton) {
        guard let value = sender.identifier?.rawValue,
              let destination = RelayDestination.allCases.first(where: { $0.title.lowercased() == value }) else { return }
        onSelectMode?(destination)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = RelayWorkspaceCellView()
        if let summary = rows[row] {
            cell.configure(summary: summary, selected: summary.id == selectedWorkspaceID)
        } else {
            cell.configureAll(selected: selectedWorkspaceID == nil)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { RelayTableRowView() }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard rows.indices.contains(row) else { return }
        let id = rows[row]?.id
        selectedWorkspaceID = id
        onSelectWorkspace?(id)
    }

    private func workspaceMenu(for event: NSEvent) -> NSMenu? {
        let row = tableView.row(at: tableView.convert(event.locationInWindow, from: nil))
        guard rows.indices.contains(row) else { return nil }
        if row == 0 {
            guard !hiddenWorkspaces.isEmpty else { return nil }
            let menu = NSMenu()
            let restore = NSMenuItem(title: "Restore Hidden Workspace", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for workspace in hiddenWorkspaces {
                let item = NSMenuItem(title: workspace.name, action: #selector(unhideWorkspace(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = workspace.id
                submenu.addItem(item)
            }
            restore.submenu = submenu
            menu.addItem(restore)
            return menu
        }
        guard let summary = rows[row] else { return nil }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        let menu = NSMenu()
        let rename = NSMenuItem(title: "Rename…", action: #selector(renameWorkspace(_:)), keyEquivalent: "")
        rename.target = self
        rename.representedObject = summary.id
        menu.addItem(rename)
        let pin = NSMenuItem(title: summary.workspace.isPinned ? "Unpin" : "Pin", action: #selector(togglePin(_:)), keyEquivalent: "")
        pin.target = self
        pin.representedObject = summary.id
        menu.addItem(pin)
        let up = NSMenuItem(title: "Move Up", action: #selector(moveWorkspaceUp(_:)), keyEquivalent: "")
        up.target = self
        up.representedObject = summary.id
        menu.addItem(up)
        let down = NSMenuItem(title: "Move Down", action: #selector(moveWorkspaceDown(_:)), keyEquivalent: "")
        down.target = self
        down.representedObject = summary.id
        menu.addItem(down)
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide Workspace", action: #selector(hideWorkspace(_:)), keyEquivalent: "")
        hide.target = self
        hide.representedObject = summary.id
        menu.addItem(hide)
        return menu
    }

    @objc private func renameWorkspace(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onRenameWorkspace?(id) } }
    @objc private func togglePin(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onTogglePinWorkspace?(id) } }
    @objc private func moveWorkspaceUp(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onMoveWorkspace?(id, -1) } }
    @objc private func moveWorkspaceDown(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onMoveWorkspace?(id, 1) } }
    @objc private func hideWorkspace(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onHideWorkspace?(id) } }
    @objc private func unhideWorkspace(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onUnhideWorkspace?(id) } }
}

@MainActor
private final class RelayWorkspaceTableView: NSTableView {
    var onContextMenu: ((NSEvent) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        onContextMenu?(event)
    }
}

@MainActor
private final class RelayWorkspaceCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let attentionLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        detailLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        attentionLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        attentionLabel.textColor = RelayDesign.attention
        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        addSubview(labels)
        attentionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(attentionLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            labels.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: attentionLabel.leadingAnchor, constant: -5),
            attentionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            attentionLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(summary: WorkspaceSummary, selected: Bool) {
        iconView.image = NSImage(systemSymbolName: summary.workspace.isPinned ? "pin.fill" : "folder", accessibilityDescription: "Workspace")
        iconView.contentTintColor = selected ? RelayDesign.signal : .secondaryLabelColor
        titleLabel.stringValue = summary.workspace.name
        detailLabel.stringValue = "\(summary.sessionCount) sessions · \(summary.activeCount) active"
        attentionLabel.stringValue = summary.attentionCount > 0 ? "\(summary.attentionCount)" : ""
        setAccessibilityLabel("Workspace \(summary.workspace.name), \(summary.sessionCount) sessions")
    }

    func configureAll(selected: Bool) {
        iconView.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "All workspaces")
        iconView.contentTintColor = selected ? RelayDesign.signal : .secondaryLabelColor
        titleLabel.stringValue = "All workspaces"
        detailLabel.stringValue = "Local session index"
        attentionLabel.stringValue = ""
        setAccessibilityLabel("All workspaces")
    }
}

@MainActor
private final class RelayListPaneView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private enum Row {
        case section(String, String?)
        case session(Session)
        case candidate(IntelligenceCandidate)
        case metric(UsageMetric)

        var id: String? {
            switch self {
            case .section: return nil
            case .session(let value): return value.id
            case .candidate(let value): return value.id
            case .metric(let value): return value.id
            }
        }
    }

    var onSelectSession: ((String?) -> Void)?
    var onSelectCandidate: ((String?) -> Void)?
    var onSelectMetric: ((String?) -> Void)?
    var onSearchChanged: ((String) -> Void)?
    var onProviderChanged: ((ProviderID?) -> Void)?
    var onStatusChanged: ((AgentStatus?) -> Void)?
    var onSortChanged: ((SessionSortOrder) -> Void)?
    var onUsageRangeChanged: ((UsageTimeRange) -> Void)?
    var onRefresh: (() -> Void)?
    var onToggleInspector: (() -> Void)?
    var onToggleDensity: (() -> Void)?

    let searchField = NSSearchField()
    private let modeLabel = NSTextField(labelWithString: "Today")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let scopeLabel = NSTextField(labelWithString: "")
    private let taskStateLabel = NSTextField(labelWithString: "")
    private let providerPopup = NSPopUpButton()
    private let statusPopup = NSPopUpButton()
    private let sortPopup = NSPopUpButton()
    private let usageRangePopup = NSPopUpButton()
    private let tableView = NSTableView()
    private var rows: [Row] = []
    private var mode: RelayDestination = .today
    private var compact = false
    private var selectedID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        mode: RelayDestination,
        sessions: [Session],
        candidates: [IntelligenceCandidate],
        metrics: [UsageMetric],
        summaries: [WorkspaceSummary],
        selectedSessionID: String?,
        selectedCandidateID: String?,
        selectedMetricID: String?,
        searchText: String,
        provider: ProviderID?,
        status: AgentStatus?,
        sortOrder: SessionSortOrder,
        usageRange: UsageTimeRange,
        compact: Bool,
        workspaceName: String?
    ) {
        self.mode = mode
        self.compact = compact
        selectedID = mode == .today ? selectedSessionID : (mode == .playbook ? selectedCandidateID : selectedMetricID)
        modeLabel.stringValue = mode.title
        subtitleLabel.stringValue = mode.subtitle
        scopeLabel.stringValue = workspaceName.map { "Workspace: \($0)" } ?? (mode == .usage ? "Workspace: All workspaces" : "All workspaces")
        searchField.stringValue = searchText
        configurePopups(provider: provider, status: status, sortOrder: sortOrder, usageRange: usageRange)
        switch mode {
        case .today: rows = makeSessionRows(sessions: sessions, summaries: summaries, sortOrder: sortOrder)
        case .playbook: rows = makeCandidateRows(candidates)
        case .usage: rows = makeMetricRows(metrics)
        }
        tableView.reloadData()
        let resultCount = rows.compactMap(\.id).count
        setTaskState(resultCount == 0 ? "no_results" : "results_ready")
        if let selectedID, let row = rows.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else if let first = rows.firstIndex(where: { $0.id != nil }) {
            tableView.selectRowIndexes(IndexSet(integer: first), byExtendingSelection: false)
        }
    }

    func setMode(_ mode: RelayDestination) { self.mode = mode }
    func setInspectorVisible(_ visible: Bool) { }
    func setCompact(_ compact: Bool) { self.compact = compact; tableView.reloadData() }
    func setProvider(_ provider: ProviderID?) { configureProviderPopup(provider: provider) }
    func setStatus(_ status: AgentStatus?) { configureStatusPopup(status: status) }
    func focusSearch() { window?.makeFirstResponder(searchField) }

    func setTaskState(_ state: String, message: String? = nil) {
        let resultCount = rows.compactMap(\.id).count
        setAccessibilityValue(state)
        setAccessibilityHelp("task-state=\(state); result-count=\(resultCount)")
        tableView.setAccessibilityHelp("task-state=\(state); result-count=\(resultCount)")
        taskStateLabel.stringValue = message ?? {
            switch state {
            case "loading": return "Loading Relay data…"
            case "no_results": return "No matching results"
            case "data_unavailable": return "Relay data is unavailable"
            default: return ""
            }
        }()
        taskStateLabel.isHidden = taskStateLabel.stringValue.isEmpty
        taskStateLabel.textColor = state == "data_unavailable" ? RelayDesign.destructive : .secondaryLabelColor
    }

    private func buildView() {
        modeLabel.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        subtitleLabel.font = NSFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        scopeLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        scopeLabel.textColor = RelayDesign.signal
        taskStateLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        taskStateLabel.identifier = NSUserInterfaceItemIdentifier("relay.search.state")
        taskStateLabel.setAccessibilityLabel("Relay search state")
        taskStateLabel.isHidden = true

        searchField.placeholderString = "Search sessions, repositories, branches, or evidence"
        searchField.identifier = NSUserInterfaceItemIdentifier("relay.search.input")
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.setAccessibilityLabel("Search Relay")
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configurePopups(provider: nil, status: nil, sortOrder: .recent, usageRange: .sevenDays)
        let refresh = relayToolbarButton(symbol: "arrow.clockwise", label: "Refresh ingestion", target: self, action: #selector(refreshClicked))
        let inspector = relayToolbarButton(symbol: "sidebar.right", label: "Toggle inspector", target: self, action: #selector(inspectorClicked))
        let density = relayToolbarButton(symbol: "text.justify", label: "Toggle list density", target: self, action: #selector(densityClicked))
        let searchRow = NSStackView(views: [searchField, NSView(), density, inspector, refresh])
        searchRow.orientation = .horizontal
        searchRow.alignment = .centerY
        searchRow.spacing = 7
        searchRow.translatesAutoresizingMaskIntoConstraints = false

        let filterRow = NSStackView(views: [providerPopup, statusPopup, sortPopup, usageRangePopup, NSView()])
        filterRow.orientation = .horizontal
        filterRow.alignment = .centerY
        filterRow.spacing = 7
        filterRow.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSStackView(views: [modeLabel, subtitleLabel, scopeLabel, taskStateLabel])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 4

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("relay.list"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.style = .sourceList
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.rowSizeStyle = .medium
        tableView.identifier = NSUserInterfaceItemIdentifier("relay.search.results")
        tableView.setAccessibilityLabel("Relay items")
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [heading, searchRow, filterRow, relayDivider(), scroll])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            searchRow.heightAnchor.constraint(equalToConstant: 30),
            filterRow.heightAnchor.constraint(equalToConstant: 30),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            providerPopup.widthAnchor.constraint(equalToConstant: 84),
            statusPopup.widthAnchor.constraint(equalToConstant: 92),
            sortPopup.widthAnchor.constraint(equalToConstant: 72),
            usageRangePopup.widthAnchor.constraint(equalToConstant: 82)
        ])
    }

    private func configurePopups(provider: ProviderID?, status: AgentStatus?, sortOrder: SessionSortOrder, usageRange: UsageTimeRange) {
        configureProviderPopup(provider: provider)
        configureStatusPopup(status: status)
        configureSortPopup(sortOrder: sortOrder)
        usageRangePopup.removeAllItems()
        usageRangePopup.addItems(withTitles: UsageTimeRange.allCases.map(\.displayName))
        usageRangePopup.selectItem(at: UsageTimeRange.allCases.firstIndex(of: usageRange) ?? 1)
        usageRangePopup.target = self
        usageRangePopup.action = #selector(usageRangeChanged(_:))
        usageRangePopup.isHidden = mode != .usage
        sortPopup.isHidden = mode != .today
    }

    private func configureProviderPopup(provider: ProviderID?) {
        providerPopup.removeAllItems()
        providerPopup.addItem(withTitle: "All providers")
        providerPopup.lastItem?.representedObject = "all"
        for value in ProviderID.allCases {
            providerPopup.addItem(withTitle: value.rawValue)
            providerPopup.lastItem?.representedObject = value.rawValue
        }
        let index = provider.flatMap { value in ProviderID.allCases.firstIndex(of: value).map { $0 + 1 } } ?? 0
        providerPopup.selectItem(at: index)
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged(_:))
    }

    private func configureStatusPopup(status: AgentStatus?) {
        statusPopup.removeAllItems()
        statusPopup.addItem(withTitle: "All statuses")
        statusPopup.lastItem?.representedObject = "all"
        for value in AgentStatus.allCases {
            statusPopup.addItem(withTitle: value.displayName)
            statusPopup.lastItem?.representedObject = value.rawValue
        }
        let index = status.flatMap { value in AgentStatus.allCases.firstIndex(of: value).map { $0 + 1 } } ?? 0
        statusPopup.selectItem(at: index)
        statusPopup.target = self
        statusPopup.action = #selector(statusChanged(_:))
    }

    private func configureSortPopup(sortOrder: SessionSortOrder) {
        sortPopup.removeAllItems()
        sortPopup.addItems(withTitles: ["Recent", "Oldest", "Title"])
        sortPopup.selectItem(at: SessionSortOrder.allCases.firstIndex(of: sortOrder) ?? 0)
        sortPopup.target = self
        sortPopup.action = #selector(sortChanged(_:))
    }

    private func makeSessionRows(sessions: [Session], summaries: [WorkspaceSummary], sortOrder: SessionSortOrder) -> [Row] {
        let summaryByID = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0) })
        let grouped = Dictionary(grouping: sessions, by: resolverID)
        var result: [Row] = []
        let statusOrder: [AgentStatus] = [.approvalRequired, .waiting, .running, .discovered, .idle, .completed, .failed, .abandoned, .unknown]
        let ordered = grouped.keys.sorted { left, right in
            let leftPriority = grouped[left]?.compactMap { statusOrder.firstIndex(of: $0.status) }.min() ?? statusOrder.count
            let rightPriority = grouped[right]?.compactMap { statusOrder.firstIndex(of: $0.status) }.min() ?? statusOrder.count
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            let leftDate = grouped[left]?.map(\.lastActivityAt).max() ?? .distantPast
            let rightDate = grouped[right]?.map(\.lastActivityAt).max() ?? .distantPast
            return leftDate > rightDate
        }
        for id in ordered {
            let group = grouped[id] ?? []
            let name = id == RelayWorkspace.unassignedID ? "Unassigned" : (summaryByID[id]?.workspace.name ?? "Workspace")
            result.append(.section(name, "\(group.count) sessions"))
            for status in statusOrder {
                let statusSessions = group.filter { $0.status == status }
                guard !statusSessions.isEmpty else { continue }
                result.append(.section(status.displayName, nil))
                let orderedSessions = statusSessions.sorted {
                    switch sortOrder {
                    case .recent: return $0.lastActivityAt > $1.lastActivityAt
                    case .oldest: return $0.lastActivityAt < $1.lastActivityAt
                    case .title: return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                }
                result.append(contentsOf: orderedSessions.map(Row.session))
            }
        }
        return result
    }

    private func makeCandidateRows(_ candidates: [IntelligenceCandidate]) -> [Row] {
        let order: [CandidateLifecycle] = [.pending, .reviewed, .applied, .snoozed, .dismissed, .undone]
        return order.flatMap { lifecycle -> [Row] in
            let group = candidates.filter { $0.lifecycle == lifecycle }
            guard !group.isEmpty else { return [] }
            return [.section(lifecycle.rawValue.capitalized, "\(group.count) candidate\(group.count == 1 ? "" : "s")")] + group.sorted { $0.confidence > $1.confidence }.map(Row.candidate)
        }
    }

    private func makeMetricRows(_ metrics: [UsageMetric]) -> [Row] {
        guard !metrics.isEmpty else { return [] }
        return [.section("Local usage", "\(metrics.count) metrics")] + metrics.map(Row.metric)
    }

    private func resolverID(_ session: Session) -> String { WorkspaceResolver().workspaceID(for: session) }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .section = rows[row] { return 28 }
        return compact ? RelayDesign.compactRowHeight : RelayDesign.rowHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { RelayTableRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .section(let title, let detail):
            let cell = RelaySectionCellView()
            cell.configure(title: title, detail: detail)
            return cell
        case .session(let session):
            let cell = RelaySessionCellView()
            cell.configure(session: session, compact: compact)
            return cell
        case .candidate(let candidate):
            let cell = RelayCandidateCellView()
            cell.configure(candidate: candidate, compact: compact)
            return cell
        case .metric(let metric):
            let cell = RelayMetricCellView()
            cell.configure(metric: metric, compact: compact)
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard rows.indices.contains(row), let id = rows[row].id else { return }
        selectedID = id
        switch rows[row] {
        case .session: onSelectSession?(id)
        case .candidate: onSelectCandidate?(id)
        case .metric: onSelectMetric?(id)
        case .section: break
        }
    }

    func controlTextDidChange(_ obj: Notification) { onSearchChanged?(searchField.stringValue) }

    @objc private func providerChanged(_ sender: NSPopUpButton) {
        let raw = sender.selectedItem?.representedObject as? String
        onProviderChanged?(raw.flatMap(ProviderID.init(rawValue:)))
    }

    @objc private func statusChanged(_ sender: NSPopUpButton) {
        let raw = sender.selectedItem?.representedObject as? String
        onStatusChanged?(raw.flatMap(AgentStatus.init(rawValue:)))
    }

    @objc private func sortChanged(_ sender: NSPopUpButton) {
        onSortChanged?(SessionSortOrder.allCases[safe: sender.indexOfSelectedItem] ?? .recent)
    }

    @objc private func usageRangeChanged(_ sender: NSPopUpButton) {
        let range = UsageTimeRange.allCases[safe: sender.indexOfSelectedItem] ?? .sevenDays
        onUsageRangeChanged?(range)
    }

    @objc private func refreshClicked() { onRefresh?() }
    @objc private func inspectorClicked() { onToggleInspector?() }
    @objc private func densityClicked() { onToggleDensity?() }
}

@MainActor
private final class RelaySectionCellView: NSTableCellView {
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        title.textColor = .secondaryLabelColor
        detail.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        detail.textColor = .tertiaryLabelColor
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, detail: String?) {
        self.title.stringValue = title.uppercased()
        self.detail.stringValue = detail ?? ""
    }
}

@MainActor
private final class RelaySessionCellView: NSTableCellView {
    private let title = NSTextField(labelWithString: "")
    private let meta = NSTextField(labelWithString: "")
    private let path = NSTextField(labelWithString: "")
    private let badgeContainer = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        meta.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        meta.textColor = .secondaryLabelColor
        path.font = NSFont.systemFont(ofSize: 11)
        path.textColor = .tertiaryLabelColor
        path.lineBreakMode = .byTruncatingMiddle
        let labels = NSStackView(views: [title, meta, path])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labels)
        addSubview(badgeContainer)
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: badgeContainer.leadingAnchor, constant: -10),
            badgeContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            badgeContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 90)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(session: Session, compact: Bool) {
        title.stringValue = session.title
        meta.stringValue = "\(session.provider.rawValue) · \(RelativeDateTimeFormatter().localizedString(for: session.lastActivityAt, relativeTo: Date()))"
        path.stringValue = session.context.worktreePath ?? session.context.repositoryPath ?? session.context.workingDirectory ?? "Repository context unavailable"
        path.isHidden = compact
        badgeContainer.subviews.forEach { $0.removeFromSuperview() }
        let badge = RelayStatusBadge(status: session.status)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: badgeContainer.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor)
        ])
        setAccessibilityLabel("\(session.title), \(session.status.displayName)")
        identifier = NSUserInterfaceItemIdentifier("relay.search.result.\(session.id)")
        setAccessibilityHelp("result-id=\(session.id); action=select")
    }
}

@MainActor
private final class RelayCandidateCellView: NSTableCellView {
    private let title = NSTextField(labelWithString: "")
    private let meta = NSTextField(labelWithString: "")
    private let badgeContainer = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        meta.font = NSFont.systemFont(ofSize: 11)
        meta.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [title, meta])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labels)
        addSubview(badgeContainer)
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: badgeContainer.leadingAnchor, constant: -10),
            badgeContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            badgeContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 82)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(candidate: IntelligenceCandidate, compact: Bool) {
        title.stringValue = candidate.title
        meta.stringValue = "\(candidate.lane.rawValue.replacingOccurrences(of: "_", with: " ")) · \(candidate.evidence.count) evidence · confidence \(Int(candidate.confidence * 100))%"
        badgeContainer.subviews.forEach { $0.removeFromSuperview() }
        let badge = RelayStatusBadge(text: candidate.lifecycle.rawValue.capitalized, color: RelayDesign.lifecycleColor(candidate.lifecycle))
        badge.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: badgeContainer.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor)
        ])
        setAccessibilityLabel("\(candidate.title), \(candidate.lifecycle.rawValue)")
        identifier = NSUserInterfaceItemIdentifier("relay.search.result.\(candidate.id)")
        setAccessibilityHelp("result-id=\(candidate.id); action=select")
    }
}

@MainActor
private final class RelayMetricCellView: NSTableCellView {
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        detail.font = NSFont.systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        value.font = NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        value.alignment = .right
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false
        value.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labels)
        addSubview(value)
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: value.leadingAnchor, constant: -10),
            value.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            value.centerYAnchor.constraint(equalTo: centerYAnchor),
            value.widthAnchor.constraint(greaterThanOrEqualToConstant: 74)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(metric: UsageMetric, compact: Bool) {
        title.stringValue = metric.label
        detail.stringValue = "\(metric.precision.rawValue) · \(metric.unit.isEmpty ? metric.source : metric.unit)"
        value.stringValue = metricValue(metric)
        setAccessibilityLabel("\(metric.label), \(value.stringValue)")
        identifier = NSUserInterfaceItemIdentifier("relay.search.result.\(metric.id)")
        setAccessibilityHelp("result-id=\(metric.id); action=select")
    }

    private func metricValue(_ metric: UsageMetric) -> String {
        if metric.unit == "availability" { return metric.value == nil ? "Unavailable" : "Available" }
        guard let value = metric.value else { return "—" }
        if metric.unit == "seconds" {
            return value < 60 ? "\(Int(value))s" : "\(Int(value / 60))m"
        }
        return value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

@MainActor
private final class RelayInspectorPaneView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Inspector")
    private let stack = NSStackView()
    private let scrollView = NSScrollView()
    private var actionTargets: [ClosureTarget] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("relay.result.details")
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Result details")
        buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showEmpty(title: String, message: String, symbol: String = "cursorarrow.click.2") {
        clear(title: "Inspector")
        setTaskState("empty")
        let empty = RelayEmptyStateView(title: title, message: message, symbol: symbol)
        stack.addArrangedSubview(empty)
        empty.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
    }

    func showSession(
        _ session: Session,
        message: (text: String, tone: NSColor)?,
        onResume: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onTerminal: @escaping () -> Void,
        onCopyPath: @escaping () -> Void
    ) {
        clear(title: session.title)
        setTaskState("details_ready")
        addBadgeRow(status: session.status, provider: session.provider)
        if let message { stack.addArrangedSubview(RelayInlineBanner(message: message.text, tone: message.tone)) }
        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 7
        let resumeTarget = ClosureTarget(onResume)
        let revealTarget = ClosureTarget(onReveal)
        let terminalTarget = ClosureTarget(onTerminal)
        let copyTarget = ClosureTarget(onCopyPath)
        actionTargets = [resumeTarget, revealTarget, terminalTarget, copyTarget]
        let resume = relayButton("Resume", target: resumeTarget, action: #selector(ClosureTarget.invoke))
        let reveal = relayToolbarButton(symbol: "folder", label: "Reveal in Finder", target: revealTarget, action: #selector(ClosureTarget.invoke))
        let terminal = relayToolbarButton(symbol: "terminal", label: "Open Terminal", target: terminalTarget, action: #selector(ClosureTarget.invoke))
        let copy = relayToolbarButton(symbol: "doc.on.doc", label: "Copy Path", target: copyTarget, action: #selector(ClosureTarget.invoke))
        actions.addArrangedSubview(resume)
        actions.addArrangedSubview(reveal)
        actions.addArrangedSubview(terminal)
        actions.addArrangedSubview(copy)
        stack.addArrangedSubview(actions)

        addSection("Context", content: contextView(session.context))
        addSection("Status evidence", content: evidenceView(session.statusEvidence))
        addSection("Event timeline", content: timelineView(session.events))
        addSection("Recent transcript", content: transcriptView(session.transcript))
        addSection("Discovered artifacts", content: artifactsView(session.artifacts))
    }

    func showCandidate(
        _ candidate: IntelligenceCandidate,
        diff: String?,
        targetPath: String?,
        suggestion: Suggestion?,
        message: (text: String, tone: NSColor)?,
        onPreview: @escaping () -> Void,
        onApply: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onUndo: @escaping () -> Void
    ) {
        clear(title: candidate.title)
        setTaskState("details_ready")
        let badge = RelayStatusBadge(text: candidate.lifecycle.rawValue.capitalized, color: RelayDesign.lifecycleColor(candidate.lifecycle))
        let confidence = relayLabel("\(candidate.lane.rawValue.replacingOccurrences(of: "_", with: " ")) · confidence \(Int(candidate.confidence * 100))%", size: 12, color: .secondaryLabelColor)
        let metadata = NSStackView(views: [badge, confidence])
        metadata.orientation = .horizontal
        metadata.alignment = .centerY
        metadata.spacing = 8
        stack.addArrangedSubview(metadata)
        if let message { stack.addArrangedSubview(RelayInlineBanner(message: message.text, tone: message.tone)) }
        addSection("Rationale", content: relayMultiline(candidate.rationale))
        addSection("Evidence", content: evidenceView(candidate.evidence))
        if let targetPath {
            addSection("Target file", content: relayMultiline(targetPath, color: .secondaryLabelColor))
        }
        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 7
        let previewTarget = ClosureTarget(onPreview)
        let applyTarget = ClosureTarget(onApply)
        let snoozeTarget = ClosureTarget(onSnooze)
        let dismissTarget = ClosureTarget(onDismiss)
        let undoTarget = ClosureTarget(onUndo)
        actionTargets = [previewTarget, applyTarget, snoozeTarget, dismissTarget, undoTarget]
        let previewButton = relayButton(diff == nil ? "Preview" : "Choose another file", target: previewTarget, action: #selector(ClosureTarget.invoke))
        actions.addArrangedSubview(previewButton)
        if diff != nil {
            let applyButton = relayButton("Apply", target: applyTarget, action: #selector(ClosureTarget.invoke))
            applyButton.hasDestructiveAction = candidate.lane == .impactIdea
            actions.addArrangedSubview(applyButton)
        }
        let snooze = relayToolbarButton(symbol: "moon.zzz", label: "Snooze", target: snoozeTarget, action: #selector(ClosureTarget.invoke))
        let dismiss = relayToolbarButton(symbol: "xmark", label: "Dismiss", target: dismissTarget, action: #selector(ClosureTarget.invoke))
        actions.addArrangedSubview(snooze)
        actions.addArrangedSubview(dismiss)
        if suggestion != nil || candidate.lifecycle == .applied {
            let undo = relayToolbarButton(symbol: "arrow.uturn.backward", label: "Undo last change", target: undoTarget, action: #selector(ClosureTarget.invoke))
            actions.addArrangedSubview(undo)
        }
        stack.addArrangedSubview(actions)
        if let suggestion {
            let risk = relayLabel("Risk: \(suggestion.risk.rawValue) · exact-path grant required", size: 11, color: RelayDesign.attention)
            stack.addArrangedSubview(risk)
        }
        if let diff {
            addSection("Exact diff", content: relayTextView(diff))
        } else {
            stack.addArrangedSubview(RelayInlineBanner(message: "Preview chooses the exact target path and shows the full proposed diff before any write.", tone: RelayDesign.signal))
        }
        if let telemetry = candidate.telemetryGuidance {
            addSection("Telemetry", content: relayMultiline(telemetry, color: .secondaryLabelColor))
        }
    }

    func showMetric(_ metric: UsageMetric, activity: [UsageActivityPoint], message: (text: String, tone: NSColor)?) {
        clear(title: metric.label)
        setTaskState("details_ready")
        let value = relayLabel(metricValue(metric), size: 34, weight: .bold)
        stack.addArrangedSubview(value)
        let precision = relayLabel("\(metric.precision.rawValue) · \(metric.source)", size: 11, color: .secondaryLabelColor)
        stack.addArrangedSubview(precision)
        if let message { stack.addArrangedSubview(RelayInlineBanner(message: message.text, tone: message.tone)) }
        addSection("What this means", content: relayMultiline(metric.explanation))
        addSection("Sessions over time", content: chartView(values: activity.map { CGFloat($0.sessionsStarted) }, color: RelayDesign.signal))
        addSection("Event activity", content: chartView(values: activity.map { CGFloat($0.eventCount) }, color: RelayDesign.success))
        addSection("Inactivity trend", content: chartView(values: activity.map { CGFloat($0.averageInactivitySeconds ?? 0) }, color: RelayDesign.attention))
        addSection("Precision", content: relayMultiline(metric.precision == .unavailable ? "Unavailable: Relay has no provider quota adapter and does not infer quota from transcript volume." : "This metric is derived from Relay’s local session and event store.", color: .secondaryLabelColor))
    }

    private func buildView() {
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        let header = NSStackView(views: [titleLabel])
        header.orientation = .horizontal
        header.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scrollView.documentView = document
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])
    }

    private func clear(title: String) {
        titleLabel.stringValue = title
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    func setTaskState(_ state: String) {
        setAccessibilityValue(state)
        setAccessibilityHelp("task-state=\(state); title=\(titleLabel.stringValue)")
    }

    private func addBadgeRow(status: AgentStatus, provider: ProviderID) {
        let statusBadge = RelayStatusBadge(status: status)
        let providerLabel = relayLabel("\(provider.rawValue) provider", size: 12, weight: .medium, color: .secondaryLabelColor)
        let row = NSStackView(views: [statusBadge, providerLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        stack.addArrangedSubview(row)
    }

    private func addSection(_ title: String, content: NSView) {
        let header = relaySectionHeader(title)
        let wrapper = NSStackView(views: [header, content])
        wrapper.orientation = .vertical
        wrapper.alignment = .width
        wrapper.spacing = 7
        stack.addArrangedSubview(wrapper)
    }

    private func contextView(_ context: SessionContext) -> NSView {
        let rows: [(String, String)] = [
            ("Repository", context.repositoryPath ?? "Unavailable"),
            ("Worktree", context.worktreePath ?? "Unavailable"),
            ("Branch", context.branch ?? "Unavailable"),
            ("Commit", context.commit ?? "Unavailable"),
            ("Working directory", context.workingDirectory ?? "Unavailable")
        ]
        return keyValueView(rows)
    }

    private func evidenceView(_ evidence: SessionStatusEvidence) -> NSView {
        let rows: [(String, String)] = [
            ("Confidence", evidence.confidence.rawValue),
            ("Source", evidence.source.rawValue),
            ("Observed", DateFormatter.localizedString(from: evidence.observedAt, dateStyle: .medium, timeStyle: .short)),
            ("Explanation", evidence.explanation)
        ]
        return keyValueView(rows)
    }

    private func evidenceView(_ evidence: [EvidenceReference]) -> NSView {
        guard !evidence.isEmpty else { return relayMultiline("No evidence excerpts recorded yet.", color: .secondaryLabelColor) }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 7
        for item in evidence.prefix(8) {
            let source = relayLabel("\(item.sessionID) · \(DateFormatter.localizedString(from: item.timestamp, dateStyle: .short, timeStyle: .short))", size: 10, weight: .medium, color: .tertiaryLabelColor)
            let excerpt = relayMultiline("“\(item.excerpt)“", size: 12)
            let block = NSStackView(views: [source, excerpt])
            block.orientation = .vertical
            block.alignment = .leading
            block.spacing = 3
            stack.addArrangedSubview(block)
        }
        return stack
    }

    private func timelineView(_ events: [SessionEvent]) -> NSView {
        guard !events.isEmpty else { return relayMultiline("No normalized events recorded for this session.", color: .secondaryLabelColor) }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        for event in events.suffix(8).reversed() {
            let heading = relayLabel("\(DateFormatter.localizedString(from: event.timestamp, dateStyle: .short, timeStyle: .short)) · \(event.type)", size: 10, weight: .medium, color: .tertiaryLabelColor)
            let text = relayMultiline(event.text, size: 12)
            let row = NSStackView(views: [heading, text])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 2
            stack.addArrangedSubview(row)
        }
        return stack
    }

    private func transcriptView(_ transcript: String) -> NSView {
        let excerpt = transcript.isEmpty ? "No transcript excerpt recorded." : String(transcript.suffix(1_600))
        return relayTextView(excerpt)
    }

    private func artifactsView(_ artifacts: [ContextArtifact]) -> NSView {
        guard !artifacts.isEmpty else { return relayMultiline("No artifacts discovered for this context.", color: .secondaryLabelColor) }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        for artifact in artifacts.prefix(12) {
            stack.addArrangedSubview(relayMultiline("\(artifact.kind) · \(artifact.logicalPath)\n\(artifact.physicalPath)", size: 11, color: .secondaryLabelColor))
        }
        return stack
    }

    private func keyValueView(_ rows: [(String, String)]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 5
        for (key, value) in rows {
            let keyLabel = relayLabel(key, size: 10, weight: .medium, color: .tertiaryLabelColor)
            keyLabel.setContentHuggingPriority(.required, for: .horizontal)
            let valueLabel = relayMultiline(value, size: 11, color: .secondaryLabelColor)
            let row = NSStackView(views: [keyLabel, valueLabel])
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 8
            stack.addArrangedSubview(row)
        }
        return stack
    }

    private func relayMultiline(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let label = relayLabel(text, size: size, weight: weight, color: color)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    private func chartView(values: [CGFloat], color: NSColor) -> NSView {
        let chart = RelaySparklineView()
        chart.values = values
        chart.strokeColor = color
        chart.wantsLayer = true
        chart.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.08).cgColor
        chart.translatesAutoresizingMaskIntoConstraints = false
        chart.heightAnchor.constraint(equalToConstant: 52).isActive = true
        return chart
    }

    private func metricValue(_ metric: UsageMetric) -> String {
        if metric.unit == "availability" { return metric.value == nil ? "Unavailable" : "Available" }
        guard let value = metric.value else { return "Unavailable" }
        if metric.unit == "seconds" { return value < 60 ? "\(Int(value))s" : "\(Int(value / 60))m" }
        return value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

@MainActor
private final class ClosureTarget: NSObject {
    private let closure: () -> Void

    init(_ closure: @escaping () -> Void) { self.closure = closure }

    @objc func invoke() { closure() }
}

@MainActor
private struct RelayCommand {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let perform: () -> Void
}

@MainActor
private final class RelayCommandPaletteView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let searchField = RelayCommandSearchField()
    private let tableView = NSTableView()
    private var commands: [RelayCommand] = []
    private var filteredCommands: [RelayCommand] = []
    var onDismiss: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.97).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 20
        layer?.shadowOffset = CGSize(width: 0, height: -8)
        buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setCommands(_ commands: [RelayCommand]) {
        self.commands = commands
        filteredCommands = commands
        searchField.stringValue = ""
        tableView.reloadData()
        if !commands.isEmpty { tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
    }

    private func buildView() {
        searchField.onKeyDown = { [weak self] event in self?.handleSearchKeyDown(event) ?? false }
        searchField.placeholderString = "Search commands…"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.font = NSFont.systemFont(ofSize: 15)
        searchField.setAccessibilityLabel("Command palette search")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.style = .sourceList
        tableView.backgroundColor = .clear
        tableView.rowSizeStyle = .medium
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchField)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            searchField.heightAnchor.constraint(equalToConstant: 30),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filteredCommands.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { RelayTableRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let command = filteredCommands[row]
        let cell = NSTableCellView()
        let icon = NSImageView(image: NSImage(systemSymbolName: command.symbol, accessibilityDescription: command.title) ?? NSImage())
        icon.contentTintColor = RelayDesign.signal
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = relayLabel(command.title, size: 13, weight: .medium)
        let detail = relayLabel(command.detail, size: 11, color: .secondaryLabelColor)
        detail.alignment = .right
        let stack = NSStackView(views: [icon, title, NSView(), detail])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: cell.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -5)
        ])
        cell.setAccessibilityLabel(command.title)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { }

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        filteredCommands = query.isEmpty ? commands : commands.filter { "\($0.title) \($0.detail)".lowercased().contains(query) }
        tableView.reloadData()
        if !filteredCommands.isEmpty { tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let event = NSApp.currentEvent, event.keyCode == 36 else { return }
        executeSelected()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            executeSelected()
            return
        }
        if event.keyCode == 53 {
            onDismiss?()
            return
        }
        super.keyDown(with: event)
    }

    private func executeSelected() {
        guard !filteredCommands.isEmpty else { return }
        let index = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard filteredCommands.indices.contains(index) else { return }
        let command = filteredCommands[index]
        onDismiss?()
        command.perform()
    }

    private func handleSearchKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125:
            moveSelection(by: 1)
            return true
        case 126:
            moveSelection(by: -1)
            return true
        case 36, 76:
            executeSelected()
            return true
        case 53:
            onDismiss?()
            return true
        default:
            return false
        }
    }

    private func moveSelection(by offset: Int) {
        guard !filteredCommands.isEmpty else { return }
        let current = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        let next = min(max(current + offset, 0), filteredCommands.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }
}

@MainActor
private final class RelayCommandSearchField: NSSearchField {
    var onKeyDown: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
