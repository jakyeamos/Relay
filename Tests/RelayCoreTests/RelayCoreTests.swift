import Foundation
import XCTest
@testable import RelayCore

final class RelayCoreTests: XCTestCase {
    func testCodexParserNormalizesSessionAndPreservesUnknownLines() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("session.jsonl")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let firstTimestamp = formatter.string(from: Date().addingTimeInterval(-2))
        let secondTimestamp = formatter.string(from: Date())
        let content = """
        {"timestamp":"\(firstTimestamp)","type":"user_message","role":"user","cwd":"/tmp/relay-project","text":"Use pnpm and run tests before declaring completion"}
        not json
        {"timestamp":"\(secondTimestamp)","type":"assistant_message","role":"assistant","text":"I will verify the project."}
        """
        try content.write(to: file, atomically: true, encoding: .utf8)
        let adapter = CodexAdapter(sessionsRoot: root)
        let imported = try XCTUnwrap(CodexSessionParser().parse(fileURL: file, modifiedAt: Date(), adapter: adapter))

        XCTAssertEqual(imported.session.provider, .codex)
        XCTAssertEqual(imported.session.title, "Use pnpm and run tests before declaring completion")
        XCTAssertEqual(imported.session.events.count, 2)
        XCTAssertEqual(imported.session.context.workingDirectory, "/tmp/relay-project")
        XCTAssertEqual(imported.session.status, .running)
    }

    func testStatusInferencePrefersApprovalAndFailureEvidence() {
        let now = Date()
        let approval = SessionEvent(
            sessionID: "session",
            timestamp: now,
            type: "permission_request",
            text: "Approval required to continue"
        )
        XCTAssertEqual(StatusInference.infer(events: [approval], now: now).status, .approvalRequired)

        let failure = SessionEvent(
            sessionID: "session",
            timestamp: now,
            type: "error",
            text: "Command failed"
        )
        XCTAssertEqual(StatusInference.infer(events: [failure], now: now).status, .failed)
    }

    func testPlaybookAnalysisSeparatesLatestScanAndPendingCandidates() {
        let now = Date()
        let recent = makeSession(
            id: "recent",
            eventText: "Please use pnpm, not npm. Run tests before completion.",
            eventDate: now.addingTimeInterval(-300)
        )
        let old = makeSession(
            id: "old",
            eventText: "The generated file should be regenerated, not edited directly.",
            eventDate: now.addingTimeInterval(-172_800)
        )
        let report = PlaybookEngine().analyze(sessions: [recent, old], now: now)

        XCTAssertEqual(report.latestScanCandidates.count, 2)
        XCTAssertEqual(report.pendingCandidates.count, 3)
        XCTAssertTrue(report.pendingCandidates.contains { $0.lane == .frictionTool })
        XCTAssertEqual(report.helperFamilyRollups["verification"], 1)
    }

    func testRedactionMasksSecretsWithoutSendingAnything() {
        let result = PlaybookEngine().redact("TOKEN=abc123\nnormal text")
        XCTAssertEqual(result.redactionCount, 1)
        XCTAssertFalse(result.text.contains("abc123"))
        XCTAssertTrue(result.text.contains("[REDACTED]"))
    }

    func testFileTransactionAppliesAndUndoesWithPreconditions() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("AGENTS.md")
        try Data("before\n".utf8).write(to: file)
        let suggestion = Suggestion(
            candidateID: "candidate",
            title: "Update instructions",
            rationale: "Evidence",
            confidence: 0.8,
            risk: .low,
            evidence: [],
            operations: [FileOperation(
                kind: .write,
                targetPath: file.path,
                beforeHash: ContentHasher.hash(string: "before\n"),
                proposedContent: "after\n"
            )]
        )
        let manager = FileTransactionManager()
        let record = try manager.apply(suggestion, grant: PathGrant(paths: [file.path]))
        XCTAssertEqual(try String(contentsOf: file), "after\n")
        _ = try manager.undo(record)
        XCTAssertEqual(try String(contentsOf: file), "before\n")
    }

    func testFileTransactionRejectsStaleTarget() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("AGENTS.md")
        try Data("changed\n".utf8).write(to: file)
        let suggestion = Suggestion(
            candidateID: "candidate",
            title: "Update instructions",
            rationale: "Evidence",
            confidence: 0.8,
            risk: .low,
            evidence: [],
            operations: [FileOperation(
                kind: .write,
                targetPath: file.path,
                beforeHash: ContentHasher.hash(string: "original\n"),
                proposedContent: "after\n"
            )]
        )
        XCTAssertThrowsError(try FileTransactionManager().apply(suggestion, grant: PathGrant(paths: [file.path]))) { error in
            guard case FileTransactionError.staleTarget = error else {
                return XCTFail("Expected a stale target error, got \(error)")
            }
        }
    }

    func testFileTransactionWritesThroughSymlinkAndPreservesLink() throws {
        let root = try temporaryDirectory()
        let target = root.appendingPathComponent("canonical.md")
        let link = root.appendingPathComponent("AGENTS.md")
        try Data("before\n".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let suggestion = Suggestion(
            candidateID: "candidate",
            title: "Update linked instructions",
            rationale: "Evidence",
            confidence: 0.8,
            risk: .low,
            evidence: [],
            operations: [FileOperation(
                kind: .write,
                targetPath: link.path,
                beforeHash: ContentHasher.hash(string: "before\n"),
                proposedContent: "after\n"
            )]
        )

        let manager = FileTransactionManager()
        let record = try manager.apply(suggestion, grant: PathGrant(paths: [link.path]))
        XCTAssertEqual(try String(contentsOf: target), "after\n")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
        _ = try manager.undo(record)
        XCTAssertEqual(try String(contentsOf: target), "before\n")
    }

    func testSQLiteRoundTripSupportsSearchAndUsage() throws {
        let root = try temporaryDirectory()
        let store = try SQLiteStore(url: root.appendingPathComponent("relay.sqlite"))
        let session = makeSession(id: "session", eventText: "Use pnpm", eventDate: Date())
        try store.upsert(imported: ImportedSession(session: session, sourceModifiedAt: Date()))
        let found = try store.sessions(search: "pnpm")
        XCTAssertEqual(found.map(\.id), ["session"])

        let metric = UsageMetric(
            label: "Active sessions",
            value: 1,
            unit: "sessions",
            source: "test",
            precision: .derived,
            observedAt: Date(),
            explanation: "test"
        )
        try store.saveUsage(metric)
        XCTAssertEqual(try store.usageMetrics().first?.label, "Active sessions")
    }

    func testUsageServiceMarksProviderQuotaUnavailable() {
        let metrics = UsageService().localMetrics(sessions: [])
        let quota = metrics.first { $0.label == "Provider quota" }
        XCTAssertEqual(quota?.precision, .unavailable)
        XCTAssertNil(quota?.value)
    }

    private func makeSession(id: String, eventText: String, eventDate: Date) -> Session {
        let event = SessionEvent(sessionID: id, timestamp: eventDate, type: "message", role: "user", text: eventText)
        let evidence = StatusInference.infer(events: [event], now: eventDate)
        return Session(
            id: id,
            provider: .codex,
            title: "Session \(id)",
            status: evidence.status,
            statusEvidence: evidence,
            startedAt: eventDate,
            lastActivityAt: eventDate,
            context: SessionContext(workingDirectory: "/tmp/relay-project"),
            transcript: eventText,
            sourceReference: "fixture://\(id)",
            events: [event]
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("relay-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
