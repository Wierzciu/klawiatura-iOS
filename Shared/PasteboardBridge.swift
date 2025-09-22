import UIKit

enum PasteboardBridge {
    private static let name = UIPasteboard.Name("barcodekb.scans")

    static func write(_ string: String) {
        guard !string.isEmpty else { return }
        let pb = UIPasteboard(name: name, create: true)
        pb?.string = string
    }

    static func readAndClear() -> String? {
        guard let pb = UIPasteboard(name: name, create: false) else { return nil }
        let value = pb.string
        if value != nil { pb.string = nil }
        return value?.isEmpty == false ? value : nil
    }
}
