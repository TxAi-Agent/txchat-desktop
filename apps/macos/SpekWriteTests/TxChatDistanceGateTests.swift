import Foundation
import XCTest
@testable import SpekWrite

final class TxChatDistanceGateTests: XCTestCase {
    func testAnalyzerAcceptsNonEscapingRawPCMWindow() throws {
        let pcm = SyntheticPCM16.sine(
            frequency: 1_000,
            decibels: -30,
            durationMilliseconds: 20
        )

        let metrics = try pcm.withUnsafeBytes { bytes in
            try TxChatPCMWindowAnalyzer.analyze(bytes)
        }

        XCTAssertEqual(metrics.levelDBFS, -33.01, accuracy: 0.35)
        XCTAssertGreaterThanOrEqual(
            metrics.speechBandRatio,
            TxChatDistanceGateParameters.minimumSpeechBandRatio
        )
    }

    func testCalibrationBuildsApprovedThresholdsFromQuietAndSpeechWindows()
        throws
    {
        let device = TxChatInputDeviceIdentity(
            uid: "test-input-a",
            displayName: "Test Input"
        )

        let profile = try TxChatCalibrationPolicy().makeProfile(
            device: device,
            quietPCM: SyntheticPCM16.sine(
                frequency: 1_000,
                decibels: -50,
                durationMilliseconds: 2_000
            ),
            speechPCM: SyntheticPCM16.sine(
                frequency: 1_000,
                decibels: -30,
                durationMilliseconds: 5_000
            ),
            createdAt: Date(timeIntervalSince1970: 42)
        )

        XCTAssertEqual(profile.device, device)
        XCTAssertEqual(profile.quietP95DBFS, -53.01, accuracy: 0.35)
        XCTAssertEqual(profile.speechP20DBFS, -33.01, accuracy: 0.35)
        XCTAssertEqual(profile.openThresholdDBFS, -37.01, accuracy: 0.35)
        XCTAssertEqual(profile.holdThresholdDBFS, -39.01, accuracy: 0.35)
        XCTAssertEqual(profile.algorithmVersion, 1)
    }

    func testCalibrationRejectsSignalToNoiseGapBelowTenDecibels() {
        XCTAssertThrowsError(
            try TxChatCalibrationPolicy().makeProfile(
                device: .init(uid: "test-input-a", displayName: "Input"),
                quietPCM: SyntheticPCM16.sine(
                    frequency: 1_000,
                    decibels: -45,
                    durationMilliseconds: 2_000
                ),
                speechPCM: SyntheticPCM16.sine(
                    frequency: 1_000,
                    decibels: -37,
                    durationMilliseconds: 5_000
                ),
                createdAt: .distantPast
            )
        ) { error in
            XCTAssertEqual(
                error as? MicrophoneCalibrationFailure,
                .insufficientSignalToNoise
            )
        }
    }

    func testCalibrationRejectsLessThanTwoSecondsOfValidSpeech() {
        let oneSecondOfSpeech = SyntheticPCM16.sine(
            frequency: 1_000,
            decibels: -25,
            durationMilliseconds: 1_000
        )
        let fourSecondsOfSilence = Data(
            repeating: 0,
            count: 4 * 16_000 * MemoryLayout<Int16>.size
        )

        XCTAssertThrowsError(
            try TxChatCalibrationPolicy().makeProfile(
                device: .init(uid: "test-input-a", displayName: "Input"),
                quietPCM: SyntheticPCM16.sine(
                    frequency: 1_000,
                    decibels: -55,
                    durationMilliseconds: 2_000
                ),
                speechPCM: oneSecondOfSpeech + fourSecondsOfSilence,
                createdAt: .distantPast
            )
        ) { error in
            XCTAssertEqual(
                error as? MicrophoneCalibrationFailure,
                .insufficientSpeech
            )
        }
    }

    func testProfileIsInvalidForAnotherDeviceOrAlgorithmVersion() {
        let device = TxChatInputDeviceIdentity(
            uid: "test-input-a",
            displayName: "Input A"
        )
        let current = makeProfile(device: device)
        let old = TxChatDistanceGateProfile(
            device: device,
            quietP95DBFS: -50,
            speechP20DBFS: -25,
            openThresholdDBFS: -29,
            holdThresholdDBFS: -31,
            createdAt: .distantPast,
            algorithmVersion: 0
        )

        XCTAssertTrue(current.isValid(for: device))
        XCTAssertFalse(
            current.isValid(
                for: .init(uid: "test-input-b", displayName: "Input B")
            )
        )
        XCTAssertFalse(old.isValid(for: device))
    }

    func testProfileRejectsLowSignalToNoiseAndUnapprovedThresholds() {
        let device = TxChatInputDeviceIdentity(
            uid: "test-input-a",
            displayName: "Input A"
        )
        let lowSignalToNoise = makeProfile(
            device: device,
            quietP95DBFS: -50,
            speechP20DBFS: -42,
            openThresholdDBFS: -46,
            holdThresholdDBFS: -48
        )
        let forgedOpenThreshold = makeProfile(
            device: device,
            openThresholdDBFS: -35,
            holdThresholdDBFS: -37
        )
        let forgedHoldThreshold = makeProfile(
            device: device,
            holdThresholdDBFS: -32
        )

        for profile in [
            lowSignalToNoise,
            forgedOpenThreshold,
            forgedHoldThreshold,
        ] {
            XCTAssertFalse(profile.isValid(for: device))
            XCTAssertThrowsError(try TxChatDistanceGate(profile: profile)) {
                error in
                XCTAssertEqual(
                    error as? TxChatDistanceGateError,
                    .invalidProfile
                )
            }
        }
    }

    func testProfileRejectsDBFSValuesOutsidePhysicalRange() {
        let device = TxChatInputDeviceIdentity(
            uid: "test-input-a",
            displayName: "Input A"
        )
        let invalidProfiles = [
            makeProfile(device: device, quietP95DBFS: -121),
            makeProfile(device: device, speechP20DBFS: 0.1),
            makeProfile(device: device, openThresholdDBFS: 0.1),
            makeProfile(device: device, holdThresholdDBFS: -121),
        ]

        for profile in invalidProfiles {
            XCTAssertFalse(profile.isValid(for: device))
            XCTAssertThrowsError(try TxChatDistanceGate(profile: profile))
        }
    }

    func testGateZerosRejectedWindowWithoutChangingLength() throws {
        var gate = try TxChatDistanceGate(profile: makeProfile())
        let rejected = SyntheticPCM16.sine(
            frequency: 1_000,
            decibels: -55,
            durationMilliseconds: 20
        )

        let output = try gate.process(rejected)

        XCTAssertEqual(output.count, rejected.count)
        XCTAssertEqual(output, Data(repeating: 0, count: rejected.count))
    }

    func testGateOpensAfterTwoConsecutiveAcceptedWindows() throws {
        var gate = try TxChatDistanceGate(profile: makeProfile())
        let accepted = SyntheticPCM16.sine(
            frequency: 1_000,
            decibels: -20,
            durationMilliseconds: 20
        )

        let first = try gate.process(accepted)
        let second = try gate.process(accepted)
        let third = try gate.process(accepted)

        XCTAssertEqual(first, Data(repeating: 0, count: accepted.count))
        XCTAssertEqual(second, accepted)
        XCTAssertEqual(third, accepted)
    }

    func testGateUsesLowerHoldThresholdAndEightWindowRelease() throws {
        var gate = try TxChatDistanceGate(profile: makeProfile())
        let accepted = SyntheticPCM16.sine(
            frequency: 1_000,
            decibels: -20,
            durationMilliseconds: 20
        )
        let release = SyntheticPCM16.sine(
            frequency: 1_000,
            decibels: -60,
            durationMilliseconds: 20
        )
        _ = try gate.process(accepted)
        _ = try gate.process(accepted)

        for _ in 0..<8 {
            XCTAssertEqual(try gate.process(release), release)
        }
        XCTAssertEqual(
            try gate.process(release),
            Data(repeating: 0, count: release.count)
        )
    }

    func testGateRejectsEnergyOutsideSpeechBand() throws {
        var gate = try TxChatDistanceGate(profile: makeProfile())
        let outsideSpeechBand = SyntheticPCM16.sine(
            frequency: 50,
            decibels: -15,
            durationMilliseconds: 20
        )

        _ = try gate.process(outsideSpeechBand)
        let output = try gate.process(outsideSpeechBand)

        XCTAssertEqual(
            output,
            Data(repeating: 0, count: outsideSpeechBand.count)
        )
    }

    func testGateFinishReportsNoNearSpeechWhenNoWindowPassed() throws {
        var gate = try TxChatDistanceGate(profile: makeProfile())
        let rejected = SyntheticPCM16.sine(
            frequency: 1_000,
            decibels: -55,
            durationMilliseconds: 20
        )
        _ = try gate.process(rejected)

        let result = gate.finish()

        XCTAssertEqual(
            result.report,
            TxChatDistanceGateReport(passedWindows: 0, totalWindows: 1)
        )
        XCTAssertFalse(result.report.detectedNearSpeech)
        XCTAssertTrue(result.remainingPCM.isEmpty)
    }

    func testGateNeverAcceptsOddOrOversizedPCM() throws {
        var gate = try TxChatDistanceGate(profile: makeProfile())

        XCTAssertThrowsError(try gate.process(Data(repeating: 1, count: 1)))
        XCTAssertThrowsError(
            try gate.process(
                Data(
                    repeating: 1,
                    count: CoreRecordingLimits.maximumFrameBytes + 2
                )
            )
        )
    }

    private func makeProfile(
        device: TxChatInputDeviceIdentity = .init(
            uid: "test-input-a",
            displayName: "Input A"
        ),
        quietP95DBFS: Double = -50,
        speechP20DBFS: Double = -25,
        openThresholdDBFS: Double = -29,
        holdThresholdDBFS: Double = -31
    ) -> TxChatDistanceGateProfile {
        TxChatDistanceGateProfile(
            device: device,
            quietP95DBFS: quietP95DBFS,
            speechP20DBFS: speechP20DBFS,
            openThresholdDBFS: openThresholdDBFS,
            holdThresholdDBFS: holdThresholdDBFS,
            createdAt: .distantPast,
            algorithmVersion: TxChatDistanceGateProfile.currentAlgorithmVersion
        )
    }
}

enum SyntheticPCM16 {
    static func sine(
        frequency: Double,
        decibels: Double,
        durationMilliseconds: Int,
        sampleRate: Double = 16_000
    ) -> Data {
        let count = Int(sampleRate * Double(durationMilliseconds) / 1_000)
        let amplitude = pow(10, decibels / 20) * Double(Int16.max)
        var data = Data(capacity: count * MemoryLayout<Int16>.size)
        for index in 0..<count {
            let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
            var sample = Int16(
                clamping: Int((sin(phase) * amplitude).rounded())
            ).littleEndian
            withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
        }
        return data
    }
}
