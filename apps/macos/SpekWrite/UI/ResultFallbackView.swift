import SwiftUI

struct ResultFallbackView: View {
    static let secondaryActionWidth: CGFloat = 80
    static let actionHeight: CGFloat = 42

    static func primaryActionWidth(
        language: TxChatLanguage
    ) -> CGFloat {
        language == .english ? 113 : 96
    }

    let text: String
    let retry: () async -> Void
    let copy: () -> Void
    let close: () -> Void

    @Environment(\.txChatLanguage) private var language
    @State private var copied = false

    init(
        text: String,
        retry: @escaping () async -> Void,
        copy: @escaping () -> Void,
        close: @escaping () -> Void,
        initiallyCopied: Bool = false
    ) {
        self.text = text
        self.retry = retry
        self.copy = copy
        self.close = close
        _copied = State(initialValue: initiallyCopied)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TxChatSurfaceBackdrop(width: 480, height: 300, radius: 18)

            TxChatBrandMark(size: 56)
                .offset(x: 20, y: 20)

            Text(language.select("文字还在，你可以重新写入。", "Your text is still here"))
                .font(TxChatTheme.noto(23, weight: .bold))
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.80)
                .frame(width: 372, height: 32, alignment: .leading)
                .offset(x: 82, y: 32)

            ScrollView {
                Text(text)
                    .font(TxChatTheme.compactBody)
                    .foregroundStyle(TxChatTheme.Palette.secondaryText)
                    .lineSpacing(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
            }
            .frame(width: 428, height: 130)
            .background(TxChatTheme.Palette.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(TxChatTheme.Palette.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 5, y: 3)
            .offset(x: 26, y: 86)

            Button(language.select("关闭", "Close"), action: close)
                .buttonStyle(
                    TxChatSecondaryButtonStyle(
                        fixedWidth: Self.secondaryActionWidth,
                        fixedHeight: Self.actionHeight
                    )
                )
                .offset(x: 270, y: 240)
                .accessibilityIdentifier("fallback.close")

            Button(
                copied
                    ? language.select("已复制并关闭", "Copied & Closed")
                    : language.select("复制并关闭", "Copy & Close")
            ) {
                copy()
                copied = true
                close()
            }
            .buttonStyle(
                TxChatCompactPrimaryButtonStyle(
                    fixedWidth: Self.primaryActionWidth(
                        language: language
                    ),
                    fixedHeight: Self.actionHeight
                )
            )
            .offset(x: 358, y: 240)
            .accessibilityIdentifier("fallback.copy-and-close")
        }
        .frame(width: 480, height: 300)
        .accessibilityIdentifier("fallback.screen")
    }
}
