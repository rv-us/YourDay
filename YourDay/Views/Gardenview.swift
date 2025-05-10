//
//  GardenView.swift
//  YourDay
//
//  Created by Rachit Verma on 5/8/25.
//

import SwiftUI
import SwiftData

struct GardenView: View {
    @Environment(\.modelContext) private var context
    
    @Query(filter: #Predicate<PlayerStats> { _ in true } ) private var playerStatsList: [PlayerStats]
    
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private var playerStats: PlayerStats {
        playerStatsList.first ?? PlayerStats()
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 15) {
                
                // Plot information and purchase button
                VStack {
                    Text("Plots: \(playerStats.numberOfOwnedPlots) / \(playerStats.maxPlotsForCurrentLevel)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if playerStats.numberOfOwnedPlots < playerStats.maxPlotsForCurrentLevel {
                        Button(action: attemptToBuyPlot) {
                            Text("Buy New Plot (\(Int(playerStats.costToBuyNextPlot())) Points)")
                                .font(.callout)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(playerStats.totalPoints >= playerStats.costToBuyNextPlot() ? Color.blue : Color.gray.opacity(0.5))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .disabled(playerStats.totalPoints < playerStats.costToBuyNextPlot())
                    } else {
                        Text("Max plots for current level reached.")
                            .font(.callout)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top)

                // Garden Grid - Simplified
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 85, maximum: 100))], spacing: 12) {
                        ForEach(0..<playerStats.numberOfOwnedPlots, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.green.opacity(0.3)) // Simple green plot
                                .frame(minHeight: 80, maxHeight: 100)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    Text("Plot \(index + 1)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                )
                                // onTapGesture for planting can be added back later
                                // .onTapGesture {
                                //     // Placeholder for future planting action on this specific plot
                                //     showAlert(title: "Plot \(index + 1)", message: "Ready for planting!")
                                // }
                        }
                    }
                    .padding()
                }
                
                Spacer()
                
                Text("Expand your garden by buying more plots!") // Updated instruction
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom)
            }
            .navigationTitle("My Garden")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Level: \(playerStats.playerLevel)")
                            .font(.headline).foregroundColor(.blue)
                        Text("Value: \(Int(playerStats.gardenValue))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill").foregroundColor(.orange)
                        Text("\(Int(playerStats.totalPoints))")
                            .font(.headline).foregroundColor(.orange)
                    }
                }
            }
            .onAppear {
                if playerStatsList.isEmpty {
                    let newStats = PlayerStats()
                    context.insert(newStats)
                    print("GardenView: Created and inserted default PlayerStats.")
                }
                // Removed playerStats.updateGardenValue() from onAppear as plant-specific logic is out for now.
                // Garden value will primarily change when plants are added/sold/grown later.
            }
            .alert(isPresented: $showingAlert) {
                Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

    // Action to attempt buying a new plot
    func attemptToBuyPlot() {
        guard let mutablePlayerStats = playerStatsList.first else {
            showAlert(title: "Error", message: "Player data not found.")
            return
        }

        let cost = mutablePlayerStats.costToBuyNextPlot()
        if mutablePlayerStats.numberOfOwnedPlots < mutablePlayerStats.maxPlotsForCurrentLevel {
            if mutablePlayerStats.totalPoints >= cost {
                if mutablePlayerStats.buyNextPlot() {
                    showAlert(title: "Plot Purchased!", message: "You now have \(mutablePlayerStats.numberOfOwnedPlots) plots.")
                } else {
                    showAlert(title: "Purchase Failed", message: "Could not buy a new plot at this time.")
                }
            } else {
                showAlert(title: "Not Enough Points", message: "You need \(Int(cost)) points to buy a new plot. You have \(Int(mutablePlayerStats.totalPoints)).")
            }
        } else {
            showAlert(title: "Max Plots Reached", message: "You have reached the maximum number of plots for your current level.")
        }
    }
    
    // Helper to show alerts
    func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}

