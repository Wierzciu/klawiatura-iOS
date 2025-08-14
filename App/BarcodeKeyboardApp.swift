import SwiftUI

@main
struct BarcodeKeyboardApp: App {
    @State private var presentedMode: ScanMode? = nil

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    if let parsed = URLRoutes.parse(url), parsed.action == "scan" {
                        presentedMode = parsed.mode
                    }
                }
                .sheet(item: $presentedMode) { mode in
                    ScannerScreen(mode: mode) { items in
                        SharedStorage.savePending(scans: items)
                        SharedStorage.set(lastMode: mode)
                        presentedMode = nil
                    }
                }
        }
    }
}
