import Foundation
#if canImport(OSLog)
import OSLog
#endif

final class ScanService {
    private struct DebounceEntry {
        let codeRaw: String
        let codeType: String
        let timestamp: Date
    }

    private let repository: ScanRepository
    private let debounceInterval: TimeInterval
    private let clock: () -> Date
    private var lastEntries: [String: DebounceEntry] = [:]
    private let queue = DispatchQueue(label: "ScanService.queue", qos: .userInitiated)
    private let telemetry: ScanTelemetry

    init(repository: ScanRepository = CoreDataScanRepository(),
         debounceInterval: TimeInterval = 1.5,
         clock: @escaping () -> Date = Date.init,
         telemetry: ScanTelemetry = DefaultScanTelemetry()) {
        self.repository = repository
        self.debounceInterval = debounceInterval
        self.clock = clock
        self.telemetry = telemetry
    }

    func addScan(listId: String, codeRaw: String, codeType: String, label: String?) throws -> ScanItemDTO {
        let sanitizedListId = listId.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedCodeRaw = codeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedCodeType = codeType.trimmingCharacters(in: .whitespacesAndNewlines)

        try validateNonEmpty(value: sanitizedListId, field: "listId")
        try validateNonEmpty(value: sanitizedCodeRaw, field: "codeRaw")
        try validateNonEmpty(value: sanitizedCodeType, field: "codeType")

        let now = clock()
        let cacheKey = sanitizedListId
        let shouldPersist = queue.sync { () -> Bool in
            if let entry = lastEntries[cacheKey],
               entry.codeRaw == sanitizedCodeRaw,
               entry.codeType == sanitizedCodeType,
               now.timeIntervalSince(entry.timestamp) < debounceInterval {
                return false
            }

            lastEntries[cacheKey] = DebounceEntry(codeRaw: sanitizedCodeRaw, codeType: sanitizedCodeType, timestamp: now)
            return true
        }

        guard shouldPersist else {
            telemetry.scanDuplicate(listId: sanitizedListId, codeRaw: sanitizedCodeRaw, codeType: sanitizedCodeType)
            throw ScanServiceError.duplicateWithinInterval
        }

        let dto = ScanItemDTO(
            id: UUID(),
            listId: sanitizedListId,
            codeRaw: sanitizedCodeRaw,
            codeType: sanitizedCodeType,
            label: label,
            createdAt: now,
            meta: nil
        )

        do {
            try repository.add(item: dto)
            telemetry.scanSuccess(listId: sanitizedListId, codeRaw: sanitizedCodeRaw, codeType: sanitizedCodeType)
        } catch {
            telemetry.scanError(listId: sanitizedListId, codeRaw: sanitizedCodeRaw, codeType: sanitizedCodeType, error: error)
            queue.sync {
                if let entry = lastEntries[cacheKey], entry.timestamp == now {
                    lastEntries.removeValue(forKey: cacheKey)
                }
            }
            throw error
        }
        return dto
    }

    func getItems(listId: String) throws -> [ScanItemDTO] {
        try repository.listItems(for: listId)
    }

    func removeItem(_ id: UUID) throws {
        try repository.delete(id: id)
    }

    func updateLabel(_ id: UUID, label: String?) throws {
        try repository.updateLabel(id: id, label: label)
    }

    private func validateNonEmpty(value: String, field: String) throws {
        guard !value.isEmpty else {
            throw ScanServiceError.invalidValue(field: field)
        }
    }
}

enum ScanServiceError: Error, LocalizedError {
    case invalidValue(field: String)
    case duplicateWithinInterval

    var errorDescription: String? {
        switch self {
        case .invalidValue(let field):
            return "Invalid value for \(field)."
        case .duplicateWithinInterval:
            return "Duplicate scan ignored."
        }
    }
}

protocol ScanTelemetry {
    func scanSuccess(listId: String, codeRaw: String, codeType: String)
    func scanDuplicate(listId: String, codeRaw: String, codeType: String)
    func scanError(listId: String, codeRaw: String, codeType: String, error: Error)
}

struct DefaultScanTelemetry: ScanTelemetry {
#if canImport(OSLog)
    private let logger = Logger(subsystem: "pl.twojefirma.klawiatura", category: "ScanService")
#endif

    func scanSuccess(listId: String, codeRaw: String, codeType: String) {
#if canImport(OSLog)
        logger.log("scan_success list=\(listId, privacy: .public) code=\(codeRaw, privacy: .private(mask: .hash)) type=\(codeType, privacy: .public)")
#else
        print("scan_success list=\(listId) code=\(codeRaw) type=\(codeType)")
#endif
    }

    func scanDuplicate(listId: String, codeRaw: String, codeType: String) {
#if canImport(OSLog)
        logger.log("scan_duplicate list=\(listId, privacy: .public) code=\(codeRaw, privacy: .private(mask: .hash)) type=\(codeType, privacy: .public)")
#else
        print("scan_duplicate list=\(listId) code=\(codeRaw) type=\(codeType)")
#endif
    }

    func scanError(listId: String, codeRaw: String, codeType: String, error: Error) {
#if canImport(OSLog)
        logger.error("scan_error list=\(listId, privacy: .public) code=\(codeRaw, privacy: .private(mask: .hash)) type=\(codeType, privacy: .public) error=\(String(describing: error), privacy: .public)")
#else
        print("scan_error list=\(listId) code=\(codeRaw) type=\(codeType) error=\(error)")
#endif
    }
}
