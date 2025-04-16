//
//  ContentView.swift
//  YourDay
//
//  Created by Rachit Verma on 4/8/25.
//

import SwiftUI

struct Todoview: View {
    @StateObject var viewModel = TodoViewModel()
    init() {
        
    }
    var body: some View {
        NavigationView {
            VStack {
                
            }
            .navigationTitle("To Do List")
            .toolbar {
                Button {
                    viewModel.showingNewItemView = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $viewModel.showingNewItemView){
                NewItemview(newItemPresented: $viewModel.showingNewItemView)
            }
        }
    }
}

