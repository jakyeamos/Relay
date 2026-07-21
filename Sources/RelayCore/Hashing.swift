import CryptoKit
import Foundation

public enum ContentHasher {
    public static func hash(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func hash(string: String) -> String {
        hash(data: Data(string.utf8))
    }
}
