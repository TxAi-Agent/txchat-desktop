import Foundation

struct TxChatInputDeviceIdentity: Codable, Equatable, Sendable {
    let uid: String
    let displayName: String
}

struct TxChatDistanceGateProfile: Codable, Equatable, Sendable {
    static let currentAlgorithmVersion = 1
    private static let minimumDBFS = -120.0
    private static let maximumDBFS = 0.0
    private static let minimumSignalToNoiseDB = 10.0
    private static let thresholdTolerance = 0.000_001

    let device: TxChatInputDeviceIdentity
    let quietP95DBFS: Double
    let speechP20DBFS: Double
    let openThresholdDBFS: Double
    let holdThresholdDBFS: Double
    let createdAt: Date
    let algorithmVersion: Int

    func isValid(for candidate: TxChatInputDeviceIdentity) -> Bool {
        let dbfsValues = [
            quietP95DBFS,
            speechP20DBFS,
            openThresholdDBFS,
            holdThresholdDBFS,
        ]
        guard !device.uid.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty,
            !candidate.uid.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty,
            device.uid == candidate.uid,
            algorithmVersion == Self.currentAlgorithmVersion,
            createdAt.timeIntervalSinceReferenceDate.isFinite,
            dbfsValues.allSatisfy({ value in
                value.isFinite &&
                    value >= Self.minimumDBFS &&
                    value <= Self.maximumDBFS
            }),
            speechP20DBFS - quietP95DBFS >=
                Self.minimumSignalToNoiseDB else {
            return false
        }

        let expectedOpenThreshold = max(
            quietP95DBFS + 8,
            speechP20DBFS - 4
        )
        let expectedHoldThreshold = expectedOpenThreshold - 2
        return abs(openThresholdDBFS - expectedOpenThreshold) <=
                Self.thresholdTolerance &&
            abs(holdThresholdDBFS - expectedHoldThreshold) <=
                Self.thresholdTolerance
    }
}

enum MicrophoneCalibrationFailure: Error, Equatable, Sendable {
    case inputDeviceUnavailable
    case inputDeviceChanged
    case invalidPCM
    case insufficientSignalToNoise
    case insufficientSpeech
    case alreadyRunning
}

enum TxChatDistanceGateError: Error, Equatable, Sendable {
    case invalidProfile
    case invalidPCM
}

enum TxChatDistanceGateParameters {
    static let sampleRate = 16_000
    static let windowMilliseconds = 20
    static let samplesPerWindow = 320
    static let bytesPerWindow = 640
    static let attackWindows = 2
    static let releaseWindows = 8
    static let maximumInputBytes = 6_400
    static let minimumSpeechBandRatio = 0.45
    static let lowCutHertz = 120.0
    static let highCutHertz = 4_200.0
}

struct TxChatPCMWindowMetrics: Equatable, Sendable {
    let levelDBFS: Double
    let speechBandRatio: Double
}

enum TxChatPCMWindowAnalyzer {
    private static let minimumDBFS = -120.0

    static func analyze(
        _ pcm16: UnsafeRawBufferPointer
    ) throws -> TxChatPCMWindowMetrics {
        guard pcm16.count == TxChatDistanceGateParameters.bytesPerWindow else {
            throw MicrophoneCalibrationFailure.invalidPCM
        }

        let samples = (
            0..<TxChatDistanceGateParameters.samplesPerWindow
        ).map { index in
            let raw = pcm16.loadUnaligned(
                fromByteOffset: index * MemoryLayout<Int16>.size,
                as: Int16.self
            )
            return Double(Int16(littleEndian: raw)) / 32_768.0
        }
        let totalEnergy = samples.reduce(0.0) { $0 + $1 * $1 }
        guard totalEnergy > 0, totalEnergy.isFinite else {
            return TxChatPCMWindowMetrics(
                levelDBFS: minimumDBFS,
                speechBandRatio: 0
            )
        }

        let sampleInterval = 1.0 / Double(TxChatDistanceGateParameters.sampleRate)
        let highPassRC = 1.0 / (
            2 * Double.pi * TxChatDistanceGateParameters.lowCutHertz
        )
        let highPassAlpha = highPassRC / (highPassRC + sampleInterval)
        let lowPassRC = 1.0 / (
            2 * Double.pi * TxChatDistanceGateParameters.highCutHertz
        )
        let lowPassAlpha = sampleInterval / (lowPassRC + sampleInterval)
        var previousInput = 0.0
        var previousHighPass = 0.0
        var previousBandPass = 0.0
        var bandEnergy = 0.0
        for sample in samples {
            let highPass = highPassAlpha * (
                previousHighPass + sample - previousInput
            )
            let bandPass = previousBandPass +
                lowPassAlpha * (highPass - previousBandPass)
            bandEnergy += bandPass * bandPass
            previousInput = sample
            previousHighPass = highPass
            previousBandPass = bandPass
        }

        let rms = sqrt(totalEnergy / Double(samples.count))
        let level = max(20 * log10(rms), minimumDBFS)
        let ratio = min(max(bandEnergy / totalEnergy, 0), 1)
        return TxChatPCMWindowMetrics(
            levelDBFS: level,
            speechBandRatio: ratio
        )
    }
}

struct TxChatCalibrationPolicy: Sendable {
    func makeProfile(
        device: TxChatInputDeviceIdentity,
        quietPCM: Data,
        speechPCM: Data,
        createdAt: Date
    ) throws -> TxChatDistanceGateProfile {
        let quietBytes = 2 * TxChatDistanceGateParameters.sampleRate *
            MemoryLayout<Int16>.size
        let speechBytes = 5 * TxChatDistanceGateParameters.sampleRate *
            MemoryLayout<Int16>.size
        guard quietPCM.count == quietBytes,
              speechPCM.count == speechBytes else {
            throw MicrophoneCalibrationFailure.invalidPCM
        }

        let quietMetrics = try metrics(for: quietPCM)
        let quietP95 = try percentile(
            quietMetrics.map(\.levelDBFS),
            percentile: 0.95
        )
        let validSpeech = try metrics(for: speechPCM).filter { metrics in
            metrics.speechBandRatio >=
                TxChatDistanceGateParameters.minimumSpeechBandRatio &&
                metrics.levelDBFS >= quietP95 + 3
        }
        let validSpeechMilliseconds = validSpeech.count *
            TxChatDistanceGateParameters.windowMilliseconds
        guard validSpeechMilliseconds >= 2_000 else {
            throw MicrophoneCalibrationFailure.insufficientSpeech
        }

        let speechP20 = try percentile(
            validSpeech.map(\.levelDBFS),
            percentile: 0.20
        )
        guard speechP20 - quietP95 >= 10 else {
            throw MicrophoneCalibrationFailure.insufficientSignalToNoise
        }
        let openThreshold = max(quietP95 + 8, speechP20 - 4)
        return TxChatDistanceGateProfile(
            device: device,
            quietP95DBFS: quietP95,
            speechP20DBFS: speechP20,
            openThresholdDBFS: openThreshold,
            holdThresholdDBFS: openThreshold - 2,
            createdAt: createdAt,
            algorithmVersion:
                TxChatDistanceGateProfile.currentAlgorithmVersion
        )
    }

    private func metrics(
        for pcm16: Data
    ) throws -> [TxChatPCMWindowMetrics] {
        guard !pcm16.isEmpty,
              pcm16.count.isMultiple(
                of: TxChatDistanceGateParameters.bytesPerWindow
              ) else {
            throw MicrophoneCalibrationFailure.invalidPCM
        }
        return try pcm16.withUnsafeBytes { bytes in
            var result: [TxChatPCMWindowMetrics] = []
            result.reserveCapacity(
                pcm16.count / TxChatDistanceGateParameters.bytesPerWindow
            )
            var offset = 0
            while offset < bytes.count {
                let end = offset + TxChatDistanceGateParameters.bytesPerWindow
                result.append(
                    try TxChatPCMWindowAnalyzer.analyze(
                        UnsafeRawBufferPointer(
                            rebasing: bytes[offset..<end]
                        )
                    )
                )
                offset = end
            }
            return result
        }
    }

    private func percentile(
        _ values: [Double],
        percentile: Double
    ) throws -> Double {
        guard !values.isEmpty,
              values.allSatisfy(\.isFinite),
              percentile > 0,
              percentile <= 1 else {
            throw MicrophoneCalibrationFailure.invalidPCM
        }
        let sorted = values.sorted()
        let nearestRank = Int(ceil(percentile * Double(sorted.count)))
        return sorted[max(nearestRank - 1, 0)]
    }
}

struct TxChatDistanceGateReport: Equatable, Sendable {
    let passedWindows: Int
    let totalWindows: Int

    var detectedNearSpeech: Bool {
        passedWindows > 0
    }
}

struct TxChatDistanceGateFinish: Equatable, Sendable {
    let remainingPCM: Data
    let report: TxChatDistanceGateReport
}

struct TxChatDistanceGate: Sendable {
    private let profile: TxChatDistanceGateProfile
    private var pending = Data()
    private var consecutiveOpenWindows = 0
    private var releaseWindowsRemaining = 0
    private var isOpen = false
    private var passedWindows = 0
    private var totalWindows = 0

    init(profile: TxChatDistanceGateProfile) throws {
        guard profile.isValid(for: profile.device) else {
            throw TxChatDistanceGateError.invalidProfile
        }
        self.profile = profile
    }

    mutating func process(_ pcm16: Data) throws -> Data {
        guard !pcm16.isEmpty,
              pcm16.count.isMultiple(of: MemoryLayout<Int16>.size),
              pcm16.count <= TxChatDistanceGateParameters.maximumInputBytes else {
            discardPending()
            throw TxChatDistanceGateError.invalidPCM
        }
        pending.append(pcm16)
        var output = Data()
        output.reserveCapacity(pending.count)
        while pending.count >= TxChatDistanceGateParameters.bytesPerWindow {
            let window = Data(
                pending.prefix(TxChatDistanceGateParameters.bytesPerWindow)
            )
            pending.resetBytes(
                in: 0..<TxChatDistanceGateParameters.bytesPerWindow
            )
            pending.removeFirst(TxChatDistanceGateParameters.bytesPerWindow)
            output.append(try processWindow(window))
        }
        return output
    }

    mutating func finish() -> TxChatDistanceGateFinish {
        var remaining = Data()
        if !pending.isEmpty {
            totalWindows += 1
            remaining = Data(repeating: 0, count: pending.count)
            discardPending()
        }
        let report = TxChatDistanceGateReport(
            passedWindows: passedWindows,
            totalWindows: totalWindows
        )
        isOpen = false
        consecutiveOpenWindows = 0
        releaseWindowsRemaining = 0
        return TxChatDistanceGateFinish(
            remainingPCM: remaining,
            report: report
        )
    }

    mutating func cancel() {
        discardPending()
        isOpen = false
        consecutiveOpenWindows = 0
        releaseWindowsRemaining = 0
    }

    private mutating func processWindow(_ window: Data) throws -> Data {
        let metrics = try window.withUnsafeBytes { bytes in
            try TxChatPCMWindowAnalyzer.analyze(bytes)
        }
        totalWindows += 1
        let isSpeechBand = metrics.speechBandRatio >=
            TxChatDistanceGateParameters.minimumSpeechBandRatio

        if isOpen {
            if isSpeechBand &&
                metrics.levelDBFS >= profile.holdThresholdDBFS {
                releaseWindowsRemaining =
                    TxChatDistanceGateParameters.releaseWindows
                passedWindows += 1
                return window
            }
            if releaseWindowsRemaining > 0 {
                releaseWindowsRemaining -= 1
                passedWindows += 1
                return window
            }
            isOpen = false
            consecutiveOpenWindows = 0
            return Data(repeating: 0, count: window.count)
        }

        let isOpenCandidate = isSpeechBand &&
            metrics.levelDBFS >= profile.openThresholdDBFS
        consecutiveOpenWindows = isOpenCandidate
            ? consecutiveOpenWindows + 1
            : 0
        guard consecutiveOpenWindows >=
                TxChatDistanceGateParameters.attackWindows else {
            return Data(repeating: 0, count: window.count)
        }
        isOpen = true
        releaseWindowsRemaining = TxChatDistanceGateParameters.releaseWindows
        passedWindows += 1
        return window
    }

    private mutating func discardPending() {
        pending.resetBytes(in: 0..<pending.count)
        pending.removeAll(keepingCapacity: false)
    }
}
