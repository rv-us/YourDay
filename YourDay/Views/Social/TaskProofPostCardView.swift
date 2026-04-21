import SwiftUI
import FirebaseAuth

struct TaskProofPostCardView: View {
    let post: TaskProofPost
    let votes: [TaskProofVote]
    var onVote: (TaskProofVoteType) -> Void
    var onDelete: () -> Void

    private var currentUserVote: TaskProofVoteType? {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return nil }
        return votes.first(where: { $0.voterId == currentUserId })?.voteType
    }

    private var checkVotes: [TaskProofVote] {
        votes.filter { $0.voteType == .check }
    }

    private var xVotes: [TaskProofVote] {
        votes.filter { $0.voteType == .xmark }
    }

    private var isAuthor: Bool {
        post.authorId == Auth.auth().currentUser?.uid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorDisplayName)
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                    Text(post.taskTitle)
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                Spacer()
                Text(post.completedAt, style: .time)
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
            }

            AsyncImage(url: URL(string: post.photoURL)) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(dynamicSecondaryBackgroundColor)
                        ProgressView()
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(dynamicSecondaryBackgroundColor)
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            // `.clipped()` clips both visual *and* hit-testing bounds; without it a
            // `.scaledToFill` image can overflow its 240pt frame (especially for square/portrait
            // photos) and silently cover the check/X/Delete row below it, swallowing taps.
            .clipped()
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                voteButton(
                    title: "\(checkVotes.count)",
                    systemImage: "checkmark.circle.fill",
                    isSelected: currentUserVote == .check,
                    action: { onVote(.check) }
                )

                voteButton(
                    title: "\(xVotes.count)",
                    systemImage: "xmark.circle.fill",
                    isSelected: currentUserVote == .xmark,
                    action: { onVote(.xmark) }
                )

                Spacer()

                if isAuthor {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("✓: \(checkVotes.map(\.voterDisplayName).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                Text("✗: \(xVotes.map(\.voterDisplayName).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
        }
        .padding(14)
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(14)
    }

    @ViewBuilder
    private func voteButton(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(isSelected ? .white : dynamicTextColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? dynamicPrimaryColor : dynamicBackgroundColor)
            .cornerRadius(9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}
