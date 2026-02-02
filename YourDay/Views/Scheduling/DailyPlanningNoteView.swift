//
//  DailyPlanningNoteView.swift
//  YourDay
//
//  View for daily planning note input that extracts tasks
//

import SwiftUI
import SwiftData
import FirebaseVertexAI

struct DailyPlanningNoteView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @Binding var isPresented: Bool
    @State private var noteText: String = ""
    @State private var isGenerating = false
    @State private var generatedTasks: [TodoItem] = []
    @State private var showingConfirmGeneratedTasks = false
    
    var onComplete: (() -> Void)? = nil
    
    private let today = Calendar.current.startOfDay(for: Date())
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isGenerating {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Extracting tasks from your plans...")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(dynamicBackgroundColor)
                } else {
                    TextEditor(text: $noteText)
                        .padding()
                        .background(dynamicSecondaryBackgroundColor)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(dynamicSecondaryTextColor.opacity(0.5), lineWidth: 1)
                        )
                        .frame(minHeight: 250, idealHeight: 400, maxHeight: .infinity)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .foregroundColor(dynamicTextColor)
                        .textInputAutocapitalization(.sentences)
                        .scrollContentBackground(.hidden)
                }
            }
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") {
                        onComplete?()
                        isPresented = false
                    }
                    .foregroundColor(dynamicPrimaryColor)
                }
                ToolbarItem(placement: .principal) {
                    Text("What else are you planning today?")
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                        .multilineTextAlignment(.center)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        extractAndSaveTasks()
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                    .foregroundColor(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating ? dynamicSecondaryTextColor.opacity(0.5) : dynamicPrimaryColor)
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingConfirmGeneratedTasks) {
            ConfirmGeneratedTasksView(tasks: generatedTasks) { selectedTasks in
                for task in selectedTasks {
                    context.insert(task)
                }
                do {
                    try context.save()
                } catch {
                    print("Error saving extracted tasks: \(error.localizedDescription)")
                }
                generatedTasks = []
                showingConfirmGeneratedTasks = false
                isPresented = false
                onComplete?()
            }
        }
    }
    
    private func extractAndSaveTasks() {
        let trimmedText = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        isGenerating = true
        
        Task {
            do {
                let prompt = """
                You are an intelligent task management assistant. Your goal is to process a note about what someone plans to do today and extract actionable tasks with relevant details.

                Analyze the following note and generate a structured list of tasks. For each task, identify a concise title, a more detailed description (if implied), and set the due date to today. If a task can be broken down further, suggest a list of subtasks.

                Format each task clearly using the following structure:

                [Task]
                Title: <concise title>
                Description: <detailed description or "None">
                DueDate: \(formatDateForPrompt(today))
                Subtasks:
                - <subtask 1>
                - <subtask 2>
                ...

                --- Note ---

                \(trimmedText)

                Ensure that the generated tasks are specific, measurable, achievable, relevant, and time-bound (SMART) where possible. Set all due dates to today (\(formatDateForPrompt(today))). Be concise and avoid unnecessary conversational elements. Additionally, write the tasks in a format that is similar to my writing style.
                """

                let vertex = VertexAI.vertexAI()
                let model = vertex.generativeModel(modelName: "gemini-2.5-flash-lite")

                let userMessage = ModelContent(role: "user", parts: [TextPart(prompt)])
                let response = try await model.generateContent([userMessage])
                
                DispatchQueue.main.async {
                    isGenerating = false
                    
                    if let text = response.text {
                        let tasks = parseGeminiResponse(text)
                        if !tasks.isEmpty {
                            generatedTasks = tasks
                            showingConfirmGeneratedTasks = true
                        } else {
                            // No tasks extracted, just proceed
                            isPresented = false
                            onComplete?()
                        }
                    } else {
                        print("⚠️ Received an empty response from the AI.")
                        // Proceed even if extraction fails
                        isPresented = false
                        onComplete?()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("❌ Failed to generate tasks: \(error.localizedDescription)")
                    isGenerating = false
                    // Proceed even if extraction fails
                    isPresented = false
                    onComplete?()
                }
            }
        }
    }
    
    private func formatDateForPrompt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func parseGeminiResponse(_ text: String) -> [TodoItem] {
        var tasks: [TodoItem] = []

        let pattern = "\\[Task.*\\]"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])

        let nsText = text as NSString
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []

        var blocks: [String] = []
        var lastIndex = 0

        for match in matches {
            let range = match.range
            if lastIndex != range.location {
                let block = nsText.substring(with: NSRange(location: lastIndex, length: range.location - lastIndex))
                blocks.append(block)
            }
            lastIndex = range.location
        }

        if lastIndex < nsText.length {
            let finalBlock = nsText.substring(from: lastIndex)
            blocks.append(finalBlock)
        }

        for block in blocks {
            let titleMatch = block.range(of: "Title: (.*)", options: .regularExpression)
            let descriptionMatch = block.range(of: "Description: (.*)", options: .regularExpression)
            let dueDateMatch = block.range(of: "DueDate: (.*)", options: .regularExpression)
            let subtasksMatches = block.matches(for: "- (.*)")

            if let titleRange = titleMatch,
               let title = block[titleRange].components(separatedBy: "Title: ").last?.trimmingCharacters(in: .whitespacesAndNewlines) {

                let description = descriptionMatch.flatMap { block[$0].components(separatedBy: "Description: ").last?.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""

                let dueDateString = dueDateMatch.flatMap { block[$0].components(separatedBy: "DueDate: ").last?.trimmingCharacters(in: .whitespacesAndNewlines) } ?? formatDateForPrompt(today)

                let subtasks = subtasksMatches.map { match in
                    Subtask(title: match)
                }

                let dueDate: Date = {
                    if let date = parseDate(dueDateString) {
                        return date
                    } else {
                        return today
                    }
                }()

                let newTask = TodoItem(
                    title: title,
                    detail: description,
                    dueDate: dueDate,
                    subtasks: subtasks,
                    origin: .today
                )
                tasks.append(newTask)
            }
        }

        return tasks
    }
    
    private func parseDate(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: str)
    }
}	

