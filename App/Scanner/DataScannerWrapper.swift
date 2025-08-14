import SwiftUI
import VisionKit

struct DataScannerWrapper: UIViewControllerRepresentable {
    let onCandidateChange: (ScannedItem?) -> Void

    static var isSupported: Bool {
        if #available(iOS 16.0, *) {
            return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        } else {
            return false
        }
    }

    func makeUIViewController(context: Context) -> UIViewController {
        if #available(iOS 16.0, *) {
            let vc = DataScannerViewController(
                recognizedDataTypes: [.barcode()],
                qualityLevel: .balanced,
                recognizesMultipleItems: true,
                isHighFrameRateTrackingEnabled: true,
                isPinchToZoomEnabled: true,
                isGuidanceEnabled: true
            )
            vc.delegate = context.coordinator
            try? vc.startScanning()
            return vc
        } else {
            return UIViewController()
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCandidateChange: onCandidateChange) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCandidateChange: (ScannedItem?) -> Void
        init(onCandidateChange: @escaping (ScannedItem?) -> Void) {
            self.onCandidateChange = onCandidateChange
        }

        @available(iOS 16.0, *)
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            onCandidateChange(itemsToCandidate(allItems))
        }

        @available(iOS 16.0, *)
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            onCandidateChange(itemsToCandidate(allItems))
        }

        @available(iOS 16.0, *)
        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            onCandidateChange(itemsToCandidate(allItems))
        }

        @available(iOS 16.0, *)
        private func itemsToCandidate(_ items: [RecognizedItem]) -> ScannedItem? {
            items.compactMap(toScanned).first
        }

        @available(iOS 16.0, *)
        private func toScanned(_ item: RecognizedItem) -> ScannedItem? {
            switch item {
            case .barcode(let barcode):
                let value = barcode.payloadStringValue ?? ""
                guard !value.isEmpty else { return nil }
                return ScannedItem(value: value, symbology: nil)
            default:
                return nil
            }
        }
    }
}

struct ReticleOverlayView: View {
    let isLockedOn: Bool
    
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) * 0.6
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                .foregroundStyle(isLockedOn ? Color.green : Color.white.opacity(0.9))
                .frame(width: size, height: size * 0.4)
                .position(x: geo.size.width/2, y: geo.size.height/2)
                .shadow(color: (isLockedOn ? Color.green : Color.black.opacity(0.3)), radius: isLockedOn ? 8 : 5)
                .animation(.easeInOut(duration: 0.15), value: isLockedOn)
        }
        .allowsHitTesting(false)
    }
}

// Dodatkowe nakładki dla VisionKit pominięte dla stabilności (systemowe highlighty włączone)
