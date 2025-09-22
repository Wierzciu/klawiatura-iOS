import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CSVExporter {
    static func export(_ items: [ScanItemDTO],
                       delimiter: String = ",",
                       includeHeader: Bool = true) throws -> URL {
        let header = ["id", "listId", "codeRaw", "codeType", "label", "createdAt"].joined(separator: delimiter)
        let formatter = ISO8601DateFormatter()

        let body = items.map { item in
            [
                item.id.uuidString,
                item.listId,
                item.codeRaw,
                item.codeType,
                item.label ?? "",
                formatter.string(from: item.createdAt)
            ].map { escape($0, delimiter: delimiter) }.joined(separator: delimiter)
        }

        var lines: [String] = []
        if includeHeader {
            lines.append(header)
        }
        lines.append(contentsOf: body)

        let csvString = lines.joined(separator: "\n")
        guard let data = csvString.data(using: .utf8) else {
            throw CSVExporterError.encodingFailed
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("scan-items-\(UUID().uuidString).csv")
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    private static func escape(_ value: String, delimiter: String) -> String {
        guard !value.isEmpty else { return "" }

        var needsQuotes = value.contains(delimiter) || value.contains("\n") || value.contains("\"")
        var escaped = value.replacingOccurrences(of: "\"", with: "\"\"")

        if !needsQuotes {
            needsQuotes = escaped.contains("\r")
        }

        return needsQuotes ? "\"\(escaped)\"" : escaped
    }
}

enum CSVExporterError: Error, LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode CSV data."
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url])
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
