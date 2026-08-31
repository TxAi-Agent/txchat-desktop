import Foundation

enum MicrophoneCalibrationPhase: Equatable, Sendable {
    case required(deviceName: String)
    case samplingQuiet(progress: Double, deviceName: String)
    case samplingSpeech(progress: Double, deviceName: String)
    case ready(deviceName: String, calibratedAt: Date)
    case failed(MicrophoneCalibrationFailure)
}

final class TxChatSensitivePCM16Chunk: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Data

    init(_ data: Data) {
        storage = data
    }

    var isCleared: Bool {
        lock.withLock { storage.isEmpty }
    }

    var retainedByteCount: Int {
        lock.withLock { storage.count }
    }

    func consume<Result>(
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        lock.lock()
        defer {
            clearLocked()
            lock.unlock()
        }
        return try storage.withUnsafeBytes { bytes in
            try body(bytes)
        }
    }

    func clear() {
        lock.withLock { clearLocked() }
    }

    deinit {
        clearLocked()
    }

    private func clearLocked() {
        if !storage.isEmpty {
            storage.resetBytes(in: storage.startIndex..<storage.endIndex)
            storage.removeAll(keepingCapacity: false)
        }
    }
}

protocol PCM16AudioSourcing: Sendable {
    func start() async throws ->
        AsyncThrowingStream<TxChatSensitivePCM16Chunk, Error>
    func stop() async
    func cancel() async
}

typealias PCM16AudioSourceFactory = @Sendable () -> any PCM16AudioSourcing

protocol MicrophoneCalibrationServing: Sendable {
    func status() async -> MicrophoneCalibrationPhase
    func calibrate(
        onProgress: @escaping @Sendable (
            MicrophoneCalibrationPhase
        ) async -> Void
    ) async throws -> TxChatDistanceGateProfile
    func invalidateCurrentProfile() async
}

actor TxChatMicrophoneCalibrationService: MicrophoneCalibrationServing {
    private static let quietByteCount = 2 *
        TxChatDistanceGateParameters.sampleRate * MemoryLayout<Int16>.size
    private static let speechByteCount = 5 *
        TxChatDistanceGateParameters.sampleRate * MemoryLayout<Int16>.size

    private let deviceProvider: any TxChatInputDeviceProviding
    private let store: any MicrophoneCalibrationStoring
    private let sourceFactory: PCM16AudioSourceFactory
    private let now: @Sendable () -> Date
    private let calibrationTimeout: Duration
    private var isRunning = false
    private var currentPhase: MicrophoneCalibrationPhase?

    init(
        deviceProvider: any TxChatInputDeviceProviding,
        store: any MicrophoneCalibrationStoring,
        sourceFactory: @escaping PCM16AudioSourceFactory,
        now: @escaping @Sendable () -> Date = Date.init,
        calibrationTimeout: Duration = .seconds(10)
    ) {
        self.deviceProvider = deviceProvider
        self.store = store
        self.sourceFactory = sourceFactory
        self.now = now
        self.calibrationTimeout = calibrationTimeout
    }

    func status() async -> MicrophoneCalibrationPhase {
        if isRunning, let currentPhase {
            return currentPhase
        }
        do {
            let device = try deviceProvider.currentInputDevice()
            if let profile = await store.profile(for: device) {
                return .ready(
                    deviceName: device.displayName,
                    calibratedAt: profile.createdAt
                )
            }
            return .required(deviceName: device.displayName)
        } catch {
            return .failed(.inputDeviceUnavailable)
        }
    }

    func calibrate(
        onProgress: @escaping @Sendable (
            MicrophoneCalibrationPhase
        ) async -> Void
    ) async throws -> TxChatDistanceGateProfile {
        guard !isRunning else {
            throw MicrophoneCalibrationFailure.alreadyRunning
        }
        isRunning = true
        defer { isRunning = false }

        let device: TxChatInputDeviceIdentity
        do {
            device = try deviceProvider.currentInputDevice()
        } catch {
            throw MicrophoneCalibrationFailure.inputDeviceUnavailable
        }

        let source = sourceFactory()
        var quietPCM = Data(capacity: Self.quietByteCount)
        var speechPCM = Data(capacity: Self.speechByteCount)
        var stoppedSuccessfully = false
        defer {
            quietPCM.resetBytes(in: 0..<quietPCM.count)
            speechPCM.resetBytes(in: 0..<speechPCM.count)
            quietPCM.removeAll(keepingCapacity: false)
            speechPCM.removeAll(keepingCapacity: false)
        }

        do {
            await publish(
                .samplingQuiet(progress: 0, deviceName: device.displayName),
                onProgress: onProgress
            )
            let stream = try await source.start()
            let timeoutTask = Task {
                do {
                    try await Task.sleep(for: calibrationTimeout)
                } catch {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                await source.cancel()
            }
            defer { timeoutTask.cancel() }
            for try await chunk in stream {
                let activeDevice: TxChatInputDeviceIdentity
                do {
                    activeDevice = try deviceProvider.currentInputDevice()
                } catch {
                    throw MicrophoneCalibrationFailure.inputDeviceUnavailable
                }
                guard activeDevice.uid == device.uid else {
                    throw MicrophoneCalibrationFailure.inputDeviceChanged
                }
                let wasSamplingQuiet = quietPCM.count < Self.quietByteCount
                try chunk.consume { pcm in
                    guard !pcm.isEmpty,
                          pcm.count.isMultiple(
                            of: MemoryLayout<Int16>.size
                          ) else {
                        throw MicrophoneCalibrationFailure.invalidPCM
                    }
                    append(
                        pcm,
                        quietPCM: &quietPCM,
                        speechPCM: &speechPCM
                    )
                }
                if wasSamplingQuiet,
                   quietPCM.count == Self.quietByteCount {
                    await publish(
                        .samplingSpeech(
                            progress: 0,
                            deviceName: device.displayName
                        ),
                        onProgress: onProgress
                    )
                }
                if quietPCM.count < Self.quietByteCount {
                    await publish(
                        .samplingQuiet(
                            progress: Double(quietPCM.count) /
                                Double(Self.quietByteCount),
                            deviceName: device.displayName
                        ),
                        onProgress: onProgress
                    )
                } else if speechPCM.count < Self.speechByteCount {
                    await publish(
                        .samplingSpeech(
                            progress: Double(speechPCM.count) /
                                Double(Self.speechByteCount),
                            deviceName: device.displayName
                        ),
                        onProgress: onProgress
                    )
                }
                if quietPCM.count == Self.quietByteCount,
                   speechPCM.count == Self.speechByteCount {
                    break
                }
            }
            guard quietPCM.count == Self.quietByteCount,
                  speechPCM.count == Self.speechByteCount else {
                throw MicrophoneCalibrationFailure.invalidPCM
            }

            let endingDevice: TxChatInputDeviceIdentity
            do {
                endingDevice = try deviceProvider.currentInputDevice()
            } catch {
                throw MicrophoneCalibrationFailure.inputDeviceUnavailable
            }
            guard endingDevice.uid == device.uid else {
                throw MicrophoneCalibrationFailure.inputDeviceChanged
            }
            let createdAt = now()
            let profile = try TxChatCalibrationPolicy().makeProfile(
                device: device,
                quietPCM: quietPCM,
                speechPCM: speechPCM,
                createdAt: createdAt
            )
            try await store.save(profile)
            await source.stop()
            stoppedSuccessfully = true
            await publish(
                .ready(
                    deviceName: device.displayName,
                    calibratedAt: createdAt
                ),
                onProgress: onProgress
            )
            return profile
        } catch {
            if !stoppedSuccessfully {
                await source.cancel()
            }
            if let failure = error as? MicrophoneCalibrationFailure {
                await publish(.failed(failure), onProgress: onProgress)
                throw failure
            }
            await publish(.failed(.invalidPCM), onProgress: onProgress)
            throw MicrophoneCalibrationFailure.invalidPCM
        }
    }

    func invalidateCurrentProfile() async {
        guard let device = try? deviceProvider.currentInputDevice() else {
            return
        }
        await store.removeProfile(for: device.uid)
    }

    private func append(
        _ chunk: UnsafeRawBufferPointer,
        quietPCM: inout Data,
        speechPCM: inout Data
    ) {
        var offset = 0
        if quietPCM.count < Self.quietByteCount {
            let byteCount = min(
                Self.quietByteCount - quietPCM.count,
                chunk.count
            )
            quietPCM.append(contentsOf: chunk.prefix(byteCount))
            offset += byteCount
        }
        if offset < chunk.count,
           speechPCM.count < Self.speechByteCount {
            let byteCount = min(
                Self.speechByteCount - speechPCM.count,
                chunk.count - offset
            )
            speechPCM.append(
                contentsOf: chunk[offset..<(offset + byteCount)]
            )
        }
    }

    private func publish(
        _ phase: MicrophoneCalibrationPhase,
        onProgress: @escaping @Sendable (
            MicrophoneCalibrationPhase
        ) async -> Void
    ) async {
        currentPhase = phase
        await onProgress(phase)
    }
}
