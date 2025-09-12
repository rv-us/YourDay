import SwiftUI
import SwiftData
import FirebaseAuth

struct ShareProgressPickerView: View {
    let friendId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var firebaseManager: FirebaseManager
    
    @Query private var allTodoItems: [TodoItem]
    
    @AppStorage("sharedProgressMapRaw") private var sharedProgressMapRaw: String = ""
    
    private var tasksToShow: [TodoItem] {
        let excludedKeys = currentSharedKeysFor(friendId: friendId)
        return allTodoItems.filter { item in
            // Exclude tasks received (linked to shared task)
            guard item.sharedTaskId == nil else { return false }
            // Exclude already shared to this friend
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
        firebaseManager.shareProgress(
            to: friendId,
            title: item.title,
            detail: item.detail,
            dueDate: item.dueDate,
            subtasks: sharedSubtasks,
            isCompleted: item.isDone
        ) { error, docId in
            if error == nil, let docId = docId {
                // Link local task so future toggles sync to the shared doc
                item.sharedTaskId = docId
                do { try modelContext.save() } catch { print("Failed to save sharedTaskId link: \(error)") }
                
                // Record that we shared this task to this friend, so it doesn't appear again
                var map = loadSharedProgressMap()
                let key = progressKey(for: item)
                var set = Set(map[friendId] ?? [])
                set.insert(key)
                map[friendId] = Array(set)
                saveSharedProgressMap(map)
                
                // Send chat message notifying shared progress
                if let currentId = Auth.auth().currentUser?.uid {
                    let info = "Shared progress: \(item.title)"
                    let msg = ChatMessage(senderId: currentId, receiverId: friendId, content: info, timestamp: Date())
                    firebaseManager.sendChatMessage(msg) { _ in }
                }
            }
            dismiss()
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
    
    private func currentSharedKeysFor(friendId: String) -> Set<String> {
        Set(loadSharedProgressMap()[friendId] ?? [])
    }
} 