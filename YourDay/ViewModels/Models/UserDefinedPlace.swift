import Foundation
import CoreLocation

struct UserDefinedPlace: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var address: String
    var description: String = ""
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func load() -> [UserDefinedPlace] {
        guard let data = UserDefaults.standard.data(forKey: "userDefinedPlaces"),
              let places = try? JSONDecoder().decode([UserDefinedPlace].self, from: data) else {
            return []
        }
        return places
    }

    static func save(_ places: [UserDefinedPlace]) {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: "userDefinedPlaces")
        }
    }
}
