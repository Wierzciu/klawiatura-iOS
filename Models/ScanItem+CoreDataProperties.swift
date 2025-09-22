import CoreData

public extension ScanItem {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ScanItem> {
        NSFetchRequest<ScanItem>(entityName: "ScanItem")
    }

    @NSManaged var id: UUID
    @NSManaged var listId: String
    @NSManaged var codeRaw: String
    @NSManaged var codeType: String
    @NSManaged var label: String?
    @NSManaged var createdAt: Date
    @NSManaged var meta: Data?
}

extension ScanItem: Identifiable {}
