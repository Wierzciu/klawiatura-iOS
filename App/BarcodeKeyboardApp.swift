import SwiftUI

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
                .onOpenURL(perform: handle)
                .onAppear {
                    appDelegate.onDeepLink = { url in handle(url) }
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
