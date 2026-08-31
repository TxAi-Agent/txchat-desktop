import Foundation
import XCTest
@testable import SpekWrite

private enum FakeTransportError: Error {
    case closed
}

private enum FakePromptError: Error {
    case failed
}

private actor FakeRealtimeTransport: RealtimeDictationTransport {
    struct Snapshot: Sendable {
        let accessTokens: [String]
        let controls: [RealtimeClientControl]
        let audioFrames: [Data]
        let audioBytes: Int
        let closeCount: Int
    }

    private var accessTokens: [String] = []
    private var controls: [RealtimeClientControl] = []
    private var audioFrames: [Data] = []
    private var audioBytes = 0
    private var closeCount = 0
    private var recordAudio = true
    private var received: [Result<RealtimeServerControl, Error>] = []
    private var waiters: [CheckedContinuation<RealtimeServerControl, Error>] = []

    func connect(accessToken: String) async throws {
        accessTokens.append(accessToken)
    }

    func send(control: RealtimeClientControl) async throws {
        controls.append(control)
    }

    func send(audio: Data) async throws {
        audioBytes += audio.count
        if recordAudio {
            audioFrames.append(audio)
        }
    }

    func receive() async throws -> RealtimeServerControl {
        if !received.isEmpty {
            return try received.removeFirst().get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func close() async {
        closeCount += 1
        let pending = waiters
        waiters.removeAll(keepingCapacity: false)
        for waiter in pending {
            waiter.resume(throwing: FakeTransportError.closed)
        }
    }

    func push(_ control: RealtimeServerControl) {
        if !waiters.isEmpty {
            waiters.removeFirst().resume(returning: control)
        } else {
            received.append(.success(control))
        }
    }

    func setRecordAudio(_ enabled: Bool) {
        recordAudio = enabled
    }

    func snapshot() -> Snapshot {
        Snapshot(
            accessTokens: accessTokens,
            controls: controls,
            audioFrames: audioFrames,
            audioBytes: audioBytes,
            closeCount: closeCount
        )
    }
}

private actor PartialRecorder {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }
}

private actor OrganizingRecorder {
    private var count = 0

    func record() { count += 1 }
    func snapshot() -> Int { count }
}

final class StreamingDictationClientTests: XCTestCase {
    func testStartSendsTheFrozenSmartModeExactlyOnce() async throws {
        let transport = FakeRealtimeTransport()
        let client = StreamingDictationClient(transport: transport)
        let prompt = try BuiltInTextOptimizationPrompt.loadCurrent()

        let start = Task {
            try await client.start(
                accessToken: "token",
                mode: .smart
            )
        }
        try await waitUntil {
            await transport.snapshot().controls == [
                .start(.smart, prompt: prompt),
            ]
        }
        await transport.push(
            .started
        )
        try await start.value
        let snapshot = await transport.snapshot()
        XCTAssertEqual(
            snapshot.controls,
            [.start(.smart, prompt: prompt)]
        )
        await client.cancel()
    }

    func testSmartStartFailsClosedWhenPromptCannotLoad() async {
        let transport = FakeRealtimeTransport()
        let client = StreamingDictationClient(
            transport: transport,
            promptLoader: { throw FakePromptError.failed }
        )

        do {
            try await client.start(accessToken: "token", mode: .smart)
            XCTFail("smart start accepted a missing prompt")
        } catch {
            XCTAssertEqual(
                error as? RealtimeDictationError,
                .serviceUnavailable
            )
        }

        let snapshot = await transport.snapshot()
        XCTAssertTrue(snapshot.controls.isEmpty)
        XCTAssertEqual(snapshot.closeCount, 1)
    }

    func testVerbatimStartDoesNotLoadPrompt() async throws {
        let transport = FakeRealtimeTransport()
        let client = StreamingDictationClient(
            transport: transport,
            promptLoader: { throw FakePromptError.failed }
        )
        let start = Task {
            try await client.start(accessToken: "token", mode: .verbatim)
        }
        try await waitUntil {
            await transport.snapshot().controls == [.start(.verbatim)]
        }
        await transport.push(
            .started
        )
        try await start.value
        await client.cancel()
    }

    func testOrganizingThenModeAwareFinalCompletesNormally() async throws {
        let transport = FakeRealtimeTransport()
        let client = StreamingDictationClient(transport: transport)
        let recorder = OrganizingRecorder()
        let prompt = try BuiltInTextOptimizationPrompt.loadCurrent()
        let start = Task {
            try await client.start(
                accessToken: "token",
                mode: .smart,
                onPartial: { _ in },
                onOrganizing: { await recorder.record() }
            )
        }
        try await waitUntil {
            await transport.snapshot().controls == [
                .start(.smart, prompt: prompt),
            ]
        }
        await transport.push(
            .started
        )
        try await start.value
        let finish = Task { try await client.finishResult() }
        try await waitUntil {
            await transport.snapshot().controls.last == .finish
        }
        await transport.push(.organizing)
        await transport.push(
            .finalResult(text: "整理后的结果。", mode: .smart)
        )
        await transport.push(.ended)

        let result = try await finish.value
        XCTAssertEqual(result.text, "整理后的结果。")
        XCTAssertEqual(result.mode, .smart)
        let organizingCount = await recorder.snapshot()
        XCTAssertEqual(organizingCount, 1)
    }

    func testFallbackReasonIsPreservedForCompletionFeedback() async throws {
        let (client, transport) = try await startedClient(mode: .smart)
        let finish = Task { try await client.finishResult() }
        try await waitUntil {
            await transport.snapshot().controls.last == .finish
        }
        await transport.push(.organizing)
        await transport.push(
            .finalFallback(
                text: "逐字回退结果。",
                reason: .textOptimizationTimeout
            )
        )
        await transport.push(.ended)

        let result = try await finish.value
        XCTAssertEqual(result.mode, .verbatimFallback)
        XCTAssertEqual(
            result.fallbackReason,
            .textOptimizationTimeout
        )
    }

    func testVerbatimAcceptsPublicLocalOrganizingSequence() async throws {
        let (client, transport) = try await startedClient(mode: .verbatim)
        let finish = Task { try await client.finishResult() }
        try await waitUntil {
            await transport.snapshot().controls.last == .finish
        }
        let transcript = "Synthetic public-local dictation completed."
        await transport.push(.organizing)
        await transport.push(.publicLocalFinal(
            transcript: transcript,
            organizedText: transcript
        ))
        await transport.push(.ended)

        let result = try await finish.value
        XCTAssertEqual(result.text, transcript)
        XCTAssertEqual(result.mode, .verbatim)
    }

    func testSmartRejectsDuplicateOrganizing() async throws {
        let (client, transport) = try await startedClient(mode: .smart)
        let finish = Task { try await client.finishResult() }
        try await waitUntil {
            await transport.snapshot().controls.last == .finish
        }
        await transport.push(.organizing)
        await transport.push(.organizing)

        await assertProtocolViolation(finish)
    }

    func testSmartRejectsPartialAfterOrganizing() async throws {
        let (client, transport) = try await startedClient(mode: .smart)
        let finish = Task { try await client.finishResult() }
        try await waitUntil {
            await transport.snapshot().controls.last == .finish
        }
        await transport.push(.organizing)
        await transport.push(.partial(text: "错序 partial"))

        await assertProtocolViolation(finish)
    }

    func testSmartRejectsFinalWithoutOrganizing() async throws {
        let (client, transport) = try await startedClient(mode: .smart)
        let finish = Task { try await client.finishResult() }
        try await waitUntil {
            await transport.snapshot().controls.last == .finish
        }
        await transport.push(
            .finalResult(text: "缺少整理事件", mode: .smart)
        )

        await assertProtocolViolation(finish)
    }

    func testFrozenModeRejectsMismatchedFinalResultMode() async throws {
        let (client, transport) = try await startedClient(mode: .verbatim)
        let finish = Task { try await client.finishResult() }
        try await waitUntil {
            await transport.snapshot().controls.last == .finish
        }
        await transport.push(
            .finalResult(text: "非法 smart 结果", mode: .smart)
        )

        await assertProtocolViolation(finish)
    }

    func testValidatedPartialIsDeliveredBeforeFinal() async throws {
        let transport = FakeRealtimeTransport()
        let client = StreamingDictationClient(transport: transport)
        let recorder = PartialRecorder()

        let start = Task {
            try await client.start(accessToken: "token") { text in
                await recorder.append(text)
            }
        }
        try await waitUntil { await transport.snapshot().controls == [.start()] }
        await transport.push(
            .started
        )
        try await start.value

        await transport.push(.partial(text: "已校验 partial"))
        try await waitUntil {
            await recorder.snapshot() == ["已校验 partial"]
        }

        let finish = Task { try await client.finish() }
        try await waitUntil {
            await transport.snapshot().controls.last == .finish
        }
        await transport.push(.final(text: "唯一 final"))
        await transport.push(.ended)

        let finalText = try await finish.value
        let partials = await recorder.snapshot()
        XCTAssertEqual(finalText, "唯一 final")
        XCTAssertEqual(partials, ["已校验 partial"])
    }

    func testNoPartialIsDeliveredAfterTerminalClose() async throws {
        let transport = FakeRealtimeTransport()
        let client = StreamingDictationClient(transport: transport)
        let recorder = PartialRecorder()

        let start = Task {
            try await client.start(accessToken: "token") { text in
                await recorder.append(text)
            }
        }
        try await waitUntil { await transport.snapshot().controls == [.start()] }
        await transport.push(
            .started
        )
        try await start.value

        let finish = Task { try await client.finish() }
        try await waitUntil {
            await transport.snapshot().controls.last == .finish
        }
        await transport.push(.partial(text: "terminal 前"))
        try await waitUntil {
            await recorder.snapshot() == ["terminal 前"]
        }
        await transport.push(.final(text: "final"))
        await transport.push(.ended)
        _ = try await finish.value

        await transport.push(.partial(text: "terminal 后"))
        try await Task.sleep(for: .milliseconds(20))
        let partials = await recorder.snapshot()
        XCTAssertEqual(partials, ["terminal 前"])
    }

    func testPartialAfterFinalIsRejectedWithoutDelivery() async throws {
        let transport = FakeRealtimeTransport()
        let client = StreamingDictationClient(transport: transport)
        let recorder = PartialRecorder()

        let start = Task {
            try await client.start(accessToken: "token") { text in
                await recorder.append(text)
            }
        }
        try await waitUntil { await transport.snapshot().controls == [.start()] }
        await transport.push(
            .started
        )
        try await start.value

        let finish = Task { try await client.finish() }
        try await waitUntil {
            await transport.snapshot().controls.last == .finish
        }
        await transport.push(.final(text: "final"))
        await transport.push(.partial(text: "final 后的非法 partial"))
        await transport.push(.ended)

        do {
            _ = try await finish.value
            XCTFail("partial after final was accepted")
        } catch {
            XCTAssertEqual(
                error as? RealtimeDictationError,
                .protocolViolation
            )
        }
        let partials = await recorder.snapshot()
        XCTAssertTrue(partials.isEmpty)
    }

    func testLegacyStartWithoutPartialHandlerStillFinishes() async throws {
        let (client, transport) = try await startedClient()
        let finish = Task { try await client.finish() }
        try await waitUntil {
            await transport.snapshot().controls.last == .finish
        }
        await transport.push(.partial(text: "旧接口不消费"))
        await transport.push(.final(text: "旧接口 final"))
        await transport.push(.ended)

        let finalText = try await finish.value
        XCTAssertEqual(finalText, "旧接口 final")
    }

    func testStreamsAudioAndReturnsOnlyTheSingleFinalText() async throws {
        let transport = FakeRealtimeTransport()
        let client = StreamingDictationClient(transport: transport)

        let start = Task { try await client.start(accessToken: "access-token") }
        try await waitUntil { await transport.snapshot().controls == [.start()] }
        await transport.push(
            .started
        )
        try await start.value

        try await client.send(audio: Data([1, 2, 3, 4]))
        let finish = Task { try await client.finish() }
        try await waitUntil {
            await transport.snapshot().controls == [.start(), .finish]
        }
        await transport.push(.partial(text: "临时文本"))
        await transport.push(.final(text: "最终文本。"))
        await transport.push(.ended)

        let finalText = try await finish.value
        XCTAssertEqual(finalText, "最终文本。")
        let snapshot = await transport.snapshot()
        let clientState = await client.state
        XCTAssertEqual(snapshot.accessTokens, ["access-token"])
        XCTAssertEqual(snapshot.audioFrames, [Data([1, 2, 3, 4])])
        XCTAssertEqual(snapshot.closeCount, 1)
        XCTAssertEqual(clientState, .ended)
    }

    func testRejectsInvalidFramesAndAudioAfterFinish() async throws {
        let (client, transport) = try await startedClient()

        for frame in [Data(), Data([1]), Data(repeating: 0, count: 6_402)] {
            do {
                try await client.send(audio: frame)
                XCTFail("invalid frame was accepted")
            } catch {
                XCTAssertEqual(error as? RealtimeDictationError, .invalidAudioFrame)
            }
        }

        let finish = Task { try await client.finish() }
        try await waitUntil {
            await transport.snapshot().controls.last == .finish
        }
        do {
            try await client.send(audio: Data([1, 2]))
            XCTFail("audio after finish was accepted")
        } catch {
            XCTAssertEqual(error as? RealtimeDictationError, .invalidState)
        }
        await transport.push(.final(text: "完成。"))
        await transport.push(.ended)
        _ = try await finish.value
    }

    func testEnforcesTheFiveMinuteByteLimit() async throws {
        let (client, transport) = try await startedClient()
        await transport.setRecordAudio(false)

        for _ in 0..<1_500 {
            try await client.send(audio: Data(repeating: 0, count: 6_400))
        }
        let snapshot = await transport.snapshot()
        XCTAssertEqual(snapshot.audioBytes, 9_600_000)
        do {
            try await client.send(audio: Data([0, 0]))
            XCTFail("audio over the five-minute limit was accepted")
        } catch {
            XCTAssertEqual(error as? RealtimeDictationError, .audioLimitExceeded)
        }
        await client.cancel()
    }

    func testCancellationIsIdempotentAndClosesTheTransport() async throws {
        let (client, transport) = try await startedClient()
        await client.cancel()
        await client.cancel()

        let snapshot = await transport.snapshot()
        let clientState = await client.state
        XCTAssertEqual(snapshot.controls, [.start(), .cancel])
        XCTAssertEqual(snapshot.closeCount, 1)
        XCTAssertEqual(clientState, .ended)
    }

    func testMapsInvalidSequenceWithoutReturningPartialText() async throws {
        let (client, transport) = try await startedClient()
        let finish = Task { try await client.finish() }
        try await waitUntil {
            await transport.snapshot().controls.last == .finish
        }
        await transport.push(.partial(text: "不应返回"))
        await transport.push(.failed(code: .invalidSequence))
        await transport.push(.ended)

        do {
            _ = try await finish.value
            XCTFail("public invalid sequence returned success")
        } catch {
            XCTAssertEqual(error as? RealtimeDictationError, .protocolViolation)
        }
        let snapshot = await transport.snapshot()
        XCTAssertEqual(snapshot.closeCount, 1)
    }

    func testRejectsDuplicateAndLateFinals() async throws {
        let (client, transport) = try await startedClient()
        let finish = Task { try await client.finish() }
        try await waitUntil {
            await transport.snapshot().controls.last == .finish
        }
        await transport.push(.final(text: "第一份。"))
        await transport.push(.final(text: "第二份。"))
        await transport.push(.ended)

        do {
            _ = try await finish.value
            XCTFail("duplicate final was accepted")
        } catch {
            XCTAssertEqual(error as? RealtimeDictationError, .protocolViolation)
        }

        do {
            _ = try await client.finish()
            XCTFail("late finish was accepted")
        } catch {
            XCTAssertEqual(error as? RealtimeDictationError, .invalidState)
        }
    }

    private func startedClient(
        mode: RealtimeSessionMode = .dictation
    ) async throws -> (
        StreamingDictationClient,
        FakeRealtimeTransport
    ) {
        let transport = FakeRealtimeTransport()
        let client = StreamingDictationClient(transport: transport)
        let prompt = mode == .smart
            ? try BuiltInTextOptimizationPrompt.loadCurrent()
            : nil
        let start = Task {
            try await client.start(accessToken: "token", mode: mode)
        }
        try await waitUntil {
            await transport.snapshot().controls == [
                .start(mode, prompt: prompt),
            ]
        }
        await transport.push(
            .started
        )
        try await start.value
        return (client, transport)
    }

    private func assertProtocolViolation(
        _ task: Task<DictationStreamingResult, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await task.value
            XCTFail("protocol violation was accepted", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? RealtimeDictationError,
                .protocolViolation,
                file: file,
                line: line
            )
        }
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        _ predicate: @escaping @Sendable () async -> Bool
    ) async throws {
        let started = ContinuousClock.now
        while !(await predicate()) {
            if ContinuousClock.now - started > .nanoseconds(Int64(timeoutNanoseconds)) {
                XCTFail("condition timed out")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
