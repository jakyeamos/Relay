import Foundation

public struct UsageService {
    public init() {}

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
}
