import Foundation

public enum TextInsertionFormatter {
    public static func joinedText(for values: [String]) -> String {
        values.joined(separator: "\n")
    }

    public static func joinedText(for items: [ScannedItem]) -> String {
        joinedText(for: items.map { $0.value })
    }
}

