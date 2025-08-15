import SwiftUI

struct ContentView: View {
    @State private var showScanner: ScanMode? = nil
    @State private var lastSaved: [ScannedItem] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Button {
                    showScanner = SharedStorage.getLastMode() ?? .single
                } label: {
                    Label("Skanuj", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(.borderedProminent)

                if !lastSaved.isEmpty {
                    List(lastSaved, id: \.date) { item in
                        VStack(alignment: .leading) {
                            Text(item.value).font(.headline)
                            if let sym = item.symbology { Text(sym).font(.caption).foregroundColor(.secondary) }
                        }
                    }
                    .frame(maxHeight: 280)
                }

                Spacer()

                Text("App Group: \(SharedStorage.appGroupIdentifier)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Skaner kodów")
            .sheet(item: $showScanner) { mode in
                ScannerScreen(mode: mode) { items in
                    SharedStorage.savePending(scans: items)
                    lastSaved = items
                    showScanner = nil
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
