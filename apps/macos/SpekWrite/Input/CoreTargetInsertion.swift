import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Darwin
import Foundation

enum CoreAccessibilityPolicy {
    static func isSecure(role: String?, subrole: String?) -> Bool {
        let securityDescription = [role ?? "", subrole ?? ""]
            .joined(separator: " ")
            .lowercased()
        return securityDescription.contains("secure") ||
            securityDescription.contains("password")
    }

    static func supportsDirectAX(
        role: String?,
        selectedTextSettable: Bool
    ) -> Bool {
        guard selectedTextSettable, let role else {
            return false
        }
        return [
            kAXTextAreaRole as String,
            kAXTextFieldRole as String,
            kAXComboBoxRole as String,
        ].contains(role)
    }

    static func supportsPasteFallback(
        role: String?,
        subrole: String?,
        enabled: Bool,
        valueSettable: Bool,
        selectedTextSettable: Bool,
        selectedTextMarkerRangeSettable: Bool = false,
        confirmedEditableByAccessibility: Bool = false,
        systemPasteCommandEnabled: Bool = false,
        isSystemFocusedElement: Bool = false
    ) -> Bool {
        guard let role,
              !isSecure(role: role, subrole: subrole) else {
            return false
        }
        if systemPasteCommandEnabled && isSystemFocusedElement {
            return true
        }
        guard enabled,
              valueSettable || selectedTextSettable ||
                  selectedTextMarkerRangeSettable ||
                  confirmedEditableByAccessibility else {
            return false
        }
        return [
            kAXTextAreaRole as String,
            kAXTextFieldRole as String,
            kAXComboBoxRole as String,
            "AXWebArea",
        ].contains(role)
    }

    static func isEligible(
        role: String?,
        subrole: String?,
        selectedTextSettable: Bool
    ) -> Bool {
        !isSecure(role: role, subrole: subrole) &&
            supportsDirectAX(
                role: role,
                selectedTextSettable: selectedTextSettable
            )
    }
}

enum CoreTargetContinuityPolicy {
    static func allowsPaste(
        capturedPID: pid_t,
        frontmostPID: pid_t?,
        focusedPID: pid_t?,
        ownPID: pid_t,
        sameElement: Bool
    ) -> Bool {
        guard capturedPID > 0, capturedPID != ownPID else {
            return false
        }
        return frontmostPID == capturedPID &&
            focusedPID == capturedPID && sameElement
    }
}

struct CoreWindowPasteContinuity: Equatable, Sendable {
    let capturedApplicationPID: pid_t
    let currentApplicationPID: pid_t
    let sameFocusedWindow: Bool
    let pasteCommandEnabled: Bool
    let secureInputEnabled: Bool

    var allowsPaste: Bool {
        capturedApplicationPID > 0 &&
            capturedApplicationPID == currentApplicationPID &&
            sameFocusedWindow && pasteCommandEnabled &&
            !secureInputEnabled
    }
}

enum CoreInsertionDeliveryMethod: Equatable {
    case foregroundPaste
}

enum CoreInsertionDeliveryPolicy {
    static func methodForEligibleTarget() -> CoreInsertionDeliveryMethod {
        // AXSelectedText can report success without changing Chromium-based
        // editors. The foreground paste route is the only production method.
        .foregroundPaste
    }
}

enum CoreProcessAncestry {
    private static let maximumDepth = 32

    static func processFamilyCandidates(
        startingAt processIdentifier: pid_t,
        parentOf: (pid_t) -> pid_t?
    ) -> [pid_t] {
        guard processIdentifier > 1 else {
            return []
        }
        var candidates: [pid_t] = []
        var current = processIdentifier
        var visited = Set<pid_t>()
        for _ in 0..<maximumDepth {
            guard current > 1, visited.insert(current).inserted else {
                break
            }
            candidates.append(current)
            guard let parent = parentOf(current),
                  parent > 1,
                  parent != current else {
                break
            }
            current = parent
        }
        return candidates
    }

    static func belongsToSameProcessFamily(
        _ lhs: pid_t,
        _ rhs: pid_t,
        parentOf: (pid_t) -> pid_t?
    ) -> Bool {
        lhs == rhs ||
            isDescendant(lhs, of: rhs, parentOf: parentOf) ||
            isDescendant(rhs, of: lhs, parentOf: parentOf)
    }

    static func canonicalApplicationProcessIdentifier(
        from processFamilyCandidates: [pid_t]
    ) -> pid_t? {
        processFamilyCandidates.last
    }

    static func focusQueryCandidates(
        preferredProcessIdentifiers: [pid_t],
        canonicalApplicationProcessIdentifier: pid_t,
        allProcessIdentifiers: [pid_t],
        parentOf: (pid_t) -> pid_t?
    ) -> [pid_t] {
        guard canonicalApplicationProcessIdentifier > 1 else {
            return []
        }
        var result: [pid_t] = []
        var seen = Set<pid_t>()
        for processIdentifier in preferredProcessIdentifiers
        where processIdentifier > 1 && seen.insert(processIdentifier).inserted {
            result.append(processIdentifier)
        }

        let descendants = allProcessIdentifiers.compactMap {
            processIdentifier -> (pid_t, Int)? in
            guard processIdentifier > 1,
                  !seen.contains(processIdentifier),
                  let depth = descendantDepth(
                      processIdentifier,
                      from: canonicalApplicationProcessIdentifier,
                      parentOf: parentOf
                  ) else {
                return nil
            }
            return (processIdentifier, depth)
        }.sorted {
            $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1
        }
        for (processIdentifier, _) in descendants
        where seen.insert(processIdentifier).inserted {
            result.append(processIdentifier)
        }
        return result
    }

    private static func descendantDepth(
        _ processIdentifier: pid_t,
        from ancestorProcessIdentifier: pid_t,
        parentOf: (pid_t) -> pid_t?
    ) -> Int? {
        guard processIdentifier != ancestorProcessIdentifier else {
            return nil
        }
        var current = processIdentifier
        var visited = Set<pid_t>()
        for depth in 1...maximumDepth {
            guard visited.insert(current).inserted,
                  let parent = parentOf(current),
                  parent > 0,
                  parent != current else {
                return nil
            }
            if parent == ancestorProcessIdentifier {
                return depth
            }
            current = parent
        }
        return nil
    }

    static func isDescendant(
        _ processIdentifier: pid_t,
        of ancestorProcessIdentifier: pid_t,
        parentOf: (pid_t) -> pid_t?
    ) -> Bool {
        guard processIdentifier > 0,
              ancestorProcessIdentifier > 0,
              processIdentifier != ancestorProcessIdentifier else {
            return false
        }
        var current = processIdentifier
        var visited = Set<pid_t>()
        for _ in 0..<maximumDepth {
            guard visited.insert(current).inserted,
                  let parent = parentOf(current),
                  parent > 0,
                  parent != current else {
                return false
            }
            if parent == ancestorProcessIdentifier {
                return true
            }
            current = parent
        }
        return false
    }

    static func systemParent(of processIdentifier: pid_t) -> pid_t? {
        guard processIdentifier > 0 else {
            return nil
        }
        var info = proc_bsdinfo()
        let expectedSize = MemoryLayout<proc_bsdinfo>.size
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(
                processIdentifier,
                PROC_PIDTBSDINFO,
                0,
                pointer,
                Int32(expectedSize)
            )
        }
        guard result == Int32(expectedSize), info.pbi_ppid > 0 else {
            return nil
        }
        return pid_t(info.pbi_ppid)
    }

    static func systemProcessIdentifiers() -> [pid_t] {
        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount > 0 else {
            return []
        }
        var processIdentifiers = Array(
            repeating: pid_t(),
            count: Int(estimatedCount) + 64
        )
        let copiedCount = processIdentifiers.withUnsafeMutableBufferPointer {
            buffer in
            proc_listallpids(
                buffer.baseAddress,
                Int32(buffer.count * MemoryLayout<pid_t>.stride)
            )
        }
        guard copiedCount > 0 else {
            return []
        }
        return Array(processIdentifiers.prefix(Int(copiedCount)))
            .filter { $0 > 1 }
    }
}

enum CoreTargetProcessPolicy {
    static func pasteDeliveryProcessIdentifier(
        frontmostPID: pid_t,
        focusedPID: pid_t
    ) -> pid_t {
        focusedPID > 0 ? focusedPID : frontmostPID
    }

    static func allowsCapture(
        frontmostPID: pid_t,
        focusedPID: pid_t,
        ownPID: pid_t,
        focusedProcessBelongsToFrontmostApp: Bool,
        allowOwnProcess: Bool = false
    ) -> Bool {
        guard frontmostPID > 0,
              focusedPID > 0 else {
            return false
        }
        if frontmostPID == ownPID || focusedPID == ownPID {
            return allowOwnProcess &&
                frontmostPID == ownPID && focusedPID == ownPID
        }
        return focusedPID == frontmostPID ||
            focusedProcessBelongsToFrontmostApp
    }

    static func allowsInsertion(
        capturedFrontmostPID: pid_t,
        capturedFocusedPID: pid_t,
        currentFrontmostPID: pid_t?,
        currentFocusedPID: pid_t?,
        ownPID: pid_t,
        sameElement: Bool,
        focusedProcessBelongsToFrontmostApp: Bool,
        allowOwnProcess: Bool = false
    ) -> Bool {
        _ = sameElement
        guard capturedFrontmostPID > 0,
              capturedFocusedPID > 0,
              currentFrontmostPID == capturedFrontmostPID,
              let currentFocusedPID,
              currentFocusedPID > 0 else {
            return false
        }
        let involvesOwnProcess = capturedFrontmostPID == ownPID ||
            capturedFocusedPID == ownPID || currentFocusedPID == ownPID
        if involvesOwnProcess {
            return allowOwnProcess &&
                capturedFrontmostPID == ownPID &&
                capturedFocusedPID == ownPID &&
                currentFocusedPID == ownPID
        }
        return currentFocusedPID == capturedFrontmostPID ||
            focusedProcessBelongsToFrontmostApp
    }
}

enum CoreOwnProcessTargetPolicy {
    private static let allowedIdentifiers: Set<String> = [
        "dictionary.editor.wrong",
        "dictionary.editor.correct",
    ]

    static func allowsTarget(
        identifier: String?,
        role: String?,
        subrole: String?
    ) -> Bool {
        guard let identifier,
              allowedIdentifiers.contains(identifier),
              !CoreAccessibilityPolicy.isSecure(
                  role: role,
                  subrole: subrole
              ) else {
            return false
        }
        return role == kAXTextFieldRole as String ||
            role == kAXTextAreaRole as String
    }
}

enum CoreTargetCapturePolicy {
    static func outcomeForFailure(
        accessibilityAuthorized: Bool,
        secureEventInputEnabled: Bool,
        role: String?,
        subrole: String?
    ) -> CoreTargetCaptureOutcome {
        if !accessibilityAuthorized || secureEventInputEnabled ||
            CoreAccessibilityPolicy.isSecure(role: role, subrole: subrole) {
            return .blocked
        }
        return .unavailable
    }

}

enum CoreFocusedApplicationQuery {
    static func focusedElement<Application, Element>(
        processIdentifiers: [pid_t],
        createApplication: (pid_t) -> Application,
        copyFocusedElement: (Application) -> Element?,
        prepareForRetry: ([pid_t]) -> Void,
        retryAttempts: Int,
        waitBeforeRetry: (Int) -> Void
    ) -> Element? {
        func query() -> Element? {
            for processIdentifier in processIdentifiers {
                let application = createApplication(processIdentifier)
                if let element = copyFocusedElement(application) {
                    return element
                }
            }
            return nil
        }

        if let element = query() {
            return element
        }
        prepareForRetry(processIdentifiers)
        for attempt in 0..<max(0, retryAttempts) {
            waitBeforeRetry(attempt)
            if let element = query() {
                return element
            }
        }
        return nil
    }
}

enum CoreAccessibilityPreparation {
    static let attributeNames = [
        "AXEnhancedUserInterface",
        "AXManualAccessibility",
    ]
}

enum CorePasteCommandPolicy {
    static func isPlainPasteCommand(
        commandCharacter: String?,
        modifierRawValue: UInt32?,
        enabled: Bool
    ) -> Bool {
        guard enabled,
              commandCharacter?.caseInsensitiveCompare("V") == .orderedSame
        else {
            return false
        }
        return modifierRawValue.map { $0 == 0 } ?? true
    }
}

enum CorePasteMenuTreeQuery {
    private static let maximumElements = 1_024

    static func containsEnabledPlainPasteCommand<Element: Hashable>(
        root: Element,
        children: (Element) -> [Element],
        command: (Element) -> (String?, UInt32?, Bool)?
    ) -> Bool {
        var pending = [root]
        var visited = Set<Element>()
        while let element = pending.popLast(),
              visited.count < maximumElements {
            guard visited.insert(element).inserted else {
                continue
            }
            if let descriptor = command(element),
               CorePasteCommandPolicy.isPlainPasteCommand(
                   commandCharacter: descriptor.0,
                   modifierRawValue: descriptor.1,
                   enabled: descriptor.2
               ) {
                return true
            }
            pending.append(contentsOf: children(element))
        }
        return false
    }
}

@MainActor
protocol CoreTextPasteCommandCapabilityQuerying: AnyObject {
    func isPlainTextPasteCommandEnabled(
        processIdentifiers: [pid_t]
    ) -> Bool
}

private struct CoreAXElementNode: Hashable {
    let element: AXUIElement

    static func == (lhs: Self, rhs: Self) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

@MainActor
final class SystemCoreTextPasteCommandCapabilityQuery:
    CoreTextPasteCommandCapabilityQuerying
{
    func isPlainTextPasteCommandEnabled(
        processIdentifiers: [pid_t]
    ) -> Bool {
        for processIdentifier in processIdentifiers where processIdentifier > 1 {
            let application = AXUIElementCreateApplication(processIdentifier)
            guard let menuBar = elementAttribute(
                kAXMenuBarAttribute,
                of: application
            ) else {
                continue
            }
            if CorePasteMenuTreeQuery.containsEnabledPlainPasteCommand(
                root: CoreAXElementNode(element: menuBar),
                children: { [self] node in
                    elementArrayAttribute(
                        kAXChildrenAttribute,
                        of: node.element
                    ).map(CoreAXElementNode.init)
                },
                command: { [self] node in
                    guard stringAttribute(
                        kAXRoleAttribute,
                        of: node.element
                    ) == kAXMenuItemRole as String else {
                        return nil
                    }
                    return (
                        stringAttribute(
                            kAXMenuItemCmdCharAttribute,
                            of: node.element
                        ),
                        numberAttribute(
                            kAXMenuItemCmdModifiersAttribute,
                            of: node.element
                        )?.uint32Value,
                        booleanAttribute(
                            kAXEnabledAttribute,
                            of: node.element
                        ) ?? false
                    )
                }
            ) {
                return true
            }
        }
        return false
    }

    private func elementAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value as AnyObject, to: AXUIElement.self)
    }

    private func elementArrayAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success,
        let values = value as? [AnyObject] else {
            return []
        }
        return values.compactMap { value in
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeDowncast(value, to: AXUIElement.self)
        }
    }

    private func stringAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private func numberAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> NSNumber? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? NSNumber
    }

    private func booleanAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> Bool? {
        numberAttribute(attribute, of: element)?.boolValue
    }
}

@MainActor
final class CoreTextPasteCapabilityProbe {
    private static let probeText = "\u{2060}"

    private let pasteboard: any PasteboardTransactionServing
    private let query: any CoreTextPasteCommandCapabilityQuerying

    init(
        pasteboard: any PasteboardTransactionServing =
            SystemPasteboardTransaction(),
        query: any CoreTextPasteCommandCapabilityQuerying
    ) {
        self.pasteboard = pasteboard
        self.query = query
    }

    func canPastePlainText(processIdentifiers: [pid_t]) -> Bool {
        guard !processIdentifiers.isEmpty,
              let snapshot = pasteboard.snapshot(),
              let ownedChangeCount = pasteboard.writeTransientText(
                  Self.probeText,
                  preserving: snapshot
              )
        else {
            return false
        }
        let commandEnabled = query.isPlainTextPasteCommandEnabled(
            processIdentifiers: processIdentifiers
        )
        let restored = pasteboard.restore(
            snapshot,
            ifOwned: ownedChangeCount
        )
        return commandEnabled && restored
    }
}

@MainActor
final class CoreAccessibilityTargetHandler: CoreTargetHandling {
    private enum StoredTargetAnchor {
        case element(AXUIElement)
        case focusedWindow(AXUIElement)
    }

    private struct StoredTarget {
        let frontmostProcessIdentifier: pid_t
        let focusedProcessIdentifier: pid_t
        let anchor: StoredTargetAnchor
        let requiresSystemPasteCapabilityValidation: Bool
        let ownProcessTargetIdentifier: String?
    }

    private var targets: [UUID: StoredTarget] = [:]
    private let pasteInserter: TransientPasteInserter
    private let pasteCapabilityProbe: CoreTextPasteCapabilityProbe
    private let diagnostics: any CoreInsertionDiagnosticRecording

    init(
        pasteInserter: TransientPasteInserter? = nil,
        pasteCapabilityProbe: CoreTextPasteCapabilityProbe? = nil,
        diagnostics: any CoreInsertionDiagnosticRecording =
            SystemCoreInsertionDiagnosticRecorder()
    ) {
        self.diagnostics = diagnostics
        self.pasteInserter = pasteInserter ?? TransientPasteInserter(
            diagnostics: diagnostics
        )
        self.pasteCapabilityProbe = pasteCapabilityProbe ??
            CoreTextPasteCapabilityProbe(
                query: SystemCoreTextPasteCommandCapabilityQuery()
            )
    }

    static func requestAuthorizationIfNeeded() -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions(
            [promptKey: true] as CFDictionary
        )
    }

    func capture() -> CoreTargetCaptureOutcome {
        guard AXIsProcessTrusted() else {
            diagnostics.record(.captureAuthorizationFailed)
            return CoreTargetCapturePolicy.outcomeForFailure(
                accessibilityAuthorized: false,
                secureEventInputEnabled: false,
                role: nil,
                subrole: nil
            )
        }
        guard !IsSecureEventInputEnabled() else {
            diagnostics.record(.captureSecureInput)
            return CoreTargetCapturePolicy.outcomeForFailure(
                accessibilityAuthorized: true,
                secureEventInputEnabled: true,
                role: nil,
                subrole: nil
            )
        }
        guard let frontmostApplication =
            NSWorkspace.shared.frontmostApplication,
            frontmostApplication.processIdentifier > 0
        else {
            diagnostics.record(.captureFrontmostInvalid)
            return .unavailable
        }
        let rawFrontmostProcessIdentifier =
            frontmostApplication.processIdentifier
        let ancestorProcessIdentifiers =
            CoreProcessAncestry.processFamilyCandidates(
                startingAt: rawFrontmostProcessIdentifier,
                parentOf: CoreProcessAncestry.systemParent
            )
        guard let processIdentifier =
            CoreProcessAncestry.canonicalApplicationProcessIdentifier(
                from: ancestorProcessIdentifiers
        ) else {
            diagnostics.record(.captureFrontmostInvalid)
            return .unavailable
        }
        let processFamilyCandidates =
            CoreProcessAncestry.focusQueryCandidates(
                preferredProcessIdentifiers: ancestorProcessIdentifiers,
                canonicalApplicationProcessIdentifier: processIdentifier,
                allProcessIdentifiers:
                    CoreProcessAncestry.systemProcessIdentifiers(),
                parentOf: CoreProcessAncestry.systemParent
            )
        let isOwnProcess = rawFrontmostProcessIdentifier == getpid() ||
            processIdentifier == getpid()
        let focusedElement = focusedElement(for: processFamilyCandidates)
        if let focusedElement {
            let focusedRole = stringAttribute(
                kAXRoleAttribute,
                of: focusedElement
            )
            let focusedSubrole = stringAttribute(
                kAXSubroleAttribute,
                of: focusedElement
            )
            if CoreAccessibilityPolicy.isSecure(
                role: focusedRole,
                subrole: focusedSubrole
            ) {
                diagnostics.record(.captureSecureInput)
                return CoreTargetCapturePolicy.outcomeForFailure(
                    accessibilityAuthorized: true,
                    secureEventInputEnabled: false,
                    role: focusedRole,
                    subrole: focusedSubrole
                )
            }
        }
        let systemPasteCommandEnabled = isOwnProcess
            ? false
            : pasteCapabilityProbe.canPastePlainText(
                processIdentifiers: processFamilyCandidates
            )
        if let focusedElement {
            let element = systemPasteCommandEnabled
                ? pasteTarget(
                    from: focusedElement,
                    systemPasteCommandEnabled: true
                )
                : pasteTarget(from: focusedElement)
            if let element,
               let focusedProcessIdentifier = self.processIdentifier(
                   of: element
               ) {
                let ownProcessTargetIdentifier = isOwnProcess
                    ? stringAttribute(kAXIdentifierAttribute, of: element)
                    : nil
                if isOwnProcess && !CoreOwnProcessTargetPolicy.allowsTarget(
                    identifier: ownProcessTargetIdentifier,
                    role: stringAttribute(kAXRoleAttribute, of: element),
                    subrole: stringAttribute(kAXSubroleAttribute, of: element)
                ) {
                    diagnostics.record(.captureOwnProcess)
                    return .unavailable
                }
                let focusedProcessBelongsToFrontmostApp =
                    focusedProcessIdentifier != processIdentifier &&
                    CoreProcessAncestry.belongsToSameProcessFamily(
                        focusedProcessIdentifier,
                        processIdentifier,
                        parentOf: CoreProcessAncestry.systemParent
                    )
                guard CoreTargetProcessPolicy.allowsCapture(
                    frontmostPID: processIdentifier,
                    focusedPID: focusedProcessIdentifier,
                    ownPID: getpid(),
                    focusedProcessBelongsToFrontmostApp:
                        focusedProcessBelongsToFrontmostApp,
                    allowOwnProcess: isOwnProcess
                ) else {
                    diagnostics.record(.captureFocusedProcessChanged)
                    return .unavailable
                }
                let identifier = UUID()
                targets[identifier] = StoredTarget(
                    frontmostProcessIdentifier: processIdentifier,
                    focusedProcessIdentifier: focusedProcessIdentifier,
                    anchor: .element(element),
                    requiresSystemPasteCapabilityValidation:
                        systemPasteCommandEnabled,
                    ownProcessTargetIdentifier: ownProcessTargetIdentifier
                )
                if systemPasteCommandEnabled {
                    diagnostics.record(
                        .captureSystemPasteCapabilityAccepted
                    )
                }
                diagnostics.record(.captureSucceeded)
                return .captured(
                    CoreCapturedTarget(
                        id: identifier,
                        processIdentifier: processIdentifier
                    )
                )
            }
        }

        if isOwnProcess {
            diagnostics.record(.captureOwnProcess)
            return .unavailable
        }

        guard systemPasteCommandEnabled,
              let window = focusedWindow(for: processFamilyCandidates),
              let windowProcessIdentifier = self.processIdentifier(of: window)
        else {
            diagnostics.record(
                focusedElement == nil
                    ? .captureFocusedElementUnavailable
                    : .captureTargetUnsupported
            )
            return .unavailable
        }
        let windowProcessBelongsToFrontmostApp =
            windowProcessIdentifier != processIdentifier &&
            CoreProcessAncestry.belongsToSameProcessFamily(
                windowProcessIdentifier,
                processIdentifier,
                parentOf: CoreProcessAncestry.systemParent
            )
        guard CoreTargetProcessPolicy.allowsCapture(
            frontmostPID: processIdentifier,
            focusedPID: windowProcessIdentifier,
            ownPID: getpid(),
            focusedProcessBelongsToFrontmostApp:
                windowProcessBelongsToFrontmostApp
        ),
        CoreWindowPasteContinuity(
            capturedApplicationPID: processIdentifier,
            currentApplicationPID: processIdentifier,
            sameFocusedWindow: true,
            pasteCommandEnabled: systemPasteCommandEnabled,
            secureInputEnabled: false
        ).allowsPaste
        else {
            diagnostics.record(.captureFocusedProcessChanged)
            return .unavailable
        }
        let identifier = UUID()
        targets[identifier] = StoredTarget(
            frontmostProcessIdentifier: processIdentifier,
            focusedProcessIdentifier: windowProcessIdentifier,
            anchor: .focusedWindow(window),
            requiresSystemPasteCapabilityValidation: true,
            ownProcessTargetIdentifier: nil
        )
        diagnostics.record(.captureSystemPasteCapabilityAccepted)
        diagnostics.record(.captureWindowFallbackSucceeded)
        diagnostics.record(.captureSucceeded)
        return .captured(
            CoreCapturedTarget(
                id: identifier,
                processIdentifier: processIdentifier
            )
        )
    }

    func insert(_ text: String, into target: CoreCapturedTarget) -> Bool {
        guard !text.isEmpty else {
            diagnostics.record(.insertionEmptyText)
            return false
        }
        guard let stored = targets.removeValue(forKey: target.id) else {
            diagnostics.record(.insertionTargetMissing)
            return false
        }
        guard stored.frontmostProcessIdentifier == target.processIdentifier else {
            diagnostics.record(.insertionTargetIdentityMismatch)
            return false
        }
        let secureInputEnabled = IsSecureEventInputEnabled()
        guard !secureInputEnabled else {
            diagnostics.record(.insertionSecureInput)
            return false
        }
        guard let frontmostApplication =
            NSWorkspace.shared.frontmostApplication else {
            diagnostics.record(.insertionFrontmostChanged)
            return false
        }
        let rawFrontmostPID = frontmostApplication.processIdentifier
        let ancestorProcessIdentifiers =
            CoreProcessAncestry.processFamilyCandidates(
                startingAt: rawFrontmostPID,
                parentOf: CoreProcessAncestry.systemParent
            )
        guard let frontmostPID =
            CoreProcessAncestry.canonicalApplicationProcessIdentifier(
                from: ancestorProcessIdentifiers
            ) else {
            diagnostics.record(.insertionFrontmostChanged)
            return false
        }
        guard frontmostPID == target.processIdentifier else {
            diagnostics.record(.insertionFrontmostChanged)
            return false
        }
        let processFamilyCandidates =
            CoreProcessAncestry.focusQueryCandidates(
                preferredProcessIdentifiers: ancestorProcessIdentifiers,
                canonicalApplicationProcessIdentifier: frontmostPID,
                allProcessIdentifiers:
                    CoreProcessAncestry.systemProcessIdentifiers(),
                parentOf: CoreProcessAncestry.systemParent
            )
        switch stored.anchor {
        case .element(let capturedElement):
            guard let focusedElement = focusedElement(
                for: processFamilyCandidates
            ) else {
                diagnostics.record(.insertionFocusedProcessChanged)
                return false
            }
            let systemPasteCommandEnabled: Bool
            if stored.requiresSystemPasteCapabilityValidation {
                systemPasteCommandEnabled =
                    pasteCapabilityProbe.canPastePlainText(
                        processIdentifiers: processFamilyCandidates
                    )
                guard systemPasteCommandEnabled else {
                    diagnostics.record(.insertionCurrentTargetUnsupported)
                    return false
                }
            } else {
                systemPasteCommandEnabled = false
            }
            guard let current = pasteTarget(
                from: focusedElement,
                systemPasteCommandEnabled: systemPasteCommandEnabled
            ) else {
                diagnostics.record(.insertionFocusedProcessChanged)
                return false
            }
            let currentPID = processIdentifier(of: current)
            let sameElement = CFEqual(capturedElement, current)
            let allowsOwnProcess = stored.ownProcessTargetIdentifier != nil
            if let expectedIdentifier = stored.ownProcessTargetIdentifier {
                guard stringAttribute(kAXIdentifierAttribute, of: current) ==
                    expectedIdentifier,
                    CoreOwnProcessTargetPolicy.allowsTarget(
                        identifier: expectedIdentifier,
                        role: stringAttribute(kAXRoleAttribute, of: current),
                        subrole: stringAttribute(kAXSubroleAttribute, of: current)
                    ) else {
                    diagnostics.record(.insertionCurrentTargetUnsupported)
                    return false
                }
            }
            let focusedProcessBelongsToFrontmostApp = currentPID.map {
                $0 != target.processIdentifier &&
                    CoreProcessAncestry.belongsToSameProcessFamily(
                        $0,
                        target.processIdentifier,
                        parentOf: CoreProcessAncestry.systemParent
                    )
            } ?? false
            guard CoreTargetProcessPolicy.allowsInsertion(
                capturedFrontmostPID: target.processIdentifier,
                capturedFocusedPID: stored.focusedProcessIdentifier,
                currentFrontmostPID: frontmostPID,
                currentFocusedPID: currentPID,
                ownPID: getpid(),
                sameElement: sameElement,
                focusedProcessBelongsToFrontmostApp:
                    focusedProcessBelongsToFrontmostApp,
                allowOwnProcess: allowsOwnProcess
            ) else {
                diagnostics.record(.insertionFocusedProcessChanged)
                return false
            }
            return deliverThroughForegroundPaste(
                text,
                processIdentifier: CoreTargetProcessPolicy
                    .pasteDeliveryProcessIdentifier(
                        frontmostPID: target.processIdentifier,
                        focusedPID: stored.focusedProcessIdentifier
                    )
            )

        case .focusedWindow(let capturedWindow):
            let systemPasteCommandEnabled =
                pasteCapabilityProbe.canPastePlainText(
                    processIdentifiers: processFamilyCandidates
                )
            guard systemPasteCommandEnabled else {
                diagnostics.record(.insertionCurrentTargetUnsupported)
                return false
            }
            guard let currentWindow = focusedWindow(
                for: processFamilyCandidates
            ),
            let currentWindowPID = processIdentifier(of: currentWindow) else {
                diagnostics.record(.insertionFocusedProcessChanged)
                return false
            }
            let windowProcessBelongsToFrontmostApp =
                currentWindowPID != target.processIdentifier &&
                CoreProcessAncestry.belongsToSameProcessFamily(
                    currentWindowPID,
                    target.processIdentifier,
                    parentOf: CoreProcessAncestry.systemParent
                )
            guard CoreTargetProcessPolicy.allowsInsertion(
                capturedFrontmostPID: target.processIdentifier,
                capturedFocusedPID: stored.focusedProcessIdentifier,
                currentFrontmostPID: frontmostPID,
                currentFocusedPID: currentWindowPID,
                ownPID: getpid(),
                sameElement: CFEqual(capturedWindow, currentWindow),
                focusedProcessBelongsToFrontmostApp:
                    windowProcessBelongsToFrontmostApp
            ),
            CoreWindowPasteContinuity(
                capturedApplicationPID: target.processIdentifier,
                currentApplicationPID: frontmostPID,
                sameFocusedWindow: CFEqual(
                    capturedWindow,
                    currentWindow
                ),
                pasteCommandEnabled: systemPasteCommandEnabled,
                secureInputEnabled: secureInputEnabled
            ).allowsPaste
            else {
                diagnostics.record(.insertionFocusedProcessChanged)
                return false
            }
            return deliverThroughForegroundPaste(
                text,
                processIdentifier: CoreTargetProcessPolicy
                    .pasteDeliveryProcessIdentifier(
                        frontmostPID: target.processIdentifier,
                        focusedPID: currentWindowPID
                    )
            )
        }
    }

    func discard(_ target: CoreCapturedTarget) {
        targets.removeValue(forKey: target.id)
    }

    private func deliverThroughForegroundPaste(
        _ text: String,
        processIdentifier: pid_t
    ) -> Bool {
        switch CoreInsertionDeliveryPolicy.methodForEligibleTarget() {
        case .foregroundPaste:
            diagnostics.record(.pasteFallbackStarted)
            return pasteInserter.insert(text, into: processIdentifier)
        }
    }

    private func focusedElement(
        for processIdentifiers: [pid_t]
    ) -> AXUIElement? {
        CoreFocusedApplicationQuery.focusedElement(
            processIdentifiers: processIdentifiers,
            createApplication: AXUIElementCreateApplication,
            copyFocusedElement: { application in
                var value: CFTypeRef?
                guard
                    AXUIElementCopyAttributeValue(
                        application,
                        kAXFocusedUIElementAttribute as CFString,
                        &value
                    ) == .success,
                    let value,
                    CFGetTypeID(value) == AXUIElementGetTypeID()
                else {
                    return nil
                }
                return unsafeDowncast(
                    value as AnyObject,
                    to: AXUIElement.self
                )
            },
            prepareForRetry: enableEnhancedAccessibility,
            retryAttempts: 3,
            waitBeforeRetry: { _ in
                usleep(40_000)
            }
        )
    }

    private func focusedWindow(
        for processIdentifiers: [pid_t]
    ) -> AXUIElement? {
        CoreFocusedApplicationQuery.focusedElement(
            processIdentifiers: processIdentifiers,
            createApplication: AXUIElementCreateApplication,
            copyFocusedElement: { application in
                var value: CFTypeRef?
                guard
                    AXUIElementCopyAttributeValue(
                        application,
                        kAXFocusedWindowAttribute as CFString,
                        &value
                    ) == .success,
                    let value,
                    CFGetTypeID(value) == AXUIElementGetTypeID()
                else {
                    return nil
                }
                return unsafeDowncast(
                    value as AnyObject,
                    to: AXUIElement.self
                )
            },
            prepareForRetry: enableEnhancedAccessibility,
            retryAttempts: 3,
            waitBeforeRetry: { _ in
                usleep(40_000)
            }
        )
    }

    private func enableEnhancedAccessibility(
        for processIdentifiers: [pid_t]
    ) {
        diagnostics.record(.accessibilityPreparationStarted)
        for processIdentifier in processIdentifiers {
            let application = AXUIElementCreateApplication(processIdentifier)
            for attribute in CoreAccessibilityPreparation.attributeNames {
                _ = AXUIElementSetAttributeValue(
                    application,
                    attribute as CFString,
                    kCFBooleanTrue
                )
            }

            var windowValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                application,
                kAXFocusedWindowAttribute as CFString,
                &windowValue
            ) == .success,
               let windowValue,
               CFGetTypeID(windowValue) == AXUIElementGetTypeID() {
                let window = unsafeDowncast(
                    windowValue as AnyObject,
                    to: AXUIElement.self
                )
                for attribute in CoreAccessibilityPreparation.attributeNames {
                    _ = AXUIElementSetAttributeValue(
                        window,
                        attribute as CFString,
                        kCFBooleanTrue
                    )
                }
            }
        }
    }

    private func processIdentifier(of element: AXUIElement) -> pid_t? {
        var processIdentifier = pid_t()
        guard AXUIElementGetPid(element, &processIdentifier) == .success else {
            return nil
        }
        return processIdentifier
    }

    private func pasteTarget(
        from focusedElement: AXUIElement,
        systemPasteCommandEnabled: Bool = false
    ) -> AXUIElement? {
        let focusedRole = stringAttribute(kAXRoleAttribute, of: focusedElement)
        let focusedSubrole = stringAttribute(
            kAXSubroleAttribute,
            of: focusedElement
        )
        guard !CoreAccessibilityPolicy.isSecure(
            role: focusedRole,
            subrole: focusedSubrole
        ) else {
            return nil
        }

        if supportsPasteFallback(
            focusedElement,
            systemPasteCommandEnabled: systemPasteCommandEnabled,
            isSystemFocusedElement: true
        ) {
            return focusedElement
        }

        // WebKit and other custom editors can expose the keyboard-editable
        // control through an AX editable-ancestor relationship while keeping
        // AXValue and AXSelectedText read-only. Resolve that system-provided
        // relationship instead of maintaining application-specific rules.
        for attribute in [
            "AXEditableAncestor",
            "AXHighestEditableAncestor",
        ] {
            guard let ancestor = elementAttribute(
                attribute,
                of: focusedElement
            ) else {
                continue
            }
            if supportsPasteFallback(
                ancestor,
                confirmedEditableByAccessibility: true,
                isSystemFocusedElement: false
            ) {
                return ancestor
            }
        }
        return nil
    }

    private func supportsPasteFallback(
        _ element: AXUIElement,
        confirmedEditableByAccessibility: Bool = false,
        systemPasteCommandEnabled: Bool = false,
        isSystemFocusedElement: Bool = false
    ) -> Bool {
        var valueSettable = DarwinBoolean(false)
        var selectedTextSettable = DarwinBoolean(false)
        var selectedTextMarkerRangeSettable = DarwinBoolean(false)
        _ = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &valueSettable
        )
        _ = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextSettable
        )
        _ = AXUIElementIsAttributeSettable(
            element,
            "AXSelectedTextMarkerRange" as CFString,
            &selectedTextMarkerRangeSettable
        )
        return CoreAccessibilityPolicy.supportsPasteFallback(
            role: stringAttribute(kAXRoleAttribute, of: element),
            subrole: stringAttribute(kAXSubroleAttribute, of: element),
            enabled: booleanAttribute(kAXEnabledAttribute, of: element) ?? true,
            valueSettable: valueSettable.boolValue,
            selectedTextSettable: selectedTextSettable.boolValue,
            selectedTextMarkerRangeSettable:
                selectedTextMarkerRangeSettable.boolValue,
            confirmedEditableByAccessibility:
                confirmedEditableByAccessibility,
            systemPasteCommandEnabled: systemPasteCommandEnabled,
            isSystemFocusedElement: isSystemFocusedElement
        )
    }

    private func elementAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &value
            ) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(value as AnyObject, to: AXUIElement.self)
    }

    private func booleanAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> Bool? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &value
            ) == .success,
            let number = value as? NSNumber
        else {
            return nil
        }
        return number.boolValue
    }

    private func stringAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &value
            ) == .success
        else {
            return nil
        }
        return value as? String
    }
}
