import SwiftUI
import SwiftData

struct NewItemview: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: NewItemModel
    @Binding var newItemPresented: Bool

    init(newItemPresented: Binding<Bool>, editingItem: TodoItem? = nil) {
        self._viewModel = StateObject(wrappedValue: NewItemModel(item: editingItem))
        self._newItemPresented = newItemPresented
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header:
                    Text("Task Details")
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                        .padding(.top, 5)
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Title")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)

                        TextField("Enter task title", text: $viewModel.title)
                            .padding(10)
                            .background(dynamicSecondaryBackgroundColor.opacity(0.3))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(dynamicSecondaryTextColor.opacity(0.5), lineWidth: 1)
                            )
                            .foregroundColor(dynamicTextColor)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.sentences)

                        Text("Description")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)

                        TextEditor(text: $viewModel.description)
                            .frame(minHeight: 100)
                            .padding(10)
                            .background(dynamicSecondaryBackgroundColor.opacity(0.3))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(dynamicSecondaryTextColor.opacity(0.5), lineWidth: 1)
                            )
                            .foregroundColor(dynamicTextColor)
                            .textInputAutocapitalization(.sentences)
                            .scrollContentBackground(.hidden)
                    }
                    .listRowBackground(dynamicBackgroundColor)
                }

                Section(header:
                    Text("Subtasks")
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                        .padding(.top, 5)
                ) {
                    ForEach($viewModel.subtasks) { $subtask in
                        TextField("Subtask", text: $subtask.title)
                            .padding(8)
                            .background(dynamicSecondaryBackgroundColor.opacity(0.3))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(dynamicSecondaryTextColor.opacity(0.5), lineWidth: 1)
                            )
                            .foregroundColor(dynamicTextColor)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.sentences)
                            .listRowBackground(dynamicBackgroundColor)
                    }
                    .onDelete { indexSet in
                        viewModel.subtasks.remove(atOffsets: indexSet)
                    }

                    Button(action: viewModel.addSubtask) {
                        Label("Add Subtask", systemImage: "plus.circle.fill")
                            .foregroundColor(dynamicPrimaryColor)
                    }
                    .listRowBackground(dynamicBackgroundColor)
                }

                Section(header:
                    Text("Due Date")
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                        .padding(.top, 5)
                ) {
                    DatePicker("Select Due Date", selection: $viewModel.donebye)
                        .datePickerStyle(GraphicalDatePickerStyle())
                        .tint(dynamicPrimaryColor)
                        .foregroundColor(dynamicTextColor)
                        .background(dynamicSecondaryBackgroundColor.opacity(0.5))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(dynamicPrimaryColor, lineWidth: 1.5)
                        )
                        .padding(.vertical, 5)
                        .listRowBackground(dynamicBackgroundColor)
                }

                Section {
                    Button(action: saveTask) {
                        Text(viewModel.originalItem == nil ? "Add Task" : "Save Task")
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? dynamicSecondaryTextColor.opacity(0.5) : dynamicPrimaryColor)
                            .cornerRadius(10)
                    }
                    .listRowBackground(Color.clear)
                    .disabled(viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(dynamicPrimaryColor)
                }
                ToolbarItem(placement: .principal) {
                    Text(viewModel.originalItem == nil ? "New Task" : "Edit Task")
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                }
            }
            .alert(isPresented: $viewModel.showAlert) {
                Alert(title: Text("Error"), message: Text("Please fill in task title"))
            }
        }
        .navigationViewStyle(.stack)
    }

    private func saveTask() {
        if viewModel.title.trimmingCharacters(in: .whitespaces).isEmpty {
            viewModel.showAlert = true
            return
        }

        if let existing = viewModel.originalItem {
            existing.title = viewModel.title
            existing.detail = viewModel.description
            existing.dueDate = viewModel.donebye
            existing.subtasks = viewModel.subtasks
            print("Updated task '\(existing.title)')")
        } else {
            let newItem = TodoItem(
                title: viewModel.title,
                detail: viewModel.description,
                dueDate: viewModel.donebye,
                subtasks: viewModel.subtasks
            )
            context.insert(newItem)
            print("Created new task '\(newItem.title)')")
        }

        dismiss()
    }
}
