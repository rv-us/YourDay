//
//  DailyPlanningNoteView.swift
//  YourDay
//
//  View for daily planning note input that extracts tasks
//

import SwiftUI
import SwiftData
import FirebaseVertexAI
import FirebaseAuth

struct DailyPlanningNoteView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Binding var isPresented: Bool
    @State private var noteText: String = ""
    @State private var isGenerating = false
    @State private var generatedTasks: [TodoItem] = []
    @State private var showingConfirmGeneratedTasks = false

    /// Typewriter + fade cycle for empty editor (cancelled when user types).
    @State private var placeholderDisplayedText: String = ""
    @State private var placeholderOpacity: Double = 0
    @State private var suggestionCycleTask: Task<Void, Never>?

    var onComplete: (() -> Void)? = nil

    private let today = Calendar.current.startOfDay(for: Date())

    private static let planningSuggestions: [String] = [
        "I'd like to finish my essay draft and submit it before 5pm…",
        "Complete the HR onboarding form and upload my documents…",
        "Run errands: groceries, pharmacy, then prep dinner…",
        "Call the dentist back and schedule a cleaning for next week…",
        "Study two chapters for the exam and do the practice quiz…",
    ]

    private var isNoteEffectivelyEmpty: Bool {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("What else are you planning today?")
                                .font(.title2.weight(.bold))
                                .foregroundColor(dynamicTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                                .minimumScaleFactor(0.85)

                            Text("Jot down what you want to get done—we'll turn it into tasks.")
                                .font(.subheadline)
                                .foregroundColor(dynamicSecondaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.subheadline)
                                    .foregroundColor(dynamicPrimaryColor)
                                    .frame(width: 22, alignment: .center)
                                Text("Be specific: names, times, and locations help us extract better tasks.")
                                    .font(.caption)
                                    .foregroundColor(dynamicSecondaryTextColor)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            planningEditorCard
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .background(dynamicBackgroundColor)
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
                        stopSuggestionCycle()
                        onComplete?()
                        isPresented = false
                    }
                    .foregroundColor(dynamicPrimaryColor)
                }
                ToolbarItem(placement: .principal) {
                    Text("Today's plans")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        extractAndSaveTasks()
                    }
                    .disabled(isNoteEffectivelyEmpty || isGenerating)
                    .foregroundColor(isNoteEffectivelyEmpty || isGenerating ? dynamicSecondaryTextColor.opacity(0.5) : dynamicPrimaryColor)
                }
            }
            .onAppear {
                if isNoteEffectivelyEmpty, !isGenerating {
                    startSuggestionCycle()
                }
            }
            .onDisappear {
                stopSuggestionCycle()
            }
            .onChange(of: noteText) { _, _ in
                if isNoteEffectivelyEmpty, !isGenerating {
                    startSuggestionCycle()
                } else {
                    stopSuggestionCycle()
                    placeholderDisplayedText = ""
                    placeholderOpacity = 0
                }
            }
            .onChange(of: isGenerating) { _, generating in
                if generating {
                    stopSuggestionCycle()
                    placeholderDisplayedText = ""
                    placeholderOpacity = 0
                } else if isNoteEffectivelyEmpty {
                    startSuggestionCycle()
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingConfirmGeneratedTasks) {
            ConfirmGeneratedTasksView(tasks: generatedTasks) { selectedTasks in
                for task in selectedTasks {
                    context.insert(task)

                    // Sync new task to Firebase
                    if let userId = FirebaseAuth.Auth.auth().currentUser?.uid {
                        let codableTask = TodoItemCodable(from: task, userId: userId)
                        FirebaseManager.shared.saveTodoItem(codableTask) { error in
                            if let error = error {
                                print("DailyPlanningNoteView: Failed to sync generated task to Firebase: \(error.localizedDescription)")
                            } else {
                                print("DailyPlanningNoteView: Successfully synced generated task to Firebase")
                            }
                        }
                    }
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

    private var planningEditorCard: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $noteText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200, idealHeight: 240, maxHeight: 280)
                .padding(10)
                .foregroundColor(dynamicTextColor)
                .textInputAutocapitalization(.sentences)

            if isNoteEffectivelyEmpty {
                Text(placeholderDisplayedText.isEmpty ? " " : placeholderDisplayedText)
                    .font(.body)
                    .foregroundColor(dynamicSecondaryTextColor.opacity(0.5 * placeholderOpacity))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .multilineTextAlignment(.leading)
                    .allowsHitTesting(false)
            }
        }
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(dynamicSecondaryTextColor.opacity(0.5), lineWidth: 1)
        )
    }

    private func startSuggestionCycle() {
        stopSuggestionCycle()
        guard isNoteEffectivelyEmpty, !isGenerating else { return }

        suggestionCycleTask = Task { @MainActor in
            var suggestionIndex = 0
            while !Task.isCancelled {
                guard isNoteEffectivelyEmpty, !isGenerating else { break }

                let fullText = Self.planningSuggestions[suggestionIndex % Self.planningSuggestions.count]
                placeholderOpacity = 1
                placeholderDisplayedText = ""

                for charCount in 1...fullText.count {
                    guard !Task.isCancelled, isNoteEffectivelyEmpty, !isGenerating else { break }
                    let end = fullText.index(fullText.startIndex, offsetBy: charCount)
                    placeholderDisplayedText = String(fullText[..<end])
                    try? await Task.sleep(nanoseconds: 42_000_000)
                }

                guard !Task.isCancelled, isNoteEffectivelyEmpty, !isGenerating else { break }
                try? await Task.sleep(nanoseconds: 1_100_000_000)

                guard !Task.isCancelled, isNoteEffectivelyEmpty, !isGenerating else { break }
                withAnimation(.easeOut(duration: 0.45)) {
                    placeholderOpacity = 0
                }
                try? await Task.sleep(nanoseconds: 480_000_000)

                guard !Task.isCancelled, isNoteEffectivelyEmpty, !isGenerating else { break }
                placeholderDisplayedText = ""
                placeholderOpacity = 1
                suggestionIndex += 1
            }
        }
    }

    private func stopSuggestionCycle() {
        suggestionCycleTask?.cancel()
        suggestionCycleTask = nil
    }

    private func extractAndSaveTasks() {
        let trimmedText = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        stopSuggestionCycle()
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
                let model = vertex.generativeModel(modelName: "gemini-2.5-flash")

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
