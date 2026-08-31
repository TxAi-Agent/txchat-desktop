struct DictionaryReplacer: Sendable {
    private struct Node: Sendable {
        var children: [Unicode.Scalar: Int] = [:]
        var replacement: String?
    }

    private let nodes: [Node]

    init<S: Sequence>(entries: S) where S.Element == TxChatDictionaryEntry {
        var nodes = [Node()]
        for entry in entries where entry.isEnabled && entry.isValid {
            var nodeIndex = 0
            for scalar in entry.wrong.unicodeScalars {
                if let existing = nodes[nodeIndex].children[scalar] {
                    nodeIndex = existing
                } else {
                    let childIndex = nodes.count
                    nodes.append(Node())
                    nodes[nodeIndex].children[scalar] = childIndex
                    nodeIndex = childIndex
                }
            }
            if nodes[nodeIndex].replacement == nil {
                nodes[nodeIndex].replacement = entry.correct
            }
        }
        self.nodes = nodes
    }

    func replace(_ text: String) -> String {
        guard nodes.count > 1, !text.isEmpty else { return text }

        let scalars = text.unicodeScalars
        var sourceIndex = scalars.startIndex
        var output = ""
        output.reserveCapacity(text.utf8.count)

        while sourceIndex < scalars.endIndex {
            var scanIndex = sourceIndex
            var nodeIndex = 0
            var longestMatch: (end: String.UnicodeScalarView.Index, value: String)?

            while scanIndex < scalars.endIndex,
                  let childIndex = nodes[nodeIndex].children[scalars[scanIndex]] {
                nodeIndex = childIndex
                scanIndex = scalars.index(after: scanIndex)
                if let replacement = nodes[nodeIndex].replacement {
                    longestMatch = (scanIndex, replacement)
                }
            }

            if let longestMatch {
                output.append(longestMatch.value)
                sourceIndex = longestMatch.end
            } else {
                output.unicodeScalars.append(scalars[sourceIndex])
                sourceIndex = scalars.index(after: sourceIndex)
            }
        }
        return output
    }
}
