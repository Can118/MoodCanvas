import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Logo
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [.purple, .pink],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                        .frame(width: 120, height: 120)
                    Text("😊")
                        .font(.system(size: 60))
                }
                .padding(.bottom, 32)

                VStack(spacing: 12) {
                    Text("MoodCanvas")
                        .font(.largeTitle.bold())

                    Text("Share how you're feeling\nwith the people that matter most.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 40)
                }

                Spacer()

                NavigationLink(destination: PhoneNumberView()) {
                    Text("Let's Go")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
            }
        }
    }
}

#Preview {
    WelcomeView()
}
