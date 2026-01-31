import SwiftUI
import SwiftData

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

    let isPlantingMode: Bool
    let onPlantSelected: ((String) -> Void)?

    private var unplacedPlantItems: [(blueprint: PlantBlueprint, quantity: Int)] {
        var items: [(blueprint: PlantBlueprint, quantity: Int)] = []
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
            return sections
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !isPlantingMode {
                    Text("Fertilizer: \(playerStats.fertilizerCount)")
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                        .padding(.top)
                    
                    Text("Convert 10 of a plant type into 1 fertilizer.")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .padding(.bottom, 5)
                } else {
                    Text("Select a Plant to Place")
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                        .padding(.top)
                }

                Picker("Sort by", selection: $selectedSortOption) {
                    ForEach(InventorySortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding([.horizontal, .bottom])
                .colorMultiply(dynamicPrimaryColor)


                if unplacedPlantItems.isEmpty {
                    Spacer()
                    Text(isPlantingMode ? "No plants available to plant." : "Your inventory is empty.")
                        .font(.title2).foregroundColor(dynamicSecondaryTextColor)
                    if !isPlantingMode {
                        Text("Get new plants from the Shop!")
                            .font(.headline).foregroundColor(dynamicSecondaryTextColor)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(sortedAndGroupedItems) { section in
                            Section(header:
                                Text(section.title)
                                    .font(.headline)
                                    .foregroundColor(dynamicTextColor)
                                    .padding(.vertical, 4)
                            ) {
                                ForEach(section.items, id: \.blueprint.id) { item in
                                    inventoryRow(for: item.blueprint, quantity: item.quantity)
                                }
                            }
                            .listRowBackground(dynamicSecondaryBackgroundColor.opacity(0.5))
                        }
                    }
                    .listStyle(PlainListStyle())
                    .background(dynamicBackgroundColor)
                }
            }
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .navigationTitle(isPlantingMode ? "Choose Plant" : "Inventory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal){
                    Text(isPlantingMode ? "Choose Plant" : "Inventory")
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundColor(dynamicPrimaryColor)
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
                        }
                    )
                } else {
                    Text("Error: Could not load plant details for conversion.")
                        .foregroundColor(dynamicDestructiveColor)
                }
            }
            .alert("Conversion Result", isPresented: .constant(conversionResultMessage != nil), actions: {
                Button("OK") { conversionResultMessage = nil }
                    .foregroundColor(dynamicSecondaryColor)
            }, message: {
                Text(conversionResultMessage ?? "")
            })
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func inventoryRow(for blueprint: PlantBlueprint, quantity: Int) -> some View {
        let rowContent = HStack {
            blueprint.iconVisual
                .frame(width: 40, height: 40)
                .background(dynamicPrimaryColor.opacity(0.1)).cornerRadius(6)
            
            VStack(alignment: .leading) {
                Text(blueprint.name).font(.headline).foregroundColor(dynamicTextColor)
                Text("Rarity: \(blueprint.rarity.rawValue)").font(.caption).foregroundColor(dynamicSecondaryTextColor)
                Text("Theme: \(blueprint.theme.rawValue)").font(.caption).foregroundColor(dynamicSecondaryTextColor)
            }
            Spacer()
            Text("x\(quantity)").font(.title3).fontWeight(.medium).foregroundColor(dynamicTextColor)

            if isPlantingMode {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(dynamicPrimaryColor)
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
                        .foregroundColor(dynamicPrimaryColor)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.vertical, 4)

        if isPlantingMode {
            Button(action: {
                if quantity > 0 {
                    onPlantSelected?(blueprint.id)
                }
            }) {
                rowContent
            }
            .buttonStyle(.plain)
            .disabled(quantity <= 0)
        } else {
            rowContent
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
                    .foregroundColor(dynamicTextColor)
                
                plantBlueprint.iconVisual
                    .frame(width: 80, height: 80)
                    .background(dynamicPrimaryColor.opacity(0.2))
                    .cornerRadius(10)

                Text("You have: \(maxConvertibleQuantity)")
                    .foregroundColor(dynamicSecondaryTextColor)
                Text("Convert 10 plants for 1 fertilizer.")
                    .foregroundColor(dynamicSecondaryTextColor)

                HStack {
                    Text("Plants to Convert:")
                        .foregroundColor(dynamicTextColor)
                    Spacer()
                    Text("\(currentQuantityToConvert)")
                        .foregroundColor(dynamicTextColor)
                }
                
                Stepper("Quantity", value: $currentQuantityToConvert,
                        in: (maxFertilizerUnitsPossible > 0 ? 10 : 0)...(maxFertilizerUnitsPossible * 10),
                        step: 10)
                    .labelsHidden()
                    .colorMultiply(dynamicPrimaryColor)
                    .disabled(maxFertilizerUnitsPossible == 0)


                Button("Max (\(maxFertilizerUnitsPossible * 10) plants for \(maxFertilizerUnitsPossible) fertilizer)") {
                    currentQuantityToConvert = maxFertilizerUnitsPossible * 10
                }
                .foregroundColor(dynamicPrimaryColor)
                .disabled(maxFertilizerUnitsPossible == 0)

                Text("You will gain: \(fertilizerToGain) Fertilizer")
                    .font(.headline)
                    .foregroundColor(dynamicTextColor)
                
                HStack(spacing: 20) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .padding().frame(maxWidth: .infinity)
                    .background(dynamicSecondaryTextColor.opacity(0.3)).foregroundColor(dynamicTextColor).cornerRadius(10)

                    Button("Confirm") {
                        onConfirm(currentQuantityToConvert)
                        dismiss()
                    }
                    .padding().frame(maxWidth: .infinity)
                    .background(fertilizerToGain > 0 ? dynamicSecondaryColor : dynamicSecondaryTextColor.opacity(0.5))
                    .foregroundColor(.white).cornerRadius(10)
                    .disabled(fertilizerToGain <= 0)
                }
                Spacer()
            }
            .padding()
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .navigationTitle("Make Fertilizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                 ToolbarItem(placement: .principal){
                    Text("Make Fertilizer")
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        onCancel()
                        dismiss()
                    }
                    .foregroundColor(dynamicPrimaryColor)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct GroupedInventorySection: Identifiable {
    let id = UUID()
    let title: String
    let items: [(blueprint: PlantBlueprint, quantity: Int)]
}
