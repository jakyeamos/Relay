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

    func testCodexParserReadsNestedPayloadFields() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("nested.jsonl")
        let content = """
        {"timestamp":"2026-07-21T12:00:00Z","type":"session_meta","payload":{"cwd":"/tmp/nested-project","session_id":"nested","type":"session_meta"}}
        {"timestamp":"2026-07-21T12:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Use pnpm for this project"}]}}
        {"timestamp":"2026-07-21T12:00:02Z","type":"event_msg","payload":{"type":"task_complete","message":"Finished"}}
        """
        try content.write(to: file, atomically: true, encoding: .utf8)

        let adapter = CodexAdapter(sessionsRoot: root)
        let imported = try XCTUnwrap(CodexSessionParser().parse(fileURL: file, modifiedAt: Date(), adapter: adapter))

        XCTAssertEqual(imported.session.context.workingDirectory, "/tmp/nested-project")
        XCTAssertEqual(imported.session.title, "Use pnpm for this project")
        XCTAssertEqual(imported.session.status, .completed)
    }

    func testSessionTitleNormalizerMakesMetadataTitlesReadable() {
        XCTAssertEqual(
            SessionTitleNormalizer.normalize("<recommended_plugins>"),
            "Recommended plugins"
        )
        XCTAssertEqual(
            SessionTitleNormalizer.normalize("<codex_internal_context source=\"goal\">"),
            "Codex internal context"
        )
        XCTAssertEqual(
            SessionTitleNormalizer.normalize(
                "# AGENTS.md instructions for /tmp/relay-project",
                workingDirectory: "/tmp/relay-project"
            ),
            "AGENTS.md instructions"
        )
        XCTAssertEqual(
            SessionTitleNormalizer.normalize("PLEASE IMPLEMENT THIS PLAN:"),
            "Implement this plan"
        )
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

    func testCodexAdapterBoundsInitialHistoryToRecentFiles() throws {
        let root = try temporaryDirectory()
        let older = root.appendingPathComponent("older.jsonl")
        let newer = root.appendingPathComponent("newer.jsonl")
        let content = "{\"timestamp\":\"2026-07-21T12:00:00Z\",\"type\":\"user_message\",\"role\":\"user\",\"cwd\":\"/tmp\",\"text\":\"session\"}\n"
        try content.write(to: older, atomically: true, encoding: .utf8)
        try content.write(to: newer, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3_600)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: newer.path)

        let adapter = CodexAdapter(
            sessionsRoot: root,
            initialLookback: 86_400,
            initialSessionLimit: 1
        )
        let imported = try adapter.importSessions()

        XCTAssertEqual(imported.count, 1)
        let importedPath = imported.first.map { URL(fileURLWithPath: $0.session.sourceReference).lastPathComponent }
        XCTAssertEqual(importedPath, newer.lastPathComponent)
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

    func testWorkspaceResolverGroupsRepositoryWorktreeFallbackAndUnassignedSessions() {
        let now = Date(timeIntervalSince1970: 1_000)
        var repositorySession = makeSession(id: "repository", eventText: "Use pnpm", eventDate: now)
        repositorySession.context = SessionContext(
            workingDirectory: "/tmp/worktree-a",
            repositoryPath: "/tmp/relay-repository",
            worktreePath: "/tmp/worktree-a",
            branch: "dev",
            commit: "abc123"
        )
        var secondWorktree = makeSession(id: "second", eventText: "Run tests", eventDate: now.addingTimeInterval(10))
        secondWorktree.context = SessionContext(
            workingDirectory: "/tmp/worktree-b",
            repositoryPath: "/tmp/relay-repository",
            worktreePath: "/tmp/worktree-b"
        )
        var fallbackSession = makeSession(id: "fallback", eventText: "Fallback", eventDate: now.addingTimeInterval(20))
        fallbackSession.context = SessionContext(worktreePath: "/tmp/standalone-worktree")
        var unassignedSession = makeSession(id: "unassigned", eventText: "No path", eventDate: now.addingTimeInterval(30))
        unassignedSession.context = SessionContext()

        let resolver = WorkspaceResolver()
        let summaries = resolver.summaries(
            sessions: [repositorySession, secondWorktree, fallbackSession, unassignedSession],
            now: now
        )

        let repositoryID = resolver.workspaceID(for: repositorySession)
        let repositorySummary = summaries.first { $0.id == repositoryID }
        XCTAssertEqual(repositorySummary?.sessionCount, 2)
        XCTAssertEqual(repositorySummary?.associatedWorktrees, ["/tmp/worktree-a", "/tmp/worktree-b"])
        XCTAssertEqual(resolver.workspaceID(for: fallbackSession), RelayWorkspace.stableID(for: "/tmp/standalone-worktree"))
        XCTAssertTrue(summaries.contains { $0.id == RelayWorkspace.unassignedID && $0.sessionCount == 1 })
    }

    func testWorkspacePersistencePreservesRenamePinOrderAndExistingDatabaseLoad() throws {
        let root = try temporaryDirectory()
        let databaseURL = root.appendingPathComponent("relay.sqlite")
        let session = makeSession(id: "workspace-session", eventText: "workspace", eventDate: Date())
        var contextualSession = session
        contextualSession.context = SessionContext(repositoryPath: "/tmp/relay-persisted")

        do {
            let store = try SQLiteStore(url: databaseURL)
            try store.upsert(imported: ImportedSession(session: contextualSession, sourceModifiedAt: Date()))
            try store.ensureWorkspaces(for: [contextualSession])
            var workspace = try XCTUnwrap(store.workspaces().first)
            workspace.name = "Pinned Relay"
            workspace.isPinned = true
            workspace.sortOrder = 7
            workspace.isHidden = false
            try store.saveWorkspace(workspace)
        }

        let reopened = try SQLiteStore(url: databaseURL)
        let persisted = try XCTUnwrap(reopened.workspaces().first)
        XCTAssertEqual(persisted.name, "Pinned Relay")
        XCTAssertTrue(persisted.isPinned)
        XCTAssertEqual(persisted.sortOrder, 7)
        XCTAssertEqual(try reopened.sessions().map(\.id), ["workspace-session"])
    }

    func testSessionQueryScopesWorkspaceProviderStatusAndText() throws {
        let root = try temporaryDirectory()
        let store = try SQLiteStore(url: root.appendingPathComponent("relay.sqlite"))
        var codex = makeSession(id: "codex", eventText: "Find the repository build", eventDate: Date())
        codex.context = SessionContext(repositoryPath: "/tmp/query-repository")
        var claude = makeSession(id: "claude", eventText: "Find a different provider", eventDate: Date().addingTimeInterval(-10))
        claude.context = SessionContext(repositoryPath: "/tmp/query-other")
        claude.status = .waiting
        try store.upsert(imported: ImportedSession(session: codex, sourceModifiedAt: Date()))
        try store.upsert(imported: ImportedSession(session: claude, sourceModifiedAt: Date()))

        let resolver = WorkspaceResolver()
        let scoped = try store.sessions(query: SessionQuery(
            workspaceID: resolver.workspaceID(for: codex),
            text: "build",
            provider: .codex,
            statuses: [.running],
            sortOrder: .recent
        ))
        XCTAssertEqual(scoped.map(\.id), ["codex"])
        XCTAssertEqual(try store.sessions(query: SessionQuery(text: "repository build")).map(\.id), ["codex"])
        XCTAssertTrue(try store.sessions(query: SessionQuery(provider: .claudeCode)).isEmpty)
        XCTAssertEqual(try store.sessions(query: SessionQuery(statuses: [.waiting])).map(\.id), ["claude"])
    }

    func testWorkspaceScopedQueryAppliesLimitAfterGrouping() throws {
        let root = try temporaryDirectory()
        let store = try SQLiteStore(url: root.appendingPathComponent("relay.sqlite"))
        var older = makeSession(id: "older", eventText: "older", eventDate: Date(timeIntervalSince1970: 100))
        older.context = SessionContext(repositoryPath: "/tmp/limited-workspace")
        var newer = makeSession(id: "newer", eventText: "newer", eventDate: Date(timeIntervalSince1970: 200))
        newer.context = SessionContext(repositoryPath: "/tmp/other-workspace")
        try store.upsert(imported: ImportedSession(session: older, sourceModifiedAt: older.lastActivityAt))
        try store.upsert(imported: ImportedSession(session: newer, sourceModifiedAt: newer.lastActivityAt))

        let workspaceID = WorkspaceResolver().workspaceID(for: older)
        let scoped = try store.sessions(query: SessionQuery(workspaceID: workspaceID, limit: 1))
        XCTAssertEqual(scoped.map(\.id), ["older"])
    }

    func testUsageScopeAndActivitySeriesRemainLocalAndExplicit() {
        let now = Date(timeIntervalSince1970: 86_400 * 10 + 12 * 3_600)
        var current = makeSession(id: "current", eventText: "current", eventDate: now.addingTimeInterval(-1_800))
        current.context = SessionContext(repositoryPath: "/tmp/usage-repository")
        current.status = .waiting
        var other = makeSession(id: "other", eventText: "other", eventDate: now.addingTimeInterval(-1_200))
        other.context = SessionContext(repositoryPath: "/tmp/other-repository")
        let service = UsageService()
        let filtered = service.filter(
            sessions: [current, other],
            scope: UsageScope(workspaceID: WorkspaceResolver().workspaceID(for: current), timeRange: .sevenDays),
            now: now
        )
        XCTAssertEqual(filtered.map(\.id), ["current"])
        XCTAssertEqual(service.localMetrics(sessions: filtered, now: now).first { $0.label == "Needs attention" }?.value, 1)
        let series = service.activitySeries(sessions: filtered, now: now, days: 7)
        XCTAssertEqual(series.count, 7)
        XCTAssertEqual(series.last?.sessionsStarted, 1)
        XCTAssertEqual(service.localMetrics(sessions: filtered).first { $0.label == "Provider quota" }?.precision, .unavailable)
    }

    func testCandidateLifecycleRoundTripsWithStableCandidateIdentity() throws {
        let now = Date()
        let session = makeSession(id: "candidate-session", eventText: "Use pnpm, not npm", eventDate: now)
        let engine = PlaybookEngine()
        let first = try XCTUnwrap(engine.analyze(sessions: [session], now: now).pendingCandidates.first)
        let second = try XCTUnwrap(engine.analyze(sessions: [session], now: now).pendingCandidates.first)
        XCTAssertEqual(first.id, second.id)

        let root = try temporaryDirectory()
        let store = try SQLiteStore(url: root.appendingPathComponent("relay.sqlite"))
        var snoozed = first
        snoozed.lifecycle = .snoozed
        try store.saveCandidate(snoozed)
        XCTAssertEqual(try store.candidates().first?.lifecycle, .snoozed)
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
