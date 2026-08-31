import Foundation

struct ProductConfiguration: Equatable, Sendable {
    enum Error: Swift.Error, Equatable {
        case invalidAPIOrigin
        case invalidRealtimeOrigin
    }

    let apiBaseURL: URL
    let realtimeBaseURL: URL
    let allowsInsecureLoopbackForTesting: Bool

    init(
        apiBaseURL: URL,
        realtimeBaseURL: URL,
        allowsInsecureLoopbackForTesting: Bool = false
    ) throws {
        guard Self.isValidOrigin(
            apiBaseURL,
            secureScheme: "https",
            insecureScheme: "http",
            allowsInsecureLoopback: allowsInsecureLoopbackForTesting
        ) else {
            throw Error.invalidAPIOrigin
        }
        guard Self.isValidOrigin(
            realtimeBaseURL,
            secureScheme: "wss",
            insecureScheme: "ws",
            allowsInsecureLoopback: allowsInsecureLoopbackForTesting
        ) else {
            throw Error.invalidRealtimeOrigin
        }
        self.apiBaseURL = apiBaseURL
        self.realtimeBaseURL = realtimeBaseURL
        self.allowsInsecureLoopbackForTesting =
            allowsInsecureLoopbackForTesting
    }

    private static func isValidOrigin(
        _ url: URL,
        secureScheme: String,
        insecureScheme: String,
        allowsInsecureLoopback: Bool
    ) -> Bool {
        guard
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            let scheme = components.scheme?.lowercased(),
            let host = components.host?.lowercased(),
            !host.isEmpty,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil,
            components.percentEncodedPath.isEmpty ||
                components.percentEncodedPath == "/"
        else {
            return false
        }
        if scheme == secureScheme {
            return true
        }
        return allowsInsecureLoopback &&
            scheme == insecureScheme &&
            host == "127.0.0.1"
    }
}

struct PublicLocalDevelopmentConfiguration: Equatable, Sendable {
    let apiBaseURL: URL
    let realtimeBaseURL: URL

    static func load(environment: [String: String]) -> Self? {
#if DEBUG
        let allowedFields: Set<String> = [
            "TXCHAT_PUBLIC_LOCAL_DEVELOPMENT",
            "TXCHAT_PUBLIC_LOCAL_PORT",
        ]
        guard environment.keys.allSatisfy({ field in
            !field.hasPrefix("TXCHAT_PUBLIC_LOCAL_") ||
                allowedFields.contains(field)
        }) else {
            return nil
        }
        guard environment["TXCHAT_PUBLIC_LOCAL_DEVELOPMENT"] == "1",
              let rawPort = environment["TXCHAT_PUBLIC_LOCAL_PORT"],
              !rawPort.isEmpty,
              rawPort.allSatisfy({ $0.isASCII && $0.isNumber }),
              let port = Int(rawPort),
              (1024...65_535).contains(port),
              let apiBaseURL = loopbackURL(scheme: "http", port: port),
              let realtimeBaseURL = loopbackURL(scheme: "ws", port: port)
        else {
            return nil
        }
        return Self(
            apiBaseURL: apiBaseURL,
            realtimeBaseURL: realtimeBaseURL
        )
#else
        return nil
#endif
    }

#if DEBUG
    private static func loopbackURL(scheme: String, port: Int) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "127.0.0.1"
        components.port = port
        return components.url
    }
#endif
}

enum ProductConfigurationLoader {
    static func load(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) -> ProductConfiguration? {
        if info.keys.contains(where: isCredentialLikeInfoField) {
            return nil
        }
        let apiSource = nonemptyString(info["SPEKWRITE_API_BASE_URL"])
        let realtimeSource = nonemptyString(
            info["SPEKWRITE_REALTIME_BASE_URL"]
        )
        guard
            let apiValue = apiSource,
            let realtimeValue = realtimeSource,
            let apiURL = URL(string: apiValue),
            let realtimeURL = URL(string: realtimeValue)
        else {
            return nil
        }

        return try? ProductConfiguration(
            apiBaseURL: apiURL,
            realtimeBaseURL: realtimeURL,
            allowsInsecureLoopbackForTesting: false
        )
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isCredentialLikeInfoField(_ field: String) -> Bool {
        let components = infoFieldComponents(field)
        guard !components.isEmpty else {
            return false
        }
        let safeMetadataSuffixes: Set<String> = [
            "EXPIRY",
            "FORMAT",
            "POLICY",
            "STATUS",
        ]
        let terminalCredentialComponents: Set<String> = [
            "AUTHORIZATION",
            "CREDENTIAL",
            "CREDENTIALS",
            "PASSPHRASE",
            "PASSWORD",
            "SECRET",
            "TOKEN",
        ]
        let compactCredentialComponents = [
            "CONNECTIONSTRING",
            "REFRESHTOKEN",
            "CLIENTSECRET",
            "ACCESSTOKEN",
            "AUTHORIZATION",
            "CREDENTIALS",
            "PASSPHRASE",
            "PRIVATEKEY",
            "APIKEY",
            "ACCESSKEY",
            "AUTHTOKEN",
            "SECRETKEY",
            "CREDENTIAL",
            "PASSWORD",
            "SECRET",
            "TOKEN",
        ]

        if components.count == 1 {
            let match = compactCredentialComponentMatch(
                components[0],
                credentialMarkers: compactCredentialComponents
            )
            guard match.found else {
                return false
            }
            guard let suffix = match.suffix else {
                return true
            }
            return suffix.isEmpty ||
                !safeMetadataSuffixes.contains(suffix)
        }

        let credentialPairs: Set<String> = [
            "ACCESS KEY",
            "ACCESS TOKEN",
            "API KEY",
            "AUTH TOKEN",
            "CLIENT SECRET",
            "CONNECTION STRING",
            "PRIVATE KEY",
            "REFRESH TOKEN",
            "SECRET KEY",
        ]
        for index in components.indices {
            if terminalCredentialComponents.contains(components[index]) {
                let suffix = components[(index + 1)...]
                if suffix.isEmpty ||
                    !suffix.allSatisfy(safeMetadataSuffixes.contains) {
                    return true
                }
            }
            let compactMatch = compactCredentialComponentMatch(
                components[index],
                credentialMarkers: compactCredentialComponents
            )
            if compactMatch.found {
                guard let compactSuffix = compactMatch.suffix else {
                    return true
                }
                var suffix: [String] = []
                if !compactSuffix.isEmpty {
                    suffix.append(compactSuffix)
                }
                suffix.append(contentsOf: components[(index + 1)...])
                if suffix.isEmpty ||
                    !suffix.allSatisfy(safeMetadataSuffixes.contains) {
                    return true
                }
            }
            guard index + 1 < components.endIndex else {
                continue
            }
            let pair = components[index] + " " + components[index + 1]
            if credentialPairs.contains(pair) ||
                crossComponentCredentialMatch(
                    left: components[index],
                    right: components[index + 1],
                    credentialMarkers: compactCredentialComponents
                ) {
                let suffix = components[(index + 2)...]
                if suffix.isEmpty ||
                    !suffix.allSatisfy(safeMetadataSuffixes.contains) {
                    return true
                }
            }
        }
        return false
    }

    private static func compactCredentialComponentMatch(
        _ compact: String,
        credentialMarkers: [String]
    ) -> (found: Bool, suffix: String?) {
        var ranges: [Range<String.Index>] = []
        var cursor = compact.startIndex
        while cursor < compact.endIndex {
            var matchedRange: Range<String.Index>?
            for marker in credentialMarkers
            where compact[cursor...].hasPrefix(marker) {
                matchedRange = cursor..<compact.index(
                    cursor,
                    offsetBy: marker.count
                )
                break
            }
            if let matchedRange {
                ranges.append(matchedRange)
                cursor = matchedRange.upperBound
            } else {
                cursor = compact.index(after: cursor)
            }
        }

        guard !ranges.isEmpty else {
            return (false, nil)
        }
        guard ranges.count == 1, let range = ranges.first else {
            return (true, nil)
        }
        return (true, String(compact[range.upperBound...]))
    }

    private static func crossComponentCredentialMatch(
        left: String,
        right: String,
        credentialMarkers: [String]
    ) -> Bool {
        for marker in credentialMarkers where marker.count > 1 {
            for offset in 1..<marker.count {
                let boundary = marker.index(
                    marker.startIndex,
                    offsetBy: offset
                )
                let prefix = String(marker[..<boundary])
                let suffix = String(marker[boundary...])
                let pluralSuffix = suffix.hasSuffix("KEY")
                    ? suffix + "S"
                    : nil
                if left.hasSuffix(prefix),
                   right == suffix || right == pluralSuffix {
                    return true
                }
            }
        }
        return false
    }

    private static func infoFieldComponents(_ field: String) -> [String] {
        let characters = Array(field)
        var components: [String] = []
        var current = ""

        func flushCurrent() {
            guard !current.isEmpty else {
                return
            }
            components.append(current.uppercased())
            current.removeAll(keepingCapacity: true)
        }

        for index in characters.indices {
            let character = characters[index]
            guard character.isLetter || character.isNumber else {
                flushCurrent()
                continue
            }

            let previous = index > characters.startIndex
                ? characters[index - 1]
                : nil
            let next = index < characters.index(before: characters.endIndex)
                ? characters[index + 1]
                : nil
            let beginsNewComponent =
                !current.isEmpty &&
                character.isUppercase &&
                (previous?.isLowercase == true ||
                    previous?.isNumber == true ||
                    (previous?.isUppercase == true &&
                        next?.isLowercase == true))
            if beginsNewComponent {
                flushCurrent()
            }
            current.append(character)
        }
        flushCurrent()
        return components
    }
}
