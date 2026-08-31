import SwiftUI

struct LoginView: View {
    @Binding var phone: String
    @Binding var verificationCode: String
    @Binding var termsAccepted: Bool

    let presentation: LoginPresentation
    let resendSecondsRemaining: Int
    let isSMSRequestLocked: Bool
    let verificationCodeFocusGeneration: Int
    let isRequestingSMSCode: Bool
    let isVerifyingSMSCode: Bool
    let shortcutDisplayName: String
    let requestSMSCode: () async -> Void
    let verifySMSCode: () async -> Void
    let toggleLanguage: () -> Void
    let showDocument: (TxChatTextDocumentKind) -> Void
    @Environment(\.txChatLanguage) private var language
    @FocusState private var focusedField: LoginField?

    private enum LoginField: Hashable {
        case phone
        case verificationCode
    }

    init(
        phone: Binding<String>,
        verificationCode: Binding<String>,
        termsAccepted: Binding<Bool>,
        presentation: LoginPresentation,
        resendSecondsRemaining: Int,
        isSMSRequestLocked: Bool,
        verificationCodeFocusGeneration: Int,
        isRequestingSMSCode: Bool,
        isVerifyingSMSCode: Bool,
        shortcutDisplayName: String,
        requestSMSCode: @escaping () async -> Void,
        verifySMSCode: @escaping () async -> Void,
        toggleLanguage: @escaping () -> Void,
        showDocument:
            @escaping (TxChatTextDocumentKind) -> Void = { _ in }
    ) {
        _phone = phone
        _verificationCode = verificationCode
        _termsAccepted = termsAccepted
        self.presentation = presentation
        self.resendSecondsRemaining = resendSecondsRemaining
        self.isSMSRequestLocked = isSMSRequestLocked
        self.verificationCodeFocusGeneration =
            verificationCodeFocusGeneration
        self.isRequestingSMSCode = isRequestingSMSCode
        self.isVerifyingSMSCode = isVerifyingSMSCode
        self.shortcutDisplayName = shortcutDisplayName
        self.requestSMSCode = requestSMSCode
        self.verifySMSCode = verifySMSCode
        self.toggleLanguage = toggleLanguage
        self.showDocument = showDocument
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TxChatWindowBackdrop()

            TxChatBrandMark(size: 56)
                .offset(x: 331, y: 76)

            welcomeCopy

            headlineCopy
                .offset(x: 77, y: 226)

            privacyChip
                .offset(x: 77, y: 363)

            loginForm
                .offset(x: 389, y: 226)

            languageLabel
                .offset(x: 634, y: 17)

            if let toastMessage = presentation.toastMessage {
                switch presentation.toastPlacement {
                case .topSMS:
                    if let smsPillWidth = presentation.smsPillWidth {
                        smsStatusPill(
                            toastMessage,
                            width: smsPillWidth
                        )
                        .offset(
                            x: (TxChatTheme.Layout.windowWidth - smsPillWidth) / 2,
                            y: 41
                        )
                        .transition(.opacity)
                    }
                case .bottomCompact:
                    compactLoginToast(toastMessage)
                        .offset(x: 390, y: 478)
                        .transition(.opacity)
                case nil:
                    EmptyView()
                }
            }
        }
        .frame(
            width: TxChatTheme.Layout.windowWidth,
            height: TxChatTheme.Layout.windowHeight
        )
        .clipped()
        .onChange(of: phone) {
            let formatted = TxChatLoginInputFormatter.phone(phone)
            if phone != formatted {
                phone = formatted
            }
        }
        .onChange(of: verificationCode) {
            let formatted = TxChatLoginInputFormatter.credential(
                verificationCode
            )
            if verificationCode != formatted {
                verificationCode = formatted
            }
        }
        .onChange(of: verificationCodeFocusGeneration) {
            focusedField = .verificationCode
        }
        .accessibilityIdentifier("login.screen")
    }

    @ViewBuilder
    private var welcomeCopy: some View {
        if language == .english {
            (
                Text("Welcome to ")
                    .foregroundColor(TxChatTheme.Palette.secondaryText) +
                    Text(ProductBrand.displayName)
                    .foregroundColor(TxChatTheme.Palette.warmAccent)
            )
            .font(TxChatTheme.bodyEmphasis)
            .fixedSize()
            .offset(x: 295, y: 146)
        } else {
            (
                Text("欢迎使用 ")
                    .foregroundColor(TxChatTheme.Palette.secondaryText) +
                    Text(ProductBrand.displayName)
                    .foregroundColor(TxChatTheme.Palette.warmAccent)
            )
            .font(TxChatTheme.bodyEmphasis)
            .fixedSize()
            .offset(x: 296, y: 146)
        }
    }

    private var headlineCopy: some View {
        Text(
            language.select(
                "有想法就要\n说出来",
                "Just say it\nout loud"
            )
        )
        .font(TxChatTheme.loginDisplay)
        .foregroundStyle(TxChatTheme.Palette.primaryText)
        .lineSpacing(0)
        .frame(width: 250, height: 96, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var privacyChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(TxChatTheme.Palette.warmAccent)
                .frame(width: 6, height: 6)
            Text(language.select("说话，比打字更快", "Talk — faster than typing"))
                .font(TxChatTheme.caption)
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(TxChatTheme.Palette.raised.opacity(0.56))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(TxChatTheme.Palette.border, lineWidth: 1)
        }
        .accessibilityLabel(
            language.select(
                "说话，比打字更快。快捷键 \(shortcutDisplayName)",
                "Talk faster than typing. Shortcut \(shortcutDisplayName)"
            )
        )
    }

    private var loginForm: some View {
        ZStack(alignment: .topLeading) {
            phoneField
                .offset(y: 0)
            credentialField
                .offset(y: 70)

            HStack(spacing: 2) {
                TxChatCheckbox(
                    isOn: $termsAccepted,
                    title: language.select("同意", "Agree to")
                )
                .fixedSize()

                Button(
                    language.select("《服务条款》", "Terms of Service")
                ) {
                    showDocument(.serviceTerms)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("login.document.service-terms")

                Text(language.select("和", "and"))

                Button(
                    language.select("《隐私说明》", "Privacy Policy")
                ) {
                    showDocument(.privacyNotice)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("login.document.privacy-notice")
            }
            .font(TxChatTheme.compactCaption)
            .foregroundStyle(TxChatTheme.Palette.tertiaryText)
            .frame(width: 286, height: 24, alignment: .leading)
            .offset(y: 140)
            .accessibilityIdentifier("login.terms")

            Button(
                isVerifyingSMSCode
                    ? language.select("正在登录…", "Signing in…")
                    : language.select("登录", "Log In")
            ) {
                Task { await verifySMSCode() }
            }
            .buttonStyle(
                LoginPrimaryButtonStyle(
                    enabled: canVerify || isSMSRequestLocked
                )
            )
            .disabled(!canVerify)
            .accessibilityIdentifier("login.verify")
            .frame(width: 286, height: 48)
            .offset(y: 178)
        }
        .frame(
            width: TxChatTheme.Layout.formWidth,
            height: 226,
            alignment: .topLeading
        )
    }

    private var phoneField: some View {
        HStack(spacing: 0) {
            Text("+86")
            .font(TxChatTheme.control)
            .foregroundStyle(TxChatTheme.Palette.secondaryText)
            .frame(width: 64, height: 40)
            .background(TxChatTheme.Palette.fieldInset)
            .clipShape(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

            TextField(
                language.select("请输入手机号", "Enter phone number"),
                text: $phone
            )
                .focused($focusedField, equals: .phone)
                .textFieldStyle(.plain)
                .font(TxChatTheme.compactBody)
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .padding(.leading, 16)
                .accessibilityIdentifier("login.phone")
        }
        .padding(.horizontal, 7)
        .frame(height: 56)
        .background(TxChatTheme.Palette.raised.opacity(0.9))
        .clipShape(fieldShape)
        .overlay {
            fieldShape
                .stroke(phoneFieldBorder, lineWidth: phoneFieldBorderWidth)
                .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(0.09), radius: 6, y: 5)
    }

    private var credentialField: some View {
        HStack(spacing: 6) {
            TextField(
                    language.select(
                        "输入 6 位验证码",
                        "Enter 6-digit code"
                    ),
                    text: $verificationCode
                )
                .textFieldStyle(.plain)
                .font(TxChatTheme.compactBody)
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
                .focused($focusedField, equals: .verificationCode)
                .accessibilityIdentifier("login.verification-code")
                .accessibilityHint(
                    language.select(
                        "请输入短信中的 6 位验证码",
                        "Enter the six-digit code from the text message"
                    )
                )
            .padding(.leading, 6)

            Button(
                isRequestingSMSCode
                    ? language.select("获取中…", "Getting…")
                    : requestCodeTitle
            ) {
                Task { await requestSMSCode() }
            }
            .buttonStyle(.plain)
            .font(TxChatTheme.compactCaption)
            .foregroundStyle(
                canRequestCode &&
                    presentation.visualState != .invalidCredential
                    ? TxChatTheme.Palette.fieldActionText
                    : TxChatTheme.Palette.secondaryText
            )
            .frame(width: 100, height: 40)
            .background(
                canRequestCode || isSMSRequestLocked
                    ? TxChatTheme.Palette.fieldAction
                    : TxChatTheme.Palette.fieldInset
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .disabled(!canRequestCode)
            .accessibilityIdentifier("login.request-code")
        }
        .padding(.horizontal, 7)
        .frame(width: 286, height: 56)
        .background(TxChatTheme.Palette.raised.opacity(0.9))
        .clipShape(fieldShape)
        .overlay {
            fieldShape
                .stroke(
                    credentialFieldBorder,
                    lineWidth: credentialFieldBorderWidth
                )
                .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(0.09), radius: 6, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("login.verification-help")
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: TxChatTheme.Radius.field,
            style: .continuous
        )
    }

    private var phoneFieldBorder: Color {
        phone.isEmpty
            ? TxChatTheme.Palette.fieldBorder
            : TxChatTheme.Palette.fieldFocus.opacity(0.65)
    }

    private var phoneFieldBorderWidth: CGFloat {
        phone.isEmpty ? 1 : 1.5
    }

    private var credentialFieldBorder: Color {
        switch presentation.visualState {
        case .invalidCredential, .verificationLocked:
            return TxChatTheme.Palette.fieldError
        case .initial, .phoneEntered, .codeSent, .credentialEntered, .ready,
             .challengeExpired, .challengeExhausted,
             .verificationRetryLimited, .sendCooldown, .sendQuotaLimited,
             .sendUnavailable, .serviceUnavailable:
            return TxChatTheme.Palette.fieldBorder
        }
    }

    private var credentialFieldBorderWidth: CGFloat {
        [.invalidCredential, .verificationLocked]
            .contains(presentation.visualState) ? 1.5 : 1
    }

    private func smsStatusPill(
        _ text: String,
        width smsPillWidth: CGFloat
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(TxChatTheme.Palette.smsStatusIcon)
                .frame(width: 18, height: 18)
            Text(text)
                .font(TxChatTheme.bodyEmphasis)
                .foregroundStyle(TxChatTheme.Palette.inverseText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 18)
        .frame(width: smsPillWidth, height: 44)
        .background(TxChatTheme.Palette.inverseSurface)
        .clipShape(Capsule())
        .accessibilityIdentifier("login.sms-message")
    }

    private func compactLoginToast(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(TxChatTheme.Palette.warning)
            Text(text)
                .font(TxChatTheme.caption)
                .foregroundStyle(TxChatTheme.Palette.primaryText)
        }
        .padding(.horizontal, 13)
        .frame(width: TxChatTheme.Layout.formWidth, height: 38)
        .background(TxChatTheme.Palette.raised.opacity(0.96))
        .clipShape(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TxChatTheme.Palette.border, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
        .accessibilityIdentifier("login.message")
    }

    private var canVerify: Bool {
        !isVerifyingSMSCode && presentation.canVerify
    }

    private var canRequestCode: Bool {
        !isRequestingSMSCode && resendSecondsRemaining == 0 &&
            !isSMSRequestLocked &&
            (try? MainlandPhone(phone)) != nil
    }

    private var requestCodeTitle: String {
        if resendSecondsRemaining > 0 {
            let duration = ProductPresentation.retryDuration(
                seconds: resendSecondsRemaining,
                language: language
            )
            return language.select(
                "\(duration)后重试",
                "Retry in \(duration)"
            )
        }
        return language.select("获取验证码", "Get Code")
    }

    private var languageLabel: some View {
        Button(action: toggleLanguage) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .regular))
                Text(language == .simplifiedChinese ? "English" : "中文")
                    .font(TxChatTheme.caption)
            }
            .foregroundStyle(TxChatTheme.Palette.secondaryText)
            .frame(width: 64, height: 20, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("login.language")
    }
}

enum TxChatLoginInputFormatter {
    static func phone(_ value: String) -> String {
        var digits = value.filter(\.isNumber)
        if digits.hasPrefix("86"), digits.count > 11 {
            digits.removeFirst(2)
        }
        digits = String(digits.prefix(11))
        return grouped(digits, lengths: [3, 4, 4])
    }

    static func credential(_ value: String) -> String {
        let digits = String(value.filter(\.isNumber).prefix(6))
        return grouped(digits, lengths: [3, 3])
    }

    private static func grouped(
        _ value: String,
        lengths: [Int]
    ) -> String {
        var remainder = value[...]
        var groups: [String] = []
        for length in lengths where !remainder.isEmpty {
            let end = remainder.index(
                remainder.startIndex,
                offsetBy: min(length, remainder.count)
            )
            groups.append(String(remainder[..<end]))
            remainder = remainder[end...]
        }
        return groups.joined(separator: " ")
    }
}

private struct LoginPrimaryButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TxChatTheme.label)
            .foregroundStyle(TxChatTheme.Palette.onPrimaryControl)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                enabled
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [
                                TxChatTheme.Palette.primaryControl,
                                TxChatTheme.Palette.primaryControl.opacity(0.86),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(TxChatTheme.Palette.disabledControl)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: TxChatTheme.Radius.control,
                    style: .continuous
                )
            )
            .shadow(
                color: enabled
                    ? Color.black.opacity(0.12)
                    : Color.black.opacity(0.06),
                radius: 10,
                y: 6
            )
    }
}
