import Foundation

public struct RelayWorkspace: Codable, Sendable, Equatable, Identifiable {
    public static let unassignedID = "unassigned"

    public let id: String
    public var name: String
    public let canonicalRepositoryPath: String?
    public let fallbackDirectory: String?
    public var isPinned: Bool
    public var sortOrder: Int
    public let createdAt: Date
    public var lastOpenedAt: Date?
    public var isHidden: Bool

    public init(
        id: String? = nil,
        name: String,
        canonicalRepositoryPath: String? = nil,
        fallbackDirectory: String? = nil,
        isPinned: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        isHidden: Bool = false
    ) {
        self.id = id ?? Self.stableID(for: canonicalRepositoryPath ?? fallbackDirectory ?? name)
        self.name = name
        self.canonicalRepositoryPath = canonicalRepositoryPath
        self.fallbackDirectory = fallbackDirectory
        self.isPinned = isPinned
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.isHidden = isHidden
    }

    public static let unassigned = RelayWorkspace(
        id: unassignedID,
        name: "Unassigned",
        createdAt: Date(timeIntervalSince1970: 0)
    )

    public static func stableID(for path: String) -> String {
        "workspace-\(ContentHasher.hash(string: path))"
    }
}

public struct WorkspaceSummary: Codable, Sendable, Equatable, Identifiable {
    public let workspace: RelayWorkspace
    public let sessionCount: Int
    public let activeCount: Int
    public let attentionCount: Int
    public let latestActivityAt: Date?
    public let associatedWorktrees: [String]

    public var id: String { workspace.id }

    public init(
        workspace: RelayWorkspace,
        sessionCount: Int,
        activeCount: Int,
        attentionCount: Int,
        latestActivityAt: Date?,
        associatedWorktrees: [String]
    ) {
        self.workspace = workspace
        self.sessionCount = sessionCount
        self.activeCount = activeCount
        self.attentionCount = attentionCount
        self.latestActivityAt = latestActivityAt
        self.associatedWorktrees = associatedWorktrees
    }
}

public enum SessionSortOrder: String, Codable, CaseIterable, Sendable {
    case recent
    case oldest
    case title
}

public struct SessionQuery: Sendable, Equatable {
    public var workspaceID: String?
    public var text: String?
    public var provider: ProviderID?
    public var statuses: Set<AgentStatus>
    public var sortOrder: SessionSortOrder
    public var limit: Int

    public init(
        workspaceID: String? = nil,
        text: String? = nil,
        provider: ProviderID? = nil,
        statuses: Set<AgentStatus> = [],
        sortOrder: SessionSortOrder = .recent,
        limit: Int = 500
    ) {
        self.workspaceID = workspaceID
        self.text = text
        self.provider = provider
        self.statuses = statuses
        self.sortOrder = sortOrder
        self.limit = max(1, min(limit, 2_000))
    }
}

public struct WorkspaceResolver: Sendable {
    public init() {}

    public func workspace(for session: Session, now: Date = Date()) -> RelayWorkspace {
        let repositoryPath = normalizedPath(session.context.repositoryPath)
        let fallbackDirectory = normalizedPath(session.context.worktreePath ?? session.context.workingDirectory)
        let keyPath = repositoryPath ?? fallbackDirectory
        guard let keyPath else { return .unassigned }

        return RelayWorkspace(
            name: Self.displayName(for: keyPath),
            canonicalRepositoryPath: repositoryPath,
            fallbackDirectory: fallbackDirectory,
            createdAt: now
        )
    }

    public func workspaceID(for session: Session) -> String {
        workspace(for: session, now: Date(timeIntervalSince1970: 0)).id
    }

    public func summaries(
        sessions: [Session],
        storedWorkspaces: [RelayWorkspace] = [],
        now: Date = Date()
    ) -> [WorkspaceSummary] {
        let storedByID = Dictionary(uniqueKeysWithValues: storedWorkspaces.map { ($0.id, $0) })
        var grouped: [String: [Session]] = [:]
        for session in sessions {
            grouped[workspaceID(for: session), default: []].append(session)
        }

        var summaries = grouped.map { id, groupedSessions in
            let discovered = workspace(for: groupedSessions[0], now: now)
            let workspace = storedByID[id] ?? discovered
            let worktrees = Set(groupedSessions.compactMap { normalizedPath($0.context.worktreePath) }).sorted()
            let activeCount = groupedSessions.filter { [.running, .waiting, .approvalRequired].contains($0.status) }.count
            let attentionCount = groupedSessions.filter { [.waiting, .approvalRequired].contains($0.status) }.count
            return WorkspaceSummary(
                workspace: workspace,
                sessionCount: groupedSessions.count,
                activeCount: activeCount,
                attentionCount: attentionCount,
                latestActivityAt: groupedSessions.map(\.lastActivityAt).max(),
                associatedWorktrees: worktrees
            )
        }

        for workspace in storedWorkspaces where grouped[workspace.id] == nil && !workspace.isHidden {
            summaries.append(WorkspaceSummary(
                workspace: workspace,
                sessionCount: 0,
                activeCount: 0,
                attentionCount: 0,
                latestActivityAt: nil,
                associatedWorktrees: []
            ))
        }

        return summaries
            .filter { !$0.workspace.isHidden }
            .sorted {
                if $0.workspace.isPinned != $1.workspace.isPinned { return $0.workspace.isPinned }
                if $0.workspace.sortOrder != $1.workspace.sortOrder { return $0.workspace.sortOrder < $1.workspace.sortOrder }
                return ($0.latestActivityAt ?? .distantPast) > ($1.latestActivityAt ?? .distantPast)
            }
    }

    public func matches(_ session: Session, workspaceID: String?) -> Bool {
        guard let workspaceID else { return true }
        return self.workspaceID(for: session) == workspaceID
    }

    public func normalizedPath(_ path: String?) -> String? {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func displayName(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }
}
