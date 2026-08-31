enum DictationAvailability: Equatable, Sendable {
    case authenticationRequired
    case sessionReplaced
    case sessionExpired
    case accountDisabled
    case prerequisitesMissing
}

enum DictationFailure: Equatable, Sendable {
    case targetUnavailable
    case captureUnavailable
    case microphoneCalibrationRequired
    case inputDeviceChanged
    case nearSpeechNotDetected
    case serviceUnavailable
    case tooManyRequests
    case protocolViolation
    case audioLimitExceeded
    case finalTimeout
}
