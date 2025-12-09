//
//  Crag.swift
//  Climbate
//
//  Created by David Levy on 3/13/25.
//

import Foundation

struct Crag: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let location: String
    let latitude: Double
    let longitude: Double
    let safetyStatus: SafetyStatus
    let googleMapsUrl: String?
    let mountainProjectUrl: String?
    let precipitation: PrecipitationData?

    enum SafetyStatus: String, Codable, CaseIterable {
        case safe = "SAFE"
        case caution = "CAUTION"
        case unsafe = "UNSAFE"
        case unknown = "UNKNOWN"

        var displayName: String {
            switch self {
            case .safe: return "Safe"
            case .caution: return "Caution"
            case .unsafe: return "Unsafe"
            case .unknown: return "Unknown"
            }
        }
    }

    struct PrecipitationData: Codable, Equatable {
        let last7DaysMm: Double
        let lastRainDate: String?
        let daysSinceRain: Int?

        enum CodingKeys: String, CodingKey {
            case last7DaysMm = "last_7_days_mm"
            case lastRainDate = "last_rain_date"
            case daysSinceRain = "days_since_rain"
        }
    }

    // Coding keys for snake_case API response
    enum CodingKeys: String, CodingKey {
        case id, name, location, latitude, longitude, precipitation
        case safetyStatus = "safety_status"
        case googleMapsUrl = "google_maps_url"
        case mountainProjectUrl = "mountain_project_url"
    }

    // Decoder for API responses
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.location = try container.decode(String.self, forKey: .location)
        self.latitude = try container.decode(Double.self, forKey: .latitude)
        self.longitude = try container.decode(Double.self, forKey: .longitude)
        self.safetyStatus = try container.decode(SafetyStatus.self, forKey: .safetyStatus)
        self.googleMapsUrl = try container.decodeIfPresent(String.self, forKey: .googleMapsUrl)
        self.mountainProjectUrl = try container.decodeIfPresent(String.self, forKey: .mountainProjectUrl)
        self.precipitation = try container.decodeIfPresent(PrecipitationData.self, forKey: .precipitation)
    }

    // Manual initializer for previews and testing
    init(
        id: String = UUID().uuidString,
        name: String,
        location: String,
        latitude: Double = 0.0,
        longitude: Double = 0.0,
        safetyStatus: SafetyStatus = .unknown,
        googleMapsUrl: String? = nil,
        mountainProjectUrl: String? = nil,
        precipitation: PrecipitationData? = nil
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.safetyStatus = safetyStatus
        self.googleMapsUrl = googleMapsUrl
        self.mountainProjectUrl = mountainProjectUrl
        self.precipitation = precipitation
    }

    static func == (lhs: Crag, rhs: Crag) -> Bool {
        lhs.id == rhs.id
    }

    /// Extracts the state/region from the location hierarchy (first component before " > ")
    var state: String {
        location.components(separatedBy: " > ").first ?? location
    }
}

// MARK: - Preview Helpers

extension Crag {
    static let preview = Crag(
        name: "Yosemite Valley",
        location: "California > Yosemite National Park",
        latitude: 37.7456,
        longitude: -119.5936,
        safetyStatus: .safe,
        googleMapsUrl: "https://www.google.com/maps?q=37.7456,-119.5936",
        mountainProjectUrl: "https://www.mountainproject.com/area/105833381/yosemite-valley",
        precipitation: PrecipitationData(last7DaysMm: 0.0, lastRainDate: "2025-02-28", daysSinceRain: 7)
    )

    static let previewUnsafe = Crag(
        name: "Red River Gorge",
        location: "Kentucky > Red River Gorge",
        latitude: 37.7749,
        longitude: -83.6829,
        safetyStatus: .unsafe,
        googleMapsUrl: "https://www.google.com/maps?q=37.7749,-83.6829",
        mountainProjectUrl: "https://www.mountainproject.com/area/105841134/red-river-gorge",
        precipitation: PrecipitationData(last7DaysMm: 25.4, lastRainDate: "2025-03-05", daysSinceRain: 2)
    )
}
