import SwiftUI

struct VerificationView: View {
    @EnvironmentObject var authService: AuthService
    let phoneNumber: String

    @State private var code = ""
    @State private var isLoading = false
    @FocusState private var isCodeFocused: Bool

    private var isValid: Bool { code.count == 6 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Text("Enter the code")
                    .font(.largeTitle.bold())

                Text("Sent to \(phoneNumber)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)

            // OTP field
            TextField("000000", text: $code)
                .keyboardType(.numberPad)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .tracking(10)
                .frame(height: 60)
                .focused($isCodeFocused)
                .onChange(of: code) { _, newValue in
                    let filtered = String(newValue.filter { $0.isNumber }.prefix(6))
                    if code != filtered { code = filtered }
                }

            Spacer()

            Button {
                Task {
                    isLoading = true
                    await authService.verifyCode(code, for: phoneNumber)
                    isLoading = false
                }
            } label: {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Verify")
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
            .padding(.bottom, 8)

            if let error = authService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
            } else {
                Spacer().frame(height: 52)
            }
        }
        .onAppear { isCodeFocused = true }
    }
}

#Preview {
    NavigationStack {
        VerificationView(phoneNumber: "+1 (555) 000-0000")
            .environmentObject(AuthService())
    }
}
