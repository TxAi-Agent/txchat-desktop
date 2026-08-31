import Foundation
import XCTest
@testable import SpekWrite

final class TxChatPublicLocalContractTests: XCTestCase {
    func testDefinesThePublicLocalDevelopmentIdentity() {
        XCTAssertEqual(
            TxChatPublicLocalContract.protocolIdentifier,
            "txchat.public-local.v1"
        )
        XCTAssertEqual(
            TxChatPublicLocalContract.sessionPath,
            "/public-local/v1/session"
        )
        XCTAssertEqual(
            TxChatPublicLocalContract.refreshPath,
            "/public-local/v1/session/refresh"
        )
        XCTAssertEqual(
            TxChatPublicLocalContract.accountPath,
            "/public-local/v1/account"
        )
        XCTAssertEqual(
            TxChatPublicLocalContract.logoutPath,
            "/public-local/v1/logout"
        )
        XCTAssertEqual(
            TxChatPublicLocalContract.dictationPath,
            "/public-local/v1/dictation"
        )
        XCTAssertEqual(TxChatPublicLocalContract.audioMaxDurationSeconds, 300)
    }

    func testMatchesTheCompanionPublicCloudSchemaWhenProvided() throws {
        guard let schemaPath = ProcessInfo.processInfo.environment[
            "TXCHAT_PUBLIC_LOCAL_CLOUD_SCHEMA"
        ], !schemaPath.isEmpty else {
            throw XCTSkip("Companion public Cloud schema was not provided")
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: schemaPath))
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let contract = try XCTUnwrap(
            root["x-txchat-contract"] as? [String: Any]
        )
        let routes = try XCTUnwrap(contract["routes"] as? [String: String])
        let audio = try XCTUnwrap(contract["audio"] as? [String: Any])

        XCTAssertEqual(
            contract["protocolIdentifier"] as? String,
            TxChatPublicLocalContract.protocolIdentifier
        )
        XCTAssertEqual(routes["session"], TxChatPublicLocalContract.sessionPath)
        XCTAssertEqual(routes["refresh"], TxChatPublicLocalContract.refreshPath)
        XCTAssertEqual(routes["account"], TxChatPublicLocalContract.accountPath)
        XCTAssertEqual(routes["logout"], TxChatPublicLocalContract.logoutPath)
        XCTAssertEqual(routes["dictation"], TxChatPublicLocalContract.dictationPath)
        XCTAssertEqual(
            audio["maximumDurationSeconds"] as? Int,
            TxChatPublicLocalContract.audioMaxDurationSeconds
        )
    }
}
