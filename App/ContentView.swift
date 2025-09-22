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

    var body: some View {
        List {
            ForEach(Array(lists.enumerated()), id: \.offset) { _, obj in
                let name = (try? obj.value(forKey: "name")) as? String ?? "(bez nazwy)"
                NavigationLink(destination: ScanListView(listId: name)) {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: 64, height: 64)
                            Text(String(name.prefix(2)).uppercased())
                                .font(.headline)
                        }
                        Text(name)
                            .font(.headline)
                    }
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Twoje listy")
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
}
