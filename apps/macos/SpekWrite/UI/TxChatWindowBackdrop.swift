import SwiftUI

struct TxChatWindowBackdrop: View {
    var body: some View {
        TxChatSurfaceBackdrop(
            width: TxChatTheme.Layout.windowWidth,
            height: TxChatTheme.Layout.windowHeight,
            radius: TxChatTheme.Layout.windowRadius
        )
    }
}

struct TxChatSurfaceBackdrop: View {
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat

    var body: some View {
        TxChatTheme.Palette.canvas
        .frame(
            width: width,
            height: height
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: radius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: radius,
                style: .continuous
            )
            .stroke(TxChatTheme.Palette.border, lineWidth: 1)
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
