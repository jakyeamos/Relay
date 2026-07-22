import Foundation

public enum UsageTimeRange: String, CaseIterable, Codable, Sendable {
    case today
    case sevenDays
    case thirtyDays
    case all

    public var displayName: String {
        switch self {
        case .today: return "Today"
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        case .all: return "All time"
        }
    }

    public func startDate(now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .today: return calendar.startOfDay(for: now)
        case .sevenDays: return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
        case .thirtyDays: return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))
        case .all: return nil
        }
    }
}

public struct UsageScope: Sendable, Equatable {
    public var workspaceID: String?
    public var provider: ProviderID?
    public var timeRange: UsageTimeRange

    public init(
        workspaceID: String? = nil,
        provider: ProviderID? = nil,
        timeRange: UsageTimeRange = .sevenDays
    ) {
        self.workspaceID = workspaceID
        self.provider = provider
        self.timeRange = timeRange
    }
}

public struct UsageActivityPoint: Sendable, Equatable, Identifiable {
    public let date: Date
    public let sessionsStarted: Int
    public let eventCount: Int
    public let attentionCount: Int
    public let averageInactivitySeconds: Double?

    public var id: Date { date }

    public init(
        date: Date,
        sessionsStarted: Int,
        eventCount: Int,
        attentionCount: Int,
        averageInactivitySeconds: Double?
    ) {
        self.date = date
        self.sessionsStarted = sessionsStarted
        self.eventCount = eventCount
        self.attentionCount = attentionCount
        self.averageInactivitySeconds = averageInactivitySeconds
    }
}

public struct UsageService: Sendable {
    public init() {}

    public func filter(sessions: [Session], scope: UsageScope, now: Date = Date()) -> [Session] {
        let resolver = WorkspaceResolver()
        let startDate = scope.timeRange.startDate(now: now)
        return sessions.filter { session in
            guard resolver.matches(session, workspaceID: scope.workspaceID) else { return false }
            guard scope.provider == nil || session.provider == scope.provider else { return false }
            guard startDate == nil || session.lastActivityAt >= startDate! else { return false }
            return true
        }
    }

    public func localMetrics(sessions: [Session], now: Date = Date()) -> [UsageMetric] {
        let dayStart = Calendar.current.startOfDay(for: now)
        let active = sessions.filter { [.running, .waiting, .approvalRequired].contains($0.status) }.count
        let attention = sessions.filter { [.waiting, .approvalRequired].contains($0.status) }.count
        let today = sessions.filter { $0.startedAt >= dayStart }.count
        let totalEvents = sessions.reduce(0) { $0 + $1.events.count }
        let averageAge: Double? = sessions.isEmpty
            ? nil
            : sessions.map { max(0, now.timeIntervalSince($0.lastActivityAt)) }.reduce(0, +) / Double(sessions.count)

        return [
            UsageMetric(
                label: "Active sessions",
                value: Double(active),
                unit: "sessions",
                source: "Relay local session store",
                precision: .derived,
                observedAt: now,
                explanation: "Sessions currently classified as running, waiting, or approval required."
            ),
            UsageMetric(
                label: "Needs attention",
                value: Double(attention),
                unit: "sessions",
                source: "Relay local status model",
                precision: .derived,
                observedAt: now,
                explanation: "Waiting and approval-required sessions are surfaced first."
            ),
            UsageMetric(
                label: "Sessions today",
                value: Double(today),
                unit: "sessions",
                source: "Relay local session store",
                precision: .derived,
                observedAt: now,
                explanation: "Sessions whose recorded start time is today."
            ),
            UsageMetric(
                label: "Captured events",
                value: Double(totalEvents),
                unit: "events",
                source: "Relay local event store",
                precision: .derived,
                observedAt: now,
                explanation: "Normalized provider events retained under local retention settings."
            ),
            UsageMetric(
                label: "Average inactivity",
                value: averageAge,
                unit: "seconds",
                source: "Relay local status model",
                precision: averageAge == nil ? .unavailable : .estimated,
                observedAt: now,
                explanation: averageAge == nil ? "Unavailable until a session is imported." : "Estimated time since the last observed event."
            ),
            UsageMetric(
                label: "Provider quota",
                value: nil,
                unit: "",
                source: "No provider quota adapter configured",
                precision: .unavailable,
                observedAt: nil,
                explanation: "Provider-reported usage is best-effort and is not inferred from transcript volume."
            )
        ]
    }

    public func activitySeries(
        sessions: [Session],
        now: Date = Date(),
        days: Int = 7,
        calendar: Calendar = .current
    ) -> [UsageActivityPoint] {
        let dayCount = max(1, min(days, 90))
        let today = calendar.startOfDay(for: now)
        return (0..<dayCount).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let nextDate = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let daySessions = sessions.filter { $0.startedAt >= date && $0.startedAt < nextDate }
            let dayEvents = sessions.flatMap(\.events).filter { $0.timestamp >= date && $0.timestamp < nextDate }
            let attention = daySessions.filter { [.waiting, .approvalRequired].contains($0.status) }.count
            let inactivityValues = daySessions.map { max(0, now.timeIntervalSince($0.lastActivityAt)) }
            let averageInactivity = inactivityValues.isEmpty ? nil : inactivityValues.reduce(0, +) / Double(inactivityValues.count)
            return UsageActivityPoint(
                date: date,
                sessionsStarted: daySessions.count,
                eventCount: dayEvents.count,
                attentionCount: attention,
                averageInactivitySeconds: averageInactivity
            )
        }
    }

    public func providerFreshnessMetrics(health: [ProviderHealth], now: Date = Date()) -> [UsageMetric] {
        health.map { provider in
            UsageMetric(
                id: "provider-freshness-\(provider.provider.rawValue)",
                label: "\(provider.provider.rawValue) freshness",
                value: provider.isAvailable ? 1 : nil,
                unit: "availability",
                source: provider.dataSourcePath,
                precision: provider.isAvailable ? .derived : .unavailable,
                observedAt: now,
                explanation: provider.message
            )
        }
    }
}
