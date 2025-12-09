//
//  CragStore.swift
//  Climbate
//
//  Manages saved crags with UserDefaults persistence
//

import Foundation
import SwiftUI

@MainActor
class CragStore: ObservableObject {
    @Published var savedCrags: [Crag] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    private let userDefaultsKey = "savedCrags"
    private let apiClient = APIClient.shared

    init() {
        loadFromStorage()
    }

    // MARK: - Saved Crags Management

    func save(_ crag: Crag) {
        guard !savedCrags.contains(where: { $0.id == crag.id }) else { return }
        savedCrags.append(crag)
        persistToStorage()
    }

    func remove(_ crag: Crag) {
        savedCrags.removeAll { $0.id == crag.id }
        persistToStorage()
    }

    func remove(at offsets: IndexSet) {
        savedCrags.remove(atOffsets: offsets)
        persistToStorage()
    }

    func isSaved(_ crag: Crag) -> Bool {
        savedCrags.contains(where: { $0.id == crag.id })
    }

    func toggle(_ crag: Crag) {
        if isSaved(crag) {
            remove(crag)
        } else {
            save(crag)
        }
    }

    // MARK: - API Fetching

    func fetchAllCrags() async -> [Crag] {
        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            let crags = try await apiClient.fetchAllCrags()
            print("Fetched \(crags.count) total crags")
            return crags
        } catch {
            self.error = error.localizedDescription
            print("Error fetching crags: \(error)")
            return []
        }
    }

    func searchCrags(query: String) async -> [Crag] {
        guard !query.isEmpty else { return [] }

        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            let results = try await apiClient.searchCrags(query: query)
            print("Search returned \(results.count) crags")
            return results
        } catch {
            self.error = error.localizedDescription
            print("Error searching crags: \(error)")
            return []
        }
    }

    func refreshCragDetails(_ crag: Crag) async -> Crag? {
        do {
            let detailed = try await apiClient.getCrag(id: crag.id)
            return detailed
        } catch {
            print("Error fetching crag details for \(crag.id): \(error)")
            return nil
        }
    }

    // MARK: - Persistence

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }

        do {
            savedCrags = try JSONDecoder().decode([Crag].self, from: data)
        } catch {
            print("Error loading saved crags: \(error)")
        }
    }

    private func persistToStorage() {
        do {
            let data = try JSONEncoder().encode(savedCrags)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("Error saving crags: \(error)")
        }
    }
}
