import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        Group {
            if authService.isAuthenticated {
                if authService.needsNameEntry {
                    NameEntryView()
                } else {
                    HomeView()
                }
            } else {
                WelcomeView()
            }
        }
        .animation(.easeInOut, value: authService.isAuthenticated)
        .animation(.easeInOut, value: authService.needsNameEntry)
    }
}
