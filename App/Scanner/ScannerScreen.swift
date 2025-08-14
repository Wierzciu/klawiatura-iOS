import SwiftUI

struct ScannerScreen: View {
    let mode: ScanMode
    let onDone: ([ScannedItem]) -> Void

    @State private var collectedItems: [ScannedItem] = []
    @State private var lastCandidateValue: String? = nil
    @State private var lockedCandidate: ScannedItem? = nil

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                scannerView
                ReticleOverlayView(isLockedOn: lockedCandidate != nil)
            }

            header
                .padding(.horizontal)
                .padding(.top, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            // Reset state when presented
            collectedItems.removeAll()
            lastCandidateValue = nil
        }
    }

    @ViewBuilder
    private var scannerView: some View {
        if DataScannerWrapper.isSupported {
            DataScannerWrapper(onCandidateChange: handleCandidate(_:))
                .ignoresSafeArea()
        } else {
            AVScannerWrapper(onCandidateChange: handleCandidate(_:))
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            HStack(spacing: 10) {
                if mode == .multi {
                    Label("\(collectedItems.count)", systemImage: "tray.full")
                        .foregroundStyle(.white)
                    Button("Dodaj") { if let c = lockedCandidate { addCandidate(c) } }
                        .buttonStyle(.bordered)
                } else {
                    Button("Zapisz") { if let c = lockedCandidate { onDone([c]) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(lockedCandidate == nil)
                }
                if mode == .multi {
                    Button("Gotowe") { onDone(collectedItems) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var title: String { mode == .single ? "Skan – pojedynczy" : "Skan – wiele" }
    private var subtitle: String { mode == .single ? "Nakieruj kod i naciśnij Zapisz" : "Nakieruj, Dodaj kolejne i naciśnij Gotowe" }

    private func handleCandidate(_ candidate: ScannedItem?) {
        guard let item = candidate, !item.value.isEmpty else {
            lockedCandidate = nil
            return
        }

        // Debounce flicker
        guard lastCandidateValue != item.value else { return }
        lastCandidateValue = item.value
        lockedCandidate = item
    }

    private func addCandidate(_ item: ScannedItem) {
        if !collectedItems.contains(where: { $0.value == item.value }) {
            collectedItems.append(item)
        }
    }
}

#Preview {
    ScannerScreen(mode: .single) { _ in }
}


