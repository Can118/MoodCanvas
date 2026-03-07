import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        ZStack {
            // Real content is always rendered at full opacity underneath —
            // this prevents the window background from ever bleeding through.
            if authService.isAuthenticated {
                if authService.needsNameEntry {
                    NameEntryView()
                } else {
                    HomeView()
                }
            } else {
                WelcomeView()
            }

            // Cream splash sits on top and fades away once auth is resolved.
            // Because the real content is underneath at full opacity, fading
            // out this overlay can never expose a dark/black background.
            if authService.isRestoringSession {
                Color(hex: "FFFCED")
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: authService.isRestoringSession)
        .animation(.easeInOut, value: authService.isAuthenticated)
        .animation(.easeInOut, value: authService.needsNameEntry)
    }
}
