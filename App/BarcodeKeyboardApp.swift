import SwiftUI
import CoreData
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static let shared = AppDelegate()
    var onDeepLink: ((URL) -> Void)?

    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("🔗 AppDelegate: application(_:open:options:) received URL: \(url)")
        onDeepLink?(url)
        return true
    }
}


@main
struct BarcodeKeyboardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var presentedMode: ScanMode? = nil
    private let persistenceController = PersistenceController.shared
    private let scanService = ScanPersistenceService.shared
    private let defaultListId = ScanPersistenceService.defaultListId

    @MainActor private func handle(_ url: URL) {
        print("🔗 BarcodeKeyboardApp: Handling URL: \(url)")
        if let parsed = URLRoutes.parse(url), parsed.action == "scan" {
            print("✅ BarcodeKeyboardApp: Parsed successfully, mode: \(parsed.mode)")
            presentedMode = parsed.mode
        } else {
            print("❌ BarcodeKeyboardApp: Failed to parse URL")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onOpenURL(perform: handle)
                .onAppear {
                    appDelegate.onDeepLink = { url in handle(url) }
                }
                .sheet(item: $presentedMode) { mode in
                    ScannerScreen(mode: mode) { items in
                        let targetList = SharedStorage.getLastListId() ?? defaultListId
                        scanService.save(scannedItems: items, listId: targetList)
                        SharedStorage.addKnownListId(targetList)
                        SharedStorage.savePending(scans: items)
                        // Fallback bridge for keyboards: named pasteboard
                        let text = TextInsertionFormatter.joinedText(for: items)
                        PasteboardBridge.write(text)
                        SharedStorage.set(lastMode: mode)
                        presentedMode = nil
                    }
                }
        }
    }
}
