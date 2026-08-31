@preconcurrency import Carbon.HIToolbox
import Foundation

enum ShortcutRegistrationFailure: Equatable, Sendable {
    case conflict
    case unavailable
    case unsupported
}

enum ShortcutRegistrationResult: Equatable, Sendable {
    case registered
    case failed(ShortcutRegistrationFailure)

    var isRegistered: Bool {
        self == .registered
    }
}

@MainActor
protocol ProductShortcutMonitoring: AnyObject {
    @discardableResult
    func start(
        shortcut: ProductShortcut,
        handler: @escaping @MainActor () -> Void
    ) -> ShortcutRegistrationResult
    func stop()
}

@MainActor
protocol ProductFunctionShortcutRegistering: AnyObject {
    @discardableResult
    func start(
        handler: @escaping @MainActor () -> Void
    ) -> ShortcutRegistrationResult
    func stop()
}

@MainActor
protocol ProductStandardShortcutRegistering: AnyObject {
    @discardableResult
    func start(
        shortcut: ProductShortcut,
        handler: @escaping @MainActor () -> Void
    ) -> ShortcutRegistrationResult
    func stop()
}

@MainActor
protocol ProductRightOptionShortcutListening: AnyObject {
    @discardableResult
    func start(
        handler: @escaping @MainActor () -> Void
    ) -> ShortcutRegistrationResult
    func stop()
}

@MainActor
final class ProductShortcutMonitor: ProductShortcutMonitoring {
    private enum Route {
        case function
        case standard
        case rightOption
    }

    private let functionRegistrar: any ProductFunctionShortcutRegistering
    private let standardRegistrar: any ProductStandardShortcutRegistering
    private let rightOptionListener: any ProductRightOptionShortcutListening
    private var activeRoute: Route?
    private var generation: UInt = 0

    init(
        functionRegistrar: any ProductFunctionShortcutRegistering =
            CoreProductFunctionShortcutRegistrar(),
        standardRegistrar: any ProductStandardShortcutRegistering =
            CarbonProductStandardShortcutRegistrar(),
        rightOptionListener: any ProductRightOptionShortcutListening =
            UnsupportedProductRightOptionShortcutListener()
    ) {
        self.functionRegistrar = functionRegistrar
        self.standardRegistrar = standardRegistrar
        self.rightOptionListener = rightOptionListener
    }

    @discardableResult
    func start(
        shortcut: ProductShortcut,
        handler: @escaping @MainActor () -> Void
    ) -> ShortcutRegistrationResult {
        stop()
        generation &+= 1
        let currentGeneration = generation
        let guardedHandler: @MainActor () -> Void = { [weak self] in
            guard let self,
                  self.generation == currentGeneration,
                  self.activeRoute != nil else {
                return
            }
            handler()
        }

        let route: Route
        let result: ShortcutRegistrationResult
        switch shortcut.key {
        case .function:
            route = .function
            result = functionRegistrar.start(handler: guardedHandler)
        case .standard:
            route = .standard
            result = standardRegistrar.start(
                shortcut: shortcut,
                handler: guardedHandler
            )
        case .rightOption:
            route = .rightOption
            result = rightOptionListener.start(handler: guardedHandler)
        }

        guard result.isRegistered else {
            generation &+= 1
            stop(route: route)
            return result
        }
        activeRoute = route
        return result
    }

    func stop() {
        generation &+= 1
        guard let activeRoute else {
            return
        }
        stop(route: activeRoute)
        self.activeRoute = nil
    }

    private func stop(route: Route) {
        switch route {
        case .function:
            functionRegistrar.stop()
        case .standard:
            standardRegistrar.stop()
        case .rightOption:
            rightOptionListener.stop()
        }
    }
}

@MainActor
final class CoreProductFunctionShortcutRegistrar:
    ProductFunctionShortcutRegistering
{
    private let monitor: CoreHotkeyMonitor

    init(monitor: CoreHotkeyMonitor = CoreHotkeyMonitor()) {
        self.monitor = monitor
    }

    @discardableResult
    func start(
        handler: @escaping @MainActor () -> Void
    ) -> ShortcutRegistrationResult {
        monitor.start(handler: handler)
            ? .registered
            : .failed(.unavailable)
    }

    func stop() {
        monitor.stop()
    }
}

@MainActor
final class UnsupportedProductRightOptionShortcutListener:
    ProductRightOptionShortcutListening
{
    @discardableResult
    func start(
        handler: @escaping @MainActor () -> Void
    ) -> ShortcutRegistrationResult {
        _ = handler
        return .failed(.unsupported)
    }

    func stop() {}
}

private func productCarbonHotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    _ = nextHandler
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }
    var hotKeyIdentifier = EventHotKeyID(signature: 0, id: 0)
    let parameterStatus = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyIdentifier
    )
    guard parameterStatus == noErr else {
        return parameterStatus
    }
    let registrar = Unmanaged<CarbonProductStandardShortcutRegistrar>
        .fromOpaque(userData)
        .takeUnretainedValue()
    return MainActor.assumeIsolated {
        registrar.handleRegisteredShortcut(
            signature: hotKeyIdentifier.signature,
            identifier: hotKeyIdentifier.id
        )
    }
}

@MainActor
final class CarbonProductStandardShortcutRegistrar:
    ProductStandardShortcutRegistering
{
    private static let signature: OSType = 0x5458_4348
    private static let identifier: UInt32 = 1

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var handler: (@MainActor () -> Void)?

    @discardableResult
    func start(
        shortcut: ProductShortcut,
        handler: @escaping @MainActor () -> Void
    ) -> ShortcutRegistrationResult {
        stop()
        guard case .standard = shortcut.key else {
            return .failed(.unsupported)
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            productCarbonHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedHandler
        )
        guard installStatus == noErr else {
            return .failed(.unavailable)
        }
        eventHandler = installedHandler

        var registeredHotKey: EventHotKeyRef?
        let registrationStatus = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.modifierMask(for: shortcut.modifiers),
            EventHotKeyID(
                signature: Self.signature,
                id: Self.identifier
            ),
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )
        guard registrationStatus == noErr else {
            stop()
            return registrationStatus == OSStatus(eventHotKeyExistsErr)
                ? .failed(.conflict)
                : .failed(.unavailable)
        }

        hotKey = registeredHotKey
        self.handler = handler
        return .registered
    }

    func stop() {
        handler = nil
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        hotKey = nil
        eventHandler = nil
    }

    fileprivate func handleRegisteredShortcut(
        signature: OSType,
        identifier: UInt32
    ) -> OSStatus {
        guard Self.acceptsHotKey(
            signature: signature,
            identifier: identifier
        ) else {
            return OSStatus(eventNotHandledErr)
        }
        handler?()
        return noErr
    }

    static func acceptsHotKey(
        signature: OSType,
        identifier: UInt32
    ) -> Bool {
        signature == Self.signature && identifier == Self.identifier
    }

    static func modifierMask(
        for modifiers: [ProductShortcut.Modifier]
    ) -> UInt32 {
        modifiers.reduce(UInt32(0)) { result, modifier in
            switch modifier {
            case .control:
                result | UInt32(controlKey)
            case .option:
                result | UInt32(optionKey)
            case .shift:
                result | UInt32(shiftKey)
            case .command:
                result | UInt32(cmdKey)
            case .function:
                result
            }
        }
    }
}
