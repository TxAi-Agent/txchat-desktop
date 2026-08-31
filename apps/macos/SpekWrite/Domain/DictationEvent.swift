enum DictationEvent: Equatable, Sendable {
    case becameAvailable
    case becameUnavailable(DictationAvailability)
    case userStarted(mode: DictationMode)
    case targetCaptured
    case targetUnavailable
    case targetBlocked
    case sessionStarted
    case partialReceived(String)
    case userStopped
    case maximumDurationReached
    case organizingStarted
    case finalReceived(String)
    case finalPrepared(String)
    case finalPreparationFailed(rawText: String)
    case insertionSucceeded
    case insertionFailed
    case insertionRetried
    case serviceFailed(DictationFailure)
    case authenticationInvalidated(DictationAvailability)
    case userCancelled
    case resultDismissed
    case loggedOut
    case applicationTerminated
}

enum DictationEffect: Equatable, Sendable {
    case captureTarget
    case startSession
    case stopAndFinalize
    case prepareFinal(text: String)
    case insert(text: String)
    case cancelSession
    case releaseSession
}

struct DictationTransition: Equatable, Sendable {
    let state: DictationState
    let effects: [DictationEffect]
    let accepted: Bool
}
