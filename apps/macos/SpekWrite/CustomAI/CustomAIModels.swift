import Foundation

enum CustomAIServiceCategory: String, Codable, CaseIterable, Sendable {
    case asr
    case optimization
}

enum CustomAIASRProviderID: String, Codable, CaseIterable, Sendable {
    case alibabaBailian = "alibaba-bailian"
    case volcengine
    case tencentCloud = "tencent-cloud"
    case iflytek
    case openAI = "openai"
}

enum CustomAIOptimizationProviderID: String, Codable, CaseIterable, Sendable {
    case alibabaBailian = "alibaba-bailian"
    case volcengine
    case deepSeek = "deepseek"
    case kimi
    case glm
    case openAI = "openai"
}

enum CustomAIFieldID: String, Codable, CaseIterable, Sendable {
    case apiKey = "api-key"
    case appID = "app-id"
    case accessToken = "access-token"
    case resourceID = "resource-id"
    case secretID = "secret-id"
    case secretKey = "secret-key"
    case apiSecret = "api-secret"
    case endpointID = "endpoint-id"
    case endpointURL = "endpoint-url"
}

struct CustomAIModelDescriptor: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let zhName: String
    let enName: String

    func name(language: TxChatLanguage) -> String {
        language.select(zhName, enName)
    }

    func cardName(language: TxChatLanguage) -> String {
        let value: String = switch id {
        case "fun-asr-flash-2026-06-15": "Fun-ASR"
        case "qwen3-asr-flash-2026-02-10": "Qwen3-ASR"
        case "volc.seedasr.sauc.duration": "Streaming 2.0"
        case "16k_zh_large": language.select("普方英", "Mandarin Pro")
        case "16k_multi_lang": language.select("多语种", "Multilingual")
        case "iat-v2": language.select("语音听写", "Dictation")
        case "gpt-4o-transcribe": "GPT-4o"
        case "gpt-4o-mini-transcribe": "GPT-4o mini"
        case "qwen3.7-plus": "Qwen3.7+"
        case "qwen3.7-flash": "Qwen3.7 Flash"
        case "doubao-seed-2-0-lite-260215": "Seed 2.0 Lite"
        case "deepseek-v4-flash": "V4 Flash"
        case "deepseek-v4-pro": "V4 Pro"
        default: name(language: language)
        }
        return value
    }
}

struct CustomAIFieldDescriptor: Equatable, Sendable, Identifiable {
    let id: CustomAIFieldID
    let zhLabel: String
    let enLabel: String
    let isSecret: Bool
    let isRequired: Bool
    let defaultValue: String?

    init(
        id: CustomAIFieldID,
        zhLabel: String,
        enLabel: String,
        isSecret: Bool,
        isRequired: Bool = true,
        defaultValue: String? = nil
    ) {
        self.id = id
        self.zhLabel = zhLabel
        self.enLabel = enLabel
        self.isSecret = isSecret
        self.isRequired = isRequired
        self.defaultValue = defaultValue
    }

    func label(language: TxChatLanguage) -> String {
        language.select(zhLabel, enLabel)
    }
}

struct CustomAIASRProviderDescriptor: Equatable, Sendable, Identifiable {
    let id: CustomAIASRProviderID
    let zhName: String
    let enName: String
    let models: [CustomAIModelDescriptor]
    let fields: [CustomAIFieldDescriptor]

    func name(language: TxChatLanguage) -> String {
        language.select(zhName, enName)
    }
}

struct CustomAIOptimizationProviderDescriptor: Equatable, Sendable,
    Identifiable
{
    let id: CustomAIOptimizationProviderID
    let zhName: String
    let enName: String
    let models: [CustomAIModelDescriptor]
    let fields: [CustomAIFieldDescriptor]

    func name(language: TxChatLanguage) -> String {
        language.select(zhName, enName)
    }
}

enum CustomAIProviderSupportPolicy {
    static let asr: [CustomAIASRProviderID] = [
        .alibabaBailian,
        .volcengine,
    ]
    static let optimization: [CustomAIOptimizationProviderID] = [
        .alibabaBailian,
        .volcengine,
        .deepSeek,
        .kimi,
        .glm,
    ]

    static func supports(_ providerID: CustomAIASRProviderID) -> Bool {
        asr.contains(providerID)
    }

    static func supports(
        _ providerID: CustomAIOptimizationProviderID
    ) -> Bool {
        optimization.contains(providerID)
    }

    static func supportsASR(rawValue: String) -> Bool {
        CustomAIASRProviderID(rawValue: rawValue)
            .map { supports($0) } == true
    }

    static func supportsOptimization(rawValue: String) -> Bool {
        CustomAIOptimizationProviderID(rawValue: rawValue)
            .map { supports($0) } == true
    }
}

enum CustomAIProviderCatalog {
    private static let apiKey = CustomAIFieldDescriptor(
        id: .apiKey,
        zhLabel: "API Key",
        enLabel: "API Key",
        isSecret: true
    )
    private static let volcengineSpeechAPPKey = CustomAIFieldDescriptor(
        id: .apiKey,
        zhLabel: "豆包语音 APP Key",
        enLabel: "Doubao Voice APP Key",
        isSecret: true
    )
    private static let volcengineModelArkAPIKey = CustomAIFieldDescriptor(
        id: .apiKey,
        zhLabel: "火山方舟 API Key",
        enLabel: "ModelArk API Key",
        isSecret: true
    )
    private static let endpointURL = CustomAIFieldDescriptor(
        id: .endpointURL,
        zhLabel: "服务地址",
        enLabel: "Service endpoint URL",
        isSecret: false
    )

    static let asr: [CustomAIASRProviderDescriptor] = [
        .init(
            id: .alibabaBailian,
            zhName: "阿里云百炼",
            enName: "Alibaba Bailian",
            models: [
                .init(
                    id: "fun-asr-flash-2026-06-15",
                    zhName: "Fun-ASR Flash",
                    enName: "Fun-ASR Flash"
                ),
                .init(
                    id: "qwen3-asr-flash-2026-02-10",
                    zhName: "Qwen3-ASR Flash",
                    enName: "Qwen3-ASR Flash"
                ),
            ],
            fields: [apiKey, endpointURL]
        ),
        .init(
            id: .volcengine,
            zhName: "火山引擎",
            enName: "Volcengine",
            models: [
                .init(
                    id: "volc.seedasr.sauc.duration",
                    zhName: "流式语音识别 2.0",
                    enName: "Streaming Speech Recognition 2.0"
                ),
            ],
            fields: [volcengineSpeechAPPKey, endpointURL]
        ),
    ]

    static let optimization: [CustomAIOptimizationProviderDescriptor] = [
        .init(
            id: .alibabaBailian,
            zhName: "阿里云百炼",
            enName: "Alibaba Bailian",
            models: [
                .init(
                    id: "qwen3.7-plus",
                    zhName: "Qwen3.7 Plus",
                    enName: "Qwen3.7 Plus"
                ),
                .init(
                    id: "qwen3.7-flash",
                    zhName: "Qwen3.7 Flash",
                    enName: "Qwen3.7 Flash"
                ),
            ],
            fields: [apiKey, endpointURL]
        ),
        .init(
            id: .volcengine,
            zhName: "火山引擎",
            enName: "Volcengine",
            models: [
                .init(
                    id: "doubao-seed-2-0-lite-260215",
                    zhName: "Doubao Seed 2.0 Lite",
                    enName: "Doubao Seed 2.0 Lite"
                ),
            ],
            fields: [
                volcengineModelArkAPIKey,
                endpointURL,
                .init(
                    id: .endpointID,
                    zhLabel: "Endpoint ID（可选）",
                    enLabel: "Endpoint ID (optional)",
                    isSecret: false,
                    isRequired: false
                ),
            ]
        ),
        .init(
            id: .deepSeek,
            zhName: "DeepSeek",
            enName: "DeepSeek",
            models: [
                .init(
                    id: "deepseek-v4-flash",
                    zhName: "DeepSeek V4 Flash",
                    enName: "DeepSeek V4 Flash"
                ),
                .init(
                    id: "deepseek-v4-pro",
                    zhName: "DeepSeek V4 Pro",
                    enName: "DeepSeek V4 Pro"
                ),
            ],
            fields: [apiKey, endpointURL]
        ),
        .init(
            id: .kimi,
            zhName: "Kimi",
            enName: "Kimi",
            models: [
                .init(id: "kimi-k3", zhName: "Kimi K3", enName: "Kimi K3"),
            ],
            fields: [apiKey, endpointURL]
        ),
        .init(
            id: .glm,
            zhName: "GLM",
            enName: "GLM",
            models: [
                .init(id: "glm-5", zhName: "GLM-5", enName: "GLM-5"),
                .init(
                    id: "glm-5-turbo",
                    zhName: "GLM-5-Turbo",
                    enName: "GLM-5-Turbo"
                ),
            ],
            fields: [apiKey, endpointURL]
        ),
    ]

    static func asrProvider(
        _ id: CustomAIASRProviderID
    ) -> CustomAIASRProviderDescriptor? {
        asr.first { $0.id == id }
    }

    static func optimizationProvider(
        _ id: CustomAIOptimizationProviderID
    ) -> CustomAIOptimizationProviderDescriptor? {
        optimization.first { $0.id == id }
    }
}

private enum CustomAILegacyProviderMetadata {
    static func accepts(_ selection: CustomAIASRSelection) -> Bool {
        let allowedModels: Set<String>
        let allowedNonsecretFields: Set<CustomAIFieldID>
        switch selection.providerID {
        case .tencentCloud:
            allowedModels = ["16k_zh_large", "16k_multi_lang"]
            allowedNonsecretFields = [.appID]
        case .iflytek:
            allowedModels = ["iat-v2"]
            allowedNonsecretFields = [.appID]
        case .openAI:
            allowedModels = [
                "gpt-4o-transcribe",
                "gpt-4o-mini-transcribe",
            ]
            allowedNonsecretFields = []
        case .alibabaBailian, .volcengine:
            return false
        }
        return allowedModels.contains(selection.modelID) &&
            Set(selection.nonsecretValues.keys)
                .isSubset(of: allowedNonsecretFields)
    }

    static func accepts(
        _ selection: CustomAIOptimizationSelection
    ) -> Bool {
        guard selection.providerID == .openAI else { return false }
        return ["gpt-5.6-luna", "gpt-5.6-terra"]
            .contains(selection.modelID) && selection.nonsecretValues.isEmpty
    }
}

struct CustomAIASRSelection: Codable, Equatable, Sendable {
    var providerID: CustomAIASRProviderID
    var modelID: String
    var nonsecretValues: [CustomAIFieldID: String]
}

struct CustomAIOptimizationSelection: Codable, Equatable, Sendable {
    var providerID: CustomAIOptimizationProviderID
    var modelID: String
    var nonsecretValues: [CustomAIFieldID: String]
}

struct CustomAIConfiguration: Codable, Equatable, Sendable {
    static let schemaVersion = 3

    let schemaVersion: Int
    var isEnabled: Bool
    private(set) var selectedASRProviderID: CustomAIASRProviderID?
    private(set) var selectedOptimizationProviderID:
        CustomAIOptimizationProviderID?
    private var asrProfiles: [String: CustomAIASRSelection]
    private var optimizationProfiles: [String: CustomAIOptimizationSelection]

    var asr: CustomAIASRSelection? {
        get {
            selectedASRProviderID.flatMap {
                asrProfiles[$0.rawValue]
            }
        }
        set {
            guard let newValue else {
                selectedASRProviderID = nil
                return
            }
            guard CustomAIProviderSupportPolicy.supports(newValue.providerID)
            else { return }
            selectedASRProviderID = newValue.providerID
            asrProfiles[newValue.providerID.rawValue] = newValue
        }
    }

    var optimization: CustomAIOptimizationSelection? {
        get {
            selectedOptimizationProviderID.flatMap {
                optimizationProfiles[$0.rawValue]
            }
        }
        set {
            guard let newValue else {
                selectedOptimizationProviderID = nil
                return
            }
            guard CustomAIProviderSupportPolicy.supports(newValue.providerID)
            else { return }
            selectedOptimizationProviderID = newValue.providerID
            optimizationProfiles[newValue.providerID.rawValue] = newValue
        }
    }

    init(
        schemaVersion: Int = schemaVersion,
        isEnabled: Bool,
        asr: CustomAIASRSelection,
        optimization: CustomAIOptimizationSelection
    ) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        selectedASRProviderID = asr.providerID
        selectedOptimizationProviderID = optimization.providerID
        asrProfiles = [asr.providerID.rawValue: asr]
        optimizationProfiles = [optimization.providerID.rawValue: optimization]
    }

    private init(
        schemaVersion: Int,
        isEnabled: Bool,
        selectedASRProviderID: CustomAIASRProviderID?,
        selectedOptimizationProviderID: CustomAIOptimizationProviderID?,
        asrProfiles: [String: CustomAIASRSelection],
        optimizationProfiles: [String: CustomAIOptimizationSelection]
    ) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.selectedASRProviderID = selectedASRProviderID
        self.selectedOptimizationProviderID = selectedOptimizationProviderID
        self.asrProfiles = asrProfiles
        self.optimizationProfiles = optimizationProfiles
    }

    private static let fallbackASR = CustomAIASRSelection(
        providerID: .alibabaBailian,
        modelID: "fun-asr-flash-2026-06-15",
        nonsecretValues: [:]
    )
    private static let fallbackOptimization = CustomAIOptimizationSelection(
        providerID: .alibabaBailian,
        modelID: "qwen3.7-plus",
        nonsecretValues: [:]
    )

    static let `default` = CustomAIConfiguration(
        schemaVersion: schemaVersion,
        isEnabled: false,
        selectedASRProviderID: nil,
        selectedOptimizationProviderID: nil,
        asrProfiles: [:],
        optimizationProfiles: [:]
    )

    func asrSelection(
        for providerID: CustomAIASRProviderID
    ) -> CustomAIASRSelection? {
        asrProfiles[providerID.rawValue]
    }

    func optimizationSelection(
        for providerID: CustomAIOptimizationProviderID
    ) -> CustomAIOptimizationSelection? {
        optimizationProfiles[providerID.rawValue]
    }

    mutating func storeASRSelection(
        _ selection: CustomAIASRSelection,
        select: Bool
    ) {
        guard CustomAIProviderSupportPolicy.supports(selection.providerID)
        else { return }
        asrProfiles[selection.providerID.rawValue] = selection
        if select { selectedASRProviderID = selection.providerID }
    }

    mutating func storeOptimizationSelection(
        _ selection: CustomAIOptimizationSelection,
        select: Bool
    ) {
        guard CustomAIProviderSupportPolicy.supports(selection.providerID)
        else { return }
        optimizationProfiles[selection.providerID.rawValue] = selection
        if select { selectedOptimizationProviderID = selection.providerID }
    }

    mutating func selectASRProvider(_ providerID: CustomAIASRProviderID) {
        guard CustomAIProviderSupportPolicy.supports(providerID),
              asrProfiles[providerID.rawValue] != nil else { return }
        selectedASRProviderID = providerID
    }

    mutating func selectOptimizationProvider(
        _ providerID: CustomAIOptimizationProviderID
    ) {
        guard CustomAIProviderSupportPolicy.supports(providerID),
              optimizationProfiles[providerID.rawValue] != nil else { return }
        selectedOptimizationProviderID = providerID
    }

    func migrated(
        secretReferencesWithValues: Set<CustomAISecretReference>
    ) -> CustomAIConfiguration {
        guard schemaVersion == 1 || schemaVersion == 2 else { return self }

        let migratedASRProfiles: [String: CustomAIASRSelection] = Dictionary(
            uniqueKeysWithValues: asrProfiles.compactMap { key, selection in
                guard key == selection.providerID.rawValue,
                      CustomAIProviderSupportPolicy.supports(
                          selection.providerID
                      ) else { return nil }
                return (
                    key,
                    Self.migratingLegacyVolcengineSelection(
                        Self.removingDeprecatedValues(from: selection)
                    )
                )
            }
        )
        let migratedOptimizationProfiles:
            [String: CustomAIOptimizationSelection] = Dictionary(
                uniqueKeysWithValues: optimizationProfiles.compactMap {
                    key, selection in
                    guard key == selection.providerID.rawValue,
                          CustomAIProviderSupportPolicy.supports(
                              selection.providerID
                          ) else { return nil }
                    return (key, selection)
                }
            )
        let migratedASRProviderID: CustomAIASRProviderID? =
            selectedASRProviderID.flatMap { providerID in
                guard migratedASRProfiles[providerID.rawValue] != nil else {
                    return nil
                }
                if schemaVersion == 1,
                   !shouldPreserveASRSelection(
                       secretReferencesWithValues: secretReferencesWithValues
                   ) {
                    return nil
                }
                return providerID
            }
        let migratedOptimizationProviderID:
            CustomAIOptimizationProviderID? =
            selectedOptimizationProviderID.flatMap { providerID in
                guard migratedOptimizationProfiles[providerID.rawValue] != nil
                else { return nil }
                if schemaVersion == 1,
                   !shouldPreserveOptimizationSelection(
                       secretReferencesWithValues: secretReferencesWithValues
                   ) {
                    return nil
                }
                return providerID
            }
        let migratedEnabled = isEnabled && migratedASRProviderID != nil &&
            migratedOptimizationProviderID != nil

        return CustomAIConfiguration(
            schemaVersion: Self.schemaVersion,
            isEnabled: migratedEnabled,
            selectedASRProviderID: migratedASRProviderID,
            selectedOptimizationProviderID: migratedOptimizationProviderID,
            asrProfiles: migratedASRProfiles,
            optimizationProfiles: migratedOptimizationProfiles
        )
    }

    var isCatalogValid: Bool {
        schemaVersion == Self.schemaVersion &&
            isStructurallyValid(
                asrValidator: {
                    Self.isValid(
                        $0,
                        allowingLegacyVolcengineModels: false,
                        allowingLegacyVolcengineFields: false
                    )
                },
                optimizationValidator: Self.isValid
            )
    }

    var isLoadableForMigration: Bool {
        switch schemaVersion {
        case Self.schemaVersion:
            return isCatalogValid
        case 1, 2:
            return isStructurallyValid(
                asrValidator: { selection in
                    CustomAIProviderSupportPolicy.supports(
                        selection.providerID
                    )
                        ? Self.isValid(
                            selection,
                            allowingLegacyVolcengineModels: true,
                            allowingLegacyVolcengineFields: schemaVersion == 1
                        )
                        : CustomAILegacyProviderMetadata.accepts(selection)
                },
                optimizationValidator: { selection in
                    CustomAIProviderSupportPolicy.supports(
                        selection.providerID
                    )
                        ? Self.isValid(selection)
                        : CustomAILegacyProviderMetadata.accepts(selection)
                }
            )
        default:
            return false
        }
    }

    private func isStructurallyValid(
        asrValidator: (CustomAIASRSelection) -> Bool,
        optimizationValidator: (CustomAIOptimizationSelection) -> Bool
    ) -> Bool {
        guard selectedASRProviderID.map({
            asrProfiles[$0.rawValue] != nil
        }) ?? true,
        selectedOptimizationProviderID.map({
            optimizationProfiles[$0.rawValue] != nil
        }) ?? true,
        !isEnabled || (
            selectedASRProviderID != nil &&
                selectedOptimizationProviderID != nil
        ),
        asrProfiles.allSatisfy({ key, selection in
            key == selection.providerID.rawValue && asrValidator(selection)
        }),
        optimizationProfiles.allSatisfy({ key, selection in
            key == selection.providerID.rawValue &&
                optimizationValidator(selection)
        }) else {
            return false
        }
        return true
    }

    private func shouldPreserveASRSelection(
        secretReferencesWithValues: Set<CustomAISecretReference>
    ) -> Bool {
        guard let selectedASRProviderID,
              let selection = asrProfiles[selectedASRProviderID.rawValue]
        else { return false }
        if isEnabled || selectedASRProviderID != .alibabaBailian ||
            selection.modelID != Self.fallbackASR.modelID ||
            !selection.nonsecretValues.isEmpty {
            return true
        }
        guard let provider = CustomAIProviderCatalog.asrProvider(
            selectedASRProviderID
        ) else { return false }
        return provider.fields.filter { $0.isSecret && $0.isRequired }
            .contains { field in
                secretReferencesWithValues.contains(
                    .init(
                        category: .asr,
                        providerID: selectedASRProviderID.rawValue,
                        fieldID: field.id
                    )
                )
            }
    }

    private func shouldPreserveOptimizationSelection(
        secretReferencesWithValues: Set<CustomAISecretReference>
    ) -> Bool {
        guard let selectedOptimizationProviderID,
              let selection = optimizationProfiles[
                  selectedOptimizationProviderID.rawValue
              ]
        else { return false }
        if isEnabled ||
            selectedOptimizationProviderID != .alibabaBailian ||
            selection.modelID != Self.fallbackOptimization.modelID ||
            !selection.nonsecretValues.isEmpty {
            return true
        }
        guard let provider = CustomAIProviderCatalog.optimizationProvider(
            selectedOptimizationProviderID
        ) else { return false }
        return provider.fields.filter { $0.isSecret && $0.isRequired }
            .contains { field in
                secretReferencesWithValues.contains(
                    .init(
                        category: .optimization,
                        providerID: selectedOptimizationProviderID.rawValue,
                        fieldID: field.id
                    )
                )
            }
    }

    private static func isValid(
        _ selection: CustomAIASRSelection,
        allowingLegacyVolcengineModels: Bool,
        allowingLegacyVolcengineFields: Bool
    ) -> Bool {
        guard let provider = CustomAIProviderCatalog.asrProvider(
            selection.providerID
        ) else {
            return false
        }
        let isCurrentModel = provider.models.contains {
            $0.id == selection.modelID
        }
        let isExplicitLegacyVolcengineModel =
            allowingLegacyVolcengineModels &&
            selection.providerID == .volcengine &&
            [
                "volc.bigasr.auc_turbo",
                "volc.seedasr.auc",
            ].contains(selection.modelID)
        guard isCurrentModel || isExplicitLegacyVolcengineModel else {
            return false
        }
        var allowed = Set(provider.fields.filter { !$0.isSecret }.map(\.id))
        if allowingLegacyVolcengineFields &&
            selection.providerID == .volcengine {
            allowed.formUnion([.appID, .resourceID])
        }
        return Set(selection.nonsecretValues.keys).isSubset(of: allowed)
    }

    private static func removingDeprecatedValues(
        from selection: CustomAIASRSelection
    ) -> CustomAIASRSelection {
        guard let provider = CustomAIProviderCatalog.asrProvider(
            selection.providerID
        ) else { return selection }
        let allowed = Set(provider.fields.filter { !$0.isSecret }.map(\.id))
        var result = selection
        result.nonsecretValues = selection.nonsecretValues.filter {
            allowed.contains($0.key)
        }
        return result
    }

    private static func migratingLegacyVolcengineSelection(
        _ selection: CustomAIASRSelection
    ) -> CustomAIASRSelection {
        guard selection.providerID == .volcengine,
              [
                  "volc.bigasr.auc_turbo",
                  "volc.seedasr.auc",
              ].contains(selection.modelID)
        else { return selection }
        var result = selection
        result.modelID = "volc.seedasr.sauc.duration"
        return result
    }

    private static func isValid(
        _ selection: CustomAIOptimizationSelection
    ) -> Bool {
        guard let provider = CustomAIProviderCatalog.optimizationProvider(
            selection.providerID
        ), provider.models.contains(where: { $0.id == selection.modelID }) else {
            return false
        }
        let allowed = Set(provider.fields.filter { !$0.isSecret }.map(\.id))
        return Set(selection.nonsecretValues.keys).isSubset(of: allowed)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case isEnabled
        case selectedASRProviderID
        case selectedOptimizationProviderID
        case asrProfiles
        case optimizationProfiles
        case asr
        case optimization
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        if let profiles = try container.decodeIfPresent(
            [String: CustomAIASRSelection].self,
            forKey: .asrProfiles
        ), let optimizationProfiles = try container.decodeIfPresent(
            [String: CustomAIOptimizationSelection].self,
            forKey: .optimizationProfiles
        ) {
            asrProfiles = profiles
            self.optimizationProfiles = optimizationProfiles
            selectedASRProviderID = try container.decodeIfPresent(
                CustomAIASRProviderID.self,
                forKey: .selectedASRProviderID
            )
            selectedOptimizationProviderID = try container.decodeIfPresent(
                CustomAIOptimizationProviderID.self,
                forKey: .selectedOptimizationProviderID
            )
        } else {
            let legacyASR = try container.decode(
                CustomAIASRSelection.self,
                forKey: .asr
            )
            let legacyOptimization = try container.decode(
                CustomAIOptimizationSelection.self,
                forKey: .optimization
            )
            selectedASRProviderID = legacyASR.providerID
            selectedOptimizationProviderID = legacyOptimization.providerID
            asrProfiles = [legacyASR.providerID.rawValue: legacyASR]
            optimizationProfiles = [
                legacyOptimization.providerID.rawValue: legacyOptimization,
            ]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(
            selectedASRProviderID,
            forKey: .selectedASRProviderID
        )
        try container.encodeIfPresent(
            selectedOptimizationProviderID,
            forKey: .selectedOptimizationProviderID
        )
        try container.encode(asrProfiles, forKey: .asrProfiles)
        try container.encode(
            optimizationProfiles,
            forKey: .optimizationProfiles
        )
    }
}

struct CustomAISecretReference: Hashable, Sendable {
    let category: CustomAIServiceCategory
    let providerID: String
    let fieldID: CustomAIFieldID

    var account: String {
        "\(category.rawValue).\(providerID).\(fieldID.rawValue)"
    }
}

struct CustomAIRuntimeSelection: Equatable, Sendable {
    let providerID: String
    let modelID: String
    let values: [CustomAIFieldID: String]
}

struct CustomAIRuntimeConfiguration: Equatable, Sendable {
    let asr: CustomAIRuntimeSelection
    let optimization: CustomAIRuntimeSelection
}
