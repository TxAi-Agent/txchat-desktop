import Foundation
import XCTest
@testable import SpekWrite

final class PublicLocalBootstrapCredentialStoreTests: XCTestCase {
    func testLoadsOnceRotatesAndDeletesOnlyInMemory() async throws {
        let counter = PublicLocalBootstrapCounter()
        let first = Self.credential(marker: "a")
        let second = Self.credential(marker: "b")
        let store = PublicLocalBootstrapCredentialStore {
            await counter.increment()
            return first
        }

        async let left = store.load()
        async let right = store.load()
        let leftValue = try await left
        let rightValue = try await right
        let initialBootstrapCount = await counter.value()
        XCTAssertEqual(leftValue, first)
        XCTAssertEqual(rightValue, first)
        XCTAssertEqual(initialBootstrapCount, 1)

        try await store.replace(with: second)
        let rotated = try await store.load()
        XCTAssertEqual(rotated, second)
        try await store.delete()
        let reloaded = try await store.load()
        let finalBootstrapCount = await counter.value()
        XCTAssertEqual(reloaded, first)
        XCTAssertEqual(finalBootstrapCount, 2)
    }

    private static func credential(marker: Character) -> StoredRefreshCredential {
        StoredRefreshCredential(
            refreshToken: String(repeating: marker, count: 43),
            sessionID: UUID().uuidString.lowercased()
        )
    }
}

private actor PublicLocalBootstrapCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}
