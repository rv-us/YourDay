import SwiftUI

struct SocialView: View {
    @EnvironmentObject var loginViewModel: LoginViewModel
    @EnvironmentObject var firebaseManager: FirebaseManager

    @State private var showFriendsSheet = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Social Hub")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                        .padding(.top)

                    Text("Track your friends, compete, and grow together!")
                        .font(.headline)
                        .foregroundColor(dynamicSecondaryTextColor)

                    Image(systemName: "person.3.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .foregroundColor(dynamicPrimaryColor.opacity(0.7))
                        .padding()

                    // Manage Friends Button
                    Button(action: {
                        showFriendsSheet = true
                    }) {
                        HStack {
                            Image(systemName: "person.2.fill")
                            Text("Manage Friends")
                                .fontWeight(.semibold)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(dynamicPrimaryColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: dynamicPrimaryColor.opacity(0.4), radius: 4, x: 0, y: 2)
                    }
                    .padding(.horizontal)

                    // 🔹 NEW Chat Button
                    NavigationLink(destination: ChatListView()
                        .environmentObject(firebaseManager)
                        .environmentObject(loginViewModel)) {
                        VStack {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .padding(10)
                                .background(dynamicSecondaryBackgroundColor)
                                .cornerRadius(20)
                                .shadow(color: dynamicSecondaryTextColor.opacity(0.4), radius: 5, x: 0, y: 2)
                            Text("Chats")
                                .font(.caption)
                                .foregroundColor(dynamicTextColor)
                        }
                    }
                    .padding(.top, 10)

                    // Placeholder Content
                    VStack(spacing: 12) {
                        Text("🌱 Coming Soon:")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)
                        Text("• Weekly leaderboard\n• Community garden\n• Social challenges")
                            .multilineTextAlignment(.center)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .font(.subheadline)
                    }
                    .padding(.top, 20)

                    Spacer()
                }
                .padding()
            }
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .navigationTitle("Social")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Social")
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showFriendsSheet = true
                    } label: {
                        Image(systemName: "person.2.fill")
                    }
                    .foregroundColor(dynamicPrimaryColor)
                }
            }
            .sheet(isPresented: $showFriendsSheet) {
                FriendsView()
                    .environmentObject(firebaseManager)
                    .environmentObject(loginViewModel)
            }
        }
        .navigationViewStyle(.stack)
    }
}
