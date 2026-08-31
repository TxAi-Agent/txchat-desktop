import SwiftUI

private enum DictionarySettingsLayout {
    static let windowSize = CGSize(width: 720, height: 560)
    static let contentWidth: CGFloat = 640
    static let gridWidth: CGFloat = 632
    static let cardSize = CGSize(width: 204, height: 56)
    static let actionSize = CGSize(width: 88, height: 42)
}

private struct DictionarySettingsCopy {
    let language: TxChatLanguage

    var title: String { language.select("词典", "Dictionary") }
    var description: String {
        language.select(
            "将识别结果中的错误词固定替换为正确词",
            "Replace incorrectly recognized words with fixed corrections"
        )
    }
    var reload: String { language.select("重新加载", "Reload") }
    var openFolder: String { language.select("打开词典文件", "Open Dictionary File") }
    var add: String { language.select("添加", "Add") }
    var cancel: String { language.select("取消", "Cancel") }
    var save: String { language.select("保存", "Save") }
    var emptyTitle: String { language.select("还没有词条", "No entries yet") }
    var emptyBody: String {
        language.select(
            "点击右下角“添加”，创建第一条“错误词 → 正确词”固定纠正规则。",
            "Click “Add” in the bottom-right to create your first “incorrect → correct” rule."
        )
    }
    var addTitle: String { language.select("添加词条", "Add Entry") }
    var editTitle: String { language.select("编辑词条", "Edit Entry") }
    var wrong: String {
        language.select("识别结果中的错误词", "Incorrect recognized word")
    }
    var correct: String {
        language.select("固定替换为正确词", "Replace with correct word")
    }
    var wrongPlaceholder: String {
        language.select("请输入错误词", "Enter incorrect word")
    }
    var correctPlaceholder: String {
        language.select("请输入正确词", "Enter correct word")
    }
    var enabled: String { language.select("启用此词条", "Enable this entry") }
    var delete: String { language.select("删除", "Delete") }
    var deleteTitle: String { language.select("删除这个词条？", "Delete this entry?") }
    var deleteBody: String {
        language.select(
            "删除后，这条固定纠正规则将不再生效。",
            "After deletion, this fixed correction will no longer apply."
        )
    }
    var confirmDelete: String { language.select("确认删除", "Confirm") }

    func validation(_ error: DictionaryEditorValidationError) -> String {
        switch error {
        case .wrongEmpty:
            language.select("请输入错误词", "Enter the wrong term")
        case .correctEmpty:
            language.select("请输入正确词", "Enter the correct term")
        case .valuesEqual:
            language.select("错误词和正确词不能相同", "The two terms must differ")
        case .fieldTooLong:
            language.select("每个词最多 100 个字符", "Each term can contain up to 100 characters")
        case .duplicateWrong:
            language.select(
                "该错误词已存在，请编辑原词条",
                "Already exists. Edit the existing entry."
            )
        case .invalidLineBreak:
            language.select("词条不能包含换行", "Entries cannot contain line breaks")
        }
    }

    func notice(
        _ notice: DictionarySettingsNotice,
        loadedEntryCount: Int
    ) -> String {
        switch notice {
        case let .partialReload(skippedLineCount):
            language.select(
                "已加载 \(loadedEntryCount) 条，另有 \(skippedLineCount) 行格式不正确，已跳过",
                "Loaded \(loadedEntryCount) entries; skipped \(skippedLineCount) invalid rows"
            )
        case .loadFailed:
            language.select("无法读取词典，当前内容未更改", "Couldn’t read the dictionary; current content is unchanged")
        case .reloadFailed:
            language.select("重新加载失败，继续使用上次有效内容", "Reload failed; the last valid content is still active")
        case .saveFailed:
            language.select("保存失败，原文件保持不变", "Save failed; the original file is unchanged")
        case .openFileFailed:
            language.select("无法创建或打开词典文件", "Couldn’t create or open the dictionary file")
        }
    }
}

struct DictionarySettingsView: View {
    @ObservedObject var coordinator: DictionarySettingsCoordinator
    @Environment(\.txChatLanguage) private var language

    var body: some View {
        let copy = DictionarySettingsCopy(language: language)
        ZStack(alignment: .topLeading) {
            TxChatTheme.Palette.canvas
            header(copy)
            content(copy)
            footer(copy)

            if let notice = coordinator.notice {
                noticeView(notice, copy: copy)
            }
            if coordinator.isBusy {
                TxChatTheme.Palette.canvas.opacity(0.38)
                ProgressView()
                    .controlSize(.small)
                    .offset(x: 351, y: 275)
                    .accessibilityLabel(language.select("处理中", "Working"))
            }
            if coordinator.editor != nil {
                Color.black.opacity(0.18)
                DictionaryEntryEditorDialog(
                    coordinator: coordinator,
                    copy: copy
                )
                .offset(x: 40, y: 140)
            }
            if let entry = pendingCardDeletionEntry {
                Color.black.opacity(0.18)
                DictionaryDeleteConfirmation(
                    copy: copy,
                    entry: entry,
                    cancel: coordinator.cancelCardDeletion,
                    confirm: coordinator.confirmCardDeletion
                )
                .offset(x: 160, y: 160)
            }
        }
        .frame(
            width: DictionarySettingsLayout.windowSize.width,
            height: DictionarySettingsLayout.windowSize.height,
            alignment: .topLeading
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onExitCommand {
            if coordinator.editor != nil {
                coordinator.dismissEditor()
            } else {
                coordinator.cancel()
            }
        }
        .accessibilityIdentifier("dictionary.window")
    }

    private func header(_ copy: DictionarySettingsCopy) -> some View {
        Group {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(copy.title)
                    .font(TxChatTheme.noto(17, weight: .medium))
                    .foregroundStyle(TxChatTheme.Palette.primaryText)
                Text(copy.description)
                    .font(TxChatTheme.noto(12))
                    .foregroundStyle(TxChatTheme.Palette.secondaryText)
                    .lineLimit(1)
            }
            .offset(x: 40, y: 61)

            HStack(spacing: 8) {
                dictionaryIconButton(
                    asset: "TxChatDictionaryReload",
                    label: copy.reload
                ) {
                    Task { await coordinator.reload() }
                }
                dictionaryIconButton(
                    asset: "TxChatDictionaryFolder",
                    label: copy.openFolder
                ) {
                    Task { await coordinator.openFile() }
                }
            }
            .offset(x: 616, y: 58)
        }
    }

    @ViewBuilder
    private func content(_ copy: DictionarySettingsCopy) -> some View {
        if coordinator.entries.isEmpty {
            VStack(spacing: 10) {
                Image("TxChatDictionaryEmpty")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(TxChatTheme.Palette.secondaryText.opacity(0.42))
                    .frame(width: 40, height: 40)
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                Text(copy.emptyTitle)
                    .font(TxChatTheme.noto(17, weight: .medium))
                    .foregroundStyle(TxChatTheme.Palette.primaryText)
                Text(copy.emptyBody)
                    .font(TxChatTheme.noto(12))
                    .foregroundStyle(TxChatTheme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(width: 440)
            }
            .frame(width: 632, height: 190)
            .offset(x: 40, y: 200)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("dictionary.empty")
        } else {
            let entries = ScrollView(.vertical) {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(
                            .fixed(DictionarySettingsLayout.cardSize.width),
                            spacing: 10
                        ),
                        count: 3
                    ),
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(
                        Array(coordinator.entries.enumerated()),
                        id: \.offset
                    ) { index, entry in
                        DictionaryEntryCard(
                            entry: entry,
                            edit: { coordinator.presentEditEditor(at: index) },
                            delete: {
                                coordinator.requestCardDeletion(at: index)
                            }
                        )
                    }
                }
                .frame(width: DictionarySettingsLayout.gridWidth, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier("dictionary.entries")

            if coordinator.notice?.isPartialReload == true {
                entries
                    .frame(width: 640, height: 222, alignment: .topLeading)
                    .offset(x: 40, y: 172)
            } else if coordinator.entries.count > 12 {
                entries
                    .frame(width: 640, height: 350, alignment: .topLeading)
                    .offset(x: 40, y: 120)
            } else {
                entries
                    .frame(width: 640, height: 274, alignment: .topLeading)
                    .offset(x: 40, y: 120)
            }
        }
    }

    private func footer(_ copy: DictionarySettingsCopy) -> some View {
        HStack(spacing: 8) {
            DictionaryActionButton(title: copy.add, style: .secondary) {
                coordinator.presentAddEditor()
            }
            .disabled(
                coordinator.entries.count >= TxChatDictionaryLimits.maximumEntryCount
                    || coordinator.isBusy
            )
            .accessibilityIdentifier("dictionary.add")
            DictionaryActionButton(title: copy.cancel, style: .secondary) {
                coordinator.cancel()
            }
            .accessibilityIdentifier("dictionary.cancel")
            DictionaryActionButton(title: copy.save, style: .primary) {
                Task { await coordinator.save() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(coordinator.isBusy)
            .accessibilityIdentifier("dictionary.save")
        }
        .offset(x: 400, y: 498)
    }

    private func dictionaryIconButton(
        asset: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(asset)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .frame(width: 16, height: 16)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(coordinator.isBusy)
        .accessibilityLabel(label)
        .help(label)
    }

    private func noticeView(
        _ notice: DictionarySettingsNotice,
        copy: DictionarySettingsCopy
    ) -> some View {
        HStack(spacing: 10) {
            if notice.isPartialReload {
                Image("TxChatDictionaryReload")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .opacity(0.62)
            } else {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 13, weight: .regular))
            }
            Text(
                copy.notice(
                    notice,
                    loadedEntryCount: coordinator.entries.count
                )
            )
                .font(TxChatTheme.noto(13))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(
            notice.isFailure
                ? TxChatTheme.Palette.dictionaryDanger
                : TxChatTheme.Palette.secondaryText
        )
        .padding(.horizontal, 12)
        .frame(width: 632, height: 44)
        .background(TxChatTheme.Palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .offset(x: 40, y: 112)
        .accessibilityIdentifier("dictionary.notice")
    }

    private var pendingCardDeletionEntry: TxChatDictionaryEntry? {
        guard let index = coordinator.pendingCardDeletionIndex,
              coordinator.entries.indices.contains(index) else {
            return nil
        }
        return coordinator.entries[index]
    }
}

private extension DictionarySettingsNotice {
    var isPartialReload: Bool {
        if case .partialReload = self { return true }
        return false
    }

    var isFailure: Bool {
        switch self {
        case .partialReload: false
        case .loadFailed, .reloadFailed, .saveFailed, .openFileFailed: true
        }
    }
}

private struct DictionaryEntryCard: View {
    let entry: TxChatDictionaryEntry
    let edit: () -> Void
    let delete: () -> Void
    @Environment(\.txChatLanguage) private var language

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                term(entry.wrong)
                Image("TxChatDictionaryArrow")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(TxChatTheme.Palette.secondaryText)
                    .frame(width: 16, height: 16)
                term(entry.correct)
            }
            .frame(width: 126, height: 24)
            .clipped()

            HStack(spacing: 4) {
                compactAction(
                    asset: "TxChatDictionaryEdit",
                    label: language.select("编辑词条", "Edit entry"),
                    action: edit
                )
                compactAction(
                    asset: "TxChatDictionaryDelete",
                    label: language.select("删除词条", "Delete entry"),
                    action: delete
                )
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(width: 204, height: 56)
        .background(
            entry.isEnabled
                ? TxChatTheme.Palette.raised
                : TxChatTheme.Palette.canvas
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(TxChatTheme.Palette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(entry.isEnabled ? 1 : 0.55)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entry.wrong), \(entry.correct)")
    }

    private func term(_ value: String) -> some View {
        Text(value)
            .font(TxChatTheme.noto(13))
            .foregroundStyle(TxChatTheme.Palette.primaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactAction(
        asset: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(asset)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .frame(width: 16, height: 16)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct DictionaryEntryEditorDialog: View {
    @ObservedObject var coordinator: DictionarySettingsCoordinator
    let copy: DictionarySettingsCopy
    @FocusState private var focusedField: Field?

    private enum Field { case wrong, correct }

    var body: some View {
        if let editor = coordinator.editor {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(TxChatTheme.Palette.raised)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(TxChatTheme.Palette.border, lineWidth: 1)
                    }
                    .shadow(
                        color: Color.black.opacity(0.16),
                        radius: 20,
                        x: 0,
                        y: 16
                    )

                Text(editorTitle(editor))
                    .font(TxChatTheme.noto(23, weight: .bold))
                    .foregroundStyle(TxChatTheme.Palette.primaryText)
                    .offset(x: 32, y: 32)

                DictionaryToggle(
                    isOn: editor.isEnabled,
                    label: copy.enabled,
                    set: coordinator.updateEditorEnabled
                )
                .offset(x: 556, y: 34)

                HStack(spacing: 72) {
                    Text(copy.wrong)
                        .frame(width: 252, alignment: .leading)
                    Text(copy.correct)
                        .frame(width: 252, alignment: .leading)
                }
                .font(TxChatTheme.noto(13, weight: .medium))
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .offset(x: 32, y: 96)

                HStack(spacing: 28) {
                    editorField(
                        label: copy.wrongPlaceholder,
                        value: editor.wrong,
                        field: .wrong,
                        isInvalid: isFieldInvalid(
                            .wrong,
                            error: editor.validationError
                        )
                    )
                    Image("TxChatDictionaryArrow")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(TxChatTheme.Palette.secondaryText)
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                    editorField(
                        label: copy.correctPlaceholder,
                        value: editor.correct,
                        field: .correct,
                        isInvalid: isFieldInvalid(
                            .correct,
                            error: editor.validationError
                        )
                    )
                }
                .offset(x: 32, y: 129)

                if let error = editor.validationError {
                    Text(copy.validation(error))
                        .font(TxChatTheme.noto(11))
                        .foregroundStyle(TxChatTheme.Palette.dictionaryDanger)
                        .offset(x: 32, y: 176)
                        .accessibilityIdentifier("dictionary.editor.error")
                }

                if case .edit = editor.mode {
                    DictionaryActionButton(
                        title: editor.isDeleteConfirmationPresented
                            ? copy.confirmDelete
                            : copy.delete,
                        style: .destructive
                    ) {
                        if editor.isDeleteConfirmationPresented {
                            coordinator.confirmEditorDeletion()
                        } else {
                            coordinator.requestEditorDeletion()
                        }
                    }
                    .offset(x: 32, y: 206)
                    .accessibilityIdentifier("dictionary.editor.delete")
                }

                HStack(spacing: 8) {
                    DictionaryActionButton(title: copy.cancel, style: .secondary) {
                        coordinator.dismissEditor()
                    }
                    DictionaryActionButton(title: copy.save, style: .primary) {
                        coordinator.confirmEditor()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(editor.validationError != nil)
                }
                .offset(x: 432, y: 206)
            }
            .frame(width: 640, height: 280)
            .onAppear { focusedField = .wrong }
            .accessibilityIdentifier("dictionary.editor")
        }
    }

    private func editorTitle(_ editor: DictionaryEditorState) -> String {
        switch editor.mode {
        case .add: copy.addTitle
        case .edit: copy.editTitle
        }
    }

    private func editorField(
        label: String,
        value: String,
        field: Field,
        isInvalid: Bool
    ) -> some View {
        TextField(
            "",
            text: Binding(
                get: { value },
                set: { newValue in
                    switch field {
                    case .wrong:
                        coordinator.updateEditorWrong(newValue)
                    case .correct:
                        coordinator.updateEditorCorrect(newValue)
                    }
                }
            ),
            prompt: Text(label)
        )
        .textFieldStyle(.plain)
        .font(TxChatTheme.noto(14))
        .foregroundStyle(TxChatTheme.Palette.primaryText)
        .padding(.horizontal, 12)
        .frame(width: 252, height: 42)
        .background(TxChatTheme.Palette.raised)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isInvalid
                        ? TxChatTheme.Palette.dictionaryDanger
                        : focusedField == field
                            ? TxChatTheme.Palette.fieldFocus
                            : TxChatTheme.Palette.fieldBorder,
                    lineWidth: isInvalid || focusedField == field ? 2 : 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .focused($focusedField, equals: field)
        .accessibilityLabel(label)
        .accessibilityIdentifier(
            field == .wrong
                ? "dictionary.editor.wrong"
                : "dictionary.editor.correct"
        )
    }

    private func isFieldInvalid(
        _ field: Field,
        error: DictionaryEditorValidationError?
    ) -> Bool {
        switch error {
        case .wrongEmpty, .duplicateWrong:
            field == .wrong
        case .correctEmpty:
            field == .correct
        case .valuesEqual, .fieldTooLong, .invalidLineBreak:
            true
        case nil:
            false
        }
    }
}

private struct DictionaryToggle: View {
    let isOn: Bool
    let label: String
    let set: (Bool) -> Void

    var body: some View {
        Button { set(!isOn) } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        isOn
                            ? TxChatTheme.Palette.inverseSurface
                            : TxChatTheme.Palette.fieldAction
                    )
                Circle()
                    .fill(TxChatTheme.Palette.raised)
                    .frame(width: 22, height: 22)
                    .padding(3)
            }
            .frame(width: 52, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "1" : "0")
    }
}

private struct DictionaryDeleteConfirmation: View {
    let copy: DictionarySettingsCopy
    let entry: TxChatDictionaryEntry
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(copy.deleteTitle)
                .font(TxChatTheme.noto(23, weight: .bold))
                .foregroundStyle(TxChatTheme.Palette.primaryText)
            Text(copy.deleteBody)
                .font(TxChatTheme.noto(14))
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .frame(width: 336, alignment: .leading)
            Text("\(entry.wrong)  →  \(entry.correct)")
                .font(TxChatTheme.noto(13, weight: .medium))
                .foregroundStyle(TxChatTheme.Palette.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 336, height: 36, alignment: .center)
            HStack(spacing: 8) {
                Spacer()
                DictionaryActionButton(
                    title: copy.cancel,
                    style: .secondary,
                    action: cancel
                )
                DictionaryActionButton(
                    title: copy.delete,
                    style: .destructive,
                    action: confirm
                )
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 32)
        .frame(width: 400, height: 240)
        .background(TxChatTheme.Palette.raised)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TxChatTheme.Palette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 20, y: 16)
        .accessibilityIdentifier("dictionary.delete-confirmation")
    }
}

private struct DictionaryActionButton: View {
    enum Style { case primary, secondary, destructive }

    let title: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(DictionaryActionButtonStyle(style: style))
    }
}

private struct DictionaryActionButtonStyle: ButtonStyle {
    let style: DictionaryActionButton.Style
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TxChatTheme.noto(14, weight: .medium))
            .foregroundStyle(foregroundColor)
            .frame(width: 88, height: 42)
            .background(
                style == .primary
                    ? isEnabled
                        ? TxChatTheme.Palette.inverseSurface
                        : TxChatTheme.Palette.fieldAction
                    : TxChatTheme.Palette.raised
            )
            .overlay {
                if style != .primary {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(
                            style == .destructive
                                ? TxChatTheme.Palette.dictionaryDanger
                                : TxChatTheme.Palette.border,
                            lineWidth: 1
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .opacity(configuration.isPressed ? 0.76 : 1)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: TxChatTheme.Palette.inverseText
        case .secondary: TxChatTheme.Palette.primaryText
        case .destructive: TxChatTheme.Palette.dictionaryDanger
        }
    }
}
