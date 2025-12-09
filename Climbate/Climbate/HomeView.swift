//
//  HomeView.swift
//  CLIMB.it
//
//  Main dashboard showing saved crags with weather status
//

import SwiftUI

// MARK: - Sort Order

enum CragSortOrder: String, CaseIterable {
    case status = "Status"
    case name = "Name"
    case location = "Location"

    var icon: String {
        switch self {
        case .status: return "circle.lefthalf.filled"
        case .name: return "textformat"
        case .location: return "mappin"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var cragStore: CragStore
    @State private var showingSearchView = false
    @AppStorage("cragSortOrder") private var sortOrder: CragSortOrder = .status

    // MARK: - Sorted Crags

    private var sortedCrags: [Crag] {
        switch sortOrder {
        case .status:
            // Safe first, then Caution, then Unsafe, then Unknown
            return cragStore.savedCrags.sorted { crag1, crag2 in
                let order: [Crag.SafetyStatus] = [.safe, .caution, .unsafe, .unknown]
                let index1 = order.firstIndex(of: crag1.safetyStatus) ?? order.count
                let index2 = order.firstIndex(of: crag2.safetyStatus) ?? order.count
                if index1 != index2 {
                    return index1 < index2
                }
                return crag1.name < crag2.name
            }
        case .name:
            return cragStore.savedCrags.sorted { $0.name < $1.name }
        case .location:
            return cragStore.savedCrags.sorted { $0.location < $1.location }
        }
    }

    /// Groups crags by state, sorted alphabetically by state name
    private var groupedCrags: [(state: String, crags: [Crag])] {
        let grouped = Dictionary(grouping: sortedCrags) { $0.state }
        return grouped.keys.sorted().map { state in
            (state: state, crags: grouped[state] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.climbChalk
                    .ignoresSafeArea()

                if cragStore.savedCrags.isEmpty {
                    emptyState
                } else {
                    cragDashboard
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        ForEach(CragSortOrder.allCases, id: \.self) { order in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    sortOrder = order
                                }
                            }) {
                                Label(order.rawValue, systemImage: order.icon)
                                if sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.subheadline)
                            Text(sortOrder.rawValue)
                                .font(ClimbTypography.caption)
                        }
                        .foregroundColor(.climbRope)
                    }
                }
                ToolbarItem(placement: .principal) {
                    ClimbLogo(size: .small)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSearchView.toggle() }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.climbRope)
                    }
                }
            }
            .sheet(isPresented: $showingSearchView) {
                SearchView()
            }
            .toolbarBackground(Color.climbChalk, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: ClimbSpacing.lg) {
            Spacer()

            // Hero illustration area
            ZStack {
                Circle()
                    .fill(Color.climbMist)
                    .frame(width: 160, height: 160)

                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.climbSandstone, .climbGranite],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: ClimbSpacing.sm) {
                Text("Your Crags")
                    .font(ClimbTypography.title1)
                    .foregroundColor(.climbGranite)

                Text("Save climbing areas to track conditions\nand know when it's safe to send")
                    .font(ClimbTypography.body)
                    .foregroundColor(.climbStone)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            ClimbButton("Find Crags", icon: "magnifyingglass") {
                showingSearchView.toggle()
            }
            .padding(.horizontal, ClimbSpacing.xxl)

            Spacer()

            ClimbTagline()
                .padding(.bottom, ClimbSpacing.lg)
        }
        .padding(ClimbSpacing.lg)
    }

    // MARK: - Crag Dashboard

    private var cragDashboard: some View {
        ScrollView {
            VStack(spacing: ClimbSpacing.lg) {
                // Status summary header
                statusSummary
                    .padding(.horizontal, ClimbSpacing.md)

                // Crag cards grouped by state
                LazyVStack(spacing: ClimbSpacing.lg, pinnedViews: .sectionHeaders) {
                    ForEach(groupedCrags, id: \.state) { group in
                        Section {
                            ForEach(group.crags) { crag in
                                NavigationLink(destination: CragDetailView(crag: crag)) {
                                    CragCard(crag: crag)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        } header: {
                            StateHeader(state: group.state, count: group.crags.count)
                        }
                    }
                }
                .padding(.horizontal, ClimbSpacing.md)
            }
            .padding(.top, ClimbSpacing.md)
            .padding(.bottom, ClimbSpacing.xxl)
        }
    }

    // MARK: - Status Summary

    private var statusSummary: some View {
        HStack(spacing: ClimbSpacing.sm) {
            statusPill(
                count: safeCrags.count,
                label: "Safe",
                color: .climbSafe
            )
            statusPill(
                count: cautionCrags.count,
                label: "Caution",
                color: .climbCaution
            )
            statusPill(
                count: unsafeCrags.count,
                label: "Unsafe",
                color: .climbUnsafe
            )
            if unknownCrags.count > 0 {
                statusPill(
                    count: unknownCrags.count,
                    label: "Unknown",
                    color: .climbUnknown
                )
            }
        }
    }

    private func statusPill(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(ClimbTypography.title2)
                .foregroundColor(color)
            Text(label)
                .font(ClimbTypography.micro)
                .foregroundColor(.climbStone)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ClimbSpacing.sm)
        .background(color.opacity(0.1))
        .cornerRadius(ClimbRadius.medium)
    }

    // MARK: - Computed Properties

    private var safeCrags: [Crag] {
        cragStore.savedCrags.filter { $0.safetyStatus == .safe }
    }

    private var cautionCrags: [Crag] {
        cragStore.savedCrags.filter { $0.safetyStatus == .caution }
    }

    private var unsafeCrags: [Crag] {
        cragStore.savedCrags.filter { $0.safetyStatus == .unsafe }
    }

    private var unknownCrags: [Crag] {
        cragStore.savedCrags.filter { $0.safetyStatus == .unknown }
    }
}

// MARK: - Crag Card

struct CragCard: View {
    let crag: Crag
    @EnvironmentObject var cragStore: CragStore

    var body: some View {
        HStack(spacing: ClimbSpacing.md) {
            // Status indicator bar
            RoundedRectangle(cornerRadius: 2)
                .fill(statusColor)
                .frame(width: 4)

            // Content
            VStack(alignment: .leading, spacing: ClimbSpacing.sm) {
                // Header row
                HStack {
                    Text(crag.name)
                        .font(ClimbTypography.title3)
                        .foregroundColor(.climbGranite)
                        .lineLimit(1)

                    Spacer()

                    ClimbStatusBadge(crag.safetyStatus, size: .small)
                }

                // Location
                Text(crag.location)
                    .font(ClimbTypography.caption)
                    .foregroundColor(.climbStone)
                    .lineLimit(1)

                // Weather info
                if let precip = crag.precipitation {
                    HStack(spacing: ClimbSpacing.lg) {
                        weatherStat(
                            icon: "drop.fill",
                            value: "\(String(format: "%.1f", precip.last7DaysMm))mm",
                            label: "7 days"
                        )

                        if let days = precip.daysSinceRain {
                            weatherStat(
                                icon: "calendar",
                                value: "\(days)",
                                label: days == 1 ? "day dry" : "days dry"
                            )
                        }
                    }
                    .padding(.top, ClimbSpacing.xs)
                }
            }

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.climbStone)
        }
        .padding(ClimbSpacing.md)
        .background(Color.white)
        .cornerRadius(ClimbRadius.large)
        .climbCardShadow()
    }

    private func weatherStat(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.climbRope)

            Text(value)
                .font(ClimbTypography.captionBold)
                .foregroundColor(.climbGranite)

            Text(label)
                .font(ClimbTypography.micro)
                .foregroundColor(.climbStone)
        }
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

// MARK: - State Header

struct StateHeader: View {
    let state: String
    let count: Int

    var body: some View {
        HStack {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.climbSandstone)

            Text(state)
                .font(ClimbTypography.title3)
                .foregroundColor(.climbGranite)

            Text("(\(count))")
                .font(ClimbTypography.caption)
                .foregroundColor(.climbStone)

            Spacer()
        }
        .padding(.vertical, ClimbSpacing.sm)
        .padding(.horizontal, ClimbSpacing.xs)
        .background(Color.climbChalk)
    }
}

// MARK: - Legacy Support (keeping old StatusBadge for compatibility)

struct StatusBadge: View {
    let status: Crag.SafetyStatus

    var body: some View {
        ClimbStatusBadge(status, size: .small)
    }
}

struct CragRowView: View {
    let crag: Crag

    var body: some View {
        CragCard(crag: crag)
    }
}

#Preview("With Crags") {
    let store = CragStore()
    store.savedCrags = [
        .preview,
        .previewUnsafe,
        Crag(name: "Bishop", location: "California > Eastern Sierra", safetyStatus: .safe),
        Crag(name: "Joshua Tree", location: "California > High Desert", safetyStatus: .caution)
    ]
    return HomeView()
        .environmentObject(store)
}

#Preview("Empty State") {
    HomeView()
        .environmentObject(CragStore())
}
