import AppKit
import SwiftUI

#if DEBUG
enum ProductShortcutEditorVisualFixture: CaseIterable, Equatable {
    case current
    case waiting
    case captured
    case conflict
    case unavailable
    case unsupportedRightOption
    case saveFailed
    case longCurrent

    @MainActor
    func makeModel() -> ProductShortcutEditorModel {
        let candidate = (
            try? ProductShortcut(
                key: .standard(keyCode: 40, displayName: "A"),
                modifiers: [.control, .option]
            )
        ) ?? .defaultFn
        let longCurrent = (
            try? ProductShortcut(
                key: .standard(keyCode: 40, displayName: "K"),
                modifiers: [.control, .option, .shift, .command]
            )
        ) ?? .defaultFn
        let rightOption = (
            try? ProductShortcut(key: .rightOption, modifiers: [])
        ) ?? .defaultFn
        let model = ProductShortcutEditorModel(
            current: self == .longCurrent ? longCurrent : .defaultFn
        )

        switch self {
        case .current, .longCurrent:
            break
        case .waiting:
            model.beginCapture()
        case .captured:
            model.capture(candidate)
        case .conflict:
            model.capture(candidate)
            _ = model.save { _ in .failed(.conflict) }
        case .unavailable:
            model.rejectCandidate(
                displayName: "Shift + A",
                message: "Shift-only is unsafe"
            )
        case .unsupportedRightOption:
            model.capture(rightOption)
        case .saveFailed:
            model.capture(candidate)
            _ = model.save { _ in .saveFailed }
        }
        return model
    }
}
#endif

@MainActor
struct ProductShortcutEditorView: View {
    @StateObject private var model: ProductShortcutEditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.txChatLanguage) private var language
    @Environment(\.colorScheme) private var colorScheme

    private let updateShortcut:
        (ProductShortcut) -> ShortcutUpdateResult

    init(
        current: ProductShortcut,
        updateShortcut: @escaping
            (ProductShortcut) -> ShortcutUpdateResult
    ) {
        _model = StateObject(
            wrappedValue: ProductShortcutEditorModel(current: current)
        )
        self.updateShortcut = updateShortcut
    }

#if DEBUG
    init(
        visualFixture: ProductShortcutEditorVisualFixture,
        updateShortcut: @escaping
            (ProductShortcut) -> ShortcutUpdateResult = { _ in .updated }
    ) {
        _model = StateObject(wrappedValue: visualFixture.makeModel())
        self.updateShortcut = updateShortcut
    }
#endif

    var body: some View {
        ZStack(alignment: .topLeading) {
            TxChatSurfaceBackdrop(
                width: TxChatTheme.Layout.shortcutEditorWidth,
                height: TxChatTheme.Layout.shortcutEditorHeight,
                radius: 18
            )

            header
                .offset(x: 24, y: 24)

            currentShortcutRow
                .offset(x: 24, y: 100)

            Button {
                if model.state != .waiting {
                    model.beginCapture()
                }
            } label: {
                ShortcutCaptureKeycap(
                    mainText: captureMainText,
                    secondaryText: captureSecondaryText
                )
            }
            .buttonStyle(.plain)
            .background {
                if model.state == .waiting {
                    ShortcutCaptureEventView(onEvent: handleCaptureEvent)
                        .frame(width: 1, height: 1)
                }
            }
            .offset(x: 24, y: 148)
            .accessibilityIdentifier("shortcut.capture-field")

            guidance
                .offset(x: 24, y: 266)

            actions
                .offset(x: 24, y: 322)
        }
        .frame(
            width: TxChatTheme.Layout.shortcutEditorWidth,
            height: TxChatTheme.Layout.shortcutEditorHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 20, y: 16)
        .accessibilityIdentifier("shortcut.editor")
    }

    private var header: some View {
        HStack(spacing: 12) {
            TxChatBrandMark(size: 56)
            Text(language.select("修改快捷键", "Change Shortcut"))
                .font(TxChatTheme.noto(20, weight: .bold))
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .lineLimit(1)
        }
        .frame(height: 56)
    }

    private var currentShortcutRow: some View {
        HStack(spacing: language == .english ? 12 : 12) {
            Text(language.select("当前快捷键", "Current Shortcut"))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .fixedSize()
            ShortcutCurrentKeycap(name: model.current.displayName)
            Spacer(minLength: 0)
        }
        .frame(width: 472, height: 28, alignment: .leading)
    }

    private var guidance: some View {
        Text(
            language.select(
                "普通组合键需包含 Control、Option、Shift 或 Command。不接受裸键、Shift-only、Fn 组合、重复修饰键或空主键。",
                "Combinations must include Control, Option, Shift, or Command. Bare keys, Shift-only, Fn combos, duplicate modifiers, or empty main keys are not accepted."
            )
        )
        .font(TxChatTheme.compactCaption)
        .foregroundStyle(TxChatTheme.Palette.secondaryText)
        .lineSpacing(3)
        .lineLimit(2)
        .frame(width: 472, height: 38, alignment: .topLeading)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Spacer()
            Button(language.select("取消", "Cancel")) {
                model.cancelCapture()
                dismiss()
            }
            .buttonStyle(ShortcutSecondaryActionStyle())
            .keyboardShortcut(.cancelAction)

            Button(
                model.state == .saveFailed
                    ? language.select("重试保存", "Retry Save")
                    : language.select("保存", "Save")
            ) {
                if model.save(using: updateShortcut) {
                    dismiss()
                }
            }
            .buttonStyle(
                ShortcutPrimaryActionStyle(
                    width: model.state == .saveFailed
                        ? TxChatTheme.Layout.shortcutRetryButtonWidth
                        : TxChatTheme.Layout.shortcutPrimaryButtonWidth
                )
            )
            .disabled(!model.canSave)
            .accessibilityIdentifier("shortcut.save")
        }
        .frame(width: 472, height: 43)
    }

    private var captureMainText: String {
        switch model.state {
        case .current:
            language.select("按下新的快捷键", "Press a new shortcut")
        case .waiting:
            language.select("请按下新的快捷键…", "Press a new shortcut…")
        case .captured, .conflict, .unavailable, .unsupported, .saveFailed:
            model.displayedName
        }
    }

    private var captureSecondaryText: String {
        switch model.state {
        case .current:
            language.select("点击此处开始录入", "Click here to start recording")
        case .waiting:
            language.select("按 Esc 可取消", "Press Esc to cancel")
        case .captured:
            language.select("保存成功后才会生效", "Takes effect only after saving")
        case .conflict:
            language.select(
                "已被占用，重新设置新的快捷键。",
                "Already in use — please set a new shortcut."
            )
        case .unavailable:
            language.select(
                "不安全，重新设置新的快捷键。",
                "Unsafe — please set a new shortcut."
            )
        case .unsupported:
            language.select(
                "暂不支持，重新设置新的快捷键。",
                "Not supported — please set a new shortcut."
            )
        case .saveFailed:
            language.select(
                "未能保存到本机，重新设置新的快捷键。",
                "Failed to save locally — please set a new shortcut."
            )
        }
    }

    private func handleCaptureEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            model.cancelCapture()
            dismiss()
            return
        }
        do {
            if let shortcut = try ProductShortcutEventMapper.shortcut(from: event) {
                model.capture(shortcut)
            }
        } catch let validation as ProductShortcut.ValidationError {
            model.rejectCandidate(
                displayName: ProductShortcutEventMapper.displayName(from: event),
                message: validationMessage(for: validation)
            )
        } catch {
            model.rejectCandidate(
                displayName: ProductShortcutEventMapper.displayName(from: event)
            )
        }
    }

    private func validationMessage(
        for error: ProductShortcut.ValidationError
    ) -> String {
        switch error {
        case .shiftOnly:
            language.select("Shift-only 不安全", "Shift-only is unsafe")
        case .emptyModifiers:
            language.select("裸键不安全", "Bare keys are unsafe")
        case .functionKeyCombination:
            language.select("Fn 组合暂不支持", "Fn combinations are not supported")
        case .duplicateModifiers:
            language.select("重复修饰键无效", "Duplicate modifiers are invalid")
        case .standaloneModifierCombination:
            language.select("独立修饰键组合无效", "Modifier-only shortcuts are invalid")
        case .emptyKeyDisplayName:
            language.select("空主键无效", "An empty main key is invalid")
        }
    }
}

private struct ShortcutCurrentKeycap: View {
    let name: String

    var body: some View {
        TxChatInlineKeycap(label: name)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ShortcutCaptureKeycap: View {
    let mainText: String
    let secondaryText: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.102, green: 0.102, blue: 0.102))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(red: 0.102, green: 0.102, blue: 0.102), lineWidth: 1)
                }

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.188, blue: 0.18),
                            Color(red: 0.122, green: 0.110, blue: 0.102),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(red: 0.251, green: 0.239, blue: 0.231), lineWidth: 1)
                }
                .padding(8)

            VStack(spacing: 6) {
                Text(mainText)
                    .font(TxChatTheme.noto(16, weight: .bold))
                    .foregroundStyle(Color(red: 0.95, green: 0.94, blue: 0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(secondaryText)
                    .font(TxChatTheme.noto(12))
                    .foregroundStyle(Color(red: 0.95, green: 0.94, blue: 0.92).opacity(0.40))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 20)
        }
        .frame(width: 472, height: 98)
        .shadow(color: .black.opacity(0.30), radius: 5, y: 4)
        .contentShape(Rectangle())
    }
}

private struct ShortcutSecondaryActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TxChatTheme.control)
            .foregroundStyle(TxChatTheme.Palette.secondaryText)
            .frame(
                width: TxChatTheme.Layout.shortcutSecondaryButtonWidth,
                height: TxChatTheme.Layout.shortcutSecondaryButtonHeight
            )
            .background(TxChatTheme.Palette.canvas.opacity(configuration.isPressed ? 0.62 : 1))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(TxChatTheme.Palette.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct ShortcutPrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TxChatTheme.control)
            .foregroundStyle(TxChatTheme.Palette.onPrimaryControl)
            .frame(
                width: width,
                height: TxChatTheme.Layout.shortcutPrimaryButtonHeight
            )
            .background(TxChatTheme.Palette.primaryControl)
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.34)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct ShortcutCaptureEventView: NSViewRepresentable {
    let onEvent: (NSEvent) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onEvent = onEvent
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onEvent = onEvent
        nsView.requestFocus()
    }

    final class CaptureView: NSView {
        var onEvent: (NSEvent) -> Void = { _ in }

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            requestFocus()
        }

        func requestFocus() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.window?.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            onEvent(event)
        }

        override func flagsChanged(with event: NSEvent) {
            onEvent(event)
        }
    }
}
