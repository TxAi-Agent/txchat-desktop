import SwiftUI

struct OnboardingStatusSpineView: View {
    let items: [OnboardingSpineItem]

    private let nodeX: CGFloat = 12
    private let nodeY: [CGFloat] = [17, 112, 207, 302]

    var body: some View {
        ZStack(alignment: .topLeading) {
            spinePath
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
                node(for: item.state)
                    .position(x: nodeX, y: nodeY[index])

                Text(item.title)
                    .font(TxChatTheme.caption)
                    .foregroundStyle(TxChatTheme.Palette.secondaryText)
                    .offset(x: 34, y: nodeY[index] - 8)
                    .fixedSize()
            }
        }
        .frame(width: 132, height: 340, alignment: .topLeading)
    }

    private var spinePath: Path {
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

    @ViewBuilder
    private func node(for state: OnboardingSpineState) -> some View {
        ZStack {
            Circle()
                .fill(
                    TxChatTheme.Palette.nodeSurface.opacity(
                        state == .upcoming ? 0.52 : 0.96
                    )
                )
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            Circle()
                .stroke(TxChatTheme.Palette.border, lineWidth: 1)
                .frame(width: 22, height: 22)

            switch state {
            case .complete:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(TxChatTheme.Palette.success)
            case .current:
                Circle()
                    .fill(TxChatTheme.Palette.warmAccent)
                    .frame(width: 7, height: 7)
            case .upcoming:
                Circle()
                    .fill(TxChatTheme.Palette.border.opacity(0.46))
                    .frame(width: 4, height: 4)
            }
        }
    }
}
