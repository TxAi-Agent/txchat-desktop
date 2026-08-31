import Foundation

struct DictionaryMarkdownCodec: Sendable {
    static let schemaMarker = "<!-- txchat-dictionary-schema: 1 -->"
    static let header = "| wrong | correct | enabled |"
    static let separator = "| --- | --- | --- |"

    func decode(_ data: Data) throws -> TxChatDictionaryDocument {
        guard data.count <= TxChatDictionaryLimits.maximumFileBytes else {
            throw DictionaryMarkdownError.oversizedFile
        }
        guard var markdown = String(data: data, encoding: .utf8) else {
            throw DictionaryMarkdownError.invalidUTF8
        }
        if markdown.first == "\u{FEFF}" {
            markdown.removeFirst()
        }

        let lines = markdown.components(separatedBy: .newlines)
        let schemaVersion = try parseSchemaVersion(lines)
        guard schemaVersion == TxChatDictionaryLimits.schemaVersion else {
            throw DictionaryMarkdownError.unsupportedSchema(schemaVersion)
        }
        guard let headerIndex = lines.firstIndex(where: {
            normalizedTableLine($0) == Self.header
        }), headerIndex + 1 < lines.count,
        normalizedTableLine(lines[headerIndex + 1]) == Self.separator else {
            throw DictionaryMarkdownError.invalidStructure
        }

        var entries: [TxChatDictionaryEntry] = []
        var seenWrong = Set<String>()
        var skippedLineCount = 0

        for rawLine in lines.dropFirst(headerIndex + 2) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard !trimmed.hasPrefix("<!--") else { continue }
            guard let columns = parseColumns(from: trimmed),
                  columns.count == 3,
                  let isEnabled = parseBoolean(columns[2]) else {
                skippedLineCount += 1
                continue
            }
            let entry = TxChatDictionaryEntry(
                wrong: columns[0],
                correct: columns[1],
                isEnabled: isEnabled
            )
            guard entry.isValid, !seenWrong.contains(entry.wrong),
                  entries.count < TxChatDictionaryLimits.maximumEntryCount else {
                skippedLineCount += 1
                continue
            }
            entries.append(entry)
            seenWrong.insert(entry.wrong)
        }

        return TxChatDictionaryDocument(
            schemaVersion: schemaVersion,
            entries: entries,
            skippedLineCount: skippedLineCount
        )
    }

    func encode(_ entries: [TxChatDictionaryEntry]) throws -> Data {
        guard entries.count <= TxChatDictionaryLimits.maximumEntryCount else {
            throw DictionaryMarkdownError.tooManyEntries
        }
        var seenWrong = Set<String>()
        for (index, entry) in entries.enumerated() {
            guard entry.isValid else {
                throw DictionaryMarkdownError.invalidEntry(index: index)
            }
            guard seenWrong.insert(entry.wrong).inserted else {
                throw DictionaryMarkdownError.duplicateWrong(index: index)
            }
        }

        var lines = [
            Self.schemaMarker,
            "",
            Self.header,
            Self.separator,
        ]
        lines.append(contentsOf: entries.map { entry in
            "| \(escape(entry.wrong)) | \(escape(entry.correct)) | \(entry.isEnabled) |"
        })
        let markdown = lines.joined(separator: "\n") + "\n"
        guard let data = markdown.data(using: .utf8) else {
            throw DictionaryMarkdownError.encodingFailed
        }
        guard data.count <= TxChatDictionaryLimits.maximumFileBytes else {
            throw DictionaryMarkdownError.oversizedFile
        }
        return data
    }

    private func parseSchemaVersion(_ lines: [String]) throws -> Int {
        let prefix = "<!-- txchat-dictionary-schema:"
        guard let line = lines.first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
        }) else {
            throw DictionaryMarkdownError.missingSchema
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("-->"),
              let colon = trimmed.firstIndex(of: ":") else {
            throw DictionaryMarkdownError.missingSchema
        }
        let valueStart = trimmed.index(after: colon)
        let valueEnd = trimmed.index(trimmed.endIndex, offsetBy: -3)
        let value = trimmed[valueStart..<valueEnd]
            .trimmingCharacters(in: .whitespaces)
        guard let version = Int(value) else {
            throw DictionaryMarkdownError.missingSchema
        }
        return version
    }

    private func normalizedTableLine(_ line: String) -> String {
        guard let columns = parseColumns(from: line) else {
            return line.trimmingCharacters(in: .whitespaces)
        }
        return "| " + columns.map {
            $0.trimmingCharacters(in: .whitespaces)
        }.joined(separator: " | ") + " |"
    }

    private func parseColumns(from line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == "|", trimmed.last == "|" else { return nil }

        var columns: [String] = []
        var value = ""
        var isEscaping = false
        for character in trimmed.dropFirst().dropLast() {
            if isEscaping {
                if character == "|" || character == "\\" {
                    value.append(character)
                } else {
                    value.append("\\")
                    value.append(character)
                }
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else if character == "|" {
                columns.append(removingMarkdownPadding(from: value))
                value = ""
            } else {
                value.append(character)
            }
        }
        if isEscaping {
            value.append("\\")
        }
        columns.append(removingMarkdownPadding(from: value))
        return columns
    }

    private func removingMarkdownPadding(from value: String) -> String {
        var content = value
        if content.first == " " {
            content.removeFirst()
        }
        if content.last == " " {
            content.removeLast()
        }
        return content
    }

    private func parseBoolean(_ value: String) -> Bool? {
        switch value {
        case "true": true
        case "false": false
        default: nil
        }
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
    }
}
