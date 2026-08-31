import CryptoKit
import Foundation

struct TextOptimizationPrompt: Encodable, Equatable, Sendable {
    let version: String
    let sha256: String
    let utf8Bytes: Int
    let content: String
}

enum BuiltInTextOptimizationPromptError: Error, Equatable {
    case invalidManifest
    case missingResource
}

enum BuiltInTextOptimizationPrompt {
    static let approvedVersion = "public-default-v1"
    static let approvedSHA256 =
        "c24a3933bfdc1d6a561d4ed6e010044964f2406b1a7b895a3c8fb2a07445096e"
    static let approvedUTF8Bytes = 167
    static let approvedCodePoints = 167
    static let approvedLineCount = 2

    static func loadCurrent(
        bundle: Bundle = .main
    ) throws -> TextOptimizationPrompt {
        guard let url = bundle.url(
            forResource: "DefaultPrompt-v5",
            withExtension: "json"
        ) else {
            throw BuiltInTextOptimizationPromptError.missingResource
        }
        return try load(data: Data(contentsOf: url))
    }

    static func load(data: Data) throws -> TextOptimizationPrompt {
        guard
            !data.isEmpty,
            data.count <= 4_096,
            let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            Set(object.keys) == [
                "version", "sha256", "utf8Bytes", "content",
            ],
            let version = object["version"] as? String,
            let sha256 = object["sha256"] as? String,
            let utf8Bytes = object["utf8Bytes"] as? Int,
            let content = object["content"] as? String,
            version == approvedVersion,
            sha256 == approvedSHA256,
            utf8Bytes == approvedUTF8Bytes,
            content.utf8.count == utf8Bytes,
            content.count == approvedCodePoints,
            digest(content) == sha256,
            isApprovedStructure(content, version: version)
        else {
            throw BuiltInTextOptimizationPromptError.invalidManifest
        }
        return TextOptimizationPrompt(
            version: version,
            sha256: sha256,
            utf8Bytes: utf8Bytes,
            content: content
        )
    }

    private static func digest(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func isApprovedStructure(
        _ content: String,
        version: String
    ) -> Bool {
        guard !content.contains("\r") else {
            return false
        }
        for scalar in content.unicodeScalars where scalar != "\n" {
            if CharacterSet.controlCharacters.contains(scalar) {
                return false
            }
        }
        let lines = content.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        return lines.count == approvedLineCount &&
            lines.first == Substring("[prompt:\(version)]") &&
            lines.allSatisfy { $0.count <= 512 }
    }
}
