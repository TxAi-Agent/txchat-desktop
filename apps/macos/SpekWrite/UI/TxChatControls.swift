import SwiftUI

struct TxChatAvatar: View {
    let label: String
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .fill(TxChatTheme.Palette.warmAccent.opacity(0.2))
            Circle()
                .stroke(TxChatTheme.Palette.controlBorder, lineWidth: 1.5)
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(TxChatTheme.Palette.primaryText)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(label)
    }
}

struct TxChatStatusLabel: View {
    let text: String
    var color: Color = TxChatTheme.Palette.success

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(TxChatTheme.status)
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
        }
        .fixedSize()
    }
}

struct TxChatLargeKeycap: View {
    let label: String
    var scale: CGFloat = 1
    var maximumWidth: CGFloat?
    var lineLimit: Int = 1
    var minimumScaleFactor: CGFloat = 1
    var fontSize: CGFloat = 34

    init(
        label: String,
        scale: CGFloat = 1,
        maximumWidth: CGFloat? = nil,
        lineLimit: Int = 1,
        minimumScaleFactor: CGFloat = 1,
        fontSize: CGFloat = 34
    ) {
        self.label = label
        self.scale = scale
        self.maximumWidth = maximumWidth
        self.lineLimit = lineLimit
        self.minimumScaleFactor = minimumScaleFactor
        self.fontSize = fontSize
    }

    @ViewBuilder
    var body: some View {
        if scale == 1 {
            keySurface
        } else {
            keySurface
                .frame(
                    width: TxChatTheme.Layout.keycapSize,
                    height: TxChatTheme.Layout.largeKeycapHeight
                )
                .scaleEffect(scale)
                .frame(
                    width: TxChatTheme.Layout.keycapSize * scale,
                    height: TxChatTheme.Layout.largeKeycapHeight * scale
                )
        }
    }

    private var keySurface: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 43 / 255, green: 43 / 255, blue: 43 / 255),
                    Color(red: 9 / 255, green: 9 / 255, blue: 9 / 255),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 50 / 255, green: 50 / 255, blue: 50 / 255),
                            Color(red: 27 / 255, green: 27 / 255, blue: 27 / 255),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.40), lineWidth: 1)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 1)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .padding(.horizontal, 8)
                .padding(.top, 7)
                .padding(.bottom, 9)

            Text(label)
                .font(.system(size: fontSize, weight: .regular))
                .foregroundStyle(Color(red: 251 / 255, green: 250 / 255, blue: 248 / 255))
                .lineLimit(lineLimit)
                .minimumScaleFactor(minimumScaleFactor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(
            minWidth: TxChatTheme.Layout.keycapSize,
            maxWidth: maximumWidth
        )
        .frame(height: TxChatTheme.Layout.largeKeycapHeight)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color(red: 5 / 255, green: 5 / 255, blue: 5 / 255), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 9, y: 8)
        .accessibilityLabel("快捷键 \(label)")
    }
}

struct TxChatInlineKeycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(TxChatTheme.Palette.secondaryText)
            .padding(.horizontal, 9)
            .frame(minWidth: 36)
            .frame(height: TxChatTheme.Layout.inlineKeycapHeight)
            .background(TxChatTheme.Palette.raised.opacity(0.78))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 7,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(TxChatTheme.Palette.controlBorder, lineWidth: 1)
            }
            .accessibilityLabel("快捷键 \(label)")
    }
}

struct TxChatModePicker: View {
    @Binding var selection: DictationMode
    let onChange: (DictationMode) -> Void
    @Environment(\.txChatLanguage) private var language

    var body: some View {
        HStack(spacing: 0) {
            option(language.select("智能整理", "Formatted"), mode: .smart)
            option(language.select("逐字记录", "Verbatim"), mode: .verbatim)
        }
        .padding(3)
        .frame(
            width: TxChatTheme.Layout.modeWidth,
            height: TxChatTheme.Layout.modeHeight
        )
        .background(TxChatTheme.Palette.raised)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
            .stroke(TxChatTheme.Palette.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("听写模式")
        .accessibilityIdentifier("home.mode-picker")
    }

    private func option(
        _ title: String,
        mode: DictationMode
    ) -> some View {
        let selected = selection == mode
        return Button {
            selection = mode
            onChange(mode)
        } label: {
            Text(title)
                .font(TxChatTheme.control)
                .foregroundStyle(
                    selected
                        ? TxChatTheme.Palette.onPrimaryControl
                        : TxChatTheme.Palette.secondaryText
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    selected
                        ? TxChatTheme.Palette.primaryControl
                        : Color.clear
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 8,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("home.mode.\(mode.rawValue)")
    }
}

struct TxChatStatusSettingsMenu: View {
    let showCustomAISettings: () -> Void
    let showShortcutEditor: () -> Void
    let showDictionary: () -> Void
    let showAbout: () -> Void
    @Environment(\.txChatLanguage) private var language

    init(
        showCustomAISettings: @escaping () -> Void = {},
        showShortcutEditor: @escaping () -> Void,
        showDictionary: @escaping () -> Void = {},
        showAbout: @escaping () -> Void = {}
    ) {
        self.showCustomAISettings = showCustomAISettings
        self.showShortcutEditor = showShortcutEditor
        self.showDictionary = showDictionary
        self.showAbout = showAbout
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(
                language.select("AI 识别服务", "AI Services"),
                iconAsset: "TxChatStatusSparkles"
            ) {
                showCustomAISettings()
            }
            row(
                language.select("快捷键", "Shortcut"),
                iconAsset: "TxChatStatusKeyboard"
            ) {
                showShortcutEditor()
            }
            row(
                language.select("词典", "Dictionary"),
                iconAsset: "TxChatStatusDictionary"
            ) {
                showDictionary()
            }
            row(
                language.select("关于 TxChat", "About TxChat"),
                iconAsset: "TxChatStatusInfo"
            ) {
                showAbout()
            }
        }
        .frame(width: 150, height: 176, alignment: .topLeading)
    }

    private func row(
        _ title: String,
        iconAsset: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(iconAsset)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(TxChatTheme.Palette.warmAccent)
                    .frame(width: 18, height: 18)
                Spacer(minLength: 4)
                Text(title)
                    .font(TxChatTheme.compactBody)
                    .foregroundStyle(TxChatTheme.Palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(width: 150, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TxChatPermissionCard: View {
    let title: String
    let detail: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TxChatTheme.Palette.raised.opacity(0.86))

            Text(title)
                .font(TxChatTheme.bodyControl)
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .lineLimit(1)
                .frame(width: 266, height: 23, alignment: .leading)
                .offset(x: 17, y: 18)

            Text(detail)
                .font(TxChatTheme.caption)
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .lineLimit(1)
                .frame(width: 266, height: 19, alignment: .leading)
                .offset(x: 17, y: 52)

            if granted {
                Text("已开启")
                    .font(TxChatTheme.control)
                    .foregroundStyle(TxChatTheme.Palette.success)
                    .frame(width: 116, height: 40)
                    .offset(x: 293, y: 27)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(
                        TxChatCompactPrimaryButtonStyle(fixedWidth: 116)
                    )
                    .offset(x: 293, y: 27)
            }
        }
        .frame(width: 430, height: 94)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .stroke(TxChatTheme.Palette.permissionBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.11), radius: 8, y: 7)
    }
}

struct TxChatCheckbox: View {
    @Binding var isOn: Bool
    let title: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            isOn
                                ? TxChatTheme.Palette.keycap
                                : TxChatTheme.Palette.raised.opacity(0.62)
                        )
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(
                            isOn
                                ? TxChatTheme.Palette.keycap
                                : TxChatTheme.Palette.controlBorder,
                            lineWidth: 1
                        )
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 16, height: 16)

                Text(title)
                    .font(TxChatTheme.compactCaption)
                    .foregroundStyle(TxChatTheme.Palette.tertiaryText)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 32,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "已同意" : "未同意")
    }
}

struct TxChatCompactPrimaryButtonStyle: ButtonStyle {
    var fixedWidth: CGFloat?
    var fixedHeight: CGFloat

    init(
        fixedWidth: CGFloat? = nil,
        fixedHeight: CGFloat = 40
    ) {
        self.fixedWidth = fixedWidth
        self.fixedHeight = fixedHeight
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TxChatTheme.control)
            .foregroundStyle(TxChatTheme.Palette.onPrimaryControl)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, fixedWidth == nil ? 14 : 0)
            .frame(width: fixedWidth, height: fixedHeight)
            .background(
                TxChatTheme.Palette.primaryControl.opacity(
                    configuration.isPressed ? 0.78 : 1
                )
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 8, y: 5)
    }
}
