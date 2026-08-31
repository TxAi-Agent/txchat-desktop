import Combine
import Foundation

protocol ProductSessionManaging: Sendable {
    func install(_ session: AuthenticatedSession) async throws
    func restore() async throws -> AccountSummary?
    func logout() async throws
}

extension SessionManager: ProductSessionManaging {}

actor ProductReadyMicrophoneCalibrationService:
    MicrophoneCalibrationServing
{
    private let profile: TxChatDistanceGateProfile
    private var required = false

    init(deviceName: String = "测试麦克风") {
        let device = TxChatInputDeviceIdentity(
            uid: "product-ready-calibration",
            displayName: deviceName
        )
        profile = TxChatDistanceGateProfile(
            device: device,
            quietP95DBFS: -50,
            speechP20DBFS: -30,
            openThresholdDBFS: -34,
            holdThresholdDBFS: -36,
            createdAt: Date(timeIntervalSince1970: 100),
            algorithmVersion:
                TxChatDistanceGateProfile.currentAlgorithmVersion
        )
    }

    func status() async -> MicrophoneCalibrationPhase {
        required
            ? .required(deviceName: profile.device.displayName)
            : .ready(
                deviceName: profile.device.displayName,
                calibratedAt: profile.createdAt
            )
    }

    func calibrate(
        onProgress: @escaping @Sendable (
            MicrophoneCalibrationPhase
        ) async -> Void
    ) async throws -> TxChatDistanceGateProfile {
        required = false
        await onProgress(
            .ready(
                deviceName: profile.device.displayName,
                calibratedAt: profile.createdAt
            )
        )
        return profile
    }

    func invalidateCurrentProfile() async {
        required = true
    }
}

@MainActor
protocol ProductDictationControlling: AnyObject {
    var state: DictationState { get }
    var mode: DictationMode { get }
    var shortcut: ProductShortcut { get }
    var voiceTestResultText: String? { get }

    func toggle() async
    func toggleVoiceTest() async
    func clearVoiceTestResult()
    @discardableResult
    func retryInsertion() async -> Bool
    @discardableResult
    func cancel() async -> Bool
    func setMode(_ mode: DictationMode)
    func reloadPreferences()
    @discardableResult
    func updateShortcut(_ shortcut: ProductShortcut) -> ShortcutUpdateResult
}

extension ProductDictationControlling {
    func reloadPreferences() {}
}

@MainActor
final class ProductCoordinator: ObservableObject {
    @Published private(set) var phase: ProductPhase = .launching
    @Published var phone = "" {
        didSet {
            guard phone != oldValue else {
                return
            }
            invalidateSMSLoginState()
        }
    }
    @Published var verificationCode = "" {
        didSet {
            guard verificationCode != oldValue,
                  let rejectedCode = lastRejectedVerificationCode,
                  let candidate = try? SMSVerificationCode(verificationCode),
                  candidate != rejectedCode else {
                return
            }
            lastRejectedVerificationCode = nil
            switch loginFeedback {
            case .verificationInvalid, .verificationIncorrect:
                loginFeedback = .none
            default:
                break
            }
        }
    }
    @Published var termsAccepted = false
    @Published private(set) var account: AccountSummary?
    @Published private(set) var permissionSnapshot =
        ProductPermissionSnapshot(
            microphone: .needsSetup,
            accessibility: .needsSetup,
            hotkey: .needsSetup,
            voiceTest: .ready
        )
    @Published private(set) var microphoneCalibrationPhase:
        MicrophoneCalibrationPhase = .required(
            deviceName: "当前输入设备"
        )
    @Published private(set) var formMessage: String?
    @Published private(set) var isVerifyingSMSCode = false
    @Published private(set) var isRequestingSMSCode = false
    @Published private(set) var activeSMSChallenge: SMSChallenge?
    @Published private(set) var resendSecondsRemaining = 0
    @Published private(set) var verificationRetrySecondsRemaining = 0
    @Published private(set) var isSMSRequestLocked = false
    @Published private(set) var verificationCodeFocusGeneration = 0
    @Published private(set) var loginFeedback: LoginFeedback = .none
    @Published private(set) var isPermissionRepairPresented = false
    @Published private(set) var language: TxChatLanguage

    private let authentication: any AuthenticationServing
    private let session: any ProductSessionManaging
    private let permissions: any ProductPermissionServing
    private let microphoneCalibration: any MicrophoneCalibrationServing
    private let dictation: any ProductDictationControlling
    private let diagnosticLog: AuthenticationDiagnosticLogger
    private let diagnosticRecorder: any DiagnosticIncidentRecording
    private let allowsNewDictation: @MainActor () -> Bool
    private let now: @Sendable () -> Date
    private let loginSleep: @Sendable () async -> Void
    private let onboardingCompletionStore:
        any OnboardingCompletionStoring
    private var cloudDisclosureAccepted = false
    private var pendingSession: AuthenticatedSession?
    private var onboardingCompleted = false
    private var smsRequestAvailableAt: Date?
    private var smsRequestCountdownDisplayOffset = 0
    private var smsVerificationRetryAvailableAt: Date?
    private var smsVerificationLockedUntil: Date?
    private var lastRejectedVerificationCode: SMSVerificationCode?

    init(
        authentication: any AuthenticationServing,
        session: any ProductSessionManaging,
        permissions: any ProductPermissionServing,
        microphoneCalibration: any MicrophoneCalibrationServing =
            ProductReadyMicrophoneCalibrationService(),
        dictation: any ProductDictationControlling,
        diagnosticLog: AuthenticationDiagnosticLogger = .disabled,
        diagnosticRecorder: any DiagnosticIncidentRecording =
            DisabledDiagnosticIncidentRecorder.shared,
        onboardingCompletionStore: any OnboardingCompletionStoring =
            UserDefaultsOnboardingCompletionStore(),
        language: TxChatLanguage = .productDefault,
        allowsNewDictation: @escaping @MainActor () -> Bool = { true },
        now: @escaping @Sendable () -> Date = Date.init,
        loginSleep: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(for: .seconds(1))
        }
    ) {
        self.authentication = authentication
        self.session = session
        self.permissions = permissions
        self.microphoneCalibration = microphoneCalibration
        self.dictation = dictation
        self.diagnosticLog = diagnosticLog
        self.diagnosticRecorder = diagnosticRecorder
        self.onboardingCompletionStore = onboardingCompletionStore
        self.language = language
        self.allowsNewDictation = allowsNewDictation
        self.now = now
        self.loginSleep = loginSleep
    }

    var homePresentation: HomePresentation {
        ProductPresentation.home(
            permissions: permissionSnapshot,
            dictation: dictation.state,
            mode: dictation.mode,
            shortcut: dictation.shortcut,
            microphoneDeviceName: currentMicrophoneDeviceName,
            language: language
        )
    }

    var shortcutDisplayName: String {
        dictation.shortcut.displayName
    }

    var currentShortcut: ProductShortcut {
        dictation.shortcut
    }

    private var currentMicrophoneDeviceName: String {
        switch microphoneCalibrationPhase {
        case .required(let deviceName),
             .samplingQuiet(_, let deviceName),
             .samplingSpeech(_, let deviceName),
             .ready(let deviceName, _):
            return deviceName
        case .failed:
            return "当前输入设备"
        }
    }

    var voiceTestState: DictationState {
        dictation.state
    }

    var voiceTestResultText: String? {
        dictation.voiceTestResultText
    }

    var overlayPresentation: OverlayPresentation {
        ProductPresentation.overlay(
            for: dictation.state,
            shortcut: dictation.shortcut,
            language: language
        )
    }

    var permissionRepairPresentation: PermissionRepairPresentation? {
        ProductPresentation.permissionRepair(
            permissions: permissionSnapshot,
            language: language
        )
    }

    var loginPresentation: LoginPresentation {
        ProductPresentation.login(
            phone: phone,
            verificationCode: verificationCode,
            termsAccepted: termsAccepted,
            challengeIsActive:
                activeSMSChallenge?.isActive(at: now()) == true,
            feedback: loginFeedback,
            verificationCanRetry: verificationCanRetry,
            language: language
        )
    }

    func launch() async {
        guard phase == .launching else {
            return
        }
        phase = .launching
        formMessage = nil
        do {
            guard let restoredAccount = try await session.restore() else {
                dictation.reloadPreferences()
                resetSignedOut()
                return
            }
            dictation.reloadPreferences()
            account = restoredAccount
            cloudDisclosureAccepted = true
            permissionSnapshot = await permissions.snapshot()
            microphoneCalibrationPhase =
                await microphoneCalibration.status()
            onboardingCompleted = onboardingCompletionStore.isCompleted(
                for: restoredAccount
            )
            if !onboardingCompleted,
               permissionSnapshot.voiceTest == .ready {
                onboardingCompleted = onboardingCompletionStore
                    .markCompleted(for: restoredAccount)
            }
            advancePastPermissions()
        } catch {
            recordAuthenticationProtocolViolationIfNeeded(
                error,
                stage: .sessionRestore
            )
            recordLocalStateFailureIfNeeded(
                error,
                stage: .sessionRestore,
                code: .localStateReadFailed
            )
            resetSignedOut()
            formMessage = Self.safeMessage(for: error)
        }
    }

    func showSetupUnavailable() {
        phase = .setupUnavailable
        account = nil
        formMessage = nil
    }

    func verifySMSCode() async {
        guard !isVerifyingSMSCode else {
            return
        }
        refreshLoginTiming()
        guard !isSMSRequestLocked,
              verificationRetrySecondsRemaining == 0 else {
            return
        }
        guard termsAccepted else {
            loginFeedback = .termsRequired
            return
        }
        if let pendingSession {
            isVerifyingSMSCode = true
            defer { isVerifyingSMSCode = false }
            do {
                try await finishAuthenticationInstallation(pendingSession)
                loginFeedback = .none
            } catch {
                loginFeedback = .serviceUnavailable
            }
            return
        }
        guard let challenge = activeSMSChallenge else {
            loginFeedback = .challengeExpired
            return
        }
        guard challenge.isActive(at: now()) else {
            activeSMSChallenge = nil
            verificationCode = ""
            clearSMSVerificationRetry()
            lastRejectedVerificationCode = nil
            loginFeedback = .challengeExpired
            return
        }
        let submittedPhone: MainlandPhone
        let submittedCode: SMSVerificationCode
        do {
            submittedPhone = try MainlandPhone(phone)
            submittedCode = try SMSVerificationCode(verificationCode)
        } catch {
            loginFeedback = .verificationInvalid
            return
        }
        guard verificationCanRetry else {
            return
        }
        formMessage = nil
        loginFeedback = .none
        isVerifyingSMSCode = true
        defer { isVerifyingSMSCode = false }
        do {
            let authenticated = try await authentication.verifySMSChallenge(
                challenge: challenge,
                code: submittedCode
            )
            guard isCurrentSMSVerification(
                phone: submittedPhone,
                challenge: challenge
            ) else {
                return
            }
            let installedSession = Self.sessionForDisplay(
                authenticated,
                phone: submittedPhone
            )
            pendingSession = installedSession
            try await finishAuthenticationInstallation(installedSession)
        } catch {
            guard isCurrentSMSVerification(
                phone: submittedPhone,
                challenge: challenge
            ) else {
                return
            }
            recordAuthenticationProtocolViolationIfNeeded(
                error,
                stage: .sessionInstall
            )
            switch error as? AuthenticationServiceError {
            case .invalidVerificationCode,
                 .verificationCodeInvalidOrExpired:
                lastRejectedVerificationCode = submittedCode
                loginFeedback = .verificationInvalid
            case .verificationIncorrect(let attemptsRemaining):
                lastRejectedVerificationCode = submittedCode
                loginFeedback = .verificationIncorrect(
                    attemptsRemaining: attemptsRemaining
                )
            case .smsChallengeExpired:
                activeSMSChallenge = nil
                verificationCode = ""
                clearSMSVerificationRetry()
                lastRejectedVerificationCode = nil
                loginFeedback = .challengeExpired
            case .smsChallengeExhausted:
                activeSMSChallenge = nil
                verificationCode = ""
                clearSMSVerificationRetry()
                lastRejectedVerificationCode = nil
                loginFeedback = .challengeExhausted
            case .verificationRetryLimited(let retryAfterSeconds):
                setSMSVerificationRetry(seconds: retryAfterSeconds)
                loginFeedback = .verificationRetryLimited(
                    retryAfterSeconds: verificationRetrySecondsRemaining
                )
            case .verificationLocked(let retryAfterSeconds):
                setSMSVerificationLock(seconds: retryAfterSeconds)
                loginFeedback = .verificationLocked(
                    retryAfterSeconds: retryAfterSeconds
                )
            case .tooManyRequests(let retryAfterSeconds):
                setSMSVerificationLock(seconds: retryAfterSeconds)
                loginFeedback = .verificationLocked(
                    retryAfterSeconds: retryAfterSeconds
                )
            case .serviceUnavailable, nil:
                loginFeedback = .serviceUnavailable
            default:
                loginFeedback = .serviceUnavailable
            }
        }
    }

    func requestSMSCode() async {
        refreshLoginTiming()
        guard !isRequestingSMSCode, resendSecondsRemaining == 0,
              !isSMSRequestLocked else {
            return
        }
        formMessage = nil
        loginFeedback = .none
        let requestedPhone: MainlandPhone
        do {
            requestedPhone = try MainlandPhone(phone)
        } catch {
            loginFeedback = .invalidPhone
            return
        }

        isRequestingSMSCode = true
        activeSMSChallenge = nil
        verificationCode = ""
        clearSMSVerificationRetry()
        lastRejectedVerificationCode = nil
        defer { isRequestingSMSCode = false }
        do {
            let challenge = try await authentication.requestSMSChallenge(
                phone: requestedPhone
            )
            guard (try? MainlandPhone(phone))?.e164 == requestedPhone.e164 else {
                return
            }
            activeSMSChallenge = challenge
            smsRequestAvailableAt = challenge.resendAvailableAt
            smsRequestCountdownDisplayOffset = 1
            lastRejectedVerificationCode = nil
            refreshLoginTiming()
            verificationCodeFocusGeneration += 1
        } catch {
            guard (try? MainlandPhone(phone))?.e164 == requestedPhone.e164 else {
                return
            }
            recordAuthenticationProtocolViolationIfNeeded(
                error,
                stage: .sessionInstall
            )
            diagnosticLog.recordPresentedFailure(
                operation: .smsChallengeRequest,
                error: error
            )
            activeSMSChallenge = nil
            verificationCode = ""
            switch error as? AuthenticationServiceError {
            case .sendCooldown(let retryAfterSeconds):
                setSMSRequestCooldown(seconds: retryAfterSeconds)
                loginFeedback = .sendCooldown(
                    retryAfterSeconds: resendSecondsRemaining
                )
            case .sendQuotaLimited(let retryAfterSeconds):
                setSMSRequestCooldown(seconds: retryAfterSeconds)
                loginFeedback = .sendQuotaLimited(
                    retryAfterSeconds: resendSecondsRemaining
                )
            case .tooManyRequests(let retryAfterSeconds):
                setSMSRequestCooldown(seconds: retryAfterSeconds)
                loginFeedback = .sendQuotaLimited(
                    retryAfterSeconds: resendSecondsRemaining
                )
            case .serviceUnavailable(let retryAfterSeconds):
                if let retryAfterSeconds {
                    setSMSRequestCooldown(seconds: retryAfterSeconds)
                }
                loginFeedback = .sendUnavailable
            case .invalidPhone:
                loginFeedback = .invalidPhone
            default:
                loginFeedback = .sendUnavailable
            }
        }
    }

    func refreshLoginTiming() {
        let currentDate = now()
        if let smsVerificationLockedUntil {
            let remaining = smsVerificationLockedUntil
                .timeIntervalSince(currentDate)
            if remaining > 0 {
                isSMSRequestLocked = true
                if case .verificationLocked = loginFeedback {
                    loginFeedback = .verificationLocked(
                        retryAfterSeconds: Int(ceil(remaining))
                    )
                }
            } else {
                self.smsVerificationLockedUntil = nil
                isSMSRequestLocked = false
                if case .verificationLocked = loginFeedback {
                    loginFeedback = .none
                }
            }
        } else {
            isSMSRequestLocked = false
        }
        if let smsVerificationRetryAvailableAt {
            let remaining = smsVerificationRetryAvailableAt
                .timeIntervalSince(currentDate)
            if remaining > 0 {
                verificationRetrySecondsRemaining = Int(ceil(remaining))
                if case .verificationRetryLimited = loginFeedback {
                    loginFeedback = .verificationRetryLimited(
                        retryAfterSeconds:
                            verificationRetrySecondsRemaining
                    )
                }
            } else {
                clearSMSVerificationRetry()
                if case .verificationRetryLimited = loginFeedback {
                    loginFeedback = .none
                }
            }
        } else {
            verificationRetrySecondsRemaining = 0
        }
        if let challenge = activeSMSChallenge,
           !challenge.isActive(at: currentDate) {
            activeSMSChallenge = nil
            verificationCode = ""
            clearSMSVerificationRetry()
            lastRejectedVerificationCode = nil
            if !isSMSRequestLocked {
                loginFeedback = .challengeExpired
            }
        }
        guard let smsRequestAvailableAt else {
            smsRequestCountdownDisplayOffset = 0
            resendSecondsRemaining = 0
            return
        }
        let remaining = smsRequestAvailableAt.timeIntervalSince(currentDate)
        if remaining <= 0 {
            self.smsRequestAvailableAt = nil
            smsRequestCountdownDisplayOffset = 0
            resendSecondsRemaining = 0
            switch loginFeedback {
            case .sendCooldown, .sendQuotaLimited:
                loginFeedback = .none
            default:
                break
            }
        } else {
            resendSecondsRemaining = max(
                1,
                Int(ceil(remaining)) - smsRequestCountdownDisplayOffset
            )
            switch loginFeedback {
            case .sendCooldown:
                loginFeedback = .sendCooldown(
                    retryAfterSeconds: resendSecondsRemaining
                )
            case .sendQuotaLimited:
                loginFeedback = .sendQuotaLimited(
                    retryAfterSeconds: resendSecondsRemaining
                )
            default:
                break
            }
        }
    }

    func runLoginCountdown() async {
        while !Task.isCancelled,
              resendSecondsRemaining > 0 ||
              verificationRetrySecondsRemaining > 0 ||
              isSMSRequestLocked {
            await loginSleep()
            refreshLoginTiming()
        }
    }

    func acceptCloudDisclosure() async {
        guard
            phase == .onboarding(.cloudDisclosure),
            let pendingSession
        else {
            return
        }
        formMessage = nil
        do {
            try await installSession(pendingSession)
        } catch {
            formMessage = Self.safeMessage(for: error)
            return
        }
        self.pendingSession = nil
        cloudDisclosureAccepted = true
        permissionSnapshot = await permissions.snapshot()
        microphoneCalibrationPhase =
            await microphoneCalibration.status()
        advancePastPermissions()
    }

    func requestMicrophone() async {
        guard cloudDisclosureAccepted else {
            return
        }
        permissionSnapshot = await permissions.requestMicrophone()
        if permissionSnapshot.microphone == .ready {
            microphoneCalibrationPhase =
                await microphoneCalibration.status()
        }
        advancePastPermissions()
    }

    func calibrateMicrophone() async {
        guard cloudDisclosureAccepted,
              permissionSnapshot.microphone == .ready else {
            return
        }
        formMessage = nil
        do {
            _ = try await microphoneCalibration.calibrate {
                [weak self] phase in
                await self?.receiveMicrophoneCalibrationPhase(phase)
            }
            microphoneCalibrationPhase =
                await microphoneCalibration.status()
            advancePastPermissions()
        } catch let failure as MicrophoneCalibrationFailure {
            microphoneCalibrationPhase = .failed(failure)
            formMessage = Self.calibrationMessage(for: failure)
        } catch {
            formMessage = "麦克风校准未完成，请重试"
        }
    }

    func recalibrateMicrophone() async {
        guard phase == .ready else {
            return
        }
        await microphoneCalibration.invalidateCurrentProfile()
        microphoneCalibrationPhase = await microphoneCalibration.status()
        advancePastPermissions()
    }

    func requestAccessibility() async {
        guard cloudDisclosureAccepted else {
            return
        }
        permissionSnapshot = await permissions.requestAccessibility()
        advancePastPermissions()
    }

    func openSystemSettings(for permission: ProductPermissionKind) async {
        await permissions.openSystemSettings(for: permission)
    }

    func repairPermission(_ permission: ProductPermissionKind) async {
        guard phase == .ready else {
            return
        }
        switch permission {
        case .microphone:
            await requestMicrophone()
        case .accessibility:
            await requestAccessibility()
        }

        let stillMissing: Bool
        switch permission {
        case .microphone:
            stillMissing = permissionSnapshot.microphone != .ready
        case .accessibility:
            stillMissing = permissionSnapshot.accessibility != .ready ||
                permissionSnapshot.hotkey != .ready
        }
        if stillMissing {
            await openSystemSettings(for: permission)
        }
        if permissionRepairPresentation == nil {
            dismissPermissionRepair()
        }
    }

    func performOnboardingAction(
        _ action: OnboardingActionKind
    ) async {
        switch action {
        case .acceptCloudDisclosure:
            await acceptCloudDisclosure()
        case .request(.microphone):
            await requestMicrophone()
            if permissionSnapshot.microphone != .ready {
                await openSystemSettings(for: .microphone)
            }
        case .request(.accessibility):
            await requestAccessibility()
        case .openSettings(let permission):
            await openSystemSettings(for: permission)
        case .calibrateMicrophone:
            await calibrateMicrophone()
        case .voiceTest:
            await toggleDictation()
        case .skipVoiceTest:
            await skipVoiceTest()
        case .completeOnboarding:
            completeOnboarding()
        }
    }

    func refreshPermissions() async {
        permissionSnapshot = await permissions.snapshot()
        if permissionSnapshot.microphone == .ready {
            microphoneCalibrationPhase =
                await microphoneCalibration.status()
        }
        if cloudDisclosureAccepted {
            advancePastPermissions()
        }
        if phase == .ready,
           permissionSnapshot.microphone != .ready {
            switch dictation.state {
            case .starting, .listening, .finalizing, .organizing,
                 .inserting, .resultFallback:
                await dictation.cancel()
                objectWillChange.send()
            case .unavailable, .idle, .completed, .failed:
                break
            }
        }
        if phase == .ready,
           permissionRepairPresentation != nil {
            isPermissionRepairPresented = true
        } else if permissionRepairPresentation == nil {
            isPermissionRepairPresented = false
        }
    }

    func presentPermissionRepair() {
        guard phase == .ready,
              permissionRepairPresentation != nil
        else {
            return
        }
        isPermissionRepairPresented = true
    }

    func dismissPermissionRepair() {
        isPermissionRepairPresented = false
    }

    func completeVoiceTest() async {
        await finishVoiceTest()
    }

    func skipVoiceTest() async {
        await finishVoiceTest()
    }

    func reconcileVoiceTestCompletion() async {
        // Completion is intentionally presented on step 3. The user advances
        // only through the explicit Next action, or skips before testing.
    }

    private func finishVoiceTest() async {
        guard phase == .onboarding(.voiceTest) else {
            return
        }
        switch dictation.state {
        case .starting, .listening, .finalizing, .organizing, .inserting,
             .resultFallback:
            await dictation.cancel()
            objectWillChange.send()
        case .unavailable, .idle, .completed, .failed:
            break
        }
        formMessage = nil
        permissionSnapshot = await permissions.completeVoiceTest()
        guard permissionSnapshot.voiceTest == .ready else {
            formMessage = language.select(
                "无法保存语音测试设置，请稍后重试",
                "We couldn't save the voice test. Please try again."
            )
            return
        }
        dictation.clearVoiceTestResult()
        objectWillChange.send()
        phase = .onboarding(.getStarted)
    }

    private static func sessionForDisplay(
        _ session: AuthenticatedSession,
        phone: MainlandPhone
    ) -> AuthenticatedSession {
        AuthenticatedSession(
            account: AccountSummary(
                maskedPhone: phone.maskedDisplayPhone,
                loggedIn: session.account.loggedIn
            ),
            accessToken: session.accessToken,
            accessExpiresInSeconds: session.accessExpiresInSeconds,
            refreshToken: session.refreshToken,
            refreshExpiresInSeconds: session.refreshExpiresInSeconds,
            deviceID: session.deviceID,
            sessionID: session.sessionID
        )
    }

    func completeOnboarding() {
        guard phase == .onboarding(.getStarted),
              let account else {
            return
        }
        guard onboardingCompletionStore.markCompleted(for: account) else {
            formMessage = language.select(
                "无法保存引导完成状态，请稍后重试",
                "We couldn't save onboarding completion. Please try again."
            )
            return
        }
        onboardingCompleted = true
        advancePastPermissions()
    }

    func setMode(_ mode: DictationMode) {
        guard phase == .ready else {
            return
        }
        dictation.setMode(mode)
        objectWillChange.send()
    }

    func toggleLanguage() {
        language = language == .simplifiedChinese
            ? .english
            : .simplifiedChinese
    }

    @discardableResult
    func updateShortcut(
        _ shortcut: ProductShortcut
    ) -> ShortcutUpdateResult {
        guard phase == .ready else {
            return .failed(.unavailable)
        }
        let result = dictation.updateShortcut(shortcut)
        objectWillChange.send()
        return result
    }

    func toggleDictation() async {
        guard canToggleDictationUnderUpdatePolicy else { return }
        if phase == .onboarding(.voiceTest) {
            permissionSnapshot = await permissions.snapshot()
            guard canToggleDictationUnderUpdatePolicy else { return }
            guard permissionSnapshot.microphone == .ready,
                  permissionSnapshot.accessibility == .ready,
                  permissionSnapshot.hotkey == .ready else {
                advancePastPermissions()
                return
            }
            await dictation.toggleVoiceTest()
            objectWillChange.send()
            return
        }
        guard phase == .ready else {
            return
        }
        await refreshPermissions()
        guard canToggleDictationUnderUpdatePolicy else { return }
        guard permissionSnapshot.microphone == .ready,
              permissionSnapshot.accessibility == .ready,
              permissionSnapshot.hotkey == .ready else {
            return
        }
        await dictation.toggle()
        objectWillChange.send()
    }

    private var canToggleDictationUnderUpdatePolicy: Bool {
        if allowsNewDictation() { return true }
        if case .listening = dictation.state { return true }
        return false
    }

    func reconcileMicrophoneCalibrationRequirement() async {
        guard phase == .ready else {
            return
        }
        return
    }

    @discardableResult
    func retryInsertion() async -> Bool {
        guard phase == .ready else {
            return false
        }
        let succeeded = await dictation.retryInsertion()
        objectWillChange.send()
        return succeeded
    }

    func logout() async {
        await dictation.cancel()
        do {
            try await session.logout()
            resetSignedOut()
        } catch {
            recordLocalStateFailureIfNeeded(
                error,
                stage: .sessionDelete,
                code: .localStateDeleteFailed
            )
            formMessage = "无法安全清除本机会话，请稍后重试"
        }
    }

    func sessionInvalidated(_ error: AuthenticationServiceError) async {
        await dictation.cancel()
        do {
            try await session.logout()
        } catch {
            recordLocalStateFailureIfNeeded(
                error,
                stage: .sessionDelete,
                code: .localStateDeleteFailed
            )
        }
        resetSignedOut()
        if case .sessionReplaced = error {
            phase = .sessionInterruption(.replaced)
        } else {
            phase = .sessionInterruption(.expired)
        }
    }

    func beginReauthentication() {
        guard case .sessionInterruption = phase else {
            return
        }
        phase = .signedOut
        formMessage = nil
    }

    private func advancePastPermissions() {
        guard cloudDisclosureAccepted else {
            phase = .onboarding(.cloudDisclosure)
            return
        }
        // A restored, completed onboarding session stays on the product home
        // while macOS permissions are repaired from the dedicated sheet.
        if onboardingCompleted {
            phase = .ready
            return
        }
        if permissionSnapshot.microphone != .ready {
            phase = .onboarding(.microphone)
        } else if permissionSnapshot.accessibility != .ready ||
                    permissionSnapshot.hotkey != .ready
        {
            phase = .onboarding(.accessibility)
        } else if permissionSnapshot.voiceTest != .ready
        {
            phase = .onboarding(.voiceTest)
        } else if onboardingCompleted {
            phase = .ready
        } else {
            phase = .onboarding(.getStarted)
        }
    }

    private var microphoneCalibrationIsReady: Bool {
        if case .ready = microphoneCalibrationPhase {
            return true
        }
        return false
    }

    private func receiveMicrophoneCalibrationPhase(
        _ phase: MicrophoneCalibrationPhase
    ) {
        microphoneCalibrationPhase = phase
    }

    private func setSMSRequestCooldown(seconds: Int) {
        guard seconds > 0 else {
            smsRequestAvailableAt = nil
            smsRequestCountdownDisplayOffset = 0
            resendSecondsRemaining = 0
            return
        }
        smsRequestCountdownDisplayOffset = 0
        smsRequestAvailableAt = now().addingTimeInterval(
            TimeInterval(seconds)
        )
        refreshLoginTiming()
    }

    private func setSMSVerificationLock(seconds: Int) {
        guard seconds > 0 else {
            smsVerificationLockedUntil = nil
            isSMSRequestLocked = false
            return
        }
        smsVerificationLockedUntil = now().addingTimeInterval(
            TimeInterval(seconds)
        )
        refreshLoginTiming()
    }

    private func setSMSVerificationRetry(seconds: Int) {
        guard seconds > 0 else {
            clearSMSVerificationRetry()
            return
        }
        smsVerificationRetryAvailableAt = now().addingTimeInterval(
            TimeInterval(seconds)
        )
        refreshLoginTiming()
    }

    private func clearSMSVerificationRetry() {
        smsVerificationRetryAvailableAt = nil
        verificationRetrySecondsRemaining = 0
    }

    private var verificationCanRetry: Bool {
        guard !isSMSRequestLocked,
              verificationRetrySecondsRemaining == 0,
              let candidate = try? SMSVerificationCode(verificationCode)
        else {
            return false
        }
        return candidate != lastRejectedVerificationCode
    }

    private func isCurrentSMSVerification(
        phone submittedPhone: MainlandPhone,
        challenge submittedChallenge: SMSChallenge
    ) -> Bool {
        (try? MainlandPhone(phone)) == submittedPhone &&
            activeSMSChallenge == submittedChallenge
    }

    private func finishAuthenticationInstallation(
        _ installedSession: AuthenticatedSession
    ) async throws {
        try await installSession(installedSession)
        dictation.reloadPreferences()
        verificationCode = ""
        activeSMSChallenge = nil
        smsRequestAvailableAt = nil
        smsRequestCountdownDisplayOffset = 0
        clearSMSVerificationRetry()
        smsVerificationLockedUntil = nil
        resendSecondsRemaining = 0
        isSMSRequestLocked = false
        lastRejectedVerificationCode = nil
        pendingSession = nil
        account = installedSession.account
        cloudDisclosureAccepted = true
        permissionSnapshot = await permissions.snapshot()
        microphoneCalibrationPhase = await microphoneCalibration.status()
        onboardingCompleted = onboardingCompletionStore.isCompleted(
            for: installedSession.account
        )
        advancePastPermissions()
    }

    private func installSession(
        _ installedSession: AuthenticatedSession
    ) async throws {
        do {
            try await session.install(installedSession)
        } catch {
            recordLocalStateFailureIfNeeded(
                error,
                stage: .sessionInstall,
                code: .localStateWriteFailed
            )
            throw error
        }
    }

    private func recordLocalStateFailureIfNeeded(
        _ error: Error,
        stage: DiagnosticStage,
        code: DiagnosticCode
    ) {
        guard !(error is AuthenticationServiceError) else { return }
        diagnosticRecorder.record(
            DiagnosticIncident(
                category: .authentication,
                taskId: nil,
                stage: stage,
                code: code
            )
        )
    }

    private func recordAuthenticationProtocolViolationIfNeeded(
        _ error: Error,
        stage: DiagnosticStage
    ) {
        guard error as? AuthenticationServiceError == .protocolViolation else {
            return
        }
        diagnosticRecorder.record(
            DiagnosticIncident(
                category: .authentication,
                taskId: nil,
                stage: stage,
                code: .protocolViolation
            )
        )
    }

    private func invalidateSMSLoginState() {
        activeSMSChallenge = nil
        smsRequestAvailableAt = nil
        smsRequestCountdownDisplayOffset = 0
        clearSMSVerificationRetry()
        smsVerificationLockedUntil = nil
        resendSecondsRemaining = 0
        isSMSRequestLocked = false
        verificationCode = ""
        lastRejectedVerificationCode = nil
        loginFeedback = .none
        pendingSession = nil
    }

    private func resetSignedOut() {
        phase = .signedOut
        account = nil
        invalidateSMSLoginState()
        cloudDisclosureAccepted = false
        pendingSession = nil
        onboardingCompleted = false
        isPermissionRepairPresented = false
    }

    private static func safeMessage(for error: Error) -> String {
        guard let error = error as? AuthenticationServiceError else {
            return "服务暂时不可用，请稍后重试"
        }
        switch error {
        case .invalidPhone:
            return "请输入正确的中国大陆手机号"
        case .invalidEnrollmentCredential:
            return "服务暂时不可用，请稍后重试"
        case .invalidVerificationCode,
             .verificationCodeInvalidOrExpired:
            return "验证码无效或已过期"
        case .verificationIncorrect(let attemptsRemaining):
            return "验证码错误，还可尝试 \(attemptsRemaining) 次"
        case .smsChallengeExpired:
            return "短信验证码已过期"
        case .smsChallengeExhausted:
            return "验证码错误次数已用完，请重新获取"
        case .verificationRetryLimited(let seconds):
            return "验证过于频繁，请在 \(seconds) 秒后重试"
        case .verificationLocked(let seconds):
            return "验证码错误次数过多，请在 \(seconds) 秒后重试"
        case .sendCooldown(let seconds),
             .sendQuotaLimited(let seconds):
            return "发送过于频繁，请在 \(seconds) 秒后重试"
        case .phoneNotAllowed:
            return "此手机号无法使用"
        case .tooManyRequests(let seconds):
            return "操作过于频繁，请在 \(seconds) 秒后重试"
        case .serviceUnavailable:
            return "服务暂时不可用，请稍后重试"
        case .authenticationRequired:
            return "登录已失效，请重新登录"
        case .sessionReplaced:
            return "账号已在其他设备登录，请重新登录"
        case .sessionReplayed:
            return "登录状态异常，请重新登录"
        case .accountDisabled:
            return "账号暂时不可用"
        case .protocolViolation:
            return "服务响应异常，请稍后重试"
        }
    }

    private static func calibrationMessage(
        for failure: MicrophoneCalibrationFailure
    ) -> String {
        switch failure {
        case .insufficientSignalToNoise:
            return "环境声音较大，请靠近麦克风或换到更安静的位置"
        case .insufficientSpeech:
            return "没有检测到足够的朗读声音，请用正常音量重试"
        case .inputDeviceChanged:
            return "输入设备已变化，请确认设备后重新校准"
        case .inputDeviceUnavailable:
            return "当前输入设备不可用，请检查系统声音设置"
        case .invalidPCM:
            return "麦克风音频格式不可用，请重新选择输入设备"
        case .alreadyRunning:
            return "麦克风校准正在进行"
        }
    }
}
