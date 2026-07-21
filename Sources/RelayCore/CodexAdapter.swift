import Foundation

public struct CodexAdapter: ProviderAdapter {
    public let provider: ProviderID = .codex
    public let sessionsRoot: URL
    private let fileManager: FileManager
    private let contextResolver: GitContextResolver
    private let artifactScanner: ContextArtifactScanner

    public init(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.sessionsRoot = sessionsRoot
        self.fileManager = fileManager
        self.contextResolver = GitContextResolver()
        self.artifactScanner = ContextArtifactScanner(fileManager: fileManager)
    }

    public func detect() -> Bool {
        fileManager.fileExists(atPath: sessionsRoot.path)
    }

    public func health() -> ProviderHealth {
        let executable = ExecutableLocator.find(named: "codex")
        let available = detect()
        let capabilities: Set<ProviderCapability> = available
            ? [.detection, .historicalImport, .statusInference, .contextResolution, .artifactDiscovery, .resume]
            : [.detection]
        let message: String
        if available {
            message = executable == nil
                ? "Local session data is available; executable path was not resolved."
                : "Codex session data is available."
        } else {
            message = "No Codex session directory was found at the configured path."
        }

        return ProviderHealth(
            provider: .codex,
            executablePath: executable,
            dataSourcePath: sessionsRoot.path,
            version: nil,
            isAvailable: available,
            capabilities: capabilities,
            message: message
        )
    }

    public func importSessions(since: Date? = nil) throws -> [ImportedSession] {
        guard detect() else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var imports: [ImportedSession] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }
            guard let modifiedAt = values.contentModificationDate else { continue }
            if let since, modifiedAt <= since { continue }
            if let imported = try CodexSessionParser(fileManager: fileManager).parse(fileURL: url, modifiedAt: modifiedAt, adapter: self) {
                imports.append(imported)
            }
        }
        return imports.sorted { $0.session.lastActivityAt < $1.session.lastActivityAt }
    }

    public func inferStatus(for session: Session) -> SessionStatusEvidence {
        StatusInference.infer(events: session.events)
    }

    public func resolveContext(for workingDirectory: String?) -> SessionContext {
        contextResolver.resolve(workingDirectory: workingDirectory)
    }

    public func discoverArtifacts(for context: SessionContext) -> [ContextArtifact] {
        artifactScanner.scan(context: context, provider: .codex)
    }

    public func resumeAction(for session: Session) -> ResumeAction? {
        guard let path = session.context.worktreePath ?? session.context.workingDirectory else { return nil }
        let slug = path
            .split(separator: "/")
            .suffix(2)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "-")
        return .tmux(path: path, sessionName: "relay-\(slug)")
    }
}

public struct ClaudeCodeAdapter: ProviderAdapter {
    public let provider: ProviderID = .claudeCode
    public let sessionsRoot: URL
    private let fileManager: FileManager

    public init(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.sessionsRoot = sessionsRoot
        self.fileManager = fileManager
    }

    public func detect() -> Bool {
        fileManager.fileExists(atPath: sessionsRoot.path)
    }

    public func health() -> ProviderHealth {
        ProviderHealth(
            provider: .claudeCode,
            executablePath: ExecutableLocator.find(named: "claude"),
            dataSourcePath: sessionsRoot.path,
            isAvailable: false,
            capabilities: detect() ? [.detection] : [],
            message: detect()
                ? "Claude data was detected; the adapter is queued after Codex validation."
                : "No Claude Code project data was found at the configured path."
        )
    }

    public func importSessions(since: Date? = nil) throws -> [ImportedSession] {
        []
    }

    public func inferStatus(for session: Session) -> SessionStatusEvidence {
        StatusInference.infer(events: session.events)
    }

    public func resolveContext(for workingDirectory: String?) -> SessionContext {
        GitContextResolver().resolve(workingDirectory: workingDirectory)
    }

    public func discoverArtifacts(for context: SessionContext) -> [ContextArtifact] {
        ContextArtifactScanner(fileManager: fileManager).scan(context: context, provider: .claudeCode)
    }

    public func resumeAction(for session: Session) -> ResumeAction? {
        guard let path = session.context.worktreePath ?? session.context.workingDirectory else { return nil }
        return .terminal(path: path)
    }
}

public struct CodexSessionParser {
    public init(fileManager: FileManager = .default) {}

    public func parse(
        fileURL: URL,
        modifiedAt: Date,
        adapter: CodexAdapter
    ) throws -> ImportedSession? {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let fallbackDate = modifiedAt
        let sessionID = fileURL.deletingPathExtension().lastPathComponent
        var events: [SessionEvent] = []
        var workingDirectory: String?
        var title: String?

        for (index, line) in contents.split(whereSeparator: \.isNewline).enumerated() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                  let dictionary = object as? [String: Any] else {
                continue
            }

            let timestamp = DateParser.date(from: value(in: dictionary, keys: ["timestamp", "created_at", "createdAt"])) ?? fallbackDate
            let type = value(in: dictionary, keys: ["type", "event_type", "eventType", "kind"]) ?? "event"
            let role = value(in: dictionary, keys: ["role", "author", "source"])
            let text = textValue(in: dictionary)
            let eventID = value(in: dictionary, keys: ["id", "event_id", "eventId"]) ?? "\(sessionID)-\(index)"

            if workingDirectory == nil {
                workingDirectory = pathValue(in: dictionary, keys: ["cwd", "working_directory", "workingDirectory", "workdir"])
            }
            if title == nil, role?.lowercased() == "user", !text.isEmpty {
                title = text.split(separator: "\n", maxSplits: 1).first.map(String.init)
            }

            events.append(SessionEvent(
                id: eventID,
                sessionID: sessionID,
                timestamp: timestamp,
                type: type,
                role: role,
                text: text,
                rawJSON: String(data: try JSONSerialization.data(withJSONObject: dictionary), encoding: .utf8)
            ))
        }

        guard !events.isEmpty else { return nil }
        events.sort { $0.timestamp < $1.timestamp }
        let context = adapter.resolveContext(for: workingDirectory)
        let statusEvidence = adapter.inferStatus(for: Session(
            id: sessionID,
            provider: .codex,
            title: title ?? "Codex session",
            status: .discovered,
            statusEvidence: SessionStatusEvidence(
                status: .discovered,
                confidence: .low,
                source: .file,
                observedAt: fallbackDate,
                explanation: "Parsing session data."
            ),
            startedAt: events[0].timestamp,
            lastActivityAt: events.last?.timestamp ?? fallbackDate,
            context: context,
            transcript: events.map(\.text).joined(separator: "\n"),
            sourceReference: fileURL.path,
            events: events
        ))
        let session = Session(
            id: sessionID,
            provider: .codex,
            title: title ?? "Codex session",
            status: statusEvidence.status,
            statusEvidence: statusEvidence,
            startedAt: events[0].timestamp,
            lastActivityAt: events.last?.timestamp ?? fallbackDate,
            context: context,
            transcript: events.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n"),
            sourceReference: fileURL.path,
            events: events,
            artifacts: adapter.discoverArtifacts(for: context)
        )
        let transition = StatusTransition(
            sessionID: sessionID,
            previous: nil,
            current: statusEvidence.status,
            evidence: statusEvidence
        )
        return ImportedSession(session: session, transitions: [transition], sourceModifiedAt: modifiedAt)
    }

    private func value(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let string = dictionary[key] as? String, !string.isEmpty { return string }
            if let number = dictionary[key] as? NSNumber { return number.stringValue }
        }
        return nil
    }

    private func pathValue(in dictionary: [String: Any], keys: [String]) -> String? {
        guard let value = value(in: dictionary, keys: keys), value.hasPrefix("/") else { return nil }
        return value
    }

    private func textValue(in dictionary: [String: Any]) -> String {
        let directKeys = ["text", "message", "prompt", "command", "content", "summary"]
        for key in directKeys {
            if let string = dictionary[key] as? String { return string }
            if let nested = dictionary[key] as? [String: Any], let text = textValue(in: nested) as String?, !text.isEmpty {
                return text
            }
            if let values = dictionary[key] as? [[String: Any]] {
                let text = values.compactMap { textValue(in: $0) }.filter { !$0.isEmpty }.joined(separator: "\n")
                if !text.isEmpty { return text }
            }
        }
        return ""
    }
}

private enum DateParser {
    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        if let number = Double(value) {
            return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1_000 : number)
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

private enum ExecutableLocator {
    static func find(named name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/\(name)").path
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
