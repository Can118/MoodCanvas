import SwiftUI

struct NameEntryView: View {
    @EnvironmentObject var authService: AuthService
    @State private var name = ""
    @State private var isLoading = false
    @FocusState private var isFocused: Bool

    private var isValid: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        ZStack {
            Color(hex: "FFFCED").ignoresSafeArea()

            // Back button
            VStack {
                HStack {
                    Button { authService.signOut() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(hex: "3C392A"))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 12)
                    .padding(.top, 8)
                    Spacer()
                }
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer().frame(height: 120)

                // Title
                Text("What's your first name?")
                    .font(Font.custom("EBGaramond-Medium", size: 28))
                    .foregroundStyle(Color(hex: "3C392A"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Spacer().frame(height: 28)

                // Name input
                TextField("", text: $name)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "3C392A"))
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .tint(Color(hex: "B8721C"))
                    .frame(height: 60)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "FFFBE5")))
                    .shadow(color: Color(hex: "3C392A").opacity(0.10), radius: 12, x: 0, y: 5)
                    .padding(.horizontal, 28)

                Spacer()

                // Error (if any)
                if let error = authService.errorMessage {
                    Text(error)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 8)
                }

                // Done button
                Button {
                    Task {
                        isLoading = true
                        await authService.setName(name.trimmingCharacters(in: .whitespaces))
                        isLoading = false
                    }
                } label: {
                    doneButtonLabel
                }
                .buttonStyle(.plain)
                .disabled(!isValid || isLoading)
                .opacity(isValid ? 1 : 0.5)
                .padding(.horizontal, 40)

                Spacer().frame(height: 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .onAppear { isFocused = true }
    }

    private var doneButtonLabel: some View {
        ZStack {
            if isLoading {
                ProgressView().tint(.white)
            } else {
                Text("Done!")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background {
            Capsule()
                .fill(Color(hex: "B8721C"))
                .overlay {
                    Capsule()
                        .strokeBorder(Color(hex: "3C392A").opacity(0.4), lineWidth: 5)
                }
        }
    }
}

#Preview {
    NameEntryView()
        .environmentObject(AuthService())
}
