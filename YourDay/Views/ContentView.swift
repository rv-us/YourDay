//
//  ContentView.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 4/27/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Todoview()
                .tabItem {
                    Image(systemName: "checkmark.circle")
                    Text("Tasks")
                }
            
            AddNotesView()
                .tabItem {
                    Image(systemName: "note.text")
                    Text("Notes")
                }
        }
    }
}

#Preview {
    ContentView()
}
