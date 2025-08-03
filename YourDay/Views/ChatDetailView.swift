//
//  ChatDetailView.swift
//  YourDay
//
//  Created by Rachit Verma on 8/2/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore



struct ChatDetailView: View {
    let friend: FriendEntry
    @EnvironmentObject var firebaseManager: FirebaseManager
    @EnvironmentObject var loginViewModel: LoginViewModel

    @State private var messages: [ChatMessage] = []
    @State private var newMessage = ""
    @State private var listener: ListenerRegistration?

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { msg in
                            HStack {
                                if msg.senderId == Auth.auth().currentUser?.uid {
                                    Spacer()
                                    Text(msg.content)
                                        .padding()
                                        .background(dynamicPrimaryColor)
                                        .cornerRadius(12)
                                        .foregroundColor(.white)
                                } else {
                                    Text(msg.content)
                                        .padding()
                                        .background(dynamicSecondaryBackgroundColor)
                                        .cornerRadius(12)
                                        .foregroundColor(dynamicTextColor)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }

            HStack {
                TextField("Message...", text: $newMessage)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Send") {
                    guard !newMessage.trimmingCharacters(in: .whitespaces).isEmpty,
                          let currentId = Auth.auth().currentUser?.uid else { return }

                    let message = ChatMessage(
                        senderId: currentId,
                        receiverId: friend.userId,
                        content: newMessage,
                        timestamp: Date()
                    )
                    firebaseManager.sendChatMessage(message) { _ in
                        newMessage = ""
                    }
                }
                .foregroundColor(dynamicPrimaryColor)
            }
            .padding()
            .background(dynamicBackgroundColor)
        }
        .navigationTitle(friend.displayName)
        .onAppear {
            listener = firebaseManager.listenToChat(with: friend.userId) { updated in
                self.messages = updated
            }

            firebaseManager.fetchLastLoginDate(for: friend.userId) { date in
                if let date = date {
//                    print("✅ [DEBUG] ChatDetailView got last login date: \(date)")
                }
            }
        }

        .onDisappear {
            listener?.remove()
        }
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
    }
}
