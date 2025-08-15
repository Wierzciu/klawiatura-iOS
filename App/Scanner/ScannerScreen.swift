import SwiftUI

struct ScannerScreen: View {
    let mode: ScanMode
    let onDone: ([ScannedItem]) -> Void

    @State private var collectedItems: [ScannedItem] = []
    @State private var lastCandidateValue: String? = nil
    @State private var lockedCandidate: ScannedItem? = nil
    @State private var lastCandidateAt: Date = .distantPast
    @State private var currentMode: ScanMode = .single

    var body: some View {
        ZStack {
            scannerView
                .ignoresSafeArea()
            AimDot()
                .frame(width: 10, height: 10)
                .foregroundStyle(.white)
                .opacity(0.9)
        }
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            collectedItems.removeAll()
            lastCandidateValue = nil
            currentMode = mode
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
            if currentMode == .multi {
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
        HStack(spacing: 14) {
            // Lewy: przełącz na single
            Button(action: {
                currentMode = .single
                SharedStorage.set(lastMode: .single)
            }) {
                Label("single", systemImage: "barcode.viewfinder")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(currentMode == .single ? .ultraThinMaterial : .thinMaterial, in: Capsule())
            }

            Spacer()

            // Środkowy: spust
            Button(action: {
                if currentMode == .multi {
                    if let c = lockedCandidate { addCandidate(c) }
                } else if let c = lockedCandidate {
                    onDone([c])
                }
            }) {
                ZStack {
                    Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 4)
                        .frame(width: 72, height: 72)
                    Circle().fill(lockedCandidate == nil ? Color.white.opacity(0.3) : Color.white)
                        .frame(width: 58, height: 58)
                }
            }
            .disabled(lockedCandidate == nil)

            Spacer()

            // Prawy: przełącz na multi + licznik nad
            VStack(spacing: 6) {
                if currentMode == .multi, collectedItems.count > 0 {
                    Text("\(collectedItems.count)")
                        .font(.caption2)
                        .padding(5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                Button(action: {
                    currentMode = .multi
                    SharedStorage.set(lastMode: .multi)
                }) {
                    Label("multi", systemImage: "square.stack.3d.up")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(currentMode == .multi ? .ultraThinMaterial : .thinMaterial, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
        // Przycisk "Zakończ" nad spustem – tylko w multi po pierwszym dodaniu
        .overlay(alignment: .top) {
            if currentMode == .multi && collectedItems.count > 0 {
                Button("Zakończ") { onDone(collectedItems) }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.top, -6)
            }
        }
    }

    private var title: String { currentMode == .single ? "Skan – pojedynczy" : "Skan – wiele" }
    private var subtitle: String { currentMode == .single ? "Nakieruj kod i naciśnij Zapisz" : "Nakieruj, Dodaj kolejne i naciśnij Zakończ" }

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

struct AimDot: View {
    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.9))
            .shadow(color: .black.opacity(0.6), radius: 1)
    }
}
