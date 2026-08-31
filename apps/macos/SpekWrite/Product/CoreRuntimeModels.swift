import Foundation

enum CoreRecordingLimits {
    static let sampleRate = 16_000.0
    static let channels: UInt32 = 1
    static let bitsPerSample: UInt32 = 16
    static let maximumFrameBytes = 6_400
    static let frameBufferCapacity = 16
    static let maximumDuration: Duration = .seconds(300)
}

enum CoreAudioFramePolicy {
    enum Error: Swift.Error, Equatable {
        case invalidFrame
    }

    static func validate(_ frame: Data) throws {
        guard
            !frame.isEmpty,
            frame.count <= CoreRecordingLimits.maximumFrameBytes,
            frame.count.isMultiple(of: 2)
        else {
            throw Error.invalidFrame
        }
    }
}

protocol CoreAudioCapturing: Sendable {
    func start() async throws -> AsyncThrowingStream<Data, Error>
    func stop() async
    func cancel() async
}

struct CoreCapturedTarget: Equatable, Sendable {
    let id: UUID
    let processIdentifier: pid_t
}

enum CoreTargetCaptureOutcome: Equatable, Sendable {
    case captured(CoreCapturedTarget)
    case unavailable
    case blocked
}

@MainActor
protocol CoreTargetHandling: AnyObject {
    func capture() -> CoreTargetCaptureOutcome
    func insert(_ text: String, into target: CoreCapturedTarget) -> Bool
    func discard(_ target: CoreCapturedTarget)
}
