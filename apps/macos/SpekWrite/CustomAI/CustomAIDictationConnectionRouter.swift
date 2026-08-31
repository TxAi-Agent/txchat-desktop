import Foundation

@MainActor
final class CustomAIDictationConnectionRouter {
    typealias CloudFactory = @MainActor @Sendable () async throws ->
        DictationStreamingSession

    private let resolver: CustomAIRuntimeConfigurationResolver
    private let asr: any CustomAIASRServing
    private let optimizer: any CustomAIOptimizationServing
    private let cloud: CloudFactory
    private let promptLoader: CustomAIStreamingClient.PromptLoader

    init(
        resolver: CustomAIRuntimeConfigurationResolver,
        asr: any CustomAIASRServing,
        optimizer: any CustomAIOptimizationServing,
        cloud: @escaping CloudFactory,
        promptLoader: @escaping CustomAIStreamingClient.PromptLoader = {
            try BuiltInTextOptimizationPrompt.loadCurrent()
        }
    ) {
        self.resolver = resolver
        self.asr = asr
        self.optimizer = optimizer
        self.cloud = cloud
        self.promptLoader = promptLoader
    }

    func connection() async throws -> DictationStreamingSession {
        let configuration: CustomAIRuntimeConfiguration?
        do {
            configuration = try await resolver.resolve()
        } catch {
            throw CustomAIDiagnosticError.configurationFailure(error)
        }
        guard let configuration else {
            return try await cloud()
        }
        return DictationStreamingSession(
            client: CustomAIStreamingClient(
                configuration: configuration,
                asr: asr,
                optimizer: optimizer,
                promptLoader: promptLoader
            ),
            accessToken: "",
            backend: .custom
        )
    }
}
