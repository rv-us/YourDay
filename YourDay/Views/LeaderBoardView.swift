//
//  LeaderBoardView.swift
//  YourDay
//
//  Created by Rachit Verma on 5/20/25.
//
import SwiftUI
import FirebaseAuth // To get current user ID for initial ViewModel state


let genericYellow = Color.yellow // Using a standard yellow


struct LeaderboardView: View {

    @StateObject private var viewModel: LeaderboardViewModel
    @EnvironmentObject var loginViewModel: LoginViewModel
    @State private var scrollViewProxy: ScrollViewProxy? = nil

    init() {
        _viewModel = StateObject(wrappedValue: LeaderboardViewModel(currentUserID: Auth.auth().currentUser?.uid))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.leaderboardEntries.isEmpty {
                    Spacer()
                    ProgressView("Loading Leaderboard...")
                        .progressViewStyle(CircularProgressViewStyle(tint: plantMediumGreen)) // Reverted
                        .scaleEffect(1.5)
                        .padding()
                    Spacer()
                } else if let errorMessage = viewModel.errorMessage {
                    Spacer()
                    VStack {
                        Text("Error: \(errorMessage)")
                            .foregroundColor(plantPink) // Kept for error emphasis
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") {
                            viewModel.refreshLeaderboard()
                        }
                        .padding()
                        .background(plantMediumGreen) // Reverted
                        .foregroundColor(.white)    // Reverted
                        .cornerRadius(8)
                        .padding(.top)
                    }
                    .padding()
                    Spacer()
                } else if viewModel.leaderboardEntries.isEmpty {
                    Spacer()
                    Text("Leaderboard is currently empty.")
                        .foregroundColor(plantDustyBlue) // Reverted
                        .padding()
                    Spacer()
                } else {
                    if viewModel.currentUserRank != nil && viewModel.currentUserID != nil {
                        Button(action: {
                            scrollToCurrentUser()
                        }) {
                            HStack {
                                Image(systemName: "scope")
                                Text("Find My Rank")
                                    .fontWeight(.semibold)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(plantPastelBlue) // Reverted
                            .foregroundColor(plantDarkGreen) // Reverted
                            .cornerRadius(10)
                            .shadow(color: plantDustyBlue.opacity(0.3), radius: 3, x: 0, y: 2) // Reverted
                        }
                        .padding(.vertical, 15)
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
                        .background(plantBeige) // Reverted
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
                    
                    if !viewModel.leaderboardEntries.isEmpty {
                        VStack {
                            Divider().background(plantLightMintGreen) // Reverted
                            HStack {
                                if let rank = viewModel.currentUserRank {
                                    Text("Your Rank: \(rank)")
                                        .fontWeight(.semibold)
                                } else if viewModel.currentUserID != nil {
                                    Text("Your Rank: N/A")
                                }
                                Spacer()
                                Text("Total Players: \(viewModel.leaderboardEntries.count)")
                            }
                            .font(.caption)
                            .foregroundColor(plantMediumGreen) // Reverted
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .background(plantBeige) // Reverted
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(plantBeige.edgesIgnoringSafeArea(.all)) // Reverted
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(plantLightMintGreen, for: .navigationBar) // Reverted
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Leaderboard")
                        .fontWeight(.bold)
                        .foregroundColor(plantDarkGreen) // Reverted
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.refreshLeaderboard()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(plantDarkGreen) // Reverted
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .navigationViewStyle(.stack)
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
        }
    }
}

struct LeaderboardHeaderView: View {
    var body: some View {
        HStack {
            Text("Rank")
                .fontWeight(.semibold)
                .foregroundColor(plantDarkGreen)
                .frame(width: 50, alignment: .center)
            Text("Player")
                .fontWeight(.semibold)
                .foregroundColor(plantDarkGreen)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)
            Text("Level")
                .fontWeight(.semibold)
                .foregroundColor(plantDarkGreen)
                .frame(width: 50, alignment: .trailing)
            Text("Value")
                .fontWeight(.semibold)
                .foregroundColor(plantDarkGreen)
                .frame(width: 80, alignment: .trailing)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(plantPastelGreen.opacity(0.5)) // Reverted
        .cornerRadius(6)
        .listRowInsets(EdgeInsets())
    }
}

struct LeaderboardRowView: View {
    let entry: LeaderboardEntry
    let isCurrentUser: Bool

    var body: some View {
        HStack {
            Text("\(entry.rank ?? 0)")
                .fontWeight(isCurrentUser ? .bold : .regular)
                .foregroundColor(isCurrentUser ? plantDarkGreen : plantMediumGreen)
                .frame(width: 50, alignment: .center)
            
            Text(entry.displayName)
                .fontWeight(isCurrentUser ? .bold : .regular)
                .foregroundColor(isCurrentUser ? plantDarkGreen : plantMediumGreen) // User's name in yellow
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)
            
            Text("\(entry.playerLevel)")
                .fontWeight(isCurrentUser ? .bold : .regular)
                .foregroundColor(isCurrentUser ? plantDarkGreen : plantMediumGreen)
                .frame(width: 50, alignment: .trailing)
            
            Text("\(Int(entry.gardenValue))")
                .fontWeight(isCurrentUser ? .bold : .regular)
                .foregroundColor(isCurrentUser ? plantDarkGreen : plantMediumGreen)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 5)
        .background(isCurrentUser ? plantPink.opacity(0.6) : Color.clear) // User's row highlighted in pink
        .cornerRadius(isCurrentUser ? 8 : 0)
        .listRowBackground(plantBeige) // Reverted
    }
}


