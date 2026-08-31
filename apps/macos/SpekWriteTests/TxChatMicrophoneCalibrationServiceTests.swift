import Foundation
import XCTest
@testable import SpekWrite

private actor CalibrationTestSource: PCM16AudioSourcing {
    let chunks: [TxChatSensitivePCM16Chunk]
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0

    init(chunks: [Data]) {
        self.chunks = chunks.map(TxChatSensitivePCM16Chunk.init)
    }

    func start() async throws ->
        AsyncThrowingStream<TxChatSensitivePCM16Chunk, Error>
    {
        startCount += 1
        let chunks = chunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    func stop() async {
        stopCount += 1
        chunks.forEach { $0.clear() }
    }

    func cancel() async {
        cancelCount += 1
        chunks.forEach { $0.clear() }
    }

    func counts() -> (start: Int, stop: Int, cancel: Int) {
        (startCount, stopCount, cancelCount)
    }

    func allChunksAreCleared() -> Bool {
        chunks.allSatisfy(\.isCleared)
    }
}

private actor SuspendedCalibrationTestSource: PCM16AudioSourcing {
    private var continuation:
        AsyncThrowingStream<TxChatSensitivePCM16Chunk, Error>.Continuation?
    private var chunks: [TxChatSensitivePCM16Chunk] = []
    private var cancelCount = 0

    func start() async throws ->
        AsyncThrowingStream<TxChatSensitivePCM16Chunk, Error>
    {
        let pair = AsyncThrowingStream<
            TxChatSensitivePCM16Chunk,
            Error
        >.makeStream()
        continuation = pair.continuation
        return pair.stream
    }

    func stop() async {
        chunks.forEach { $0.clear() }
        continuation?.finish()
        continuation = nil
    }

    func cancel() async {
        cancelCount += 1
        chunks.forEach { $0.clear() }
        continuation?.finish(throwing: CancellationError())
        continuation = nil
    }

    func yield(_ pcm: Data) -> TxChatSensitivePCM16Chunk {
        let chunk = TxChatSensitivePCM16Chunk(pcm)
        chunks.append(chunk)
        continuation?.yield(chunk)
        return chunk
    }

    func finishInput() {
        continuation?.finish()
        continuation = nil
    }

    func allChunksAreCleared() -> Bool {
        chunks.allSatisfy(\.isCleared)
    }

    func cancellationCount() -> Int {
        cancelCount
    }
}

private final class CalibrationTestDeviceProvider:
    @unchecked Sendable, TxChatInputDeviceProviding
{
    private let lock = NSLock()
    private var devices: [TxChatInputDeviceIdentity]

    init(devices: [TxChatInputDeviceIdentity]) {
        self.devices = devices
    }

    func currentInputDevice() throws -> TxChatInputDeviceIdentity {
        lock.withLock {
            if devices.count > 1 {
                return devices.removeFirst()
            }
            return devices[0]
        }
    }
}

private actor CalibrationTestStore: MicrophoneCalibrationStoring {
    private(set) var savedProfiles: [TxChatDistanceGateProfile] = []

    func profile(
        for device: TxChatInputDeviceIdentity
    ) async -> TxChatDistanceGateProfile? {
        savedProfiles.last { $0.isValid(for: device) }
    }

    func save(_ profile: TxChatDistanceGateProfile) async throws {
        savedProfiles.append(profile)
    }

    func removeProfile(for deviceUID: String) async {
        savedProfiles.removeAll { $0.device.uid == deviceUID }
    }

    func snapshot() -> [TxChatDistanceGateProfile] {
        savedProfiles
    }
}

final class TxChatMicrophoneCalibrationServiceTests: XCTestCase {
    func testSensitivePCMChunkClearsRetainedBytesAfterConsumption() throws {
        let chunk = TxChatSensitivePCM16Chunk(
            Data(repeating: 0x5A, count: 640)
        )
        var consumedByteCount = 0

        chunk.consume { (pcm: UnsafeRawBufferPointer) in
            consumedByteCount = pcm.count
            XCTAssertEqual(Set(pcm), [0x5A])
        }

        XCTAssertEqual(consumedByteCount, 640)
        XCTAssertTrue(chunk.isCleared)
        XCTAssertEqual(chunk.retainedByteCount, 0)
    }

    func testStatusPreservesSamplingPhaseWhileCalibrationIsRunning()
        async
    {
        let device = TxChatInputDeviceIdentity(
            uid: "test-input-a",
            displayName: "Test Input"
        )
        let source = SuspendedCalibrationTestSource()
        let service = TxChatMicrophoneCalibrationService(
            deviceProvider: CalibrationTestDeviceProvider(devices: [device]),
            store: CalibrationTestStore(),
            sourceFactory: { source }
        )
        let phases = CalibrationPhaseRecorder()
        let calibration = Task {
            try await service.calibrate { phase in
                await phases.append(phase)
            }
        }
        await waitUntil {
            await phases.snapshot().contains(
                .samplingQuiet(progress: 0, deviceName: "Test Input")
            )
        }
        let chunk = await source.yield(
            SyntheticPCM16.sine(
                frequency: 1_000,
                decibels: -55,
                durationMilliseconds: 20
            )
        )
        await waitUntil {
            await phases.snapshot().contains(
                .samplingQuiet(progress: 0.01, deviceName: "Test Input")
            )
        }
        XCTAssertTrue(chunk.isCleared)

        let status = await service.status()

        XCTAssertEqual(
            status,
            .samplingQuiet(progress: 0.01, deviceName: "Test Input")
        )
        await source.finishInput()
        _ = await calibration.result
    }

    func testCalibrationConsumesTwoSecondsQuietAndFiveSecondsSpeech()
        async throws
    {
        let device = TxChatInputDeviceIdentity(
            uid: "test-input-a",
            displayName: "Test Input"
        )
        let quiet = SyntheticPCM16.sine(
            frequency: 1_000,
            decibels: -55,
            durationMilliseconds: 2_000
        )
        let speech = SyntheticPCM16.sine(
            frequency: 1_000,
            decibels: -25,
            durationMilliseconds: 5_000
        )
        let ignoredTail = Data(repeating: 0x55, count: 640)
        let firstQuietChunk = Data(quiet.prefix(7_112))
        let remainingCalibrationPCM =
            Data(quiet.dropFirst(7_112)) + speech
        let source = CalibrationTestSource(
            chunks: [firstQuietChunk, remainingCalibrationPCM, ignoredTail]
        )
        let store = CalibrationTestStore()
        let service = TxChatMicrophoneCalibrationService(
            deviceProvider: CalibrationTestDeviceProvider(devices: [device]),
            store: store,
            sourceFactory: { source },
            now: { Date(timeIntervalSince1970: 42) }
        )
        let phases = CalibrationPhaseRecorder()

        let profile = try await service.calibrate { phase in
            await phases.append(phase)
        }

        XCTAssertEqual(profile.device, device)
        XCTAssertEqual(profile.createdAt, Date(timeIntervalSince1970: 42))
        let savedProfiles = await store.snapshot()
        XCTAssertEqual(savedProfiles, [profile])
        let counts = await source.counts()
        XCTAssertEqual(counts.start, 1)
        XCTAssertEqual(counts.stop, 1)
        XCTAssertEqual(counts.cancel, 0)
        let allChunksAreCleared = await source.allChunksAreCleared()
        XCTAssertTrue(allChunksAreCleared)
        let recorded = await phases.snapshot()
        XCTAssertTrue(
            recorded.contains(
                .samplingQuiet(progress: 0, deviceName: "Test Input")
            )
        )
        XCTAssertTrue(
            recorded.contains(
                .samplingSpeech(progress: 0, deviceName: "Test Input")
            )
        )
        XCTAssertEqual(
            recorded.last,
            .ready(
                deviceName: "Test Input",
                calibratedAt: Date(timeIntervalSince1970: 42)
            )
        )
    }

    func testCalibrationFailsClosedWhenInputDeviceChanges() async {
        let first = TxChatInputDeviceIdentity(
            uid: "test-input-a",
            displayName: "Input A"
        )
        let second = TxChatInputDeviceIdentity(
            uid: "test-input-b",
            displayName: "Input B"
        )
        let source = CalibrationTestSource(
            chunks: [
                SyntheticPCM16.sine(
                    frequency: 1_000,
                    decibels: -55,
                    durationMilliseconds: 2_000
                ) + SyntheticPCM16.sine(
                    frequency: 1_000,
                    decibels: -25,
                    durationMilliseconds: 5_000
                ),
            ]
        )
        let store = CalibrationTestStore()
        let service = TxChatMicrophoneCalibrationService(
            deviceProvider: CalibrationTestDeviceProvider(
                devices: [first, second]
            ),
            store: store,
            sourceFactory: { source }
        )

        do {
            _ = try await service.calibrate { _ in }
            XCTFail("Expected calibration to fail when the device changes")
        } catch {
            XCTAssertEqual(
                error as? MicrophoneCalibrationFailure,
                .inputDeviceChanged
            )
        }

        let savedProfiles = await store.snapshot()
        XCTAssertTrue(savedProfiles.isEmpty)
        let counts = await source.counts()
        XCTAssertEqual(counts.stop, 0)
        XCTAssertEqual(counts.cancel, 1)
        let allChunksAreCleared = await source.allChunksAreCleared()
        XCTAssertTrue(allChunksAreCleared)
    }

    func testCalibrationDetectsInputDeviceChangeDuringSampling() async {
        let first = TxChatInputDeviceIdentity(
            uid: "test-input-a",
            displayName: "Input A"
        )
        let second = TxChatInputDeviceIdentity(
            uid: "test-input-b",
            displayName: "Input B"
        )
        let source = SuspendedCalibrationTestSource()
        let service = TxChatMicrophoneCalibrationService(
            deviceProvider: CalibrationTestDeviceProvider(
                devices: [first, second]
            ),
            store: CalibrationTestStore(),
            sourceFactory: { source }
        )
        let phases = CalibrationPhaseRecorder()
        let calibration = Task {
            try await service.calibrate { phase in
                await phases.append(phase)
            }
        }
        await waitUntil {
            await phases.snapshot().contains(
                .samplingQuiet(progress: 0, deviceName: "Input A")
            )
        }
        let chunk = await source.yield(
            SyntheticPCM16.sine(
                frequency: 1_000,
                decibels: -55,
                durationMilliseconds: 20
            )
        )
        await source.finishInput()

        let result = await calibration.result

        switch result {
        case .success:
            XCTFail("Expected an in-progress device change to fail closed")
        case let .failure(error):
            XCTAssertEqual(
                error as? MicrophoneCalibrationFailure,
                .inputDeviceChanged
            )
        }
        XCTAssertTrue(chunk.isCleared)
    }

    func testCalibrationTimesOutWhenPCMSourceStopsProducing() async {
        let device = TxChatInputDeviceIdentity(
            uid: "test-input-a",
            displayName: "Input A"
        )
        let source = SuspendedCalibrationTestSource()
        let service = TxChatMicrophoneCalibrationService(
            deviceProvider: CalibrationTestDeviceProvider(devices: [device]),
            store: CalibrationTestStore(),
            sourceFactory: { source },
            calibrationTimeout: .milliseconds(10)
        )

        do {
            _ = try await service.calibrate { _ in }
            XCTFail("Expected stalled calibration PCM to time out")
        } catch {
            XCTAssertEqual(
                error as? MicrophoneCalibrationFailure,
                .invalidPCM
            )
        }

        let cancellationCount = await source.cancellationCount()
        XCTAssertGreaterThanOrEqual(cancellationCount, 1)
    }

    func testSystemSourceBuffersOnlyOneSensitivePCMChunk() {
        XCTAssertEqual(SystemPCM16AudioSource.streamBufferCapacity, 1)
    }

    func testStatusAndInvalidationAreProfileOnlyAndDoNotStartPCM()
        async throws
    {
        let device = TxChatInputDeviceIdentity(
            uid: "test-input-a",
            displayName: "Input A"
        )
        let source = CalibrationTestSource(chunks: [])
        let store = CalibrationTestStore()
        let service = TxChatMicrophoneCalibrationService(
            deviceProvider: CalibrationTestDeviceProvider(devices: [device]),
            store: store,
            sourceFactory: { source }
        )

        let status = await service.status()
        XCTAssertEqual(status, .required(deviceName: "Input A"))
        await service.invalidateCurrentProfile()

        let counts = await source.counts()
        XCTAssertEqual(counts.start, 0)
        XCTAssertEqual(counts.stop, 0)
        XCTAssertEqual(counts.cancel, 0)
    }

    private func waitUntil(
        _ predicate: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<200 {
            if await predicate() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition did not become true")
    }
}

private actor CalibrationPhaseRecorder {
    private var phases: [MicrophoneCalibrationPhase] = []

    func append(_ phase: MicrophoneCalibrationPhase) {
        phases.append(phase)
    }

    func snapshot() -> [MicrophoneCalibrationPhase] {
        phases
    }
}
