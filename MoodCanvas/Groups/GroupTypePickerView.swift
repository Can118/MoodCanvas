import SwiftUI

struct GroupTypePickerView: View {
    @EnvironmentObject var groupService: GroupService
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: GroupType = .bff

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(hex: "FFFCED").ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Header
                    Text("Who's Joining?")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: "3C392A"))

                    Spacer().frame(height: 52)

                    // Type options
                    VStack(spacing: 16) {
                        typeOption(.bff,    label: "Friends")
                        typeOption(.couple, label: "Couples")
                        typeOption(.family, label: "Family")
                    }
                    .padding(.horizontal, 44)

                    Spacer()

                    // "next" button — navigates to name step
                    NavigationLink {
                        GroupNameView(selectedType: selectedType, onComplete: { dismiss() })
                            .environmentObject(groupService)
                            .environmentObject(authService)
                    } label: {
                        nextButtonLabel
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 48)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Type option pill

    @ViewBuilder
    private func typeOption(_ type: GroupType, label: String) -> some View {
        let selected = selectedType == type
        Button { selectedType = type } label: {
            HStack(spacing: 0) {
                // Circle indicator — invisible when not selected to keep text centered
                Circle()
                    .fill(selected ? Color(hex: "B8721C") : Color.clear)
                    .frame(width: 12, height: 12)
                    .padding(.leading, 22)

                Spacer()

                Text(label)
                    .font(Font.custom("EBGaramond-Medium", size: 21))
                    .foregroundStyle(Color(hex: "3C392A"))

                Spacer()

                // Mirror spacing on the right so text stays centered
                Color.clear
                    .frame(width: 12, height: 12)
                    .padding(.trailing, 22)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                Capsule()
                    .fill(Color(hex: "FFF8D4"))
                    // Approximate spread: -8 by shrinking the shadow shape
                    .shadow(color: Color(hex: "3C392A").opacity(0.15), radius: 14, x: 0, y: 6)
            }
            .overlay {
                if selected {
                    Capsule()
                        .strokeBorder(Color(hex: "B8721C"), lineWidth: 3.5)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.14), value: selectedType)
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
    GroupTypePickerView()
        .environmentObject(GroupService())
        .environmentObject(AuthService())
}
