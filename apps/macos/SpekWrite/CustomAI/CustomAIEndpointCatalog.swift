import Foundation

enum CustomAIEndpointCatalog {
    static func httpsEndpoint(
        for selection: CustomAIRuntimeSelection
    ) throws -> URL {
        try endpoint(for: selection, allowedScheme: "https")
    }

    static func wssEndpoint(
        for selection: CustomAIRuntimeSelection
    ) throws -> URL {
        try endpoint(for: selection, allowedScheme: "wss")
    }

    private static func endpoint(
        for selection: CustomAIRuntimeSelection,
        allowedScheme: String
    ) throws -> URL {
        guard
            let rawValue = selection.values[.endpointURL]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawValue.isEmpty,
            let components = URLComponents(string: rawValue),
            components.scheme == allowedScheme,
            components.host?.isEmpty == false,
            components.user == nil,
            components.password == nil,
            components.fragment == nil,
            let url = components.url
        else {
            throw CustomAIProviderError.invalidConfiguration
        }
        return url
    }
}
