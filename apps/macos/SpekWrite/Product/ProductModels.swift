import CoreGraphics

enum ProductOnboardingStep: Equatable, Sendable {
    // Legacy states remain decodable for in-flight local state, but new flows
    // begin at microphone and never present these two screens.
    case cloudDisclosure
    case microphone
    case microphoneCalibration
    case accessibility
    case voiceTest
    case getStarted
}

enum ProductSessionInterruption: Equatable, Sendable {
    case expired
    case replaced
}

enum ProductPhase: Equatable, Sendable {
    case launching
    case signedOut
    case onboarding(ProductOnboardingStep)
    case ready
    case sessionInterruption(ProductSessionInterruption)
    case setupUnavailable
}

enum ProductSetupState: Equatable, Sendable {
    case ready
    case needsSetup
}

enum LoginVisualState: Equatable, Sendable {
    case initial
    case phoneEntered
    case codeSent
    case credentialEntered
    case ready
    case invalidCredential
    case challengeExpired
    case challengeExhausted
    case verificationRetryLimited
    case sendCooldown
    case sendQuotaLimited
    case verificationLocked
    case sendUnavailable
    case serviceUnavailable
}

enum LoginFeedback: Equatable, Sendable {
    case none
    case termsRequired
    case invalidPhone
    case verificationInvalid
    case verificationIncorrect(attemptsRemaining: Int)
    case challengeExpired
    case challengeExhausted
    case verificationRetryLimited(retryAfterSeconds: Int)
    case verificationLocked(retryAfterSeconds: Int)
    case sendCooldown(retryAfterSeconds: Int)
    case sendQuotaLimited(retryAfterSeconds: Int)
    case sendUnavailable
    case serviceUnavailable
}

struct LoginPresentation: Equatable, Sendable {
    let visualState: LoginVisualState
    let toastMessage: String?
    let toastPlacement: LoginToastPlacement?
    let smsPillWidth: CGFloat?
    let canVerify: Bool

    init(
        visualState: LoginVisualState,
        toastMessage: String?,
        toastPlacement: LoginToastPlacement? = nil,
        smsPillWidth: CGFloat? = nil,
        canVerify: Bool
    ) {
        self.visualState = visualState
        self.toastMessage = toastMessage
        self.toastPlacement = toastPlacement
        self.smsPillWidth = smsPillWidth
        self.canVerify = canVerify
    }
}

enum LoginToastPlacement: Equatable, Sendable {
    case topSMS
    case bottomCompact
}

enum OnboardingSpineState: Equatable, Sendable {
    case complete
    case current
    case upcoming
}

struct OnboardingSpineItem: Equatable, Sendable {
    let title: String
    let state: OnboardingSpineState
}

enum OnboardingActionKind: Equatable, Sendable {
    case acceptCloudDisclosure
    case request(ProductPermissionKind)
    case openSettings(ProductPermissionKind)
    case calibrateMicrophone
    case voiceTest
    case skipVoiceTest
    case completeOnboarding
}

struct OnboardingPresentation: Equatable, Sendable {
    let step: ProductOnboardingStep
    let status: String
    let title: String
    let detail: String
    let cardTitle: String
    let cardDetail: String
    let primaryAction: String
    let footnote: String
    let actionKind: OnboardingActionKind
    let spine: [OnboardingSpineItem]
}

struct SessionInterruptionPresentation: Equatable, Sendable {
    let title: String
    let detail: String
    let action: String
}

struct PermissionRepairPresentation: Equatable, Sendable {
    let permission: ProductPermissionKind
    let title: String
    let detail: String
    let action: String
}

struct ProductPermissionSnapshot: Equatable, Sendable {
    let microphone: ProductSetupState
    let accessibility: ProductSetupState
    let hotkey: ProductSetupState
    let voiceTest: ProductSetupState

    static let allReady = ProductPermissionSnapshot(
        microphone: .ready,
        accessibility: .ready,
        hotkey: .ready,
        voiceTest: .ready
    )

    var allPrerequisitesReady: Bool {
        microphone == .ready &&
            accessibility == .ready &&
            hotkey == .ready &&
            voiceTest == .ready
    }
}

struct StatusSpineItem: Equatable, Sendable {
    let title: String
    let state: ProductSetupState
}

struct HomePresentation: Equatable, Sendable {
    let status: String
    let headline: String
    let instruction: String
    let shortcutDisplayName: String
    let microphoneDeviceName: String
    let items: [StatusSpineItem]
    let selectedMode: DictationMode
    let modeSelectionEnabled: Bool
}

enum OverlayVisualState: Equatable, Sendable {
    case starting
    case listening
    case finalizing
    case organizing
    case inserting
    case cancelled
    case completed
    case resultFallback
    case failed
    case unavailable
}

struct OverlayPresentation: Equatable, Sendable {
    let title: String
    let detail: String
    let actionLabel: String
    let visualState: OverlayVisualState
    let claimsInsertionCompleted: Bool
    let cancellationAccessibilityLabel: String?

    init(
        title: String,
        detail: String,
        actionLabel: String,
        visualState: OverlayVisualState,
        claimsInsertionCompleted: Bool,
        cancellationAccessibilityLabel: String? = nil
    ) {
        self.title = title
        self.detail = detail
        self.actionLabel = actionLabel
        self.visualState = visualState
        self.claimsInsertionCompleted = claimsInsertionCompleted
        self.cancellationAccessibilityLabel =
            cancellationAccessibilityLabel
    }
}

enum ProductMenuStatusKind: Equatable, Sendable {
    case success
    case attention
}

struct ProductMenuPresentation: Equatable, Sendable {
    let statusTitle: String
    let statusDetail: String
    let panelHeight: CGFloat
    let showsBrandMark: Bool
    let statusKind: ProductMenuStatusKind
}
