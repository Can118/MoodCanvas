import SwiftUI

struct VerificationView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    let phoneNumber: String

    @State private var code = ""
    @State private var isLoading = false
    @State private var countdown = 30
    @State private var canResend = false
    @FocusState private var isFocused: Bool

    private var isValid: Bool { code.count == 6 }

    var body: some View {
        ZStack {
            Color(hex: "FFFCED").ignoresSafeArea()

            // Back button
            VStack {
                HStack {
                    Button { dismiss() } label: {
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
                Text("Verify your number")
                    .font(Font.custom("EBGaramond-Medium", size: 28))
                    .foregroundStyle(Color(hex: "3C392A"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Spacer().frame(height: 28)

                // Code input
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "3C392A"))
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .tint(Color(hex: "B8721C"))
                    .frame(height: 60)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "FFFBE5")))
                    .shadow(color: Color(hex: "3C392A").opacity(0.10), radius: 12, x: 0, y: 5)
                    .padding(.horizontal, 28)
                    .onChange(of: code) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(6))
                        if code != digits { code = digits }
                    }

                Spacer().frame(height: 20)

                // Sent to + countdown/resend
                VStack(spacing: 8) {
                    Text("Sent to \(phoneNumber)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "837C5A"))

                    if canResend {
                        Button {
                            Task {
                                canResend = false
                                countdown = 30
                                await authService.sendVerificationCode(to: phoneNumber)
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Resend Code")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(Color(hex: "3C392A"))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color(hex: "EDE8D8")))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Try again in \(countdown) secs")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Color(hex: "837C5A"))
                    }
                }

                Spacer()

                // Error
                if let error = authService.errorMessage {
                    Text(error)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 8)
                }

                // Next button
                Button {
                    Task {
                        isLoading = true
                        await authService.verifyCode(code, for: phoneNumber)
                        isLoading = false
                    }
                } label: {
                    nextButtonLabel
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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard !canResend else { return }
            if countdown > 0 { countdown -= 1 } else { canResend = true }
        }
    }

    private var nextButtonLabel: some View {
        ZStack {
            if isLoading {
                ProgressView().tint(.white)
            } else {
                Text("Next")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)
                HStack {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 17, weight: .black))
                        .padding(.trailing, 26)
                }
                .foregroundStyle(.white)
            }
        }
        .foregroundStyle(.white)
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
    NavigationStack {
        VerificationView(phoneNumber: "+15551234567")
            .environmentObject(AuthService())
    }
}
