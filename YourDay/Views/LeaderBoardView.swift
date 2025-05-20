//
//  LeaderBoardView.swift
//  YourDay
//
//  Created by Rachit Verma on 5/20/25.
//
import SwiftUI
import FirebaseAuth // To get current user ID for initial ViewModel state

struct LeaderboardView: View {

    @StateObject private var viewModel: LeaderboardViewModel
    

    @EnvironmentObject var loginViewModel: LoginViewModel

    @State private var scrollViewProxy: ScrollViewProxy? = nil

    init() {
        _viewModel = StateObject(wrappedValue: LeaderboardViewModel(currentUserID: Auth.auth().currentUser?.uid))
    }

    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoading && viewModel.leaderboardEntries.isEmpty {
                    ProgressView("Loading Leaderboard...")
                        .scaleEffect(1.5)
                        .padding()
                    Spacer()
                } else if let errorMessage = viewModel.errorMessage {
                    VStack {
                        Text("Error: \(errorMessage)")
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            viewModel.refreshLeaderboard()
                        }
                        .padding(.top)
                    }
                    .padding()
                    Spacer()
                } else if viewModel.leaderboardEntries.isEmpty {
                    Text("Leaderboard is currently empty or no data found.")
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                } else {
        
                    if viewModel.currentUserRank != nil && viewModel.currentUserID != nil {
                        Button(action: {
                            scrollToCurrentUser()
                        }) {
                            HStack {
                                Text("Find My Rank")
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.blue.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding(.vertical, 10)
                    }

                    ScrollViewReader { proxy in
                        List {
                            Section(header: LeaderboardHeaderView()) {
                                ForEach(viewModel.leaderboardEntries) { entry in
                                    LeaderboardRowView(
                                        entry: entry,
                                        isCurrentUser: entry.id == viewModel.currentUserID
                                    )
                                    .id(entry.rank)
                                }
                            }
                        }
                        .listStyle(PlainListStyle())
                        .onAppear {
                            self.scrollViewProxy = proxy
                            if viewModel.currentUserID != Auth.auth().currentUser?.uid {
                                viewModel.currentUserID = Auth.auth().currentUser?.uid
                                viewModel.refreshLeaderboard()
                            }
                        }
                        .refreshable {
                            print("LeaderboardView: Refresh triggered.")
                            viewModel.refreshLeaderboard()
                        }
                    }
                }
            }
            .navigationTitle("Leaderboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.refreshLeaderboard()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        // Ensure loginViewModel is passed if it's not in the global environment from a parent
        // .environmentObject(LoginViewModel()) // Only if LoginViewModel is created here or passed down
    }

    private func scrollToCurrentUser() {
        guard let proxy = scrollViewProxy else {
            print("LeaderboardView: ScrollViewProxy not available.")
            return
        }
        if let rank = viewModel.currentUserRank {
            print("LeaderboardView: Scrolling to current user rank: \(rank).")
            withAnimation {
                proxy.scrollTo(rank, anchor: .center)
            }
        } else {
            print("LeaderboardView: Current user rank not found, cannot scroll.")
            // Optionally show an alert to the user
        }
    }
}

struct LeaderboardHeaderView: View {
    var body: some View {
        HStack {
            Text("Rank")
                .fontWeight(.bold)
                .frame(width: 50, alignment: .center)
            Text("Player")
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)
            Text("Level")
                .fontWeight(.bold)
                .frame(width: 50, alignment: .trailing)
            Text("Value") // Shortened for space
                .fontWeight(.bold)
                .frame(width: 80, alignment: .trailing)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 5) // Add some vertical padding to the header
    }
}

struct LeaderboardRowView: View {
    let entry: LeaderboardEntry
    let isCurrentUser: Bool

    var body: some View {
        HStack {
            Text("\(entry.rank ?? 0)")
                .fontWeight(isCurrentUser ? .bold : .regular)
                .frame(width: 50, alignment: .center)
            
            Text(entry.displayName)
                .fontWeight(isCurrentUser ? .bold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)
            
            Text("\(entry.playerLevel)")
                .fontWeight(isCurrentUser ? .bold : .regular)
                .frame(width: 50, alignment: .trailing)
            
            Text("\(Int(entry.gardenValue))")
                .fontWeight(isCurrentUser ? .bold : .regular)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 8) // Increased padding for better readability
        .background(isCurrentUser ? Color.yellow.opacity(0.3) : Color.clear) // Highlight current user
        .cornerRadius(isCurrentUser ? 6 : 0)
        .listRowInsets(EdgeInsets(top: 0, leading: isCurrentUser ? 0 : 16, bottom: 0, trailing: 16)) // Adjust insets
    }
}



