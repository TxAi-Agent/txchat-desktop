import CoreGraphics

enum ProductPresentation {
    static func login(
        phone: String,
        verificationCode: String,
        termsAccepted: Bool,
        challengeIsActive: Bool,
        feedback: LoginFeedback,
        verificationCanRetry: Bool = true,
        language: TxChatLanguage = .productDefault
    ) -> LoginPresentation {
        let phoneIsValid = (try? MainlandPhone(phone)) != nil
        let codeIsValid = (try? SMSVerificationCode(verificationCode)) != nil
        let canVerify = phoneIsValid && challengeIsActive &&
            codeIsValid && termsAccepted && verificationCanRetry

        switch feedback {
        case .termsRequired:
            return LoginPresentation(
                visualState: .serviceUnavailable,
                toastMessage: language.select(
                    "请先阅读并同意服务条款与隐私说明",
                    "Please agree to the Terms of Service and Privacy Policy"
                ),
                toastPlacement: .bottomCompact,
                canVerify: canVerify
            )
        case .invalidPhone:
            return LoginPresentation(
                visualState: .serviceUnavailable,
                toastMessage: language.select(
                    "请输入正确的中国大陆手机号",
                    "Enter a valid mainland China mobile number"
                ),
                toastPlacement: .bottomCompact,
                canVerify: canVerify
            )
        case .verificationInvalid:
            return LoginPresentation(
                visualState: .invalidCredential,
                toastMessage: nil,
                canVerify: canVerify
            )
        case .verificationIncorrect(let attemptsRemaining):
            return LoginPresentation(
                visualState: .invalidCredential,
                toastMessage: language.select(
                    "验证码错误，还可尝试 \(attemptsRemaining) 次",
                    "Incorrect code. \(attemptsRemaining) attempts remaining"
                ),
                toastPlacement: .topSMS,
                smsPillWidth: smsPillWidth(
                    for: feedback,
                    language: language
                ),
                canVerify: false
            )
        case .challengeExpired:
            return LoginPresentation(
                visualState: .challengeExpired,
                toastMessage: language.select(
                    "短信验证码已过期，请重新获取",
                    "Verification code expired. Get a new code"
                ),
                toastPlacement: .topSMS,
                smsPillWidth: smsPillWidth(
                    for: feedback,
                    language: language
                ),
                canVerify: false
            )
        case .challengeExhausted:
            return LoginPresentation(
                visualState: .challengeExhausted,
                toastMessage: language.select(
                    "本次验证码已失效，请重新获取",
                    "This code is no longer valid. Get a new code"
                ),
                toastPlacement: .topSMS,
                smsPillWidth: smsPillWidth(
                    for: feedback,
                    language: language
                ),
                canVerify: false
            )
        case .verificationRetryLimited(let retryAfterSeconds):
            let duration = retryDuration(
                seconds: retryAfterSeconds,
                language: language
            )
            return LoginPresentation(
                visualState: .verificationRetryLimited,
                toastMessage: language.select(
                    "操作太快，请 \(duration)后重试",
                    "Please wait \(duration) and try again"
                ),
                toastPlacement: .topSMS,
                smsPillWidth: smsPillWidth(
                    for: feedback,
                    language: language
                ),
                canVerify: false
            )
        case .verificationLocked(let retryAfterSeconds):
            let duration = retryDuration(
                seconds: retryAfterSeconds,
                language: language
            )
            return LoginPresentation(
                visualState: .verificationLocked,
                toastMessage: language.select(
                    "验证码错误次数过多，请 \(duration)后重试",
                    "Too many incorrect codes. Try again in \(duration)"
                ),
                toastPlacement: .topSMS,
                smsPillWidth: smsPillWidth(
                    for: feedback,
                    language: language
                ),
                canVerify: false
            )
        case .sendCooldown(let retryAfterSeconds):
            let duration = retryDuration(
                seconds: retryAfterSeconds,
                language: language
            )
            return LoginPresentation(
                visualState: .sendCooldown,
                toastMessage: language.select(
                    "请 \(duration)后重新获取验证码",
                    "Get another code in \(duration)"
                ),
                toastPlacement: .topSMS,
                smsPillWidth: smsPillWidth(
                    for: feedback,
                    language: language
                ),
                canVerify: canVerify
            )
        case .sendQuotaLimited(let retryAfterSeconds):
            let duration = retryDuration(
                seconds: retryAfterSeconds,
                language: language
            )
            return LoginPresentation(
                visualState: .sendQuotaLimited,
                toastMessage: language.select(
                    "发送次数较多，请 \(duration)后重试",
                    "Too many codes requested. Try again in \(duration)"
                ),
                toastPlacement: .topSMS,
                smsPillWidth: smsPillWidth(
                    for: feedback,
                    language: language
                ),
                canVerify: canVerify
            )
        case .sendUnavailable:
            return LoginPresentation(
                visualState: .sendUnavailable,
                toastMessage: language.select(
                    "短信验证码发送失败，请稍后重试",
                    "Couldn’t send code. Try again later"
                ),
                toastPlacement: .topSMS,
                smsPillWidth: smsPillWidth(
                    for: feedback,
                    language: language
                ),
                canVerify: canVerify
            )
        case .serviceUnavailable:
            return LoginPresentation(
                visualState: .serviceUnavailable,
                toastMessage: language.select(
                    "服务暂时不可用，请稍后重试",
                    "Service unavailable. Try again later"
                ),
                toastPlacement: .bottomCompact,
                canVerify: canVerify
            )
        case .none:
            break
        }

        if canVerify {
            return LoginPresentation(
                visualState: .ready,
                toastMessage: nil,
                canVerify: true
            )
        }
        if !verificationCode.isEmpty {
            return LoginPresentation(
                visualState: .credentialEntered,
                toastMessage: nil,
                canVerify: false
            )
        }
        if challengeIsActive {
            return LoginPresentation(
                visualState: .codeSent,
                toastMessage: nil,
                canVerify: false
            )
        }
        if !phone.filter(\.isNumber).isEmpty {
            return LoginPresentation(
                visualState: .phoneEntered,
                toastMessage: nil,
                canVerify: false
            )
        }
        return LoginPresentation(
            visualState: .initial,
            toastMessage: nil,
            canVerify: false
        )
    }

    static func retryDuration(
        seconds: Int,
        language: TxChatLanguage
    ) -> String {
        let value = max(0, seconds)
        if value >= 3_600 {
            let hours = value / 3_600
            let minutes = (value % 3_600) / 60
            return language.select(
                "\(hours) 小时 \(twoDigit(minutes)) 分",
                "\(hours)h \(twoDigit(minutes))m"
            )
        }
        if value >= 60 {
            let minutes = value / 60
            let seconds = value % 60
            return language.select(
                "\(minutes) 分 \(twoDigit(seconds)) 秒",
                "\(minutes)m \(twoDigit(seconds))s"
            )
        }
        return language.select("\(value) 秒", "\(value)s")
    }

    private static func twoDigit(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private static func smsPillWidth(
        for feedback: LoginFeedback,
        language: TxChatLanguage
    ) -> CGFloat? {
        switch (feedback, language) {
        case (.verificationIncorrect, .simplifiedChinese):
            316
        case (.challengeExpired, .simplifiedChinese):
            286
        case (.challengeExhausted, .simplifiedChinese):
            330
        case (.verificationRetryLimited, .simplifiedChinese):
            286
        case (.verificationLocked, .simplifiedChinese):
            420
        case (.sendCooldown, .simplifiedChinese):
            316
        case (.sendQuotaLimited, .simplifiedChinese):
            380
        case (.sendUnavailable, .simplifiedChinese):
            330
        case (.verificationIncorrect, .english):
            420
        case (.challengeExpired, .english):
            430
        case (.challengeExhausted, .english):
            485
        case (.verificationRetryLimited, .english):
            360
        case (.verificationLocked, .english):
            485
        case (.sendCooldown, .english):
            360
        case (.sendQuotaLimited, .english):
            485
        case (.sendUnavailable, .english):
            375
        default:
            nil
        }
    }

    static func onboarding(
        step: ProductOnboardingStep,
        shortcut: ProductShortcut,
        permissions: ProductPermissionSnapshot,
        language: TxChatLanguage = .productDefault
    ) -> OnboardingPresentation {
        let steps: [ProductOnboardingStep] = [
            .microphone,
            .accessibility,
            .voiceTest,
            .getStarted,
        ]
        let labels: [String] = [
            language.select("麦克风", "Microphone"),
            language.select("辅助功能", "Accessibility"),
            language.select("语音测试", "Voice Test"),
            language.select("开始使用", "Get Started"),
        ]
        let effectiveStep = steps.contains(step) ? step : .microphone
        let currentIndex = steps.firstIndex(of: effectiveStep) ?? 0
        let spine = labels.enumerated().map { index, label in
            let state: OnboardingSpineState
            if effectiveStep == .getStarted || index < currentIndex {
                state = .complete
            } else if index == currentIndex {
                state = .current
            } else {
                state = .upcoming
            }
            return OnboardingSpineItem(title: label, state: state)
        }

        switch effectiveStep {
        case .microphone:
            return OnboardingPresentation(
                step: effectiveStep,
                status: language.select(
                    "设置 1 / 4 · 麦克风",
                    "Setup 1 / 4 · Microphone"
                ),
                title: language.select(
                    "允许使用麦克风",
                    "Allow Microphone Access"
                ),
                detail: language.select(
                    "TxChat 需要使用麦克风来收听语音，请在系统弹窗中点击\"允许\"。",
                    "TxChat needs microphone access to listen to your voice. Please click \"Allow\" in the system dialog."
                ),
                cardTitle: language.select("麦克风权限", "Microphone Permission"),
                cardDetail: permissions.microphone == .ready
                    ? language.select(
                        "已授权 · 仅在主动听写时使用",
                        "Authorized · Used only during dictation"
                    )
                    : language.select(
                        "未授权 · 点击进入系统设置",
                        "Not authorized · Click to open System Settings"
                    ),
                primaryAction: language.select("打开系统设置", "Open Settings"),
                footnote: language.select(
                    "权限可随时在系统设置中关闭",
                    "Permissions can be revoked in System Settings anytime"
                ),
                actionKind: .request(.microphone),
                spine: spine
            )
        case .accessibility:
            return OnboardingPresentation(
                step: effectiveStep,
                status: language.select(
                    "设置 2 / 4 · 辅助功能",
                    "Setup 2 / 4 · Accessibility"
                ),
                title: language.select(
                    "允许写入当前光标",
                    "Allow Writing at Cursor"
                ),
                detail: language.select(
                    "TxChat 需要辅助功能权限，才能把识别结果写入正确位置。",
                    "TxChat needs Accessibility permission to insert recognized text at the correct position."
                ),
                cardTitle: language.select(
                    "辅助功能权限",
                    "Accessibility Permission"
                ),
                cardDetail: permissions.accessibility == .ready
                    ? language.select(
                        "已授权 · 仅用于写入识别结果",
                        "Authorized · Only used for inserting text"
                    )
                    : language.select(
                        "未授权 · 仅用于写入识别结果",
                        "Not authorized · Only used for inserting text"
                    ),
                primaryAction: language.select("打开系统设置", "Open Settings"),
                footnote: language.select(
                    "不会读取屏幕内容，也不会记录键盘输入",
                    "Does not read screen content or record keystrokes"
                ),
                actionKind: .openSettings(.accessibility),
                spine: spine
            )
        case .voiceTest:
            return OnboardingPresentation(
                step: effectiveStep,
                status: language.select(
                    "设置 3 / 4 · 语音测试",
                    "Setup 3 / 4 · Voice Test"
                ),
                title: language.select(
                    "说一句，试试看",
                    "Try Speaking Now"
                ),
                detail: language.select(
                    "按一次 \(shortcut.displayName) 开始，再按一次结束，测试会通过悬浮窗反馈。",
                    "Press \(shortcut.displayName) once to start, press again to stop. Test results will be shown in the floating window."
                ),
                cardTitle: language.select(
                    "通过悬浮窗测试",
                    "Test via Floating Window"
                ),
                cardDetail: language.select(
                    "快捷键可在正式使用时变更",
                    "Shortcut can be changed later"
                ),
                primaryAction: language.select(
                    "跳过此步",
                    "Skip This Step"
                ),
                footnote: language.select(
                    "测试完成后即可开始使用 TxChat",
                    "You can start using TxChat after testing"
                ),
                actionKind: .skipVoiceTest,
                spine: spine
            )
        case .getStarted:
            return OnboardingPresentation(
                step: effectiveStep,
                status: language.select(
                    "设置 4 / 4 · 开始使用",
                    "Setup 4 / 4 · Get Started"
                ),
                title: language.select("一切就绪", "All Set"),
                detail: language.select(
                    "TxChat 已配置完成，可以开始使用了。",
                    "TxChat is configured and ready to use."
                ),
                cardTitle: language.select(
                    "TxChat 已准备好",
                    "TxChat Is Ready"
                ),
                cardDetail: language.select(
                    "更多内容进入状态中心查看",
                    "See more details in Status Center"
                ),
                primaryAction: language.select(
                    "进入状态中心",
                    "Status Center"
                ),
                footnote: language.select(
                    "之后可从菜单栏随时打开状态与设置",
                    "You can access status and settings from the menu bar anytime"
                ),
                actionKind: .completeOnboarding,
                spine: spine
            )
        case .cloudDisclosure, .microphoneCalibration:
            preconditionFailure("legacy onboarding states are normalized")
        }
    }

    static func sessionInterruption(
        _ interruption: ProductSessionInterruption,
        language: TxChatLanguage = .productDefault
    ) -> SessionInterruptionPresentation {
        switch interruption {
        case .expired:
            return SessionInterruptionPresentation(
                title: language.select("登录状态已过期", "Login session expired"),
                detail: language.select("重新登录后可继续使用", "Log in again to continue"),
                action: language.select("重新登录", "Log In Again")
            )
        case .replaced:
            return SessionInterruptionPresentation(
                title: language.select(
                    "账号已在其他设备登录",
                    "Account logged in on another device"
                ),
                detail: language.select("重新登录后可继续使用", "Log in again to continue"),
                action: language.select("重新登录", "Log In Again")
            )
        }
    }

    static func permissionRepair(
        permissions: ProductPermissionSnapshot,
        language: TxChatLanguage = .productDefault
    ) -> PermissionRepairPresentation? {
        if permissions.microphone != .ready {
            return PermissionRepairPresentation(
                permission: .microphone,
                title: language.select(
                    "麦克风权限已关闭",
                    "Microphone Access Is Off"
                ),
                detail: language.select(
                    "在系统设置中允许 TxChat 使用麦克风，才能继续听写。",
                    "Allow TxChat to use the microphone in System Settings to continue dictation."
                ),
                action: language.select("打开系统设置", "Open Settings")
            )
        }
        if permissions.accessibility != .ready ||
            permissions.hotkey != .ready
        {
            return PermissionRepairPresentation(
                permission: .accessibility,
                title: language.select("需要恢复辅助功能权限", "Accessibility Access Required"),
                detail: language.select(
                    "在系统设置中允许 TxChat 控制电脑，才能响应快捷键并写入文字。",
                    "Allow TxChat in System Settings so it can use the shortcut and insert text."
                ),
                action: language.select("打开系统设置", "Open Settings")
            )
        }
        return nil
    }

    static func menu(
        phase: ProductPhase,
        readyStatus: String,
        dictation: DictationState,
        language: TxChatLanguage = .productDefault
    ) -> ProductMenuPresentation {
        let status: String
        switch phase {
        case .launching:
            status = language.select("正在准备", "TxChat Is Starting")
        case .signedOut:
            status = language.select("未登录", "TxChat Needs Login")
        case .onboarding:
            status = language.select("TxChat 需要设置", "TxChat Needs Setup")
        case .ready:
            switch dictation {
            case .idle, .completed:
                status = readyStatus
            default:
                status = overlay(for: dictation, language: language).title
            }
        case .sessionInterruption:
            status = language.select("TxChat 需要登录", "TxChat Needs Login")
        case .setupUnavailable:
            status = language.select("TxChat 需要设置", "TxChat Needs Setup")
        }

        let statusDetail: String
        switch phase {
        case .ready:
            switch dictation {
            case .idle, .completed:
                statusDetail = language.select("可以开始听写", "Ready to start dictation")
            case .listening:
                statusDetail = language.select("正在识别语音", "Recognizing voice")
            default:
                statusDetail = overlay(for: dictation, language: language).detail
            }
        case .launching:
            statusDetail = language.select("正在准备本机体验", "Preparing TxChat")
        case .signedOut:
            statusDetail = language.select("打开 TxChat 完成登录", "Open TxChat to log in")
        case .onboarding:
            statusDetail = language.select("完成设置即可开始听写", "Complete setup to start dictation")
        case .sessionInterruption:
            statusDetail = language.select("打开 TxChat 重新登录", "Open TxChat to log in again")
        case .setupUnavailable:
            statusDetail = language.select("服务尚未配置", "Service Not Configured")
        }

        return ProductMenuPresentation(
            statusTitle: status,
            statusDetail: statusDetail,
            panelHeight: TxChatTheme.Layout.menuHeight,
            showsBrandMark: true,
            statusKind: {
                switch phase {
                case .onboarding, .ready:
                    return .success
                case .launching, .signedOut, .sessionInterruption,
                     .setupUnavailable:
                    return .attention
                }
            }()
        )
    }

    static func home(
        permissions: ProductPermissionSnapshot,
        dictation: DictationState,
        mode: DictationMode,
        shortcut: ProductShortcut = .defaultFn,
        microphoneDeviceName: String = "当前输入设备",
        language: TxChatLanguage = .productDefault
    ) -> HomePresentation {
        let shortcutName = shortcut.displayName
        let ready = permissions.allPrerequisitesReady
        return HomePresentation(
            status: homeStatus(
                permissions: permissions,
                dictation: dictation,
                language: language
            ),
            headline: ready
                ? language.select("随时说 直接写", "Speak Anytime, Write Directly")
                : language.select("还差一步 就能开始", "One more step to get started"),
            instruction: ready
                ? language.select(
                    "在任意输入框按下快捷键开始说话",
                    "Press the shortcut in any text field to start speaking"
                )
                : language.select(
                    "请完成以下授权设置，即可正常使用。",
                    "Please complete the following permissions to get started."
                ),
            shortcutDisplayName: shortcutName,
            microphoneDeviceName: microphoneDeviceName,
            items: [
                StatusSpineItem(
                    title: language.select("麦克风", "Microphone"),
                    state: permissions.microphone
                ),
                StatusSpineItem(
                    title: language.select("辅助功能", "Accessibility"),
                    state: permissions.accessibility
                ),
                StatusSpineItem(
                    title: language.select("快捷键", "Shortcut"),
                    state: permissions.hotkey
                ),
                StatusSpineItem(
                    title: language.select("语音测试", "Voice Test"),
                    state: permissions.voiceTest
                ),
            ],
            selectedMode: mode,
            modeSelectionEnabled: modeSelectionEnabled(for: dictation)
        )
    }

    private static func modeSelectionEnabled(
        for dictation: DictationState
    ) -> Bool {
        switch dictation {
        case .starting, .listening, .finalizing, .organizing, .inserting:
            return false
        case .unavailable, .idle, .resultFallback, .completed, .failed:
            return true
        }
    }

    static func overlay(
        for state: DictationState,
        shortcut: ProductShortcut = .defaultFn,
        usedVerbatimFallback: Bool = false,
        language: TxChatLanguage = .productDefault
    ) -> OverlayPresentation {
        switch state {
        case .unavailable:
            return OverlayPresentation(
                title: language.select("需要设置", "Setup Required"),
                detail: language.select("请先完成必要设置", "Complete setup first"),
                actionLabel: language.select("设置", "Setup"),
                visualState: .unavailable,
                claimsInsertionCompleted: false
            )
        case .idle:
            return OverlayPresentation(
                title: language.select("已就绪", "Ready"),
                detail: language.select(
                    "按一次 \(shortcut.displayName) 开始说话",
                    "Press \(shortcut.displayName) once to start"
                ),
                actionLabel: language.select("开始", "Start"),
                visualState: .completed,
                claimsInsertionCompleted: false
            )
        case .starting:
            return OverlayPresentation(
                title: language.select("正在连接", "Connecting"),
                detail: language.select(
                    "正在连接 TxChat 云服务",
                    "Connecting to TxChat cloud service"
                ),
                actionLabel: "",
                visualState: .starting,
                claimsInsertionCompleted: false,
                cancellationAccessibilityLabel: language.select(
                    "取消本次听写",
                    "Cancel this dictation"
                )
            )
        case .listening:
            return OverlayPresentation(
                title: language.select("正在聆听", "Listening"),
                detail: language.select(
                    "再按快捷键结束聆听",
                    "Press shortcut again to stop"
                ),
                actionLabel: "",
                visualState: .listening,
                claimsInsertionCompleted: false,
                cancellationAccessibilityLabel: language.select(
                    "取消本次听写",
                    "Cancel this dictation"
                )
            )
        case .finalizing:
            return OverlayPresentation(
                title: language.select("正在整理", "Formatting"),
                detail: language.select(
                    "正在优化断句与表达",
                    "Refining punctuation and phrasing"
                ),
                actionLabel: "",
                visualState: .finalizing,
                claimsInsertionCompleted: false,
                cancellationAccessibilityLabel: language.select(
                    "取消本次听写",
                    "Cancel this dictation"
                )
            )
        case .organizing:
            return OverlayPresentation(
                title: language.select("正在整理", "Formatting"),
                detail: language.select(
                    "正在优化断句与表达",
                    "Refining punctuation and phrasing"
                ),
                actionLabel: "",
                visualState: .organizing,
                claimsInsertionCompleted: false,
                cancellationAccessibilityLabel: language.select(
                    "取消本次听写",
                    "Cancel this dictation"
                )
            )
        case .inserting:
            return OverlayPresentation(
                title: language.select("正在写入", "Writing"),
                detail: language.select("正在写入原输入位置", "Writing to the original input position"),
                actionLabel: "",
                visualState: .inserting,
                claimsInsertionCompleted: false
            )
        case .resultFallback:
            return OverlayPresentation(
                title: language.select("需要处理", "Action Required"),
                detail: language.select("文字已保留，请查看兜底窗口", "Text retained — open the fallback window"),
                actionLabel: language.select("查看", "View"),
                visualState: .resultFallback,
                claimsInsertionCompleted: false
            )
        case .completed:
            return OverlayPresentation(
                title: language.select("已完成", "Done"),
                detail: usedVerbatimFallback
                    ? language.select("已使用逐字结果", "Verbatim result used")
                    : language.select(
                        "已写入 · 1.5 秒后收起",
                        "Written · Dismissing in 1.5s"
                    ),
                actionLabel: "",
                visualState: .completed,
                claimsInsertionCompleted: true
            )
        case .failed(.targetUnavailable):
            return OverlayPresentation(
                title: language.select("暂时不可用", "Temporarily Unavailable"),
                detail: language.select(
                    "请先点击可输入文字的位置",
                    "Click on a text input field first"
                ),
                actionLabel: "",
                visualState: .unavailable,
                claimsInsertionCompleted: false
            )
        case .failed(.microphoneCalibrationRequired):
            return OverlayPresentation(
                title: language.select("需要校准麦克风", "Microphone Setup Required"),
                detail: language.select("请打开 TxChat 完成近距离语音校准", "Open TxChat to complete microphone setup"),
                actionLabel: language.select("打开 TxChat", "Open TxChat"),
                visualState: .unavailable,
                claimsInsertionCompleted: false
            )
        case .failed(.inputDeviceChanged):
            return OverlayPresentation(
                title: language.select("输入设备已变化", "Input Device Changed"),
                detail: language.select("请打开 TxChat 检查麦克风", "Open TxChat to check the microphone"),
                actionLabel: language.select("打开 TxChat", "Open TxChat"),
                visualState: .unavailable,
                claimsInsertionCompleted: false
            )
        case .failed(.nearSpeechNotDetected):
            return OverlayPresentation(
                title: language.select("未检测到近距离语音", "No Clear Voice Detected"),
                detail: language.select("未检测到足够清晰的近距离语音", "Move closer to the microphone and try again"),
                actionLabel: language.select("重试", "Retry"),
                visualState: .failed,
                claimsInsertionCompleted: false
            )
        case .failed:
            return OverlayPresentation(
                title: language.select("暂时不可用", "Temporarily Unavailable"),
                detail: language.select("听写失败，请稍后重试", "Dictation failed — please try again"),
                actionLabel: "",
                visualState: .failed,
                claimsInsertionCompleted: false
            )
        }
    }

    static func cancellation(
        language: TxChatLanguage = .productDefault
    ) -> OverlayPresentation {
        OverlayPresentation(
            title: language.select("已取消", "Canceled"),
            detail: language.select(
                "未写入任何内容",
                "Nothing was written"
            ),
            actionLabel: "",
            visualState: .cancelled,
            claimsInsertionCompleted: false
        )
    }

    private static func homeStatus(
        permissions: ProductPermissionSnapshot,
        dictation: DictationState,
        language: TxChatLanguage
    ) -> String {
        guard permissions.allPrerequisitesReady else {
            return language.select("TxChat 需要设置", "TxChat Needs Setup")
        }
        if case .unavailable = dictation {
            return language.select("TxChat 需要设置", "TxChat Needs Setup")
        }
        return language.select("TxChat 已就绪", "TxChat Ready")
    }
}
