import SwiftUI

struct TxChatTextReaderView: View {
    let document: TxChatTextDocument
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(TxChatTheme.Palette.raised)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(TxChatTheme.Palette.border, lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.16), radius: 20, y: 16)

            Text(document.title)
                .font(TxChatTheme.readerTitle)
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .lineLimit(1)
                .frame(width: 520, height: 32, alignment: .leading)
                .offset(x: 27, y: 19)
                .accessibilityAddTraits(.isHeader)

            documentScrollView
                .offset(x: 27, y: 67)

            Button(document.language.select("关闭", "Close"), action: close)
                .buttonStyle(
                    TxChatCompactPrimaryButtonStyle(
                        fixedWidth: 92,
                        fixedHeight: 42
                    )
                )
                .frame(width: 92, height: 42)
                .offset(x: 499, y: 393)
                .accessibilityIdentifier("text-reader.close")
        }
        .frame(width: 620, height: 460, alignment: .topLeading)
        .background(Color.clear)
        .accessibilityIdentifier("text-reader.\(document.kind.rawValue)")
    }

    private var documentScrollView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(
                    Array(document.blocks.enumerated()),
                    id: \.offset
                ) { _, block in
                    blockView(block)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 564, height: 310)
        .background(TxChatTheme.Palette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TxChatTheme.Palette.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func blockView(_ block: TxChatTextBlock) -> some View {
        switch block {
        case .heading(let value):
            Text(value)
                .font(TxChatTheme.readerHeading)
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .lineSpacing(6)
        case .paragraph(let value):
            Text(value)
                .font(TxChatTheme.readerBody)
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .lineSpacing(7)
        }
    }
}
