struct TranscriptSnapshot: Equatable, Sendable {
    let partialText: String

    static let empty = TranscriptSnapshot(partialText: "")
}
