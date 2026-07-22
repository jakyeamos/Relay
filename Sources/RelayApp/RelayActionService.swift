import AppKit
import Foundation
import RelayCore

enum RelayActionError: Error, LocalizedError {
    case noContext
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noContext: return "This session does not have a mapped working directory."
        case .commandFailed(let message): return message
        }
    }
}

final class RelayActionService {
    private let configuration: RelayConfiguration

    init(configuration: RelayConfiguration = .load()) {
        self.configuration = configuration
    }

    func resume(session: Session) throws {
        guard let path = session.context.worktreePath ?? session.context.workingDirectory else {
            throw RelayActionError.noContext
        }
        let tmuxName = "relay-" + path.split(separator: "/").suffix(2).joined(separator: "-")
        let tmuxCommand = configuration.tmuxCommandTemplate
            .replacingOccurrences(of: "{session}", with: shellQuote(tmuxName))
            .replacingOccurrences(of: "{path}", with: shellQuote(path))
        do {
            try runShell(tmuxCommand)
        } catch {
            let editorCommand = configuration.editorCommandTemplate
                .replacingOccurrences(of: "{path}", with: shellQuote(path))
            try openTerminal(command: editorCommand)
        }
    }

    func reveal(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw RelayActionError.commandFailed("The context path no longer exists: \(path)")
        }
        let url = URL(fileURLWithPath: path)
        let container = url.hasDirectoryPath ? path : url.deletingLastPathComponent().path
        guard NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: container) else {
            throw RelayActionError.commandFailed("Finder could not reveal \(path).")
        }
    }

    func openTerminal(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw RelayActionError.commandFailed("The context path no longer exists: \(path)")
        }
        try openTerminal(command: "cd \(shellQuote(path))")
    }

    private func openTerminal(command: String) throws {
        let escapedCommand = command.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\" to do script \"\(escapedCommand)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Terminal could not be opened."
            throw RelayActionError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func runShell(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", command]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Command failed."
            throw RelayActionError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
