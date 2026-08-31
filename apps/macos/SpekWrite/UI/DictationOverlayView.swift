import SwiftUI

struct DictationOverlayView: View {
    let presentation: OverlayPresentation
    let audioLevel: Double?
    let action: (() -> Void)?
    let cancelAction: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        presentation: OverlayPresentation,
        audioLevel: Double? = nil,
        action: (() -> Void)? = nil,
        cancelAction: (() -> Void)? = nil
    ) {
        self.presentation = presentation
        self.audioLevel = audioLevel
        self.action = action
        self.cancelAction = cancelAction
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("TxChatHUDLogo")
                .resizable()
                .scaledToFit()
                .frame(
                    width: TxChatTheme.Layout.hudLogoSize,
                    height: TxChatTheme.Layout.hudLogoSize
                )
                .offset(x: 10, y: 12)
                .accessibilityHidden(true)

            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .shadow(color: statusColor.opacity(0.5), radius: 2.5)
                .offset(x: statusDotX, y: statusDotY)

            VStack(alignment: .leading, spacing: 5.5) {
                Text(presentation.title)
                    .font(TxChatTheme.hudLabel)
                    .foregroundStyle(
                        Color(
                            red: 251 / 255,
                            green: 250 / 255,
                            blue: 248 / 255
                        )
                    )

                Text(presentation.detail)
                    .font(TxChatTheme.hudCaption)
                    .foregroundStyle(
                        Color(
                            red: 169 / 255,
                            green: 162 / 255,
                            blue: 154 / 255
                        )
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 188, alignment: .leading)
            .offset(x: textStackX, y: 23.5)

            if let cancelAction {
                compactStateIndicator
                cancelButton(action: cancelAction)
                    .offset(x: 317, y: 23)
            } else if action == nil {
                stateIndicator
            } else {
                actionPill
                    .offset(x: 293, y: 28)
            }
        }
        .frame(width: 360, height: 80, alignment: .topLeading)
        .background {
            LinearGradient(
                colors: [
                    Color(
                        red: 37 / 255,
                        green: 36 / 255,
                        blue: 34 / 255
                    ),
                    Color(
                        red: 23 / 255,
                        green: 22 / 255,
                        blue: 21 / 255
                    ),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .circular))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .circular)
                .strokeBorder(
                    Color(
                        red: 62 / 255,
                        green: 58 / 255,
                        blue: 54 / 255
                    )
                )
        }
        .accessibilityElement(
            children: cancelAction == nil ? .combine : .contain
        )
        .accessibilityIdentifier("dictation.overlay")
    }

    private var compactStateIndicator: some View {
        TxChatHUDIndicator(
            state: presentation.visualState,
            audioLevel: audioLevel,
            reduceMotion: reduceMotion,
            compact: true
        )
        .frame(width: 32, height: 32)
        .offset(x: 273, y: 24)
    }

    private func cancelButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        Color(
                            red: 255 / 255,
                            green: 252 / 255,
                            blue: 248 / 255
                        )
                    )
                Circle()
                    .stroke(
                        Color(
                            red: 222 / 255,
                            green: 216 / 255,
                            blue: 208 / 255
                        ),
                        lineWidth: 1
                    )
                Text("×")
                    .font(TxChatTheme.hudLabel)
                    .foregroundStyle(
                        Color(
                            red: 23 / 255,
                            green: 22 / 255,
                            blue: 21 / 255
                        )
                    )
            }
            .frame(width: 24, height: 24)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            presentation.cancellationAccessibilityLabel ?? "Cancel dictation"
        )
        .accessibilityIdentifier("dictation.overlay.cancel")
    }

    @ViewBuilder
    private var stateIndicator: some View {
        let indicator = TxChatHUDIndicator(
            state: presentation.visualState,
            audioLevel: audioLevel,
            reduceMotion: reduceMotion
        )
        switch presentation.visualState {
        case .completed, .cancelled, .failed, .unavailable:
            indicator
                .frame(width: 22, height: 22)
                .offset(x: 317, y: 28)
        case .listening:
            indicator
                .frame(width: 58, height: 32)
                .offset(x: 281, y: 24)
        case .starting, .finalizing, .organizing, .inserting,
             .resultFallback:
            indicator
                .frame(width: 58, height: 32)
                .offset(x: 281, y: 23)
        }
    }

    @ViewBuilder
    private var actionPill: some View {
        if let action {
            Button(action: action) {
                actionPillLabel
            }
            .buttonStyle(.plain)
        } else {
            actionPillLabel
        }
    }

    private var actionPillLabel: some View {
        HStack(spacing: 7) {
            Text(presentation.actionLabel)
                .font(TxChatTheme.hudAction)
                .foregroundStyle(
                    Color(
                        red: 240 / 255,
                        green: 238 / 255,
                        blue: 235 / 255
                    )
                )
                .lineLimit(1)
        }
        .frame(width: 46, height: 28)
        .background(
            Color(
                red: 120 / 255,
                green: 115 / 255,
                blue: 110 / 255
            )
            .opacity(0.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .circular))
    }

    private var statusDotX: CGFloat {
        presentation.visualState == .cancelled ? 76 : baseStatusDotX
    }

    private var statusDotY: CGFloat {
        presentation.visualState == .cancelled ? 27 : baseStatusDotY
    }

    private var textStackX: CGFloat {
        presentation.visualState == .cancelled ? 89 : baseTextStackX
    }

    private var baseStatusDotX: CGFloat { action == nil ? 77 : 76 }
    private var baseStatusDotY: CGFloat { action == nil ? 28 : 27 }
    private var baseTextStackX: CGFloat { action == nil ? 90 : 89 }

    private var statusColor: Color {
        switch presentation.visualState {
        case .completed:
            return Color(
                red: 101 / 255,
                green: 185 / 255,
                blue: 121 / 255
            )
        case .listening, .failed:
            return Color(
                red: 225 / 255,
                green: 115 / 255,
                blue: 110 / 255
            )
        case .starting, .finalizing, .organizing, .cancelled:
            return Color(
                red: 214 / 255,
                green: 148 / 255,
                blue: 80 / 255
            )
        case .inserting, .resultFallback:
            return Color(
                red: 201 / 255,
                green: 149 / 255,
                blue: 121 / 255
            )
        case .unavailable:
            return Color(
                red: 225 / 255,
                green: 115 / 255,
                blue: 110 / 255
            )
        }
    }

    private var actionColor: Color {
        statusColor
    }
}

private struct TxChatHUDIndicator: View {
    let state: OverlayVisualState
    let audioLevel: Double?
    let reduceMotion: Bool
    var compact = false

    var body: some View {
        switch state {
        case .completed:
            statusBadge {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(
                        Color(
                            red: 47 / 255,
                            green: 138 / 255,
                            blue: 76 / 255
                        )
                    )
            }
        case .listening:
            bars(
                heights: displayedHeights(
                    TxChatHUDWaveform.heights(
                        level: audioLevel,
                        reduceMotion: reduceMotion
                    ).map { CGFloat($0) }
                ),
                opacity: 1
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.05),
                value: audioLevel
            )
        case .starting:
            bars(
                heights: displayedHeights([4, 8, 6, 10, 7, 9, 5, 8, 4]),
                opacity: 0.58
            )
        case .finalizing, .organizing:
            bars(
                heights: displayedHeights([6, 10, 8, 14, 10, 12, 8, 10, 6]),
                opacity: 0.68
            )
        case .inserting, .resultFallback:
            bars(
                heights: displayedHeights([4, 7, 5, 9, 6, 8, 5, 7, 4]),
                opacity: 0.55
            )
        case .cancelled:
            EmptyView()
        case .failed, .unavailable:
            statusBadge {
                Circle()
                    .fill(
                        Color(
                            red: 201 / 255,
                            green: 74 / 255,
                            blue: 69 / 255
                        )
                    )
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func bars(
        heights: [CGFloat],
        opacity: Double
    ) -> some View {
        HStack(spacing: compact ? 4 : 5) {
            ForEach(Array(heights.enumerated()), id: \.offset) {
                _, height in
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        Color(
                            red: 216 / 255,
                            green: 177 / 255,
                            blue: 155 / 255
                        )
                    )
                    .opacity(opacity)
                    .frame(width: 2, height: height)
            }
        }
    }

    private func displayedHeights(_ heights: [CGFloat]) -> [CGFloat] {
        guard compact, heights.count >= 9 else {
            return heights
        }
        return [
            heights[0], heights[2], heights[3],
            heights[5], heights[6], heights[8],
        ]
    }

    private func statusBadge<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Circle()
                .fill(
                    Color(
                        red: 255 / 255,
                        green: 252 / 255,
                        blue: 248 / 255
                    )
                )
            Circle()
                .stroke(
                    Color(
                        red: 229 / 255,
                        green: 222 / 255,
                        blue: 214 / 255
                    ),
                    lineWidth: 1
                )
            content()
        }
        .frame(width: 22, height: 22)
        .shadow(
            color: Color(
                red: 111 / 255,
                green: 102 / 255,
                blue: 94 / 255
            ).opacity(0.16),
            radius: 2.5,
            y: 2
        )
    }
}
