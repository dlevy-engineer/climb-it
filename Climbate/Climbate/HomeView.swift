//
//  HomeView.swift
//  CLIMB.it
//
//  Main dashboard showing saved crags with weather status
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var cragStore: CragStore
    @State private var showingSearchView = false

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

                // Crag cards
                LazyVStack(spacing: ClimbSpacing.md) {
                    ForEach(cragStore.savedCrags) { crag in
                        NavigationLink(destination: CragDetailView(crag: crag)) {
                            CragCard(crag: crag)
                        }
                        .buttonStyle(PlainButtonStyle())
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
        }
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
    store.savedCrags = [.preview, .previewUnsafe]
    return HomeView()
        .environmentObject(store)
}

#Preview("Empty State") {
    HomeView()
        .environmentObject(CragStore())
}
