import SwiftUI

struct ProductMenuPanelView: View {
    let presentation: ProductMenuPresentation
    let openApp: () -> Void
    let quit: () -> Void

    @Environment(\.txChatLanguage) private var language

    var body: some View {
        ZStack(alignment: .topLeading) {
            TxChatTheme.Palette.canvas

            if presentation.showsBrandMark {
                TxChatBrandMark(size: 56)
                    .offset(x: 20, y: 18)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(presentation.statusTitle)
                        .font(TxChatTheme.noto(14, weight: .medium))
                        .foregroundStyle(TxChatTheme.Palette.primaryText)
                        .lineLimit(1)
                        .frame(height: 22)
                }
                Text(presentation.statusDetail)
                    .font(TxChatTheme.status)
                    .foregroundStyle(TxChatTheme.Palette.secondaryText)
                    .lineLimit(1)
                    .frame(height: 20)
            }
            .frame(width: 230, alignment: .leading)
            .offset(x: 95, y: 26)

            Rectangle()
                .fill(TxChatTheme.Palette.border)
                .frame(width: 316, height: 1)
                .offset(x: 22, y: 91)

            menuRow(
                title: language.select("打开 TxChat", "Open TxChat"),
                hint: nil,
                color: TxChatTheme.Palette.primaryText,
                action: openApp
            )
            .offset(x: 0, y: 96)

            Rectangle()
                .fill(TxChatTheme.Palette.border)
                .frame(width: 316, height: 1)
                .offset(x: 22, y: 152)

            menuRow(
                title: language.select("退出 TxChat", "Quit TxChat"),
                hint: "⌘Q",
                color: Color(red: 0.65, green: 0.20, blue: 0.14),
                action: quit
            )
            .offset(x: 0, y: 157)
        }
        .frame(
            width: TxChatTheme.Layout.menuWidth,
            height: TxChatTheme.Layout.menuHeight,
            alignment: .topLeading
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TxChatTheme.Palette.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 12)
        .accessibilityIdentifier("menu.panel")
    }

    private func menuRow(
        title: String,
        hint: String?,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(TxChatTheme.compactBody)
                    .lineLimit(1)
                Spacer()
                if let hint {
                    Text(hint)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(TxChatTheme.Palette.tertiaryText)
                }
            }
            .padding(.leading, 22)
            .padding(.trailing, 17)
            .frame(width: 360, height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
    }

    private var statusColor: Color {
        switch presentation.statusKind {
        case .success:
            TxChatTheme.Palette.success
        case .attention:
            Color(red: 0.80, green: 0.39, blue: 0.15)
        }
    }
}
