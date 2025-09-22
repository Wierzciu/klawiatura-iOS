import Foundation
import CoreData

/// Provides access to the Core Data stack used across the application.
final class PersistenceController {
    static let shared = PersistenceController()
    static let preview: PersistenceController = {
        PersistenceController(inMemory: true)
    }()

    static func makeInMemory() -> PersistenceController {
        PersistenceController(inMemory: true)
    }

    static func makePersistent(at url: URL) -> PersistenceController {
        PersistenceController(storeURL: url)
    }

    let container: NSPersistentContainer

    private init(inMemory: Bool = false, storeURL: URL? = nil) {
        container = NSPersistentContainer(name: "ScanDB")

        if let storeURL {
            let description = NSPersistentStoreDescription(url: storeURL)
            container.persistentStoreDescriptions = [description]
        } else if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        // Enable lightweight migration
        for description in container.persistentStoreDescriptions {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { _, error in
            if let error {
                NSLog("Unresolved error loading persistent stores: %@", error.localizedDescription)
                assertionFailure("Unresolved error loading persistent stores: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Saves changes on the provided context (or the viewContext when nil).
    func save(context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext

        context.performAndWait {
            guard context.hasChanges else { return }

            do {
                try context.save()
            } catch {
                NSLog("Failed to save context: %@", error.localizedDescription)
                assertionFailure("Failed to save context: \(error)")
            }
        }
    }
}
