//
//  ContentView.swift
//  YourDay
//
//  Created by Rachit Verma on 4/8/25.
//

import SwiftUI

struct Todoview: View {
    @StateObject var viewModel = TodoViewModel()
    var body: some View {
        NavigationView {
            VStack {
                
            }
            .navigationTitle("To Do List")
            .toolbar {
                Button {
                    
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

