import Combine
import Foundation

enum CustomAISettingsLoadState: Equatable, Sendable {
    case loading
    case ready
    case failed
}

enum CustomAITestScope: String, CaseIterable, Sendable {
    case asr
    case optimization
    case all
}

enum CustomAITestStatus: Equatable, Sendable {
    case idle
    case running
    case passed
    case failed
}

enum CustomAITestFailureCategory: Equatable, Hashable, Sendable {
    case microphone
    case audioSample
    case network
    case authentication
    case permissionOrModel
    case rateLimit
    case invalidRequest
    case incompatibleResponse
}

enum CustomAISettingsAlert: Equatable, Sendable {
    case unsavedChanges
    case invalidConfiguration
    case loadFailed
    case saveFailed
}

protocol CustomAIConfigurationTesting: Sendable {
    func test(
        _ scope: CustomAITestScope,
        configuration: CustomAIRuntimeConfiguration
    ) async throws
}

@MainActor
final class CustomAISettingsCoordinator: ObservableObject {
    typealias CloseHandler = @MainActor @Sendable () -> Void

    @Published private(set) var configuration = CustomAIConfiguration.default
    @Published private(set) var loadState = CustomAISettingsLoadState.loading
    @Published private(set) var testStatus: [CustomAITestScope: CustomAITestStatus] = [
        .asr: .idle,
        .optimization: .idle,
        .all: .idle,
    ]
    @Published private(set) var testFailureCategories:
        [CustomAITestScope: CustomAITestFailureCategory] = [:]
    @Published private(set) var testFailureStages:
        [CustomAITestScope: CustomAIProviderStage] = [:]
    @Published private(set) var testProviderFailures:
        [CustomAITestScope: CustomAIProviderFailure] = [:]
    @Published private(set) var alert: CustomAISettingsAlert?
    @Published private(set) var isSaving = false
    @Published private(set) var editingCategory: CustomAIServiceCategory?
    @Published private(set) var editingASRProviderID: CustomAIASRProviderID?
    @Published private(set) var editingOptimizationProviderID:
        CustomAIOptimizationProviderID?

    private let configurations: any CustomAIConfigurationStoring
    private let secrets: any CustomAISecretStoring
    private let tester: any CustomAIConfigurationTesting
    private let testDiagnostics: any CustomAITestDiagnosticRecording
    private var close: CloseHandler
    private var baselineConfiguration = CustomAIConfiguration.default
    private var baselineSecrets: [CustomAISecretReference: String] = [:]
    private var secretDrafts: [CustomAISecretReference: String] = [:]
    private var dirtySecretReferences: Set<CustomAISecretReference> = []
    private var editingSnapshot: EditingSnapshot?
    private var loadGeneration: UInt64 = 0
    private static let maximumMigrationLoadAttempts = 3

    private enum LoadError: Error {
        case migrationConflictLimitExceeded
    }

    private struct EditingSnapshot {
        let configuration: CustomAIConfiguration
        let secrets: [CustomAISecretReference: String]
        let dirtySecretReferences: Set<CustomAISecretReference>
    }

    init(
        configurations: any CustomAIConfigurationStoring,
        secrets: any CustomAISecretStoring,
        tester: any CustomAIConfigurationTesting,
        testDiagnostics: any CustomAITestDiagnosticRecording =
            NullCustomAITestDiagnosticRecorder(),
        close: @escaping CloseHandler = {}
    ) {
        self.configurations = configurations
        self.secrets = secrets
        self.tester = tester
        self.testDiagnostics = testDiagnostics
        self.close = close
    }

    func setCloseHandler(_ close: @escaping CloseHandler) {
        self.close = close
    }

    var hasUnsavedChanges: Bool {
        configuration != baselineConfiguration ||
            !dirtySecretReferences.isEmpty
    }

    var actionsDisabled: Bool {
        isSaving || testStatus.values.contains(.running)
    }

    var hasAnySelectedProvider: Bool {
        configuration.selectedASRProviderID != nil ||
            configuration.selectedOptimizationProviderID != nil
    }

    var canRunOverallTest: Bool {
        guard configuration.isEnabled,
              let asr = configuration.selectedASRProviderID,
              let optimization =
                configuration.selectedOptimizationProviderID else {
            return false
        }
        return isASRProviderConfigured(asr) &&
            isOptimizationProviderConfigured(optimization) &&
            !actionsDisabled
    }

    func cancelLoading() {
        loadGeneration &+= 1
    }

    func load() async {
        guard !Task.isCancelled else { return }
        loadGeneration &+= 1
        let generation = loadGeneration
        loadState = .loading
        alert = nil
        testFailureCategories = [:]
        testFailureStages = [:]
        testProviderFailures = [:]
        do {
            for attempt in 1...Self.maximumMigrationLoadAttempts {
                let loaded = try await configurations.load()
                try Task.checkCancellation()
                guard generation == loadGeneration else { return }
                var loadedSecrets: [CustomAISecretReference: String] = [:]
                for reference in Self.allSecretReferences {
                    if let value = try await secrets.load(reference) {
                        loadedSecrets[reference] = value
                    }
                    try Task.checkCancellation()
                    guard generation == loadGeneration else { return }
                }
                let migrated = loaded.migrated(
                    secretReferencesWithValues: Set(loadedSecrets.keys)
                )
                guard migrated.isCatalogValid else {
                    throw CustomAIRuntimeConfigurationError
                        .invalidConfiguration
                }
                if migrated != loaded {
                    let saved = try await configurations.saveMigrated(
                        migrated,
                        ifUnchangedFrom: loaded
                    )
                    try Task.checkCancellation()
                    guard generation == loadGeneration else { return }
                    guard saved else {
                        guard attempt < Self.maximumMigrationLoadAttempts else {
                            throw LoadError.migrationConflictLimitExceeded
                        }
                        await Task.yield()
                        try Task.checkCancellation()
                        guard generation == loadGeneration else { return }
                        continue
                    }
                }
                try Task.checkCancellation()
                guard generation == loadGeneration else { return }
                configuration = migrated
                baselineConfiguration = migrated
                secretDrafts = loadedSecrets
                baselineSecrets = loadedSecrets
                dirtySecretReferences = []
                editingSnapshot = nil
                editingCategory = nil
                editingASRProviderID = nil
                editingOptimizationProviderID = nil
                testStatus = [.asr: .idle, .optimization: .idle, .all: .idle]
                testFailureCategories = [:]
                testFailureStages = [:]
                testProviderFailures = [:]
                loadState = .ready
                return
            }
            throw LoadError.migrationConflictLimitExceeded
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else {
                return
            }
            configuration = .default
            baselineConfiguration = .default
            secretDrafts = [:]
            baselineSecrets = [:]
            dirtySecretReferences = []
            editingSnapshot = nil
            editingCategory = nil
            editingASRProviderID = nil
            editingOptimizationProviderID = nil
            loadState = .failed
            alert = .loadFailed
        }
    }

    func setEnabled(_ enabled: Bool) {
        configuration.isEnabled = enabled
        invalidateTests()
    }

    func selectASRProvider(_ providerID: CustomAIASRProviderID) {
        guard let provider = CustomAIProviderCatalog.asrProvider(providerID),
              let model = provider.models.first else {
            return
        }
        configuration.asr = configuration.asrSelection(for: providerID) ??
            .init(
                providerID: providerID,
                modelID: model.id,
                nonsecretValues: Self.defaultNonsecretValues(provider.fields)
            )
        invalidateTests()
    }

    func selectOptimizationProvider(
        _ providerID: CustomAIOptimizationProviderID
    ) {
        guard let provider = CustomAIProviderCatalog.optimizationProvider(
            providerID
        ), let model = provider.models.first else {
            return
        }
        configuration.optimization = configuration.optimizationSelection(
            for: providerID
        ) ?? .init(
            providerID: providerID,
            modelID: model.id,
            nonsecretValues: Self.defaultNonsecretValues(provider.fields)
        )
        invalidateTests()
    }

    func beginEditingASRProvider(_ providerID: CustomAIASRProviderID) {
        guard CustomAIProviderCatalog.asrProvider(providerID) != nil else {
            return
        }
        invalidateTest(.asr)
        beginEditing(.asr)
        editingASRProviderID = providerID
        if configuration.asrSelection(for: providerID) == nil,
           let provider = CustomAIProviderCatalog.asrProvider(providerID),
           let model = provider.models.first {
            configuration.storeASRSelection(
                .init(
                    providerID: providerID,
                    modelID: model.id,
                    nonsecretValues: Self.defaultNonsecretValues(
                        provider.fields
                    )
                ),
                select: false
            )
        }
    }

    func beginEditingOptimizationProvider(
        _ providerID: CustomAIOptimizationProviderID
    ) {
        guard CustomAIProviderCatalog.optimizationProvider(providerID) != nil else {
            return
        }
        invalidateTest(.optimization)
        beginEditing(.optimization)
        editingOptimizationProviderID = providerID
        if configuration.optimizationSelection(for: providerID) == nil,
           let provider = CustomAIProviderCatalog.optimizationProvider(
               providerID
           ), let model = provider.models.first {
            configuration.storeOptimizationSelection(
                .init(
                    providerID: providerID,
                    modelID: model.id,
                    nonsecretValues: Self.defaultNonsecretValues(
                        provider.fields
                    )
                ),
                select: false
            )
        }
    }

    func cancelEditing() {
        guard let snapshot = editingSnapshot else {
            finishEditing()
            return
        }
        configuration = snapshot.configuration
        secretDrafts = snapshot.secrets
        dirtySecretReferences = snapshot.dirtySecretReferences
        finishEditing()
        invalidateTests()
    }

    func commitEditing() {
        finishEditing()
    }

    func commitEditingAndEnable() {
        switch editingCategory {
        case .asr:
            if let providerID = editingASRProviderID {
                configuration.selectASRProvider(providerID)
            }
        case .optimization:
            if let providerID = editingOptimizationProviderID {
                configuration.selectOptimizationProvider(providerID)
            }
        case nil:
            break
        }
        finishEditing()
        invalidateTests()
    }

    func selectModel(_ modelID: String, category: CustomAIServiceCategory) {
        switch category {
        case .asr:
            let providerID = activeASRProviderID
            guard let providerID,
                  CustomAIProviderCatalog.asrProvider(providerID)?
                    .models.contains(where: { $0.id == modelID }) == true,
                  var selection = configuration.asrSelection(
                      for: providerID
                  ) else {
                return
            }
            selection.modelID = modelID
            configuration.storeASRSelection(selection, select: false)
        case .optimization:
            let providerID = activeOptimizationProviderID
            guard let providerID,
                  CustomAIProviderCatalog.optimizationProvider(providerID)?
                    .models.contains(where: { $0.id == modelID }) == true,
                  var selection = configuration.optimizationSelection(
                      for: providerID
                  ) else {
                return
            }
            selection.modelID = modelID
            configuration.storeOptimizationSelection(
                selection,
                select: false
            )
        }
        invalidateTests()
    }

    func setField(
        _ fieldID: CustomAIFieldID,
        value: String,
        category: CustomAIServiceCategory
    ) {
        let descriptor = fieldDescriptor(fieldID, category: category)
        guard let descriptor else { return }
        if descriptor.isSecret {
            guard let reference = secretReference(
                fieldID,
                category: category
            ) else { return }
            if value.isEmpty {
                secretDrafts.removeValue(forKey: reference)
            } else {
                secretDrafts[reference] = value
            }
            if baselineSecrets[reference] == secretDrafts[reference] {
                dirtySecretReferences.remove(reference)
            } else {
                dirtySecretReferences.insert(reference)
            }
        } else {
            switch category {
            case .asr:
                guard let providerID = activeASRProviderID,
                      var selection = configuration.asrSelection(
                          for: providerID
                      ) else { return }
                if value.isEmpty {
                    selection.nonsecretValues.removeValue(
                        forKey: fieldID
                    )
                } else {
                    selection.nonsecretValues[fieldID] = value
                }
                configuration.storeASRSelection(selection, select: false)
            case .optimization:
                guard let providerID = activeOptimizationProviderID,
                      var selection = configuration.optimizationSelection(
                          for: providerID
                      ) else { return }
                if value.isEmpty {
                    selection.nonsecretValues.removeValue(
                        forKey: fieldID
                    )
                } else {
                    selection.nonsecretValues[fieldID] = value
                }
                configuration.storeOptimizationSelection(
                    selection,
                    select: false
                )
            }
        }
        invalidateTests()
    }

    func fieldValue(
        _ fieldID: CustomAIFieldID,
        category: CustomAIServiceCategory
    ) -> String {
        guard let field = fieldDescriptor(fieldID, category: category) else {
            return ""
        }
        if field.isSecret {
            guard let reference = secretReference(
                fieldID,
                category: category
            ) else { return "" }
            return secretDrafts[reference] ?? ""
        }
        switch category {
        case .asr:
            guard let providerID = activeASRProviderID else { return "" }
            return configuration.asrSelection(for: providerID)?
                .nonsecretValues[fieldID] ??
                field.defaultValue ?? ""
        case .optimization:
            guard let providerID = activeOptimizationProviderID else {
                return ""
            }
            return configuration.optimizationSelection(for: providerID)?
                .nonsecretValues[fieldID] ??
                field.defaultValue ?? ""
        }
    }

    func isASRProviderConfigured(_ providerID: CustomAIASRProviderID) -> Bool {
        guard let provider = CustomAIProviderCatalog.asrProvider(providerID),
              let selection = configuration.asrSelection(for: providerID) else {
            return false
        }
        return isConfigured(
            category: .asr,
            providerID: providerID.rawValue,
            fields: provider.fields,
            nonsecretValues: selection.nonsecretValues
        )
    }

    func isOptimizationProviderConfigured(
        _ providerID: CustomAIOptimizationProviderID
    ) -> Bool {
        guard let provider = CustomAIProviderCatalog.optimizationProvider(
            providerID
        ), let selection = configuration.optimizationSelection(
            for: providerID
        ) else {
            return false
        }
        return isConfigured(
            category: .optimization,
            providerID: providerID.rawValue,
            fields: provider.fields,
            nonsecretValues: selection.nonsecretValues
        )
    }

    func test(_ scope: CustomAITestScope) async {
        guard !actionsDisabled else { return }
        testStatus[scope] = .running
        testFailureCategories.removeValue(forKey: scope)
        testFailureStages.removeValue(forKey: scope)
        testProviderFailures.removeValue(forKey: scope)
        do {
            let runtime = try buildRuntimeConfiguration(for: scope)
            try await tester.test(scope, configuration: runtime)
            testStatus[scope] = .passed
        } catch {
            testStatus[scope] = .failed
            let failure = CustomAITestFailureClassifier.failure(
                error,
                stage: scope == .optimization ? .optimization : .asr
            )
            testFailureCategories[scope] = failure.category
            testFailureStages[scope] = failure.stage
            testProviderFailures[scope] = failure.providerFailure
            let identity = diagnosticIdentity(for: failure.stage)
            await testDiagnostics.record(
                .init(
                    scope: scope,
                    stage: failure.stage,
                    category: failure.category,
                    providerID: identity.providerID,
                    modelID: identity.modelID,
                    httpStatus: failure.providerFailure?.httpStatus,
                    providerCode: failure.providerFailure?.providerCode,
                    requestID: failure.providerFailure?.requestID,
                    localReason: CustomAITestLocalFailureReason(error)
                )
            )
        }
    }

    @discardableResult
    func save() async -> Bool {
        guard !actionsDisabled else { return false }
        isSaving = true
        defer { isSaving = false }
        if configuration.isEnabled {
            do {
                _ = try buildRuntimeConfiguration(for: .all)
            } catch {
                alert = .invalidConfiguration
                return false
            }
        }
        var applied: [CustomAISecretReference] = []
        do {
            for reference in dirtySecretReferences.sorted(by: {
                $0.account < $1.account
            }) {
                if let value = secretDrafts[reference] {
                    try await secrets.replace(value, for: reference)
                } else {
                    try await secrets.delete(reference)
                }
                applied.append(reference)
            }
            try await configurations.save(configuration)
        } catch {
            for reference in applied.reversed() {
                if let oldValue = baselineSecrets[reference] {
                    try? await secrets.replace(oldValue, for: reference)
                } else {
                    try? await secrets.delete(reference)
                }
            }
            alert = .saveFailed
            return false
        }
        baselineConfiguration = configuration
        baselineSecrets = secretDrafts
        dirtySecretReferences = []
        finishEditing()
        alert = nil
        close()
        return true
    }

    func requestClose() {
        if hasUnsavedChanges {
            alert = .unsavedChanges
        } else {
            close()
        }
    }

    func cancelAlert() {
        alert = nil
    }

    func discardAndClose() async {
        configuration = baselineConfiguration
        secretDrafts = baselineSecrets
        dirtySecretReferences = []
        finishEditing()
        alert = nil
        close()
    }

    private func invalidateTests() {
        testStatus = [.asr: .idle, .optimization: .idle, .all: .idle]
        testFailureCategories = [:]
        testFailureStages = [:]
        testProviderFailures = [:]
        if alert == .invalidConfiguration || alert == .saveFailed {
            alert = nil
        }
    }

    private func invalidateTest(_ scope: CustomAITestScope) {
        testStatus[scope] = .idle
        testFailureCategories.removeValue(forKey: scope)
        testFailureStages.removeValue(forKey: scope)
        testProviderFailures.removeValue(forKey: scope)
    }

    private func beginEditing(_ category: CustomAIServiceCategory) {
        if editingSnapshot == nil {
            editingSnapshot = EditingSnapshot(
                configuration: configuration,
                secrets: secretDrafts,
                dirtySecretReferences: dirtySecretReferences
            )
        }
        editingCategory = category
    }

    private func buildRuntimeConfiguration(
        for scope: CustomAITestScope
    ) throws -> CustomAIRuntimeConfiguration {
        if scope == .all, !configuration.isCatalogValid {
            throw CustomAIRuntimeConfigurationError.invalidConfiguration
        }
        let requiresASR = scope == .asr || scope == .all
        let requiresOptimization = scope == .optimization || scope == .all
        let asrProviderID = scope == .asr
            ? editingASRProviderID ?? configuration.selectedASRProviderID
            : configuration.selectedASRProviderID
        let optimizationProviderID = scope == .optimization
            ? editingOptimizationProviderID ??
                configuration.selectedOptimizationProviderID
            : configuration.selectedOptimizationProviderID
        let asr = try runtimeASRSelection(
            required: requiresASR,
            providerID: asrProviderID
        )
        let optimization = try runtimeOptimizationSelection(
            required: requiresOptimization,
            providerID: optimizationProviderID
        )
        return .init(asr: asr, optimization: optimization)
    }

    private func runtimeASRSelection(
        required: Bool,
        providerID: CustomAIASRProviderID?
    ) throws -> CustomAIRuntimeSelection {
        guard let providerID else {
            if required {
                throw CustomAIRuntimeConfigurationError.invalidConfiguration
            }
            return .init(providerID: "", modelID: "", values: [:])
        }
        guard let provider = CustomAIProviderCatalog.asrProvider(providerID),
              let selection = configuration.asrSelection(for: providerID),
              provider.models.contains(where: {
                  $0.id == selection.modelID
              }) else {
            throw CustomAIRuntimeConfigurationError.invalidConfiguration
        }
        return try runtimeSelection(
            category: .asr,
            providerID: providerID.rawValue,
            modelID: selection.modelID,
            fields: provider.fields,
            nonsecret: selection.nonsecretValues,
            required: required
        )
    }

    private func runtimeOptimizationSelection(
        required: Bool,
        providerID: CustomAIOptimizationProviderID?
    ) throws -> CustomAIRuntimeSelection {
        guard let providerID else {
            if required {
                throw CustomAIRuntimeConfigurationError.invalidConfiguration
            }
            return .init(providerID: "", modelID: "", values: [:])
        }
        guard let provider = CustomAIProviderCatalog.optimizationProvider(
            providerID
        ), let selection = configuration.optimizationSelection(
            for: providerID
        ), provider.models.contains(where: {
            $0.id == selection.modelID
        }) else {
            throw CustomAIRuntimeConfigurationError.invalidConfiguration
        }
        return try runtimeSelection(
            category: .optimization,
            providerID: providerID.rawValue,
            modelID: selection.modelID,
            fields: provider.fields,
            nonsecret: selection.nonsecretValues,
            required: required
        )
    }

    private func runtimeSelection(
        category: CustomAIServiceCategory,
        providerID: String,
        modelID: String,
        fields: [CustomAIFieldDescriptor],
        nonsecret: [CustomAIFieldID: String],
        required: Bool
    ) throws -> CustomAIRuntimeSelection {
        var values: [CustomAIFieldID: String] = [:]
        for field in fields {
            let value: String?
            if field.isSecret {
                value = secretDrafts[
                    .init(
                        category: category,
                        providerID: providerID,
                        fieldID: field.id
                    )
                ]
            } else {
                value = nonsecret[field.id] ?? field.defaultValue
            }
            if let value, Self.isValidFieldValue(value) {
                values[field.id] = value
            } else if required && field.isRequired {
                throw CustomAIRuntimeConfigurationError.missingRequiredField(
                    category: category,
                    providerID: providerID,
                    fieldID: field.id
                )
            }
        }
        return .init(providerID: providerID, modelID: modelID, values: values)
    }

    private func isConfigured(
        category: CustomAIServiceCategory,
        providerID: String,
        fields: [CustomAIFieldDescriptor],
        nonsecretValues: [CustomAIFieldID: String]
    ) -> Bool {
        fields.filter(\.isRequired).allSatisfy { field in
            let value: String?
            if field.isSecret {
                value = secretDrafts[
                    .init(
                        category: category,
                        providerID: providerID,
                        fieldID: field.id
                    )
                ]
            } else {
                value = nonsecretValues[field.id] ?? field.defaultValue
            }
            return value.map(Self.isValidFieldValue) == true
        }
    }

    private func fieldDescriptor(
        _ fieldID: CustomAIFieldID,
        category: CustomAIServiceCategory
    ) -> CustomAIFieldDescriptor? {
        switch category {
        case .asr:
            guard let providerID = activeASRProviderID else { return nil }
            return CustomAIProviderCatalog.asrProvider(providerID)?
                .fields.first { $0.id == fieldID }
        case .optimization:
            guard let providerID = activeOptimizationProviderID else {
                return nil
            }
            return CustomAIProviderCatalog.optimizationProvider(providerID)?
                .fields.first { $0.id == fieldID }
        }
    }

    private func secretReference(
        _ fieldID: CustomAIFieldID,
        category: CustomAIServiceCategory
    ) -> CustomAISecretReference? {
        let providerID: String?
        switch category {
        case .asr:
            providerID = activeASRProviderID?.rawValue
        case .optimization:
            providerID = activeOptimizationProviderID?.rawValue
        }
        guard let providerID else { return nil }
        return .init(
            category: category,
            providerID: providerID,
            fieldID: fieldID
        )
    }

    private static func defaultNonsecretValues(
        _ fields: [CustomAIFieldDescriptor]
    ) -> [CustomAIFieldID: String] {
        Dictionary(uniqueKeysWithValues: fields.compactMap { field in
            guard !field.isSecret, let value = field.defaultValue else {
                return nil
            }
            return (field.id, value)
        })
    }

    private var activeASRProviderID: CustomAIASRProviderID? {
        editingCategory == .asr
            ? editingASRProviderID
            : configuration.selectedASRProviderID
    }

    private var activeOptimizationProviderID:
        CustomAIOptimizationProviderID?
    {
        editingCategory == .optimization
            ? editingOptimizationProviderID
            : configuration.selectedOptimizationProviderID
    }

    private func diagnosticIdentity(
        for stage: CustomAIProviderStage
    ) -> (providerID: String?, modelID: String?) {
        switch stage {
        case .asr:
            let providerID = editingCategory == .asr
                ? editingASRProviderID ??
                    configuration.selectedASRProviderID
                : configuration.selectedASRProviderID
            return (
                providerID?.rawValue,
                providerID.flatMap {
                    configuration.asrSelection(for: $0)?.modelID
                }
            )
        case .optimization:
            let providerID = editingCategory == .optimization
                ? editingOptimizationProviderID ??
                    configuration.selectedOptimizationProviderID
                : configuration.selectedOptimizationProviderID
            return (
                providerID?.rawValue,
                providerID.flatMap {
                    configuration.optimizationSelection(for: $0)?.modelID
                }
            )
        }
    }

    private func finishEditing() {
        editingSnapshot = nil
        editingCategory = nil
        editingASRProviderID = nil
        editingOptimizationProviderID = nil
    }

    private static func isValidFieldValue(_ value: String) -> Bool {
        value == value.trimmingCharacters(in: .whitespacesAndNewlines) &&
            !value.isEmpty &&
            value.utf8.count <= 16_384 &&
            !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
    }

    private static let allSecretReferences: [CustomAISecretReference] = {
        let asr = CustomAIProviderCatalog.asr.flatMap { provider in
            provider.fields.filter(\.isSecret).map {
                CustomAISecretReference(
                    category: .asr,
                    providerID: provider.id.rawValue,
                    fieldID: $0.id
                )
            }
        }
        let optimization = CustomAIProviderCatalog.optimization.flatMap {
            provider in
            provider.fields.filter(\.isSecret).map {
                CustomAISecretReference(
                    category: .optimization,
                    providerID: provider.id.rawValue,
                    fieldID: $0.id
                )
            }
        }
        return asr + optimization
    }()
}

#if DEBUG
private actor CustomAIVisualConfigurationStore:
    CustomAIConfigurationStoring
{
    private var configuration: CustomAIConfiguration

    init(_ configuration: CustomAIConfiguration) {
        self.configuration = configuration
    }

    func load() async throws -> CustomAIConfiguration { configuration }

    func save(_ configuration: CustomAIConfiguration) async throws {
        self.configuration = configuration
    }
}

private actor CustomAIVisualSecretStore: CustomAISecretStoring {
    private var values: [CustomAISecretReference: String]

    init(references: Set<CustomAISecretReference>) {
        values = Dictionary(uniqueKeysWithValues: references.map {
            ($0, "visual-fixture-secret")
        })
    }

    func load(_ reference: CustomAISecretReference) async throws -> String? {
        values[reference]
    }

    func replace(
        _ value: String,
        for reference: CustomAISecretReference
    ) async throws {
        values[reference] = value
    }

    func delete(_ reference: CustomAISecretReference) async throws {
        values.removeValue(forKey: reference)
    }
}

private struct CustomAIVisualTester: CustomAIConfigurationTesting {
    func test(
        _ scope: CustomAITestScope,
        configuration: CustomAIRuntimeConfiguration
    ) async throws {
        _ = scope
        _ = configuration
    }
}

extension CustomAISettingsCoordinator {
    convenience init(
        visualConfiguration: CustomAIConfiguration,
        configuredSecrets: Set<CustomAISecretReference>,
        testStatus: CustomAITestStatus,
        alert: CustomAISettingsAlert?,
        editingCategory: CustomAIServiceCategory?,
        editingASRProviderID: CustomAIASRProviderID?,
        editingOptimizationProviderID: CustomAIOptimizationProviderID?,
        hasUnsavedChanges: Bool
    ) {
        self.init(
            configurations: CustomAIVisualConfigurationStore(
                visualConfiguration
            ),
            secrets: CustomAIVisualSecretStore(
                references: configuredSecrets
            ),
            tester: CustomAIVisualTester()
        )
        configuration = visualConfiguration
        baselineConfiguration = hasUnsavedChanges
            ? .default
            : visualConfiguration
        let visualSecrets = Dictionary(
            uniqueKeysWithValues: configuredSecrets.map {
                ($0, "visual-fixture-secret")
            }
        )
        secretDrafts = visualSecrets
        baselineSecrets = visualSecrets
        dirtySecretReferences = []
        loadState = .ready
        self.testStatus = [
            .asr: .idle,
            .optimization: .idle,
            .all: testStatus,
        ]
        self.alert = alert
        self.editingCategory = editingCategory
        self.editingASRProviderID = editingASRProviderID
        self.editingOptimizationProviderID = editingOptimizationProviderID
    }
}
#endif
