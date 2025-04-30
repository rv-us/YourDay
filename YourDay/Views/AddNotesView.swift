//
//  AddNotesView.swift
//  YourDay
//

import SwiftUI
import SwiftData
import FirebaseVertexAI

struct AddNotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\NoteItem.createdAt, order: .reverse)]) private var notes: [NoteItem]
    @State private var showingNewNoteView = false
    @State private var selectedNotes: Set<NoteItem> = []
    @State private var isSelecting = false
    @State private var generatedTasks: [TodoItem] = []
    @State private var showingConfirmGeneratedTasks = false

    var body: some View {
        NavigationView {
            VStack {
                List(selection: isSelecting ? $selectedNotes : .constant([])) {
                    ForEach(notes) { note in
                        if isSelecting {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(note.content.isEmpty ? "New Note" : note.content)
                                    .lineLimit(1)
                                    .font(.body)
                                Text(note.createdAt, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 4)
                            .tag(note)
                        } else {
                            NavigationLink(destination: NoteDetailView(note: note)) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(note.content.isEmpty ? "New Note" : note.content)
                                        .lineLimit(1)
                                        .font(.body)
                                    Text(note.createdAt, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            context.delete(notes[index])
                        }
                    }
                }
                .listStyle(.plain)
                .navigationTitle("Notes")

                if isSelecting {
                    Button(action: generateTasksFromSelectedNotes) {
                        Text("Generate Tasks")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedNotes.isEmpty ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }
                    .disabled(selectedNotes.isEmpty)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isSelecting.toggle()
                        selectedNotes.removeAll()
                    } label: {
                        Text(isSelecting ? "Cancel" : "Select Notes")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingNewNoteView = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showingNewNoteView) {
                NewNoteView(isPresented: $showingNewNoteView)
            }
            .sheet(isPresented: $showingConfirmGeneratedTasks) {
                ConfirmGeneratedTasksView(tasks: generatedTasks) { selectedTasks in
                    for task in selectedTasks {
                        context.insert(task)
                    }
                    generatedTasks = []
                    showingConfirmGeneratedTasks = false
                }
            }
        }
    }

    func generateTasksFromSelectedNotes() {
        let combinedText = selectedNotes.map { $0.content }.joined(separator: "\n\n")
        Task {
            do {
                let prompt = """
                You are an intelligent task management assistant. Your goal is to process a series of notes and extract actionable tasks with relevant details.

                Analyze the following notes and generate a structured list of tasks. For each task, identify a concise title, a more detailed description (if implied), and a potential due date if one can be reasonably inferred from the context. If a task can be broken down further, suggest a list of subtasks.

                Format each task clearly using the following structure:

                [Task]
                Title: <concise title>
                Description: <detailed description or "None">
                DueDate: <YYYY-MM-DD or "None">
                Subtasks:
                - <subtask 1>
                - <subtask 2>
                ...

                --- Notes ---

                \(combinedText)

                Ensure that the generated tasks are specific, measurable, achievable, relevant, and time-bound (SMART) where possible. If a due date isn't explicitly mentioned or strongly implied, mark it as "None". Be concise and avoid unnecessary conversational elements. Additionally, write the tasks in a format that is similar to my writing style.
                """

                let vertex = VertexAI.vertexAI()
                let model = vertex.generativeModel(modelName: "gemini-1.5-flash")
                
                let userMessage = try ModelContent(role: "user", parts: [TextPart(prompt)])
                let response = try await model.generateContent([userMessage])
                print(response)
                if let text = response.text {
                    let tasks = parseGeminiResponse(text)
                    generatedTasks = tasks
                    showingConfirmGeneratedTasks = true
                    isSelecting = false
                } else {
                    print("⚠️ Received an empty response from the AI.")
                }
            } catch {
                print("❌ Failed to generate tasks: \(error.localizedDescription)")
            }
        }
    }

    func parseGeminiResponse(_ text: String) -> [TodoItem] {
        var tasks: [TodoItem] = []

        // Use regex to find each [Task X] block
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

        // Append final block
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

                let dueDateString = dueDateMatch.flatMap { block[$0].components(separatedBy: "DueDate: ").last?.trimmingCharacters(in: .whitespacesAndNewlines) } ?? "None"

                let subtasks = subtasksMatches.map { match in
                    Subtask(title: match)
                }

                let dueDate: Date = {
                    if dueDateString == "None" { return Date().addingTimeInterval(86400*7) }
                    else if let date = parseDate(dueDateString) {
                        return date
                    } else {
                        return Date().addingTimeInterval(86400*7)
                    }
                }()

                let newTask = TodoItem(
                    title: title,
                    detail: description,
                    dueDate: dueDate,
                    subtasks: subtasks
                )
                tasks.append(newTask)
            }
        }

        return tasks
    }


    func parseDate(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: str)
    }
}

extension String {
    func matches(for regex: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let nsString = self as NSString
            let results = regex.matches(in: self, range: NSRange(location: 0, length: nsString.length))
            return results.map { nsString.substring(with: $0.range(at: 1)) }
        } catch let error {
            print("Invalid regex: \(error.localizedDescription)")
            return []
        }
    }
}
