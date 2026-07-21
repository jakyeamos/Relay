import Foundation

public enum StatusInference {
    public static func infer(events: [SessionEvent], now: Date = Date()) -> SessionStatusEvidence {
        guard let latest = events.max(by: { $0.timestamp < $1.timestamp }) else {
            return SessionStatusEvidence(
                status: .discovered,
                confidence: .low,
                source: .file,
                observedAt: now,
                explanation: "Session data exists, but no activity evidence is available.",
                evidenceReferences: []
            )
        }

        let normalizedType = latest.type.lowercased()
        let normalizedText = latest.text.lowercased()
        let evidence = [latest.id]

        if containsAny(normalizedType, values: ["approval", "permission", "confirm"]) ||
            containsAny(normalizedText, values: ["approval required", "permission required", "waiting for approval"]) {
            return SessionStatusEvidence(
                status: .approvalRequired,
                confidence: .high,
                source: .provider,
                observedAt: latest.timestamp,
                explanation: "The latest provider event indicates an approval or permission gate.",
                evidenceReferences: evidence
            )
        }

        if containsAny(normalizedType, values: ["error", "failed", "failure"]) ||
            containsAny(normalizedText, values: ["fatal error", "command failed", "traceback"]) {
            return SessionStatusEvidence(
                status: .failed,
                confidence: .high,
                source: .provider,
                observedAt: latest.timestamp,
                explanation: "The latest provider event contains an error signal.",
                evidenceReferences: evidence
            )
        }

        if containsAny(normalizedType, values: ["completed", "complete", "done", "exit", "terminated"]) {
            return SessionStatusEvidence(
                status: .completed,
                confidence: .high,
                source: .provider,
                observedAt: latest.timestamp,
                explanation: "The provider recorded a completion or termination event.",
                evidenceReferences: evidence
            )
        }

        if containsAny(normalizedType, values: ["waiting", "input", "question", "prompt"]) ||
            containsAny(normalizedText, values: ["what would you like", "please choose", "waiting for input"]) {
            return SessionStatusEvidence(
                status: .waiting,
                confidence: .medium,
                source: .inferred,
                observedAt: latest.timestamp,
                explanation: "The latest event looks like a request for user input.",
                evidenceReferences: evidence
            )
        }

        let age = max(0, now.timeIntervalSince(latest.timestamp))
        if age <= 15 {
            return SessionStatusEvidence(
                status: .running,
                confidence: .medium,
                source: .file,
                observedAt: latest.timestamp,
                explanation: "Recent provider activity suggests the session is still running.",
                evidenceReferences: evidence
            )
        }

        if age <= 900 {
            return SessionStatusEvidence(
                status: .idle,
                confidence: .low,
                source: .inferred,
                observedAt: latest.timestamp,
                explanation: "No qualifying activity was observed within the active threshold.",
                evidenceReferences: evidence
            )
        }

        return SessionStatusEvidence(
            status: .unknown,
            confidence: .low,
            source: .inferred,
            observedAt: latest.timestamp,
            explanation: "The available evidence is too old to classify the current state safely.",
            evidenceReferences: evidence
        )
    }

    private static func containsAny(_ value: String, values: [String]) -> Bool {
        values.contains { value.contains($0) }
    }
}
