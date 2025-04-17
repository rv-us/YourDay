//
//  NewItemview.swift
//  YourDay
//
//  Created by Rachit Verma on 4/16/25.
//

import SwiftUI
import SwiftData

struct NewItemview: View{
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel = NewItemModel()
    @Binding var newItemPresented: Bool
    var body: some View {
        VStack {
            Text("New Task")
                .font(.system(size: 32))
                .bold()
                .padding(.top, 100)
            Form {
                TextField("Task", text: $viewModel.title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Description", text: $viewModel.description)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                DatePicker("Due Date", selection: $viewModel.donebye)
                    .datePickerStyle(GraphicalDatePickerStyle())
                Button(action: {
                    if viewModel.canSave {
                        let newItem = TodoItem(
                            title: viewModel.title,
                            detail: viewModel.description,
                            dueDate: viewModel.donebye
                        )
                        context.insert(newItem)
                        dismiss()
                    } else {
                        viewModel.showAlert = true
                    }
                }) {
                    Text("Add")
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()
            }
            .alert(isPresented: $viewModel.showAlert) {
                Alert(title: Text("Error"), message: Text("Please fill in task field and select future due date"))
            }
        }
    }
}
