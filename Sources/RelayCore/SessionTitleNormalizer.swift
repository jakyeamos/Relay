import Foundation

public enum SessionTitleNormalizer {
    public static func normalize(_ rawTitle: String, workingDirectory: String? = nil) -> String {
        var title = rawTitle
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while title.range(of: "^#{1,6}\\s+", options: .regularExpression) != nil {
            title = title.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
        }

        if let workingDirectory {
            let paths = Set([
                workingDirectory,
                URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
            ])
            for path in paths where !path.isEmpty {
                for preposition in [" for ", " in ", " at "] {
                    let suffix = "\(preposition)\(path)"
                    if title.hasSuffix(suffix) {
                        title.removeLast(suffix.count)
                        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }

        if title.first == "<", title.last == ">" {
            let identifier = String(title.dropFirst().dropLast())
                .split(whereSeparator: { $0.isWhitespace })
                .first
                .map(String.init) ?? ""
            if !identifier.isEmpty,
               identifier.allSatisfy({ $0.isLetter || $0.isNumber || "_.-".contains($0) }) {
                title = humanizeIdentifier(identifier)
            }
        }

        title = title.trimmingCharacters(in: CharacterSet(charactersIn: ":;"))

        let letters = title.filter { $0.isLetter }
        let wordCount = title.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount > 1, !letters.isEmpty, letters.allSatisfy({ $0.isUppercase }) {
            title = title.lowercased()
        }

        if title.lowercased().hasPrefix("please ") {
            title = String(title.dropFirst("please ".count))
        }
        if let first = title.first, first.isLowercase {
            title = first.uppercased() + title.dropFirst()
        }

        guard !title.isEmpty else { return "Untitled session" }
        let maximumLength = 72
        guard title.count > maximumLength else { return title }
        let prefix = String(title.prefix(maximumLength - 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)…"
    }

    private static func humanizeIdentifier(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .enumerated()
            .map { index, word in
                let lowercase = word.lowercased()
                guard let first = lowercase.first else { return "" }
                return index == 0
                    ? first.uppercased() + lowercase.dropFirst()
                    : lowercase
            }
            .joined(separator: " ")
    }
}
