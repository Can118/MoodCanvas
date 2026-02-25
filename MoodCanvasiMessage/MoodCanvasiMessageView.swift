import SwiftUI

struct MoodCanvasiMessageView: View {
    let onSendCanvas: (MoodGroup) -> Void

    @State private var groups: [MoodGroup] = []
    @State private var selectedGroupId: String?
    @State private var isLoading = true

    private var selectedGroup: MoodGroup? {
        groups.first { $0.id == selectedGroupId }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Send a Mood Canvas")
                .font(.headline)
                .padding(.vertical, 14)

            Divider()

            // Group list
            Group {
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if groups.isEmpty {
                    Spacer()
                    Text("No groups yet.\nCreate one in the MoodCanvas app.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding()
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(groups) { group in
                                GroupCanvasCard(
                                    group: group,
                                    isSelected: selectedGroupId == group.id
                                )
                                .onTapGesture {
                                    selectedGroupId = group.id
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .task {
                await loadGroups()
            }

            Divider()

            // Send button
            Button {
                if let group = selectedGroup {
                    onSendCanvas(group)
                }
            } label: {
                Text("Send Canvas")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedGroup != nil ? Color.blue : Color.secondary.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(selectedGroup == nil)
            .padding(16)
        }
    }

    // MARK: - Data Loading

    private func loadGroups() async {
        // 1. Try the App Group cache first (same data the widget uses)
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        if let data = defaults?.data(forKey: "widget_groups"),
           let cached = try? JSONDecoder().decode([MoodGroup].self, from: data),
           !cached.isEmpty {
            groups = cached
            isLoading = false
            return
        }
        // 2. Cache miss — fetch live from Supabase
        let fetched = await WidgetDataService.fetchGroups()
        groups = fetched
        isLoading = false
    }
}

// MARK: - Group Canvas Card

struct GroupCanvasCard: View {
    let group: MoodGroup
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            RoundedRectangle(cornerRadius: 10)
                .fill(group.type.backgroundGradient)
                .frame(width: 50, height: 50)
                .overlay { Text(group.type.icon).font(.title2) }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.subheadline.bold())

                // Mood summary
                let moodSummary = group.members.compactMap { member -> String? in
                    guard let mood = group.currentMoods[member.id] else { return nil }
                    return "\(member.name) \(mood.emoji)"
                }.joined(separator: " · ")

                Text(moodSummary.isEmpty ? "\(group.members.count) members" : moodSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Checkmark
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        }
    }
}
