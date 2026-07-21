import Foundation

public enum FileTransactionError: Error, LocalizedError {
    case noPathGrant(String)
    case targetIsDirectory(String)
    case staleTarget(String)
    case unsupportedOperation(FileOperationKind)
    case transactionFailed(String)
    case undoConflict(String)

    public var errorDescription: String? {
        switch self {
        case .noPathGrant(let path): return "The selected path was not granted for this transaction: \(path)"
        case .targetIsDirectory(let path): return "Relay will not replace a directory: \(path)"
        case .staleTarget(let path): return "The target changed after the suggestion was created: \(path)"
        case .unsupportedOperation(let operation): return "Unsupported file operation: \(operation.rawValue)"
        case .transactionFailed(let message): return "Relay could not complete the transaction: \(message)"
        case .undoConflict(let path): return "The applied file changed, so Relay will not undo it automatically: \(path)"
        }
    }
}

public struct PathGrant: Sendable, Equatable {
    public let paths: Set<String>

    public init(paths: Set<String>) {
        self.paths = Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
    }

    public func contains(_ path: String) -> Bool {
        paths.contains(URL(fileURLWithPath: path).standardizedFileURL.path)
    }
}

public final class FileTransactionManager: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func apply(_ suggestion: Suggestion, grant: PathGrant) throws -> FileTransactionRecord {
        guard !suggestion.operations.isEmpty else {
            throw FileTransactionError.transactionFailed("The suggestion has no file operations.")
        }

        var prepared: [(operation: FileOperation, logical: URL, physical: URL, previous: Data?, existed: Bool)] = []
        for operation in suggestion.operations {
            guard grant.contains(operation.targetPath) else {
                throw FileTransactionError.noPathGrant(operation.targetPath)
            }
            guard let proposedContent = operation.proposedContent else {
                throw FileTransactionError.unsupportedOperation(operation.kind)
            }
            let logical = URL(fileURLWithPath: operation.targetPath).standardizedFileURL
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: logical.path, isDirectory: &isDirectory)
            guard !isDirectory.boolValue else { throw FileTransactionError.targetIsDirectory(logical.path) }
            let physical = logical.resolvingSymlinksInPath()
            let previous = exists ? try Data(contentsOf: physical) : nil
            let actualHash = previous.map(ContentHasher.hash(data:))
            guard actualHash == operation.beforeHash else {
                throw FileTransactionError.staleTarget(logical.path)
            }
            guard !proposedContent.isEmpty || operation.kind != .create else {
                throw FileTransactionError.transactionFailed("A create operation must include content.")
            }
            prepared.append((operation, logical, physical, previous, exists))
        }

        var entries: [RollbackEntry] = []
        do {
            for item in prepared {
                guard let content = item.operation.proposedContent else {
                    throw FileTransactionError.unsupportedOperation(item.operation.kind)
                }
                let data = Data(content.utf8)
                try fileManager.createDirectory(at: item.physical.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: item.physical, options: [.atomic])
                entries.append(RollbackEntry(
                    logicalPath: item.logical.path,
                    physicalPath: item.physical.path,
                    previousContent: item.previous,
                    previousHash: item.previous.map(ContentHasher.hash(data:)),
                    appliedHash: ContentHasher.hash(data: data),
                    existedBefore: item.existed
                ))
            }
        } catch {
            restore(entries: entries)
            throw FileTransactionError.transactionFailed(error.localizedDescription)
        }

        return FileTransactionRecord(suggestionID: suggestion.id, entries: entries)
    }

    public func undo(_ record: FileTransactionRecord) throws -> FileTransactionRecord {
        guard !record.undone else { return record }
        var restored: [RollbackEntry] = []
        do {
            for entry in record.entries {
                let currentURL = URL(fileURLWithPath: entry.physicalPath)
                let currentData = try Data(contentsOf: currentURL)
                guard ContentHasher.hash(data: currentData) == entry.appliedHash else {
                    throw FileTransactionError.undoConflict(entry.logicalPath)
                }
                if entry.existedBefore, let previousContent = entry.previousContent {
                    try previousContent.write(to: currentURL, options: [.atomic])
                } else {
                    try fileManager.removeItem(at: currentURL)
                }
                restored.append(entry)
            }
        } catch {
            restoreApplied(entries: restored)
            if let transactionError = error as? FileTransactionError { throw transactionError }
            throw FileTransactionError.transactionFailed(error.localizedDescription)
        }
        var result = record
        result.undone = true
        return result
    }

    private func restore(entries: [RollbackEntry]) {
        for entry in entries.reversed() {
            if entry.existedBefore, let previous = entry.previousContent {
                try? previous.write(to: URL(fileURLWithPath: entry.physicalPath), options: [.atomic])
            } else {
                try? fileManager.removeItem(at: URL(fileURLWithPath: entry.physicalPath))
            }
        }
    }

    private func restoreApplied(entries: [RollbackEntry]) {
        for entry in entries.reversed() {
            let url = URL(fileURLWithPath: entry.physicalPath)
            if entry.existedBefore, let previous = entry.previousContent {
                try? previous.write(to: url, options: [.atomic])
            } else {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
