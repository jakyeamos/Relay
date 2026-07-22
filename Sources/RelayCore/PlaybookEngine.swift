import Foundation

public struct RedactionResult: Sendable, Equatable {
    public let text: String
    public let redactionCount: Int
    public let redactedPatterns: [String]

    public init(text: String, redactionCount: Int, redactedPatterns: [String]) {
        self.text = text
        self.redactionCount = redactionCount
        self.redactedPatterns = redactedPatterns
    }
}

public struct PlaybookEngine: Sendable {
    private struct Rule: Sendable {
        let lane: IntelligenceLane
        let key: String
        let title: String
        let rationale: String
        let helperFamily: String
        let terms: [String]
        let guidance: String
    }

    private let rules: [Rule] = [
        Rule(
            lane: .frictionTool,
            key: "package-manager",
            title: "Use the repository package manager consistently",
            rationale: "The session contains repeated package-manager corrections.",
            helperFamily: "tooling-convention",
            terms: ["use pnpm", "not npm", "use bun", "package manager"],
            guidance: "Add the selected package manager to the repository Playbook and verify it before dependency commands."
        ),
        Rule(
            lane: .workflowSkill,
            key: "verification",
            title: "Make verification part of the completion workflow",
            rationale: "The session repeatedly discusses tests, type checking, linting, or a definition of done.",
            helperFamily: "verification",
            terms: ["run tests", "run the tests", "typecheck", "type check", "before declaring", "definition of done"],
            guidance: "Create a project verification checklist covering the commands that must pass before completion."
        ),
        Rule(
            lane: .workflowSkill,
            key: "generated-files",
            title: "Document generated-file boundaries",
            rationale: "The session contains a correction about editing or regenerating generated files.",
            helperFamily: "repository-convention",
            terms: ["generated file", "do not edit", "regenerate", "generated files"],
            guidance: "Document which files are generated and the command that owns their regeneration."
        ),
        Rule(
            lane: .impactIdea,
            key: "stale-instruction",
            title: "Review stale or conflicting instructions",
            rationale: "The session suggests that an existing instruction is stale, duplicated, or contradictory.",
            helperFamily: "playbook-health",
            terms: ["stale instruction", "conflicting instruction", "no longer applies", "remove this rule"],
            guidance: "Review the referenced instruction before applying new guidance; prefer one canonical rule."
        )
    ]

    public init() {}

    public func analyze(sessions: [Session], now: Date = Date()) -> IntelligenceReport {
        let latestCutoff = now.addingTimeInterval(-86_400)
        var candidates: [IntelligenceCandidate] = []

        for rule in rules {
            let matchingEvents = sessions.flatMap { session in
                session.events.filter { event in
                    let text = event.text.lowercased()
                    return rule.terms.contains { text.contains($0) }
                }.map { event in
                    EvidenceReference(
                        sessionID: event.sessionID,
                        excerpt: compact(event.text),
                        timestamp: event.timestamp
                    )
                }
            }
            guard !matchingEvents.isEmpty else { continue }

            let distinctSessions = Set(matchingEvents.map(\.sessionID)).count
            let confidence = min(0.95, distinctSessions >= 2 ? 0.8 + min(0.15, Double(distinctSessions - 2) * 0.05) : 0.65)
            let latestScan = matchingEvents.contains { $0.timestamp >= latestCutoff }
            candidates.append(IntelligenceCandidate(
                id: "candidate-\(ContentHasher.hash(string: rule.key))",
                lane: rule.lane,
                title: rule.title,
                rationale: rule.rationale,
                confidence: confidence,
                evidence: Array(matchingEvents.prefix(8)),
                helperFamily: rule.helperFamily,
                latestScan: latestScan,
                telemetryGuidance: "Track whether this candidate is reviewed, applied, dismissed, or recurs in later sessions.",
                removalGuidance: rule.lane == .impactIdea ? "Confirm the old instruction is obsolete before removal." : nil
            ))
        }

        let rollups = Dictionary(grouping: candidates, by: \.helperFamily).mapValues(\.count)
        let removalCandidates = candidates.filter { $0.removalGuidance != nil }
        return IntelligenceReport(
            generatedAt: now,
            latestScanCandidates: candidates.filter(\.latestScan),
            pendingCandidates: candidates,
            helperFamilyRollups: rollups,
            implementationTelemetryGuidance: "Relay records candidate provenance, review outcomes, transaction results, and recurrence without sending transcripts off-device.",
            removalCandidates: removalCandidates
        )
    }

    public func makeSuggestion(
        for candidate: IntelligenceCandidate,
        targetURL: URL,
        proposedContent: String,
        currentContent: String?
    ) -> Suggestion {
        let targetPath = targetURL.standardizedFileURL.path
        let currentData = currentContent.map { Data($0.utf8) }
        let kind: FileOperationKind = currentContent == nil ? .create : .write
        let operation = FileOperation(
            kind: kind,
            targetPath: targetPath,
            beforeHash: currentData.map(ContentHasher.hash(data:)),
            proposedContent: proposedContent
        )
        return Suggestion(
            candidateID: candidate.id,
            title: candidate.title,
            rationale: candidate.rationale,
            confidence: candidate.confidence,
            risk: candidate.lane == .impactIdea ? .medium : .low,
            evidence: candidate.evidence,
            operations: [operation]
        )
    }

    public func redact(_ text: String) -> RedactionResult {
        let patterns: [(String, String)] = [
            ("private-key", "-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----"),
            ("token", "(?i)(token|secret|password|api[_-]?key)\\s*[:=]\\s*[^\\s]+"),
            ("env-assignment", "(?m)^[A-Z0-9_]+=(?!$).+$")
        ]
        var output = text
        var count = 0
        var names: [String] = []
        for (name, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            let matches = regex.matches(in: output, range: range)
            guard !matches.isEmpty else { continue }
            output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: "[REDACTED]")
            count += matches.count
            names.append(name)
        }
        return RedactionResult(text: output, redactionCount: count, redactedPatterns: names)
    }

    private func compact(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(normalized.prefix(280))
    }
}
