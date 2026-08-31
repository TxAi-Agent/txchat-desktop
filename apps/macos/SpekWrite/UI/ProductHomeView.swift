import SwiftUI

struct ProductHomeView: View {
    let presentation: HomePresentation
    let accountLabel: String
    let setMode: (DictationMode) -> Void
    let testVoiceInput: () async -> Void
    let showCustomAISettings: () -> Void
    let showDictionary: () -> Void
    let showShortcutEditor: () -> Void
    let recalibrateMicrophone: () async -> Void
    let repairPermissions: () -> Void
    let logout: () async -> Void
    let toggleLanguage: () -> Void
    let showDocument: (TxChatTextDocumentKind) -> Void

    @Environment(\.txChatLanguage) private var language
    @State private var selectedMode: DictationMode

    init(
        presentation: HomePresentation,
        accountLabel: String,
        setMode: @escaping (DictationMode) -> Void,
        testVoiceInput: @escaping () async -> Void,
        showCustomAISettings: @escaping () -> Void = {},
        showDictionary: @escaping () -> Void = {},
        showShortcutEditor: @escaping () -> Void,
        recalibrateMicrophone: @escaping () async -> Void,
        repairPermissions: @escaping () -> Void,
        logout: @escaping () async -> Void,
        toggleLanguage: @escaping () -> Void,
        showDocument:
            @escaping (TxChatTextDocumentKind) -> Void = { _ in }
    ) {
        self.presentation = presentation
        self.accountLabel = accountLabel
        self.setMode = setMode
        self.testVoiceInput = testVoiceInput
        self.showCustomAISettings = showCustomAISettings
        self.showDictionary = showDictionary
        self.showShortcutEditor = showShortcutEditor
        self.recalibrateMicrophone = recalibrateMicrophone
        self.repairPermissions = repairPermissions
        self.logout = logout
        self.toggleLanguage = toggleLanguage
        self.showDocument = showDocument
        _selectedMode = State(initialValue: presentation.selectedMode)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TxChatWindowBackdrop()

            Button(action: toggleLanguage) {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 14, weight: .regular))
                    Text(language.select("English", "中文"))
                        .font(TxChatTheme.caption)
                }
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .frame(width: 64, height: 20, alignment: .trailing)
            }
                .buttonStyle(.plain)
                .offset(x: 634, y: 17)
                .accessibilityIdentifier("home.language")

            TxChatHeaderBrandLockup()
                .offset(x: 60, y: 62)

            accountMenu
                .offset(x: 569, y: 79)

            TxChatStatusLabel(text: presentation.status, color: statusColor)
                .offset(x: 60, y: 139)

            Text(presentation.headline)
                .font(TxChatTheme.headline)
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 600, alignment: .leading)
                .offset(x: 60, y: 170)
                .accessibilityAddTraits(.isHeader)

            Text(presentation.instruction)
                .font(TxChatTheme.body)
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .lineLimit(2)
                .frame(width: 600, alignment: .leading)
                .offset(x: 60, y: 223)

            if isReady {
                readyContent
            } else {
                setupContent
                setupFooter
                    .offset(x: 60, y: 499)
            }

            TxChatStatusSettingsMenu(
                showCustomAISettings: showCustomAISettings,
                showShortcutEditor: showShortcutEditor,
                showDictionary: showDictionary,
                showAbout: { showDocument(.about) }
            )
                .offset(x: 510, y: 253)
        }
        .frame(
            width: TxChatTheme.Layout.windowWidth,
            height: TxChatTheme.Layout.windowHeight,
            alignment: .topLeading
        )
        .clipped()
        .onChange(of: presentation.selectedMode) { _, value in
            selectedMode = value
        }
        .accessibilityIdentifier("home.screen")
    }

    private var readyContent: some View {
        Group {
            TxChatLargeKeycap(
                label: presentation.shortcutDisplayName,
                fontSize: 28
            )
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: 60, y: 303)

            TxChatModePicker(selection: $selectedMode, onChange: setMode)
                .disabled(!presentation.modeSelectionEnabled)
                .offset(x: 60, y: 437)

            Text(
                language.select(
                    "智能整理可通过大模型将所说内容根据语境将文字内容进行适当调整",
                    "Smart Format uses AI to refine spoken content based on context"
                )
            )
            .font(TxChatTheme.compactCaption)
            .foregroundStyle(TxChatTheme.Palette.tertiaryText)
            .lineLimit(1)
            .offset(x: 60, y: 499)
        }
    }

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            if presentation.items.first?.state != .ready {
                setupRow(
                    title: language.select("麦克风配置", "Microphone Setup"),
                    action: language.select("授权麦克风", "Allow Microphone"),
                    detail: language.select(
                        "麦克风权限用来收听语音",
                        "For voice recognition"
                    )
                )
            }
            if presentation.items.dropFirst().first?.state != .ready ||
                presentation.items.dropFirst(2).first?.state != .ready
            {
                setupRow(
                    title: language.select("辅助功能配置", "Accessibility Setup"),
                    action: language.select("授权辅助功能", "Allow Accessibility"),
                    detail: language.select(
                        "辅助功能权限用来输入文字",
                        "For inserting recognized text"
                    )
                )
            }
        }
        .offset(x: 60, y: 281)
        .accessibilityIdentifier("home.setup-rows")
    }

    private func setupRow(
        title: String,
        action: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Color.orange)
                Text(title)
                    .font(TxChatTheme.compactBody)
                    .foregroundStyle(TxChatTheme.Palette.primaryText)
            }
            HStack(spacing: 18) {
                Button(action) { repairPermissions() }
                    .buttonStyle(TxChatCompactPrimaryButtonStyle())
                Text(detail)
                    .font(TxChatTheme.compactBody)
                    .foregroundStyle(TxChatTheme.Palette.secondaryText)
                    .lineLimit(1)
            }
        }
        .fixedSize()
    }

    private var setupFooter: some View {
        HStack(spacing: 3) {
            Text(language.select("如果已配置可点击", "If already configured, click"))
                .fixedSize()
            Button(language.select("检查配置", "Check Configuration")) {
                repairPermissions()
            }
            .buttonStyle(.plain)
            .foregroundStyle(TxChatTheme.Palette.blueLink)
            Text(
                language.select(
                    "获取最新配置信息。如无法解决可通过菜单中的常见问题查询解决办法。",
                    "for the latest status. If unresolved, check the FAQ in the menu."
                )
            )
            .frame(
                width: language == .english ? 338 : 405,
                alignment: .leading
            )
        }
        .font(TxChatTheme.compactCaption)
        .foregroundStyle(TxChatTheme.Palette.tertiaryText)
        .lineLimit(2)
        .frame(width: 600, height: 36, alignment: .topLeading)
    }

    private var accountMenu: some View {
        Button {
            Task { await logout() }
        } label: {
            HStack(spacing: 8) {
                Text(accountLabel)
                    .font(TxChatTheme.compactCaption)
                    .foregroundStyle(TxChatTheme.Palette.secondaryText)
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(TxChatTheme.Palette.warmAccent)
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityIdentifier("home.logout")
    }

    private var isReady: Bool {
        presentation.items.allSatisfy { $0.state == .ready }
    }

    private var statusColor: Color {
        isReady ? TxChatTheme.Palette.success : TxChatTheme.Palette.error
    }
}
