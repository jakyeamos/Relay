import Foundation

public struct MonitoringRunResult: Sendable, Equatable {
    public let importedSessions: Int
    public let availableProviders: [ProviderID]
    public let failures: [String]

    public init(importedSessions: Int, availableProviders: [ProviderID], failures: [String]) {
        self.importedSessions = importedSessions
        self.availableProviders = availableProviders
        self.failures = failures
    }
}

public final class MonitoringCoordinator: @unchecked Sendable {
    public let store: SQLiteStore
    public let adapters: [any ProviderAdapter]
    private let queue = DispatchQueue(label: "codes.relay.monitoring", qos: .utility)
    private let runLock = NSLock()
    private var timer: DispatchSourceTimer?
    private var lastScan: Date?

    public init(store: SQLiteStore, adapters: [any ProviderAdapter] = [
        CodexAdapter(),
        ClaudeCodeAdapter()
    ]) {
        self.store = store
        self.adapters = adapters
    }

    @discardableResult
    public func runOnce() -> MonitoringRunResult {
        runLock.lock()
        defer { runLock.unlock() }
        var imported = 0
        var available: [ProviderID] = []
        var failures: [String] = []

        for adapter in adapters {
            let health = adapter.health()
            if health.isAvailable { available.append(adapter.provider) }
            do {
                let sessions = try adapter.importSessions(since: lastScan)
                for session in sessions {
                    try store.upsert(imported: session)
                    imported += 1
                }
                for metric in adapter.usageSnapshot() {
                    try store.saveUsage(metric)
                }
            } catch {
                failures.append("\(adapter.provider.rawValue): \(error.localizedDescription)")
            }
        }

        lastScan = Date()
        NotificationCenter.default.post(name: .relayDataDidChange, object: nil)
        return MonitoringRunResult(importedSessions: imported, availableProviders: available, failures: failures)
    }

    public func start(interval: TimeInterval = 5) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            _ = self?.runOnce()
        }
        self.timer = timer
        timer.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }
}

public extension Notification.Name {
    static let relayDataDidChange = Notification.Name("RelayDataDidChange")
}
