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

    private let apiClient = APIClient.shared

    /// Filter areas by search text (local filtering)
    var filteredAreas: [Area] {
        if searchText.isEmpty {
            return areas
        }
        let query = searchText.lowercased()
        return areas.filter { $0.name.lowercased().contains(query) }
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
                    if isLoading {
                        loadingState
                    } else if let error = error {
                        errorState(error)
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
        }
    }

    // MARK: - Components

    private var searchBar: some View {
        HStack(spacing: ClimbSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.climbStone)

            TextField("Filter areas...", text: $searchText)
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
            if area.isCrag {
                // This is a crag - go to detail view
                if let crag = area.toCrag(location: breadcrumb) {
                    CragDetailView(crag: crag)
                }
            } else {
                // This is a region - show children
                AreaChildrenView(area: area, breadcrumb: breadcrumb)
            }
        } label: {
            HStack(spacing: ClimbSpacing.md) {
                // Icon based on type
                ZStack {
                    Circle()
                        .fill(area.isCrag ? statusColor.opacity(0.15) : Color.climbMist)
                        .frame(width: 40, height: 40)

                    Image(systemName: area.isCrag ? "mountain.2.fill" : "folder.fill")
                        .font(.system(size: 16))
                        .foregroundColor(area.isCrag ? statusColor : .climbStone)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(area.name)
                        .font(ClimbTypography.bodyBold)
                        .foregroundColor(.climbGranite)
                        .lineLimit(1)

                    if area.isCrag {
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

                // Action button for crags, chevron for folders
                if area.isCrag {
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
                } else if children.isEmpty {
                    emptyState
                } else {
                    childrenList
                }
            }
        }
        .navigationTitle(area.name)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadChildren()
        }
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

#Preview {
    AreaBrowserView()
        .environmentObject(CragStore())
}
