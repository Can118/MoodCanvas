import SwiftUI

struct EditGroupNameSheet: View {
    let onSave: (String) -> Void

    @State private var groupName: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(initialName: String, onSave: @escaping (String) -> Void) {
        _groupName = State<String>(initialValue: initialName)
        self.onSave = onSave
    }

    private var isValid: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 36)

            Text("Edit Group's Name")
                .font(Font.custom("EBGaramond-Bold", size: 28))
                .foregroundStyle(.white)

            Spacer().frame(height: 32)

            // Text field inside a cream card
            ZStack(alignment: .center) {
                if groupName.isEmpty {
                    Text("Monkeys without bananas 🌙🐵")
                        .font(Font.custom("EBGaramond-Medium", size: 22))
                        .foregroundStyle(Color(hex: "665938").opacity(0.3))
                        .multilineTextAlignment(.center)
                        .allowsHitTesting(false)
                }
                TextField("", text: $groupName, axis: .vertical)
                    .font(Font.custom("EBGaramond-Medium", size: 22))
                    .foregroundStyle(Color(hex: "665938"))
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .tint(Color(hex: "665938"))
                    .lineLimit(1...3)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(hex: "FFF8D4"))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(Color(hex: "3C392A").opacity(0.15), lineWidth: 3)
                    }
            }
            .padding(.horizontal, 20)

            Spacer()

            Button {
                let trimmed = groupName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                onSave(trimmed)
                dismiss()
            } label: {
                Text("that's better!")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background {
                        Capsule()
                            .fill(Color(hex: "B8721C"))
                            .overlay {
                                Capsule()
                                    .strokeBorder(Color(hex: "3C392A").opacity(0.4), lineWidth: 5)
                            }
                    }
            }
            .buttonStyle(.plain)
            .disabled(!isValid)
            .opacity(isValid ? 1 : 0.4)
            .padding(.horizontal, 36)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(hex: "4A4540"))
        .onAppear { isFocused = true }
    }
}
