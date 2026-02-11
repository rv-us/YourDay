import SwiftUI
import FirebaseFirestore

struct TaskProofFeedView: View {
    @EnvironmentObject private var firebaseManager: FirebaseManager

    @State private var posts: [TaskProofPost] = []
    @State private var feedToken: TaskProofFeedListenerToken?
    @State private var voteListeners: [String: ListenerRegistration] = [:]
    @State private var votesByPostId: [String: [TaskProofVote]] = [:]

    var body: some View {
        ScrollView {
            if posts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 32))
                        .foregroundColor(dynamicSecondaryTextColor)
                    Text("No proof posts yet")
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                    Text("Complete a task and share a photo proof to get started.")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 80)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(posts) { post in
                        TaskProofPostCardView(
                            post: post,
                            votes: votesByPostId[post.id ?? ""] ?? [],
                            onVote: { voteType in
                                guard let postId = post.id else { return }
                                firebaseManager.setTaskProofVote(postId: postId, voteType: voteType) { error in
                                    if let error = error {
                                        print("Failed to set proof vote: \(error.localizedDescription)")
                                    }
                                }
                            },
                            onDelete: {
                                guard let postId = post.id else { return }
                                firebaseManager.deleteTaskProofPost(postId: postId) { error in
                                    if let error = error {
                                        print("Failed to delete proof post: \(error.localizedDescription)")
                                    }
                                }
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
        .navigationTitle("Proof Feed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            startFeedListener()
        }
        .onDisappear {
            tearDownListeners()
        }
    }

    private func startFeedListener() {
        tearDownListeners()
        feedToken = firebaseManager.listenToTaskProofFeed { updatedPosts in
            DispatchQueue.main.async {
                posts = updatedPosts
                syncVoteListeners(for: updatedPosts)
            }
        }
    }

    private func syncVoteListeners(for updatedPosts: [TaskProofPost]) {
        let postIds = Set(updatedPosts.compactMap(\.id))

        for (postId, listener) in voteListeners where !postIds.contains(postId) {
            listener.remove()
            voteListeners.removeValue(forKey: postId)
            votesByPostId.removeValue(forKey: postId)
        }

        for postId in postIds where voteListeners[postId] == nil {
            let listener = firebaseManager.listenToTaskProofVotes(postId: postId) { votes in
                DispatchQueue.main.async {
                    votesByPostId[postId] = votes
                }
            }
            voteListeners[postId] = listener
        }
    }

    private func tearDownListeners() {
        feedToken?.remove()
        feedToken = nil

        voteListeners.values.forEach { $0.remove() }
        voteListeners.removeAll()
        votesByPostId.removeAll()
    }
}
