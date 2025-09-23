import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showScanner: ScanMode? = nil
    private let scanService = ScanPersistenceService.shared
    private static let defaultListId = ScanPersistenceService.defaultListId
    @State private var showScanList: Bool = false
    @State private var selectedListId: String

    init() {
        _selectedListId = State(initialValue: SharedStorage.getLastListId() ?? Self.defaultListId)
    }

    private var trimmedListId: String { selectedListId.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Wybór/nadanie nazwy listy
                HStack(spacing: 12) {
                    TextField("Nazwa listy", text: $selectedListId)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .autocapitalization(.none)
                    Button(action: { showScanList = true }) {
                        Label("Pokaż listę", systemImage: "list.bullet")
                    }.buttonStyle(.bordered)
                }

                Button {
                    showScanner = (trimmedListId.isEmpty ? nil : (SharedStorage.getLastMode() ?? .single))
                } label: {
                    Label("Skanuj do \(trimmedListId.isEmpty ? "(podaj nazwę)" : trimmedListId)", systemImage: "barcode.viewfinder")
                }
                .disabled(trimmedListId.isEmpty)
                .buttonStyle(.borderedProminent)

                NavigationLink(destination: ListsView()) {
                    Label("Twoje listy", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("App Group: \(SharedStorage.appGroupIdentifier)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Skaner kodów")
            .background(
                NavigationLink(destination: ScanListView(listId: trimmedListId), isActive: $showScanList) {
                    EmptyView()
                }
                .hidden()
            )
            .onChange(of: selectedListId) { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                SharedStorage.set(lastListId: trimmed)
            }
            .onAppear {
                let trimmed = trimmedListId
                SharedStorage.set(lastListId: trimmed)
            }
            .fullScreenCover(item: $showScanner) { mode in
                ScannerScreen(mode: mode) { items in
                    let listId = trimmedListId
                    guard !listId.isEmpty else { return }
                    SharedStorage.savePending(scans: items)
                    scanService.save(scannedItems: items, listId: listId, context: viewContext)
                    SharedStorage.addKnownListId(listId)
                    showScanner = nil
                }
                .ignoresSafeArea()
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

struct ListsView: View {
    @Environment(\.managedObjectContext) private var context

    @State private var showCreate: Bool = false
    @State private var newName: String = ""
    @State private var lists: [NSManagedObject] = []
    @State private var showDeleteConfirm: Bool = false
    @State private var pendingDelete: NSManagedObject? = nil
    @State private var pendingDeleteName: String = ""
    @State private var confirmDeleteInput: String = ""

    var body: some View {
        ScrollView {
            let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(lists.enumerated()), id: \.offset) { _, obj in
                    let name = (try? obj.value(forKey: "name")) as? String ?? "(bez nazwy)"
                    NavigationLink(destination: ScanListView(listId: name)) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.15))
                                .aspectRatio(1, contentMode: .fit)
                            Text(name)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingDelete = obj
                            pendingDeleteName = name
                            confirmDeleteInput = ""
                            showDeleteConfirm = true
                        } label: {
                            Label("Usuń listę", systemImage: "trash")
                        }
                    }
                }

                Button(action: { showCreate = true }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                            .foregroundStyle(Color.accentColor)
                            .aspectRatio(1, contentMode: .fit)
                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.title)
                            Text("Nowa lista")
                                .font(.subheadline)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Twoje listy")
        .sheet(isPresented: $showDeleteConfirm) {
            NavigationStack {
                Form {
                    Section("Potwierdź usunięcie") {
                        Text("Aby usunąć listę wpisz jej nazwę dokładnie:")
                        Text("\(pendingDeleteName)")
                            .font(.headline)
                        TextField("Wpisz nazwę listy", text: $confirmDeleteInput)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }
                    Section {
                        Button("Usuń listę", role: .destructive) {
                            deletePendingConfirmed()
                        }
                        .disabled(confirmDeleteInput.trimmingCharacters(in: .whitespacesAndNewlines) != pendingDeleteName)
                    }
                }
                .navigationTitle("Usuń listę")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Anuluj") { showDeleteConfirm = false }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showCreate = true }) { Image(systemName: "plus") }
            }
        }
        .onAppear(perform: reload)
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                Form {
                    Section("Nazwa listy") {
                        TextField("np. magazyn A", text: $newName)
                            .textFieldStyle(.roundedBorder)
                            .disableAutocorrection(true)
                            .autocapitalization(.none)
                    }
                }
                .navigationTitle("Nowa lista")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Anuluj") { showCreate = false; newName = "" }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Zapisz") { create() }
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func reload() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ScanList")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        do { lists = try context.fetch(request) } catch { lists = [] }
    }

    private func create() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let entity = NSEntityDescription.entity(forEntityName: "ScanList", in: context) {
            let list = NSManagedObject(entity: entity, insertInto: context)
            list.setValue(UUID(), forKey: "id")
            list.setValue(trimmed, forKey: "name")
            list.setValue(Date(), forKey: "createdAt")
            PersistenceController.shared.save(context: context)
            SharedStorage.set(lastListId: trimmed)
            newName = ""
            showCreate = false
            reload()
        }
    }

    private func delete(offsets: IndexSet) {
        for index in offsets {
            let item = lists[index]
            context.delete(item)
        }
        PersistenceController.shared.save(context: context)
        reload()
    }

    private func deletePendingConfirmed() {
        guard let obj = pendingDelete else { return }
        context.delete(obj)
        PersistenceController.shared.save(context: context)
        if SharedStorage.getLastListId() == pendingDeleteName {
            SharedStorage.set(lastListId: "")
        }
        showDeleteConfirm = false
        pendingDelete = nil
        reload()
    }
}
