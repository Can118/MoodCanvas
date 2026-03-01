import SwiftUI

/// Paywall shown when a free-plan user tries to exceed 3 groups.
/// Replace the body with the final design when ready.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // TODO: replace with final paywall design
        ZStack {
            Color(hex: "FFFCED").ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Upgrade to Pro")
                    .font(Font.custom("EBGaramond-Bold", size: 32))
                    .foregroundStyle(Color(hex: "3C392A"))
                Text("Paywall design coming soon.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color(hex: "3C392A").opacity(0.6))
                Button("Close") { dismiss() }
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .foregroundStyle(Color(hex: "B8721C"))
            }
            .padding(40)
        }
    }
}

#Preview {
    PaywallView()
}
