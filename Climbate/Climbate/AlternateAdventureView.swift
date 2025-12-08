//
//  AlternateAdventureView.swift
//  CLIMB.it
//
//  Find alternative adventures when your spot is wet
//

import SwiftUI
import MapKit

struct AlternateAdventureView: View {
    @EnvironmentObject var cragStore: CragStore
    @StateObject private var adventureService = AdventureService()
    @State private var selectedType: AdventureType = .dryCrag
    @State private var userLocation: CLLocationCoordinate2D?

    // Default to a central US location if we don't have user location
    private var searchLocation: CLLocationCoordinate2D {
        userLocation ?? CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795)
    }

    var body: some View {
        ZStack {
            Color.climbChalk.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerSection
                    .padding(.horizontal, ClimbSpacing.md)

                // Category tabs
                categoryTabs
                    .padding(.top, ClimbSpacing.sm)

                // Content
                if adventureService.isLoading {
                    loadingState
                } else {
                    adventuresList
                }
            }
        }
        .navigationTitle("Plan B")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.climbChalk, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .task {
            await loadAdventures()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: ClimbSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spot's wet?")
                        .font(ClimbTypography.title2)
                        .foregroundColor(.climbGranite)
                    Text("Here's what else is nearby")
                        .font(ClimbTypography.body)
                        .foregroundColor(.climbStone)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.climbSandstone.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 24))
                        .foregroundColor(.climbSandstone)
                }
            }
        }
        .padding(.vertical, ClimbSpacing.md)
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ClimbSpacing.sm) {
                ForEach(AdventureType.allCases, id: \.self) { type in
                    AdventureTypeTab(
                        type: type,
                        isSelected: selectedType == type,
                        count: adventureService.adventures[type]?.count ?? 0
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedType = type
                        }
                    }
                }
            }
            .padding(.horizontal, ClimbSpacing.md)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: ClimbSpacing.md) {
            Spacer()
            ProgressView()
                .tint(.climbRope)
            Text("Finding adventures...")
                .font(ClimbTypography.caption)
                .foregroundColor(.climbStone)
            Spacer()
        }
    }

    // MARK: - Adventures List

    private var adventuresList: some View {
        let adventures = adventureService.adventures[selectedType] ?? []

        return ScrollView {
            LazyVStack(spacing: ClimbSpacing.sm) {
                if adventures.isEmpty {
                    emptyState
                } else {
                    ForEach(adventures) { adventure in
                        AdventureCard(adventure: adventure)
                    }
                }
            }
            .padding(.horizontal, ClimbSpacing.md)
            .padding(.top, ClimbSpacing.md)
            .padding(.bottom, ClimbSpacing.xxl)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: ClimbSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.climbMist)
                    .frame(width: 80, height: 80)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundColor(.climbStone)
            }

            Text("Nothing found nearby")
                .font(ClimbTypography.title3)
                .foregroundColor(.climbGranite)

            Text("Try a different category")
                .font(ClimbTypography.body)
                .foregroundColor(.climbStone)
        }
        .padding(.vertical, ClimbSpacing.xxl)
    }

    // MARK: - Load Adventures

    private func loadAdventures() async {
        let safeCrags = await cragStore.fetchAllCrags().filter { $0.safetyStatus == .safe }
        await adventureService.searchAdventures(near: searchLocation, safeCrags: safeCrags)
    }
}

// MARK: - Adventure Type Tab

struct AdventureTypeTab: View {
    let type: AdventureType
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 14))
                Text(type.rawValue)
                    .font(ClimbTypography.captionBold)
                if count > 0 {
                    Text("\(count)")
                        .font(ClimbTypography.micro)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.3) : Color.climbMist)
                        .cornerRadius(8)
                }
            }
            .foregroundColor(isSelected ? .white : .climbGranite)
            .padding(.horizontal, ClimbSpacing.md)
            .padding(.vertical, ClimbSpacing.sm)
            .background(isSelected ? typeColor : Color.white)
            .cornerRadius(ClimbRadius.medium)
            .climbSubtleShadow()
        }
    }

    private var typeColor: Color {
        switch type {
        case .dryCrag: return .climbSafe
        case .indoorGym: return .climbRope
        case .hiking: return .climbSandstone
        case .brewery: return .climbCaution
        }
    }
}

// MARK: - Adventure Card

struct AdventureCard: View {
    let adventure: Adventure
    @Environment(\.openURL) var openURL

    var body: some View {
        Button(action: openInMaps) {
            HStack(spacing: ClimbSpacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(typeColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: adventure.type.icon)
                        .font(.system(size: 20))
                        .foregroundColor(typeColor)
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(adventure.name)
                        .font(ClimbTypography.bodyBold)
                        .foregroundColor(.climbGranite)
                        .lineLimit(1)

                    if let crag = adventure.crag {
                        Text(crag.location)
                            .font(ClimbTypography.caption)
                            .foregroundColor(.climbStone)
                            .lineLimit(1)

                        if let precip = crag.precipitation, let days = precip.daysSinceRain {
                            HStack(spacing: 4) {
                                Image(systemName: "sun.max.fill")
                                    .font(.caption2)
                                Text("\(days) days dry")
                                    .font(ClimbTypography.micro)
                            }
                            .foregroundColor(.climbSafe)
                        }
                    }
                }

                Spacer()

                // Drive time badge
                if let minutes = adventure.driveTimeMinutes {
                    driveTimeBadge(minutes: minutes)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.climbStone)
            }
            .padding(ClimbSpacing.md)
            .background(Color.white)
            .cornerRadius(ClimbRadius.medium)
            .climbSubtleShadow()
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func driveTimeBadge(minutes: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "car.fill")
                .font(.system(size: 10))
            Text(formatDriveTime(minutes))
                .font(ClimbTypography.micro)
        }
        .foregroundColor(.climbRope)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.climbRope.opacity(0.1))
        .cornerRadius(ClimbRadius.small)
    }

    private func formatDriveTime(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
    }

    private var typeColor: Color {
        switch adventure.type {
        case .dryCrag: return .climbSafe
        case .indoorGym: return .climbRope
        case .hiking: return .climbSandstone
        case .brewery: return .climbCaution
        }
    }

    private func openInMaps() {
        if let mapItem = adventure.mapItem {
            mapItem.openInMaps()
        } else {
            let coordinate = adventure.coordinate
            let url = URL(string: "http://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=\(adventure.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
            openURL(url)
        }
    }
}

#Preview {
    NavigationStack {
        AlternateAdventureView()
            .environmentObject(CragStore())
    }
}
