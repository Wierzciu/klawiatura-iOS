import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    private var hosting: UIHostingController<KeyboardRootView>?
    
    override var primaryLanguage: String? {
        get { "pl-PL" }
        set { /* keep fixed language; ignore external set */ }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = KeyboardRootView(
            isFullAccess: self.hasFullAccess,
            startSingle: { [weak self] in self?.openScanner(mode: .single) },
            startMulti: { [weak self] in self?.openScanner(mode: .multi) },
            insertPending: { [weak self] in self?.insertPendingIfAny() },
            nextKeyboard: { [weak self] in self?.advanceToNextInputMode() },
            insertText: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            deleteBackward: { [weak self] in self?.textDocumentProxy.deleteBackward() },
            insertNewline: { [weak self] in self?.textDocumentProxy.insertText("\n") }
        )
        let host = UIHostingController(rootView: root)
        if #available(iOS 16.0, *) {
            host.sizingOptions = .intrinsicContentSize
        }
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hosting = host
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        insertPendingIfAny()
    }

    func insertPendingIfAny() {
        let items = SharedStorage.fetchAndClear()
        guard !items.isEmpty else { return }
        let text = TextInsertionFormatter.joinedText(for: items)
        textDocumentProxy.insertText(text)
    }

    func openScanner(mode: ScanMode) {
        print("🔍 KeyboardViewController: openScanner called with mode: \(mode)")
        print("ℹ️ KeyboardViewController: hasFullAccess = \(hasFullAccess)")
        
        // Check if we have full access
        guard hasFullAccess else {
            print("❌ KeyboardViewController: No full access - cannot open URLs")
            showFullAccessAlert()
            return
        }
        
        guard let url = URLRoutes.scanURL(mode: mode) else {
            print("❌ KeyboardViewController: Failed to create URL")
            return
        }
        
        print("🔗 KeyboardViewController: Generated URL: \(url)")
        
        guard let extensionContext = self.extensionContext else {
            print("❌ KeyboardViewController: extensionContext is nil")
            return
        }
        
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
            
            print("📱 KeyboardViewController: Calling extensionContext.open with URL: \(url.absoluteString)")
            extensionContext.open(url) { [weak self] success in
                print("✅ KeyboardViewController: extensionContext.open completed with success: \(success)")
                if !success {
                    print("⚠️ KeyboardViewController: Failed to open URL. Ensure Full Access is enabled and the host app is installed with the 'barcodekb' URL scheme.")
                    self?.showOpenFailedAlert()
                }
            }
        }
    }
    
    private func showFullAccessAlert() {
        let alert = UIAlertController(
            title: "Wymagany pełny dostęp",
            message: "Aby używać funkcji skanowania, włącz 'Pełny dostęp' dla tej klawiatury w Ustawieniach > Ogólne > Klawiatura > Klawiatury.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showOpenFailedAlert() {
        let alert = UIAlertController(
            title: "Nie udało się otworzyć aplikacji",
            message: "Sprawdź, czy aplikacja jest zainstalowana i czy ma zdefiniowany schemat URL 'barcodekb'. Następnie spróbuj ponownie.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

struct KeyboardRootView: View {
    let isFullAccess: Bool
    let startSingle: () -> Void
    let startMulti: () -> Void
    let insertPending: () -> Void
    let nextKeyboard: () -> Void
    let insertText: (String) -> Void
    let deleteBackward: () -> Void
    let insertNewline: () -> Void

    @State private var lastCount: Int = 0

    var body: some View {
        VStack(spacing: 6) {
            if !isFullAccess {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Włącz 'Pełny dostęp' w Ustawieniach, aby uruchomić skanowanie.")
                }
                .font(.footnote)
                .foregroundColor(.white)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.orange)
                .cornerRadius(8)
                .padding(.horizontal, 8)
            }
            // Scan bar (compact)
            HStack(spacing: 12) {
            
if let url = URLRoutes.scanURL(mode: SharedStorage.getLastMode() ?? .single) {
    Link(destination: url) {
        Label("Skanuj", systemImage: "barcode.viewfinder")
    }
    .simultaneousGesture(TapGesture().onEnded {
        let mode = SharedStorage.getLastMode() ?? .single
        SharedStorage.set(lastMode: mode)
    })
    .buttonStyle(.borderedProminent)
    .controlSize(.small)
    .font(.callout)
} else {
    Button(action: { /* fallback */ }) {
        Label("Skanuj", systemImage: "barcode.viewfinder")
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.small)
    .font(.callout)
}


            Spacer()

            if lastCount > 0 {
                Label("\(lastCount)", systemImage: "tray.full")
                    .padding(6)
            }

            Button(action: { insertPending(); lastCount = 0 }) {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.plain)

            Button(action: nextKeyboard) {
                Image(systemName: "globe")
            }
            .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .onAppear { lastCount = SharedStorage.loadPending().count }

            // System-like keyboard body
            SystemLikeKeyboardView(
                insertText: insertText,
                deleteBackward: deleteBackward,
                advanceToNext: nextKeyboard,
                insertNewline: insertNewline
            )
            .padding(.horizontal, 6)
        }
    }
}
