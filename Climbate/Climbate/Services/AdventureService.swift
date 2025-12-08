//
//  AdventureService.swift
//  CLIMB.it
//
//  Find alternative adventures when climbing conditions are poor
//

import Foundation
import MapKit
import CoreLocation

// MARK: - Adventure Model

struct Adventure: Identifiable {
    let id: String
    let name: String
    let type: AdventureType
    let coordinate: CLLocationCoordinate2D
    var driveTimeMinutes: Int?
    var distanceMiles: Double?
    let mapItem: MKMapItem?

    // For dry crags from our database
    var crag: Crag?
}

enum AdventureType: String, CaseIterable {
    case dryCrag = "Dry Crags"
    case indoorGym = "Indoor Climbing"
    case hiking = "Hiking"
    case brewery = "Food & Drink"

    var icon: String {
        switch self {
        case .dryCrag: return "mountain.2.fill"
        case .indoorGym: return "figure.climbing"
        case .hiking: return "figure.hiking"
        case .brewery: return "mug.fill"
        }
    }

    var color: String {
        switch self {
        case .dryCrag: return "climbSafe"
        case .indoorGym: return "climbRope"
        case .hiking: return "climbSandstone"
        case .brewery: return "climbCaution"
        }
    }

    var searchQuery: String {
        switch self {
        case .dryCrag: return "" // Uses our DB
        case .indoorGym: return "climbing gym"
        case .hiking: return "hiking trail"
        case .brewery: return "brewery"
        }
    }
}

// MARK: - Adventure Service

@MainActor
class AdventureService: ObservableObject {
    @Published var adventures: [AdventureType: [Adventure]] = [:]
    @Published var isLoading = false

    private let searchRadius: CLLocationDistance = 80467 // 50 miles in meters

    /// Search for adventures near a location
    func searchAdventures(near location: CLLocationCoordinate2D, safeCrags: [Crag]) async {
        isLoading = true

        // Start with dry crags from our database
        var results: [AdventureType: [Adventure]] = [:]
        results[.dryCrag] = safeCrags.map { crag in
            Adventure(
                id: crag.id.uuidString,
                name: crag.name,
                type: .dryCrag,
                coordinate: CLLocationCoordinate2D(latitude: crag.latitude, longitude: crag.longitude),
                driveTimeMinutes: nil,
                distanceMiles: nil,
                mapItem: nil,
                crag: crag
            )
        }

        // Search for other adventure types in parallel
        await withTaskGroup(of: (AdventureType, [Adventure]).self) { group in
            for type in [AdventureType.indoorGym, .hiking, .brewery] {
                group.addTask {
                    let adventures = await self.searchPlaces(type: type, near: location)
                    return (type, adventures)
                }
            }

            for await (type, typeAdventures) in group {
                results[type] = typeAdventures
            }
        }

        // Calculate drive times for all adventures
        for (type, typeAdventures) in results {
            var adventuresWithTimes = typeAdventures
            for i in adventuresWithTimes.indices {
                if let driveTime = await calculateDriveTime(from: location, to: adventuresWithTimes[i].coordinate) {
                    adventuresWithTimes[i].driveTimeMinutes = driveTime.minutes
                    adventuresWithTimes[i].distanceMiles = driveTime.miles
                }
            }
            // Sort by drive time
            results[type] = adventuresWithTimes.sorted { ($0.driveTimeMinutes ?? 999) < ($1.driveTimeMinutes ?? 999) }
        }

        adventures = results
        isLoading = false
    }

    /// Search for places using MKLocalSearch
    private func searchPlaces(type: AdventureType, near location: CLLocationCoordinate2D) async -> [Adventure] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = type.searchQuery
        request.region = MKCoordinateRegion(
            center: location,
            latitudinalMeters: searchRadius * 2,
            longitudinalMeters: searchRadius * 2
        )

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()

            return response.mapItems.prefix(10).map { item in
                Adventure(
                    id: item.placemark.coordinate.latitude.description + item.placemark.coordinate.longitude.description,
                    name: item.name ?? "Unknown",
                    type: type,
                    coordinate: item.placemark.coordinate,
                    driveTimeMinutes: nil,
                    distanceMiles: nil,
                    mapItem: item,
                    crag: nil
                )
            }
        } catch {
            print("Search error for \(type): \(error)")
            return []
        }
    }

    /// Calculate drive time using MKDirections
    private func calculateDriveTime(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> (minutes: Int, miles: Double)? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile

        do {
            let directions = MKDirections(request: request)
            let response = try await directions.calculate()

            if let route = response.routes.first {
                let minutes = Int(route.expectedTravelTime / 60)
                let miles = route.distance / 1609.34
                return (minutes, miles)
            }
        } catch {
            // Fallback to straight-line distance estimate
            let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
            let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
            let distanceMeters = fromLocation.distance(from: toLocation)
            let miles = distanceMeters / 1609.34
            let estimatedMinutes = Int(miles / 45 * 60) // Assume 45 mph average
            return (estimatedMinutes, miles)
        }

        return nil
    }
}
