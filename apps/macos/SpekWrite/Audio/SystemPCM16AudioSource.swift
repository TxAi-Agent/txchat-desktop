@preconcurrency import AVFoundation
import Foundation

private final class SystemPCM16AudioPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private let converter: CorePCMConverter
    private let continuation:
        AsyncThrowingStream<TxChatSensitivePCM16Chunk, Error>.Continuation
    private var outstandingChunks: [TxChatSensitivePCM16Chunk] = []
    private var terminated = false

    init(
        converter: CorePCMConverter,
        continuation: AsyncThrowingStream<
            TxChatSensitivePCM16Chunk,
            Error
        >.Continuation
    ) {
        self.converter = converter
        self.continuation = continuation
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !terminated else {
            return
        }
        outstandingChunks.removeAll(where: \.isCleared)
        do {
            var frames = try converter.convert(buffer)
            defer {
                for index in frames.indices {
                    Self.clear(&frames[index])
                }
            }
            for index in frames.indices {
                let chunk = TxChatSensitivePCM16Chunk(frames[index])
                Self.clear(&frames[index])
                outstandingChunks.append(chunk)
                switch continuation.yield(chunk) {
                case .enqueued:
                    continue
                case let .dropped(droppedChunk):
                    droppedChunk.clear()
                    terminate(
                        throwing: CoreAudioCaptureError.frameBufferOverflow
                    )
                    return
                case .terminated:
                    chunk.clear()
                    clearOutstandingChunks()
                    terminated = true
                    return
                @unknown default:
                    terminate(
                        throwing: CoreAudioCaptureError.conversionFailed
                    )
                    return
                }
            }
        } catch {
            terminate(throwing: error)
        }
    }

    func finish(throwing error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        guard !terminated else {
            return
        }
        if let error {
            terminate(throwing: error)
        } else {
            terminated = true
            clearOutstandingChunks()
            continuation.finish()
        }
    }

    private func terminate(throwing error: Error) {
        guard !terminated else {
            return
        }
        terminated = true
        clearOutstandingChunks()
        continuation.finish(throwing: error)
    }

    private func clearOutstandingChunks() {
        outstandingChunks.forEach { $0.clear() }
        outstandingChunks.removeAll(keepingCapacity: false)
    }

    private static func clear(_ data: inout Data) {
        if !data.isEmpty {
            data.resetBytes(in: data.startIndex..<data.endIndex)
            data.removeAll(keepingCapacity: false)
        }
    }
}

final class SystemPCM16AudioSource: @unchecked Sendable,
    PCM16AudioSourcing
{
    static let streamBufferCapacity = 1

    private struct Session {
        let engine: AVAudioEngine
        let pipeline: SystemPCM16AudioPipeline
    }

    private let lock = NSLock()
    private var session: Session?

    func start() async throws ->
        AsyncThrowingStream<TxChatSensitivePCM16Chunk, Error>
    {
        guard lock.withLock({ session == nil }) else {
            throw CoreAudioCaptureError.invalidState
        }
        guard await Self.microphoneAccessIsAuthorized() else {
            throw CoreAudioCaptureError.microphoneUnavailable
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let sourceFormat = input.inputFormat(forBus: 0)
        let converter = try CorePCMConverter(sourceFormat: sourceFormat)
        let pair = AsyncThrowingStream<
            TxChatSensitivePCM16Chunk,
            Error
        >.makeStream(
            bufferingPolicy: .bufferingOldest(
                Self.streamBufferCapacity
            )
        )
        let pipeline = SystemPCM16AudioPipeline(
            converter: converter,
            continuation: pair.continuation
        )
        let newSession = Session(engine: engine, pipeline: pipeline)
        guard lock.withLock({
            guard session == nil else {
                return false
            }
            session = newSession
            return true
        }) else {
            pair.continuation.finish(
                throwing: CoreAudioCaptureError.invalidState
            )
            throw CoreAudioCaptureError.invalidState
        }

        input.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: sourceFormat
        ) { buffer, _ in
            pipeline.consume(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            lock.withLock { session = nil }
            pipeline.finish(
                throwing: CoreAudioCaptureError.microphoneUnavailable
            )
            throw CoreAudioCaptureError.microphoneUnavailable
        }
        return pair.stream
    }

    func stop() async {
        finish(throwing: nil)
    }

    func cancel() async {
        finish(throwing: CancellationError())
    }

    private func finish(throwing error: Error?) {
        let active = lock.withLock { () -> Session? in
            defer { session = nil }
            return session
        }
        guard let active else {
            return
        }
        active.engine.inputNode.removeTap(onBus: 0)
        active.engine.stop()
        active.pipeline.finish(throwing: error)
    }

    private static func microphoneAccessIsAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
