import Foundation

protocol CustomAIConfigurationStoring: Sendable {
    func load() async throws -> CustomAIConfiguration
    func save(_ configuration: CustomAIConfiguration) async throws
    func saveMigrated(
        _ configuration: CustomAIConfiguration,
        ifUnchangedFrom storedConfiguration: CustomAIConfiguration
    ) async throws -> Bool
}

extension CustomAIConfigurationStoring {
    // In-memory test stores use this best-effort fallback. The production
    // UserDefaults store overrides it with a serialized atomic comparison.
    func saveMigrated(
        _ configuration: CustomAIConfiguration,
        ifUnchangedFrom storedConfiguration: CustomAIConfiguration
    ) async throws -> Bool {
        guard try await load() == storedConfiguration else { return false }
        try await save(configuration)
        return true
    }
}

final class UserDefaultsCustomAIConfigurationStore: @unchecked Sendable,
    CustomAIConfigurationStoring
{
    enum Error: Swift.Error, Equatable, Sendable {
        case invalidConfiguration
        case oversizedConfiguration
        case encodingFailed
    }

    static let key = "txchat.custom-ai.configuration.v3"
    static let schemaV2Key = "txchat.custom-ai.configuration.v2"
    static let schemaV1Key = "txchat.custom-ai.configuration.v1"
    static let persistenceKeys = [key, schemaV2Key, schemaV1Key]
    static let maximumBytes = 16_384
    private static let persistenceQueue = DispatchQueue(
        label: "org.example.txchat.custom-ai.configuration-store"
    )

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() async throws -> CustomAIConfiguration {
        try Self.persistenceQueue.sync { try loadStoredConfiguration() }
    }

    func save(_ configuration: CustomAIConfiguration) async throws {
        try Self.persistenceQueue.sync { try persist(configuration) }
    }

    func saveMigrated(
        _ configuration: CustomAIConfiguration,
        ifUnchangedFrom storedConfiguration: CustomAIConfiguration
    ) async throws -> Bool {
        try Self.persistenceQueue.sync {
            guard try loadStoredConfiguration() == storedConfiguration else {
                return false
            }
            try persist(configuration)
            return true
        }
    }

    private func loadStoredConfiguration() throws -> CustomAIConfiguration {
        guard let persistenceKey = Self.persistenceKeys.first(where: {
            self.defaults.object(forKey: $0) != nil
        }) else {
            return .default
        }
        guard let data = defaults.object(forKey: persistenceKey) as? Data else {
            throw Error.invalidConfiguration
        }
        guard !data.isEmpty, data.count <= Self.maximumBytes else {
            throw Error.oversizedConfiguration
        }
        guard let configuration = try? JSONDecoder().decode(
            CustomAIConfiguration.self,
            from: data
        ), configuration.isLoadableForMigration else {
            throw Error.invalidConfiguration
        }
        return configuration
    }

    private func persist(_ configuration: CustomAIConfiguration) throws {
        guard configuration.schemaVersion == CustomAIConfiguration.schemaVersion,
              configuration.isCatalogValid else {
            throw Error.invalidConfiguration
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(configuration) else {
            throw Error.encodingFailed
        }
        guard !data.isEmpty, data.count <= Self.maximumBytes else {
            throw Error.oversizedConfiguration
        }
        defaults.set(data, forKey: Self.key)
    }
}

enum CustomAIRuntimeConfigurationError: Error, Equatable, Sendable {
    case invalidConfiguration
    case missingRequiredField(
        category: CustomAIServiceCategory,
        providerID: String,
        fieldID: CustomAIFieldID
    )
}

actor CustomAIRuntimeConfigurationResolver {
    private let configurations: any CustomAIConfigurationStoring
    private let secrets: any CustomAISecretStoring

    init(
        configurations: any CustomAIConfigurationStoring,
        secrets: any CustomAISecretStoring
    ) {
        self.configurations = configurations
        self.secrets = secrets
    }

    func resolve() async throws -> CustomAIRuntimeConfiguration? {
        while true {
            let storedConfiguration = try await configurations.load()
            let secretReferences = try await legacyMigrationSecretReferences(
                storedConfiguration
            )
            let configuration = storedConfiguration.migrated(
                secretReferencesWithValues: secretReferences
            )
            guard configuration.isCatalogValid else {
                throw CustomAIRuntimeConfigurationError.invalidConfiguration
            }
            if configuration != storedConfiguration {
                let saved = try await configurations.saveMigrated(
                    configuration,
                    ifUnchangedFrom: storedConfiguration
                )
                guard saved else { continue }
            }
            guard configuration.isEnabled else {
                return nil
            }
            guard let asr = configuration.asr,
                  let optimization = configuration.optimization,
                  let asrProvider = CustomAIProviderCatalog.asrProvider(
                      asr.providerID
                  ), let optimizationProvider =
                CustomAIProviderCatalog.optimizationProvider(
                    optimization.providerID
                ) else {
                throw CustomAIRuntimeConfigurationError.invalidConfiguration
            }

            let asrValues = try await resolveValues(
                category: .asr,
                providerID: asr.providerID.rawValue,
                fields: asrProvider.fields,
                nonsecret: asr.nonsecretValues
            )
            let optimizationValues = try await resolveValues(
                category: .optimization,
                providerID: optimization.providerID.rawValue,
                fields: optimizationProvider.fields,
                nonsecret: optimization.nonsecretValues
            )
            return CustomAIRuntimeConfiguration(
                asr: .init(
                    providerID: asr.providerID.rawValue,
                    modelID: asr.modelID,
                    values: asrValues
                ),
                optimization: .init(
                    providerID: optimization.providerID.rawValue,
                    modelID: optimization.modelID,
                    values: optimizationValues
                )
            )
        }
    }

    private func legacyMigrationSecretReferences(
        _ configuration: CustomAIConfiguration
    ) async throws -> Set<CustomAISecretReference> {
        guard configuration.schemaVersion == 1 else { return [] }
        var references: Set<CustomAISecretReference> = []
        if let providerID = configuration.selectedASRProviderID,
           let provider = CustomAIProviderCatalog.asrProvider(providerID) {
            for field in provider.fields where field.isSecret && field.isRequired {
                let reference = CustomAISecretReference(
                    category: .asr,
                    providerID: providerID.rawValue,
                    fieldID: field.id
                )
                if try await secrets.load(reference) != nil {
                    references.insert(reference)
                }
            }
        }
        if let providerID = configuration.selectedOptimizationProviderID,
           let provider = CustomAIProviderCatalog.optimizationProvider(
               providerID
           ) {
            for field in provider.fields where field.isSecret && field.isRequired {
                let reference = CustomAISecretReference(
                    category: .optimization,
                    providerID: providerID.rawValue,
                    fieldID: field.id
                )
                if try await secrets.load(reference) != nil {
                    references.insert(reference)
                }
            }
        }
        return references
    }

    private func resolveValues(
        category: CustomAIServiceCategory,
        providerID: String,
        fields: [CustomAIFieldDescriptor],
        nonsecret: [CustomAIFieldID: String]
    ) async throws -> [CustomAIFieldID: String] {
        var values: [CustomAIFieldID: String] = [:]
        for field in fields {
            let value: String?
            if field.isSecret {
                value = try await secrets.load(
                    .init(
                        category: category,
                        providerID: providerID,
                        fieldID: field.id
                    )
                )
            } else {
                value = nonsecret[field.id] ?? field.defaultValue
            }
            if let value, Self.isValidValue(value) {
                values[field.id] = value
            } else if field.isRequired {
                throw CustomAIRuntimeConfigurationError.missingRequiredField(
                    category: category,
                    providerID: providerID,
                    fieldID: field.id
                )
            }
        }
        return values
    }

    private static func isValidValue(_ value: String) -> Bool {
        value == value.trimmingCharacters(in: .whitespacesAndNewlines) &&
            !value.isEmpty &&
            value.utf8.count <= 16_384 &&
            !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
    }
}
