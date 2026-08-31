import Foundation

@MainActor
final class AccessibilityTargetHandler: DictationTargetHandling {
    private let base: any CoreTargetHandling

    init(
        base: any CoreTargetHandling = CoreAccessibilityTargetHandler()
    ) {
        self.base = base
    }

    func capture() -> DictationTargetCaptureOutcome {
        switch base.capture() {
        case .captured(let target):
            return .captured(
                DictationTarget(
                    id: target.id,
                    processIdentifier: target.processIdentifier
                )
            )
        case .unavailable:
            return .unavailable
        case .blocked:
            return .blocked
        }
    }

    func insert(_ text: String, into target: DictationTarget) -> Bool {
        base.insert(text, into: task3Target(from: target))
    }

    func discard(_ target: DictationTarget) {
        base.discard(task3Target(from: target))
    }

    private func task3Target(
        from target: DictationTarget
    ) -> CoreCapturedTarget {
        CoreCapturedTarget(
            id: target.id,
            processIdentifier: target.processIdentifier
        )
    }
}
