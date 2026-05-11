import SwiftUI
import SwiftData
import MapKit

// MARK: - Sheet destination

private enum PlaceSearchTarget: Identifiable {
    case home
    case addPlace
    case task(TodoItem)

    var id: String {
        switch self {
        case .home:        return "home"
        case .addPlace:    return "addPlace"
        case .task(let t): return "task_\(t.localTaskId)"
        }
    }
}

struct LocationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var geofenceManager = GeofenceManager.shared

    @Query(filter: #Predicate<TodoItem> { !$0.isDone }, sort: [SortDescriptor(\TodoItem.title)])
    private var incompleteTasks: [TodoItem]

    private var todayTasks: [TodoItem] {
        incompleteTasks
            .filter { $0.origin == .today }
            .sorted { a, b in
                let aPin = !a.taskLocations.isEmpty || a.locationCategory != nil
                let bPin = !b.taskLocations.isEmpty || b.locationCategory != nil
                if aPin != bPin { return aPin }
                return a.title < b.title
            }
    }

    @AppStorage("geofenceRemindersEnabled") private var remindersEnabled: Bool = true
    @AppStorage("userHomeAddress")          private var homeAddress: String = ""
    @AppStorage("userHomeName")             private var homeName: String = ""
    @AppStorage("userLocationAIContext")    private var aiContext: String = ""

    @State private var userPlaces: [UserDefinedPlace] = []
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var searchTarget: PlaceSearchTarget? = nil
    @State private var editingPlaceId: String? = nil

    var body: some View {
        List {
            enableSection
            mapSection
            tasksSection
            classifySection
            myPlacesSection
            aiContextSection
            permissionSection
        }
        .scrollContentBackground(.hidden)
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
        .listStyle(.insetGrouped)
        .navigationTitle("Location & Places")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { userPlaces = UserDefinedPlace.load() }
        .onChange(of: geofenceManager.activeGeofences.count) { _, _ in
            mapPosition = .automatic
        }
        .sheet(item: $searchTarget, content: placeSearchSheet)
    }

    // MARK: - Sections

    private var enableSection: some View {
        Section {
            Toggle(isOn: $remindersEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location-Based Reminders")
                        .foregroundColor(dynamicTextColor)
                    Text("Notify you when near relevant places")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
            }
            .tint(dynamicPrimaryColor)
            .listRowBackground(dynamicSecondaryBackgroundColor)
            .onChange(of: remindersEnabled) { _, enabled in
                if !enabled { geofenceManager.clearAllGeofences() }
            }
        }
    }

    private var mapSection: some View {
        Section {
            if geofenceManager.isClassifying {
                centeredStatus(icon: nil, text: "Finding nearby places…", isLoading: true)
            } else if geofenceManager.activeGeofences.isEmpty {
                centeredStatus(icon: "mappin.slash", text: "No geofences yet",
                               sub: "Tap \"Re-classify with AI\" to get started.")
            } else {
                Map(position: $mapPosition) {
                    ForEach(geofenceManager.activeGeofences) { fence in
                        MapCircle(center: fence.coordinate, radius: fence.radius)
                            .foregroundStyle(dynamicPrimaryColor.opacity(0.12))
                            .stroke(dynamicPrimaryColor, lineWidth: 1.5)
                        Annotation(fence.name, coordinate: fence.coordinate) {
                            VStack(spacing: 0) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(dynamicPrimaryColor)
                                    .background(Color.white.clipShape(Circle()).padding(2))
                            }
                        }
                    }
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(dynamicBackgroundColor)
            }
        } header: {
            Text("Active Geofences (\(geofenceManager.activeGeofences.count))")
                .foregroundColor(dynamicSecondaryTextColor)
        }
    }

    private var tasksSection: some View {
        Section {
            if todayTasks.isEmpty {
                Text("No tasks for today.")
                    .font(.subheadline)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .listRowBackground(dynamicSecondaryBackgroundColor)
            } else {
                ForEach(todayTasks) { task in
                    taskRow(task)
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                }
            }
        } header: {
            Text("Task Reminders")
                .foregroundColor(dynamicSecondaryTextColor)
        } footer: {
            Text("Each task can have multiple geofence locations. The AI auto-fills these; you can adjust them here.")
                .foregroundColor(dynamicSecondaryTextColor)
        }
    }

    private var classifySection: some View {
        Section {
            Button {
                guard !geofenceManager.isClassifying else { return }
                geofenceManager.clearAllGeofences()
                geofenceManager.classifyAndSetupGeofences(context: modelContext)
            } label: {
                HStack {
                    if geofenceManager.isClassifying {
                        ProgressView().tint(dynamicPrimaryColor)
                    } else {
                        Image(systemName: "sparkles").foregroundColor(dynamicPrimaryColor)
                    }
                    Text(geofenceManager.isClassifying ? "Classifying…" : "Re-classify with AI")
                        .foregroundColor(dynamicTextColor)
                }
            }
            .listRowBackground(dynamicSecondaryBackgroundColor)
        } footer: {
            Text("Runs automatically after your daily summary. Tap to refresh manually.")
                .foregroundColor(dynamicSecondaryTextColor)
        }
    }

    private var myPlacesSection: some View {
        Section {
            // Home
            if homeName.isEmpty && homeAddress.isEmpty {
                Button { searchTarget = .home } label: {
                    Label("Set Home Location", systemImage: "house.fill")
                        .foregroundColor(dynamicPrimaryColor)
                }
                .listRowBackground(dynamicSecondaryBackgroundColor)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "house.fill")
                        .foregroundColor(dynamicPrimaryColor)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(homeName.isEmpty ? homeAddress : homeName)
                            .foregroundColor(dynamicTextColor)
                        if !homeName.isEmpty, !homeAddress.isEmpty {
                            Text(homeAddress)
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                    }
                    Spacer()
                    Button { searchTarget = .home } label: {
                        Text("Change").font(.caption).foregroundColor(dynamicPrimaryColor)
                    }
                }
                .listRowBackground(dynamicSecondaryBackgroundColor)
            }

            // User-defined places
            ForEach($userPlaces) { $place in
                placeRow($place)
            }
            .onDelete { indices in
                userPlaces.remove(atOffsets: indices)
                UserDefinedPlace.save(userPlaces)
                geofenceManager.refreshGeofencesFromCurrentCategories(context: modelContext)
            }

            Button { searchTarget = .addPlace } label: {
                Label("Add a Place", systemImage: "plus.circle.fill")
                    .foregroundColor(dynamicPrimaryColor)
            }
            .listRowBackground(dynamicSecondaryBackgroundColor)
        } header: {
            Text("My Places")
                .foregroundColor(dynamicSecondaryTextColor)
        } footer: {
            Text("Named places the AI can assign tasks to. Tap the pencil to add a description.")
                .foregroundColor(dynamicSecondaryTextColor)
        }
    }

    private var aiContextSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if aiContext.isEmpty {
                    Text("e.g. I prefer Trader Joe's. I study best at McHenry Library.")
                        .font(.body)
                        .foregroundColor(dynamicSecondaryTextColor.opacity(0.5))
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $aiContext)
                    .frame(minHeight: 72)
                    .foregroundColor(dynamicTextColor)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .listRowBackground(dynamicSecondaryBackgroundColor)
        } header: {
            Text("Additional AI Context")
                .foregroundColor(dynamicSecondaryTextColor)
        } footer: {
            Text("Freeform hints the AI uses during classification.")
                .foregroundColor(dynamicSecondaryTextColor)
        }
    }

    private var permissionSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").foregroundColor(dynamicSecondaryTextColor).frame(width: 20)
                Text("Geofence reminders require \"Always\" location access. Go to Settings → YourDay → Location.")
                    .font(.caption).foregroundColor(dynamicSecondaryTextColor)
            }
            .listRowBackground(dynamicSecondaryBackgroundColor)
        }
    }

    // MARK: - Task Row

    private func taskRow(_ task: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: task.taskLocations.isEmpty ? categoryIcon(task.locationCategory) : "mappin.and.ellipse")
                    .foregroundColor(task.taskLocations.isEmpty && task.locationCategory == nil
                                     ? dynamicSecondaryTextColor.opacity(0.3)
                                     : dynamicPrimaryColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.body).foregroundColor(dynamicTextColor).lineLimit(1)
                    if task.taskLocations.isEmpty && task.locationCategory == nil {
                        Text("Not classified")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor.opacity(0.5))
                            .italic()
                    } else if task.taskLocations.isEmpty, let cat = task.locationCategory {
                        Text(categoryLabel(cat))
                            .font(.caption).foregroundColor(dynamicSecondaryTextColor)
                    }
                }

                Spacer()

                Menu {
                    Button { searchTarget = .task(task) } label: {
                        Label("Add Specific Place…", systemImage: "mappin.and.ellipse")
                    }
                    Divider()
                    ForEach(allLocationCategories, id: \.self) { cat in
                        Button {
                            geofenceManager.addCategoryLocations(for: task, category: cat, context: modelContext)
                        } label: {
                            Label("Add \(categoryLabel(cat)) places", systemImage: categoryIcon(cat))
                        }
                    }
                    if !task.taskLocations.isEmpty {
                        Divider()
                        Button(role: .destructive) {
                            task.taskLocations = []
                            task.locationCategory = nil
                            try? modelContext.save()
                            geofenceManager.refreshGeofencesFromCurrentCategories(context: modelContext)
                        } label: {
                            Label("Clear All Locations", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(dynamicPrimaryColor)
                        .font(.title3)
                }
            }

            // Location chips
            if !task.taskLocations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(task.taskLocations) { loc in
                            HStack(spacing: 3) {
                                Text(loc.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Button {
                                    task.taskLocations.removeAll { $0.id == loc.id }
                                    try? modelContext.save()
                                    geofenceManager.refreshGeofencesFromCurrentCategories(context: modelContext)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(dynamicPrimaryColor.opacity(0.12))
                            .foregroundColor(dynamicPrimaryColor)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.leading, 30)
                }
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Place Row

    private func placeRow(_ place: Binding<UserDefinedPlace>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(dynamicPrimaryColor).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.wrappedValue.name)
                        .font(.body).foregroundColor(dynamicTextColor)
                    if !place.wrappedValue.address.isEmpty {
                        Text(place.wrappedValue.address)
                            .font(.caption).foregroundColor(dynamicSecondaryTextColor)
                    }
                }
                Spacer()
                Button {
                    withAnimation {
                        editingPlaceId = editingPlaceId == place.id ? nil : place.id
                    }
                } label: {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(dynamicSecondaryTextColor)
                }
            }
            if editingPlaceId == place.id {
                HStack {
                    Image(systemName: "text.quote")
                        .foregroundColor(dynamicSecondaryTextColor.opacity(0.5)).frame(width: 22)
                    TextField("Description (e.g. my study spot)", text: place.description)
                        .font(.caption).foregroundColor(dynamicTextColor)
                        .onSubmit {
                            UserDefinedPlace.save(userPlaces)
                            editingPlaceId = nil
                        }
                }
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(dynamicSecondaryBackgroundColor)
    }

    // MARK: - Place Search Sheet

    @ViewBuilder
    private func placeSearchSheet(_ target: PlaceSearchTarget) -> some View {
        switch target {
        case .home:
            PlaceSearchView(title: "Set Home Location") { item in
                homeName = item.name ?? ""
                homeAddress = item.placemark.shortAddress ?? ""
                UserDefaults.standard.set(item.placemark.coordinate.latitude, forKey: "userHomeLat")
                UserDefaults.standard.set(item.placemark.coordinate.longitude, forKey: "userHomeLon")
            }
        case .addPlace:
            PlaceSearchView(title: "Add a Place") { item in
                let place = UserDefinedPlace(
                    name: item.name ?? "Unknown",
                    address: item.placemark.shortAddress ?? "",
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
                userPlaces.append(place)
                UserDefinedPlace.save(userPlaces)
                geofenceManager.refreshGeofencesFromCurrentCategories(context: modelContext)
            }
        case .task(let task):
            PlaceSearchView(title: "Add Location for Task") { item in
                let loc = TaskLocation(
                    name: item.name ?? "Unknown",
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
                task.taskLocations.append(loc)
                try? modelContext.save()
                geofenceManager.refreshGeofencesFromCurrentCategories(context: modelContext)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func centeredStatus(icon: String?, text: String, sub: String? = nil, isLoading: Bool = false) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(dynamicPrimaryColor)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 32))
                        .foregroundColor(dynamicSecondaryTextColor.opacity(0.5))
                }
                Text(text).font(.subheadline).foregroundColor(dynamicSecondaryTextColor)
                if let sub {
                    Text(sub).font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 28)
            Spacer()
        }
        .listRowBackground(dynamicSecondaryBackgroundColor)
    }

    private let allLocationCategories = [
        "library", "grocery", "restaurant", "gym", "cafe", "pharmacy", "park"
    ]

    private func categoryLabel(_ cat: String?) -> String {
        switch cat {
        case "home":       return "Home"
        case "library":    return "Library / Study"
        case "grocery":    return "Grocery Store"
        case "restaurant": return "Restaurant"
        case "gym":        return "Gym"
        case "cafe":       return "Café"
        case "pharmacy":   return "Pharmacy"
        case "park":       return "Park"
        case "anywhere":   return "Anywhere (Digital)"
        default:           return "Not classified"
        }
    }

    private func categoryIcon(_ cat: String?) -> String {
        switch cat {
        case "home":       return "house.fill"
        case "library":    return "books.vertical.fill"
        case "grocery":    return "cart.fill"
        case "restaurant": return "fork.knife"
        case "gym":        return "dumbbell.fill"
        case "cafe":       return "cup.and.saucer.fill"
        case "pharmacy":   return "cross.vial.fill"
        case "park":       return "leaf.fill"
        case "anywhere":   return "laptopcomputer"
        default:           return "questionmark.circle"
        }
    }
}

// MARK: - Map annotation pointer

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}
