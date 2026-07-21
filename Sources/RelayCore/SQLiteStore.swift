import CSQLite
import Foundation

public enum RelayDatabase {
    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return applicationSupport.appendingPathComponent("Relay/relay.sqlite")
    }
}

public enum SQLiteStoreError: Error, LocalizedError {
    case openFailed(String)
    case queryFailed(String)
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "Could not open Relay database: \(message)"
        case .queryFailed(let message): return "Relay database query failed: \(message)"
        case .encodingFailed: return "Relay could not encode a database record."
        }
    }
}

public final class SQLiteStore: @unchecked Sendable {
    public let url: URL
    private var database: OpaquePointer?
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL = RelayDatabase.defaultURL(), fileManager: FileManager = .default) throws {
        self.url = url
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let handle { sqlite3_close(handle) }
            throw SQLiteStoreError.openFailed(message)
        }
        self.database = handle
        try migrate()
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    public func upsert(imported: ImportedSession) throws {
        lock.lock()
        defer { lock.unlock() }
        let session = imported.session
        let normalizedTitle = SessionTitleNormalizer.normalize(
            session.title,
            workingDirectory: session.context.workingDirectory
        )
        let artifactsJSON = try encode(session.artifacts)
        try execute(
            """
            INSERT INTO sessions (
                id, provider, title, status, confidence, status_source, status_explanation,
                started_at, last_activity_at, working_directory, repository_path, worktree_path,
                branch, commit_hash, transcript, source_reference, artifacts_json, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                provider = excluded.provider,
                title = excluded.title,
                status = excluded.status,
                confidence = excluded.confidence,
                status_source = excluded.status_source,
                status_explanation = excluded.status_explanation,
                started_at = excluded.started_at,
                last_activity_at = excluded.last_activity_at,
                working_directory = excluded.working_directory,
                repository_path = excluded.repository_path,
                worktree_path = excluded.worktree_path,
                branch = excluded.branch,
                commit_hash = excluded.commit_hash,
                transcript = excluded.transcript,
                source_reference = excluded.source_reference,
                artifacts_json = excluded.artifacts_json,
                updated_at = excluded.updated_at
            """,
            bindings: [
                .text(session.id), .text(session.provider.rawValue), .text(normalizedTitle),
                .text(session.status.rawValue), .text(session.statusEvidence.confidence.rawValue),
                .text(session.statusEvidence.source.rawValue), .text(session.statusEvidence.explanation),
                .double(session.startedAt.timeIntervalSince1970), .double(session.lastActivityAt.timeIntervalSince1970),
                .text(session.context.workingDirectory), .text(session.context.repositoryPath),
                .text(session.context.worktreePath), .text(session.context.branch), .text(session.context.commit),
                .text(session.transcript), .text(session.sourceReference), .text(artifactsJSON),
                .double(imported.sourceModifiedAt.timeIntervalSince1970)
            ]
        )

        try execute("DELETE FROM session_events WHERE session_id = ?", bindings: [.text(session.id)])
        for event in session.events {
            try execute(
                "INSERT OR REPLACE INTO session_events (id, session_id, timestamp, type, role, text, raw_json) VALUES (?, ?, ?, ?, ?, ?, ?)",
                bindings: [
                    .text(event.id), .text(event.sessionID), .double(event.timestamp.timeIntervalSince1970),
                    .text(event.type), .text(event.role), .text(event.text), .text(event.rawJSON)
                ]
            )
        }

        for transition in imported.transitions {
            let evidenceJSON = try encode(transition.evidence)
            try execute(
                "INSERT OR REPLACE INTO status_transitions (id, session_id, previous_status, current_status, evidence_json, timestamp) VALUES (?, ?, ?, ?, ?, ?)",
                bindings: [
                    .text(transition.id), .text(transition.sessionID), .text(transition.previous?.rawValue),
                    .text(transition.current.rawValue), .text(evidenceJSON),
                    .double(transition.evidence.observedAt.timeIntervalSince1970)
                ]
            )
        }
    }

    public func sessions(search searchTerm: String? = nil) throws -> [Session] {
        lock.lock()
        defer { lock.unlock() }
        let normalizedQuery = searchTerm?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sql: String
        let bindings: [SQLiteBinding]
        if let normalizedQuery, !normalizedQuery.isEmpty {
            sql = """
            SELECT id, provider, title, status, confidence, status_source, status_explanation,
                   started_at, last_activity_at, working_directory, repository_path, worktree_path,
                   branch, commit_hash, transcript, source_reference, artifacts_json
            FROM sessions
            WHERE title LIKE ? OR provider LIKE ? OR branch LIKE ? OR repository_path LIKE ? OR transcript LIKE ?
            ORDER BY last_activity_at DESC
            LIMIT 500
            """
            let pattern = "%\(normalizedQuery)%"
            bindings = Array(repeating: .text(pattern), count: 5)
        } else {
            sql = """
            SELECT id, provider, title, status, confidence, status_source, status_explanation,
                   started_at, last_activity_at, working_directory, repository_path, worktree_path,
                   branch, commit_hash, transcript, source_reference, artifacts_json
            FROM sessions ORDER BY last_activity_at DESC LIMIT 500
            """
            bindings = []
        }

        return try query(sql, bindings: bindings) { statement in
            try session(from: statement)
        }
    }

    public func saveUsage(_ metric: UsageMetric) throws {
        lock.lock()
        defer { lock.unlock() }
        let encoded = try encode(metric)
        try execute(
            "INSERT OR REPLACE INTO usage_metrics (id, label, precision, observed_at, payload_json) VALUES (?, ?, ?, ?, ?)",
            bindings: [
                .text(metric.id), .text(metric.label), .text(metric.precision.rawValue),
                .double(metric.observedAt?.timeIntervalSince1970), .text(encoded)
            ]
        )
    }

    public func usageMetrics() throws -> [UsageMetric] {
        lock.lock()
        defer { lock.unlock() }
        return try query("SELECT payload_json FROM usage_metrics ORDER BY observed_at DESC", bindings: []) { statement in
            guard let text = columnText(statement, index: 0), let data = text.data(using: .utf8) else {
                throw SQLiteStoreError.encodingFailed
            }
            return try decoder.decode(UsageMetric.self, from: data)
        }
    }

    public func saveCandidate(_ candidate: IntelligenceCandidate) throws {
        lock.lock()
        defer { lock.unlock() }
        try execute(
            "INSERT OR REPLACE INTO candidates (id, lane, lifecycle, latest_scan, payload_json) VALUES (?, ?, ?, ?, ?)",
            bindings: [
                .text(candidate.id), .text(candidate.lane.rawValue), .text(candidate.lifecycle.rawValue),
                .integer(candidate.latestScan ? 1 : 0), .text(try encode(candidate))
            ]
        )
    }

    public func candidates() throws -> [IntelligenceCandidate] {
        lock.lock()
        defer { lock.unlock() }
        return try query("SELECT payload_json FROM candidates ORDER BY latest_scan DESC, id", bindings: []) { statement in
            guard let text = columnText(statement, index: 0), let data = text.data(using: .utf8) else {
                throw SQLiteStoreError.encodingFailed
            }
            return try decoder.decode(IntelligenceCandidate.self, from: data)
        }
    }

    public func saveSuggestion(_ suggestion: Suggestion) throws {
        lock.lock()
        defer { lock.unlock() }
        try execute(
            "INSERT OR REPLACE INTO suggestions (id, candidate_id, state, payload_json) VALUES (?, ?, ?, ?)",
            bindings: [
                .text(suggestion.id), .text(suggestion.candidateID), .text(suggestion.state.rawValue),
                .text(try encode(suggestion))
            ]
        )
    }

    public func suggestions() throws -> [Suggestion] {
        lock.lock()
        defer { lock.unlock() }
        return try query("SELECT payload_json FROM suggestions ORDER BY id DESC", bindings: []) { statement in
            guard let text = columnText(statement, index: 0), let data = text.data(using: .utf8) else {
                throw SQLiteStoreError.encodingFailed
            }
            return try decoder.decode(Suggestion.self, from: data)
        }
    }

    public func record(transaction: FileTransactionRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        try execute(
            "INSERT OR REPLACE INTO transactions (id, suggestion_id, undone, payload_json) VALUES (?, ?, ?, ?)",
            bindings: [
                .text(transaction.id), .text(transaction.suggestionID), .integer(transaction.undone ? 1 : 0),
                .text(try encode(transaction))
            ]
        )
    }

    public func record(auditEvent: AuditEvent) throws {
        lock.lock()
        defer { lock.unlock() }
        try execute(
            "INSERT OR REPLACE INTO audit_events (id, action, entity_id, processing_mode, timestamp, detail) VALUES (?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(auditEvent.id), .text(auditEvent.action), .text(auditEvent.entityID),
                .text(auditEvent.processingMode), .double(auditEvent.timestamp.timeIntervalSince1970),
                .text(auditEvent.detail)
            ]
        )
    }

    private func migrate() throws {
        try executeScript(
            """
            PRAGMA journal_mode = WAL;
            PRAGMA foreign_keys = ON;
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                provider TEXT NOT NULL,
                title TEXT NOT NULL,
                status TEXT NOT NULL,
                confidence TEXT NOT NULL,
                status_source TEXT NOT NULL,
                status_explanation TEXT NOT NULL,
                started_at REAL NOT NULL,
                last_activity_at REAL NOT NULL,
                working_directory TEXT,
                repository_path TEXT,
                worktree_path TEXT,
                branch TEXT,
                commit_hash TEXT,
                transcript TEXT NOT NULL,
                source_reference TEXT NOT NULL,
                artifacts_json TEXT NOT NULL,
                updated_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS sessions_last_activity_idx ON sessions(last_activity_at DESC);
            CREATE TABLE IF NOT EXISTS session_events (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                timestamp REAL NOT NULL,
                type TEXT NOT NULL,
                role TEXT,
                text TEXT NOT NULL,
                raw_json TEXT
            );
            CREATE INDEX IF NOT EXISTS session_events_session_idx ON session_events(session_id, timestamp);
            CREATE TABLE IF NOT EXISTS status_transitions (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                previous_status TEXT,
                current_status TEXT NOT NULL,
                evidence_json TEXT NOT NULL,
                timestamp REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS usage_metrics (
                id TEXT PRIMARY KEY,
                label TEXT NOT NULL,
                precision TEXT NOT NULL,
                observed_at REAL,
                payload_json TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS candidates (
                id TEXT PRIMARY KEY,
                lane TEXT NOT NULL,
                lifecycle TEXT NOT NULL,
                latest_scan INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS suggestions (
                id TEXT PRIMARY KEY,
                candidate_id TEXT NOT NULL,
                state TEXT NOT NULL,
                payload_json TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS transactions (
                id TEXT PRIMARY KEY,
                suggestion_id TEXT NOT NULL,
                undone INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS audit_events (
                id TEXT PRIMARY KEY,
                action TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                processing_mode TEXT NOT NULL,
                timestamp REAL NOT NULL,
                detail TEXT NOT NULL
            );
            """
        )
    }

    private func executeScript(_ sql: String) throws {
        guard let database else { throw SQLiteStoreError.queryFailed("database is closed") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? lastError
            if let errorMessage { sqlite3_free(errorMessage) }
            throw SQLiteStoreError.queryFailed(message)
        }
    }

    private func session(from statement: OpaquePointer) throws -> Session {
        let id = columnText(statement, index: 0) ?? UUID().uuidString
        let provider = ProviderID(rawValue: columnText(statement, index: 1) ?? "") ?? .codex
        let status = AgentStatus(rawValue: columnText(statement, index: 3) ?? "") ?? .unknown
        let confidence = Confidence(rawValue: columnText(statement, index: 4) ?? "") ?? .low
        let source = EvidenceSource(rawValue: columnText(statement, index: 5) ?? "") ?? .inferred
        let lastActivity = Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))
        let evidence = SessionStatusEvidence(
            status: status,
            confidence: confidence,
            source: source,
            observedAt: lastActivity,
            explanation: columnText(statement, index: 6) ?? "No explanation available."
        )
        let artifacts: [ContextArtifact]
        if let text = columnText(statement, index: 16), let data = text.data(using: .utf8) {
            artifacts = (try? decoder.decode([ContextArtifact].self, from: data)) ?? []
        } else {
            artifacts = []
        }
        let context = SessionContext(
            workingDirectory: columnText(statement, index: 9),
            repositoryPath: columnText(statement, index: 10),
            worktreePath: columnText(statement, index: 11),
            branch: columnText(statement, index: 12),
            commit: columnText(statement, index: 13)
        )
        let title = SessionTitleNormalizer.normalize(
            columnText(statement, index: 2) ?? "Untitled session",
            workingDirectory: context.workingDirectory
        )
        let sessionID = id
        let events = try query(
            "SELECT id, timestamp, type, role, text, raw_json FROM session_events WHERE session_id = ? ORDER BY timestamp",
            bindings: [.text(sessionID)]
        ) { eventStatement in
            SessionEvent(
                id: columnText(eventStatement, index: 0) ?? UUID().uuidString,
                sessionID: sessionID,
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(eventStatement, 1)),
                type: columnText(eventStatement, index: 2) ?? "event",
                role: columnText(eventStatement, index: 3),
                text: columnText(eventStatement, index: 4) ?? "",
                rawJSON: columnText(eventStatement, index: 5)
            )
        }
        return Session(
            id: id,
            provider: provider,
            title: title,
            status: status,
            statusEvidence: evidence,
            startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
            lastActivityAt: lastActivity,
            context: context,
            transcript: columnText(statement, index: 14) ?? "",
            sourceReference: columnText(statement, index: 15) ?? "",
            events: events,
            artifacts: artifacts
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        guard let string = String(data: try encoder.encode(value), encoding: .utf8) else {
            throw SQLiteStoreError.encodingFailed
        }
        return string
    }

    private func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws {
        guard let database else { throw SQLiteStoreError.queryFailed("database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.queryFailed(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.queryFailed(lastError)
        }
    }

    private func query<T>(_ sql: String, bindings: [SQLiteBinding], row: (OpaquePointer) throws -> T) throws -> [T] {
        guard let database else { throw SQLiteStoreError.queryFailed("database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.queryFailed(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var results: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                results.append(try row(statement))
            } else if result == SQLITE_DONE {
                return results
            } else {
                throw SQLiteStoreError.queryFailed(lastError)
            }
        }
    }

    private func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .text(let value):
                if let value {
                    result = value.withCString { sqlite3_bind_text(statement, index, $0, -1, sqliteTransient) }
                } else {
                    result = sqlite3_bind_null(statement, index)
                }
            case .double(let value):
                if let value {
                    result = sqlite3_bind_double(statement, index, value)
                } else {
                    result = sqlite3_bind_null(statement, index)
                }
            case .integer(let value):
                result = sqlite3_bind_int64(statement, index, value)
            }
            guard result == SQLITE_OK else { throw SQLiteStoreError.queryFailed(lastError) }
        }
    }

    private var lastError: String {
        guard let database else { return "database is closed" }
        return String(cString: sqlite3_errmsg(database))
    }
}

private enum SQLiteBinding {
    case text(String?)
    case double(Double?)
    case integer(Int64)
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
    guard let value = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: value)
}
