import Foundation

protocol CustomAITestAudioProviding: Sendable {
    func wavSample() async throws -> Data
}

struct CustomAIFixedTestAudioProvider: CustomAITestAudioProviding {
    func wavSample() async throws -> Data {
        CustomAIPublicTestAudio.wav()
    }
}

private enum CustomAIPublicTestAudio {
    static func wav() -> Data {
        let sampleRate: UInt32 = 16_000
        let sampleCount = Int(sampleRate / 2)
        let frequency = 440.0
        let amplitude = 1_800.0
        var pcm = Data(capacity: sampleCount * MemoryLayout<Int16>.size)

        for index in 0..<sampleCount {
            let phase = 2 * Double.pi * frequency * Double(index) /
                Double(sampleRate)
            append(Int16(sin(phase) * amplitude), to: &pcm)
        }

        var result = Data(capacity: 44 + pcm.count)
        result.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        append(UInt32(36 + pcm.count), to: &result)
        result.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
        result.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
        append(UInt32(16), to: &result)
        append(UInt16(1), to: &result)
        append(UInt16(1), to: &result)
        append(sampleRate, to: &result)
        append(sampleRate * 2, to: &result)
        append(UInt16(2), to: &result)
        append(UInt16(16), to: &result)
        result.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        append(UInt32(pcm.count), to: &result)
        result.append(pcm)
        return result
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) {
            data.append(contentsOf: $0)
        }
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) {
            data.append(contentsOf: $0)
        }
    }

    private static func append(_ value: Int16, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) {
            data.append(contentsOf: $0)
        }
    }
}

struct CustomAIProductionSettingsTester: CustomAIConfigurationTesting {
    private static let fixedOptimizationTestText =
        "This is sample text for testing a text optimization service."

    private let audio: any CustomAITestAudioProviding
    private let asr: any CustomAIASRServing
    private let optimizer: any CustomAIOptimizationServing
    private let promptLoader: CustomAIStreamingClient.PromptLoader

    init(
        audio: any CustomAITestAudioProviding =
            CustomAIFixedTestAudioProvider(),
        asr: any CustomAIASRServing = CustomAIProviderService(),
        optimizer: any CustomAIOptimizationServing = CustomAIProviderService(),
        promptLoader: @escaping CustomAIStreamingClient.PromptLoader = {
            try BuiltInTextOptimizationPrompt.loadCurrent()
        }
    ) {
        self.audio = audio
        self.asr = asr
        self.optimizer = optimizer
        self.promptLoader = promptLoader
    }

    func test(
        _ scope: CustomAITestScope,
        configuration: CustomAIRuntimeConfiguration
    ) async throws {
        switch scope {
        case .asr:
            _ = try await transcribe(configuration)
        case .optimization:
            _ = try await optimize(
                Self.fixedOptimizationTestText,
                configuration: configuration
            )
        case .all:
            let raw = try await transcribe(configuration)
            _ = try await optimize(raw, configuration: configuration)
        }
    }

    private func transcribe(
        _ configuration: CustomAIRuntimeConfiguration
    ) async throws -> String {
        do {
            let wav = try await audio.wavSample()
            let raw = try await asr.transcribe(
                wavAudio: wav,
                selection: configuration.asr
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                throw CustomAIPipelineError.emptyASRResult
            }
            return raw
        } catch {
            throw CustomAITestFailureClassifier.failure(error, stage: .asr)
        }
    }

    private func optimize(
        _ raw: String,
        configuration: CustomAIRuntimeConfiguration
    ) async throws -> String {
        do {
            let optimized = try await optimizer.optimize(
                rawText: raw,
                prompt: try promptLoader(),
                selection: configuration.optimization
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !optimized.isEmpty else {
                throw CustomAIPipelineError.emptyASRResult
            }
            return optimized
        } catch {
            throw CustomAITestFailureClassifier.failure(
                error,
                stage: .optimization
            )
        }
    }
}
