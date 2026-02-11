import SwiftUI
import SwiftData
import FirebaseVertexAI

struct NewItemview: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: NewItemModel
    @Binding var newItemPresented: Bool
    @State private var isGenerating: Bool = false

    @State private var showingAIGenerationSheet = false
    @State private var aiPromptText: String = ""

    // Optional override to handle save externally (e.g., share-only mode)
    var onSaveOverride: ((String, String, Date, [Subtask], TaskOrigin) -> Void)? = nil

    init(newItemPresented: Binding<Bool>, editingItem: TodoItem? = nil, selectedOrigin: TaskOrigin = .today, onSaveOverride: ((String, String, Date, [Subtask], TaskOrigin) -> Void)? = nil) {
        self._viewModel = StateObject(wrappedValue: NewItemModel(item: editingItem, selectedOrigin: selectedOrigin))
        self._newItemPresented = newItemPresented
        self.onSaveOverride = onSaveOverride
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Task Details")
                    .font(.headline)
                    .foregroundColor(dynamicTextColor)
                    .padding(.top, 5)
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 0) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    viewModel.origin = .today
                                }
                            } label: {
                                Text("Today")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundColor(viewModel.origin == .today ? .white : .black.opacity(0.65))
                                    .background(viewModel.origin == .today ? dynamicPrimaryColor : Color.clear)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    viewModel.origin = .master
                                }
                            } label: {
                                Text("Master List")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundColor(viewModel.origin == .master ? .white : .black.opacity(0.65))
                                    .background(viewModel.origin == .master ? dynamicPrimaryColor : Color.clear)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(4)
                        .background(Capsule().fill(Color.black.opacity(0.06)))
                        .padding(.bottom, 4)

                        Text("Title")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)

                        AppTextField(placeholder: "Enter task title", text: $viewModel.title)
                            .padding(10)
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(dynamicSecondaryTextColor.opacity(0.5), lineWidth: 1)
                            )
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.sentences)

                        Text("Description")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)

                        TextEditor(text: $viewModel.description)
                            .frame(minHeight: 100)
                            .padding(10)
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(dynamicSecondaryTextColor.opacity(0.5), lineWidth: 1)
                            )
                            .foregroundColor(dynamicTextColor)
                            .tint(dynamicPrimaryColor)
                            .textInputAutocapitalization(.sentences)
                            .scrollContentBackground(.hidden)

                        if isGenerating {
                            ProgressView("Generating...")
                                .padding()
                        }
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                }

                Section(header: Text("Subtasks")
                    .font(.headline)
                    .foregroundColor(dynamicTextColor)
                    .padding(.top, 5)
                ) {
                    ForEach($viewModel.subtasks) { $subtask in
                        AppTextField(placeholder: "Subtask", text: $subtask.title)
                            .padding(8)
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(dynamicSecondaryTextColor.opacity(0.5), lineWidth: 1)
                            )
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.sentences)
                            .listRowBackground(dynamicSecondaryBackgroundColor)
                    }
                    .onDelete { indexSet in
                        viewModel.subtasks.remove(atOffsets: indexSet)
                    }

                    Button(action: viewModel.addSubtask) {
                        Label("Add Subtask", systemImage: "plus.circle.fill")
                            .foregroundColor(dynamicPrimaryColor)
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                }

                Section(header: Text("Due Date")
                    .font(.headline)
                    .foregroundColor(dynamicTextColor)
                    .padding(.top, 5)
                ) {
                    DatePicker("Select Due Date", selection: $viewModel.donebye)
                        .datePickerStyle(.graphical)
                        .tint(dynamicPrimaryColor)
                        .foregroundColor(dynamicTextColor)
                        .background(dynamicSecondaryBackgroundColor)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(dynamicPrimaryColor, lineWidth: 1.5)
                        )
                        .padding(.vertical, 5)
                        .listRowBackground(dynamicSecondaryBackgroundColor)
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

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: {
                            showingAIGenerationSheet = true // only show sheet
                        }) {
                            Image(systemName: "sparkles")
                                .foregroundColor(dynamicPrimaryColor)
                        }

                        Button("Save") {
                            saveTask()
                        }
                        .foregroundColor(dynamicPrimaryColor)
                        .disabled(viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .alert(isPresented: $viewModel.showAlert) {
                Alert(title: Text("Error"), message: Text("Please fill in task title"))
            }
            .sheet(isPresented: $showingAIGenerationSheet) {
                NavigationView {
                    VStack {
                        if isGenerating {
                            VStack(spacing: 16) {
                                ProgressView("Generating Task...")
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .foregroundColor(dynamicTextColor)
                                Text("This might take a few seconds.")
                                    .font(.subheadline)
                                    .foregroundColor(dynamicSecondaryTextColor)
                            }
                            .frame(maxWidth: .infinity, minHeight: 250)
                            .padding()
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(12)
                        } else {
                            TextEditor(text: $aiPromptText)
                                .padding()
                                .background(dynamicSecondaryBackgroundColor)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(dynamicSecondaryTextColor.opacity(0.5), lineWidth: 1)
                                )
                                .foregroundColor(dynamicTextColor)
                                .textInputAutocapitalization(.sentences)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 250)
                        }

                        Spacer()
                    }
                    .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("Describe Task")
                                .fontWeight(.bold)
                                .foregroundColor(dynamicTextColor)
                        }
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showingAIGenerationSheet = false
                                isGenerating = false
                            }
                            .foregroundColor(dynamicPrimaryColor)
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Generate") {
                                isGenerating = true
                                generateTaskFromPrompt()
                            }
                            .disabled(aiPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .foregroundColor(dynamicPrimaryColor)
                        }
                    }
                }
                .navigationViewStyle(.stack)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func saveTask() {
        if viewModel.title.trimmingCharacters(in: .whitespaces).isEmpty {
            viewModel.showAlert = true
            return
        }

        if let override = onSaveOverride {
            override(viewModel.title, viewModel.description, viewModel.donebye, viewModel.subtasks, viewModel.origin)
            dismiss()
            return
        }

        if let existing = viewModel.originalItem {
            existing.title = viewModel.title
            existing.detail = viewModel.description
            existing.dueDate = viewModel.donebye
            existing.subtasks = viewModel.subtasks
            existing.origin = viewModel.origin
            print("Updated task '\(existing.title)'")
        } else {
            let newItem = TodoItem(
                title: viewModel.title,
                detail: viewModel.description,
                dueDate: viewModel.donebye,
                subtasks: viewModel.subtasks,
                origin: viewModel.origin
            )
            context.insert(newItem)
            print("Created new task '\(newItem.title)'")
            NotificationCenter.default.post(name: Notification.Name("NewItemSavedNotification"), object: nil, userInfo: ["item": newItem])
        }

        dismiss()
    }

    private func generateTaskFromPrompt() {
        let currentSubtasks = viewModel.subtasks.map { $0.title }.joined(separator: ", ")
        let baseInfo = """
        Current Task Data:
        - Title: \(viewModel.title)
        - Description: \(viewModel.description)
        - DueDate: \(viewModel.donebye.formatted(.iso8601))
        - Subtasks: \(currentSubtasks)
        """

        let prompt = """
        You are a helpful assistant. Based on the CURRENT task data and the USER'S input below, return an improved version of the task.

        Always return:
        - Title: short and focused
        - Description: (1–2 lines, always present — never 'None')
        - DueDate: in YYYY-MM-DD format or 'None'
        - Subtasks: comma-separated or 'None'

        \(baseInfo)

        User Input:
        \(aiPromptText)
        """

        Task {
            do {
                let vertex = VertexAI.vertexAI()
                let model = vertex.generativeModel(modelName: "gemini-2.5-flash")

                let userMessage = ModelContent(role: "user", parts: [TextPart(prompt)])
                let response = try await model.generateContent([userMessage])

                isGenerating = false
                showingAIGenerationSheet = false

                guard let text = response.text else {
                    print("⚠️ AI returned no text")
                    return
                }

                parseGeneratedTask(text)
            } catch {
                print("❌ Failed to generate AI task: \(error.localizedDescription)")
                isGenerating = false
            }
        }
    }

    private func parseGeneratedTask(_ response: String) {
        let title = extractField("Title", from: response)
        let description = extractField("Description", from: response)
        let dueDateString = extractField("DueDate", from: response)
        let subtasksRaw = extractField("Subtasks", from: response)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dueDate = formatter.date(from: dueDateString) ?? Date().addingTimeInterval(86400 * 7)

        let subtasks = subtasksRaw.lowercased() == "none" ? [] :
            subtasksRaw.components(separatedBy: ",").map { Subtask(title: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        viewModel.title = title
        viewModel.description = description
        viewModel.donebye = dueDate
        viewModel.subtasks = subtasks
    }

    private func extractField(_ field: String, from text: String) -> String {
        guard let range = text.range(of: "\(field):") else { return "" }
        let substring = text[range.upperBound...]
        if let end = substring.range(of: "\n") {
            return String(substring[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return substring.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
