import AppKit
import SwiftUI

enum DiagnosticReportViewState: Equatable, Sendable {
    case prompt(isAbnormalExit: Bool)
    case sending
    case sent(String)
    case failed(DiagnosticReportFailureReason)
}

struct DiagnosticReportContent: Equatable, Sendable {
    let title: String
    let body: String
    let caption: String
    let captionAccessibilityHint: String?
    let secondaryActionTitle: String?
    let primaryActionTitle: String
    let primaryActionEnabled: Bool
    let titleTone: TitleTone

    enum TitleTone: Equatable, Sendable {
        case primary
        case success
        case danger
    }

    static func make(
        state: DiagnosticReportViewState,
        language: TxChatLanguage
    ) -> Self {
        switch state {
        case .prompt(let isAbnormalExit) where isAbnormalExit:
            return Self(
                title: language.select(
                    "TxChat 上次意外退出",
                    "TxChat quit unexpectedly"
                ),
                body: language.select(
                    "已检测到上次运行发生异常。是否发送问题，帮助我们定位原因？",
                    "TxChat did not exit normally last time. Send an issue report to help us find the cause?"
                ),
                caption: language.select(
                    "不会自动上传；仅在你确认后发送经过脱敏的诊断信息。",
                    "Nothing is uploaded automatically. Redacted diagnostics are sent only after you confirm."
                ),
                captionAccessibilityHint: nil,
                secondaryActionTitle: language.select("暂不发送", "Not Now"),
                primaryActionTitle: language.select("发送问题", "Send Issue"),
                primaryActionEnabled: true,
                titleTone: .primary
            )
        case .prompt:
            return Self(
                title: language.select(
                    "TxChat 遇到问题",
                    "TxChat encountered an issue"
                ),
                body: language.select(
                    "刚才的操作未能完成。是否发送问题，帮助我们分析并改进？",
                    "The last action could not be completed. Send an issue report to help us investigate and improve?"
                ),
                caption: language.select(
                    "仅发送错误、版本、系统和操作阶段信息；不包含语音、识别文字、整理结果、手机号或密钥。",
                    "Sends only error, version, system, and workflow-stage data—never audio, transcripts, organized text, phone numbers, or keys."
                ),
                captionAccessibilityHint: nil,
                secondaryActionTitle: language.select("暂不发送", "Not Now"),
                primaryActionTitle: language.select("发送问题", "Send Issue"),
                primaryActionEnabled: true,
                titleTone: .primary
            )
        case .sending:
            return Self(
                title: language.select("正在发送问题…", "Sending issue…"),
                body: language.select(
                    "正在安全上传经过脱敏的错误日志，请稍候。",
                    "Securely uploading redacted diagnostic data. Please wait."
                ),
                caption: language.select(
                    "发送完成前可以继续等待；不会要求填写问题描述。",
                    "You can keep waiting while it sends; no issue description is required."
                ),
                captionAccessibilityHint: nil,
                secondaryActionTitle: nil,
                primaryActionTitle: language.select("正在发送…", "Sending…"),
                primaryActionEnabled: false,
                titleTone: .primary
            )
        case .sent(let diagnosticNumber):
            return Self(
                title: language.select("问题已发送", "Issue sent"),
                body: language.select(
                    "感谢你的帮助。问题编号 \(diagnosticNumber) 可用于后续定位。",
                    "Thanks for helping. Report ID \(diagnosticNumber) can be used for follow-up."
                ),
                caption: language.select(
                    "本次仅上传经过脱敏的诊断信息。",
                    "Only redacted diagnostic data was uploaded."
                ),
                captionAccessibilityHint: nil,
                secondaryActionTitle: nil,
                primaryActionTitle: language.select("完成", "Done"),
                primaryActionEnabled: true,
                titleTone: .success
            )
        case .failed(let reason):
            return Self(
                title: language.select("发送失败", "Couldn’t send"),
                body: failureBody(reason, language: language),
                caption: language.select(
                    "如果选择暂不发送，本次错误日志将保留到本地诊断轮转期限结束。",
                    "If you choose Not Now, this diagnostic stays on this Mac until its local rotation period ends."
                ),
                captionAccessibilityHint: language.select(
                    "选择暂不发送会删除已确认的诊断报告；仅不含内容的本地错误事件环会保留到轮转期限。",
                    "Not Now deletes the consented diagnostic report; only the content-free local event ring remains until rotation."
                ),
                secondaryActionTitle: language.select("暂不发送", "Not Now"),
                primaryActionTitle: language.select("重试", "Retry"),
                primaryActionEnabled: true,
                titleTone: .danger
            )
        }
    }

    private static func failureBody(
        _ reason: DiagnosticReportFailureReason,
        language: TxChatLanguage
    ) -> String {
        switch reason {
        case .invalidRequest:
            language.select(
                "诊断信息格式未通过校验，请稍后重试或暂不发送。",
                "The diagnostic data could not be validated. Try again later or choose Not Now."
            )
        case .conflict:
            language.select(
                "这份问题报告已存在，无需重复发送。",
                "This issue report already exists and does not need to be sent again."
            )
        case .tooLarge:
            language.select(
                "问题报告超过发送大小限制，暂时无法上传。",
                "The issue report exceeds the upload size limit."
            )
        case .rateLimited(let seconds):
            if let seconds {
                language.select(
                    "发送过于频繁，请等待 \(seconds) 秒后重试。",
                    "Too many reports were sent. Try again in \(seconds) seconds."
                )
            } else {
                language.select(
                    "发送过于频繁，请稍后重试。",
                    "Too many reports were sent. Try again later."
                )
            }
        case .unavailable:
            language.select(
                "暂时无法连接诊断服务，请检查网络连接后重试。",
                "The diagnostic service is unavailable. Check your connection and try again."
            )
        case .protocolViolation:
            language.select(
                "诊断服务返回了无法识别的结果，请稍后重试。",
                "The diagnostic service returned an unrecognized response. Try again later."
            )
        case .localPreparation:
            language.select(
                "诊断信息暂时无法准备，请稍后重试或暂不发送。",
                "The diagnostic data could not be prepared. Try again later or choose Not Now."
            )
        }
    }
}

enum DiagnosticReportPalette {
    struct Theme: Sendable {
        let surface: NSColor
        let primary: NSColor
        let secondary: NSColor
        let border: NSColor
        let inverseSurface: NSColor
        let onInverse: NSColor
        let success: NSColor
        let danger: NSColor

        var hexValues: [String] {
            [
                surface, primary, secondary, border,
                inverseSurface, onInverse, success, danger,
            ].map(Self.hex)
        }

        private static func hex(_ color: NSColor) -> String {
            let rgb = color.usingColorSpace(.sRGB)!
            return String(
                format: "#%02X%02X%02X",
                Int((rgb.redComponent * 255).rounded()),
                Int((rgb.greenComponent * 255).rounded()),
                Int((rgb.blueComponent * 255).rounded())
            )
        }
    }

    static let light = Theme(
        surface: rgb(0xFFFCF8),
        primary: rgb(0x111111),
        secondary: rgb(0x707070),
        border: rgb(0xDED8D0),
        inverseSurface: rgb(0x171615),
        onInverse: rgb(0xFBFAF8),
        success: rgb(0x2F8A4C),
        danger: rgb(0xC94A45)
    )
    static let dark = Theme(
        surface: rgb(0x211F1D),
        primary: rgb(0xFBFAF8),
        secondary: rgb(0xA9A29A),
        border: rgb(0x3A3733),
        inverseSurface: rgb(0xFFFCF8),
        onInverse: rgb(0x111111),
        success: rgb(0x65B979),
        danger: rgb(0xE1736E)
    )

    private static func rgb(_ value: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

@MainActor
final class DiagnosticReportActionGate: ObservableObject {
    @Published private(set) var areActionsEnabled = true

    @discardableResult
    func performDiscard(
        _ operation: @escaping () async -> Bool
    ) async -> Bool {
        guard areActionsEnabled else { return false }
        areActionsEnabled = false
        let completed = await operation()
        if !completed {
            areActionsEnabled = true
        }
        return completed
    }
}

struct DiagnosticReportView: View {
    let state: DiagnosticReportViewState
    let notNow: () async -> Bool
    let send: () -> Void
    let retry: () -> Void
    let done: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.txChatLanguage) private var language
    @StateObject private var actionGate = DiagnosticReportActionGate()

    var body: some View {
        let content = DiagnosticReportContent.make(
            state: state,
            language: language
        )
        let palette = colorScheme == .dark
            ? DiagnosticReportPalette.dark
            : DiagnosticReportPalette.light

        VStack(alignment: .leading, spacing: 0) {
            titleText(content.title)
                .foregroundStyle(titleColor(content.titleTone, palette: palette))
                .lineLimit(1)
                .frame(height: 32, alignment: .topLeading)
                .accessibilityIdentifier("diagnostics.title")

            Spacer().frame(height: 22)

            Text(content.body)
                .font(TxChatTheme.noto(14))
                .foregroundStyle(Color(palette.secondary))
                .lineSpacing(4)
                .frame(width: 424, height: 52, alignment: .topLeading)
                .textSelection(.enabled)
                .accessibilityIdentifier("diagnostics.body")

            Spacer().frame(height: 8)

            Text(content.caption)
                .font(TxChatTheme.noto(12))
                .foregroundStyle(Color(palette.secondary))
                .lineSpacing(3)
                .frame(width: 424, height: 40, alignment: .topLeading)
                .accessibilityIdentifier("diagnostics.caption")
                .accessibilityHint(content.captionAccessibilityHint ?? "")

            Spacer().frame(height: 28)

            HStack(spacing: 12) {
                Spacer(minLength: 0)
                if let secondary = content.secondaryActionTitle {
                    actionButton(
                        secondary,
                        kind: .secondary,
                        enabled: actionGate.areActionsEnabled,
                        palette: palette,
                        action: secondaryAction
                    )
                }
                actionButton(
                    content.primaryActionTitle,
                    kind: .primary,
                    enabled: content.primaryActionEnabled &&
                        actionGate.areActionsEnabled,
                    width: state == .sending ? 132 : 116,
                    palette: palette,
                    action: primaryAction
                )
            }
            .frame(height: 44)
        }
        .padding(.top, 27)
        .padding(.leading, 27)
        .padding(.trailing, 29)
        .padding(.bottom, 27)
        .frame(width: 480, height: 280)
        .background(Color(palette.surface))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(palette.border), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diagnostics.\(state.accessibilityName)")
    }

    private var secondaryAction: () -> Void {
        switch state {
        case .prompt, .failed:
            {
                Task { @MainActor in
                    await actionGate.performDiscard(notNow)
                }
            }
        case .sending, .sent: {}
        }
    }

    private var primaryAction: () -> Void {
        switch state {
        case .prompt: send
        case .sending: {}
        case .sent: done
        case .failed: retry
        }
    }

    private func titleColor(
        _ tone: DiagnosticReportContent.TitleTone,
        palette: DiagnosticReportPalette.Theme
    ) -> Color {
        switch tone {
        case .primary: Color(palette.primary)
        case .success: Color(palette.success)
        case .danger: Color(palette.danger)
        }
    }

    private func titleText(_ title: String) -> Text {
        let approvedFont = TxChatTheme.noto(23, weight: .bold)
        guard language == .english,
              state.isFailure,
              let apostrophe = title.firstIndex(of: "’") else {
            return Text(title).font(approvedFont)
        }
        let afterApostrophe = title.index(after: apostrophe)
        return Text(String(title[..<apostrophe])).font(approvedFont)
            + Text(String(title[apostrophe])).font(
                .system(size: 23, weight: .bold)
            )
            + Text(String(title[afterApostrophe...])).font(approvedFont)
    }

    private enum ActionKind { case primary, secondary }

    private func actionButton(
        _ title: String,
        kind: ActionKind,
        enabled: Bool,
        width: CGFloat = 116,
        palette: DiagnosticReportPalette.Theme,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(TxChatTheme.noto(14, weight: .medium))
                .foregroundStyle(
                    Color(kind == .primary ? palette.onInverse : palette.primary)
                )
                .frame(width: width, height: 44)
                .background(
                    Color(kind == .primary ? palette.inverseSurface : palette.surface)
                )
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    if kind == .secondary {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color(palette.border), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityIdentifier(
            kind == .primary
                ? "diagnostics.primary-action"
                : "diagnostics.secondary-action"
        )
    }
}

private extension DiagnosticReportViewState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    var accessibilityName: String {
        switch self {
        case .prompt(let abnormal): abnormal ? "abnormal-exit" : "prompt"
        case .sending: "sending"
        case .sent: "sent"
        case .failed: "failed"
        }
    }
}
