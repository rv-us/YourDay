import Foundation
import CoreLocation
import MapKit
import FirebaseVertexAI
import SwiftData

struct GeofenceInfo: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let radius: CLLocationDistance
    let tasks: [String]
    let category: String
}

/// Codable mirror of GeofenceInfo stored in UserDefaults so the mapping
/// survives app termination. When the OS relaunches the app for a geofence
/// event the regions are still registered in the OS; we just need to
/// restore the id→(name, tasks) lookup so didEnterRegion can fire correctly.
private struct PersistedGeofence: Codable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let tasks: [String]
    let category: String
}

private let persistenceKey = "activeGeofencesData"

final class GeofenceManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = GeofenceManager()

    private let locationManager = CLLocationManager()
    @Published var activeGeofences: [GeofenceInfo] = []
    @Published var isClassifying = false

    private override init() {
        super.init()
        locationManager.delegate = self
        restorePersistedGeofences()
    }

    // MARK: - Persistence

    private func restorePersistedGeofences() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let persisted = try? JSONDecoder().decode([PersistedGeofence].self, from: data) else { return }
        activeGeofences = persisted.map { p in
            GeofenceInfo(
                id: p.id,
                name: p.name,
                coordinate: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude),
                radius: 200,
                tasks: p.tasks,
                category: p.category
            )
        }
        print("GeofenceManager: Restored \(activeGeofences.count) geofence(s) from persistence.")
    }

    private func persistGeofences() {
        let toSave = activeGeofences.map {
            PersistedGeofence(id: $0.id, name: $0.name,
                              latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                              tasks: $0.tasks, category: $0.category)
        }
        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    // MARK: - Public API

    /// True only when both location-reminder toggles are on: the one in
    /// Location & Places settings ("geofenceRemindersEnabled") and the one in
    /// Notification settings (NotificationManager.locationRemindersEnabledKey).
    var locationRemindersEnabled: Bool {
        let defaults = UserDefaults.standard
        let geofenceFlag = defaults.object(forKey: "geofenceRemindersEnabled") as? Bool ?? true
        let notificationFlag = defaults.object(forKey: NotificationManager.locationRemindersEnabledKey) as? Bool ?? true
        return geofenceFlag && notificationFlag
    }

    /// Runs LLM classification, resolves locations to coordinates, stores on tasks, builds geofences.
    func classifyAndSetupGeofences(context: ModelContext) {
        guard locationRemindersEnabled else { return }
        let tasks = fetchTodayTasks(context)
        guard !tasks.isEmpty else { return }
        Task { @MainActor in await classifyTasks(tasks, context: context) }
    }

    /// Rebuilds geofences from the already-resolved `taskLocations` on each task (no LLM call, no MKLocalSearch).
    func refreshGeofencesFromCurrentCategories(context: ModelContext) {
        let tasks = fetchTodayTasks(context)
        Task { @MainActor in
            clearAllGeofences()
            isClassifying = true
            defer { isClassifying = false }
            buildGeofences(from: tasks)
        }
    }

    /// Searches MapKit for `category` near the current location, appends up to `limit` results to `task.taskLocations`.
    func addCategoryLocations(for task: TodoItem, category: String, limit: Int = 2, context: ModelContext) {
        Task { @MainActor in
            isClassifying = true
            defer { isClassifying = false }
            let center = locationManager.location?.coordinate
                ?? CLLocationCoordinate2D(latitude: 37.3382, longitude: -121.8863)
            let pois = await searchPOIs(category: category, near: center, limit: limit)
            let newLocs = pois.map { TaskLocation(name: $0.name, latitude: $0.coord.latitude, longitude: $0.coord.longitude) }
            task.taskLocations.append(contentsOf: newLocs)
            if task.locationCategory == nil { task.locationCategory = category }
            try? context.save()
            // Clear first: buildGeofences assigns identifiers from index 0, so
            // building on top of live regions creates duplicate ids in
            // activeGeofences and stale name/task lookups in didEnterRegion.
            clearAllGeofences()
            buildGeofences(from: fetchTodayTasks(context))
        }
    }

    func clearAllGeofences() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        activeGeofences.removeAll()
        UserDefaults.standard.removeObject(forKey: persistenceKey)
        print("GeofenceManager: Cleared all geofences.")
    }

    // MARK: - LLM Classification

    @MainActor
    private func classifyTasks(_ tasks: [TodoItem], context: ModelContext) async {
        isClassifying = true
        defer { isClassifying = false }

        let userPlaces = UserDefinedPlace.load()
        let homeAddress = UserDefaults.standard.string(forKey: "userHomeAddress") ?? ""
        let homeName = UserDefaults.standard.string(forKey: "userHomeName") ?? ""
        let aiContext = UserDefaults.standard.string(forKey: "userLocationAIContext") ?? ""

        let taskLines = tasks.map { "\($0.localTaskId): \($0.title)" }.joined(separator: "\n")

        var placesBlock = ""
        if !userPlaces.isEmpty {
            let lines = userPlaces.map { p in
                "- id:\"\(p.id)\" name:\"\(p.name)\"\(p.description.isEmpty ? "" : " desc:\"\(p.description)\"")"
            }.joined(separator: "\n")
            placesBlock = "\nUser's named places:\n\(lines)\n"
        }

        let homeBlock = (!homeName.isEmpty || !homeAddress.isEmpty)
            ? "\nHome: \(homeName.isEmpty ? homeAddress : "\(homeName) – \(homeAddress)")\n"
            : ""

        let prompt = """
        You are a task location classifier for a productivity app.
        Classify each task by WHERE it is best physically done.
        A task may have multiple relevant locations (up to 3).
        \(aiContext.isEmpty ? "" : "User context (prioritise this when classifying): \(aiContext)")
        \(homeBlock)\(placesBlock)
        Tasks (id: title):
        \(taskLines)

        Reply ONLY with valid JSON (no markdown, no extra text):
        {
          "classifications": [
            {
              "id": "TASK_ID",
              "primaryCategory": "CATEGORY",
              "locations": [
                {"category": "CATEGORY"},
                {"placeId": "PLACE_ID"}
              ]
            }
          ]
        }

        Valid primaryCategory / category values:
          home, library, grocery, restaurant, gym, cafe, pharmacy, park, anywhere
        Rules:
        - Prioritise the user context and named places above generic category guesses
        - "anywhere": digital tasks (email, calls, writing, coding) — skip locations array
        - "home": chores, cooking, household — skip locations array
        - Use placeId when a user named place fits the task (preferred over generic category)
        - Use category when no named place fits but a place type does
        - A task can have both a placeId and a category entry if applicable
        - Maximum 3 entries in locations per task
        """

        do {
            let vertex = VertexAI.vertexAI()
            let model = vertex.generativeModel(modelName: "gemini-2.5-flash")
            let response = try await model.generateContent(prompt)

            guard let text = response.text else {
                print("GeofenceManager: Empty response from LLM.")
                return
            }

            print("GeofenceManager: Raw LLM response:\n\(text)")

            guard let data = extractJSON(from: text),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let classifications = json["classifications"] as? [[String: Any]] else {
                print("GeofenceManager: Could not parse classification response.")
                return
            }

            let center = locationManager.location?.coordinate
                ?? CLLocationCoordinate2D(latitude: 37.3382, longitude: -121.8863)

            // Collect (task, category) pairs for batch MKLocalSearch.
            var categoryBatch: [(task: TodoItem, category: String)] = []

            for entry in classifications {
                guard let id = entry["id"] as? String,
                      let task = tasks.first(where: { $0.localTaskId == id }) else { continue }

                if let primary = entry["primaryCategory"] as? String {
                    task.locationCategory = primary
                }

                task.taskLocations = []  // reset before filling

                let locationEntries = entry["locations"] as? [[String: Any]] ?? []
                for locEntry in locationEntries {
                    if let placeId = locEntry["placeId"] as? String,
                       let place = userPlaces.first(where: { $0.id == placeId }) {
                        task.taskLocations.append(TaskLocation(
                            name: place.name,
                            latitude: place.latitude,
                            longitude: place.longitude
                        ))
                    } else if let cat = locEntry["category"] as? String,
                              cat != "home", cat != "anywhere" {
                        categoryBatch.append((task: task, category: cat))
                    }
                }
            }

            // Resolve category entries via MKLocalSearch.
            for (task, category) in categoryBatch {
                let pois = await searchPOIs(category: category, near: center, limit: 2)
                let locs = pois.map { TaskLocation(name: $0.name, latitude: $0.coord.latitude, longitude: $0.coord.longitude) }
                task.taskLocations.append(contentsOf: locs)
            }

            try? context.save()
            print("GeofenceManager: Classified \(classifications.count) tasks, \(classifications.map { ($0["locations"] as? [[String: Any]])?.count ?? 0 }.reduce(0, +)) total location entries.")

            clearAllGeofences()
            buildGeofences(from: fetchTodayTasks(context))
        } catch {
            print("GeofenceManager: Classification error – \(error)")
        }
    }

    // MARK: - Geofence Building

    /// Groups all TaskLocations across tasks by coordinate, then registers one CLCircularRegion per unique spot.
    @MainActor
    private func buildGeofences(from tasks: [TodoItem]) {
        // key = "lat,lon" rounded to 4dp (~11 m); value = (display name, coordinate, all task titles there)
        var groups: [String: (name: String, coord: CLLocationCoordinate2D, titles: [String])] = [:]
        for task in tasks {
            for loc in task.taskLocations {
                let key = String(format: "%.4f,%.4f", loc.latitude, loc.longitude)
                if groups[key] != nil {
                    if !groups[key]!.titles.contains(task.title) {
                        groups[key]!.titles.append(task.title)
                    }
                } else {
                    let coord = CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
                    groups[key] = (name: loc.name, coord: coord, titles: [task.title])
                }
            }
        }

        var count = 0
        for (_, group) in groups {
            guard count < 20 else { break }
            let id = "geofence_\(count)"
            activeGeofences.append(GeofenceInfo(
                id: id, name: group.name, coordinate: group.coord,
                radius: 200, tasks: group.titles, category: "custom"
            ))
            count += 1
        }

        // Persist before registering: if permission hasn't been granted yet the
        // fences survive, and registerGeofencesWithOS() runs again from
        // locationManagerDidChangeAuthorization once the user grants access.
        persistGeofences()
        registerGeofencesWithOS()
    }

    /// Registers `activeGeofences` with Core Location. Kept separate from the
    /// computation so fences built before authorization can be registered later.
    private func registerGeofencesWithOS() {
        guard !activeGeofences.isEmpty else { return }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            // Fences stay pending; the authorization callback registers them.
            locationManager.requestAlwaysAuthorization()
            print("GeofenceManager: Requested location permission — will register \(activeGeofences.count) fence(s) once granted.")
            return
        case .authorizedAlways:
            break
        case .authorizedWhenInUse:
            print("GeofenceManager: Only When-In-Use permission — region monitoring needs Always; background events may not be delivered.")
        default:
            print("GeofenceManager: Location permission denied/restricted — cannot register geofences.")
            return
        }

        for fence in activeGeofences {
            let clRegion = CLCircularRegion(center: fence.coordinate, radius: fence.radius, identifier: fence.id)
            clRegion.notifyOnEntry = true
            clRegion.notifyOnExit = false
            locationManager.startMonitoring(for: clRegion)
            // Entry events only fire on boundary crossings, so ask whether the
            // user is already standing inside the fence right now.
            locationManager.requestState(for: clRegion)
            print("GeofenceManager: Monitoring \"\(fence.name)\" for [\(fence.tasks.joined(separator: ", "))]")
        }
    }

    /// Rate-limits geofence notifications to one per location per calendar day.
    /// Rebuilds re-register regions and re-check state (daily classification,
    /// manual edits), so without this the user would be re-notified every time.
    private func markNotifiedToday(for fence: GeofenceInfo) -> Bool {
        let key = "geofenceNotifiedDates"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        var dict = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
        if dict[fence.name] == today { return false }
        dict = dict.filter { $0.value == today }  // prune stale days
        dict[fence.name] = today
        UserDefaults.standard.set(dict, forKey: key)
        return true
    }

    // MARK: - MapKit POI Search

    private func poiCategories(for category: String) -> [MKPointOfInterestCategory] {
        switch category {
        case "library":    return [.library, .university, .school]
        case "grocery":    return [.foodMarket, .store]
        case "restaurant": return [.restaurant, .foodMarket]
        case "gym":        return [.fitnessCenter]
        case "cafe":       return [.cafe]
        case "pharmacy":   return [.pharmacy]
        case "park":       return [.park, .nationalPark]
        default:           return []
        }
    }

    func searchPOIs(
        category: String,
        near center: CLLocationCoordinate2D,
        limit: Int
    ) async -> [(name: String, coord: CLLocationCoordinate2D)] {
        let mkCategories = poiCategories(for: category)
        guard !mkCategories.isEmpty else { return [] }

        let region = MKCoordinateRegion(center: center, latitudinalMeters: 10_000, longitudinalMeters: 10_000)
        var results: [(name: String, coord: CLLocationCoordinate2D)] = []

        for mkCat in mkCategories {
            guard results.count < limit else { break }
            let request = MKLocalSearch.Request()
            request.region = region
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [mkCat])
            if let response = try? await MKLocalSearch(request: request).start() {
                for item in response.mapItems.prefix(limit - results.count) {
                    results.append((name: item.name ?? category.capitalized, coord: item.placemark.coordinate))
                }
            }
        }

        return results
    }

    // MARK: - Helpers

    private func fetchTodayTasks(_ context: ModelContext) -> [TodoItem] {
        let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate<TodoItem> { !$0.isDone })
        return (try? context.fetch(descriptor))?.filter { $0.origin == .today } ?? []
    }

    // MARK: - JSON Extraction

    /// Strips markdown code fences and returns the Data for the outermost JSON object `{…}`.
    private func extractJSON(from raw: String) -> Data? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip ```json ... ``` or ``` ... ``` fences.
        if text.hasPrefix("```") {
            let lines = text.components(separatedBy: "\n")
            // Drop the opening fence line and the closing ``` if present.
            let inner = lines.dropFirst().joined(separator: "\n")
            text = inner.hasSuffix("```")
                ? String(inner.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                : inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Extract from the first `{` to the last `}`.
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let jsonString = String(text[start...end])
        return jsonString.data(using: .utf8)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        notifyForRegion(region, trigger: "entered")
    }

    /// Result of requestState(for:) issued at registration time — catches the
    /// case where the user is already inside a fence when it's created, which
    /// didEnterRegion (boundary crossings only) never reports.
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard state == .inside else { return }
        notifyForRegion(region, trigger: "already inside")
    }

    private func notifyForRegion(_ region: CLRegion, trigger: String) {
        // Regions registered with the OS can outlive the settings toggle, so
        // re-check it before notifying.
        guard locationRemindersEnabled else { return }
        guard let fence = activeGeofences.first(where: { $0.id == region.identifier }) else { return }
        guard markNotifiedToday(for: fence) else {
            print("GeofenceManager: \(trigger) \(fence.name) — already notified today, skipping")
            return
        }
        print("GeofenceManager: \(trigger) \(fence.name) — notifying")
        NotificationManager.shared.scheduleGeofenceNotification(regionTitle: fence.name, tasks: fence.tasks)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("GeofenceManager: Exited \(region.identifier)")
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("GeofenceManager: Monitoring failed – \(error)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        print("GeofenceManager: Auth status \(status.rawValue)")

        // If fences were computed before permission was granted (or the OS
        // dropped its registrations), register them now that we're allowed to.
        if (status == .authorizedAlways || status == .authorizedWhenInUse),
           !activeGeofences.isEmpty,
           manager.monitoredRegions.isEmpty {
            registerGeofencesWithOS()
        }
    }
}
