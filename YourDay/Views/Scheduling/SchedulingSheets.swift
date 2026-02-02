//
//  SchedulingSheets.swift
//  YourDay
//
//  Sheet views and backlog components for scheduling
//

import SwiftUI

// MARK: - Backlog Item Row

struct BacklogItemRow: View {
    let item: UnifiedBacklogItem
    let backlogViewModel: BacklogViewModel
    
    var body: some View {
        HStack {
            // Icon to distinguish source
            Image(systemName: backlogViewModel.isFirebaseItem(item) ? "square.and.pencil" : "checkmark.circle")
                .foregroundColor(backlogViewModel.isFirebaseItem(item) ? dynamicPrimaryColor : dynamicSecondaryTextColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(dynamicTextColor)
                
                Text(item.description)
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .lineLimit(2)
                
                if backlogViewModel.isFirebaseItem(item) {
                    Text("Backlog Item")
                        .font(.caption2)
                        .foregroundColor(dynamicPrimaryColor)
                } else {
                    Text("Current Task")
                        .font(.caption2)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
            }
            
            Spacer()
            
            if backlogViewModel.isFirebaseItem(item) {
                Button(action: {
                    backlogViewModel.deleteBacklogItem(item) { error in
                        if let error = error {
                            print("Error deleting backlog item: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(dynamicDestructiveColor)
                }
            }
        }
        .padding()
        .background(dynamicBackgroundColor)
        .cornerRadius(8)
    }
}

// MARK: - Add Backlog Item Sheet

struct AddBacklogItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var backlogViewModel: BacklogViewModel

    @State private var title = ""
    @State private var description = ""
    @State private var priority = 0
    @State private var estimatedDuration: Int? = nil
    @State private var category = ""
    @State private var tagsText = ""

    private let categoryOptions = ["", "work", "personal", "health", "errands", "learning", "creative"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Info")) {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description)
                }

                Section(header: Text("Scheduling Metadata")) {
                    Stepper("Priority: \(priority)", value: $priority, in: 0...10)

                    HStack {
                        Text("Est. Duration")
                        Spacer()
                        TextField("min", value: $estimatedDuration, format: .number)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("min")
                            .foregroundColor(dynamicSecondaryTextColor)
                    }

                    Picker("Category", selection: $category) {
                        ForEach(categoryOptions, id: \.self) { cat in
                            Text(cat.isEmpty ? "None" : cat.capitalized).tag(cat)
                        }
                    }

                    TextField("Tags (comma separated)", text: $tagsText)
                        .font(.subheadline)
                }
            }
            .navigationTitle("Add Backlog Item")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let tags = tagsText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

                        backlogViewModel.addBacklogItem(
                            title: title,
                            description: description,
                            priority: priority,
                            estimatedDuration: estimatedDuration,
                            category: category.isEmpty ? nil : category,
                            tags: tags.isEmpty ? nil : tags
                        ) { error in
                            if let error = error {
                                print("Error adding backlog item: \(error.localizedDescription)")
                            } else {
                                dismiss()
                            }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Add Task to Proposal Sheet

struct AddTaskToProposalSheet: View {
    let availableItems: [UnifiedBacklogItem]
    let onAdd: (UnifiedBacklogItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            List {
                if availableItems.isEmpty {
                    Text("No more tasks available to add.")
                        .foregroundColor(dynamicSecondaryTextColor)
                        .padding()
                } else {
                    ForEach(availableItems) { item in
                        Button(action: {
                            onAdd(item)
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.headline)
                                        .foregroundColor(dynamicTextColor)

                                    if !item.description.isEmpty {
                                        Text(item.description)
                                            .font(.caption)
                                            .foregroundColor(dynamicSecondaryTextColor)
                                            .lineLimit(2)
                                    }

                                    HStack(spacing: 8) {
                                        if let duration = item.estimatedDuration {
                                            Label("\(duration) min", systemImage: "clock")
                                                .font(.caption2)
                                                .foregroundColor(dynamicSecondaryTextColor)
                                        }
                                        if let priority = item.priority, priority > 0 {
                                            Label("P\(priority)", systemImage: "flag")
                                                .font(.caption2)
                                                .foregroundColor(dynamicSecondaryTextColor)
                                        }
                                        if let category = item.category {
                                            Text(category)
                                                .font(.caption2)
                                                .foregroundColor(dynamicPrimaryColor)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(dynamicPrimaryColor.opacity(0.15))
                                                .cornerRadius(3)
                                        }
                                    }
                                }

                                Spacer()

                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(dynamicPrimaryColor)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .navigationTitle("Add Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
        }
    }
}


