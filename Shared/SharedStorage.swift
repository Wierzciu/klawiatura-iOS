import Foundation

public enum ScanMode: String, Codable, Identifiable {
    case single
    case multi
    public var id: String { rawValue }
}

public struct ScannedItem: Codable, Equatable {
    public let value: String
    public let symbology: String?
    public let date: Date

    public init(value: String, symbology: String?, date: Date = Date()) {
        self.value = value
        self.symbology = symbology
        self.date = date
    }
}

public enum SharedStorage {
    // ZMIEŃ NA SWOJĄ GRUPĘ APP GROUPS!
    public static let appGroupIdentifier: String = "group.pl.twojefirma.klawiatura"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private enum Keys {
        static let pendingScans = "pendingScans"
        static let lastMode = "lastScanMode"
    }

    public static func savePending(scans: [ScannedItem]) {
        guard let defaults else { return }
        do {
            let data = try JSONEncoder().encode(scans)
            defaults.set(data, forKey: Keys.pendingScans)
        } catch {
            #if DEBUG
            print("SharedStorage: encode error", error)
            #endif
        }
    }

    public static func appendPending(_ item: ScannedItem) {
        var current = loadPending()
        current.append(item)
        savePending(scans: current)
    }

    public static func loadPending() -> [ScannedItem] {
        guard let defaults, let data = defaults.data(forKey: Keys.pendingScans) else { return [] }
        do {
            return try JSONDecoder().decode([ScannedItem].self, from: data)
        } catch {
            #if DEBUG
            print("SharedStorage: decode error", error)
            #endif
            return []
        }
    }

    @discardableResult
    public static func fetchAndClear() -> [ScannedItem] {
        let items = loadPending()
        clearPending()
        return items
    }

    public static func clearPending() {
        defaults?.removeObject(forKey: Keys.pendingScans)
    }

    public static func set(lastMode: ScanMode) {
        defaults?.set(lastMode.rawValue, forKey: Keys.lastMode)
    }

    public static func getLastMode() -> ScanMode? {
        guard let raw = defaults?.string(forKey: Keys.lastMode) else { return nil }
        return ScanMode(rawValue: raw)
    }
}
