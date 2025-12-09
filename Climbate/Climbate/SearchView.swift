//
//  SearchView.swift
//  CLIMB.it
//
//  Search and discover climbing areas
//

import SwiftUI
import MapKit

struct SearchView: View {
    @EnvironmentObject var cragStore: CragStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var searchResults: [Crag] = []
    @State private var isLoading: Bool = false
    @State private var hasSearched: Bool = false
    @State private var showMap: Bool = false
    @State private var selectedFilter: StatusFilter = .all

    enum StatusFilter: String, CaseIterable {
        case all = "All"
        case safe = "Safe"
        case caution = "Caution"
        case unsafe = "Unsafe"
    }

    var filteredResults: [Crag] {
        switch selectedFilter {
        case .all: return searchResults
        case .safe: return searchResults.filter { $0.safetyStatus == .safe }
        case .caution: return searchResults.filter { $0.safetyStatus == .caution }
        case .unsafe: return searchResults.filter { $0.safetyStatus == .unsafe }
        }
    }

    /// Groups crags by state, sorted alphabetically by state name, then by full location hierarchy within each state
    private var groupedResults: [(state: String, crags: [Crag])] {
        // Sort by full location path to get proper alphabetical order within nested levels
        let sorted = filteredResults.sorted { $0.location < $1.location }
        let grouped = Dictionary(grouping: sorted) { $0.state }
        return grouped.keys.sorted().map { state in
            (state: state, crags: grouped[state] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.climbChalk.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    searchBar
                        .padding(.horizontal, ClimbSpacing.md)
                        .padding(.top, ClimbSpacing.sm)

                    // Filter chips
                    filterChips
                        .padding(.top, ClimbSpacing.sm)

                    // View toggle
                    viewToggle
                        .padding(.horizontal, ClimbSpacing.md)
                        .padding(.top, ClimbSpacing.sm)

                    // Content
                    if isLoading {
                        loadingState
                    } else if filteredResults.isEmpty && hasSearched {
                        emptySearchState
                    } else if filteredResults.isEmpty {
                        initialState
                    } else if showMap {
                        mapView
                    } else {
                        resultsList
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Load all crags when view appears
                if searchResults.isEmpty {
                    await loadAllCrags()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Discover")
                        .font(ClimbTypography.title3)
                        .foregroundColor(.climbGranite)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(ClimbTypography.bodyBold)
                        .foregroundColor(.climbRope)
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: ClimbSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.climbStone)

            TextField("Search crags...", text: $searchText, prompt: Text("Search crags...").foregroundColor(.climbStone))
                .font(ClimbTypography.body)
                .foregroundColor(.climbGranite)
                .tint(.climbRope)
                .autocorrectionDisabled()
                .onSubmit {
                    Task { await performSearch() }
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    searchResults = []
                    hasSearched = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.climbStone)
                }
            }
        }
        .padding(ClimbSpacing.md)
        .background(Color.white)
        .cornerRadius(ClimbRadius.medium)
        .climbSubtleShadow()
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ClimbSpacing.sm) {
                ForEach(StatusFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        isSelected: selectedFilter == filter,
                        color: chipColor(for: filter)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, ClimbSpacing.md)
        }
    }

    private func chipColor(for filter: StatusFilter) -> Color {
        switch filter {
        case .all: return .climbRope
        case .safe: return .climbSafe
        case .caution: return .climbCaution
        case .unsafe: return .climbUnsafe
        }
    }

    // MARK: - View Toggle

    private var viewToggle: some View {
        HStack {
            Text("\(filteredResults.count) crags")
                .font(ClimbTypography.caption)
                .foregroundColor(.climbStone)

            Spacer()

            HStack(spacing: 0) {
                toggleButton(icon: "list.bullet", isSelected: !showMap) {
                    withAnimation { showMap = false }
                }
                toggleButton(icon: "map", isSelected: showMap) {
                    withAnimation { showMap = true }
                }
            }
            .background(Color.white)
            .cornerRadius(ClimbRadius.small)
            .climbSubtleShadow()
        }
    }

    private func toggleButton(icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .climbStone)
                .frame(width: 36, height: 32)
                .background(isSelected ? Color.climbRope : Color.clear)
                .cornerRadius(ClimbRadius.small)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: ClimbSpacing.md) {
            Spacer()
            ProgressView()
                .tint(.climbRope)
            Text("Searching...")
                .font(ClimbTypography.caption)
                .foregroundColor(.climbStone)
            Spacer()
        }
    }

    private var initialState: some View {
        VStack(spacing: ClimbSpacing.md) {
            Spacer()

            Image(systemName: "mountain.2.fill")
                .font(.system(size: 48))
                .foregroundColor(.climbSandstone)

            Text("No Crags Available")
                .font(ClimbTypography.title2)
                .foregroundColor(.climbGranite)

            Text("Check back later for\nclimbing area data")
                .font(ClimbTypography.body)
                .foregroundColor(.climbStone)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(ClimbSpacing.lg)
    }

    private var emptySearchState: some View {
        VStack(spacing: ClimbSpacing.md) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.climbMist)

            Text("No Results")
                .font(ClimbTypography.title2)
                .foregroundColor(.climbGranite)

            Text("Try a different search term\nor adjust your filters")
                .font(ClimbTypography.body)
                .foregroundColor(.climbStone)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(ClimbSpacing.lg)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: ClimbSpacing.md) {
                ForEach(groupedResults, id: \.state) { group in
                    DiscoverStateSection(state: group.state, crags: group.crags)
                }
            }
            .padding(.horizontal, ClimbSpacing.md)
            .padding(.top, ClimbSpacing.sm)
            .padding(.bottom, ClimbSpacing.xxl)
        }
    }

    // MARK: - Map View

    private var mapView: some View {
        CragMapView(crags: filteredResults)
            .cornerRadius(ClimbRadius.large)
            .padding(ClimbSpacing.md)
    }

    // MARK: - Actions

    private func loadAllCrags() async {
        isLoading = true
        searchResults = await cragStore.fetchAllCrags()
        isLoading = false
    }

    private func performSearch() async {
        guard !searchText.isEmpty else {
            // Reset to full list when search is cleared
            await loadAllCrags()
            hasSearched = false
            return
        }

        isLoading = true
        hasSearched = true
        searchResults = await cragStore.searchCrags(query: searchText)
        isLoading = false
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ClimbTypography.captionBold)
                .foregroundColor(isSelected ? .white : color)
                .padding(.horizontal, ClimbSpacing.md)
                .padding(.vertical, ClimbSpacing.sm)
                .background(isSelected ? color : color.opacity(0.15))
                .cornerRadius(ClimbRadius.pill)
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let crag: Crag
    @EnvironmentObject var cragStore: CragStore

    var body: some View {
        HStack(spacing: ClimbSpacing.md) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(crag.name)
                    .font(ClimbTypography.bodyBold)
                    .foregroundColor(.climbGranite)
                    .lineLimit(1)

                Text(crag.location)
                    .font(ClimbTypography.caption)
                    .foregroundColor(.climbStone)
                    .lineLimit(1)
            }

            Spacer()

            // Save button
            Button(action: { cragStore.toggle(crag) }) {
                Image(systemName: cragStore.isSaved(crag) ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundColor(cragStore.isSaved(crag) ? .climbSafe : .climbRope)
            }
        }
        .padding(ClimbSpacing.md)
        .background(Color.white)
        .cornerRadius(ClimbRadius.medium)
        .climbSubtleShadow()
    }

    private var statusColor: Color {
        switch crag.safetyStatus {
        case .safe: return .climbSafe
        case .caution: return .climbCaution
        case .unsafe: return .climbUnsafe
        case .unknown: return .climbUnknown
        }
    }
}

// MARK: - Map View

struct CragMapView: View {
    let crags: [Crag]

    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795), // US center
        span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)
    ))

    var body: some View {
        Map(position: $position) {
            ForEach(crags) { crag in
                Annotation(crag.name, coordinate: CLLocationCoordinate2D(
                    latitude: crag.latitude,
                    longitude: crag.longitude
                )) {
                    CragMapPin(crag: crag)
                }
            }
        }
    }
}

struct CragMapPin: View {
    let crag: Crag

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 28, height: 28)

                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }

            Triangle()
                .fill(statusColor)
                .frame(width: 10, height: 6)
                .offset(y: -2)
        }
        .climbSubtleShadow()
    }

    private var statusColor: Color {
        switch crag.safetyStatus {
        case .safe: return .climbSafe
        case .caution: return .climbCaution
        case .unsafe: return .climbUnsafe
        case .unknown: return .climbUnknown
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Discover State Section (Compact)

struct DiscoverStateSection: View {
    let state: String
    let crags: [Crag]
    @EnvironmentObject var cragStore: CragStore

    var body: some View {
        VStack(alignment: .leading, spacing: ClimbSpacing.xs) {
            // Compact section header
            HStack(spacing: ClimbSpacing.sm) {
                Text(state.uppercased())
                    .font(ClimbTypography.micro)
                    .fontWeight(.semibold)
                    .foregroundColor(.climbStone)
                    .tracking(0.8)

                Rectangle()
                    .fill(Color.climbMist)
                    .frame(height: 1)
            }
            .padding(.bottom, ClimbSpacing.xs)

            // Crag rows
            VStack(spacing: ClimbSpacing.sm) {
                ForEach(crags) { crag in
                    NavigationLink(destination: CragDetailView(crag: crag)) {
                        SearchResultRow(crag: crag)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    SearchView()
        .environmentObject(CragStore())
}
