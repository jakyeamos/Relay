import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case codex
    case claudeCode = "claude-code"
}

public enum ProviderCapability: String, Codable, CaseIterable, Sendable {
    case detection
    case historicalImport
    case liveWatch
    case statusInference
    case contextResolution
    case artifactDiscovery
    case usage
    case resume
}

public struct ProviderHealth: Codable, Sendable, Equatable {
    public let provider: ProviderID
    public let executablePath: String?
    public let dataSourcePath: String
    public let version: String?
    public let isAvailable: Bool
    public let capabilities: Set<ProviderCapability>
    public let message: String

    public init(
        provider: ProviderID,
        executablePath: String? = nil,
        dataSourcePath: String,
        version: String? = nil,
        isAvailable: Bool,
        capabilities: Set<ProviderCapability> = [],
        message: String
    ) {
        self.provider = provider
        self.executablePath = executablePath
        self.dataSourcePath = dataSourcePath
        self.version = version
        self.isAvailable = isAvailable
        self.capabilities = capabilities
        self.message = message
    }
}

public enum AgentStatus: String, Codable, CaseIterable, Sendable {
    case discovered
    case running
    case waiting
    case approvalRequired = "approval-required"
    case idle
    case completed
    case failed
    case abandoned
    case unknown

    public var displayName: String {
        switch self {
        case .discovered: return "Discovered"
        case .running: return "Running"
        case .waiting: return "Waiting"
        case .approvalRequired: return "Approval required"
        case .idle: return "Idle"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .abandoned: return "Abandoned"
        case .unknown: return "Unknown"
        }
    }
}

public enum Confidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

public enum EvidenceSource: String, Codable, CaseIterable, Sendable {
    case provider
    case process
    case file
    case inferred
    case manual
}

public struct SessionStatusEvidence: Codable, Sendable, Equatable {
    public let status: AgentStatus
    public let confidence: Confidence
    public let source: EvidenceSource
    public let observedAt: Date
    public let explanation: String
    public let evidenceReferences: [String]

    public init(
        status: AgentStatus,
        confidence: Confidence,
        source: EvidenceSource,
        observedAt: Date,
        explanation: String,
        evidenceReferences: [String] = []
    ) {
        self.status = status
        self.confidence = confidence
        self.source = source
        self.observedAt = observedAt
        self.explanation = explanation
        self.evidenceReferences = evidenceReferences
    }
}

public struct SessionContext: Codable, Sendable, Equatable {
    public let workingDirectory: String?
    public let repositoryPath: String?
    public let worktreePath: String?
    public let branch: String?
    public let commit: String?

    public init(
        workingDirectory: String? = nil,
        repositoryPath: String? = nil,
        worktreePath: String? = nil,
        branch: String? = nil,
        commit: String? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.repositoryPath = repositoryPath
        self.worktreePath = worktreePath
        self.branch = branch
        self.commit = commit
    }
}

public struct ContextArtifact: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let logicalPath: String
    public let physicalPath: String
    public let kind: String
    public let scope: String
    public let contentHash: String?
    public let discoveredAt: Date

    public init(
        id: String = UUID().uuidString,
        logicalPath: String,
        physicalPath: String,
        kind: String,
        scope: String,
        contentHash: String? = nil,
        discoveredAt: Date = Date()
    ) {
        self.id = id
        self.logicalPath = logicalPath
        self.physicalPath = physicalPath
        self.kind = kind
        self.scope = scope
        self.contentHash = contentHash
        self.discoveredAt = discoveredAt
    }
}

public struct SessionEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let sessionID: String
    public let timestamp: Date
    public let type: String
    public let role: String?
    public let text: String
    public let rawJSON: String?

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        timestamp: Date,
        type: String,
        role: String? = nil,
        text: String,
        rawJSON: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.type = type
        self.role = role
        self.text = text
        self.rawJSON = rawJSON
    }
}

public struct StatusTransition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let sessionID: String
    public let previous: AgentStatus?
    public let current: AgentStatus
    public let evidence: SessionStatusEvidence

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        previous: AgentStatus?,
        current: AgentStatus,
        evidence: SessionStatusEvidence
    ) {
        self.id = id
        self.sessionID = sessionID
        self.previous = previous
        self.current = current
        self.evidence = evidence
    }
}

public struct Session: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let provider: ProviderID
    public var title: String
    public var status: AgentStatus
    public var statusEvidence: SessionStatusEvidence
    public let startedAt: Date
    public var lastActivityAt: Date
    public var context: SessionContext
    public var transcript: String
    public let sourceReference: String
    public var events: [SessionEvent]
    public var artifacts: [ContextArtifact]
    public var pinned: Bool

    public init(
        id: String,
        provider: ProviderID,
        title: String,
        status: AgentStatus,
        statusEvidence: SessionStatusEvidence,
        startedAt: Date,
        lastActivityAt: Date,
        context: SessionContext,
        transcript: String,
        sourceReference: String,
        events: [SessionEvent] = [],
        artifacts: [ContextArtifact] = [],
        pinned: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.title = title
        self.status = status
        self.statusEvidence = statusEvidence
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.context = context
        self.transcript = transcript
        self.sourceReference = sourceReference
        self.events = events
        self.artifacts = artifacts
        self.pinned = pinned
    }
}

public struct ImportedSession: Sendable {
    public let session: Session
    public let transitions: [StatusTransition]
    public let sourceModifiedAt: Date

    public init(session: Session, transitions: [StatusTransition] = [], sourceModifiedAt: Date) {
        self.session = session
        self.transitions = transitions
        self.sourceModifiedAt = sourceModifiedAt
    }
}

public enum ResumeAction: Codable, Sendable, Equatable {
    case terminal(path: String)
    case tmux(path: String, sessionName: String)
    case editor(path: String, command: String)
}

public enum UsagePrecision: String, Codable, CaseIterable, Sendable {
    case providerReported = "provider-reported"
    case estimated
    case derived
    case unavailable
}

public struct UsageMetric: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let value: Double?
    public let unit: String
    public let source: String
    public let precision: UsagePrecision
    public let observedAt: Date?
    public let resetAt: Date?
    public let explanation: String

    public init(
        id: String = UUID().uuidString,
        label: String,
        value: Double?,
        unit: String,
        source: String,
        precision: UsagePrecision,
        observedAt: Date? = nil,
        resetAt: Date? = nil,
        explanation: String
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.unit = unit
        self.source = source
        self.precision = precision
        self.observedAt = observedAt
        self.resetAt = resetAt
        self.explanation = explanation
    }
}

public enum IntelligenceLane: String, Codable, CaseIterable, Sendable {
    case frictionTool = "friction_tool"
    case workflowSkill = "workflow_skill"
    case impactIdea = "impact_idea"
}

public enum CandidateLifecycle: String, Codable, CaseIterable, Sendable {
    case pending
    case reviewed
    case snoozed
    case dismissed
    case applied
    case undone
}

public struct EvidenceReference: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let sessionID: String
    public let excerpt: String
    public let timestamp: Date

    public init(id: String = UUID().uuidString, sessionID: String, excerpt: String, timestamp: Date) {
        self.id = id
        self.sessionID = sessionID
        self.excerpt = excerpt
        self.timestamp = timestamp
    }
}

public struct IntelligenceCandidate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let lane: IntelligenceLane
    public let title: String
    public let rationale: String
    public let confidence: Double
    public let evidence: [EvidenceReference]
    public let helperFamily: String
    public let latestScan: Bool
    public var lifecycle: CandidateLifecycle
    public let telemetryGuidance: String?
    public let removalGuidance: String?

    public init(
        id: String = UUID().uuidString,
        lane: IntelligenceLane,
        title: String,
        rationale: String,
        confidence: Double,
        evidence: [EvidenceReference],
        helperFamily: String,
        latestScan: Bool,
        lifecycle: CandidateLifecycle = .pending,
        telemetryGuidance: String? = nil,
        removalGuidance: String? = nil
    ) {
        self.id = id
        self.lane = lane
        self.title = title
        self.rationale = rationale
        self.confidence = confidence
        self.evidence = evidence
        self.helperFamily = helperFamily
        self.latestScan = latestScan
        self.lifecycle = lifecycle
        self.telemetryGuidance = telemetryGuidance
        self.removalGuidance = removalGuidance
    }
}

public struct IntelligenceReport: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let latestScanCandidates: [IntelligenceCandidate]
    public let pendingCandidates: [IntelligenceCandidate]
    public let helperFamilyRollups: [String: Int]
    public let implementationTelemetryGuidance: String
    public let removalCandidates: [IntelligenceCandidate]

    public init(
        generatedAt: Date = Date(),
        latestScanCandidates: [IntelligenceCandidate],
        pendingCandidates: [IntelligenceCandidate],
        helperFamilyRollups: [String: Int],
        implementationTelemetryGuidance: String,
        removalCandidates: [IntelligenceCandidate]
    ) {
        self.generatedAt = generatedAt
        self.latestScanCandidates = latestScanCandidates
        self.pendingCandidates = pendingCandidates
        self.helperFamilyRollups = helperFamilyRollups
        self.implementationTelemetryGuidance = implementationTelemetryGuidance
        self.removalCandidates = removalCandidates
    }
}

public enum SuggestionRisk: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

public enum SuggestionState: String, Codable, CaseIterable, Sendable {
    case draft
    case approved
    case applied
    case dismissed
    case snoozed
    case undone
    case conflict
}

public enum FileOperationKind: String, Codable, CaseIterable, Sendable {
    case write
    case create
    case delete
}

public struct FileOperation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: FileOperationKind
    public let targetPath: String
    public let beforeHash: String?
    public let proposedContent: String?

    public init(
        id: String = UUID().uuidString,
        kind: FileOperationKind,
        targetPath: String,
        beforeHash: String?,
        proposedContent: String?
    ) {
        self.id = id
        self.kind = kind
        self.targetPath = targetPath
        self.beforeHash = beforeHash
        self.proposedContent = proposedContent
    }
}

public struct Suggestion: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let candidateID: String
    public let title: String
    public let rationale: String
    public let confidence: Double
    public let risk: SuggestionRisk
    public let evidence: [EvidenceReference]
    public var state: SuggestionState
    public let operations: [FileOperation]

    public init(
        id: String = UUID().uuidString,
        candidateID: String,
        title: String,
        rationale: String,
        confidence: Double,
        risk: SuggestionRisk,
        evidence: [EvidenceReference],
        state: SuggestionState = .draft,
        operations: [FileOperation]
    ) {
        self.id = id
        self.candidateID = candidateID
        self.title = title
        self.rationale = rationale
        self.confidence = confidence
        self.risk = risk
        self.evidence = evidence
        self.state = state
        self.operations = operations
    }
}

public struct RollbackEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let logicalPath: String
    public let physicalPath: String
    public let previousContent: Data?
    public let previousHash: String?
    public let appliedHash: String
    public let existedBefore: Bool

    public init(
        id: String = UUID().uuidString,
        logicalPath: String,
        physicalPath: String,
        previousContent: Data?,
        previousHash: String?,
        appliedHash: String,
        existedBefore: Bool
    ) {
        self.id = id
        self.logicalPath = logicalPath
        self.physicalPath = physicalPath
        self.previousContent = previousContent
        self.previousHash = previousHash
        self.appliedHash = appliedHash
        self.existedBefore = existedBefore
    }
}

public struct FileTransactionRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let suggestionID: String
    public let createdAt: Date
    public let entries: [RollbackEntry]
    public var undone: Bool

    public init(
        id: String = UUID().uuidString,
        suggestionID: String,
        createdAt: Date = Date(),
        entries: [RollbackEntry],
        undone: Bool = false
    ) {
        self.id = id
        self.suggestionID = suggestionID
        self.createdAt = createdAt
        self.entries = entries
        self.undone = undone
    }
}

public struct AuditEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let action: String
    public let entityID: String
    public let processingMode: String
    public let timestamp: Date
    public let detail: String

    public init(
        id: String = UUID().uuidString,
        action: String,
        entityID: String,
        processingMode: String,
        timestamp: Date = Date(),
        detail: String
    ) {
        self.id = id
        self.action = action
        self.entityID = entityID
        self.processingMode = processingMode
        self.timestamp = timestamp
        self.detail = detail
    }
}

public protocol ProviderAdapter {
    var provider: ProviderID { get }
    func detect() -> Bool
    func health() -> ProviderHealth
    func importSessions(since: Date?) throws -> [ImportedSession]
    func watchSessions() -> AsyncThrowingStream<ImportedSession, Error>
    func inferStatus(for session: Session) -> SessionStatusEvidence
    func resolveContext(for workingDirectory: String?) -> SessionContext
    func discoverArtifacts(for context: SessionContext) -> [ContextArtifact]
    func usageSnapshot() -> [UsageMetric]
    func resumeAction(for session: Session) -> ResumeAction?
}

public extension ProviderAdapter {
    func watchSessions() -> AsyncThrowingStream<ImportedSession, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func usageSnapshot() -> [UsageMetric] { [] }
}
