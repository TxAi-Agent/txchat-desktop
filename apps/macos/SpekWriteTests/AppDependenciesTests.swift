import XCTest
@testable import SpekWrite

private struct DependencyTestTokenProvider: DictationAccessTokenProviding {
    let value: String

    func accessToken() async throws -> String {
        value
    }
}

final class AppDependenciesTests: XCTestCase {
    func testSystemPCM16AudioSourceSatisfiesCalibrationBoundaryWithoutStarting() {
        let source: any PCM16AudioSourcing = SystemPCM16AudioSource()
        XCTAssertNotNil(source as AnyObject)
    }

    func testVerbatimFinalPreparerReturnsRawFinal() async throws {
        let preparer = VerbatimFinalTextPreparer()

        let result = try await preparer.prepare(
            "  原样终稿。  ",
            mode: .verbatim
        )

        XCTAssertEqual(result, "  原样终稿。  ")
    }

    func testSmartFinalPreparerConservativelyReturnsRawFinal() async throws {
        let preparer = VerbatimFinalTextPreparer()

        let result = try await preparer.prepare(
            "不做本地改写",
            mode: .smart
        )

        XCTAssertEqual(result, "不做本地改写")
    }

    func testEmptyAccessTokenIsRejectedBeforeSessionStart() async {
        let provider = DependencyTestTokenProvider(value: " \n\t ")

        do {
            _ = try await AppDependencies.validatedAccessToken(from: provider)
            XCTFail("whitespace-only token was accepted")
        } catch {
            XCTAssertEqual(error as? AppDependencyError, .invalidAccessToken)
        }
    }

    func testCoreAudioCaptureCanSatisfyProductionCaptureBoundaryWithoutStarting() {
        requireCaptureBoundary(CoreAudioCapture.self)
        requireStreamingBoundary(StreamingDictationClient.self)
    }

    private func requireCaptureBoundary<T: DictationAudioCapturing>(
        _ type: T.Type
    ) {}

    private func requireStreamingBoundary<T: DictationStreamingServing>(
        _ type: T.Type
    ) {}
}
