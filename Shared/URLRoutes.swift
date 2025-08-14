import Foundation

struct URLRoutes {
    struct Parsed {
        let action: String
        let mode: ScanMode
    }

    private static let scheme: String = "barcodekb"
    private static let scanActionHost: String = "scan"

    static func scanURL(mode: ScanMode) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = scanActionHost
        components.queryItems = [URLQueryItem(name: "mode", value: mode.rawValue)]
        return components.url
    }

    static func parse(_ url: URL) -> Parsed? {
        guard url.scheme == scheme else { return nil }
        let action = url.host ?? ""
        guard action == scanActionHost else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let modeRaw = components?.queryItems?.first { $0.name == "mode" }?.value
        let parsedMode = modeRaw.flatMap { ScanMode(rawValue: $0) }
            ?? SharedStorage.getLastMode()
            ?? .single

        return Parsed(action: action, mode: parsedMode)
    }
}


