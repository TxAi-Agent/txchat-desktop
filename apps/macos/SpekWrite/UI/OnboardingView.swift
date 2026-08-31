import SwiftUI

struct OnboardingView: View {
    private enum CardLayout {
        static let keycapX: CGFloat = 17
        static let keycapY: CGFloat = 20
        static let titleX: CGFloat = 85
        static let titleY: CGFloat = 18
        static let detailY: CGFloat = 52
        static let copyWidth: CGFloat = 208
        static let actionX: CGFloat = 293
        static let actionY: CGFloat = 26
    }

    let presentation: OnboardingPresentation
    let message: String?
    let accountLabel: String
    let voiceTestState: DictationState
    let voiceTestResultText: String?
    let performAction: (OnboardingActionKind) async -> Void
    let testVoiceInput: () async -> Void
    let skipVoiceTest: () async -> Void
    let completeVoiceTest: () async -> Void
    let logout: () async -> Void
    let toggleLanguage: () -> Void

    @Environment(\.txChatLanguage) private var language

    var body: some View {
        ZStack(alignment: .topLeading) {
            TxChatWindowBackdrop()

            TxChatHeaderBrandLockup()
                .offset(x: 60, y: 62)

            languageLabel
                .offset(x: 634, y: 17)

            accountBadge
                .offset(x: 501, y: 80)

            OnboardingStatusSpineView(items: presentation.spine)
                .offset(x: 74, y: 153)

            Circle()
                .fill(TxChatTheme.Palette.warmAccent)
                .frame(width: 8, height: 8)
                .offset(x: 197, y: 158)

            Text(presentation.status)
                .font(TxChatTheme.status)
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .frame(height: 20)
                .offset(x: 229, y: 153)

            Text(presentation.title)
                .font(TxChatTheme.headline)
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .frame(width: 442, height: 44, alignment: .leading)
                .offset(x: 229, y: 189)

            Text(presentation.detail)
                .font(TxChatTheme.body)
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .lineSpacing(0)
                .lineLimit(language == .simplifiedChinese ? 1 : 2)
                .frame(
                    width: detailWidth,
                    height: 46,
                    alignment: .topLeading
                )
                .offset(x: 229, y: 249)

            stepCard
                .offset(x: 229, y: 315)

            Text(presentation.footnote)
                .font(TxChatTheme.compactCaption)
                .foregroundStyle(TxChatTheme.Palette.tertiaryText)
                .frame(width: 430, height: 18, alignment: .leading)
                .offset(x: 229, y: 447)

            if let message {
                Text(localizedMessage(message))
                    .font(TxChatTheme.compactCaption)
                    .foregroundStyle(TxChatTheme.Palette.warning)
                    .frame(width: 430, alignment: .leading)
                    .offset(x: 229, y: 477)
                    .accessibilityIdentifier("onboarding.message")
            }
        }
        .frame(
            width: TxChatTheme.Layout.windowWidth,
            height: TxChatTheme.Layout.windowHeight,
            alignment: .topLeading
        )
        .clipped()
        .accessibilityIdentifier(screenIdentifier)
    }

    private var accountBadge: some View {
        Button {
            Task { await logout() }
        } label: {
            HStack(spacing: 8) {
                Text(accountLabel)
                    .font(TxChatTheme.caption)
                    .foregroundStyle(TxChatTheme.Palette.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(TxChatTheme.Palette.secondaryText)
                    .frame(width: 14, height: 14)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 180, height: 18, alignment: .trailing)
        .accessibilityIdentifier("onboarding.logout")
    }

    private var languageLabel: some View {
        Button(action: toggleLanguage) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .regular))
                Text(language == .simplifiedChinese ? "English" : "中文")
                    .font(TxChatTheme.caption)
            }
            .foregroundStyle(TxChatTheme.Palette.secondaryText)
            .frame(width: 64, height: 20, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.language")
    }

    @ViewBuilder
    private var stepCard: some View {
        switch presentation.step {
        case .microphone, .accessibility:
            permissionCard
        case .voiceTest:
            voiceTestCard
        case .getStarted:
            getStartedCard
        default:
            permissionCard
        }
    }

    private var permissionCard: some View {
        TxChatPermissionCard(
            title: presentation.cardTitle,
            detail: presentation.cardDetail,
            granted: false,
            actionTitle: presentation.primaryAction
        ) {
            Task { await performAction(presentation.actionKind) }
        }
        .frame(width: 430, height: 94)
        .accessibilityIdentifier(screenIdentifier)
    }

    private var voiceTestCard: some View {
        actionCard(
            identifier: "onboarding.voice-test-action",
            actionTitle: voiceTestPrimaryAction,
            action: {
                Task {
                    if voiceTestState == .completed {
                        await completeVoiceTest()
                    } else {
                        await skipVoiceTest()
                    }
                }
            }
        )
        .accessibilityIdentifier("onboarding.voice-test-result")
        .accessibilityValue(voiceTestStatusText)
    }

    private var getStartedCard: some View {
        actionCard(
            identifier: "onboarding.get-started",
            actionTitle: presentation.primaryAction,
            action: {
                Task { await performAction(presentation.actionKind) }
            }
        )
    }

    private func actionCard(
        identifier: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TxChatTheme.Palette.raised.opacity(0.86))

            TxChatLargeKeycap(
                label: "Fn",
                scale: 0.65,
                fontSize: 28
            )
            .offset(x: CardLayout.keycapX, y: CardLayout.keycapY)

            Text(presentation.cardTitle)
                .font(TxChatTheme.bodyEmphasis)
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .lineLimit(1)
                .frame(
                    width: CardLayout.copyWidth,
                    height: 24,
                    alignment: .leading
                )
                .offset(x: CardLayout.titleX, y: CardLayout.titleY)

            Text(presentation.cardDetail)
                .font(TxChatTheme.caption)
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .lineLimit(1)
                .frame(
                    width: CardLayout.copyWidth,
                    height: 18,
                    alignment: .leading
                )
                .offset(x: CardLayout.titleX, y: CardLayout.detailY)

            Button(actionTitle, action: action)
                .buttonStyle(
                    TxChatCompactPrimaryButtonStyle(fixedWidth: 116)
                )
                .offset(x: CardLayout.actionX, y: CardLayout.actionY)
                .accessibilityIdentifier(identifier)
        }
        .frame(width: 430, height: 94)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TxChatTheme.Palette.permissionBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.11), radius: 8, y: 7)
    }

    private var detailWidth: CGFloat {
        if presentation.step == .microphone {
            return language == .simplifiedChinese ? 442 : 430
        }
        return 410
    }

    private var voiceTestPrimaryAction: String {
        voiceTestState == .completed
            ? language.select("下一步", "Next")
            : presentation.primaryAction
    }

    private var screenIdentifier: String {
        switch presentation.step {
        case .microphone: "onboarding.microphone"
        case .accessibility: "onboarding.accessibility"
        case .voiceTest: "onboarding.voice-test"
        case .getStarted: "onboarding.get-started"
        default: "onboarding.microphone"
        }
    }

    private var voiceTestStatusText: String {
        switch voiceTestState {
        case .idle:
            presentation.cardDetail
        case .starting:
            language.select("正在准备语音测试…", "Preparing voice test…")
        case .listening(let snapshot):
            snapshot.partialText.isEmpty
                ? language.select("正在聆听…", "Listening…")
                : snapshot.partialText
        case .finalizing:
            language.select("正在完成最后一段…", "Finishing the last segment…")
        case .organizing:
            language.select("正在整理表达…", "Refining your words…")
        case .inserting(let text), .resultFallback(let text):
            text
        case .completed:
            voiceTestResultText ?? language.select("测试成功", "Test succeeded")
        case .failed:
            language.select("可以重新测试", "You can try again")
        case .unavailable:
            language.select("语音服务暂不可用", "Voice service is unavailable")
        }
    }

    private func localizedMessage(_ message: String) -> String {
        guard language == .english else { return message }
        if message.contains("语音测试") || message.contains("保存") {
            return "Unable to save the voice test setting. Please try again."
        }
        return message
    }
}
