import Foundation
import CoreData

/// Handles persistence of scan results with deduplication.
final class ScanPersistenceService {
    static let shared = ScanPersistenceService()
    static let defaultListId = "default-list"

    private let persistenceController: PersistenceController
    private let calendar: Calendar

    init(persistenceController: PersistenceController = .shared,
         calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.persistenceController = persistenceController
        self.calendar = calendar
    }

    @discardableResult
    func save(scannedItems: [ScannedItem], listId: String, context: NSManagedObjectContext? = nil) -> [ScanItem] {
        var savedItems: [ScanItem] = []
        let context = context ?? persistenceController.container.viewContext

        // Zbierz meta z encji ScanList (itemName, supplierName)
        let listMeta = self.metaForList(named: listId, context: context)

        for item in scannedItems {
            let stored = upsert(
                listId: listId,
                codeRaw: item.value,
                codeType: item.symbology ?? "unknown",
                label: nil,
                createdAt: item.date,
                meta: listMeta,
                context: context
            )

            if let stored { savedItems.append(stored) }
        }

        return savedItems
    }

    private func metaForList(named name: String, context: NSManagedObjectContext) -> Data? {
        let req = NSFetchRequest<NSManagedObject>(entityName: "ScanList")
        req.predicate = NSPredicate(format: "name == %@", name)
        req.fetchLimit = 1
        guard let list = try? context.fetch(req).first else { return nil }
        let itemName = list.value(forKey: "itemName") as? String
        let supplierName = list.value(forKey: "supplierName") as? String
        var dict: [String: String] = [:]
        if let itemName, !itemName.isEmpty { dict["itemName"] = itemName }
        if let supplierName, !supplierName.isEmpty { dict["supplierName"] = supplierName }
        guard !dict.isEmpty else { return nil }
        return try? JSONSerialization.data(withJSONObject: dict, options: [])
    }

    @discardableResult
    func upsert(listId: String,
                codeRaw: String,
                codeType: String,
                label: String?,
                createdAt: Date,
                meta: Data?,
                context: NSManagedObjectContext? = nil) -> ScanItem? {
        let context = context ?? persistenceController.container.viewContext
        var result: ScanItem?
        var shouldSave = false

        context.performAndWait {
            let fetchRequest = ScanItem.fetchRequest()
            fetchRequest.fetchLimit = 1
            let (start, end) = self.secondInterval(for: createdAt)
            fetchRequest.predicate = NSPredicate(
                format: "listId == %@ AND codeRaw == %@ AND codeType == %@ AND createdAt >= %@ AND createdAt < %@",
                listId, codeRaw, codeType, start as NSDate, end as NSDate
            )

            do {
                if let existing = try context.fetch(fetchRequest).first {
                    if existing.label != label {
                        existing.label = label
                        shouldSave = true
                    }
                    if existing.meta != meta {
                        existing.meta = meta
                        shouldSave = true
                    }
                    result = existing
                } else {
                    let newItem = ScanItem(context: context)
                    newItem.id = UUID()
                    newItem.listId = listId
                    newItem.codeRaw = codeRaw
                    newItem.codeType = codeType
                    newItem.label = label
                    newItem.createdAt = createdAt
                    newItem.meta = meta
                    result = newItem
                    shouldSave = true
                }
            } catch {
                NSLog("Failed to fetch ScanItem for deduplication: %@", error.localizedDescription)
            }
        }

        if shouldSave {
            persistenceController.save(context: context)
        }

        return result
    }

    private func secondInterval(for date: Date) -> (Date, Date) {
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let start = calendar.date(from: calendar.dateComponents(components, from: date)) ?? date
        let end = calendar.date(byAdding: .second, value: 1, to: start) ?? date.addingTimeInterval(1)
        return (start, end)
    }
}
