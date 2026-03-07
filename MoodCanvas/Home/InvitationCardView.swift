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
                .clipped()

            VStack(alignment: .center, spacing: 14) {
                // Header text: "[name] is inviting you to join [group name]"
                inviteText

                // Buttons row — extra horizontal padding narrows the buttons
                HStack(spacing: 10) {
                    declineButton
                    acceptButton
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 130)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 12)  // scales the card down from the edges
    }

    // MARK: - Invite text

    private var inviteText: some View {
        // Regular (thinner) for inviter name + body text; bold + accent only for group name
        let regularAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "EBGaramond-Regular", size: 19) ?? UIFont.systemFont(ofSize: 19),
            .foregroundColor: UIColor(Color(hex: "837C5A")),
        ]
        let groupNameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "EBGaramond-Bold", size: 19) ?? UIFont.boldSystemFont(ofSize: 19),
            .foregroundColor: UIColor(Color(hex: "665938")),
        ]

        let full = NSMutableAttributedString()
        full.append(NSAttributedString(string: invitation.inviterName, attributes: regularAttrs))
        full.append(NSAttributedString(string: " is inviting you to join ", attributes: regularAttrs))
        full.append(NSAttributedString(string: invitation.groupName, attributes: groupNameAttrs))

        return Text(AttributedString(full))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Decline button

    private var declineButton: some View {
        Button(action: onDecline) {
            Text("Decline")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "837C5A"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 12)
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
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "B8721C"))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
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
