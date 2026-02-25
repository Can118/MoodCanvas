import SwiftUI

struct NameEntryView: View {
    @EnvironmentObject var authService: AuthService

    @State private var name = ""
    @State private var isLoading = false
    @FocusState private var isNameFocused: Bool

    private var isValid: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Text("What's your name?")
                    .font(.largeTitle.bold())

                Text("This is how your friends will see you in MoodCanvas.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 40)

            TextField("Your name", text: $name)
                .textContentType(.name)
                .autocorrectionDisabled()
                .font(.body)
                .focused($isNameFocused)
                .frame(height: 52)
                .padding(.horizontal, 14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)

            Spacer()

            if let error = authService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            Button {
                Task {
                    isLoading = true
                    await authService.setName(name)
                    isLoading = false
                }
            } label: {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Continue")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isValid ? Color.blue : Color.secondary.opacity(0.4))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!isValid || isLoading)
            .padding(.horizontal, 24)
            .padding(.bottom, 52)
        }
        .onAppear { isNameFocused = true }
    }
}

#Preview {
    NameEntryView()
        .environmentObject(AuthService())
}
