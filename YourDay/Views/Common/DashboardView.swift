//
//  DashboardView.swift
//  YourDay
//
//  Combines Notes, Chats, Friends, and Last Day into one card-based dashboard.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var loginViewModel: LoginViewModel
    @EnvironmentObject private var firebaseManager: FirebaseManager

    @Query(sort: [SortDescriptor(\TodoItem.position)]) private var allTodoItems: [TodoItem]
    @Query(sort: [SortDescriptor(\NoteItem.createdAt, order: .reverse)]) private var allNotes: [NoteItem]

    private var todayTasks: [TodoItem] {
        allTodoItems.filter { Calendar.current.isDateInToday($0.dueDate) && !$0.isDone }
    }

    private var inProgressCount: Int {
        allTodoItems.filter { !$0.isDone }.count
    }

    private var recentNotes: [NoteItem] {
        Array(allNotes.prefix(5))
    }

    @State private var showLastDayView = false
    @StateObject private var friendStatsViewModel = DashboardFriendStatsViewModel()

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        if hour < 12 { timeGreeting = "Good morning" }
        else if hour < 17 { timeGreeting = "Good afternoon" }
        else { timeGreeting = "Good evening" }
        let name = loginViewModel.userDisplayName ?? loginViewModel.userEmail?.components(separatedBy: "@").first ?? "there"
        return "\(timeGreeting), \(name)!"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    todayCard
                    summaryCardsRow
                    proofFeedCard
                    friendsActivitySection
                    notesSection
                    lastDaySection
                }
                .padding()
            }
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .onAppear {
                friendStatsViewModel.load()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Dashboard")
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showLastDayView) {
            NavigationView {
                LastDayView(isModal: true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showLastDayView = false }
                        }
                    }
            }
            .environment(\.modelContext, modelContext)
        }
    }

    private var headerSection: some View {
        HStack {
            Text(greeting)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(dynamicTextColor)
                .lineLimit(2)
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(dynamicSecondaryColor)
                    .frame(width: 4, height: 20)
                Text("Today")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(dynamicTextColor)
            }
            if todayTasks.isEmpty {
                Text("No tasks due today")
                    .font(.subheadline)
                    .foregroundColor(dynamicSecondaryTextColor)
            } else {
                ForEach(todayTasks.prefix(3)) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .font(.caption)
                            .foregroundColor(dynamicPrimaryColor)
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundColor(dynamicTextColor)
                            .lineLimit(1)
                    }
                }
                if todayTasks.count > 3 {
                    Text("+\(todayTasks.count - 3) more")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(16)
    }

    private var summaryCardsRow: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: AddNotesView().environmentObject(loginViewModel)) {
                summaryCard(icon: "pencil", value: "\(allNotes.count)", label: "Notes", useOrange: false)
            }
            .buttonStyle(.plain)

            NavigationLink(destination: ChatListView()
                .environmentObject(firebaseManager)
                .environmentObject(loginViewModel)) {
                summaryCard(icon: "message.fill", value: "Chats", label: "Messages", useOrange: true)
            }
            .buttonStyle(.plain)

            NavigationLink(destination: FriendsView()
                .environmentObject(firebaseManager)) {
                summaryCard(icon: "person.2.fill", value: "Friends", label: "Social", useOrange: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var proofFeedCard: some View {
        NavigationLink(destination: TaskProofFeedView().environmentObject(firebaseManager)) {
            HStack(spacing: 12) {
                Image(systemName: "photo.badge.checkmark")
                    .font(.title2)
                    .foregroundColor(dynamicPrimaryColor)
                    .frame(width: 42, height: 42)
                    .background(dynamicBackgroundColor)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Proof Feed")
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                    Text("See friends' completion photos and vote check or X.")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
            .padding()
            .background(dynamicSecondaryBackgroundColor)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    private func summaryCard(icon: String, value: String, label: String, useOrange: Bool = false) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(useOrange ? dynamicSecondaryColor : dynamicPrimaryColor)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(dynamicTextColor)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundColor(dynamicSecondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
    }

    private var friendsActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(dynamicSecondaryColor)
                    .frame(width: 4, height: 20)
                Text("Friends Activity")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(dynamicTextColor)
                Spacer()
                if friendStatsViewModel.hasLoadedOnce {
                    Button(action: { friendStatsViewModel.refresh() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(dynamicPrimaryColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            if friendStatsViewModel.isLoading && !friendStatsViewModel.hasLoadedOnce {
                loadingFriendsActivityCard
            } else if let errorMessage = friendStatsViewModel.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(dynamicDestructiveColor)
                    Button("Retry") {
                        friendStatsViewModel.refresh()
                    }
                    .font(.subheadline)
                    .foregroundColor(dynamicPrimaryColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
            } else if friendStatsViewModel.cards.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No friend activity yet")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(dynamicTextColor)
                    Text("Add friends to see their points, streaks, and completed tasks.")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
            } else {
                TabView {
                    ForEach(friendStatsViewModel.cards) { card in
                        friendStatsCard(card)
                            .padding(.horizontal, 4)
                    }
                }
                .frame(height: 186)
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            }
        }
    }

    private var loadingFriendsActivityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView()
                .tint(dynamicPrimaryColor)
            Text("Loading friend activity...")
                .font(.caption)
                .foregroundColor(dynamicSecondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
    }

    private func friendStatsCard(_ card: FriendDashboardStats) -> some View {
        let isMuted = card.isNoActivityYesterday

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(card.displayName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(dynamicTextColor)
                    .lineLimit(1)
                Spacer()
                if isMuted {
                    Label("No activity yesterday", systemImage: "moon.zzz.fill")
                        .font(.caption2)
                        .foregroundColor(dynamicSecondaryTextColor)
                } else {
                    Label("Active", systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundColor(dynamicSecondaryColor)
                }
            }

            HStack(spacing: 8) {
                friendMetricChip(
                    icon: "sparkles",
                    value: "\(Int(card.yesterdayPoints))",
                    label: "Points",
                    muted: isMuted
                )
                friendMetricChip(
                    icon: "flame.fill",
                    value: "\(card.taskStreak)",
                    label: "Streak",
                    muted: isMuted
                )
                friendMetricChip(
                    icon: "checkmark.circle.fill",
                    value: card.totalTasksYesterday > 0 ? "\(card.completedTasksYesterday)/\(card.totalTasksYesterday)" : "\(card.completedTasksYesterday)",
                    label: "Tasks",
                    muted: isMuted
                )
            }

            if card.isStale {
                Text("Waiting for their daily sync")
                    .font(.caption2)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            isMuted ? dynamicSecondaryBackgroundColor.opacity(0.65) : dynamicSecondaryBackgroundColor
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isMuted ? dynamicSecondaryTextColor.opacity(0.3) : dynamicPrimaryColor.opacity(0.2),
                    lineWidth: 1
                )
        )
        .cornerRadius(14)
        .opacity(isMuted ? 0.82 : 1.0)
    }

    private func friendMetricChip(icon: String, value: String, label: String, muted: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(muted ? dynamicSecondaryTextColor : dynamicPrimaryColor)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(dynamicTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2)
                .foregroundColor(dynamicSecondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(dynamicBackgroundColor.opacity(muted ? 0.4 : 0.9))
        .cornerRadius(10)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Notes")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(dynamicTextColor)
                Spacer()
                NavigationLink(destination: AddNotesView().environmentObject(loginViewModel)) {
                    Text("See all")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryColor)
                }
            }
            if recentNotes.isEmpty {
                Text("No notes yet")
                    .font(.subheadline)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(dynamicSecondaryBackgroundColor)
                    .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentNotes) { note in
                        NavigationLink(destination: NoteDetailView(note: note)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.content.isEmpty ? "New Note" : note.content)
                                        .font(.subheadline)
                                        .foregroundColor(dynamicTextColor)
                                        .lineLimit(1)
                                    Text(note.createdAt, style: .date)
                                        .font(.caption2)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(dynamicSecondaryTextColor)
                            }
                            .padding()
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var lastDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(dynamicSecondaryColor)
                    .frame(width: 4, height: 20)
                Text("Daily Summary")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(dynamicTextColor)
            }

            Button(action: { showLastDayView = true }) {
                HStack {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .foregroundColor(dynamicSecondaryColor)
                    Text("View your day summary")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(dynamicTextColor)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }
}
