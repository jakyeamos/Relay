import Foundation

public struct RelayConfiguration: Codable, Sendable, Equatable {
    public var codexSessionsPath: String
    public var claudeProjectsPath: String
    public var tmuxCommandTemplate: String
    public var editorCommandTemplate: String

    public init(
        codexSessionsPath: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions").path,
        claudeProjectsPath: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects").path,
        tmuxCommandTemplate: String = "tmux new-session -Ad -s {session} -c {path}",
        editorCommandTemplate: String = "cd {path} && nvim"
    ) {
        self.codexSessionsPath = codexSessionsPath
        self.claudeProjectsPath = claudeProjectsPath
        self.tmuxCommandTemplate = tmuxCommandTemplate
        self.editorCommandTemplate = editorCommandTemplate
    }

    public static var `default`: RelayConfiguration { RelayConfiguration() }

    public static func configurationURL(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Relay/config.json")
    }

    public static func load(fileManager: FileManager = .default) -> RelayConfiguration {
        let url = configurationURL(fileManager: fileManager)
        guard let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(RelayConfiguration.self, from: data) else {
            return .default
        }
        return configuration
    }

    public func save(fileManager: FileManager = .default) throws {
        let url = Self.configurationURL(fileManager: fileManager)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.output.encode(self)
        try data.write(to: url, options: [.atomic])
    }

    public func makeAdapters(fileManager: FileManager = .default) -> [any ProviderAdapter] {
        [
            CodexAdapter(sessionsRoot: URL(fileURLWithPath: codexSessionsPath), fileManager: fileManager),
            ClaudeCodeAdapter(sessionsRoot: URL(fileURLWithPath: claudeProjectsPath), fileManager: fileManager)
        ]
    }
}

private extension JSONEncoder {
    static var output: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
