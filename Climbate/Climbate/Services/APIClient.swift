//
//  APIClient.swift
//  ClimbIt
//
//  API client for communicating with the ClimbIt backend
//

import Foundation

class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        #if DEBUG
        // Use production API for now (no local server running)
        // TODO: Switch back to localhost:8000 for local development
        self.baseURL = URL(string: "http://climbit-prod-alb-2136483458.us-east-1.elb.amazonaws.com")!
        #else
        // Production API endpoint
        // TODO: Set up api.climbit.app DNS with HTTPS
        self.baseURL = URL(string: "http://climbit-prod-alb-2136483458.us-east-1.elb.amazonaws.com")!
        #endif

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
    }

    // MARK: - Public API

    /// Fetch all crags with optional pagination
    func fetchCrags(page: Int = 1, perPage: Int = 50) async throws -> [Crag] {
        var components = URLComponents(url: baseURL.appendingPathComponent("crags"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]

        return try await fetch(from: components.url!)
    }

    /// Search crags by name or location
    func searchCrags(query: String, limit: Int = 20) async throws -> [Crag] {
        guard !query.isEmpty else { return [] }

        var components = URLComponents(url: baseURL.appendingPathComponent("crags/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        return try await fetch(from: components.url!)
    }

    /// Find crags near a location
    func nearbyCrags(latitude: Double, longitude: Double, radiusKm: Double = 50, limit: Int = 20) async throws -> [Crag] {
        var components = URLComponents(url: baseURL.appendingPathComponent("crags/nearby"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "radius_km", value: String(radiusKm)),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        return try await fetch(from: components.url!)
    }

    /// Get detailed crag info including precipitation data
    func getCrag(id: UUID) async throws -> Crag {
        let url = baseURL.appendingPathComponent("crags/\(id.uuidString)")
        return try await fetch(from: url)
    }

    /// Health check
    func healthCheck() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        let (_, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    // MARK: - Private Helpers

    private func fetch<T: Decodable>(from url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("Decoding error: \(error)")
            throw APIError.decodingError(error)
        }
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "Server error (status \(statusCode))"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
