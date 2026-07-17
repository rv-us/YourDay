import SwiftUI
import FirebaseAuth

struct GroupMemberPickerView: View {
    let members: [GroupMember] // pre-fetched; caller decides whether to include current user
    var initiallySelected: Set<String> = []
    var isLoading: Bool = false
    var dismissesOnConfirm: Bool = true // false when embedded in a multi-step flow
    let onConfirm: ([GroupMember]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var didSeedSelection = false

    private var allSelected: Bool {
        !members.isEmpty && members.allSatisfy { selected.contains($0.id ?? "") }
    }

    private var chosenMembers: [GroupMember] {
        members.filter { selected.contains($0.id ?? "") }
    }

    var body: some View {
        NavigationView {
            List {
                if members.isEmpty {
                    Section {
                        HStack(spacing: 10) {
                            if isLoading {
                                ProgressView()
                                Text("Loading members…")
                                    .foregroundColor(dynamicSecondaryTextColor)
                            } else {
                                Text("No members found.")
                                    .foregroundColor(dynamicSecondaryTextColor)
                            }
                        }
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                } else {
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
                        let chosen = chosenMembers
                        guard !chosen.isEmpty else { return }
                        onConfirm(chosen)
                        if dismissesOnConfirm {
                            dismiss()
                        }
                    }
                    .foregroundColor(chosenMembers.isEmpty ? dynamicSecondaryTextColor : dynamicPrimaryColor)
                    .disabled(chosenMembers.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
        .onAppear {
            if !didSeedSelection {
                selected = initiallySelected
                didSeedSelection = true
            }
        }
    }
}
