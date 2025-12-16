//
//  AreaBrowserView.swift
//  CLIMB.it
//
//  Hierarchical area browser - drill down from states to crags
//

import SwiftUI

/// Main discover view with hierarchical navigation
struct AreaBrowserView: View {
    @EnvironmentObject var cragStore: CragStore
    @State private var areas: [Area] = []
    @State private var isLoading: Bool = false
    @State private var error: String?
    @State private var searchText: String = ""
    @State private var searchResults: [AreaSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?

    private let apiClient = APIClient.shared

    /// True when showing server search results
    var isShowingSearchResults: Bool {
        searchText.count >= 2
    }

    /// Filter areas by search text (local filtering for 1 char)
    var filteredAreas: [Area] {
        if searchText.isEmpty {
            return areas
        }
        if searchText.count == 1 {
            let query = searchText.lowercased()
            return areas.filter { $0.name.lowercased().contains(query) }
        }
        return areas
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.climbChalk.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar for filtering
                    searchBar
                        .padding(.horizontal, ClimbSpacing.md)
                        .padding(.top, ClimbSpacing.sm)

                    // Content
                    if isLoading && !isShowingSearchResults {
                        loadingState
                    } else if let error = error, !isShowingSearchResults {
                        errorState(error)
                    } else if isShowingSearchResults {
                        searchResultsList
                    } else if areas.isEmpty {
                        emptyState
                    } else {
                        areaList
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Discover")
                        .font(ClimbTypography.title3)
                        .foregroundColor(.climbGranite)
                }
            }
            .task {
                await loadTopLevelAreas()
            }
            .onChange(of: searchText) { _, newValue in
                performSearch(query: newValue)
            }
        }
    }

    // MARK: - Components

    private var searchBar: some View {
        HStack(spacing: ClimbSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.climbStone)

            TextField("Search all crags...", text: $searchText)
                .font(ClimbTypography.body)
                .foregroundColor(.climbGranite)
                .tint(.climbRope)
                .autocorrectionDisabled()

            if isSearching {
                ProgressView()
                    .scaleEffect(0.8)
            } else if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
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

    private var loadingState: some View {
        VStack(spacing: ClimbSpacing.md) {
            Spacer()
            ProgressView()
                .tint(.climbRope)
            Text("Loading areas...")
                .font(ClimbTypography.caption)
                .foregroundColor(.climbStone)
            Spacer()
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: ClimbSpacing.md) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.climbCaution)

            Text("Unable to Load")
                .font(ClimbTypography.title2)
                .foregroundColor(.climbGranite)

            Text(message)
                .font(ClimbTypography.body)
                .foregroundColor(.climbStone)
                .multilineTextAlignment(.center)

            ClimbButton("Try Again", icon: "arrow.clockwise") {
                Task { await loadTopLevelAreas() }
            }
            .padding(.horizontal, ClimbSpacing.xxl)

            Spacer()
        }
        .padding(ClimbSpacing.lg)
    }

    private var emptyState: some View {
        VStack(spacing: ClimbSpacing.md) {
            Spacer()

            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundColor(.climbSandstone)

            Text("No Areas Yet")
                .font(ClimbTypography.title2)
                .foregroundColor(.climbGranite)

            Text("Areas are being synced.\nCheck back soon!")
                .font(ClimbTypography.body)
                .foregroundColor(.climbStone)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(ClimbSpacing.lg)
    }

    private var areaList: some View {
        ScrollView {
            LazyVStack(spacing: ClimbSpacing.sm) {
                ForEach(filteredAreas) { area in
                    AreaRow(area: area, breadcrumb: "")
                }
            }
            .padding(.horizontal, ClimbSpacing.md)
            .padding(.top, ClimbSpacing.sm)
            .padding(.bottom, ClimbSpacing.xxl)
        }
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: ClimbSpacing.sm) {
                if searchResults.isEmpty && !isSearching {
                    VStack(spacing: ClimbSpacing.md) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.climbMist)

                        Text("No results for \"\(searchText)\"")
                            .font(ClimbTypography.body)
                            .foregroundColor(.climbStone)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, ClimbSpacing.xxl)
                } else {
                    ForEach(searchResults) { result in
                        SearchResultRow(result: result)
                    }
                }
            }
            .padding(.horizontal, ClimbSpacing.md)
            .padding(.top, ClimbSpacing.sm)
            .padding(.bottom, ClimbSpacing.xxl)
        }
    }

    // MARK: - Search

    private func performSearch(query: String) {
        // Cancel any previous search
        searchTask?.cancel()

        // Clear results if query is too short
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        // Debounce: wait 300ms before searching
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)

            guard !Task.isCancelled else { return }

            await MainActor.run { isSearching = true }

            do {
                let results = try await apiClient.searchAreas(query: query)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadTopLevelAreas() async {
        isLoading = true
        error = nil

        do {
            areas = try await apiClient.fetchAreas()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Area Row

struct AreaRow: View {
    let area: Area
    let breadcrumb: String
    @EnvironmentObject var cragStore: CragStore

    var body: some View {
        NavigationLink {
            if area.hasChildren {
                // This area has children - show sub-areas first
                AreaChildrenView(area: area, breadcrumb: breadcrumb)
            } else if area.isCrag {
                // This is a leaf crag - go to detail view
                if let crag = area.toCrag(location: breadcrumb) {
                    CragDetailView(crag: crag)
                }
            } else {
                // Fallback - show children view (will show empty state)
                AreaChildrenView(area: area, breadcrumb: breadcrumb)
            }
        } label: {
            HStack(spacing: ClimbSpacing.md) {
                // Icon based on area type
                ZStack {
                    Circle()
                        .fill(iconBackground)
                        .frame(width: 40, height: 40)

                    if isState, let abbrev = stateAbbreviation {
                        // Use custom state outline image
                        Image("state-\(abbrev)")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundColor(iconColor)
                    } else {
                        Image(systemName: iconName)
                            .font(.system(size: 16))
                            .foregroundColor(iconColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(area.name)
                        .font(ClimbTypography.bodyBold)
                        .foregroundColor(.climbGranite)
                        .lineLimit(1)

                    if isLeafCrag {
                        if let status = area.safetyStatus {
                            Text(status.displayName)
                                .font(ClimbTypography.caption)
                                .foregroundColor(statusColor)
                        }
                    } else {
                        Text(area.hasChildren ? "Tap to explore" : "No sub-areas")
                            .font(ClimbTypography.caption)
                            .foregroundColor(.climbStone)
                    }
                }

                Spacer()

                // Action button for leaf crags, chevron for areas with children
                if isLeafCrag {
                    Button(action: {
                        if let crag = area.toCrag(location: breadcrumb) {
                            cragStore.toggle(crag)
                        }
                    }) {
                        Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                            .font(.title2)
                            .foregroundColor(isSaved ? .climbSafe : .climbRope)
                    }
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.climbStone)
                }
            }
            .padding(ClimbSpacing.md)
            .background(Color.white)
            .cornerRadius(ClimbRadius.medium)
            .climbSubtleShadow()
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Area Type Detection

    /// Top-level areas (states) have empty breadcrumb
    private var isState: Bool {
        breadcrumb.isEmpty
    }

    /// Convert state name to abbreviation for asset lookup
    private var stateAbbreviation: String? {
        Self.stateAbbreviations[area.name]
    }

    /// State name to abbreviation mapping
    private static let stateAbbreviations: [String: String] = [
        "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR", "California": "CA",
        "Colorado": "CO", "Connecticut": "CT", "Delaware": "DE", "Florida": "FL", "Georgia": "GA",
        "Hawaii": "HI", "Idaho": "ID", "Illinois": "IL", "Indiana": "IN", "Iowa": "IA",
        "Kansas": "KS", "Kentucky": "KY", "Louisiana": "LA", "Maine": "ME", "Maryland": "MD",
        "Massachusetts": "MA", "Michigan": "MI", "Minnesota": "MN", "Mississippi": "MS", "Missouri": "MO",
        "Montana": "MT", "Nebraska": "NE", "Nevada": "NV", "New Hampshire": "NH", "New Jersey": "NJ",
        "New Mexico": "NM", "New York": "NY", "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH",
        "Oklahoma": "OK", "Oregon": "OR", "Pennsylvania": "PA", "Rhode Island": "RI", "South Carolina": "SC",
        "South Dakota": "SD", "Tennessee": "TN", "Texas": "TX", "Utah": "UT", "Vermont": "VT",
        "Virginia": "VA", "Washington": "WA", "West Virginia": "WV", "Wisconsin": "WI", "Wyoming": "WY",
        "District of Columbia": "DC", "Puerto Rico": "PR"
    ]

    /// A leaf crag is one that has coordinates but NO children
    private var isLeafCrag: Bool {
        area.isCrag && !area.hasChildren
    }

    /// A crag with sub-areas (like Yosemite Valley with its walls)
    private var isCragWithChildren: Bool {
        area.isCrag && area.hasChildren
    }

    /// A region is an area without coordinates (container only)
    private var isRegion: Bool {
        !area.isCrag && area.hasChildren
    }

    // MARK: - Icon Properties

    private var iconName: String {
        if isState {
            return "globe.americas.fill"  // US state
        } else if isLeafCrag {
            return "mountain.2.fill"
        } else if isCragWithChildren {
            return "mappin.circle.fill"  // Location with sub-areas
        } else if isRegion {
            return "map.fill"  // Region/container
        } else {
            return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        if isState {
            return .climbRope
        } else if isLeafCrag {
            return statusColor
        } else if isCragWithChildren {
            return .climbSandstone
        } else {
            return .climbStone
        }
    }

    private var iconBackground: Color {
        if isLeafCrag {
            return statusColor.opacity(0.15)
        } else if isState {
            return Color.climbRope.opacity(0.15)
        } else if isCragWithChildren {
            return Color.climbSandstone.opacity(0.15)
        } else {
            return Color.climbMist
        }
    }

    private var statusColor: Color {
        switch area.safetyStatus {
        case .safe: return .climbSafe
        case .caution: return .climbCaution
        case .unsafe: return .climbUnsafe
        case .unknown, .none: return .climbUnknown
        }
    }

    private var isSaved: Bool {
        cragStore.savedCrags.contains { $0.id == area.id }
    }
}

// MARK: - Area Children View (Drill-down)

struct AreaChildrenView: View {
    let area: Area
    let breadcrumb: String
    @EnvironmentObject var cragStore: CragStore

    @State private var children: [Area] = []
    @State private var isLoading: Bool = false
    @State private var error: String?
    @State private var searchText: String = ""

    private let apiClient = APIClient.shared

    /// Build full breadcrumb for children
    var childBreadcrumb: String {
        breadcrumb.isEmpty ? area.name : "\(breadcrumb) > \(area.name)"
    }

    /// Filter children by search text
    var filteredChildren: [Area] {
        if searchText.isEmpty {
            return children
        }
        let query = searchText.lowercased()
        return children.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        ZStack {
            Color.climbChalk.ignoresSafeArea()

            VStack(spacing: 0) {
                // Search bar
                searchBar
                    .padding(.horizontal, ClimbSpacing.md)
                    .padding(.top, ClimbSpacing.sm)

                // Content
                if isLoading {
                    loadingState
                } else if let error = error {
                    errorState(error)
                } else if children.isEmpty && !area.isCrag {
                    emptyState
                } else {
                    childrenListWithHeader
                }
            }
        }
        .navigationTitle(area.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.climbChalk, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .task {
            await loadChildren()
        }
    }

    /// Whether this is a state-level view (no weather tracking makes sense)
    private var isStateLevel: Bool {
        breadcrumb.isEmpty
    }

    // MARK: - Components

    private var searchBar: some View {
        HStack(spacing: ClimbSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.climbStone)

            TextField("Filter \(area.name)...", text: $searchText)
                .font(ClimbTypography.body)
                .foregroundColor(.climbGranite)
                .tint(.climbRope)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
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

    private var loadingState: some View {
        VStack(spacing: ClimbSpacing.md) {
            Spacer()
            ProgressView()
                .tint(.climbRope)
            Text("Loading...")
                .font(ClimbTypography.caption)
                .foregroundColor(.climbStone)
            Spacer()
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: ClimbSpacing.md) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.climbCaution)

            Text("Unable to Load")
                .font(ClimbTypography.title2)
                .foregroundColor(.climbGranite)

            Text(message)
                .font(ClimbTypography.body)
                .foregroundColor(.climbStone)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(ClimbSpacing.lg)
    }

    private var emptyState: some View {
        VStack(spacing: ClimbSpacing.md) {
            Spacer()

            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundColor(.climbMist)

            Text("No Sub-areas")
                .font(ClimbTypography.title2)
                .foregroundColor(.climbGranite)

            Text("This area doesn't have\nany sub-regions yet")
                .font(ClimbTypography.body)
                .foregroundColor(.climbStone)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(ClimbSpacing.lg)
    }

    private var childrenList: some View {
        ScrollView {
            LazyVStack(spacing: ClimbSpacing.sm) {
                ForEach(filteredChildren) { child in
                    AreaRow(area: child, breadcrumb: childBreadcrumb)
                }
            }
            .padding(.horizontal, ClimbSpacing.md)
            .padding(.top, ClimbSpacing.sm)
            .padding(.bottom, ClimbSpacing.xxl)
        }
    }

    /// Children list with weather section for areas with coordinates
    private var childrenListWithHeader: some View {
        ScrollView {
            LazyVStack(spacing: ClimbSpacing.sm) {
                // Weather section for areas with coordinates (but NOT states - too broad)
                // Users can track weather at any level they find useful (e.g., Yosemite Valley)
                if area.isCrag && !isStateLevel {
                    VStack(alignment: .leading, spacing: ClimbSpacing.sm) {
                        // Section header
                        Text("CONDITIONS")
                            .font(ClimbTypography.micro)
                            .fontWeight(.semibold)
                            .foregroundColor(.climbStone)
                            .tracking(1)
                            .padding(.horizontal, ClimbSpacing.sm)

                        cragInfoHeader
                    }
                    .padding(.bottom, ClimbSpacing.md)
                }

                // Children section with header if there are children
                if !filteredChildren.isEmpty {
                    VStack(alignment: .leading, spacing: ClimbSpacing.sm) {
                        // Section header for sub-areas
                        Text("SUB-AREAS")
                            .font(ClimbTypography.micro)
                            .fontWeight(.semibold)
                            .foregroundColor(.climbStone)
                            .tracking(1)
                            .padding(.horizontal, ClimbSpacing.sm)

                        ForEach(filteredChildren) { child in
                            AreaRow(area: child, breadcrumb: childBreadcrumb)
                        }
                    }
                }
            }
            .padding(.horizontal, ClimbSpacing.md)
            .padding(.top, ClimbSpacing.sm)
            .padding(.bottom, ClimbSpacing.xxl)
        }
    }

    /// Header card showing weather/safety info with link to detail view
    private var cragInfoHeader: some View {
        NavigationLink {
            if let crag = area.toCrag(location: breadcrumb) {
                CragDetailView(crag: crag)
            }
        } label: {
            HStack(spacing: ClimbSpacing.md) {
                // Weather icon
                ZStack {
                    Circle()
                        .fill(headerStatusColor.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 20))
                        .foregroundColor(headerStatusColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Weather & Safety")
                        .font(ClimbTypography.bodyBold)
                        .foregroundColor(.climbGranite)

                    if let status = area.safetyStatus {
                        Text(status.displayName)
                            .font(ClimbTypography.caption)
                            .foregroundColor(headerStatusColor)
                    } else {
                        Text("View conditions for this area")
                            .font(ClimbTypography.caption)
                            .foregroundColor(.climbStone)
                    }
                }

                Spacer()

                // Save button
                Button(action: {
                    if let crag = area.toCrag(location: breadcrumb) {
                        cragStore.toggle(crag)
                    }
                }) {
                    Image(systemName: isAreaSaved ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title2)
                        .foregroundColor(isAreaSaved ? .climbSafe : .climbRope)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.climbStone)
            }
            .padding(ClimbSpacing.md)
            .background(
                LinearGradient(
                    colors: [headerStatusColor.opacity(0.1), Color.white],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(ClimbRadius.medium)
            .climbSubtleShadow()
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var headerStatusColor: Color {
        switch area.safetyStatus {
        case .safe: return .climbSafe
        case .caution: return .climbCaution
        case .unsafe: return .climbUnsafe
        case .unknown, .none: return .climbUnknown
        }
    }

    private var isAreaSaved: Bool {
        cragStore.savedCrags.contains { $0.id == area.id }
    }

    // MARK: - Data Loading

    private func loadChildren() async {
        isLoading = true
        error = nil

        do {
            children = try await apiClient.fetchAreaChildren(areaId: area.id)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: AreaSearchResult
    @EnvironmentObject var cragStore: CragStore

    var body: some View {
        NavigationLink {
            if result.hasChildren {
                AreaChildrenView(area: result.toArea(), breadcrumb: parentBreadcrumb)
            } else if result.isCrag, let crag = result.toCrag() {
                CragDetailView(crag: crag)
            } else {
                AreaChildrenView(area: result.toArea(), breadcrumb: parentBreadcrumb)
            }
        } label: {
            HStack(spacing: ClimbSpacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconBackground)
                        .frame(width: 40, height: 40)

                    Image(systemName: iconName)
                        .font(.system(size: 16))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.name)
                        .font(ClimbTypography.bodyBold)
                        .foregroundColor(.climbGranite)
                        .lineLimit(1)

                    // Breadcrumb shows full path
                    Text(result.breadcrumb)
                        .font(ClimbTypography.caption)
                        .foregroundColor(.climbStone)
                        .lineLimit(1)
                }

                Spacer()

                // Save button for crags
                if isLeafCrag {
                    Button(action: {
                        if let crag = result.toCrag() {
                            cragStore.toggle(crag)
                        }
                    }) {
                        Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                            .font(.title2)
                            .foregroundColor(isSaved ? .climbSafe : .climbRope)
                    }
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

    // MARK: - Computed Properties

    private var isLeafCrag: Bool {
        result.isCrag && !result.hasChildren
    }

    /// Parent breadcrumb for child navigation (everything except last component)
    private var parentBreadcrumb: String {
        let components = result.breadcrumb.components(separatedBy: " > ")
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: " > ")
    }

    private var iconName: String {
        if isLeafCrag {
            return "mountain.2.fill"
        } else if result.isCrag && result.hasChildren {
            return "mappin.circle.fill"
        } else {
            return "map.fill"
        }
    }

    private var iconColor: Color {
        if isLeafCrag {
            return statusColor
        } else if result.isCrag {
            return .climbSandstone
        } else {
            return .climbStone
        }
    }

    private var iconBackground: Color {
        if isLeafCrag {
            return statusColor.opacity(0.15)
        } else if result.isCrag {
            return Color.climbSandstone.opacity(0.15)
        } else {
            return Color.climbMist
        }
    }

    private var statusColor: Color {
        switch result.safetyStatus {
        case .safe: return .climbSafe
        case .caution: return .climbCaution
        case .unsafe: return .climbUnsafe
        case .unknown, .none: return .climbUnknown
        }
    }

    private var isSaved: Bool {
        cragStore.savedCrags.contains { $0.id == result.id }
    }
}

#Preview {
    AreaBrowserView()
        .environmentObject(CragStore())
}
