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

        // Dimming + highlight layers sit above preview
        view.layer.addSublayer(dimmingLayer)
        view.layer.addSublayer(highlightLayer)
    }

    private func setupCamera() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        guard let device = selectBestBackCamera(),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) { session.addOutput(output) }
        // Using a private serial queue to avoid blocking main and reduce UI jank
        let queue = DispatchQueue(label: "barcode.metadata.queue")
        output.setMetadataObjectsDelegate(self, queue: queue)
        output.metadataObjectTypes = [.ean8, .ean13, .qr, .code128, .code39, .code93, .pdf417, .upce, .itf14, .interleaved2of5, .aztec, .dataMatrix]
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
            // Enable auto video stabilization and auto HDR when available (improves readability)
            if let connection = (view.layer as? AVCaptureVideoPreviewLayer)?.connection, connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
            device.unlockForConfiguration()
        } catch {}

        // Tap to focus
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
        session.commitConfiguration()
        session.startRunning()
    }

    // Prefer multi-camera devices that can switch optics automatically
    private func selectBestBackCamera() -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .back
        )
        // Pick first available by priority list above
        if let chosen = discovery.devices.first { return chosen }
        return AVCaptureDevice.default(for: .video)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        highlightLayer.frame = view.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // Wybierz obiekt, którego bounds zawiera punkt celowania (środek ekranu)
        guard let previewLayer else {
            DispatchQueue.main.async { [weak self] in
                self?.updateHighlight(transformed: nil)
                self?.onCandidateChange(nil)
            }
            return
        }
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let candidates = metadataObjects.compactMap { $0 as? AVMetadataMachineReadableCodeObject }
        let chosenOriginal: AVMetadataMachineReadableCodeObject? = candidates.first { obj in
            if let t = previewLayer.transformedMetadataObject(for: obj) as? AVMetadataMachineReadableCodeObject {
                return t.bounds.insetBy(dx: -12, dy: -12).contains(center)
            }
            return false
        }
        guard let original = chosenOriginal else {
            DispatchQueue.main.async { [weak self] in
                self?.updateHighlight(transformed: nil)
                self?.onCandidateChange(nil)
            }
            return
        }
        let value = original.stringValue
        let transformed = previewLayer.transformedMetadataObject(for: original) as? AVMetadataMachineReadableCodeObject
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateHighlight(transformed: transformed)
            if let v = value, !v.isEmpty {
                self.onCandidateChange(ScannedItem(value: v, symbology: original.type.rawValue))
            } else {
                self.onCandidateChange(nil)
            }
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

