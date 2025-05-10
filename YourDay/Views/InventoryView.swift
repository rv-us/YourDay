//
//  InventoryView.swift
//  YourDay
//
//  Created by Rachit Verma on 5/10/25.
//


import SwiftUI
import SwiftData

// Enum for sorting/filtering options in the inventory
enum InventorySortOption: String, CaseIterable, Identifiable {
    case byDefault = "Default"
    case byTheme = "Theme"
    case byRarity = "Rarity"
    var id: String { self.rawValue }
}

struct InventoryView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<PlayerStats> { _ in true }) private var playerStatsList: [PlayerStats]
    private var playerStats: PlayerStats { playerStatsList.first ?? PlayerStats() }

    @State private var selectedSortOption: InventorySortOption = .byDefault
    
    @State private var plantForConversionSheetItem: PlantBlueprint? = nil
    @State private var quantityToConvertToFertilizer: Int = 10
    @State private var conversionResultMessage: String? = nil

    // MARK: - Planting Mode Properties
    let isPlantingMode: Bool
    let onPlantSelected: ((String) -> Void)? // Closure to call when a plant is selected for planting

    private var unplacedPlantItems: [(blueprint: PlantBlueprint, quantity: Int)] {
        var items: [(blueprint: PlantBlueprint, quantity: Int)] = []
        // Filter out plants with zero quantity before displaying
        for (blueprintID, quantity) in playerStats.unplacedPlantsInventory where quantity > 0 {
            if let blueprint = PlantLibrary.blueprint(withId: blueprintID) {
                items.append((blueprint: blueprint, quantity: quantity))
            }
        }
        return items
    }

    private var sortedAndGroupedItems: [GroupedInventorySection] {
        let allItems = unplacedPlantItems
        switch selectedSortOption {
        case .byDefault:
            let sortedItems = allItems.sorted { $0.blueprint.name < $1.blueprint.name }
            if sortedItems.isEmpty { return [] }
            return [GroupedInventorySection(title: "All Plants", items: sortedItems)]
        case .byTheme:
            var sections: [GroupedInventorySection] = []
            for themeCase in PlantTheme.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
                let itemsInTheme = allItems.filter { $0.blueprint.theme == themeCase }
                if !itemsInTheme.isEmpty {
                    sections.append(GroupedInventorySection(title: themeCase.rawValue, items: itemsInTheme.sorted { $0.blueprint.name < $1.blueprint.name }))
                }
            }
            return sections.sorted { $0.title < $1.title }
        case .byRarity:
            var sections: [GroupedInventorySection] = []
            for rarityCase in Rarity.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
                let itemsInRarity = allItems.filter { $0.blueprint.rarity == rarityCase }
                if !itemsInRarity.isEmpty {
                    sections.append(GroupedInventorySection(title: rarityCase.rawValue, items: itemsInRarity.sorted { $0.blueprint.name < $1.blueprint.name }))
                }
            }
            return sections // Rarity enum typically has a natural order, or sort sections by title if needed.
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                if !isPlantingMode {
                    Text("Fertilizer: \(playerStats.fertilizerCount)")
                        .font(.headline)
                        .padding(.top)
                    
                    Text("Convert 10 of a plant type into 1 fertilizer.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 5)
                } else {
                    Text("Select a Plant to Place")
                        .font(.headline)
                        .padding(.top)
                }

                Picker("Sort by", selection: $selectedSortOption) {
                    ForEach(InventorySortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding([.horizontal, .bottom])

                if unplacedPlantItems.isEmpty {
                    Spacer()
                    Text(isPlantingMode ? "No plants available to plant." : "Your inventory is empty.")
                        .font(.title2).foregroundColor(.gray)
                    if !isPlantingMode {
                        Text("Get new plants from the Shop!")
                            .font(.headline).foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(sortedAndGroupedItems) { section in
                            Section(header: Text(section.title).font(.headline)) {
                                ForEach(section.items, id: \.blueprint.id) { item in
                                    inventoryRow(for: item.blueprint, quantity: item.quantity)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(isPlantingMode ? "Choose Plant" : "Inventory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $plantForConversionSheetItem, onDismiss: {
                conversionResultMessage = nil
            }) { plantItem in
                if let maxQuantity = playerStats.unplacedPlantsInventory[plantItem.id] {
                    FertilizerConversionView(
                        plantBlueprint: plantItem,
                        maxConvertibleQuantity: maxQuantity,
                        currentQuantityToConvert: $quantityToConvertToFertilizer,
                        onConfirm: { quantity in
                            performFertilizerConversion(blueprintID: plantItem.id, quantity: quantity)
                        },
                        onCancel: {
                            // Sheet will dismiss automatically
                        }
                    )
                } else {
                    Text("Error: Could not load plant details for conversion.")
                }
            }
            .alert("Conversion Result", isPresented: .constant(conversionResultMessage != nil), actions: {
                Button("OK") { conversionResultMessage = nil }
            }, message: {
                Text(conversionResultMessage ?? "")
            })
        }
    }

    @ViewBuilder
    private func inventoryRow(for blueprint: PlantBlueprint, quantity: Int) -> some View {
        // Row content
        let rowContent = HStack {
            blueprint.iconVisual
                .frame(width: 40, height: 40)
                .background(Color(UIColor.systemGray5)).cornerRadius(6)
            
            VStack(alignment: .leading) {
                Text(blueprint.name).font(.headline)
                Text("Rarity: \(blueprint.rarity.rawValue)").font(.caption)
                Text("Theme: \(blueprint.theme.rawValue)").font(.caption)
            }
            Spacer()
            Text("x\(quantity)").font(.title3).fontWeight(.medium)

            if isPlantingMode {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
            } else if quantity >= 10 {
                Button {
                    let currentMax = playerStats.unplacedPlantsInventory[blueprint.id] ?? 0
                    let maxFertilizerUnits = currentMax / 10
                    if maxFertilizerUnits > 0 {
                        quantityToConvertToFertilizer = 10
                    } else {
                        return
                    }
                    plantForConversionSheetItem = blueprint
                } label: {
                    Image(systemName: "arrow.2.squarepath")
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }

        if isPlantingMode {
            // If in planting mode, wrap the row content in a Button for reliable tap action
            Button(action: {
                if quantity > 0 {
                    onPlantSelected?(blueprint.id)
                }
            }) {
                rowContent // The HStack defined above
            }
            .buttonStyle(.plain) // Use .plain to make it look like a normal list row
            .disabled(quantity <= 0) // Disable button if no quantity to plant
        } else {
            // If not in planting mode, use the HStack directly (conversion button has its own tap)
            rowContent
            // Add .onTapGesture here if you need general tap functionality for non-planting mode
            // .contentShape(Rectangle())
            // .onTapGesture { /* Action for non-planting mode tap */ }
        }
    }
    
    private func performFertilizerConversion(blueprintID: String, quantity: Int) {
        guard let mutablePlayerStats = playerStatsList.first else {
            conversionResultMessage = "Error: Player data not found."
            return
        }
        let result = mutablePlayerStats.convertToFertilizer(blueprintID: blueprintID, quantityToConvert: quantity)
        conversionResultMessage = result.message
    }
}

// MARK: - Subviews (FertilizerConversionView, GroupedInventorySection)

struct FertilizerConversionView: View {
    @Environment(\.dismiss) var dismiss
    let plantBlueprint: PlantBlueprint
    let maxConvertibleQuantity: Int
    
    @Binding var currentQuantityToConvert: Int

    var fertilizerToGain: Int {
        currentQuantityToConvert / 10
    }
    
    var maxFertilizerUnitsPossible: Int {
        maxConvertibleQuantity / 10
    }

    let onConfirm: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Convert \(plantBlueprint.name)")
                    .font(.largeTitle)
                
                plantBlueprint.iconVisual
                    .frame(width: 80, height: 80)
                    .background(Color(UIColor.systemGray4))
                    .cornerRadius(10)

                Text("You have: \(maxConvertibleQuantity)")
                Text("Convert 10 plants for 1 fertilizer.")

                HStack {
                    Text("Plants to Convert:")
                    Spacer()
                    Text("\(currentQuantityToConvert)")
                }
                
                Stepper("Quantity", value: $currentQuantityToConvert,
                        in: (maxFertilizerUnitsPossible > 0 ? 10 : 0)...(maxFertilizerUnitsPossible * 10),
                        step: 10)
                    .labelsHidden()
                    .disabled(maxFertilizerUnitsPossible == 0)


                Button("Max (\(maxFertilizerUnitsPossible * 10) plants for \(maxFertilizerUnitsPossible) fertilizer)") {
                    currentQuantityToConvert = maxFertilizerUnitsPossible * 10
                }
                .disabled(maxFertilizerUnitsPossible == 0)

                Text("You will gain: \(fertilizerToGain) Fertilizer")
                    .font(.headline)
                
                HStack(spacing: 20) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .padding().frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.3)).foregroundColor(.primary).cornerRadius(10)

                    Button("Confirm") {
                        onConfirm(currentQuantityToConvert)
                        dismiss()
                    }
                    .padding().frame(maxWidth: .infinity)
                    .background(fertilizerToGain > 0 ? Color.green : Color.gray)
                    .foregroundColor(.white).cornerRadius(10)
                    .disabled(fertilizerToGain <= 0)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Make Fertilizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct GroupedInventorySection: Identifiable {
    let id = UUID()
    let title: String
    let items: [(blueprint: PlantBlueprint, quantity: Int)]
}
