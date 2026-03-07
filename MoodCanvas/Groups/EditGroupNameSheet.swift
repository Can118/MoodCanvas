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
            titleText
            Spacer().frame(height: 32)
            textFieldCard
            Spacer()
            saveButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground { blurBackground }
        .onAppear { isFocused = true }
    }

    private var blurBackground: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color(hex: "3C2E1A").opacity(0.45)
        }
        .ignoresSafeArea()
    }

    private var titleText: some View {
        Text("Edit Group's Name")
            .font(Font.custom("EBGaramond-Bold", size: 28))
            .foregroundStyle(.white)
    }

    private var placeholderText: some View {
        Text("Monkeys without bananas")
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(hex: "665938").opacity(0.3))
            .multilineTextAlignment(.center)
            .allowsHitTesting(false)
    }

    private var nameTextField: some View {
        TextField("", text: $groupName, axis: .vertical)
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(hex: "665938"))
            .multilineTextAlignment(.center)
            .focused($isFocused)
            .tint(Color(hex: "665938"))
            .lineLimit(1...3)
    }

    private var textFieldCard: some View {
        ZStack(alignment: .center) {
            if groupName.isEmpty { placeholderText }
            nameTextField
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .padding(.horizontal, 20)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color(hex: "FFF8D4"))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color(hex: "3C392A").opacity(0.15), lineWidth: 3)
            }
    }

    private var saveButton: some View {
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
                .padding(.vertical, 23)
                .background(buttonBackground)
        }
        .buttonStyle(.plain)
        .disabled(!isValid)
        .opacity(isValid ? 1 : 0.4)
        .padding(.horizontal, 36)
        .padding(.bottom, 48)
    }

    private var buttonBackground: some View {
        Capsule()
            .fill(Color(hex: "B8721C"))
            .overlay {
                Capsule()
                    .strokeBorder(Color(hex: "3C392A").opacity(0.4), lineWidth: 5)
            }
    }
}
