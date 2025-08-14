import SwiftUI
import AVFoundation

final class AVScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCandidateChange: (ScannedItem?) -> Void
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let highlightLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.systemGreen.withAlphaComponent(0.25).cgColor
        layer.strokeColor = UIColor.systemGreen.cgColor
        layer.lineWidth = 4
        layer.shadowColor = UIColor.systemGreen.cgColor
        layer.shadowOpacity = 0.8
        layer.shadowRadius = 8
        return layer
    }()
    private let dimmingLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.black.withAlphaComponent(0.35).cgColor
        layer.fillRule = .evenOdd
        layer.shadowOpacity = 0
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

        // Dimming + highlight layers sit above preview
        view.layer.addSublayer(dimmingLayer)
        view.layer.addSublayer(highlightLayer)
    }

    private func setupCamera() {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
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

        // Prefer fast continuous autofocus towards near range for barcodes
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = true }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        } catch {}

        // Tap to focus
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
        session.commitConfiguration()
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
                updateHighlight(transformed: transformed)
            } else {
                updateHighlight(transformed: nil)
            }
            if let value, !value.isEmpty {
                onCandidateChange(ScannedItem(value: value, symbology: first.type.rawValue))
            } else {
                onCandidateChange(nil)
            }
        } else {
            updateHighlight(transformed: nil)
            onCandidateChange(nil)
        }
    }

    private func updateHighlight(transformed: AVMetadataMachineReadableCodeObject?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let transformed {
            // Build polygon from corners if available, otherwise use bounds
            let polygonPath: UIBezierPath
            let corners = transformed.corners
            if corners.count >= 4 {
                let path = UIBezierPath()
                path.move(to: corners[0])
                for i in 1..<corners.count { path.addLine(to: corners[i]) }
                path.close()
                polygonPath = path
            } else {
                polygonPath = UIBezierPath(roundedRect: transformed.bounds, cornerRadius: 8)
            }
            // Highlight path
            highlightLayer.path = polygonPath.cgPath
            highlightLayer.isHidden = false
            // Dimming outside area using even-odd fill
            let full = UIBezierPath(rect: view.bounds)
            full.append(polygonPath)
            dimmingLayer.path = full.cgPath
            dimmingLayer.isHidden = false
        } else {
            highlightLayer.isHidden = true
            highlightLayer.path = nil
            dimmingLayer.isHidden = true
            dimmingLayer.path = nil
        }
        CATransaction.commit()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let previewLayer, let device = (session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first)?.device else { return }
        let point = gesture.location(in: view)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = devicePoint }
            if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = devicePoint }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        } catch {}
    }
}

struct AVScannerWrapper: UIViewControllerRepresentable {
    let onCandidateChange: (ScannedItem?) -> Void

    func makeUIViewController(context: Context) -> AVScannerViewController {
        AVScannerViewController(onCandidateChange: onCandidateChange)
    }

    func updateUIViewController(_ uiViewController: AVScannerViewController, context: Context) {}
}

