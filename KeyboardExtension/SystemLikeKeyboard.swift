import SwiftUI

struct SystemLikeKeyboardView: View {
    let insertText: (String) -> Void
    let deleteBackward: () -> Void
    let advanceToNext: () -> Void
    let insertNewline: () -> Void

    @State private var isShiftOn: Bool = false
    @State private var isNumbers: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            if !isNumbers { lettersRows } else { numbersRows }
            bottomRow
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    private var lettersRows: some View {
        VStack(spacing: 6) {
            keyRow(["q","w","e","r","t","y","u","i","o","p"])
            // Second row with margins to visually center
            HStack(spacing: 6) {
                Spacer(minLength: 22)
                keyRow(["a","s","d","f","g","h","j","k","l"])
                Spacer(minLength: 22)
            }
            HStack(spacing: 6) {
                specialKey(system: isShiftOn ? "shift.fill" : "shift") {
                    isShiftOn.toggle()
                }
                keyRow(["z","x","c","v","b","n","m"])
                specialKey(system: "delete.left") { deleteBackward() }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var numbersRows: some View {
        VStack(spacing: 6) {
            keyRow(["1","2","3","4","5","6","7","8","9","0"])
            keyRow(["-","/",":",";","(",")","€","&","@","\""])
            HStack(spacing: 6) {
                specialKey(text: "#+=") { /* keep simple */ }
                keyRow([".",",","?","!","'","\u{2013}"]) // en-dash
                specialKey(system: "delete.left") { deleteBackward() }
            }
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            specialKey(text: isNumbers ? "ABC" : "123") { isNumbers.toggle() }
            specialKey(system: "globe") { advanceToNext() }
            spaceKey { insertText(" ") }
            specialKey(text: "Return") { insertNewline() }
        }
    }

    private func keyRow(_ keys: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { k in
                key(k)
            }
        }
    }

    private func key(_ label: String) -> some View {
        Button(action: {
            let text = isShiftOn && !isNumbers ? label.uppercased() : label
            insertText(text)
            if isShiftOn { isShiftOn = false }
        }) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(UIColor.systemGray5))
                .overlay(Text(displayLabel(label)).font(.system(size: 18)))
                .frame(height: 42)
        }
    }

    private func displayLabel(_ label: String) -> String {
        isShiftOn && !isNumbers ? label.uppercased() : label
    }

    private func specialKey(text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(UIColor.systemGray4))
                .overlay(Text(text).font(.system(size: 16, weight: .semibold)))
                .frame(height: 42)
        }
        .frame(minWidth: 60)
    }

    private func specialKey(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(UIColor.systemGray4))
                .overlay(Image(systemName: system).font(.system(size: 18, weight: .semibold)))
                .frame(height: 42)
        }
        .frame(minWidth: 50)
    }

    private func spaceKey(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(UIColor.systemGray5))
                .overlay(Text("space").font(.system(size: 16)))
                .frame(height: 42)
        }
        .frame(minWidth: 120)
    }
}


