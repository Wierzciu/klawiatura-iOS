import SwiftUI
import AVFoundation

final class AVScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCandidateChange: (ScannedItem?) -> Void
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let highlightLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor.systemGreen.cgColor
        layer.lineWidth = 4
        layer.shadowColor = UIColor.systemGreen.cgColor
        layer.shadowOpacity = 0.8
        layer.shadowRadius = 8
        return layer
    }()

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

        // Highlight layer sits above preview
        view.layer.addSublayer(highlightLayer)
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
        view.layer.insertSublayer(preview, at: 0)
        preview.frame = view.bounds
        preview.needsDisplayOnBoundsChange = true
        self.previewLayer = preview
        session.startRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        highlightLayer.frame = view.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let first = metadataObjects.first as? AVMetadataMachineReadableCodeObject {
            let value = first.stringValue
            // Transform to preview coordinates
            if let previewLayer, let transformed = previewLayer.transformedMetadataObject(for: first) as? AVMetadataMachineReadableCodeObject {
                let rect = transformed.bounds
                updateHighlight(rect: rect)
            } else {
                updateHighlight(rect: nil)
            }
            if let value, !value.isEmpty {
                onCandidateChange(ScannedItem(value: value, symbology: first.type.rawValue))
            } else {
                onCandidateChange(nil)
            }
        } else {
            updateHighlight(rect: nil)
            onCandidateChange(nil)
        }
    }

    private func updateHighlight(rect: CGRect?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let rect {
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
            highlightLayer.path = path.cgPath
            highlightLayer.isHidden = false
        } else {
            highlightLayer.isHidden = true
            highlightLayer.path = nil
        }
        CATransaction.commit()
    }
}

struct AVScannerWrapper: UIViewControllerRepresentable {
    let onCandidateChange: (ScannedItem?) -> Void

    func makeUIViewController(context: Context) -> AVScannerViewController {
        AVScannerViewController(onCandidateChange: onCandidateChange)
    }

    func updateUIViewController(_ uiViewController: AVScannerViewController, context: Context) {}
}

