import SwiftUI

struct StatusSpineView: View {
    let items: [StatusSpineItem]

    private let nodeX: CGFloat = 12
    private let nodeY: [CGFloat] = [17, 112, 207, 302]

    var body: some View {
        ZStack(alignment: .topLeading) {
            path
                .stroke(
                    TxChatTheme.Palette.warmLine.opacity(0.78),
                    style: StrokeStyle(
                        lineWidth: 1.25,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            ForEach(Array(items.enumerated()), id: \.offset) {
                index,
                item in
                statusNode(for: item)
                    .position(x: nodeX, y: nodeY[index])
                Text(item.title)
                    .font(TxChatTheme.caption)
                    .foregroundStyle(TxChatTheme.Palette.secondaryText)
                    .offset(x: 34, y: nodeY[index] - 8)
                    .fixedSize()
                    .accessibilityIdentifier("status-spine.\(index)")
            }
        }
        .frame(width: 132, height: 340, alignment: .topLeading)
    }

    private var path: Path {
        Path { path in
            path.move(to: CGPoint(x: nodeX, y: nodeY[0]))
            path.addCurve(
                to: CGPoint(x: nodeX, y: nodeY[1]),
                control1: CGPoint(x: 33, y: 47),
                control2: CGPoint(x: 3, y: 78)
            )
            path.addCurve(
                to: CGPoint(x: nodeX, y: nodeY[2]),
                control1: CGPoint(x: -3, y: 143),
                control2: CGPoint(x: 30, y: 176)
            )
            path.addCurve(
                to: CGPoint(x: nodeX, y: nodeY[3]),
                control1: CGPoint(x: 29, y: 239),
                control2: CGPoint(x: 0, y: 271)
            )
        }
    }

    private func statusNode(for item: StatusSpineItem) -> some View {
        ZStack {
            Circle()
                .fill(TxChatTheme.Palette.nodeSurface.opacity(0.96))
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            Circle()
                .stroke(TxChatTheme.Palette.border, lineWidth: 1)
                .frame(width: 22, height: 22)
            Image(
                systemName: item.state == .ready
                    ? "checkmark"
                    : "exclamationmark"
            )
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(
                item.state == .ready
                    ? TxChatTheme.Palette.success
                    : TxChatTheme.Palette.warning
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(item.title)，\(item.state == .ready ? "已就绪" : "需要设置")"
        )
    }
}
