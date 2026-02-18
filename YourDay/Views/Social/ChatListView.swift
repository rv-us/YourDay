//  ChatListView.swift
//  YourDay
//
//  Created by Rachit Verma on 8/2/25.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ChatListView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @EnvironmentObject var loginViewModel: LoginViewModel
    @State private var friends: [FriendEntry] = []
    @State private var lastMessages: [String: ChatMessage] = [:] // friendId: lastMessage
    @State private var lastSeen: [String: Date] = [:] // friendId: lastLogin
    @State private var listeners: [String: ListenerRegistration] = [:] // friendId: listener
    @AppStorage("readChatIds") private var readChatIdsRaw: String = ""
    @State private var openedChats: Set<String> = [] // tracks read messages persistently

    /// Friends ordered by most recent chat message first.
    private var sortedFriends: [FriendEntry] {
        friends.sorted { f1, f2 in
            let t1 = lastMessages[f1.userId]?.timestamp ?? .distantPast
            let t2 = lastMessages[f2.userId]?.timestamp ?? .distantPast
            return t1 > t2
        }
    }

    var body: some View {
        List {
            ForEach(sortedFriends) { friend in
                NavigationLink(destination: ChatDetailView(friend: friend)
                    .onAppear {
                        openedChats.insert(friend.userId)
                        saveOpenedChats()
                    }) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(dynamicPrimaryColor)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(friend.displayName)
                                    .font(.headline)
                                    .foregroundColor(dynamicTextColor)
                                Spacer(minLength: 8)
                                if let msg = lastMessages[friend.userId] {
                                    Text(formatTimestamp(msg.timestamp))
                                        .font(.caption2)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                }
                            }

                            if let msg = lastMessages[friend.userId] {
                                HStack(alignment: .center, spacing: 6) {
                                    Text(msg.content)
                                        .font(.subheadline)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                        .lineLimit(1)
                                    if msg.senderId == friend.userId && !openedChats.contains(friend.userId) {
                                        Circle()
                                            .fill(dynamicPrimaryColor)
                                            .frame(width: 8, height: 8)
                                    }
                                }
                            } else {
                                Text("Tap to chat")
                                    .font(.subheadline)
                                    .foregroundColor(dynamicSecondaryTextColor)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(dynamicSecondaryBackgroundColor)
                .listRowSeparatorTint(dynamicSecondaryTextColor.opacity(0.3))
            }

            if friends.isEmpty {
                Text("No friends to chat with yet.")
                    .font(.subheadline)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
        .navigationTitle("Chats")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadOpenedChats()
            firebaseManager.fetchAcceptedFriends { fetched in
                self.friends = fetched
                for friend in fetched {
                    // Realtime listener for last message
                    let listener = firebaseManager.listenToChat(with: friend.userId) { messages in
                        if let last = messages.last {
                            lastMessages[friend.userId] = last
                        }
                    }
                    listeners[friend.userId] = listener

                    // Static fetch for last login
                    firebaseManager.fetchLastLoginDate(for: friend.userId) { date in
                        if let date = date {
                            lastSeen[friend.userId] = date
                        }
                    }
                }
            }
        }
        .onDisappear {
            for (_, listener) in listeners {
                listener.remove()
            }
            listeners.removeAll()
        }
    }

    func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE" // e.g., Monday
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "MMM d" // e.g., Jul 25
            return formatter.string(from: date)
        }
    }

    func formattedLastSeen(_ date: Date) -> String {
//        print("🕓 [DEBUG] Comparing lastLoginDate: \(date) to now: \(Date())")
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    func saveOpenedChats() {
        let ids = Array(openedChats)
        if let data = try? JSONEncoder().encode(ids),
           let str = String(data: data, encoding: .utf8) {
            readChatIdsRaw = str
        }
    }

    func loadOpenedChats() {
        if let data = readChatIdsRaw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            openedChats = Set(decoded)
        }
    }
}
