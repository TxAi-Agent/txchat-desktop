import Foundation

enum TxChatTextDocumentKind: String, CaseIterable, Identifiable, Sendable {
    case serviceTerms = "service-terms"
    case privacyNotice = "privacy-notice"
    case faq
    case about

    var id: String { rawValue }

    func title(language: TxChatLanguage) -> String {
        switch self {
        case .serviceTerms:
            return language.select("服务条款", "Terms of Service")
        case .privacyNotice:
            return language.select("隐私说明", "Privacy Notice")
        case .faq:
            return language.select(
                "常见问题",
                "Frequently Asked Questions"
            )
        case .about:
            return language.select("关于 TxChat", "About TxChat")
        }
    }

    fileprivate var resourceName: String {
        "txchat-\(rawValue)"
    }
}

enum TxChatTextBlock: Equatable, Sendable {
    case heading(String)
    case paragraph(String)

    var text: String {
        switch self {
        case .heading(let value), .paragraph(let value):
            return value
        }
    }
}

struct TxChatTextDocument: Equatable, Identifiable, Sendable {
    let kind: TxChatTextDocumentKind
    let language: TxChatLanguage
    let title: String
    let blocks: [TxChatTextBlock]

    var id: String {
        "\(kind.rawValue)-\(language.rawValue)"
    }

    var plainText: String {
        blocks.map(\.text).joined(separator: "\n\n")
    }
}

enum TxChatTextDocumentError: Error, Equatable {
    case resourceMissing(String)
    case unreadableResource(String)
    case emptyDocument
}

struct TxChatTextDocumentParser {
    func parse(
        kind: TxChatTextDocumentKind,
        language: TxChatLanguage,
        source: String
    ) throws -> TxChatTextDocument {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [TxChatTextBlock] = []
        var paragraphLines: [String] = []

        func trimmed(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func appendParagraph() {
            let value = trimmed(paragraphLines.joined(separator: "\n"))
            if !value.isEmpty {
                blocks.append(.paragraph(value))
            }
            paragraphLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let value = trimmed(line)
            if value.isEmpty {
                appendParagraph()
            } else if value.hasPrefix("## ") {
                appendParagraph()
                let heading = trimmed(String(value.dropFirst(3)))
                if !heading.isEmpty {
                    blocks.append(.heading(heading))
                }
            } else if value.hasPrefix("# ") {
                appendParagraph()
            } else {
                paragraphLines.append(value)
            }
        }
        appendParagraph()

        guard !blocks.isEmpty else {
            throw TxChatTextDocumentError.emptyDocument
        }
        return TxChatTextDocument(
            kind: kind,
            language: language,
            title: kind.title(language: language),
            blocks: blocks
        )
    }
}

struct BundledTxChatTextDocumentRepository {
    let bundle: Bundle
    private let parser: TxChatTextDocumentParser

    init(
        bundle: Bundle = .main,
        parser: TxChatTextDocumentParser = TxChatTextDocumentParser()
    ) {
        self.bundle = bundle
        self.parser = parser
    }

    func document(
        kind: TxChatTextDocumentKind,
        language: TxChatLanguage
    ) throws -> TxChatTextDocument {
        let resourceName = "\(kind.resourceName)-\(language.rawValue)"
        guard let url = bundle.url(
            forResource: resourceName,
            withExtension: "md"
        ) else {
            throw TxChatTextDocumentError.resourceMissing(resourceName)
        }
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw TxChatTextDocumentError.unreadableResource(resourceName)
        }
        return try parser.parse(
            kind: kind,
            language: language,
            source: source
        )
    }
}
