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
            startSingle: { [weak self] in self?.openScanner(mode: .single) },
            startMulti: { [weak self] in self?.openScanner(mode: .multi) },
            insertPending: { [weak self] in self?.insertPendingIfAny() },
            nextKeyboard: { [weak self] in self?.advanceToNextInputMode() },
            insertText: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            deleteBackward: { [weak self] in self?.textDocumentProxy.deleteBackward() },
            insertNewline: { [weak self] in self?.textDocumentProxy.insertText("\n") }
        )
        let host = UIHostingController(rootView: root)
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
        guard let url = URLRoutes.scanURL(mode: mode) else { return }
        if #available(iOSApplicationExtension 13.0, *) {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            self.extensionContext?.open(url, completionHandler: { _ in })
        }
    }
}

struct KeyboardRootView: View {
    let startSingle: () -> Void
    let startMulti: () -> Void
    let insertPending: () -> Void
    let nextKeyboard: () -> Void
    let insertText: (String) -> Void
    let deleteBackward: () -> Void
    let insertNewline: () -> Void

    @State private var lastCount: Int = 0

    var body: some View {
        // Scan bar
        HStack(spacing: 12) {
            Button(action: startSingle) {
                Label("Skan 1", systemImage: "barcode.viewfinder")
            }
            .buttonStyle(.borderedProminent)

            Button(action: startMulti) {
                Label("Skan wiele", systemImage: "square.stack.3d.up")
            }
            .buttonStyle(.bordered)

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
        .padding(8)
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
