//
//  PlantInfoView.swift
//  YourDay
//
//  Created by [Your Name] on 5/13/25.
//

import SwiftUI

struct PlantInfoView: View {
    @Environment(\.dismiss) var dismiss
    let plant: PlacedPlant // The PlacedPlant instance passed to this view

    // Fetches the blueprint for description and the primary grown visual.
    // This lookup is based on properties also available in PlacedPlant.
    // A more direct link would be a blueprintID stored on PlacedPlant.
    private var plantBlueprint: PlantBlueprint? {
        PlantLibrary.allPlantBlueprints.first { bp in
            // Matching based on common identifying characteristics
            // Adjust if your matching criteria should be different (e.g., if names aren't unique across rarities/themes)
            bp.name == plant.name && bp.rarity == plant.rarity && bp.theme == plant.theme
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .center, spacing: 20) {
                    Text(plant.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top)

                    // Display the grown visual of the plant
                    // PlantVisualDisplayView should handle assets vs placeholders.
                    // We use the assetName from the PlacedPlant which came from the Blueprint.
                    PlantVisualDisplayView(
                        assetName: plant.assetName, // Use assetName from PlacedPlant
                        rarity: plant.rarity,
                        displayName: plant.name,
                        isIcon: false // We want the larger "grown" visual
                    )
                    .frame(width: 200, height: 200)
                    .background(plant.rarity.backgroundColor) // Use rarity background color
                    .cornerRadius(15)
                    .shadow(radius: 5)
                    
                    VStack(alignment: .leading, spacing: 15) {
                        InfoRow(label: "Status",
                                value: plant.isFullyGrown ? "Fully Grown" : "\(plant.daysLeftTillFullyGrown) days to grow")
                        
                        InfoRow(label: "Rarity",
                                value: plant.rarity.rawValue,
                                valueColor: plant.rarity.textColor) // Uses Rarity.textColor
                        
                        InfoRow(label: "Theme",
                                value: plant.theme.rawValue,
                                valueColor: plant.theme.color)   // Uses PlantTheme.color
                        
                        // Display Current Value using PlacedPlant's getCurrentDynamicValue()
                        InfoRow(label: "Current Value",
                                value: "\(Int(plant.getCurrentDynamicValue())) Points")

                        // Display Theme Bonus information using PlacedPlant's themeBonusDetails
                        let bonusInfo = plant.themeBonusDetails
                        if plant.isFullyGrown { // Theme bonus is typically relevant for grown plants
                            if bonusInfo.isActive {
                                HStack {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                    Text("Seasonal Bonus Active! (Value x\(String(format: "%.1f", bonusInfo.multiplier)))")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                }
                            } else if let currentSeason = bonusInfo.currentSeason {
                                Text("Plant Theme: \(plant.theme.rawValue) (Current Season: \(currentSeason.rawValue))")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Divider()

                        if let blueprint = plantBlueprint, !blueprint.description.isEmpty {
                            Text("Description:")
                                .font(.headline)
                                .padding(.top, 5)
                            Text(blueprint.description)
                                .font(.body)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No description available.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(.top, 5)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Plant Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// InfoRow struct (ensure it's defined, possibly in this file or a shared UI components file)
struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(label + ":")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(valueColor)
        }
        Divider()
    }
}
