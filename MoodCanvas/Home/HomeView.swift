import SwiftUI
import StoreKit

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var groupService = GroupService()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    @State private var showCreateGroup    = false
    @State private var showPaywall        = false
    @State private var showSettings       = false
    @State private var showWidgetTutorial = false
    @State private var selectedGroup: MoodGroup?
    @State private var renamingGroup: MoodGroup?
    @AppStorage("isPremium") private var isPremium = false

    private static let freeGroupLimit = 3

    var body: some View {
        NavigationStack {
            Group {
                if groupService.groups.isEmpty && groupService.pendingInvitations.isEmpty {
                    // Wrap in a ScrollView so pull-to-refresh works even in empty state.
                    // Without this the recipient of an invitation has no way to manually
                    // trigger fetchPendingInvitations() while the app is in the foreground.
                    ScrollView {
                        EmptyHomeView(onCreateGroup: requestContactsThenCreate)
                            .containerRelativeFrame(.vertical)
                    }
                    .background(Color(hex: "FFFCED").ignoresSafeArea())
                    .refreshable {
                        let t1 = Task { await groupService.fetchGroups() }
                        let t2 = Task { await groupService.fetchPendingInvitations() }
                        await t1.value; await t2.value
                    }
                } else {
                    groupList
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                GroupTypePickerView()
                    .environmentObject(groupService)
                    .environmentObject(authService)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .fullScreenCover(isPresented: $showWidgetTutorial) {
                WidgetTutorialView(onDismiss: { showWidgetTutorial = false })
            }
            .sheet(item: $renamingGroup) { group in
                EditGroupNameSheet(initialName: group.name) { newName in
                    Task { await groupService.renameGroup(id: group.id, newName: newName) }
                }
            }
            .task {
                // Show App Store rating prompt once, right after first onboarding completion.
                // The flag is set by AuthService.setName() and cleared here immediately so
                // it never fires again (even if the user backgrounds and returns).
                if UserDefaults.standard.bool(forKey: "requestRatingAfterOnboarding") {
                    UserDefaults.standard.removeObject(forKey: "requestRatingAfterOnboarding")
                    try? await Task.sleep(for: .seconds(1.5))
                    requestReview()
                }
                // Verify premium entitlements against App Store on every launch.
                // This correctly handles subscription renewals, expirations, and
                // restores after re-installs without requiring the user to tap "Restore".
                var hasPremium = false
                for await result in Transaction.currentEntitlements {
                    if case .verified(let tx) = result,
                       ["com.huseyinturkay.moodcanvas.app.weekly",
                        "com.huseyinturkay.moodcanvas.app.yearly",
                        "com.huseyinturkay.moodcanvas.app.lifetime"].contains(tx.productID) {
                        hasPremium = true
                    }
                }
                isPremium = hasPremium
                let t1 = Task { await groupService.fetchGroups() }
                let t2 = Task { await groupService.fetchPendingInvitations() }
                await t1.value; await t2.value
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await authService.refreshJWTIfNeeded()
                        await groupService.processPendingWidgetMoods(currentUserId: authService.currentUser?.id)
                        let t1 = Task { await groupService.fetchGroups() }
                        let t2 = Task { await groupService.fetchPendingInvitations() }
                        await t1.value; await t2.value
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .moodUpdateReceived)) { _ in
                // Refresh both groups AND invitations — a silent push can arrive for
                // a mood update OR an invitation/acceptance event. Always fetching
                // invitations ensures the invitation card appears the moment a push
                // wakes the app while it's in the foreground.
                Task {
                    let t1 = Task { await groupService.fetchGroups() }
                    let t2 = Task { await groupService.fetchPendingInvitations() }
                    await t1.value; await t2.value
                }
            }
            // Poll every 10 s while this screen is active.
            // Mirrors GroupDetailView's pattern so HomeView stays live even when
            // silent pushes don't arrive (simulator has no APNs token; iOS also
            // skips or delays background pushes in low-power mode).
            // .task(id: scenePhase) is automatically cancelled and restarted on
            // every phase change, so the loop pauses in the background.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { break }
                    let t1 = Task { await groupService.fetchGroups() }
                    let t2 = Task { await groupService.fetchPendingInvitations() }
                    await t1.value; await t2.value
                }
            }
        }
    }

    // MARK: - Group list (full custom layout)

    private var groupList: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "FFFCED").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Invitation cards — shown above group cards
                    ForEach(groupService.pendingInvitations) { invitation in
                        InvitationCardView(
                            invitation: invitation,
                            onDecline: {
                                Task { await groupService.respondToInvitation(invitation.id, accept: false) }
                            },
                            onAccept: {
                                Task { await groupService.respondToInvitation(invitation.id, accept: true) }
                            }
                        )
                    }

                    // Group cards
                    ForEach(groupService.groups) { group in
                        GroupCardView(
                            group: group,
                            currentUserId: authService.currentUser?.id ?? "",
                            onMoodTap: { mood in
                                Task {
                                    if let userId = authService.currentUser?.id {
                                        await groupService.updateMood(mood, for: userId, in: group.id)
                                    }
                                }
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedGroup = group }
                    }

                    // Bottom padding so last card isn't hidden by floating button
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
            }
            .refreshable {
                let t1 = Task { await groupService.fetchGroups() }
                let t2 = Task { await groupService.fetchPendingInvitations() }
                await t1.value; await t2.value
            }
            .navigationDestination(item: $selectedGroup) { group in
                GroupDetailView(group: group)
                    .environmentObject(groupService)
                    .environmentObject(authService)
            }

            // Floating "create a group" button — bottom z-layer
            floatingCreateButton
                .padding(.horizontal, 64)
                .padding(.bottom, 32)
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            ShareLink(item: "Track your friends' moods right from your home screen. Download Moodi now: https://apps.apple.com/app/moodi") {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(hex: "B8721C")))
            }
            .buttonStyle(.plain)
            .padding(.leading, 24)
            .padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "3C392A").opacity(0.5))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(hex: "EDE8D8")))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 24)
            .padding(.top, 8)
        }
        .background(
            UIKitActionSheet(isPresented: $showSettings) { dismiss in
                var actions: [UIAlertAction] = []
                actions.append(UIAlertAction(title: "How to add the widget", style: .default) { _ in
                    dismiss(); showWidgetTutorial = true
                })
                actions.append(UIAlertAction(title: "Follow us on TikTok", style: .default) { _ in
                    dismiss()
                    if let url = URL(string: "https://www.tiktok.com/@moodi.widget.app") {
                        UIApplication.shared.open(url)
                    }
                })
                actions.append(UIAlertAction(title: "I need help", style: .default) { _ in
                    dismiss()
                    if let url = URL(string: "mailto:info@nocap.bio") {
                        UIApplication.shared.open(url)
                    }
                })
                #if DEBUG
                actions.append(UIAlertAction(title: "💳 Show Paywall", style: .default) { _ in
                    dismiss(); showPaywall = true
                })
                actions.append(UIAlertAction(title: "🧪 Load 8-member test group", style: .default) { _ in
                    dismiss(); groupService.loadMockGroups()
                })
                actions.append(UIAlertAction(title: "🗑 Clear test groups", style: .default) { _ in
                    dismiss(); groupService.clearMockGroups()
                })
                #endif
                actions.append(UIAlertAction(title: "Sign out", style: .destructive) { _ in
                    dismiss(); authService.signOut()
                })
                actions.append(UIAlertAction(title: "Cancel", style: .cancel) { _ in dismiss() })
                return actions
            }
        )
    }

    // MARK: - Floating create button

    private var floatingCreateButton: some View {
        Button(action: requestContactsThenCreate) {
            ZStack {
                Text("create a group")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)
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
                    .overlay {
                        Capsule()
                            .strokeBorder(Color(hex: "3C392A").opacity(0.4), lineWidth: 5)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func requestContactsThenCreate() {
        showCreateGroup = true
    }
}

// MARK: - UIKit Action Sheet
// iOS 26 changed confirmationDialog to a centered modal — this restores the old bottom sheet.

private struct UIKitActionSheet: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let buildActions: (_ dismiss: @escaping () -> Void) -> [UIAlertAction]

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard isPresented, uiViewController.presentedViewController == nil else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let dismiss = { isPresented = false }
        for action in buildActions(dismiss) { sheet.addAction(action) }
        DispatchQueue.main.async { uiViewController.present(sheet, animated: true) }
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthService())
}
