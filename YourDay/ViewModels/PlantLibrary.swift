//
//  PlantLibrary.swift
//  YourDay
//
//  Created by Your Name on 5/9/25.
//

import SwiftUI
import Foundation

// Note: Ensure Rarity and PlantTheme enums are accessible here from PlayerStats.swift.

/// Defines the static properties of a type of plant available in the game.
struct PlantBlueprint: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let rarity: Rarity
    let theme: PlantTheme
    let initialDaysToGrow: Int
    let baseValue: Double
    let assetName: String
    let iconName: String

    var grownVisual: PlantVisualDisplayView {
        PlantVisualDisplayView(assetName: self.assetName, rarity: self.rarity, displayName: self.name, isIcon: false)
    }
    var iconVisual: PlantVisualDisplayView {
        PlantVisualDisplayView(assetName: self.iconName, rarity: self.rarity, displayName: self.name, isIcon: true)
    }
}

/// A reusable view to display a plant's visual (actual image or placeholder).
struct PlantVisualDisplayView: View {
    let assetName: String
    let rarity: Rarity
    let displayName: String
    let isIcon: Bool

    // This color is used for the placeholder rectangle fill AND now for the asset's background
    private func rarityBasedColor() -> Color {
        switch rarity {
        case .common:   return Color.gray.opacity(0.5)
        case .uncommon: return Color.green.opacity(0.5)
        case .rare:     return Color.blue.opacity(0.5)
        case .epic:     return Color.purple.opacity(0.5)
        case .legendary: return Color.orange.opacity(0.5)
        }
    }

    var body: some View {
        // Attempt to load the image.
        if UIImage(named: assetName) != nil {
            // Asset IS found
            ZStack {
                // Background color based on rarity (using the same logic as placeholder)
                // We use a RoundedRectangle to get the shape and then fill it.
                RoundedRectangle(cornerRadius: isIcon ? 6 : 10)
                    .fill(rarityBasedColor())
                
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    // Add padding if you want the background to act as a border around the image
                    .padding(isIcon ? 3 : 6)
            }
            // No need to apply .cornerRadius to the ZStack here if the RoundedRectangle handles it.
            // The ZStack will implicitly take the shape of its content if not given a frame.
            // However, if you want to ensure a consistent outer shape, you can clip the ZStack:
            // .clipShape(RoundedRectangle(cornerRadius: isIcon ? 6 : 10))

        } else {
            // Asset IS NOT found - use the existing placeholder logic
            RoundedRectangle(cornerRadius: isIcon ? 6 : 10)
                .fill(rarityBasedColor()) // Uses the same rarity color for the placeholder fill
                .overlay(
                    VStack {
                        Text(isIcon ? String(displayName.prefix(1)) : displayName)
                            .font(isIcon ? .caption2 : .caption)
                            .fontWeight(isIcon ? .bold : .medium)
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(isIcon ? 1 : 2)
                            .minimumScaleFactor(0.7)
                        if !isIcon {
                            Text(rarity.rawValue)
                                .font(.system(size: 8))
                                .padding(.horizontal, 3)
                                .background(Color.black.opacity(0.2))
                                .cornerRadius(3)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }.padding(isIcon ? 2 : 4)
                )
        }
    }
}

/// A library to hold all defined plant blueprints in the game.
struct PlantLibrary {
    static let allPlantBlueprints: [PlantBlueprint] = [
        // Common Plants
        PlantBlueprint(id: "sunflower_c_su", name: "Sunflower", description: "A cheerful flower.", rarity: .common, theme: .summer, initialDaysToGrow: 3, baseValue: 25, assetName: "spring-common0", iconName: "spring-common0"),
        PlantBlueprint(id: "tulip_c_sp", name: "Tulip", description: "A classic spring bulb.", rarity: .common, theme: .spring, initialDaysToGrow: 3, baseValue: 25, assetName: "summer-common0", iconName: "summer-common0"),
        PlantBlueprint(id: "marigold_c_fa", name: "Marigold", description: "Hardy autumn bloom.", rarity: .common, theme: .fall, initialDaysToGrow: 3, baseValue: 25, assetName: "marigold_grown", iconName: "marigold_icon"),
        PlantBlueprint(id: "pansy_c_wi", name: "Pansy", description: "Resilient winter color.", rarity: .common, theme: .winter, initialDaysToGrow: 3, baseValue: 25, assetName: "pansy_grown", iconName: "pansy_icon"),
        PlantBlueprint(id: "fern_c_sp", name: "Spring Fern", description: "A lush, green fern unfurling in spring.", rarity: .common, theme: .spring, initialDaysToGrow: 3, baseValue: 25, assetName: "spring-common1", iconName: "spring-common1"),
        PlantBlueprint(id: "cactus_c_su", name: "Desert Bloom", description: "A hardy cactus that flowers in summer.", rarity: .common, theme: .summer, initialDaysToGrow: 3, baseValue: 25, assetName: "summer-common1", iconName: "summer-common1"),
        PlantBlueprint(id: "pumpkin_c_fa", name: "Mini Pumpkin", description: "A small, decorative pumpkin, perfect for fall.", rarity: .common, theme: .fall, initialDaysToGrow: 3, baseValue: 25, assetName: "pumpkin_grown", iconName: "pumpkin_icon"),
        PlantBlueprint(id: "holly_c_wi", name: "Winter Holly", description: "Festive holly with bright red berries.", rarity: .common, theme: .winter, initialDaysToGrow: 3, baseValue: 25, assetName: "holly_grown", iconName: "holly_icon"),


        // Uncommon Plants
        PlantBlueprint(id: "lavender_uc_su", name: "Lavender", description: "Soothing scent.", rarity: .uncommon, theme: .summer, initialDaysToGrow: 2, baseValue: 50, assetName: "spring-uncommon", iconName: "spring-uncommon"),
        PlantBlueprint(id: "daffodil_uc_sp", name: "Daffodil", description: "Joyful herald of spring.", rarity: .uncommon, theme: .spring, initialDaysToGrow: 2, baseValue: 50, assetName: "summer-uncommon", iconName: "summer-uncommon"),
        PlantBlueprint(id: "aster_uc_fa", name: "Autumn Aster", description: "Late blooming, star-shaped flowers.", rarity: .uncommon, theme: .fall, initialDaysToGrow: 2, baseValue: 50, assetName: "aster_grown", iconName: "aster_icon"),
        PlantBlueprint(id: "snowdrop_uc_wi", name: "Snowdrop", description: "One of the first signs of life in late winter.", rarity: .uncommon, theme: .winter, initialDaysToGrow: 2, baseValue: 50, assetName: "snowdrop_grown", iconName: "snowdrop_icon"),

        // Rare Plants
        PlantBlueprint(id: "rose_r_sp", name: "Mystic Rose", description: "Enchanting spring rose.", rarity: .rare, theme: .spring, initialDaysToGrow: 2, baseValue: 75, assetName: "spring-rare", iconName: "spring-rare"),
        PlantBlueprint(id: "orchid_r_su", name: "Sun Orchid", description: "Exotic summer orchid.", rarity: .rare, theme: .summer, initialDaysToGrow: 2, baseValue: 75, assetName: "summer-rare", iconName: "summer-rare"),
        PlantBlueprint(id: "nightshade_r_fa", name: "Shadow Bloom", description: "A mysterious flower that prefers the autumn twilight.", rarity: .rare, theme: .fall, initialDaysToGrow: 3, baseValue: 75, assetName: "nightshade_grown", iconName: "nightshade_icon"),
        PlantBlueprint(id: "iceflower_r_wi", name: "Ice Flower", description: "A delicate flower that seems to be made of frost.", rarity: .rare, theme: .winter, initialDaysToGrow: 3, baseValue: 75, assetName: "iceflower_grown", iconName: "iceflower_icon"),

        // Epic Plants
        PlantBlueprint(id: "moonflower_e_fa", name: "Moonflower", description: "Blooms under autumn moonlight.", rarity: .epic, theme: .fall, initialDaysToGrow: 3, baseValue: 150, assetName: "moonflower_grown", iconName: "moonflower_icon"),
        PlantBlueprint(id: "crystalbloom_e_wi", name: "Crystal Bloom", description: "Shimmers like ice in winter.", rarity: .epic, theme: .winter, initialDaysToGrow: 3, baseValue: 150, assetName: "crystalbloom_grown", iconName: "crystalbloom_icon"),
        PlantBlueprint(id: "dreamlily_e_sp", name: "Dream Lily", description: "A vibrant lily that inspires vivid dreams, blooming in spring.", rarity: .epic, theme: .spring, initialDaysToGrow: 4, baseValue: 150, assetName: "spring-epic", iconName: "spring-epic"),
        PlantBlueprint(id: "solarflare_e_su", name: "Solar Flare", description: "Radiates warmth and light, a true summer spectacle.", rarity: .epic, theme: .summer, initialDaysToGrow: 4, baseValue: 150, assetName: "summer-epic", iconName: "summer-epic"),
        
        // Legendary Plants
        PlantBlueprint(id: "starpetal_l_sp", name: "Starpetal", description: "Captures starlight. A spring marvel.", rarity: .legendary, theme: .spring, initialDaysToGrow: 5, baseValue: 300, assetName: "spring-legendary", iconName: "spring-legendary"),
        PlantBlueprint(id: "phoenixbloom_l_su", name: "Phoenix Bloom", description: "Legendary summer plant of rebirth.", rarity: .legendary, theme: .summer, initialDaysToGrow: 5, baseValue: 300, assetName: "summer-legendary", iconName: "summer-legendary"),
        PlantBlueprint(id: "ancientshade_l_fa", name: "Ancient Shade", description: "A plant of immense age and wisdom, thriving in autumn's embrace.", rarity: .legendary, theme: .fall, initialDaysToGrow: 6, baseValue: 300, assetName: "ancientshade_grown", iconName: "ancientshade_icon"),
        PlantBlueprint(id: "aurorafrost_l_wi", name: "Aurora Frost", description: "Reflects the colors of the aurora in its icy petals, a winter legend.", rarity: .legendary, theme: .winter, initialDaysToGrow: 6, baseValue: 300, assetName: "aurorafrost_grown", iconName: "aurorafrost_icon")
    ]

    /// Retrieves a specific plant blueprint by its unique ID.
    static func blueprint(withId id: String) -> PlantBlueprint? {
        return allPlantBlueprints.first(where: { $0.id == id })
    }

    /// Retrieves all plant blueprints of a specific rarity.
    static func blueprints(withRarity rarity: Rarity) -> [PlantBlueprint] {
        return allPlantBlueprints.filter { $0.rarity == rarity }
    }

    /// Helper function to get all plant blueprints of a specific theme and rarity.
    static func blueprints(theme: PlantTheme, rarity: Rarity) -> [PlantBlueprint] {
        return allPlantBlueprints.filter { $0.theme == theme && $0.rarity == rarity }
    }
}
