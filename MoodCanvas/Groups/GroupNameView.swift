import SwiftUI

struct GroupNameView: View {
    @EnvironmentObject var groupService: GroupService
    @EnvironmentObject var authService: AuthService

    let selectedType: GroupType
    let onComplete: () -> Void

    @State private var groupName = ""
    @FocusState private var isFocused: Bool

    private var isValid: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "FFFCED").ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Label
                Text("Group Name")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: "837C5A"))

                Spacer().frame(height: 32)

                // Text input with custom placeholder
                ZStack(alignment: .center) {
                    // Placeholder — fades out as soon as typing starts
                    if groupName.isEmpty {
                        Text("Sisters without Misters")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(hex: "665938").opacity(0.24))
                            .multilineTextAlignment(.center)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $groupName, axis: .vertical)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: "665938"))
                        .multilineTextAlignment(.center)
                        .focused($isFocused)
                        .tint(Color(hex: "665938"))
                        .lineLimit(1...3)
                }
                .padding(.horizontal, 44)

                Spacer()

                // Next button
                NavigationLink {
                    GroupAddFriendsView(
                        selectedType: selectedType,
                        groupName: groupName,
                        onComplete: onComplete
                    )
                    .environmentObject(groupService)
                    .environmentObject(authService)
                } label: {
                    nextButtonLabel
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.45)
                .padding(.horizontal, 48)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { isFocused = true }
    }

    // MARK: - Next button

    private var nextButtonLabel: some View {
        ZStack {
            Text("next")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .black))
                    .padding(.trailing, 26)
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
}

#Preview {
    NavigationStack {
        GroupNameView(selectedType: .bff, onComplete: {})
            .environmentObject(GroupService())
            .environmentObject(AuthService())
    }
}
