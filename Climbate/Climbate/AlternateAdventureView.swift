//
//  AlternateAdventureView.swift
//  ClimbIt
//
//  Created by David Levy on 3/13/25.
//

import SwiftUI

struct AlternateAdventureView: View {
    @EnvironmentObject var cragStore: CragStore
    @State private var safeCrags: [Crag] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.yellow)

                    Text("Find Dry Rock")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Here are some crags with safe climbing conditions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()

                // Safe crags list
                if isLoading {
                    ProgressView("Finding safe crags...")
                        .padding()
                } else if safeCrags.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "cloud.rain")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No safe crags found nearby")
                            .foregroundColor(.secondary)
                        Text("Check back later or expand your search area")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(safeCrags) { crag in
                            NavigationLink(destination: CragDetailView(crag: crag)) {
                                SafeCragCard(crag: crag)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .navigationTitle("Alternate Adventure")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSafeCrags()
        }
    }

    private func loadSafeCrags() async {
        isLoading = true

        // Fetch all crags and filter for safe ones
        let allCrags = await cragStore.fetchAllCrags()
        safeCrags = allCrags.filter { $0.safetyStatus == .safe }

        isLoading = false
    }
}

struct SafeCragCard: View {
    let crag: Crag

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(crag.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(crag.location)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let precip = crag.precipitation, let days = precip.daysSinceRain {
                    Text("\(days) days since rain")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

#Preview {
    NavigationStack {
        AlternateAdventureView()
            .environmentObject(CragStore())
    }
}
