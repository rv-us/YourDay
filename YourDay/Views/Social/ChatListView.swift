//  ChatListView.swift
//  YourDay
//
//  Created by Rachit Verma on 8/2/25.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

private enum ConversationItem: Identifiable {
    case dm(FriendEntry, ChatMessage?)
    case group(GroupConversation)

    var id: String {
        switch self {
        case .dm(let f, _): return "dm_\(f.userId)"
        case .group(let g): return "group_\(g.id ?? "")"
        }
    }

    var lastTimestamp: Date {
        switch self {
        case .dm(_, let msg): return msg?.timestamp ?? .distantPast
        case .group(let g): return g.lastMessageAt
        }
    }
}

struct ChatListView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @EnvironmentObject var loginViewModel: LoginViewModel
    @State private var friends: [FriendEntry] = []
    @State private var lastMessages: [String: ChatMessage] = [:] // friendId: lastMessage
    @State private var lastSeen: [String: Date] = [:] // friendId: lastLogin
    @State private var listeners: [String: ListenerRegistration] = [:] // friendId: listener

    // Groups
    @State private var groups: [GroupConversation] = []
    @State private var groupListener: ListenerRegistration?
    @AppStorage("groupLastReadTimestamps") private var groupLastReadRaw: String = ""
    @State private var groupLastRead: [String: Date] = [:]

    @AppStorage("readChatIds") private var readChatIdsRaw: String = ""
    @State private var openedChats: Set<String> = [] // tracks read messages persistently

    @State private var showCreateGroup = false

    private var sortedConversations: [ConversationItem] {
        var items: [ConversationItem] = []
        items += friends.map { .dm($0, lastMessages[$0.userId]) }
        items += groups.map { .group($0) }
        return items.sorted { $0.lastTimestamp > $1.lastTimestamp }
    }

    var body: some View {
        List {
            ForEach(sortedConversations) { item in
                switch item {
                case .dm(let friend, let lastMsg):
                    dmRow(friend: friend, lastMsg: lastMsg)
                case .group(let group):
                    groupRow(group: group)
                }
            }

            if sortedConversations.isEmpty {
                Text("No chats yet. Add friends or create a group to get started.")
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreateGroup = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(dynamicPrimaryColor)
                }
            }
        }
        .onAppear {
            loadOpenedChats()
            loadGroupLastRead()
            fetchFriends()
            groupListener = firebaseManager.listenToMyGroups { fetched in
                groups = fetched
            }
        }
        .onDisappear {
            for (_, listener) in listeners {
                listener.remove()
            }
            listeners.removeAll()
            groupListener?.remove()
        }
        .sheet(isPresented: $showCreateGroup) {
            CreateGroupChatView()
                .environmentObject(firebaseManager)
                .environmentObject(loginViewModel)
        }
    }

    // MARK: - Row Builders

    @ViewBuilder
    private func dmRow(friend: FriendEntry, lastMsg: ChatMessage?) -> some View {
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
                        if let msg = lastMsg {
                            Text(formatTimestamp(msg.timestamp))
                                .font(.caption2)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                    }

                    if let msg = lastMsg {
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

    @ViewBuilder
    private func groupRow(group: GroupConversation) -> some View {
        NavigationLink(destination: GroupChatDetailView(group: group)
            .onAppear {
                markGroupRead(groupId: group.id ?? "")
            }
            .environmentObject(firebaseManager)
            .environmentObject(loginViewModel)) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.3.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(dynamicPrimaryColor)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(group.name)
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)
                        Spacer(minLength: 8)
                        if group.lastMessageAt != .distantPast && !group.lastMessageText.isEmpty {
                            Text(formatTimestamp(group.lastMessageAt))
                                .font(.caption2)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                    }

                    if !group.lastMessageText.isEmpty {
                        HStack(alignment: .center, spacing: 6) {
                            let prefix = group.lastMessageSenderId == Auth.auth().currentUser?.uid ? "You" : senderName(for: group)
                            Text("\(prefix): \(group.lastMessageText)")
                                .font(.subheadline)
                                .foregroundColor(dynamicSecondaryTextColor)
                                .lineLimit(1)
                            if isGroupUnread(group) {
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

    // MARK: - Helpers

    private func senderName(for group: GroupConversation) -> String {
        // Try to find the display name from the members list in Firebase
        // For simplicity, use first name heuristic from members cache
        return "Someone"
    }

    private func isGroupUnread(_ group: GroupConversation) -> Bool {
        guard group.lastMessageSenderId != Auth.auth().currentUser?.uid,
              !group.lastMessageText.isEmpty else { return false }
        let lastRead = groupLastRead[group.id ?? ""] ?? .distantPast
        return group.lastMessageAt > lastRead
    }

    private func fetchFriends() {
        firebaseManager.fetchAcceptedFriends { fetched in
            self.friends = fetched
            for friend in fetched {
                let listener = firebaseManager.listenToChat(with: friend.userId) { messages in
                    if let last = messages.last {
                        lastMessages[friend.userId] = last
                    }
                }
                listeners[friend.userId] = listener

                firebaseManager.fetchLastLoginDate(for: friend.userId) { date in
                    if let date = date {
                        lastSeen[friend.userId] = date
                    }
                }
            }
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
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
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

    func loadGroupLastRead() {
        guard let data = groupLastReadRaw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        let formatter = ISO8601DateFormatter()
        groupLastRead = dict.compactMapValues { formatter.date(from: $0) }
    }

    func markGroupRead(groupId: String) {
        groupLastRead[groupId] = Date()
        let formatter = ISO8601DateFormatter()
        let stringDict = groupLastRead.mapValues { formatter.string(from: $0) }
        if let data = try? JSONEncoder().encode(stringDict),
           let str = String(data: data, encoding: .utf8) {
            groupLastReadRaw = str
        }
    }
}
