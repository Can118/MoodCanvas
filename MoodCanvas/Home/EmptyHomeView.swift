import SwiftUI
import UserNotifications

struct EmptyHomeView: View {
    let onCreateGroup: () -> Void

    @State private var notifStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        ZStack {
            Color(hex: "FFFCED").ignoresSafeArea()

            VStack(spacing: 0) {
//                if notifStatus == .notDetermined {
//                    notificationBanner
//                        .padding(.horizontal, 20)
//                        .padding(.top, 20)
//                }

                Spacer()

                emptyStateText
                    .padding(.horizontal, 24)
                    .padding(.top, 48)

                Spacer()

                createGroupButton
                    .padding(.horizontal, 64)
                    .padding(.bottom, 48)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notifStatus = settings.authorizationStatus
        }
    }

    // MARK: - Notification banner

    private var notificationBanner: some View {
        VStack(spacing: 14) {
            Text("see new mood updates instantly!")
                .font(Font.custom("EBGaramond-Medium", size: 18))
                .foregroundStyle(Color(hex: "3C392A"))
                .multilineTextAlignment(.center)

            Button(action: requestNotifications) {
                ZStack {
                    Text("tap to turn on")
                        .font(.system(.callout, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)

                    HStack {
                        Spacer()
                        Image(systemName: "bell.fill")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.trailing, 20)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                // Shadow lives on the shape only — text and icon cast no shadow
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "F5AA40"))
                        .shadow(color: Color(hex: "3C2A0E").opacity(0.45), radius: 2, x: 1, y: 4)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "FFF8D4"))
        )
    }

    // MARK: - Empty state text

    private var emptyStateText: some View {
        VStack(spacing: 4) {
            Text("Looks like there's nothing here!")
            Text("Why not creating a group?")
        }
        .font(.system(size: 21, weight: .bold, design: .rounded))
        .foregroundStyle(Color(hex: "3C392A"))
        .multilineTextAlignment(.center)
    }

    // MARK: - Create group button

    private var createGroupButton: some View {
        Button(action: onCreateGroup) {
            ZStack {
                // "create a group" centered in the full button width
                Text("create a group")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)

                // "+" pinned to the trailing edge
                HStack {
                    Spacer()
                    Text("+")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .padding(.trailing, 24)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background {
                Capsule()
                    .fill(Color(hex: "B8721C"))
                    // MARK: Glass shimmer (disabled — re-enable when ready)
//                    .overlay {
//                        // Shimmer clipped to capsule bounds
//                        GeometryReader { geo in
//                            GlassShimmer(buttonWidth: geo.size.width)
//                        }
//                        .clipShape(Capsule())
//                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Color(hex: "3C392A").opacity(0.4), lineWidth: 5)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            Task { @MainActor in
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                notifStatus = settings.authorizationStatus
            }
        }
    }
}

// MARK: - Glass shimmer overlay (disabled — uncomment to re-enable)

///// Diagonal white gradient that sweeps left→right every ~2.5s,
///// matching the "sharp glass" animation from the nocap create-a-poll button.
//private struct GlassShimmer: View {
//    let buttonWidth: CGFloat
//
//    @State private var offsetX: CGFloat = 0
//
//    // Shimmer strip is 38% of button width; extra margin absorbs the skew overhang
//    private var shimmerWidth: CGFloat { buttonWidth * 0.38 }
//    private var startX: CGFloat { -(shimmerWidth + 40) }
//    private var endX:   CGFloat {   buttonWidth + 40 }
//
//    var body: some View {
//        LinearGradient(
//            stops: [
//                .init(color: .white.opacity(0),    location: 0),
//                .init(color: .white.opacity(0.28), location: 0.35),
//                .init(color: .white.opacity(0.12), location: 0.65),
//                .init(color: .white.opacity(0),    location: 1),
//            ],
//            startPoint: .leading,
//            endPoint: .trailing
//        )
//        .frame(width: shimmerWidth)
//        // -20° horizontal shear: CGAffineTransform(a:1 b:0 c:tan(-20°)≈-0.364 d:1)
//        .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.364, d: 1, tx: 0, ty: 0))
//        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
//        .offset(x: offsetX)
//        .onAppear {
//            offsetX = startX
//            sweep()
//        }
//    }
//
//    private func sweep() {
//        // 2 s idle → 0.5 s linear sweep → reset → repeat
//        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
//            withAnimation(.linear(duration: 0.5)) {
//                offsetX = endX
//            }
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
//                offsetX = startX   // instant reset (off-screen, not visible)
//                sweep()
//            }
//        }
//    }
//}

#Preview {
    EmptyHomeView(onCreateGroup: {})
}
