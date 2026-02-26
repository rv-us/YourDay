import SwiftUI
import FirebaseAuth

struct GroupMemberPickerView: View {
    let members: [GroupMember] // pre-fetched, excludes current user
    let onConfirm: ([GroupMember]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    private var allSelected: Bool {
        members.allSatisfy { selected.contains($0.id ?? "") }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(dynamicPrimaryColor)
                        Text("All members")
                            .foregroundColor(dynamicTextColor)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if allSelected {
                            selected.removeAll()
                        } else {
                            selected = Set(members.compactMap { $0.id })
                        }
                    }
                }
                .listRowBackground(dynamicSecondaryBackgroundColor)

                Section {
                    ForEach(members) { member in
                        HStack {
                            Image(systemName: selected.contains(member.id ?? "") ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(dynamicPrimaryColor)
                            Text(member.displayName)
                                .foregroundColor(dynamicTextColor)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let mid = member.id {
                                if selected.contains(mid) {
                                    selected.remove(mid)
                                } else {
                                    selected.insert(mid)
                                }
                            }
                        }
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                    }
                }
            }
            .listStyle(PlainListStyle())
            .scrollContentBackground(.hidden)
            .background(dynamicBackgroundColor)
            .navigationTitle("Send to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(dynamicPrimaryColor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") {
                        let chosen = members.filter { selected.contains($0.id ?? "") }
                        onConfirm(chosen)
                        dismiss()
                    }
                    .foregroundColor(selected.isEmpty ? dynamicSecondaryTextColor : dynamicPrimaryColor)
                    .disabled(selected.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
    }
}
