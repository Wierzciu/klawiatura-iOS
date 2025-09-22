import CoreData

public extension ScanList {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ScanList> {
        NSFetchRequest<ScanList>(entityName: "ScanList")
    }

    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var createdAt: Date
}

extension ScanList: Identifiable {}
