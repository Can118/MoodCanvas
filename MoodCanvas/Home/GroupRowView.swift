import SwiftUI

struct GroupRowView: View {
    let group: MoodGroup

    var body: some View {
        HStack(spacing: 12) {
            // Group type icon
            RoundedRectangle(cornerRadius: 10)
                .fill(group.type.backgroundGradient)
                .frame(width: 46, height: 46)
                .overlay {
                    Text(group.type.icon)
                        .font(.title3)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.subheadline.bold())
                Text("\(group.type.displayName) · \(group.members.count) member\(group.members.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Latest moods preview
            HStack(spacing: -4) {
                ForEach(Array(group.currentMoods.prefix(3)), id: \.key) { _, mood in
                    Text(mood.emoji)
                        .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        GroupRowView(group: .preview)
        GroupRowView(group: .couplePreview)
        GroupRowView(group: .familyPreview)
    }
}
