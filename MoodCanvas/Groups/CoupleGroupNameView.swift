import SwiftUI

struct CoupleGroupNameView: View {
    @EnvironmentObject var groupService: GroupService
    @EnvironmentObject var authService: AuthService

    let partnerMoodiUsers: [User]
    let partnerNonMoodi: [ContactEntry]
    let onComplete: () -> Void

    @State private var groupName = ""
    @State private var isCreating = false
    @State private var showTutorial = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color(hex: "F4AABB").ignoresSafeArea()
            Image("couples_bacgkround3")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Fixed top gap — anchors content near the top regardless of keyboard state
                Spacer().frame(height: 110)

                Text("Group Name")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: "51083A"))

                Spacer().frame(height: 48)

                // Text field with custom placeholder
                ZStack(alignment: .center) {
                    if groupName.isEmpty {
                        Text("the cutest couple 💗")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(hex: "C01A8C").opacity(0.3))
                            .multilineTextAlignment(.center)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $groupName, axis: .vertical)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: "51083A"))
                        .multilineTextAlignment(.center)
                        .focused($isFocused)
                        .tint(Color(hex: "C01A8C"))
                        .lineLimit(1...3)
                }
                .padding(.horizontal, 44)

                // Single flexible spacer — absorbs all remaining space below the text field
                Spacer()
            }
        }
        // safeAreaInset always sits above the keyboard (unlike .overlay which uses
        // the full ZStack frame and can end up behind the keyboard)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            doneButton
                .padding(.horizontal, 88)
                .padding(.vertical, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showTutorial) {
            WidgetTutorialView(onDismiss: onComplete)
        }
        .onAppear { isFocused = true }
    }

    // MARK: - Done button

    private var doneButton: some View {
        Button { createGroup() } label: {
            Text(isCreating ? "creating..." : "done!")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background {
                    Capsule()
                        .fill(Color(hex: "C01A8C"))
                        .overlay {
                            Capsule()
                                .strokeBorder(Color(hex: "51083A").opacity(0.4), lineWidth: 5)
                        }
                }
        }
        .buttonStyle(.plain)
        .disabled(isCreating)
    }

    // MARK: - Create

    private func createGroup() {
        Task {
            isCreating = true
            let trimmed = groupName.trimmingCharacters(in: .whitespaces)
            let name = trimmed.isEmpty ? "the cutest couple" : trimmed
            let groupId = await groupService.createGroup(
                name: name,
                type: .couple,
                members: partnerMoodiUsers
            )
            if let groupId, let jwt = KeychainService.load(.supabaseJWT) {
                for entry in partnerNonMoodi {
                    await EdgeFunctionService.inviteByPhone(groupId: groupId, phone: entry.phone, jwt: jwt)
                }
            }
            isCreating = false
            showTutorial = true
        }
    }
}
