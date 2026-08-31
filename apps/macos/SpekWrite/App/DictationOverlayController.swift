import AppKit
import SwiftUI

private final class TxChatNonactivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class TxChatHUDModel: ObservableObject {
    @Published var presentation: OverlayPresentation
    @Published var audioLevel: Double?

    init(presentation: OverlayPresentation, audioLevel: Double?) {
        self.presentation = presentation
        self.audioLevel = audioLevel
    }
}

private struct TxChatHUDContainerView: View {
    @ObservedObject var model: TxChatHUDModel
    let cancelAction: () -> Void

    var body: some View {
        DictationOverlayView(
            presentation: model.presentation,
            audioLevel: model.audioLevel,
            cancelAction: model.presentation.cancellationAccessibilityLabel == nil
                ? nil
                : cancelAction
        )
    }
}

@MainActor
protocol DictationOverlayPresenting: AnyObject {
    func setCancellationHandler(
        _ handler: @escaping @MainActor @Sendable () async -> Bool
    )

    func update(
        for state: DictationState,
        shortcut: ProductShortcut,
        audioLevel: Double?,
        usedVerbatimFallback: Bool,
        language: TxChatLanguage
    )
}

extension DictationOverlayPresenting {
    func setCancellationHandler(
        _ handler: @escaping @MainActor @Sendable () async -> Bool
    ) {
        _ = handler
    }
}

@MainActor
final class DictationOverlayController: DictationOverlayPresenting {
    static let panelSize = NSSize(width: 360, height: 80)

    private let panel: NSPanel
    private let dismissalClock: any DictationClock
    private let transientDisplayDuration: Duration
    private var dismissalTask: Task<Void, Never>?
    private var hudModel: TxChatHUDModel?
    private var currentState: DictationState = .idle
    private var currentLanguage: TxChatLanguage = .productDefault
    private var cancellationFeedbackVisible = false
    private var cancellationRequestInFlight = false
    private var cancellationRequestGeneration = 0
    private var cancellationRequestState: DictationState?
    private var cancellationTask: Task<Void, Never>?
    private var cancellationHandler:
        @MainActor @Sendable () async -> Bool

    init(
        panel: NSPanel = DictationOverlayController.makePanel(),
        completionClock: any DictationClock = ContinuousDictationClock(),
        completionDisplayDuration: Duration = .seconds(1.5),
        cancellationHandler:
            @escaping @MainActor @Sendable () async -> Bool = { false }
    ) {
        self.panel = panel
        dismissalClock = completionClock
        transientDisplayDuration = completionDisplayDuration
        self.cancellationHandler = cancellationHandler
    }

    func setCancellationHandler(
        _ handler: @escaping @MainActor @Sendable () async -> Bool
    ) {
        cancellationHandler = handler
    }

    static func makePanel() -> NSPanel {
        let panel = TxChatNonactivatingPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
        ]
        panel.isMovableByWindowBackground = false
        return panel
    }

    func update(
        for state: DictationState,
        shortcut: ProductShortcut = .defaultFn,
        audioLevel: Double? = nil,
        usedVerbatimFallback: Bool = false,
        language: TxChatLanguage = .productDefault
    ) {
        if cancellationRequestInFlight,
           let cancellationRequestState,
           Self.isNewSessionUpdate(
               state,
               after: cancellationRequestState
           ) {
            invalidateCancellationRequest()
        }
        currentState = state
        currentLanguage = language
        if (cancellationRequestInFlight || cancellationFeedbackVisible),
           state == .idle {
            return
        }
        cancellationFeedbackVisible = false
        dismissalTask?.cancel()
        dismissalTask = nil
        switch state {
        case .starting, .listening, .finalizing, .organizing,
             .inserting:
            show(
                ProductPresentation.overlay(
                    for: state,
                    shortcut: shortcut,
                    usedVerbatimFallback: usedVerbatimFallback,
                    language: language
                ),
                audioLevel: audioLevel
            )
        case .completed, .failed:
            show(
                ProductPresentation.overlay(
                    for: state,
                    shortcut: shortcut,
                    usedVerbatimFallback: usedVerbatimFallback,
                    language: language
                ),
                audioLevel: audioLevel
            )
            scheduleDismissal()
        case .unavailable, .idle, .resultFallback:
            hide()
        }
    }

    @discardableResult
    func requestCancellation() -> Bool {
        guard Self.isCancellable(currentState),
              !cancellationRequestInFlight,
              !cancellationFeedbackVisible else {
            return false
        }
        cancellationRequestInFlight = true
        cancellationRequestGeneration &+= 1
        cancellationRequestState = currentState
        let requestGeneration = cancellationRequestGeneration
        let handler = cancellationHandler
        cancellationTask = Task { @MainActor [weak self] in
            let accepted = await handler()
            guard let self,
                  cancellationRequestGeneration == requestGeneration else {
                return
            }
            cancellationTask = nil
            cancellationRequestInFlight = false
            cancellationRequestState = nil
            guard accepted else { return }
            cancellationFeedbackVisible = true
            dismissalTask?.cancel()
            dismissalTask = nil
            show(ProductPresentation.cancellation(language: currentLanguage))
            scheduleDismissal()
        }
        return true
    }

    func show(
        _ presentation: OverlayPresentation,
        audioLevel: Double? = nil
    ) {
        if let hudModel {
            hudModel.presentation = presentation
            hudModel.audioLevel = audioLevel
        } else {
            let hudModel = TxChatHUDModel(
                presentation: presentation,
                audioLevel: audioLevel
            )
            self.hudModel = hudModel
            panel.contentViewController = NSHostingController(
                rootView: TxChatHUDContainerView(
                    model: hudModel,
                    cancelAction: { [weak self] in
                        self?.requestCancellation()
                    }
                )
            )
        }
        panel.setContentSize(Self.panelSize)
        positionPanel()
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        invalidateCancellationRequest()
        cancellationFeedbackVisible = false
        panel.orderOut(nil)
        panel.contentViewController = nil
        hudModel = nil
    }

    private func scheduleDismissal() {
        let clock = dismissalClock
        let duration = transientDisplayDuration
        dismissalTask = Task { [weak self] in
            do {
                try await clock.sleep(for: duration)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else {
                return
            }
            dismissalTask = nil
            hide()
        }
    }

    private static func isCancellable(_ state: DictationState) -> Bool {
        switch state {
        case .starting, .listening, .finalizing, .organizing:
            return true
        case .unavailable, .idle, .inserting, .resultFallback,
             .completed, .failed:
            return false
        }
    }

    private static func isNewSessionUpdate(
        _ state: DictationState,
        after requestedState: DictationState
    ) -> Bool {
        guard let requestedRank = cancellableStageRank(requestedState),
              let updatedRank = cancellableStageRank(state) else {
            return false
        }
        return updatedRank < requestedRank
    }

    private static func cancellableStageRank(
        _ state: DictationState
    ) -> Int? {
        switch state {
        case .starting: 0
        case .listening: 1
        case .finalizing: 2
        case .organizing: 3
        case .unavailable, .idle, .inserting, .resultFallback,
             .completed, .failed:
            nil
        }
    }

    private func invalidateCancellationRequest() {
        cancellationRequestGeneration &+= 1
        cancellationRequestInFlight = false
        cancellationRequestState = nil
        cancellationTask?.cancel()
        cancellationTask = nil
    }

    private func positionPanel() {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return
        }
        let origin = NSPoint(
            x: visibleFrame.midX - Self.panelSize.width / 2,
            y: visibleFrame.minY + 52
        )
        panel.setFrameOrigin(origin)
    }
}
