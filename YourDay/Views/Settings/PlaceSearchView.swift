import SwiftUI
import MapKit

struct PlaceSearchView: View {
    var title: String = "Search Places"
    let onSelect: (MKMapItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(dynamicSecondaryTextColor.opacity(0.4))
                            Text("Type to search for a place")
                                .font(.subheadline)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                        .padding(.vertical, 32)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if results.isEmpty && !isSearching {
                    Text("No results found")
                        .foregroundColor(dynamicSecondaryTextColor)
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                } else {
                    ForEach(results, id: \.self) { item in
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name ?? "Unknown Place")
                                    .foregroundColor(dynamicTextColor)
                                    .font(.body)
                                if let addr = item.placemark.shortAddress {
                                    Text(addr)
                                        .font(.caption)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a place")
            .onChange(of: query) { _, new in performSearch(new) }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(dynamicPrimaryColor)
                }
            }
        }
    }

    private func performSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { results = []; return }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        Task {
            if let response = try? await MKLocalSearch(request: request).start() {
                results = response.mapItems
            } else {
                results = []
            }
            isSearching = false
        }
    }
}

extension MKPlacemark {
    var shortAddress: String? {
        [subThoroughfare, thoroughfare, locality, administrativeArea]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nonEmpty
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
