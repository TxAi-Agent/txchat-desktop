enum DictationState: Equatable, Sendable {
    case unavailable(DictationAvailability)
    case idle
    case starting
    case listening(TranscriptSnapshot)
    case finalizing(TranscriptSnapshot)
    case organizing
    case inserting(text: String)
    case resultFallback(text: String)
    case completed
    case failed(DictationFailure)
}
