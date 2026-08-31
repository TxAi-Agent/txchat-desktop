import Foundation
import XCTest
@testable import SpekWrite

final class PublicLocalStreamingClientTests: XCTestCase {
    func testCompletesPublicLocalSmartSequenceWithoutGuessingModeFromText() async throws {
        let transcript = "Synthetic public-local dictation completed."
        let transport = PublicLocalScriptedTransport(transcript: transcript)
        let client = StreamingDictationClient(
            transport: transport,
            promptLoader: {
                TextOptimizationPrompt(
                    version: "synthetic-public-test",
                    sha256: String(repeating: "0", count: 64),
                    utf8Bytes: 1,
                    content: "x"
                )
            }
        )

        try await client.start(
            accessToken: String(repeating: "a", count: 43),
            mode: .smart
        )
        try await client.send(audio: Data(repeating: 0, count: 320))
        let result = try await client.finishResult()

        XCTAssertEqual(result.text, transcript)
        XCTAssertEqual(result.mode, .smart)
    }
}

private actor PublicLocalScriptedTransport: RealtimeDictationTransport {
    private let transcript: String
    private var pending: [RealtimeServerControl] = []
    private var waiters: [CheckedContinuation<RealtimeServerControl, Never>] = []

    init(transcript: String) {
        self.transcript = transcript
    }

    func connect(accessToken: String) async throws {
        guard !accessToken.isEmpty else {
            throw RealtimeDictationError.authRequired
        }
    }

    func send(control: RealtimeClientControl) async throws {
        switch control {
        case .start:
            push(.started)
        case .finish:
            push(.organizing)
            push(.publicLocalFinal(
                transcript: transcript,
                organizedText: transcript
            ))
            push(.ended)
        case .cancel:
            push(.ended)
        }
    }

    func send(audio: Data) async throws {
        guard !audio.isEmpty else {
            throw RealtimeDictationError.invalidAudioFrame
        }
    }

    func receive() async throws -> RealtimeServerControl {
        if !pending.isEmpty {
            return pending.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func close() async {}

    private func push(_ value: RealtimeServerControl) {
        if !waiters.isEmpty {
            waiters.removeFirst().resume(returning: value)
        } else {
            pending.append(value)
        }
    }
}
