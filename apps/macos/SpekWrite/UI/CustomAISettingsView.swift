import AppKit
import SwiftUI

enum CustomAISettingsLayout {
    static let windowSize = CGSize(width: 720, height: 560)
    static let unsavedDialogSize = CGSize(width: 480, height: 240)
}

enum CustomAISettingsPresentation {
    static func selectedProviderNames(
        asr: String?,
        optimization: String?
    ) -> String {
        [asr, optimization]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

struct CustomAISettingsCopy: Equatable, Sendable {
    private let language: TxChatLanguage
    let title: String
    let description: String
    let asrTitle: String
    let optimizationTitle: String
    let clickToConfigure: String
    let configured: String
    let test: String
    let testing: String
    let cancel: String
    let save: String
    let saveAndEnable: String
    let cloudStatus: String
    let selectedPrefix: String
    let unsavedTitle: String
    let unsavedBody: String
    let continueEditing: String
    let discard: String
    let invalidTitle: String
    let invalidBody: String
    let loadFailedTitle: String
    let loadFailedBody: String
    let saveFailedTitle: String
    let saveFailedBody: String
    let testConfiguration: String
    let model: String

    static func make(_ language: TxChatLanguage) -> Self {
        Self(
            language: language,
            title: language.select("AI 识别模型", "Recognition Model"),
            description: language.select(
                "开启后将使用自定义模型服务",
                "Turn on to use custom model services"
            ),
            asrTitle: language.select(
                "语音识别服务", "Speech Recognition"
            ),
            optimizationTitle: language.select(
                "内容优化服务", "Content Optimization"
            ),
            clickToConfigure: language.select(
                "点击配置", "Configure"
            ),
            configured: language.select("已配置", "Configured"),
            test: language.select("测试", "Test"),
            testing: language.select("正在测试…", "Testing…"),
            cancel: language.select("取消", "Cancel"),
            save: language.select("保存", "Save"),
            saveAndEnable: language.select("保存并启用", "Save and Enable"),
            cloudStatus: language.select(
                "当前使用 TxChat 云服务", "Using TxChat Cloud Service"
            ),
            selectedPrefix: language.select("已选择：", "Selected: "),
            unsavedTitle: language.select(
                "有未保存的更改", "You have unsaved changes"
            ),
            unsavedBody: language.select(
                "AI 模型服务配置尚未保存。离开后，本次更改将不会生效。",
                "Your AI model service settings haven’t been saved. " +
                    "These changes won’t take effect if you leave."
            ),
            continueEditing: language.select(
                "继续编辑", "Keep Editing"
            ),
            discard: language.select("不保存", "Don’t Save"),
            invalidTitle: language.select("配置不完整", "Incomplete Settings"),
            invalidBody: language.select(
                "请完成所选语音识别和内容优化服务的必填配置。",
                "Complete all required fields for the selected speech " +
                    "recognition and content optimization services."
            ),
            loadFailedTitle: language.select(
                "无法读取配置", "Couldn’t Load Settings"
            ),
            loadFailedBody: language.select(
                "本地配置无法安全读取，请取消后重试。",
                "The local settings could not be read safely. Cancel and retry."
            ),
            saveFailedTitle: language.select(
                "保存失败", "Couldn’t Save"
            ),
            saveFailedBody: language.select(
                "配置未更改，请检查系统钥匙串后重试。",
                "No settings were changed. Check Keychain and try again."
            ),
            testConfiguration: language.select(
                "测试配置", "Test"
            ),
            model: language.select("模型", "Model")
        )
    }

    func testFailure(_ category: CustomAITestFailureCategory) -> String {
        switch category {
        case .microphone:
            language.select("麦克风不可用", "Microphone unavailable")
        case .audioSample:
            language.select("未检测到有效语音", "No speech detected")
        case .network:
            language.select("网络连接失败", "Network error")
        case .authentication:
            language.select("认证失败", "Authentication failed")
        case .permissionOrModel:
            language.select("权限或模型不可用", "Permission or model unavailable")
        case .rateLimit:
            language.select("请求过于频繁", "Rate limit reached")
        case .invalidRequest:
            language.select("请求配置无效", "Invalid request")
        case .incompatibleResponse:
            language.select("服务响应不兼容", "Incompatible response")
        }
    }
}

struct CustomAISettingsView: View {
    @ObservedObject var coordinator: CustomAISettingsCoordinator
    @Environment(\.txChatLanguage) private var language

    var body: some View {
        let copy = CustomAISettingsCopy.make(language)
        ZStack(alignment: .topLeading) {
            TxChatTheme.Palette.canvas
            header(copy)
            sectionTitle(copy.asrTitle, y: 110)
            asrCards(copy)
            sectionTitle(copy.optimizationTitle, y: 304)
            optimizationCards(copy)
            footer(copy)

            if coordinator.loadState == .loading {
                TxChatTheme.Palette.canvas.opacity(0.82)
                ProgressView()
                    .controlSize(.small)
                    .offset(x: 346, y: 264)
            }
            if let category = coordinator.editingCategory {
                Color.black.opacity(0.28)
                CustomAIConfigurationSheet(
                    coordinator: coordinator,
                    category: category,
                    copy: copy
                )
            }
            if let alert = coordinator.alert {
                Color.black.opacity(0.28)
                settingsAlert(alert, copy: copy)
            }
        }
        .frame(
            width: CustomAISettingsLayout.windowSize.width,
            height: CustomAISettingsLayout.windowSize.height,
            alignment: .topLeading
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("custom-ai.window")
    }

    private func header(_ copy: CustomAISettingsCopy) -> some View {
        Group {
            Text(copy.title)
                .font(TxChatTheme.noto(17, weight: .medium))
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .offset(x: 40, y: 61)
            Text(copy.description)
                .font(TxChatTheme.noto(12))
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .offset(x: language == .english ? 204 : 139, y: 66)
            customToggle
                .offset(x: 628, y: 60)
        }
    }

    private var customToggle: some View {
        Button {
            coordinator.setEnabled(!coordinator.configuration.isEnabled)
        } label: {
            ZStack(alignment: coordinator.configuration.isEnabled ? .trailing : .leading) {
                Capsule()
                    .fill(
                        coordinator.configuration.isEnabled
                            ? TxChatTheme.Palette.inverseSurface
                            : TxChatTheme.Palette.warmAccent.opacity(0.62)
                    )
                Circle()
                    .fill(TxChatTheme.Palette.raised)
                    .frame(width: 22, height: 22)
                    .padding(3)
            }
            .frame(width: 52, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(coordinator.actionsDisabled || coordinator.loadState != .ready)
        .accessibilityIdentifier("custom-ai.enabled")
    }

    private func sectionTitle(_ title: String, y: CGFloat) -> some View {
        Group {
            Text(title)
                .font(TxChatTheme.noto(13, weight: .medium))
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .fixedSize()
                .offset(x: 40, y: y)
            Rectangle()
                .fill(TxChatTheme.Palette.border.opacity(0.42))
                .frame(
                    width: language == .english ? 506 : 548,
                    height: 1
                )
                .offset(
                    x: language == .english ? 174 : 132,
                    y: y + 10
                )
        }
    }

    private func asrCards(_ copy: CustomAISettingsCopy) -> some View {
        ForEach(Array(CustomAIProviderCatalog.asr.enumerated()), id: \.element.id) {
            index, provider in
            providerCard(
                name: provider.name(language: language),
                systemImage: providerSystemImage(provider.id.rawValue),
                modelName: coordinator.configuration
                    .asrSelection(for: provider.id)
                    .flatMap { selection in
                        provider.models.first { $0.id == selection.modelID }
                    }?.cardName(language: language),
                configured: coordinator.isASRProviderConfigured(provider.id),
                selected: coordinator.configuration.selectedASRProviderID ==
                    provider.id,
                enabled: coordinator.configuration.isEnabled,
                copy: copy,
                action: {
                    coordinator.beginEditingASRProvider(provider.id)
                }
            )
            .offset(x: cardX(index), y: cardY(index, firstRow: 146))
        }
    }

    private func optimizationCards(
        _ copy: CustomAISettingsCopy
    ) -> some View {
        ForEach(
            Array(CustomAIProviderCatalog.optimization.enumerated()),
            id: \.element.id
        ) { index, provider in
            providerCard(
                name: provider.name(language: language),
                systemImage: providerSystemImage(provider.id.rawValue),
                modelName: coordinator.configuration
                    .optimizationSelection(for: provider.id)
                    .flatMap { selection in
                        provider.models.first { $0.id == selection.modelID }
                    }?.cardName(language: language),
                configured: coordinator.isOptimizationProviderConfigured(
                    provider.id
                ),
                selected: coordinator.configuration
                    .selectedOptimizationProviderID == provider.id,
                enabled: coordinator.configuration.isEnabled,
                copy: copy,
                action: {
                    coordinator.beginEditingOptimizationProvider(provider.id)
                }
            )
            .offset(x: cardX(index), y: cardY(index, firstRow: 340))
        }
    }

    private func providerCard(
        name: String,
        systemImage: String,
        modelName: String?,
        configured: Bool,
        selected: Bool,
        enabled: Bool,
        copy: CustomAISettingsCopy,
        action: @escaping () -> Void
    ) -> some View {
        return Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TxChatTheme.Palette.canvas)
                    Image(systemName: systemImage)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(TxChatTheme.Palette.secondaryText)
                        .frame(width: 24, height: 24)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(TxChatTheme.noto(13, weight: .medium))
                        .foregroundStyle(TxChatTheme.Palette.primaryText)
                    Text(
                        configured
                            ? "\(modelName ?? "") · \(copy.configured)"
                            : copy.clickToConfigure
                    )
                    .font(TxChatTheme.noto(11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .foregroundStyle(
                        configured
                            ? TxChatTheme.Palette.success
                            : TxChatTheme.Palette.secondaryText
                    )
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(width: 204, height: 64)
            .contentShape(Rectangle())
            .background(TxChatTheme.Palette.raised)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected && enabled
                            ? TxChatTheme.Palette.warmAccent
                            : TxChatTheme.Palette.border,
                        lineWidth: selected && enabled ? 1.5 : 1
                    )
            }
            .shadow(
                color: selected && enabled ? Color.black.opacity(0.10) : .clear,
                radius: 3,
                y: 2
            )
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || coordinator.actionsDisabled)
    }

    private func footer(_ copy: CustomAISettingsCopy) -> some View {
        Group {
            if let status = footerStatus(copy) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(
                            coordinator.configuration.isEnabled
                                ? TxChatTheme.Palette.warmAccent
                                : TxChatTheme.Palette.secondaryText
                        )
                        .frame(width: 8, height: 8)
                    Text(status)
                        .font(TxChatTheme.noto(12))
                        .foregroundStyle(footerStatusColor)
                        .lineLimit(1)
                }
                .frame(width: 352, height: 42, alignment: .leading)
                .offset(x: 40, y: 498)
            }
            actionButton(
                coordinator.testStatus[.all] == .running
                    ? copy.testing : copy.test,
                primary: false,
                enabled: coordinator.canRunOverallTest,
                action: { Task { await coordinator.test(.all) } }
            )
            .offset(x: 400, y: 498)
            .accessibilityHint(
                language.select(
                    "将录制约 3 秒语音，并依次测试识别和内容优化。",
                    "Records about three seconds, then tests recognition and optimization in order."
                )
            )
            actionButton(
                copy.cancel,
                primary: false,
                enabled: !coordinator.actionsDisabled,
                action: coordinator.requestClose
            )
            .offset(x: 496, y: 498)
            actionButton(
                copy.save,
                primary: true,
                enabled: coordinator.hasUnsavedChanges &&
                    !coordinator.actionsDisabled,
                action: { Task { await coordinator.save() } }
            )
            .offset(x: 592, y: 498)
        }
    }

    private func actionButton(
        _ title: String,
        primary: Bool,
        width: CGFloat = 88,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            apostropheSafeText(
                title,
                size: 14,
                weight: .medium
            )
            .font(TxChatTheme.noto(14, weight: .medium))
            .foregroundStyle(
                primary
                    ? TxChatTheme.Palette.inverseText
                    : TxChatTheme.Palette.primaryText
            )
            .frame(width: width, height: 42)
            .background(
                primary
                    ? TxChatTheme.Palette.inverseSurface
                    : TxChatTheme.Palette.raised
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(TxChatTheme.Palette.border, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.38)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func footerStatus(_ copy: CustomAISettingsCopy) -> String? {
        switch coordinator.testStatus[.all] ?? .idle {
        case .running:
            return copy.testing
        case .passed:
            return language.select("整体测试通过", "All tests passed")
        case .failed:
            return language.select(
                "测试未通过，请检查所选服务配置",
                "Test failed. Check the selected service settings"
            )
        case .idle:
            guard coordinator.configuration.isEnabled else {
                return copy.cloudStatus
            }
            guard coordinator.hasAnySelectedProvider else {
                return nil
            }
            return copy.selectedPrefix + selectedProviderNames
        }
    }

    private var footerStatusColor: Color {
        switch coordinator.testStatus[.all] ?? .idle {
        case .passed: return TxChatTheme.Palette.success
        case .failed: return TxChatTheme.Palette.error
        case .idle, .running:
            return coordinator.configuration.isEnabled
                ? TxChatTheme.Palette.warmAccent
                : TxChatTheme.Palette.secondaryText
        }
    }

    private var selectedProviderNames: String {
        let asr = coordinator.configuration.selectedASRProviderID.flatMap {
            CustomAIProviderCatalog.asrProvider($0)?.name(language: language)
        }
        let optimization = coordinator.configuration
            .selectedOptimizationProviderID.flatMap {
                CustomAIProviderCatalog.optimizationProvider($0)?
                    .name(language: language)
            }
        return CustomAISettingsPresentation.selectedProviderNames(
            asr: asr,
            optimization: optimization
        )
    }

    private func settingsAlert(
        _ alert: CustomAISettingsAlert,
        copy: CustomAISettingsCopy
    ) -> some View {
        let text: (String, String)
        switch alert {
        case .unsavedChanges: text = (copy.unsavedTitle, copy.unsavedBody)
        case .invalidConfiguration: text = (copy.invalidTitle, copy.invalidBody)
        case .loadFailed: text = (copy.loadFailedTitle, copy.loadFailedBody)
        case .saveFailed: text = (copy.saveFailedTitle, copy.saveFailedBody)
        }
        return ZStack(alignment: .topLeading) {
            TxChatTheme.Palette.raised
            apostropheSafeText(text.0, size: 23, weight: .bold)
                .font(TxChatTheme.noto(23, weight: .bold))
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .offset(x: 27, y: 25)
            apostropheSafeText(text.1, size: 14)
                .font(TxChatTheme.noto(14))
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .lineSpacing(4)
                .frame(width: 426, height: 56, alignment: .topLeading)
                .offset(x: 27, y: 79)
            if alert == .unsavedChanges {
                actionButton(
                    copy.continueEditing,
                    primary: false,
                    width: 132,
                    enabled: true,
                    action: coordinator.cancelAlert
                )
                .offset(x: 27, y: 167)
                actionButton(
                    copy.discard,
                    primary: false,
                    width: 132,
                    enabled: true,
                    action: {
                        Task { await coordinator.discardAndClose() }
                    }
                )
                .offset(x: 173, y: 167)
                actionButton(
                    copy.save,
                    primary: true,
                    width: 132,
                    enabled: true,
                    action: { Task { await coordinator.save() } }
                )
                .offset(x: 319, y: 167)
            } else {
                actionButton(
                    copy.continueEditing,
                    primary: true,
                    width: 132,
                    enabled: true,
                    action: coordinator.cancelAlert
                )
                .offset(x: 319, y: 167)
            }
        }
        .frame(
            width: CustomAISettingsLayout.unsavedDialogSize.width,
            height: CustomAISettingsLayout.unsavedDialogSize.height,
            alignment: .topLeading
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TxChatTheme.Palette.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 32, y: 16)
        .offset(x: 120, y: 160)
    }

    private func cardX(_ index: Int) -> CGFloat {
        [40, 258, 476][index % 3]
    }

    private func cardY(_ index: Int, firstRow: CGFloat) -> CGFloat {
        firstRow + CGFloat(index / 3) * 70
    }

    private func providerSystemImage(_ providerID: String) -> String {
        switch providerID {
        case CustomAIASRProviderID.alibabaBailian.rawValue:
            return "waveform"
        case CustomAIASRProviderID.volcengine.rawValue:
            return "waveform"
        case CustomAIASRProviderID.tencentCloud.rawValue:
            return "waveform"
        case CustomAIASRProviderID.iflytek.rawValue:
            return "waveform"
        case CustomAIOptimizationProviderID.deepSeek.rawValue:
            return "waveform"
        case CustomAIOptimizationProviderID.kimi.rawValue:
            return "waveform"
        case CustomAIOptimizationProviderID.glm.rawValue:
            return "waveform"
        default:
            return "waveform"
        }
    }

    private func apostropheSafeText(
        _ value: String,
        size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Text {
        let parts = value.split(
            separator: "’",
            omittingEmptySubsequences: false
        )
        guard let first = parts.first else { return Text("") }
        return parts.dropFirst().reduce(Text(String(first))) { text, part in
            text + Text("’").font(.system(size: size, weight: weight)) +
                Text(String(part))
        }
    }
}

private struct CustomAIConfigurationSheet: View {
    @ObservedObject var coordinator: CustomAISettingsCoordinator
    let category: CustomAIServiceCategory
    let copy: CustomAISettingsCopy
    @Environment(\.txChatLanguage) private var language
    @State private var isModelListPresented = false

    var body: some View {
        let fields = currentFields
        let height = sheetHeight
        ZStack(alignment: .topLeading) {
            TxChatTheme.Palette.raised
            Text(configurationTitle)
                .font(TxChatTheme.noto(23, weight: .bold))
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .offset(x: 28, y: 20)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(fields) { field in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(field.label(language: language))
                            .font(TxChatTheme.noto(13, weight: .medium))
                            .foregroundStyle(TxChatTheme.Palette.primaryText)
                        fieldEditor(field)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.model)
                        .font(TxChatTheme.noto(13, weight: .medium))
                        .foregroundStyle(TxChatTheme.Palette.primaryText)
                    modelPicker
                }
            }
            .offset(x: 28, y: 72)
            .zIndex(isModelListPresented ? 2 : 0)

            let buttonY = CGFloat(height - 66)
            testResult
                .offset(x: 28, y: buttonY + 12)
            if isEditingSelectedProvider {
                sheetButton(
                    testStatus == .running
                        ? copy.testing : copy.testConfiguration,
                    width: 102,
                    primary: false,
                    action: { Task { await coordinator.test(testScope) } }
                )
                .offset(x: 294, y: buttonY)
                sheetButton(
                    copy.cancel,
                    width: 80,
                    primary: false,
                    action: coordinator.cancelEditing
                )
                .offset(x: 408, y: buttonY)
                sheetButton(
                    copy.save,
                    width: 92,
                    primary: true,
                    action: coordinator.commitEditing
                )
                .offset(x: 500, y: buttonY)
            } else {
                sheetButton(
                    testStatus == .running
                        ? copy.testing : copy.testConfiguration,
                    width: 102,
                    primary: false,
                    action: { Task { await coordinator.test(testScope) } }
                )
                .offset(x: 174, y: buttonY)
                sheetButton(
                    copy.cancel,
                    width: 80,
                    primary: false,
                    action: coordinator.cancelEditing
                )
                .offset(x: 288, y: buttonY)
                sheetButton(
                    copy.save,
                    width: 92,
                    primary: false,
                    action: coordinator.commitEditing
                )
                .offset(x: 380, y: buttonY)
                sheetButton(
                    copy.saveAndEnable,
                    width: 102,
                    primary: true,
                    allowsWrapping: language == .english,
                    action: coordinator.commitEditingAndEnable
                )
                .offset(x: 490, y: buttonY)
            }
        }
        .frame(width: 620, height: CGFloat(height), alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TxChatTheme.Palette.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 32, y: 16)
        .offset(x: 50, y: sheetY)
    }

    @ViewBuilder
    private func fieldEditor(_ field: CustomAIFieldDescriptor) -> some View {
        let binding = Binding(
            get: { coordinator.fieldValue(field.id, category: category) },
            set: { coordinator.setField(field.id, value: $0, category: category) }
        )
        let placeholder = language.select(
            "请输入\(field.label(language: language))",
            "Enter \(field.label(language: language))"
        )
        TextField("", text: binding, prompt: Text(placeholder))
            .textFieldStyle(.plain)
            .fieldSurface()
    }

    @ViewBuilder
    private var modelPicker: some View {
        if currentModels.count == 1 {
            staticModelField
        } else {
            selectableModelField
        }
    }

    private var selectableModelField: some View {
        Button {
            isModelListPresented.toggle()
        } label: {
            modelField(showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("custom-ai.model-picker")
        .overlay(alignment: .topLeading) {
            if isModelListPresented {
                modelOptionList
                    .offset(y: 44)
            }
        }
        .zIndex(3)
    }

    private var modelOptionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(currentModels.enumerated()), id: \.element.id) {
                index, model in
                Button {
                    coordinator.selectModel(model.id, category: category)
                    isModelListPresented = false
                } label: {
                    HStack(spacing: 10) {
                        Text(model.name(language: language))
                            .font(TxChatTheme.noto(14))
                            .foregroundStyle(TxChatTheme.Palette.primaryText)
                        Spacer(minLength: 0)
                        if model.id == currentModelID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(
                                    TxChatTheme.Palette.warmAccent
                                )
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 564, height: 40)
                    .contentShape(Rectangle())
                    .background(TxChatTheme.Palette.raised)
                    .overlay(alignment: .bottom) {
                        if index < currentModels.count - 1 {
                            Rectangle()
                                .fill(
                                    TxChatTheme.Palette.border.opacity(0.55)
                                )
                                .frame(height: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(
                    "custom-ai.model-option.\(model.id)"
                )
            }
        }
        .frame(width: 564)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TxChatTheme.Palette.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
    }

    private var staticModelField: some View {
        modelField(showsChevron: false)
    }

    private func modelField(showsChevron: Bool) -> some View {
        HStack(spacing: 8) {
            Text(currentModelName)
                .font(TxChatTheme.noto(14))
                .foregroundStyle(TxChatTheme.Palette.primaryText)
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TxChatTheme.Palette.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 564, height: 40)
        .contentShape(Rectangle())
        .background(TxChatTheme.Palette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TxChatTheme.Palette.border, lineWidth: 1)
        }
    }

    private var testResult: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(testStatusColor)
                .frame(width: 8, height: 8)
            Text(testStatusText)
                .font(TxChatTheme.noto(12))
                .foregroundStyle(testStatusColor)
        }
        .frame(width: 246, height: 20, alignment: .leading)
    }

    private func sheetButton(
        _ title: String,
        width: CGFloat,
        primary: Bool,
        allowsWrapping: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let displayTitle = allowsWrapping
            ? title.replacingOccurrences(of: " and ", with: " and\n")
            : title
        return Button(action: action) {
            Text(displayTitle)
                .lineLimit(allowsWrapping ? 2 : 1)
                .multilineTextAlignment(.center)
                .font(TxChatTheme.noto(14, weight: .medium))
                .foregroundStyle(
                    primary
                        ? TxChatTheme.Palette.inverseText
                        : TxChatTheme.Palette.primaryText
                )
                .frame(width: width, height: 42)
                .background(
                    primary
                        ? TxChatTheme.Palette.inverseSurface
                        : TxChatTheme.Palette.raised
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay {
                    if !primary {
                        RoundedRectangle(
                            cornerRadius: 11,
                            style: .continuous
                        )
                        .stroke(TxChatTheme.Palette.border, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
                .opacity(coordinator.actionsDisabled ? 0.38 : 1)
        }
        .buttonStyle(.plain)
        .disabled(coordinator.actionsDisabled)
    }

    private var currentFields: [CustomAIFieldDescriptor] {
        switch category {
        case .asr:
            guard let providerID = coordinator.editingASRProviderID else {
                return []
            }
            return CustomAIProviderCatalog.asrProvider(providerID)?.fields ?? []
        case .optimization:
            guard let providerID = coordinator.editingOptimizationProviderID
            else { return [] }
            return CustomAIProviderCatalog.optimizationProvider(providerID)?
                .fields ?? []
        }
    }

    private var currentModels: [CustomAIModelDescriptor] {
        switch category {
        case .asr:
            guard let providerID = coordinator.editingASRProviderID else {
                return []
            }
            return CustomAIProviderCatalog.asrProvider(providerID)?.models ?? []
        case .optimization:
            guard let providerID = coordinator.editingOptimizationProviderID
            else { return [] }
            return CustomAIProviderCatalog.optimizationProvider(providerID)?
                .models ?? []
        }
    }

    private var currentModelID: String {
        switch category {
        case .asr:
            guard let providerID = coordinator.editingASRProviderID else {
                return ""
            }
            return coordinator.configuration.asrSelection(for: providerID)?
                .modelID ?? ""
        case .optimization:
            guard let providerID = coordinator.editingOptimizationProviderID
            else { return "" }
            return coordinator.configuration.optimizationSelection(
                for: providerID
            )?.modelID ?? ""
        }
    }

    private var currentModelName: String {
        currentModels.first { $0.id == currentModelID }?
            .name(language: language) ?? ""
    }

    private var configurationTitle: String {
        let name: String
        switch category {
        case .asr:
            guard let providerID = coordinator.editingASRProviderID else {
                return ""
            }
            name = CustomAIProviderCatalog.asrProvider(providerID)?
                .name(language: language) ?? ""
        case .optimization:
            guard let providerID = coordinator.editingOptimizationProviderID
            else { return "" }
            name = CustomAIProviderCatalog.optimizationProvider(providerID)?
                .name(language: language) ?? ""
        }
        return language.select("配置 \(name)", name)
    }

    private var isEditingSelectedProvider: Bool {
        switch category {
        case .asr:
            return coordinator.editingASRProviderID ==
                coordinator.configuration.selectedASRProviderID
        case .optimization:
            return coordinator.editingOptimizationProviderID ==
                coordinator.configuration.selectedOptimizationProviderID
        }
    }

    private var sheetHeight: CGFloat {
        switch currentFields.count {
        case 0...1: return 300
        case 2: return 380
        default: return 460
        }
    }

    private var sheetY: CGFloat {
        switch currentFields.count {
        case 0...1: return 100
        case 2: return 75
        default: return 50
        }
    }

    private var testScope: CustomAITestScope {
        category == .asr ? .asr : .optimization
    }

    private var testStatus: CustomAITestStatus {
        coordinator.testStatus[testScope] ?? .idle
    }

    private var testStatusText: String {
        switch testStatus {
        case .idle: return language.select("尚未测试", "Not tested")
        case .running: return copy.testing
        case .passed: return language.select("测试通过", "Test passed")
        case .failed:
            guard let category = coordinator.testFailureCategories[testScope]
            else { return language.select("测试异常", "Test failed") }
            return copy.testFailure(category)
        }
    }

    private var testStatusColor: Color {
        switch testStatus {
        case .passed: return TxChatTheme.Palette.success
        case .failed: return TxChatTheme.Palette.error
        case .idle, .running: return TxChatTheme.Palette.secondaryText
        }
    }
}

private extension View {
    func fieldSurface() -> some View {
        self
            .font(TxChatTheme.noto(14))
            .foregroundStyle(TxChatTheme.Palette.primaryText)
            .padding(.horizontal, 12)
            .frame(width: 564, height: 40)
            .background(TxChatTheme.Palette.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(TxChatTheme.Palette.border, lineWidth: 1)
            }
    }
}
