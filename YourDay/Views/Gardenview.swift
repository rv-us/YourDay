//
//  Gardenview.swift
//  YourDay
//
//  Created by Rachit Verma on 5/8/25.
//

import SwiftUI
import SwiftData

struct GardenView: View {
    @Environment(\.modelContext) private var context
    @Query private var playerStatsList: [PlayerStats]
    private var currentPlayerStats: PlayerStats {
        playerStatsList.first ?? PlayerStats()
    }
    var body: some View {
        NavigationView {
            VStack {
               
                Text("Your Garden Plot")
                    .font(.title3)
                    .padding()
                
             
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                        ForEach(0..<20) { index in 
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.green.opacity(0.3))
                                .frame(height: 80)
                                .overlay(
                                    Text("Plot \(index + 1)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                )
                        }
                    }
                    .padding()
                }
                
                Spacer()
                
                Text("Tap on a plot to plant something!")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom)
            }
            .navigationTitle("My Garden")
            .toolbar {
                
                ToolbarItem(placement: .navigationBarLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Level: \(currentPlayerStats.playerLevel)")
                            .font(.headline)
                            .foregroundColor(.blue)
                        Text("Garden Value: \(Int(currentPlayerStats.gardenValue))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 0)
                }
                
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(.orange)
                        Text("\(Int(currentPlayerStats.totalPoints))")
                            .font(.headline)
                            .foregroundColor(.orange)
                    }
                    .padding(.trailing, 0)
                }
            }
            .onAppear {
                if playerStatsList.isEmpty {
                    let newStats = PlayerStats() // Initializes with default values
                    context.insert(newStats)
                    print("Created and inserted default PlayerStats.")
                }
            }
        }
    }
}
