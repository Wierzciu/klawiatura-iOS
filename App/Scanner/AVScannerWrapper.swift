import SwiftUI
import AVFoundation

final class AVScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCandidateChange: (ScannedItem?) -> Void

    init(onCandidateChange: @escaping (ScannedItem?) -> Void) {
        self.onCandidateChange = onCandidateChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        let reticle = UIHostingController(rootView: ReticleOverlayView(isLockedOn: false))
        addChild(reticle)
        reticle.view.backgroundColor = .clear
        reticle.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(reticle.view)
        NSLayoutConstraint.activate([
            reticle.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            reticle.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            reticle.view.topAnchor.constraint(equalTo: view.topAnchor),
            reticle.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        reticle.didMove(toParent: self)
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) { session.addOutput(output) }
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .qr, .code128, .code39, .code93, .pdf417, .upce, .itf14]
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.insertSublayer(preview, at: 0)
        session.startRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let first = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let value = first.stringValue {
            onCandidateChange(ScannedItem(value: value, symbology: first.type.rawValue))
        } else {
            onCandidateChange(nil)
        }
    }
}

struct AVScannerWrapper: UIViewControllerRepresentable {
    let onCandidateChange: (ScannedItem?) -> Void

    func makeUIViewController(context: Context) -> AVScannerViewController {
        AVScannerViewController(onCandidateChange: onCandidateChange)
    }

    func updateUIViewController(_ uiViewController: AVScannerViewController, context: Context) {}
}

