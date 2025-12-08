//
//  CragDetailView.swift
//  ClimbIt
//
//  Created by David Levy on 3/13/25.
//

import SwiftUI

struct CragDetailView: View {
    let crag: Crag
    @EnvironmentObject var cragStore: CragStore
    @State private var detailedCrag: Crag?

    var displayCrag: Crag {
        detailedCrag ?? crag
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Location
                VStack(alignment: .leading) {
                    Text(displayCrag.location)
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Safety Status Banner
                safetyBanner

                // Weather & Status Message
                weatherSection

                // Map Links
                mapLinksSection
            }
            .padding(.top)
        }
        .navigationTitle(displayCrag.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { cragStore.toggle(displayCrag) }) {
                    Image(systemName: cragStore.isSaved(displayCrag) ? "heart.fill" : "heart")
                        .foregroundColor(cragStore.isSaved(displayCrag) ? .red : .primary)
                }
            }
        }
        .task {
            // Fetch detailed info including precipitation
            detailedCrag = await cragStore.refreshCragDetails(crag)
        }
    }

    // MARK: - Components

    private var safetyBanner: some View {
        Text("Safety Status: \(displayCrag.safetyStatus.displayName)")
            .font(.title3)
            .fontWeight(.semibold)
            .padding()
            .frame(maxWidth: .infinity)
            .background(statusColor)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.horizontal)
    }

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Status message
            statusMessage

            Divider()

            // Precipitation Data
            VStack(alignment: .leading, spacing: 10) {
                Text("Precipitation Data")
                    .font(.headline)

                if let precip = displayCrag.precipitation {
                    HStack {
                        Label("\(String(format: "%.1f", precip.last7DaysMm)) mm", systemImage: "drop.fill")
                        Text("in the last 7 days")
                            .foregroundColor(.secondary)
                    }

                    if let daysSince = precip.daysSinceRain {
                        HStack {
                            Label("\(daysSince) days", systemImage: "calendar")
                            Text("since last rain")
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("Precipitation data not available")
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch displayCrag.safetyStatus {
        case .unsafe:
            unsafeMessage
        case .caution:
            cautionMessage
        case .safe:
            safeMessage
        }
    }

    private var unsafeMessage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Conditions are Unsafe")
                .font(.headline)
                .foregroundColor(.red)

            if let precip = displayCrag.precipitation, let days = precip.daysSinceRain {
                Text("\(displayCrag.name) saw rain just \(days) day\(days == 1 ? "" : "s") ago with \(String(format: "%.1f", precip.last7DaysMm)) mm of precipitation this week. The rock is likely still wet and unsafe to climb.")
                    .foregroundColor(.secondary)
            } else {
                Text("Recent precipitation has made conditions unsafe. Please check local conditions before climbing.")
                    .foregroundColor(.secondary)
            }

            NavigationLink(destination: AlternateAdventureView()) {
                Text("Find an Alternate Adventure")
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
    }

    private var cautionMessage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Use Caution")
                .font(.headline)
                .foregroundColor(.orange)

            Text("Conditions may be variable. Check local weather and rock conditions before climbing.")
                .foregroundColor(.secondary)
        }
    }

    private var safeMessage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Conditions are Safe")
                .font(.headline)
                .foregroundColor(.green)

            if let precip = displayCrag.precipitation, let days = precip.daysSinceRain {
                Text("\(displayCrag.name) has not seen rain in \(days) day\(days == 1 ? "" : "s"). Climb on!")
                    .foregroundColor(.secondary)
            } else {
                Text("No recent precipitation. Conditions look good for climbing!")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var mapLinksSection: some View {
        VStack(spacing: 10) {
            mapButton(
                title: "Open in Google Maps",
                icon: "map.fill",
                url: googleMapsURL,
                color: .blue
            )

            mapButton(
                title: "Open in Apple Maps",
                icon: "map",
                url: appleMapsURL,
                color: .green
            )

            if let mpUrl = displayCrag.mountainProjectUrl, let url = URL(string: mpUrl) {
                mapButton(
                    title: "View on Mountain Project",
                    icon: "globe",
                    url: url,
                    color: .gray
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
    }

    private func mapButton(title: String, icon: String, url: URL, color: Color) -> some View {
        Link(destination: url) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(color)
            .cornerRadius(10)
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        switch displayCrag.safetyStatus {
        case .safe: return .green
        case .caution: return .yellow
        case .unsafe: return .red
        }
    }

    private var googleMapsURL: URL {
        URL(string: "https://www.google.com/maps?q=\(displayCrag.latitude),\(displayCrag.longitude)")!
    }

    private var appleMapsURL: URL {
        URL(string: "http://maps.apple.com/?q=\(displayCrag.latitude),\(displayCrag.longitude)")!
    }
}

#Preview("Safe Crag") {
    NavigationStack {
        CragDetailView(crag: .preview)
            .environmentObject(CragStore())
    }
}

#Preview("Unsafe Crag") {
    NavigationStack {
        CragDetailView(crag: .previewUnsafe)
            .environmentObject(CragStore())
    }
}
