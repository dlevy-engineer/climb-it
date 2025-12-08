//
//  AlternateAdventureView.swift
//  CLIMB.it
//
//  Find alternative crags when your spot is wet
//

import SwiftUI

struct AlternateAdventureView: View {
    @EnvironmentObject var cragStore: CragStore
    @State private var safeCrags: [Crag] = []
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color.climbChalk.ignoresSafeArea()

            ScrollView {
                VStack(spacing: ClimbSpacing.lg) {
                    // Header
                    headerSection

                    // Content
                    if isLoading {
                        loadingState
                    } else if safeCrags.isEmpty {
                        emptyState
                    } else {
                        cragsList
                    }
                }
                .padding(.horizontal, ClimbSpacing.md)
                .padding(.bottom, ClimbSpacing.xxl)
            }
        }
        .navigationTitle("Alternatives")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSafeCrags()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: ClimbSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.climbSafe.opacity(0.15))
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(Color.climbSafe)
                    .frame(width: 72, height: 72)

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }

            VStack(spacing: ClimbSpacing.xs) {
                Text("Find Dry Rock")
                    .font(ClimbTypography.title2)
                    .foregroundColor(.climbGranite)

                Text("Crags with safe climbing conditions")
                    .font(ClimbTypography.body)
                    .foregroundColor(.climbStone)
            }
        }
        .padding(.vertical, ClimbSpacing.lg)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: ClimbSpacing.md) {
            ProgressView()
                .tint(.climbRope)

            Text("Finding safe crags...")
                .font(ClimbTypography.caption)
                .foregroundColor(.climbStone)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ClimbSpacing.xxl)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: ClimbSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.climbMist)
                    .frame(width: 80, height: 80)

                Image(systemName: "cloud.rain.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.climbStone)
            }

            Text("No Safe Crags Found")
                .font(ClimbTypography.title3)
                .foregroundColor(.climbGranite)

            Text("Looks like it's been wet everywhere.\nCheck back after a few dry days!")
                .font(ClimbTypography.body)
                .foregroundColor(.climbStone)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, ClimbSpacing.xxl)
    }

    // MARK: - Crags List

    private var cragsList: some View {
        VStack(spacing: ClimbSpacing.sm) {
            HStack {
                Text("\(safeCrags.count) safe crags")
                    .font(ClimbTypography.captionBold)
                    .foregroundColor(.climbStone)
                Spacer()
            }

            LazyVStack(spacing: ClimbSpacing.sm) {
                ForEach(safeCrags) { crag in
                    NavigationLink(destination: CragDetailView(crag: crag)) {
                        SafeCragCard(crag: crag)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - Load Safe Crags

    private func loadSafeCrags() async {
        isLoading = true
        let allCrags = await cragStore.fetchAllCrags()
        safeCrags = allCrags.filter { $0.safetyStatus == .safe }
        isLoading = false
    }
}

// MARK: - Safe Crag Card

struct SafeCragCard: View {
    let crag: Crag

    var body: some View {
        HStack(spacing: ClimbSpacing.md) {
            // Safe indicator
            ZStack {
                Circle()
                    .fill(Color.climbSafe.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.climbSafe)
            }

            // Content
            VStack(alignment: .leading, spacing: ClimbSpacing.xs) {
                Text(crag.name)
                    .font(ClimbTypography.bodyBold)
                    .foregroundColor(.climbGranite)
                    .lineLimit(1)

                Text(crag.location)
                    .font(ClimbTypography.caption)
                    .foregroundColor(.climbStone)
                    .lineLimit(1)

                if let precip = crag.precipitation, let days = precip.daysSinceRain {
                    HStack(spacing: 4) {
                        Image(systemName: "sun.max.fill")
                            .font(.caption2)
                            .foregroundColor(.climbSafe)
                        Text("\(days) days dry")
                            .font(ClimbTypography.micro)
                            .foregroundColor(.climbSafe)
                    }
                }
            }

            Spacer()

            // Arrow
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.climbStone)
        }
        .padding(ClimbSpacing.md)
        .background(Color.white)
        .cornerRadius(ClimbRadius.medium)
        .climbSubtleShadow()
    }
}

#Preview {
    NavigationStack {
        AlternateAdventureView()
            .environmentObject(CragStore())
    }
}
