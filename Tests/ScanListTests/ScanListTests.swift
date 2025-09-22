import XCTest
import CoreData
import AVFoundation
@testable import BarcodeKeyboard

final class ScanListTests: XCTestCase {
    func testAddManualSavesImmediately() throws {
        let controller = PersistenceController.makeInMemory()
        let telemetry = MockTelemetry()
        let repository = CoreDataScanRepository(persistenceController: controller, context: controller.container.viewContext)
        let service = ScanService(repository: repository, telemetry: telemetry)

        let dto = try service.addScan(listId: "list-1", codeRaw: "12345", codeType: "MANUAL", label: "Test")
        XCTAssertEqual(dto.codeRaw, "12345")

        let fetched = try service.getItems(listId: "list-1")
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.label, "Test")
        XCTAssertEqual(telemetry.loggedSuccess.count, 1)
    }

    func testDebounceDuplicateScansWithin1_5s() throws {
        let controller = PersistenceController.makeInMemory()
        let telemetry = MockTelemetry()
        let repository = CoreDataScanRepository(persistenceController: controller, context: controller.container.viewContext)

        var dates: [Date] = [Date(), Date().addingTimeInterval(1)]
        let service = ScanService(repository: repository, debounceInterval: 1.5, clock: { dates.removeFirst() }, telemetry: telemetry)

        _ = try service.addScan(listId: "list-1", codeRaw: "123", codeType: "QR", label: nil)
        XCTAssertThrowsError(try service.addScan(listId: "list-1", codeRaw: "123", codeType: "QR", label: nil)) { error in
            guard case ScanServiceError.duplicateWithinInterval = error else {
                return XCTFail("Expected duplicate error, got \(error)")
            }
        }
        XCTAssertEqual(telemetry.loggedDuplicates.count, 1)

        let fetched = try service.getItems(listId: "list-1")
        XCTAssertEqual(fetched.count, 1)
    }

    func testLoadsItemsOnInitAfterAppRestart() throws {
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("ScanListTests-\(UUID().uuidString)").appendingPathExtension("sqlite")
        defer { removeStoreFiles(at: storeURL) }

        do {
            let controller = PersistenceController.makePersistent(at: storeURL)
            let repository = CoreDataScanRepository(persistenceController: controller, context: controller.container.viewContext)
            let service = ScanService(repository: repository)
            _ = try service.addScan(listId: "list-A", codeRaw: "111", codeType: "QR", label: "First")
        }

        let controllerReloaded = PersistenceController.makePersistent(at: storeURL)
        let repositoryReloaded = CoreDataScanRepository(persistenceController: controllerReloaded, context: controllerReloaded.container.viewContext)
        let serviceReloaded = ScanService(repository: repositoryReloaded)

        let fetched = try serviceReloaded.getItems(listId: "list-A")
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.label, "First")
    }

    func testExportsValidCSV() throws {
        let now = Date()
        let items = [
            ScanItemDTO(id: UUID(), listId: "L1", codeRaw: "123", codeType: "QR", label: "A", createdAt: now, meta: nil),
            ScanItemDTO(id: UUID(), listId: "L1", codeRaw: "456", codeType: "EAN", label: "B", createdAt: now.addingTimeInterval(-60), meta: nil)
        ]

        let url = try CSVExporter.export(items)
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        XCTAssertEqual(lines.first, "id,listId,codeRaw,codeType,label,createdAt")
        XCTAssertEqual(lines.count, items.count + 1)
    }

    func testPermissionDeniedShowsManualFallback() throws {
        let controller = PersistenceController.makeInMemory()
        let repository = CoreDataScanRepository(persistenceController: controller, context: controller.container.viewContext)
        let service = ScanService(repository: repository)
        let provider = MockCameraPermissionProvider(status: .denied)
        let viewModel = ScanListViewModel(listId: "list-1", service: service, cameraPermissionProvider: provider)

        viewModel.startScanner()

        XCTAssertTrue(viewModel.cameraPermissionDenied)
        XCTAssertTrue(viewModel.showManualFallbackSuggestion)

        viewModel.prepareManualEntry()
        XCTAssertTrue(viewModel.isManualEntryPresented)
    }

    private func removeStoreFiles(at sqliteURL: URL) {
        let fm = FileManager.default
        let base = sqliteURL.deletingPathExtension().lastPathComponent
        let dir = sqliteURL.deletingLastPathComponent()
        let patterns = [
            sqliteURL,
            dir.appendingPathComponent(base + ".sqlite-wal"),
            dir.appendingPathComponent(base + ".sqlite-shm"),
            dir.appendingPathComponent(base)
        ]
        for url in patterns {
            try? fm.removeItem(at: url)
        }
    }
}

private final class MockTelemetry: ScanTelemetry {
    private(set) var loggedSuccess: [(String, String, String)] = []
    private(set) var loggedDuplicates: [(String, String, String)] = []
    private(set) var loggedErrors: [(String, String, String)] = []

    func scanSuccess(listId: String, codeRaw: String, codeType: String) {
        loggedSuccess.append((listId, codeRaw, codeType))
    }

    func scanDuplicate(listId: String, codeRaw: String, codeType: String) {
        loggedDuplicates.append((listId, codeRaw, codeType))
    }

    func scanError(listId: String, codeRaw: String, codeType: String, error: Error) {
        loggedErrors.append((listId, codeRaw, codeType))
    }
}

private final class MockCameraPermissionProvider: CameraPermissionProviding {
    private let status: AVAuthorizationStatus

    init(status: AVAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() -> AVAuthorizationStatus {
        status
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        completion(status == .authorized)
    }
}
