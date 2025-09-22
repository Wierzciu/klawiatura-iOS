import SwiftUI
import AVFoundation

final class AVScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCandidateChange: (ScannedItem?) -> Void
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var metadataOutput: AVCaptureMetadataOutput?
    private var lastProcessTs: CFTimeInterval = 0
    private let processInterval: CFTimeInterval = 0.05 // seconds
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
        // Pełne HD dla lepszego odczytu 1D (EAN/Code128) z bezpiecznym fallbackiem
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .high
        }
        guard let device = selectBestBackCamera(),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) { session.addOutput(output) }
        self.metadataOutput = output
        // Using a private serial queue to avoid blocking main and reduce UI jank
        let queue = DispatchQueue(label: "barcode.metadata.queue")
        output.setMetadataObjectsDelegate(self, queue: queue)
        // Zakres typów zoptymalizowany pod 1D; rozszerz w razie potrzeby
        output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .code39, .itf14, .interleaved2of5]
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
            // Enable auto video stabilization and force portrait orientation
            if let connection = preview.connection {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            device.unlockForConfiguration()
        } catch {}

        // Tap to focus
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
        session.commitConfiguration()
        // Configure rect of interest (center area) on the main thread after layout
        DispatchQueue.main.async { [weak self] in
            self?.updateRectOfInterest()
        }
        // Start session off the main thread to avoid UI stalls (per Thread Performance Checker)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
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
        // Update scan area when layout changes (orientation/size)
        updateRectOfInterest()
    }

func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // Przenieś całą interakcję z UI/layers na główny wątek, aby uniknąć MTC
        let objects = metadataObjects
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let previewLayer = self.previewLayer else {
                self?.updateHighlight(transformed: nil)
                self?.onCandidateChange(nil)
                return
            }

            // Throttle processing to reduce UI churn
            let now = CACurrentMediaTime()
            if now - self.lastProcessTs < self.processInterval {
                return
            }
            self.lastProcessTs = now

            // Środek ekranu = pozycja kropki
            let center = CGPoint(x: self.view.bounds.midX, y: self.view.bounds.midY)

            // Kandydaci po transformacji; wybierz tych, których ramka zawiera środek (z tolerancją)
            let margin: CGFloat = 24
            let transformedCandidates: [(orig: AVMetadataMachineReadableCodeObject, transformed: AVMetadataMachineReadableCodeObject, dist: CGFloat)] = objects.compactMap { obj in
                guard let m = obj as? AVMetadataMachineReadableCodeObject,
                      let t = previewLayer.transformedMetadataObject(for: m) as? AVMetadataMachineReadableCodeObject else {
                    return nil
                }
                let expanded = t.bounds.insetBy(dx: -margin, dy: -margin)
                if expanded.contains(center) {
                    let d = hypot(t.bounds.midX - center.x, t.bounds.midY - center.y)
                    return (m, t, d)
                }
                return nil
            }

            guard !transformedCandidates.isEmpty else {
                self.updateHighlight(transformed: nil)
                self.onCandidateChange(nil)
                return
            }

            // Wybierz najbliższego środka (gdyby nakładały się ramki)
            let chosen = transformedCandidates.min { a, b in a.dist < b.dist }!

            let value = chosen.orig.stringValue
            self.updateHighlight(transformed: chosen.transformed)
            if let v = value, !v.isEmpty {
                self.onCandidateChange(ScannedItem(value: v, symbology: chosen.orig.type.rawValue))
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Stop session off the main thread to avoid UI stalls
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func updateRectOfInterest() {
        guard let previewLayer, let output = metadataOutput else { return }
        // Dopasuj ROI do prostokąta celownika
        let layerRect = currentReticleRect()
        let roi = previewLayer.metadataOutputRectConverted(fromLayerRect: layerRect)
        output.rectOfInterest = roi
    }

    private func currentReticleRect() -> CGRect {
        // Szeroki i niski pas w centrum – dobry dla kodów 1D w portrecie
        let w = view.bounds.width
        let h = view.bounds.height
        let rw = w * 0.85
        let rh = h * 0.22
        let rect = CGRect(x: (w - rw) / 2, y: (h - rh) / 2, width: rw, height: rh)
        return rect
    }
}

struct AVScannerWrapper: UIViewControllerRepresentable {
    let onCandidateChange: (ScannedItem?) -> Void

    func makeUIViewController(context: Context) -> AVScannerViewController {
        AVScannerViewController(onCandidateChange: onCandidateChange)
    }

    func updateUIViewController(_ uiViewController: AVScannerViewController, context: Context) {}
}

