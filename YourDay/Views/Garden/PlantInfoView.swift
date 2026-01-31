////
////  PlantInfoView.swift
////  YourDay
////
////  Created by [Your Name] on 5/13/25.
////
//
//import SwiftUI
//
//struct PlantInfoView: View {
//    @Environment(\.dismiss) var dismiss
//    let plant: PlacedPlant // The PlacedPlant instance passed to this view
//
//    // Fetches the blueprint for description and the primary grown visual.
//    // This lookup is based on properties also available in PlacedPlant.
//    // A more direct link would be a blueprintID stored on PlacedPlant.
//    private var plantBlueprint: PlantBlueprint? {
//        PlantLibrary.allPlantBlueprints.first { bp in
//            // Matching based on common identifying characteristics
//            // Adjust if your matching criteria should be different (e.g., if names aren't unique across rarities/themes)
//            bp.name == plant.name && bp.rarity == plant.rarity && bp.theme == plant.theme
//        }
//    }
//
//    var body: some View {
//        NavigationView {
//            ScrollView {
//                VStack(alignment: .center, spacing: 20) {
//                    Text(plant.name)
//                        .font(.largeTitle)
//                        .fontWeight(.bold)
//                        .padding(.top)
//
//                    // Display the grown visual of the plant
//                    // PlantVisualDisplayView should handle assets vs placeholders.
//                    // We use the assetName from the PlacedPlant which came from the Blueprint.
//                    PlantVisualDisplayView(
//                        assetName: plant.assetName, // Use assetName from PlacedPlant
//                        rarity: plant.rarity,
//                        displayName: plant.name,
//                        isIcon: false // We want the larger "grown" visual
//                    )
//                    .frame(width: 200, height: 200)
//                    .background(plant.rarity.backgroundColor) // Use rarity background color
//                    .cornerRadius(15)
//                    .shadow(radius: 5)
//                    
//                    VStack(alignment: .leading, spacing: 15) {
//                        InfoRow(label: "Status",
//                                value: plant.isFullyGrown ? "Fully Grown" : "\(plant.daysLeftTillFullyGrown) days to grow")
//                        
//                        InfoRow(label: "Rarity",
//                                value: plant.rarity.rawValue,
//                                valueColor: plant.rarity.textColor) // Uses Rarity.textColor
//                        
//                        InfoRow(label: "Theme",
//                                value: plant.theme.rawValue,
//                                valueColor: plant.theme.color)   // Uses PlantTheme.color
//                        
//                        // Display Current Value using PlacedPlant's getCurrentDynamicValue()
//                        InfoRow(label: "Current Value",
//                                value: "\(Int(plant.getCurrentDynamicValue())) Points")
//
//                        // Display Theme Bonus information using PlacedPlant's themeBonusDetails
//                        let bonusInfo = plant.themeBonusDetails
//                        if plant.isFullyGrown { // Theme bonus is typically relevant for grown plants
//                            if bonusInfo.isActive {
//                                HStack {
//                                    Image(systemName: "star.fill")
//                                        .foregroundColor(.yellow)
//                                    Text("Seasonal Bonus Active! (Value x\(String(format: "%.1f", bonusInfo.multiplier)))")
//                                        .font(.subheadline)
//                                        .foregroundColor(.green)
//                                }
//                            } else if let currentSeason = bonusInfo.currentSeason {
//                                Text("Plant Theme: \(plant.theme.rawValue) (Current Season: \(currentSeason.rawValue))")
//                                    .font(.subheadline)
//                                    .foregroundColor(.gray)
//                            }
//                        }
//                        
//                        Divider()
//
//                        if let blueprint = plantBlueprint, !blueprint.description.isEmpty {
//                            Text("Description:")
//                                .font(.headline)
//                                .padding(.top, 5)
//                            Text(blueprint.description)
//                                .font(.body)
//                                .foregroundColor(.secondary)
//                        } else {
//                            Text("No description available.")
//                                .font(.body)
//                                .foregroundColor(.secondary)
//                                .padding(.top, 5)
//                        }
//                    }
//                    .padding(.horizontal)
//                    
//                    Spacer()
//                }
//                .padding()
//            }
//            .navigationTitle("Plant Details")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    Button("Done") {
//                        dismiss()
//                    }
//                }
//            }
//        }
//    }
//}
//
//// InfoRow struct (ensure it's defined, possibly in this file or a shared UI components file)
//struct InfoRow: View {
//    let label: String
//    let value: String
//    var valueColor: Color = .primary
//
//    var body: some View {
//        HStack {
//            Text(label + ":")
//                .font(.headline)
//                .foregroundColor(.secondary)
//            Spacer()
//            Text(value)
//                .font(.body)
//                .fontWeight(.medium)
//                .foregroundColor(valueColor)
//        }
//        Divider()
//    }
//}

import SwiftUI
import SwiftData

struct PlantInfoView: View {
    @Environment(\.dismiss) var dismiss
    let plant: PlacedPlant

    private var plantBlueprint: PlantBlueprint? {
        PlantLibrary.allPlantBlueprints.first { bp in
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
                        .foregroundColor(plantDarkGreen) // Themed color
                        .padding(.top)

                    PlantVisualDisplayView(
                        assetName: plant.assetName,
                        rarity: plant.rarity,
                        displayName: plant.name,
                        isIcon: false
                    )
                    .frame(width: 200, height: 200)
                    .background(plant.rarity.backgroundColor) // Uses themed rarity background color
                    .cornerRadius(15)
                    .shadow(color: plantDarkGreen.opacity(0.2), radius: 5) // Themed shadow
                    
                    VStack(alignment: .leading, spacing: 15) {
                        InfoRow(label: "Status",
                                value: plant.isFullyGrown ? "Fully Grown" : "\(plant.daysLeftTillFullyGrown) days to grow",
                                valueColor: plant.isFullyGrown ? plantMediumGreen : plantDustyBlue) // Themed status color
                        
                        InfoRow(label: "Rarity",
                                value: plant.rarity.rawValue,
                                valueColor: plant.rarity.textColor) // Uses themed Rarity.textColor
                        
                        InfoRow(label: "Theme",
                                value: plant.theme.rawValue,
                                valueColor: plant.theme.color)  // Uses themed PlantTheme.color
                        
                        InfoRow(label: "Current Value",
                                value: "\(Int(plant.getCurrentDynamicValue())) Points",
                                valueColor: plantMediumGreen) // Themed value color

                        let bonusInfo = plant.themeBonusDetails
                        if plant.isFullyGrown {
                            if bonusInfo.isActive {
                                HStack {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(plantPeach) // Themed highlight color
                                    Text("Seasonal Bonus Active! (Value x\(String(format: "%.1f", bonusInfo.multiplier)))")
                                        .font(.subheadline)
                                        .foregroundColor(plantMediumGreen) // Themed color
                                }
                            } else if let currentSeason = bonusInfo.currentSeason {
                                Text("Plant Theme: \(plant.theme.rawValue) (Current Season: \(currentSeason.rawValue))")
                                    .font(.subheadline)
                                    .foregroundColor(plantDustyBlue) // Themed color
                            }
                        }
                        
                        Divider().background(plantPastelGreen) // Themed divider

                        if let blueprint = plantBlueprint, !blueprint.description.isEmpty {
                            Text("Description:")
                                .font(.headline)
                                .foregroundColor(plantDarkGreen) // Themed color
                                .padding(.top, 5)
                            Text(blueprint.description)
                                .font(.body)
                                .foregroundColor(plantMediumGreen) // Themed color
                        } else {
                            Text("No description available.")
                                .font(.body)
                                .foregroundColor(plantDustyBlue) // Themed color
                                .padding(.top, 5)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
                .padding() // Padding around the main VStack content
            }
            .background(dynamicSecondaryBackgroundColor.edgesIgnoringSafeArea(.all)) // Overall view background
            .navigationTitle("Plant Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicBackgroundColor, for: .navigationBar) // Themed navigation bar background
            .toolbarBackground(.visible, for: .navigationBar) // Make background visible
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(plantDarkGreen) // Themed button color
                }
            }
        }
        .navigationViewStyle(.stack) // Consistent navigation style
    }
}

// InfoRow struct
struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = plantDarkGreen // Themed default value color

    var body: some View {
        HStack {
            Text(label + ":")
                .font(.headline)
                .foregroundColor(plantMediumGreen) // Themed label color
            Spacer()
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(valueColor) // Uses themed valueColor (default or passed)
        }
        Divider().background(plantPastelGreen) // Themed divider
    }
}
