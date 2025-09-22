import SwiftUI
import AVFoundation
#if canImport(OSLog)
import OSLog
#endif

struct ScanListView: View {
    @StateObject private var viewModel: ScanListViewModel

    init(listId: String,
         service: ScanService = ScanService(),
         cameraPermissionProvider: CameraPermissionProviding = SystemCameraPermissionProvider()) {
        _viewModel = StateObject(wrappedValue: ScanListViewModel(listId: listId,
                                                                 service: service,
                                                                 cameraPermissionProvider: cameraPermissionProvider))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.cameraPermissionDenied {
                banner
            }
            listContent
        }
.fullScreenCover(isPresented: $viewModel.isScannerPresented) {
            ScannerScreen(mode: .multi) { items in
                viewModel.processScannedItems(items)
                viewModel.isScannerPresented = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $viewModel.isManualEntryPresented) {
            ManualEntryView(codeValue: viewModel.manualCode,
                            labelValue: viewModel.manualLabel,
                            onSave: { code, label in viewModel.addManualEntry(code: code, label: label) },
                            onCancel: { viewModel.isManualEntryPresented = false })
        }
.sheet(item: $viewModel.exportItem) { item in
            DocumentExporter(url: item.url)
                .onDisappear { viewModel.clearExportURL() }
        }
        .alert(isPresented: Binding<Bool>(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Alert(title: Text("Błąd"), message: Text(viewModel.errorMessage ?? "Nieznany błąd"), dismissButton: .default(Text("OK")))
        }
.onAppear(perform: viewModel.loadItems)
        .onAppear {
            // Zapamiętaj aktywną listę do autosave'u pendingowych skanów
            SharedStorage.set(lastListId: viewModel.listId)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Lista skanów")
                        .font(.title2.bold())
                    Text(viewModel.listId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("Skaner", isOn: $viewModel.isScannerEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .labelsHidden()
                    .accessibilityLabel("Skaner aktywny")
            }

            HStack(spacing: 12) {
                Button("Skanuj") { viewModel.startScanner() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isScannerEnabled)

                Button("Dodaj ręcznie") { viewModel.prepareManualEntry() }
                    .buttonStyle(.bordered)

                Button("Eksport CSV") { viewModel.exportCSV() }
                    .buttonStyle(.bordered)
            }

            if viewModel.showManualFallbackSuggestion {
                Text("Brak dostępu do kamery? Dodaj wpis ręcznie.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private var banner: some View {
        Text("Brak dostępu do kamery. Użyj opcji \"Dodaj ręcznie\" lub włącz aparat w Ustawieniach.")
            .font(.footnote)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.85))
    }

    private var listContent: some View {
        List {
            ForEach(viewModel.items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.codeRaw)
                        .font(.system(.body, design: .monospaced))
                    HStack(spacing: 8) {
                        Text(item.codeType)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        if let label = item.label, !label.isEmpty {
                            Text(label)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(Self.dateFormatter.string(from: item.createdAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .swipeActions(allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.delete(item: item)
                    } label: {
                        Label("Usuń", systemImage: "trash")
                    }

                    Button {
                        viewModel.beginEditingLabel(for: item)
                    } label: {
                        Label("Etykieta", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $viewModel.editingItem) { item in
            LabelEditView(item: item, onSave: { newLabel in
                viewModel.updateLabel(for: item, newLabel: newLabel)
            }, onCancel: {
                viewModel.editingItem = nil
            })
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

final class ScanListViewModel: ObservableObject {
    @Published var items: [ScanItemDTO] = []
    @Published var errorMessage: String? = nil
    @Published var isScannerEnabled: Bool = true
    @Published var isScannerPresented: Bool = false
    @Published var isManualEntryPresented: Bool = false
    @Published var manualCode: String = ""
    @Published var manualLabel: String = ""
    @Published var exportItem: ExportItem? = nil
    @Published var editingItem: ScanItemDTO? = nil
    @Published var cameraPermissionDenied: Bool = false
    @Published var showManualFallbackSuggestion: Bool = false

    let listId: String

    private let service: ScanService
    private let cameraPermissionProvider: CameraPermissionProviding
#if canImport(OSLog)
    private let logger = Logger(subsystem: "pl.twojefirma.klawiatura", category: "ScanListViewModel")
#endif

    init(listId: String,
         service: ScanService,
         cameraPermissionProvider: CameraPermissionProviding) {
        self.listId = listId
        self.service = service
        self.cameraPermissionProvider = cameraPermissionProvider
    }

    func loadItems() {
        do {
            items = try service.getItems(listId: listId)
        } catch {
            handleError(error)
        }
    }

    func startScanner() {
        guard isScannerEnabled else { return }

        switch cameraPermissionProvider.authorizationStatus() {
        case .authorized:
            isScannerPresented = true
        case .notDetermined:
            cameraPermissionProvider.requestAccess { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.isScannerPresented = true
                    } else {
                        self?.cameraPermissionDenied = true
                        self?.showManualFallbackSuggestion = true
                    }
                }
            }
        case .denied, .restricted:
            cameraPermissionDenied = true
            showManualFallbackSuggestion = true
        @unknown default:
            cameraPermissionDenied = true
            showManualFallbackSuggestion = true
        }
    }

    func processScannedItems(_ scanned: [ScannedItem]) {
        guard !scanned.isEmpty else { return }

        do {
            for item in scanned {
                let type = item.symbology ?? "UNKNOWN"
                _ = try service.addScan(listId: listId, codeRaw: item.value, codeType: type, label: nil)
            }
            items = try service.getItems(listId: listId)
        } catch let error as ScanServiceError {
            if case .duplicateWithinInterval = error {
#if canImport(OSLog)
                logger.log("scan_duplicate handled in view model")
#else
                print("scan_duplicate handled in view model")
#endif
            }
            handleError(error)
        } catch {
            handleError(error)
        }
    }

    func prepareManualEntry() {
        manualCode = ""
        manualLabel = ""
        isManualEntryPresented = true
    }

    func addManualEntry(code: String, label: String?) {
        do {
            _ = try service.addScan(listId: listId, codeRaw: code, codeType: "MANUAL", label: label)
            items = try service.getItems(listId: listId)
            isManualEntryPresented = false
        } catch {
            handleError(error)
        }
    }

    func delete(item: ScanItemDTO) {
        do {
            try service.removeItem(item.id)
            items = try service.getItems(listId: listId)
        } catch {
            handleError(error)
        }
    }

    func beginEditingLabel(for item: ScanItemDTO) {
        editingItem = item
    }

    func updateLabel(for item: ScanItemDTO, newLabel: String) {
        do {
            try service.updateLabel(item.id, label: newLabel.isEmpty ? nil : newLabel)
            items = try service.getItems(listId: listId)
            editingItem = nil
        } catch {
            handleError(error)
        }
    }

    func exportCSV() {
        do {
            let url = try CSVExporter.export(items)
            exportItem = ExportItem(url: url)
#if canImport(OSLog)
            logger.log("export_success count=\(self.items.count)")
#else
            print("export_success count=\(self.items.count)")
#endif
        } catch {
#if canImport(OSLog)
            logger.error("export_error \(String(describing: error))")
#else
            print("export_error \(error)")
#endif
            handleError(error)
        }
    }

    func clearExportURL() {
        exportItem = nil
    }

    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

extension ScanListViewModel {
    struct ExportItem: Identifiable {
        let id = UUID()
        let url: URL
    }
}

protocol CameraPermissionProviding {
    func authorizationStatus() -> AVAuthorizationStatus
    func requestAccess(completion: @escaping (Bool) -> Void)
}

struct SystemCameraPermissionProvider: CameraPermissionProviding {
    func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
    }
}

private struct ManualEntryView: View {
    @State private var code: String
    @State private var label: String

    let onSave: (String, String?) -> Void
    let onCancel: () -> Void

    init(codeValue: String, labelValue: String, onSave: @escaping (String, String?) -> Void, onCancel: @escaping () -> Void) {
        _code = State(initialValue: codeValue)
        _label = State(initialValue: labelValue)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Kod")) {
                    TextField("Wartość", text: $code)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section(header: Text("Etykieta")) {
                    TextField("Opcjonalnie", text: $label)
                }
            }
            .navigationTitle("Dodaj wpis")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        onSave(code, label.isEmpty ? nil : label)
                    }
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct LabelEditView: View {
    let item: ScanItemDTO
    @State private var label: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    init(item: ScanItemDTO, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.item = item
        _label = State(initialValue: item.label ?? "")
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Kod")) {
                    Text(item.codeRaw)
                        .font(.system(.body, design: .monospaced))
                }

                Section(header: Text("Etykieta")) {
                    TextField("Etykieta", text: $label)
                }
            }
            .navigationTitle("Edytuj etykietę")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") { onSave(label) }
                }
            }
        }
    }
}
