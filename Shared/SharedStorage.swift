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
    // Jednolita App Group współdzielona przez appkę i rozszerzenie
    public static let appGroupIdentifier: String = "group.com.wierzciu.klawiatura"

    private static var defaults: UserDefaults? {
        let d = UserDefaults(suiteName: appGroupIdentifier)
        #if DEBUG
        if d == nil { print("❌ SharedStorage: App Group not available: \(appGroupIdentifier)") }
        #endif
        return d
    }

    private enum Keys {
        static let pendingScans = "pendingScans"
        static let lastMode = "lastScanMode"
        static let lastListId = "lastListId"
        static let knownListIds = "knownListIds"
    }

    public static func savePending(scans: [ScannedItem]) {
        guard let defaults else {
            #if DEBUG
            print("❌ SharedStorage.savePending: defaults=nil")
            #endif
            return
        }
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

    public static func set(lastListId: String) {
        defaults?.set(lastListId, forKey: Keys.lastListId)
    }

    public static func getLastListId() -> String? {
        defaults?.string(forKey: Keys.lastListId)
    }

    public static func addKnownListId(_ id: String) {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var set = Set(getKnownListIds())
        set.insert(id)
        defaults?.set(Array(set), forKey: Keys.knownListIds)
    }

    public static func getKnownListIds() -> [String] {
        guard let arr = defaults?.array(forKey: Keys.knownListIds) as? [String] else { return [] }
        return Array(Set(arr)).sorted()
    }

    public static func removeKnownListId(_ id: String) {
        var set = Set(getKnownListIds())
        set.remove(id)
        defaults?.set(Array(set), forKey: Keys.knownListIds)
    }
}
