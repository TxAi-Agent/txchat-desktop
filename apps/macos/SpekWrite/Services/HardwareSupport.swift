import Darwin

enum LocalInferenceAvailability: Equatable, Sendable {
    case supported
    case cloudFallbackOnly
    case unsupported
}

struct HardwareSupport: Equatable, Sendable {
    let architecture: String

    var localInference: LocalInferenceAvailability {
        switch architecture {
        case "arm64": .supported
        case "x86_64": .cloudFallbackOnly
        default: .unsupported
        }
    }
}

extension HardwareSupport {
    static var current: HardwareSupport {
        HardwareSupport(architecture: currentMachineArchitecture())
    }

    private static func currentMachineArchitecture() -> String {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else {
            return ""
        }

        var machine = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else {
            return ""
        }

        let bytes = machine.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
