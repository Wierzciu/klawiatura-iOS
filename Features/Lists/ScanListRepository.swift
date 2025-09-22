import Foundation
import CoreData

protocol ScanListRepository {
    func create(name: String) throws -> ScanList
    func fetchAll() throws -> [ScanList]
    func rename(id: UUID, newName: String) throws
    func delete(id: UUID) throws
}

final class CoreDataScanListRepository: ScanListRepository {
    private let persistenceController: PersistenceController
    private let context: NSManagedObjectContext

    init(persistenceController: PersistenceController = .shared,
         context: NSManagedObjectContext? = nil) {
        self.persistenceController = persistenceController
        self.context = context ?? persistenceController.container.viewContext
    }

    func create(name: String) throws -> ScanList {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NSError(domain: "ScanList", code: 1, userInfo: [NSLocalizedDescriptionKey: "List name cannot be empty"]) }
        var result: ScanList!
        try perform {
            let list = ScanList(context: context)
            list.id = UUID()
            list.name = trimmed
            list.createdAt = Date()
            result = list
        }
        try persistIfNeeded()
        return result
    }

    func fetchAll() throws -> [ScanList] {
        var items: [ScanList] = []
        try perform {
            let request = ScanList.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ScanList.createdAt, ascending: false)]
            items = try context.fetch(request)
        }
        return items
    }

    func rename(id: UUID, newName: String) throws {
        try perform {
            let req = ScanList.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            req.fetchLimit = 1
            if let list = try context.fetch(req).first {
                list.name = newName
            }
        }
        try persistIfNeeded()
    }

    func delete(id: UUID) throws {
        try perform {
            let req = ScanList.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            req.fetchLimit = 1
            if let list = try context.fetch(req).first {
                context.delete(list)
            }
        }
        try persistIfNeeded()
    }

    private func perform(_ block: () throws -> Void) throws {
        var caught: Error?
        context.performAndWait {
            do { try block() } catch { caught = error }
        }
        if let e = caught { throw e }
    }

    private func persistIfNeeded() throws {
        if context.hasChanges {
            persistenceController.save(context: context)
        }
    }
}
