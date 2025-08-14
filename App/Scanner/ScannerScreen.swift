import SwiftUI

struct ScannerScreen: View {
    let mode: ScanMode
    let onDone: ([ScannedItem]) -> Void

    @State private var collectedItems: [ScannedItem] = []
    @State private var lastCandidateValue: String? = nil
    @State private var lockedCandidate: ScannedItem? = nil
    @State private var lastCandidateAt: Date = .distantPast

    var body: some View {
        ZStack {
            scannerView
                .ignoresSafeArea()
            if lockedCandidate == nil {
                ReticleOverlayView(isLockedOn: false)
                    .ignoresSafeArea()
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            collectedItems.removeAll()
            lastCandidateValue = nil
        }
    }

    @ViewBuilder
    private var scannerView: some View {
        // Prefer AVFoundation for performance and custom highlight
        AVScannerWrapper(onCandidateChange: handleCandidate(_:))
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            if mode == .multi {
                Label("\(collectedItems.count)", systemImage: "tray.full")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0.0)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            if mode == .multi {
                Button(action: { if let c = lockedCandidate { addCandidate(c) } }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                Button("Gotowe") { onDone(collectedItems) }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 18, weight: .semibold))
            } else {
                Spacer()
                Button(action: {
                    if let c = lockedCandidate {
                        onDone([c])
                    }
                }) {
                    ZStack {
                        Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 4)
                            .frame(width: 78, height: 78)
                        Circle().fill(lockedCandidate == nil ? Color.white.opacity(0.3) : Color.white)
                            .frame(width: 64, height: 64)
                    }
                }
                .disabled(lockedCandidate == nil)
                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var title: String { mode == .single ? "Skan – pojedynczy" : "Skan – wiele" }
    private var subtitle: String { mode == .single ? "Nakieruj kod i naciśnij Zapisz" : "Nakieruj, Dodaj kolejne i naciśnij Gotowe" }

    private func handleCandidate(_ candidate: ScannedItem?) {
        if let item = candidate, !item.value.isEmpty {
            // Debounce to avoid excessive state churn
            if lastCandidateValue != item.value {
                lastCandidateValue = item.value
                lockedCandidate = item
            }
            lastCandidateAt = Date()
        } else {
            // Grace period: keep ostatni kandydat przez chwilę, aby klik w spust zadziałał
            let elapsed = Date().timeIntervalSince(lastCandidateAt)
            if elapsed > 0.5 {
                lockedCandidate = nil
                lastCandidateValue = nil
            }
        }
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


