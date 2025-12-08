//
//  ContentView.swift
//  CLIMB.it
//
//  Main tab navigation for the app
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var cragStore: CragStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "mountain.2.fill" : "mountain.2")
                    Text("My Crags")
                }
                .tag(0)

            DiscoverTab()
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "binoculars.fill" : "binoculars")
                    Text("Discover")
                }
                .tag(1)
        }
        .tint(.climbRope)
        .onAppear {
            configureTabBarAppearance()
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.white)

        // Selected state
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.climbRope)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(Color.climbRope),
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]

        // Normal state
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(Color.climbStone)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(Color.climbStone),
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Discover Tab (Search as a full tab)

struct DiscoverTab: View {
    @EnvironmentObject var cragStore: CragStore
    @State private var searchText: String = ""
    @State private var searchResults: [Crag] = []
    @State private var isLoading: Bool = false
    @State private var hasSearched: Bool = false
    @State private var showMap: Bool = false
    @State private var selectedFilter: SearchView.StatusFilter = .all

    var filteredResults: [Crag] {
        switch selectedFilter {
        case .all: return searchResults
        case .safe: return searchResults.filter { $0.safetyStatus == .safe }
        case .caution: return searchResults.filter { $0.safetyStatus == .caution }
        case .unsafe: return searchResults.filter { $0.safetyStatus == .unsafe }
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
                    } else if searchResults.isEmpty && hasSearched {
                        emptySearchState
                    } else if searchResults.isEmpty && !hasSearched {
                        initialState
                    } else if showMap {
                        mapView
                    } else {
                        resultsList
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ClimbLogo(size: .small)
                }
            }
            .task {
                if searchResults.isEmpty && !hasSearched {
                    await loadInitialCrags()
                }
            }
        }
    }

    // MARK: - Components (reusing patterns from SearchView)

    private var searchBar: some View {
        HStack(spacing: ClimbSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.climbStone)

            TextField("Search crags...", text: $searchText)
                .font(ClimbTypography.body)
                .autocorrectionDisabled()
                .onSubmit {
                    Task { await performSearch() }
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    Task { await loadInitialCrags() }
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

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ClimbSpacing.sm) {
                ForEach(SearchView.StatusFilter.allCases, id: \.self) { filter in
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

    private func chipColor(for filter: SearchView.StatusFilter) -> Color {
        switch filter {
        case .all: return .climbRope
        case .safe: return .climbSafe
        case .caution: return .climbCaution
        case .unsafe: return .climbUnsafe
        }
    }

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
            Image(systemName: isSelected ? icon + ".fill" : icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .climbStone)
                .frame(width: 36, height: 32)
                .background(isSelected ? Color.climbRope : Color.clear)
                .cornerRadius(ClimbRadius.small)
        }
    }

    private var loadingState: some View {
        VStack(spacing: ClimbSpacing.md) {
            Spacer()
            ProgressView()
                .tint(.climbRope)
            Text("Loading crags...")
                .font(ClimbTypography.caption)
                .foregroundColor(.climbStone)
            Spacer()
        }
    }

    private var initialState: some View {
        VStack(spacing: ClimbSpacing.md) {
            Spacer()

            Image(systemName: "binoculars.fill")
                .font(.system(size: 48))
                .foregroundColor(.climbSandstone)

            Text("Discover Crags")
                .font(ClimbTypography.title2)
                .foregroundColor(.climbGranite)

            Text("Search for climbing areas or browse\nall available locations")
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

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: ClimbSpacing.sm) {
                ForEach(filteredResults) { crag in
                    NavigationLink(destination: CragDetailView(crag: crag)) {
                        SearchResultRow(crag: crag)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, ClimbSpacing.md)
            .padding(.top, ClimbSpacing.sm)
            .padding(.bottom, ClimbSpacing.xxl)
        }
    }

    private var mapView: some View {
        CragMapView(crags: filteredResults)
            .cornerRadius(ClimbRadius.large)
            .padding(ClimbSpacing.md)
    }

    // MARK: - Actions

    private func loadInitialCrags() async {
        isLoading = true
        searchResults = await cragStore.fetchAllCrags()
        isLoading = false
    }

    private func performSearch() async {
        guard !searchText.isEmpty else {
            await loadInitialCrags()
            return
        }

        isLoading = true
        hasSearched = true
        searchResults = await cragStore.searchCrags(query: searchText)
        isLoading = false
    }
}

#Preview {
    ContentView()
        .environmentObject(CragStore())
}
