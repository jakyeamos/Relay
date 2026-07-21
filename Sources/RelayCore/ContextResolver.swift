import Foundation

public struct GitContextResolver {
    public init() {}

    public func resolve(workingDirectory: String?) -> SessionContext {
        guard let workingDirectory, !workingDirectory.isEmpty else {
            return SessionContext()
        }

        let directory = URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
        let repositoryPath = runGit(arguments: ["-C", directory, "rev-parse", "--show-toplevel"])
        let worktreePath = runGit(arguments: ["-C", directory, "rev-parse", "--show-toplevel"])
        let branch = runGit(arguments: ["-C", directory, "branch", "--show-current"])
        let commit = runGit(arguments: ["-C", directory, "rev-parse", "HEAD"])

        return SessionContext(
            workingDirectory: directory,
            repositoryPath: repositoryPath,
            worktreePath: worktreePath ?? directory,
            branch: branch,
            commit: commit
        )
    }

    private func runGit(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ContextArtifactScanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(context: SessionContext, provider: ProviderID) -> [ContextArtifact] {
        var paths: [(String, String, String)] = []

        if let repositoryPath = context.repositoryPath {
            paths.append((repositoryPath + "/AGENTS.md", "instruction", "repository"))
            paths.append((repositoryPath + "/CLAUDE.md", "instruction", "repository"))
            paths.append((repositoryPath + "/.codex/instructions.md", "instruction", "provider"))
        }

        if let workingDirectory = context.workingDirectory {
            paths.append((workingDirectory + "/AGENTS.md", "instruction", "directory"))
            paths.append((workingDirectory + "/.cursorrules", "instruction", "provider"))
        }

        let home = fileManager.homeDirectoryForCurrentUser.path
        paths.append((home + "/AGENTS.md", "instruction", "global"))
        paths.append((home + "/.codex/AGENTS.md", "instruction", "provider"))

        return paths.compactMap { path, kind, scope in
            let logicalURL = URL(fileURLWithPath: path)
            guard fileManager.fileExists(atPath: logicalURL.path) else { return nil }
            let physicalURL = logicalURL.resolvingSymlinksInPath()
            let hash = (try? Data(contentsOf: physicalURL)).map(ContentHasher.hash(data:))
            return ContextArtifact(
                logicalPath: logicalURL.path,
                physicalPath: physicalURL.path,
                kind: kind,
                scope: scope + ":" + provider.rawValue,
                contentHash: hash
            )
        }
    }
}
