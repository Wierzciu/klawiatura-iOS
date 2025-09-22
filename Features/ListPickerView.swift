import SwiftUI

struct ListPickerView: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @State private var known: [String] = []
    @State private var newList: String = ""

    var body: some View {
        NavigationStack {
            List {
                if !known.isEmpty {
                    Section("Zapisane listy") {
                        ForEach(known, id: \.self) { id in
                            HStack {
                                Text(id)
                                Spacer()
                                if id == selected { Image(systemName: "checkmark").foregroundStyle(.accent) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selected = id
                            }
                        }
                        .onDelete { idx in
                            for i in idx { SharedStorage.removeKnownListId(known[i]) }
                            known = SharedStorage.getKnownListIds()
                        }
                    }
                }

                Section("Nowa lista") {
                    HStack {
                        TextField("Nazwa listy", text: $newList)
                            .textFieldStyle(.roundedBorder)
                            .disableAutocorrection(true)
                            .autocapitalization(.none)
                        Button("Dodaj") {
                            let trimmed = newList.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            SharedStorage.addKnownListId(trimmed)
                            selected = trimmed
                            newList = ""
                            known = SharedStorage.getKnownListIds()
                        }
                        .disabled(newList.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Listy skanów")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
            .onAppear { known = SharedStorage.getKnownListIds() }
        }
    }
}
