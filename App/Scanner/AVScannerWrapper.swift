import SwiftUI
import AVFoundation

final class AVScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCandidateChange: (ScannedItem?) -> Void
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var metadataOutput: AVCaptureMetadataOutput?
    private var lastProcessTs: CFTimeInterval = 0
    private let processInterval: CFTimeInterval = 0.08 // seconds
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
        // Lower resolution preset for better latency
        session.sessionPreset = .vga640x480
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
        // Limit types for performance; expand if you need more symbologies
        output.metadataObjectTypes = [.ean8, .ean13, .code128]
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

            // Kandydaci po transformacji do warstwy; wybierz tylko te, których ramka zawiera środek
            let transformedCandidates: [(orig: AVMetadataMachineReadableCodeObject, transformed: AVMetadataMachineReadableCodeObject)] = objects.compactMap { obj in
                guard let m = obj as? AVMetadataMachineReadableCodeObject,
                      let t = previewLayer.transformedMetadataObject(for: m) as? AVMetadataMachineReadableCodeObject else {
                    return nil
                }
                if t.bounds.contains(center) { return (m, t) }
                return nil
            }

            guard !transformedCandidates.isEmpty else {
                self.updateHighlight(transformed: nil)
                self.onCandidateChange(nil)
                return
            }

            // Wybierz najbliższego środka (gdyby nakładały się ramki)
            let chosen = transformedCandidates.min { a, b in
                let da = hypot(a.transformed.bounds.midX - center.x, a.transformed.bounds.midY - center.y)
                let db = hypot(b.transformed.bounds.midX - center.x, b.transformed.bounds.midY - center.y)
                return da < db
            }!

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
        // Szerszy centralny ROI dla lepszego wykrywania, przy zachowaniu celu na środku
        let w = view.bounds.width
        let h = view.bounds.height
        let base = min(w, h)
        let rw = base * 0.6
        let rh = base * 0.4
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

