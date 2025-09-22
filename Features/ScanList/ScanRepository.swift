import Foundation
import CoreData

struct ScanItemDTO: Identifiable, Codable {
    var id: UUID
    var listId: String
    var codeRaw: String
    var codeType: String
    var label: String?
    var createdAt: Date
    var meta: [String: String]?
}

protocol ScanRepository {
    func add(item: ScanItemDTO) throws
    func listItems(for listId: String) throws -> [ScanItemDTO]
    func delete(id: UUID) throws
    func updateLabel(id: UUID, label: String?) throws
}

enum ScanRepositoryError: Error, LocalizedError {
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .persistenceFailed:
            return "Saving scan item failed."
        }
    }
}

final class CoreDataScanRepository: ScanRepository {
    private let persistenceController: PersistenceController
    private let context: NSManagedObjectContext

    init(persistenceController: PersistenceController = .shared,
         context: NSManagedObjectContext? = nil) {
        self.persistenceController = persistenceController
        self.context = context ?? persistenceController.container.viewContext
    }

    func add(item: ScanItemDTO) throws {
        try perform {
            let entity = ScanItem(context: context)
            apply(dto: item, to: entity)
        }
        try persistChangesIfNeeded()
    }

    func listItems(for listId: String) throws -> [ScanItemDTO] {
        var results: [ScanItemDTO] = []

        try perform {
            let request = ScanItem.fetchRequest()
            request.predicate = NSPredicate(format: "listId == %@", listId)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ScanItem.createdAt, ascending: false)]
            let items = try context.fetch(request)
            results = items.compactMap { try? dto(from: $0) }
        }

        return results
    }

    func delete(id: UUID) throws {
        var deleted = false
        try perform {
            if let item = try find(by: id) {
                context.delete(item)
                deleted = true
            }
        }
        if deleted {
            try persistChangesIfNeeded()
        }
    }

    func updateLabel(id: UUID, label: String?) throws {
        var updated = false
        try perform {
            if let item = try find(by: id) {
                item.label = label
                updated = true
            }
        }
        if updated {
            try persistChangesIfNeeded()
        }
    }

    private func find(by id: UUID) throws -> ScanItem? {
        let request = ScanItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func perform(_ block: () throws -> Void) throws {
        var caughtError: Error?
        context.performAndWait {
            do {
                try block()
            } catch {
                caughtError = error
            }
        }
        if let error = caughtError {
            throw error
        }
    }

    private func persistChangesIfNeeded() throws {
        guard context.hasChanges else { return }
        persistenceController.save(context: context)
        if context.hasChanges {
            throw ScanRepositoryError.persistenceFailed
        }
    }

    private func apply(dto: ScanItemDTO, to entity: ScanItem) {
        entity.id = dto.id
        entity.listId = dto.listId
        entity.codeRaw = dto.codeRaw
        entity.codeType = dto.codeType
        entity.label = dto.label
        entity.createdAt = dto.createdAt
        if let meta = dto.meta {
            entity.meta = try? JSONSerialization.data(withJSONObject: meta, options: [])
        } else {
            entity.meta = nil
        }
    }

    private func dto(from entity: ScanItem) throws -> ScanItemDTO {
        let metaData = entity.meta.flatMap { data -> [String: String]? in
            (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: String]
        }

        return ScanItemDTO(
            id: entity.id,
            listId: entity.listId,
            codeRaw: entity.codeRaw,
            codeType: entity.codeType,
            label: entity.label,
            createdAt: entity.createdAt,
            meta: metaData
        )
    }
}
