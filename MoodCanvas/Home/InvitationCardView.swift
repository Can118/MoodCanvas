import SwiftUI

struct InvitationCardView: View {
    let invitation: GroupInvitationDetail
    let onDecline: () -> Void
    let onAccept: () -> Void

    var body: some View {
        ZStack {
            // Background PNG
            Image("invitation_card")
                .resizable()
                .scaledToFill()

            VStack(alignment: .leading, spacing: 20) {
                // Header text: "[name] is inviting you to join [group name]"
                inviteText

                // Buttons row
                HStack(spacing: 12) {
                    declineButton
                    acceptButton
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 150)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    // MARK: - Invite text

    private var inviteText: some View {
        // Build attributed string: normal weight for most, bold for group name
        let regularAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "EBGaramond-SemiBold", size: 20) ?? UIFont.systemFont(ofSize: 20),
            .foregroundColor: UIColor(Color(hex: "837C5A")),
        ]
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "EBGaramond-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20),
            .foregroundColor: UIColor(Color(hex: "665938")),
        ]

        let full = NSMutableAttributedString()
        full.append(NSAttributedString(string: invitation.inviterName, attributes: boldAttrs))
        full.append(NSAttributedString(string: " is inviting you to join ", attributes: regularAttrs))
        full.append(NSAttributedString(string: invitation.groupName, attributes: boldAttrs))

        return Text(AttributedString(full))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Decline button

    private var declineButton: some View {
        Button(action: onDecline) {
            Text("Decline")
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(Color(hex: "837C5A"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "FEF9DD"))
                        .shadow(color: Color(hex: "3C2A0E").opacity(0.35), radius: 2, x: 0, y: 4)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accept button

    private var acceptButton: some View {
        Button(action: onAccept) {
            Text("Accept")
                .font(.system(.callout, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "B8721C"))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.black.opacity(0.20), lineWidth: 3)
                        }
                        .shadow(color: Color(hex: "3C2A0E").opacity(0.35), radius: 2, x: 0, y: 4)
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    InvitationCardView(
        invitation: GroupInvitationDetail(
            id: "1",
            groupId: "g1",
            groupName: "monkeys without bananas",
            groupType: .bff,
            inviterName: "Emilyy<3",
            inviterId: "u1"
        ),
        onDecline: {},
        onAccept: {}
    )
    .padding(20)
    .background(Color(hex: "FFFCED"))
}
