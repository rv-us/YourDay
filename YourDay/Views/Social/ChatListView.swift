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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(friends) { friend in
                    NavigationLink(destination: ChatDetailView(friend: friend)
                        .onAppear {
                            openedChats.insert(friend.userId)
                            saveOpenedChats()
                        }) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .foregroundColor(dynamicPrimaryColor)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(friend.displayName)
                                    .font(.headline)
                                    .foregroundColor(dynamicTextColor)

                                if let msg = lastMessages[friend.userId] {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(msg.content)
                                            .font(.caption)
                                            .foregroundColor(dynamicSecondaryTextColor)
                                            .lineLimit(1)
                                        Text(formatTimestamp(msg.timestamp))
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                } else {
                                    Text("Tap to chat")
                                        .font(.caption)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                }

                                if let lastSeenDate = lastSeen[friend.userId] {
                                    Text("Last seen: \(formattedLastSeen(lastSeenDate))")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }

                            Spacer()

                            VStack(spacing: 6) {
                                if let msg = lastMessages[friend.userId] {
                                    Text(formatTimestamp(msg.timestamp))
                                        .font(.caption2)
                                        .foregroundColor(.gray)

                                    if msg.senderId == friend.userId && !openedChats.contains(friend.userId) {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 8, height: 8)
                                    }
                                }

                                Image(systemName: "chevron.right")
                                    .foregroundColor(dynamicSecondaryTextColor)
                            }
                        }
                        .padding()
                        .background(dynamicSecondaryBackgroundColor)
                        .cornerRadius(12)
                        .shadow(color: dynamicSecondaryTextColor.opacity(0.1), radius: 2, x: 0, y: 1)
                        .padding(.horizontal)
                    }
                }

                if friends.isEmpty {
                    Text("No friends to chat with yet.")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .padding(.top, 50)
                }
            }
            .padding(.top)
        }
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
