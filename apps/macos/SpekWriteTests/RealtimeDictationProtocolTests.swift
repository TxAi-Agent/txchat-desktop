import Foundation
import XCTest
@testable import SpekWrite

final class RealtimeDictationProtocolTests: XCTestCase {
    func testEncodesExactPublicLocalClientControls() throws {
        XCTAssertEqual(
            try string(RealtimeProtocolCodec.encode(.start())),
            #"{"audio":{"channels":1,"encoding":"pcm_s16le","sampleRate":16000},"organizationMode":"verbatim","protocol":"txchat.public-local.v1","type":"start"}"#
        )
        XCTAssertEqual(
            try string(RealtimeProtocolCodec.encode(.finish)),
            #"{"protocol":"txchat.public-local.v1","type":"finish"}"#
        )
        XCTAssertEqual(
            try string(RealtimeProtocolCodec.encode(.cancel)),
            #"{"protocol":"txchat.public-local.v1","type":"cancel"}"#
        )
        XCTAssertThrowsError(
            try RealtimeProtocolCodec.encode(.start(.smart))
        )
    }

    func testDecodesStrictPublicLocalServerControls() throws {
        XCTAssertEqual(
            try decode(#"{"protocol":"txchat.public-local.v1","type":"started"}"#),
            .started
        )
        XCTAssertEqual(
            try decode(#"{"protocol":"txchat.public-local.v1","type":"partial","transcript":"draft"}"#),
            .partial(text: "draft")
        )
        XCTAssertEqual(
            try decode(#"{"protocol":"txchat.public-local.v1","type":"organizing"}"#),
            .organizing
        )
        XCTAssertEqual(
            try decode(#"{"protocol":"txchat.public-local.v1","type":"final","transcript":"draft","organizedText":"result"}"#),
            .publicLocalFinal(transcript: "draft", organizedText: "result")
        )
        XCTAssertEqual(
            try decode(#"{"protocol":"txchat.public-local.v1","type":"final","transcript":"same","organizedText":"same"}"#),
            .publicLocalFinal(transcript: "same", organizedText: "same")
        )
        XCTAssertEqual(
            try decode(#"{"protocol":"txchat.public-local.v1","type":"failed","code":"invalid_audio"}"#),
            .failed(code: .invalidAudio)
        )
        XCTAssertEqual(
            try decode(#"{"protocol":"txchat.public-local.v1","type":"ended","reason":"completed"}"#),
            .ended
        )
    }

    func testRejectsMissingWrongOrAdditionalProtocolFields() {
        for invalid in [
            #"{"type":"started"}"#,
            #"{"protocol":"synthetic.wrong.v1","type":"started"}"#,
            #"{"protocol":"txchat.public-local.v1","type":"started","extra":true}"#,
            #"{"protocol":"txchat.public-local.v1","type":"ended","reason":"unknown"}"#,
        ] {
            XCTAssertThrowsError(try decode(invalid))
        }
    }

    func testBoundsTranscriptAtCloudSchemaLimit() throws {
        let maximum = String(repeating: "a", count: 4_096)
        let data = try JSONSerialization.data(withJSONObject: [
            "protocol": TxChatPublicLocalContract.protocolIdentifier,
            "type": "partial",
            "transcript": maximum,
        ], options: [.sortedKeys])
        XCTAssertEqual(
            try RealtimeProtocolCodec.decodeServer(data),
            .partial(text: maximum)
        )

        let tooLong = String(repeating: "a", count: 4_097)
        let invalid = try JSONSerialization.data(withJSONObject: [
            "protocol": TxChatPublicLocalContract.protocolIdentifier,
            "type": "partial",
            "transcript": tooLong,
        ], options: [.sortedKeys])
        XCTAssertThrowsError(try RealtimeProtocolCodec.decodeServer(invalid))
    }

    private func decode(_ value: String) throws -> RealtimeServerControl {
        try RealtimeProtocolCodec.decodeServer(Data(value.utf8))
    }

    private func string(_ data: Data) throws -> String {
        try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
