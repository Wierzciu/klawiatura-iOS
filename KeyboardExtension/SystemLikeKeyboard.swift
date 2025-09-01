import SwiftUI

struct SystemLikeKeyboardView: View {
    let insertText: (String) -> Void
    let deleteBackward: () -> Void
    let advanceToNext: () -> Void
    let insertNewline: () -> Void

    @State private var isShiftOn: Bool = false
    @State private var isNumbers: Bool = false

    var body: some View {
        // Fixed row height provides intrinsic height for the keyboard view
        let spacing: CGFloat = 6
        let rowHeight: CGFloat = 44
        let totalHeight: CGFloat = rowHeight * 4 + spacing * 3 + 4

        GeometryReader { proxy in
            // Compute widths from the actual available width
            let innerWidth = proxy.size.width - 2 * spacing
            let baseWidth: CGFloat = max(28, floor((innerWidth - 9 * spacing) / 10))

            VStack(spacing: spacing) {
                if !isNumbers {
                    lettersRows(baseWidth: baseWidth, spacing: spacing, height: rowHeight)
                } else {
                    numbersRows(baseWidth: baseWidth, spacing: spacing, height: rowHeight)
                }
                bottomRow(baseWidth: baseWidth, spacing: spacing, height: rowHeight)
            }
            .padding(.horizontal, spacing)
            .padding(.bottom, 4)
        }
        .frame(height: totalHeight)
    }

    private func lettersRows(baseWidth: CGFloat, spacing: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: spacing) {
            // Row 1: 10 equally sized keys
            keyRow(["q","w","e","r","t","y","u","i","o","p"], keyWidth: baseWidth, spacing: spacing, height: height)

            // Row 2: 9 keys with half-key indent on both sides
            HStack(spacing: spacing) {
                // half-key indent adjusted by -spacing/2 to equalize total spacing vs row 1
                Color.clear.frame(width: max(0, baseWidth / 2 - spacing / 2))
                ForEach(["a","s","d","f","g","h","j","k","l"], id: \.self) { k in
                    key(k, width: baseWidth, height: height)
                }
                Color.clear.frame(width: max(0, baseWidth / 2 - spacing / 2))
            }

            // Row 3: shift + 7 keys + delete; side keys ~1.5× width
            HStack(spacing: spacing) {
                // Add S/2 margin on both ends so total spacings match row 1
                Color.clear.frame(width: spacing / 2)
                specialKey(system: isShiftOn ? "shift.fill" : "shift", width: baseWidth * 1.5, height: height) {
                    isShiftOn.toggle()
                }
                ForEach(["z","x","c","v","b","n","m"], id: \.self) { k in
                    key(k, width: baseWidth, height: height)
                }
                specialKey(system: "delete.left", width: baseWidth * 1.5, height: height) { deleteBackward() }
                Color.clear.frame(width: spacing / 2)
            }
        }
    }

    private func numbersRows(baseWidth: CGFloat, spacing: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: spacing) {
            keyRow(["1","2","3","4","5","6","7","8","9","0"], keyWidth: baseWidth, spacing: spacing, height: height)
            keyRow(["-","/",":",";","(",")","€","&","@","\""], keyWidth: baseWidth, spacing: spacing, height: height)
            HStack(spacing: spacing) {
                specialKey(text: "#+=", width: baseWidth * 1.5, height: height) { /* alt layer */ }
                keyRow([".",",","?","!","'","\u{2013}"] /* en-dash */, keyWidth: baseWidth, spacing: spacing, height: height)
                specialKey(system: "delete.left", width: baseWidth * 1.5, height: height) { deleteBackward() }
            }
        }
    }

    private func bottomRow(baseWidth: CGFloat, spacing: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: spacing) {
            // Proportions chosen to sum to ~10 × baseWidth (like system)
            specialKey(text: isNumbers ? "ABC" : "123", width: baseWidth * 1.25, height: height) { isNumbers.toggle() }
            specialKey(system: "globe", width: baseWidth * 1.25, height: height) { advanceToNext() }
            spaceKey(width: baseWidth * 5.0, height: height) { insertText(" ") }
            specialKey(text: "Return", width: baseWidth * 2.5, height: height) { insertNewline() }
        }
    }

    private func keyRow(_ keys: [String], keyWidth: CGFloat, spacing: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(keys, id: \.self) { k in
                key(k, width: keyWidth, height: height)
            }
        }
    }

    private func key(_ label: String, width: CGFloat, height: CGFloat) -> some View {
        Button(action: {
            let text = isShiftOn && !isNumbers ? label.uppercased() : label
            insertText(text)
            if isShiftOn { isShiftOn = false }
        }) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(UIColor.systemGray5))
                .overlay(
                    Text(displayLabel(label))
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                )
                .frame(width: width, height: height)
        }
    }

    private func displayLabel(_ label: String) -> String {
        isShiftOn && !isNumbers ? label.uppercased() : label
    }

    private func specialKey(text: String, width: CGFloat, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(UIColor.systemGray4))
                .overlay(
                    Text(text)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                )
                .frame(width: width, height: height)
        }
    }

    private func specialKey(system: String, width: CGFloat, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(UIColor.systemGray4))
                .overlay(
                    Image(systemName: system)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                )
                .frame(width: width, height: height)
        }
    }

    private func spaceKey(width: CGFloat, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(UIColor.systemGray5))
                .overlay(
                    Text("space")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                )
                .frame(width: width, height: height)
        }
    }
}
