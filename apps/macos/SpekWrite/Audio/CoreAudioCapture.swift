@preconcurrency import AVFoundation
import Foundation

enum CoreAudioCaptureError: Error, Equatable, Sendable {
    case invalidState
    case microphoneUnavailable
    case conversionUnavailable
    case conversionFailed
    case frameBufferOverflow
    case calibrationRequired
    case inputDeviceChanged
    case nearSpeechNotDetected
}

enum CoreAudioLevelMeter {
    private static let minimumDecibels = -60.0

    static func normalizedRMS(_ pcm16: Data) -> Double {
        guard !pcm16.isEmpty, pcm16.count.isMultiple(of: 2) else {
            return 0
        }
        let sampleCount = pcm16.count / MemoryLayout<Int16>.size
        let sumOfSquares = pcm16.withUnsafeBytes { bytes -> Double in
            var sum = 0.0
            for index in 0..<sampleCount {
                let raw = bytes.loadUnaligned(
                    fromByteOffset: index * MemoryLayout<Int16>.size,
                    as: Int16.self
                )
                let sample = Double(Int16(littleEndian: raw)) / 32_768.0
                sum += sample * sample
            }
            return sum
        }
        let rms = sqrt(sumOfSquares / Double(sampleCount))
        guard rms > 0, rms.isFinite else {
            return 0
        }
        let decibels = max(20 * log10(rms), minimumDecibels)
        return min(max((decibels - minimumDecibels) / -minimumDecibels, 0), 1)
    }
}

struct TxChatAudioLevelSmoother: Equatable, Sendable {
    static let baseline = 0.08
    private static let attack = 0.45
    private static let release = 0.20

    private(set) var currentLevel = baseline

    mutating func update(with sample: Double?) -> Double {
        let sanitized = sample.flatMap { value in
            value.isFinite ? min(max(value, 0), 1) : nil
        }
        let target = max(sanitized ?? Self.baseline, Self.baseline)
        let coefficient = target > currentLevel
            ? Self.attack
            : Self.release
        currentLevel += (target - currentLevel) * coefficient
        return currentLevel
    }
}

enum TxChatHUDWaveform {
    static let fallbackHeights: [Double] = [4, 6, 5, 7, 5, 6, 4, 6, 4]
    private static let weights: [Double] = [
        0.2558, 0.7673, 0.4476, 1.2148, 0.7673,
        1.5345, 0.6394, 1.0230, 0.3836,
    ]

    static func heights(
        level: Double?,
        reduceMotion: Bool
    ) -> [Double] {
        guard !reduceMotion,
              let level,
              level.isFinite else {
            return fallbackHeights
        }
        let normalized = min(max(level, 0), 1)
        return zip(fallbackHeights, weights).map { baseline, weight in
            min(max(baseline + normalized * 23 * weight, 4), 30)
        }
    }
}

final class CorePCMConverter: @unchecked Sendable {
    private final class InputSupply: @unchecked Sendable {
        let source: AVAudioPCMBuffer
        var supplied = false

        init(source: AVAudioPCMBuffer) {
            self.source = source
        }
    }

    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init(sourceFormat: AVAudioFormat) throws {
        guard
            sourceFormat.sampleRate > 0,
            sourceFormat.channelCount > 0,
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: CoreRecordingLimits.sampleRate,
                channels: AVAudioChannelCount(CoreRecordingLimits.channels),
                interleaved: true
            ),
            let converter = AVAudioConverter(
                from: sourceFormat,
                to: outputFormat
            )
        else {
            throw CoreAudioCaptureError.conversionUnavailable
        }
        self.converter = converter
        self.converter.primeMethod = .none
        self.outputFormat = outputFormat
    }

    func convert(_ source: AVAudioPCMBuffer) throws -> [Data] {
        guard source.frameLength > 0 else {
            return []
        }
        let ratio = outputFormat.sampleRate / source.format.sampleRate
        let estimatedFrames = ceil(Double(source.frameLength) * ratio) + 32
        guard
            estimatedFrames > 0,
            estimatedFrames <= Double(UInt32.max),
            let output = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(estimatedFrames)
            )
        else {
            throw CoreAudioCaptureError.conversionFailed
        }

        let inputSupply = InputSupply(source: source)
        var conversionError: NSError?
        let status = converter.convert(
            to: output,
            error: &conversionError
        ) { _, inputStatus in
            if inputSupply.supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputSupply.supplied = true
            inputStatus.pointee = .haveData
            return inputSupply.source
        }
        guard
            conversionError == nil,
            status != .error,
            output.frameLength > 0,
            let samples = output.int16ChannelData?[0]
        else {
            if status == .inputRanDry || status == .endOfStream {
                return []
            }
            throw CoreAudioCaptureError.conversionFailed
        }

        let totalBytes = Int(output.frameLength) * MemoryLayout<Int16>.size
        let raw = UnsafeRawBufferPointer(start: samples, count: totalBytes)
        var frames: [Data] = []
        var offset = 0
        while offset < totalBytes {
            let count = min(
                CoreRecordingLimits.maximumFrameBytes,
                totalBytes - offset
            )
            let frame = Data(raw[offset..<(offset + count)])
            try CoreAudioFramePolicy.validate(frame)
            frames.append(frame)
            offset += count
        }
        return frames
    }
}

struct CorePCMFrameAssembler {
    private static let targetFrameBytes = 3_200
    private var pending = Data()

    mutating func append(_ data: Data) throws -> [Data] {
        try CoreAudioFramePolicy.validate(data)
        pending.append(data)
        var frames: [Data] = []
        while pending.count >= Self.targetFrameBytes {
            frames.append(Data(pending.prefix(Self.targetFrameBytes)))
            pending.resetBytes(in: 0..<Self.targetFrameBytes)
            pending.removeFirst(Self.targetFrameBytes)
        }
        return frames
    }

    mutating func finish() -> Data? {
        guard !pending.isEmpty else {
            return nil
        }
        let tail = Data(pending)
        pending.resetBytes(in: 0..<pending.count)
        pending.removeAll(keepingCapacity: false)
        return tail
    }

    mutating func discard() {
        pending.resetBytes(in: 0..<pending.count)
        pending.removeAll(keepingCapacity: false)
    }
}

struct TxChatGatedPCMFrameAssembler {
    struct Finish: Equatable, Sendable {
        let frames: [Data]
        let tail: Data?
        let report: TxChatDistanceGateReport
    }

    private var gate: TxChatDistanceGate
    private var assembler = CorePCMFrameAssembler()

    init(profile: TxChatDistanceGateProfile) throws {
        gate = try TxChatDistanceGate(profile: profile)
    }

    mutating func append(_ rawPCM: Data) throws -> [Data] {
        let gatedPCM = try gate.process(rawPCM)
        guard !gatedPCM.isEmpty else {
            return []
        }
        return try assembler.append(gatedPCM)
    }

    mutating func finish() throws -> Finish {
        let gateFinish = gate.finish()
        var frames: [Data] = []
        if !gateFinish.remainingPCM.isEmpty {
            frames = try assembler.append(gateFinish.remainingPCM)
        }
        return Finish(
            frames: frames,
            tail: assembler.finish(),
            report: gateFinish.report
        )
    }

    mutating func discard() {
        gate.cancel()
        assembler.discard()
    }
}

private final class CoreAudioCapturePipeline: @unchecked Sendable {
    private let lock = NSLock()
    private let converter: CorePCMConverter
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let audioLevelHandler: DictationAudioCapturing.AudioLevelHandler
    private let deviceProvider: any TxChatInputDeviceProviding
    private let sessionDevice: TxChatInputDeviceIdentity
    private var frames = CorePCMFrameAssembler()
    private var terminated = false
    private var lastLevelEmissionUptime: TimeInterval?

    init(
        converter: CorePCMConverter,
        deviceProvider: any TxChatInputDeviceProviding,
        sessionDevice: TxChatInputDeviceIdentity,
        continuation: AsyncThrowingStream<Data, Error>.Continuation,
        audioLevelHandler:
            @escaping DictationAudioCapturing.AudioLevelHandler
    ) {
        self.converter = converter
        self.deviceProvider = deviceProvider
        self.sessionDevice = sessionDevice
        self.continuation = continuation
        self.audioLevelHandler = audioLevelHandler
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !terminated else {
            return
        }
        do {
            try verifyInputDeviceHasNotChanged()
            for converted in try converter.convert(buffer) {
                emitAudioLevelIfNeeded(for: converted)
                for frame in try frames.append(converted) {
                    guard yield(frame) else {
                        return
                    }
                }
            }
        } catch {
            terminate(throwing: error)
        }
    }

    private func verifyInputDeviceHasNotChanged() throws {
        let currentDevice: TxChatInputDeviceIdentity
        do {
            currentDevice = try deviceProvider.currentInputDevice()
        } catch {
            throw CoreAudioCaptureError.inputDeviceChanged
        }
        guard currentDevice.uid == sessionDevice.uid else {
            throw CoreAudioCaptureError.inputDeviceChanged
        }
    }

    private func emitAudioLevelIfNeeded(for pcm16: Data) {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastLevelEmissionUptime,
           now - lastLevelEmissionUptime < 0.05 {
            return
        }
        lastLevelEmissionUptime = now
        let level = CoreAudioLevelMeter.normalizedRMS(pcm16)
        let handler = audioLevelHandler
        Task {
            await handler(level)
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
            return
        }
        if let tail = frames.finish(), !yield(tail) {
            return
        }
        terminated = true
        continuation.finish()
    }

    private func yield(_ frame: Data) -> Bool {
        switch continuation.yield(frame) {
        case .enqueued:
            return true
        case .dropped:
            terminate(throwing: CoreAudioCaptureError.frameBufferOverflow)
            return false
        case .terminated:
            terminated = true
            return false
        @unknown default:
            terminate(throwing: CoreAudioCaptureError.conversionFailed)
            return false
        }
    }

    private func terminate(throwing error: Error) {
        guard !terminated else {
            return
        }
        terminated = true
        frames.discard()
        continuation.finish(throwing: error)
    }
}

final class CoreAudioCapture: @unchecked Sendable, CoreAudioCapturing {
    private struct Session {
        let engine: AVAudioEngine
        let pipeline: CoreAudioCapturePipeline
    }

    private let lock = NSLock()
    private let deviceProvider: any TxChatInputDeviceProviding
    private var session: Session?
    private var preflightDeviceUID: String?

    init(
        deviceProvider: any TxChatInputDeviceProviding =
            CoreAudioInputDeviceProvider()
    ) {
        self.deviceProvider = deviceProvider
    }

    func preflight() async throws {
        let device = try inputDevice(
            expectedDeviceUID: nil
        )
        lock.withLock {
            preflightDeviceUID = device.uid
        }
    }

    func start() async throws -> AsyncThrowingStream<Data, Error> {
        try await start(onAudioLevel: { _ in })
    }

    func start(
        onAudioLevel:
            @escaping DictationAudioCapturing.AudioLevelHandler
    ) async throws -> AsyncThrowingStream<Data, Error> {
        guard lock.withLock({ session == nil }) else {
            throw CoreAudioCaptureError.invalidState
        }
        let expectedDeviceUID = lock.withLock { preflightDeviceUID }
        let sessionDevice = try inputDevice(
            expectedDeviceUID: expectedDeviceUID
        )
        guard await Self.microphoneAccessIsAuthorized() else {
            throw CoreAudioCaptureError.microphoneUnavailable
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let sourceFormat = input.inputFormat(forBus: 0)
        let converter = try CorePCMConverter(sourceFormat: sourceFormat)
        let pair = AsyncThrowingStream<Data, Error>.makeStream(
            bufferingPolicy: .bufferingOldest(
                CoreRecordingLimits.frameBufferCapacity
            )
        )
        let pipeline = CoreAudioCapturePipeline(
            converter: converter,
            deviceProvider: deviceProvider,
            sessionDevice: sessionDevice,
            continuation: pair.continuation,
            audioLevelHandler: onAudioLevel
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
            lock.withLock {
                session = nil
            }
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

    private func inputDevice(
        expectedDeviceUID: String?
    ) throws -> TxChatInputDeviceIdentity {
        let device: TxChatInputDeviceIdentity
        do {
            device = try deviceProvider.currentInputDevice()
        } catch {
            throw CoreAudioCaptureError.microphoneUnavailable
        }
        if let expectedDeviceUID,
           expectedDeviceUID != device.uid {
            throw CoreAudioCaptureError.inputDeviceChanged
        }
        return device
    }
}
