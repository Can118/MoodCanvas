import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "FFFCED").ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer().frame(height: 36)

                    // Phone illustration
                    Image("onboarding_iphone_2")
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 40)

                    Spacer().frame(height: 40)

                    // Tagline
                    Text("Live moods of your friends &\ncouples on your home screen")
                        .font(Font.custom("EBGaramond-Medium", size: 26))
                        .foregroundStyle(Color(hex: "493504"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)

                    Spacer().frame(height: 36)

                    // Let's Go button
                    NavigationLink {
                        PhoneNumberView()
                    } label: {
                        letsGoLabel
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 48)

                    Spacer().frame(height: 48)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Let's Go button

    private var letsGoLabel: some View {
        ZStack {
            Text("Let's Go")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .black))
                    .padding(.trailing, 26)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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
    WelcomeView()
}
