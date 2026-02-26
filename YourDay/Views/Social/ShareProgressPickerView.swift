import SwiftUI
import SwiftData
import FirebaseAuth

enum ShareTarget {
    case dm(friendId: String)
    case group(groupId: String, recipientIds: [String], senderDisplayName: String)
}

struct ShareProgressPickerView: View {
    let target: ShareTarget
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var firebaseManager: FirebaseManager

    @Query private var allTodoItems: [TodoItem]

    @AppStorage("sharedProgressMapRaw") private var sharedProgressMapRaw: String = ""

    private var recipientKey: String {
        switch target {
        case .dm(let friendId): return friendId
        case .group(let groupId, _, _): return "group_\(groupId)"
        }
    }

    private var tasksToShow: [TodoItem] {
        let excludedKeys = currentSharedKeysFor(key: recipientKey)
        return allTodoItems.filter { item in
            guard item.sharedTaskId == nil else { return false }
            let key = progressKey(for: item)
            return !excludedKeys.contains(key)
        }
        .sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(tasksToShow) { item in
                    Button(action: { share(item) }) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.title)
                                    .font(.headline)
                                    .foregroundColor(dynamicTextColor)
                                if item.isDone {
                                    Text("Completed")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(dynamicSecondaryTextColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(dynamicSecondaryBackgroundColor)
                                        .cornerRadius(6)
                                }
                                Spacer()
                            }
                            if !item.detail.isEmpty {
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundColor(dynamicSecondaryTextColor)
                                    .lineLimit(2)
                            }
                            if !item.subtasks.isEmpty {
                                Text("\(item.subtasks.filter{ $0.isDone }.count)/\(item.subtasks.count) subtasks done")
                                    .font(.caption2)
                                    .foregroundColor(dynamicSecondaryTextColor)
                            }
                        }
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                }
            }
            .listStyle(PlainListStyle())
            .scrollContentBackground(.hidden)
            .background(dynamicBackgroundColor)
            .navigationTitle("Share Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(dynamicPrimaryColor)
                }
            }
        }
        .navigationViewStyle(.stack)
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
    }

    private func share(_ item: TodoItem) {
        let sharedSubtasks = item.subtasks.enumerated().map { idx, st in
            SharedSubtask(id: "sub_\(idx)", title: st.title, isDone: st.isDone)
        }

        switch target {
        case .dm(let friendId):
            firebaseManager.shareProgress(
                to: friendId,
                title: item.title,
                detail: item.detail,
                dueDate: item.dueDate,
                subtasks: sharedSubtasks,
                isCompleted: item.isDone
            ) { error, docId in
                if error == nil, let docId = docId {
                    item.sharedTaskId = docId
                    do { try modelContext.save() } catch { print("Failed to save sharedTaskId link: \(error)") }

                    var map = loadSharedProgressMap()
                    let key = progressKey(for: item)
                    var set = Set(map[friendId] ?? [])
                    set.insert(key)
                    map[friendId] = Array(set)
                    saveSharedProgressMap(map)

                    if let currentId = Auth.auth().currentUser?.uid {
                        let info = "Shared progress: \(item.title)"
                        let msg = ChatMessage(senderId: currentId, receiverId: friendId, content: info, timestamp: Date())
                        firebaseManager.sendChatMessage(msg) { _ in }
                    }
                }
                dismiss()
            }

        case .group(let groupId, let recipientIds, let senderDisplayName):
            firebaseManager.shareProgressToGroup(
                groupId: groupId,
                recipientIds: recipientIds,
                title: item.title,
                detail: item.detail,
                dueDate: item.dueDate,
                subtasks: sharedSubtasks,
                isCompleted: item.isDone,
                senderDisplayName: senderDisplayName
            ) { error, _ in
                if error == nil {
                    var map = loadSharedProgressMap()
                    let key = progressKey(for: item)
                    let recipientKey = "group_\(groupId)"
                    var set = Set(map[recipientKey] ?? [])
                    set.insert(key)
                    map[recipientKey] = Array(set)
                    saveSharedProgressMap(map)
                }
                dismiss()
            }
        }
    }

    private func progressKey(for item: TodoItem) -> String {
        "t:\(item.title)|d:\(Int(item.dueDate.timeIntervalSince1970))"
    }

    private func loadSharedProgressMap() -> [String: [String]] {
        guard let data = sharedProgressMapRaw.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return map
    }

    private func saveSharedProgressMap(_ map: [String: [String]]) {
        if let data = try? JSONEncoder().encode(map),
           let str = String(data: data, encoding: .utf8) {
            sharedProgressMapRaw = str
        }
    }

    private func currentSharedKeysFor(key: String) -> Set<String> {
        Set(loadSharedProgressMap()[key] ?? [])
    }
}
