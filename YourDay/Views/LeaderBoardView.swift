import SwiftUI
import FirebaseAuth


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
                        .progressViewStyle(CircularProgressViewStyle(tint: dynamicSecondaryColor))
                        .scaleEffect(1.5)
                        .padding()
                    Spacer()
                } else if let errorMessage = viewModel.errorMessage {
                    Spacer()
                    VStack {
                        Text("Error: \(errorMessage)")
                            .foregroundColor(dynamicDestructiveColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") {
                            viewModel.refreshLeaderboard()
                        }
                        .padding()
                        .background(dynamicSecondaryColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.top)
                    }
                    .padding()
                    Spacer()
                } else if viewModel.leaderboardEntries.isEmpty {
                    Spacer()
                    Text("Leaderboard is currently empty.")
                        .foregroundColor(dynamicSecondaryTextColor)
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
                            .background(dynamicPrimaryColor)
                            .foregroundColor(Color.white)
                            .cornerRadius(10)
                            .shadow(color: dynamicSecondaryTextColor.opacity(0.3), radius: 3, x: 0, y: 2)
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
                        .background(dynamicBackgroundColor)
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
                            Divider().background(dynamicSecondaryBackgroundColor)
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
                            .foregroundColor(dynamicSecondaryTextColor)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .background(dynamicBackgroundColor)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Leaderboard")
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.refreshLeaderboard()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(dynamicPrimaryColor)
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
                .foregroundColor(dynamicTextColor)
                .frame(width: 50, alignment: .center)
            Text("Player")
                .fontWeight(.semibold)
                .foregroundColor(dynamicTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)
            Text("Level")
                .fontWeight(.semibold)
                .foregroundColor(dynamicTextColor)
                .frame(width: 50, alignment: .trailing)
            Text("Value")
                .fontWeight(.semibold)
                .foregroundColor(dynamicTextColor)
                .frame(width: 80, alignment: .trailing)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(dynamicSecondaryBackgroundColor.opacity(0.8))
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
                .foregroundColor(isCurrentUser ? dynamicTextColor : dynamicSecondaryTextColor)
                .frame(width: 50, alignment: .center)
            
            Text(entry.displayName)
                .fontWeight(isCurrentUser ? .bold : .regular)
                .foregroundColor(isCurrentUser ? dynamicTextColor : dynamicSecondaryTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)
            
            Text("\(entry.playerLevel)")
                .fontWeight(isCurrentUser ? .bold : .regular)
                .foregroundColor(isCurrentUser ? dynamicTextColor : dynamicSecondaryTextColor)
                .frame(width: 50, alignment: .trailing)
            
            Text("\(Int(entry.gardenValue))")
                .fontWeight(isCurrentUser ? .bold : .regular)
                .foregroundColor(isCurrentUser ? dynamicTextColor : dynamicSecondaryTextColor)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 5)
        .background(isCurrentUser ? dynamicPrimaryColor.opacity(0.3) : Color.clear)
        .cornerRadius(isCurrentUser ? 8 : 0)
        .listRowBackground(dynamicBackgroundColor)
    }
}
