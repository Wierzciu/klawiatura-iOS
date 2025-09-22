import SwiftUI
import CoreData

struct ListsView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \ScanList.createdAt, ascending: false)])
    private var lists: FetchedResults<ScanList>

    @State private var showCreate: Bool = false
    @State private var newName: String = ""

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(lists) { list in
                    NavigationLink(destination: ScanListView(listId: list.name)) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.15))
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                            Text(list.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .padding()
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
                        Button("Zapisz") { createList() }
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func createList() {
        let repo = CoreDataScanListRepository(persistenceController: .shared, context: context)
        do {
            let saved = try repo.create(name: newName)
            SharedStorage.set(lastListId: saved.name)
            newName = ""
            showCreate = false
        } catch {
            print("Failed to create list: \(error)")
        }
    }
}
