import SwiftUI

struct SessionInterruptionView: View {
    let presentation: SessionInterruptionPresentation
    let beginReauthentication: () -> Void
    @Environment(\.txChatLanguage) private var language

    var body: some View {
        ZStack(alignment: .topLeading) {
            TxChatWindowBackdrop()

            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .foregroundStyle(TxChatTheme.Palette.warmAccent)
                Text(language.select("English", "中文"))
            }
            .font(TxChatTheme.caption)
            .foregroundStyle(TxChatTheme.Palette.secondaryText)
            .offset(x: 634, y: 17)

            TxChatBrandMark(size: 56)
                .offset(x: 60, y: 62)

            Text(language.select("未登录", "Not Logged In"))
                .font(TxChatTheme.compactCaption)
                .foregroundStyle(TxChatTheme.Palette.tertiaryText)
                .frame(width: 100, alignment: .trailing)
                .offset(x: 560, y: 81)

            TxChatStatusLabel(
                text: language.select(
                    presentation.title.contains("其他设备")
                        ? "TxChat 已停止"
                        : "TxChat 需要登录",
                    presentation.title.contains("another device")
                        ? "TxChat Stopped"
                        : "TxChat Needs Login"
                ),
                color: TxChatTheme.Palette.error
            )
            .offset(x: 60, y: 139)

            Text(presentation.title)
                .font(TxChatTheme.headline)
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: 638, height: 44, alignment: .leading)
                .offset(x: 60, y: 170)

            Text(presentation.detail)
                .font(TxChatTheme.body)
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .frame(width: 430, height: 23, alignment: .leading)
                .offset(x: 60, y: 223)

            Image(illustrationName)
                .resizable()
                .scaledToFit()
                .frame(width: illustrationSize.width, height: illustrationSize.height)
                .offset(x: 60, y: 255)
                .accessibilityHidden(true)

            Button(presentation.action, action: beginReauthentication)
                .buttonStyle(SessionPrimaryButtonStyle())
                .offset(x: 60, y: 426)
                .accessibilityIdentifier("session.reauthenticate")

            TxChatStatusSettingsMenu(showShortcutEditor: {})
                .offset(x: 510, y: 253)
        }
        .frame(
            width: TxChatTheme.Layout.windowWidth,
            height: TxChatTheme.Layout.windowHeight,
            alignment: .topLeading
        )
        .clipped()
        .accessibilityIdentifier("session.interruption")
    }

    private var isDeviceConflict: Bool {
        presentation.title.contains("其他设备") ||
            presentation.title.localizedCaseInsensitiveContains("another device")
    }

    private var illustrationName: String {
        isDeviceConflict ? "TxChatDeviceConflict" : "TxChatSessionExpired"
    }

    private var illustrationSize: CGSize {
        isDeviceConflict
            ? CGSize(width: 180, height: 148)
            : CGSize(width: 170, height: 155)
    }
}

private struct SessionPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TxChatTheme.label)
            .foregroundStyle(TxChatTheme.Palette.onPrimaryControl)
            .frame(width: 144, height: 47)
            .background(
                TxChatTheme.Palette.primaryControl.opacity(
                    configuration.isPressed ? 0.78 : 1
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
