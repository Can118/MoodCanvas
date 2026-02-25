import SwiftUI

struct PhoneNumberView: View {
    @EnvironmentObject var authService: AuthService

    @State private var phoneNumber = ""
    @State private var isLoading = false
    @State private var navigateToVerification = false
    @FocusState private var isPhoneFieldFocused: Bool

    private var isValid: Bool { phoneNumber.count >= 10 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Text("What's your number?")
                    .font(.largeTitle.bold())

                Text("We'll send you a one-time verification code.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 40)

            // Phone input field
            HStack(spacing: 8) {
                Text("🇺🇸 +1")
                    .font(.body)
                    .padding(.leading, 14)

                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 1, height: 22)

                TextField("(000) 000-0000", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .focused($isPhoneFieldFocused)
                    .font(.body)
                    .padding(.trailing, 14)
            }
            .frame(height: 52)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)

            Spacer()

            // Error message
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
                    await authService.sendVerificationCode(to: phoneNumber)
                    isLoading = false
                    // Only navigate if no error was set
                    if authService.errorMessage == nil {
                        navigateToVerification = true
                    }
                }
            } label: {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Send Code")
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
            .navigationDestination(isPresented: $navigateToVerification) {
                VerificationView(phoneNumber: phoneNumber)
            }
        }
        .navigationBarBackButtonHidden(false)
        .onAppear { isPhoneFieldFocused = true }
    }
}

#Preview {
    NavigationStack {
        PhoneNumberView()
            .environmentObject(AuthService())
    }
}
